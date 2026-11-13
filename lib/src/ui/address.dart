/// The address of the web app: the tab and the search of the list tabs, in
/// the fragment of the page's address (`/#/log?q=zelda`), and the browser's
/// history.
///
/// A tab change is a step of the history; typing in a search field rewrites
/// the step on screen; Back and Forward go from step to step, restoring tab
/// and search; an address opened (a link, a bookmark, an address typed)
/// shows its tab and its search. The chip filters, the favourites and "You"
/// are not in it.
///
/// Whatever opens over the page (a detail sheet, a dialog, the licences
/// page) has a step of its own too, at the same address: Back closes it, and
/// the page stays as it was (phones, whose system Back is the browser's,
/// must never leave the site for a sheet). Closed any other way, it takes its
/// step back with it.
///
/// Built on Flutter's [Router] in every app, so that the native apps have the
/// same tree as the web one; only the web app reports to the browser (the
/// native apps have no address, and Android's back button still goes
/// through the shell's `PopScope`, see `app.dart`).
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../logger.dart';
import '../web/browser_history.dart';
import '../web/web_platform.dart';
import 'view_state.dart';

/// The history of the browser's tab: the web app only. Overridden in tests.
final browserHistoryProvider = Provider<BrowserHistory?>((ref) => browserHistory());

/// Whether the app has an address in a browser: the web app.
final browserAddressProvider = Provider<bool>((ref) => ref.watch(browserHistoryProvider) != null);

/// What the address said when the app started (the web app opened on
/// `/#/log?q=zelda` starts on the Ong Log searching "zelda"); Highlights in
/// the native apps. Read once, by the providers of the tab and the queries.
final initialAddressProvider = Provider<AppAddress>(
  (ref) => ref.watch(browserAddressProvider)
      ? AppAddress.parse(Uri.tryParse(WidgetsBinding.instance.platformDispatcher.defaultRouteName) ?? Uri(path: '/'))
      : AppAddress.home,
);

/// The longest query the address holds, in characters: a longer one (a
/// pasted text) is cut there. Browsers take far longer addresses, but a
/// query that long finds nothing anyway.
const int maxAddressQueryLength = 500;

/// How long the address waits after the last key typed in a search field
/// before it is rewritten: once per pause, not once per key (Safari refuses
/// more than 100 rewrites in a few seconds, and holding Backspace gets there).
const Duration addressReplaceDelay = Duration(milliseconds: 400);

/// How long the app waits for the browser to say it moved back as asked,
/// before it reads where the browser is and goes on.
const Duration historyMoveTimeout = Duration(seconds: 2);

/// Where the app is, as its address says it: a tab and, for the list tabs,
/// the query of its search field.
@immutable
class AppAddress {
  const AppAddress(this.tab, [String query = '']) : query = tab == AppTab.about ? '' : query;

  /// The Highlights tab without search.
  static const home = AppAddress(AppTab.highlights);

  final AppTab tab;

  /// The query of [tab]'s search field; always empty for About.
  final String query;

  static const _paths = {AppTab.highlights: '/', AppTab.ongLog: '/log', AppTab.about: '/about'};

  /// The address of [uri], the part of the page's address after `#`
  /// (`/log?q=zelda`): Highlights for anything it does not know.
  factory AppAddress.parse(Uri uri) {
    var path = uri.path;
    // a trailing slash, as some hand-written links have
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path.isEmpty) path = '/';
    for (final MapEntry(key: tab, value: p) in _paths.entries) {
      if (p == path) return AppAddress(tab, _query(uri));
    }
    return home;
  }

  /// The query of [uri]; none when it cannot be read: a link cut in the middle
  /// of a character (`%E0%A4`), an accent written the old way (`caf%E9`). The
  /// tab of such an address still opens.
  static String _query(Uri uri) {
    try {
      return uri.queryParameters['q'] ?? '';
    } on FormatException {
      return '';
    } on ArgumentError {
      return '';
    }
  }

  /// This address as the app reports it: `/`, `/?q=…`, `/log`, `/log?q=…`,
  /// `/about`. The query is percent-encoded (spaces as `+`), and cut at
  /// [maxAddressQueryLength] characters.
  Uri get uri {
    final q = _cut(query);
    return Uri(path: _paths[tab], queryParameters: q.isEmpty ? null : {'q': q});
  }

  static String _cut(String query) {
    final runes = query.runes;
    return runes.length <= maxAddressQueryLength ? query : String.fromCharCodes(runes.take(maxAddressQueryLength));
  }

  @override
  bool operator ==(Object other) => other is AppAddress && other.tab == tab && other.query == query;

  @override
  int get hashCode => Object.hash(tab, query);

  @override
  String toString() => 'AppAddress($uri)';
}

/// Reads and writes [AppAddress]es.
class AppAddressParser extends RouteInformationParser<AppAddress> {
  const AppAddressParser();

  @override
  Future<AppAddress> parseRouteInformation(RouteInformation routeInformation) =>
      SynchronousFuture(AppAddress.parse(routeInformation.uri));

  @override
  RouteInformation restoreRouteInformation(AppAddress configuration) => RouteInformation(uri: configuration.uri);
}

/// The address bar and the history of the browser, as the [Router] sees them,
/// kept in step with the app by one reconciler, one history move at a time.
///
/// What the browser should show:
/// - the step of the tab and the search: a new step when the tab changes or
///   a search is started from elsewhere ([markStep]), otherwise (typing) a
///   rewrite of the step on screen once the typing pauses ([replaceDelay]),
///   or before anything else is written;
/// - over it, one step per thing open over the page ([overlaysChanged]), at
///   the same address. When they close by their own means, the browser goes
///   back as many steps: none is left behind that would show nothing.
///
/// A history move is asynchronous: each write waits for the engine's answer,
/// each move back for the browser to say it got there, before the next one,
/// decided again from what the app shows then. A step reached by the
/// browser's own buttons is the user's: what is open above it closes
/// ([onBrowserNavigation]), the router is told, and a step that stands for
/// something no longer open (Forward onto it) is left at once.
///
/// Outside a browser ([history] null) nothing is reported.
class AddressBar extends RouteInformationProvider with WidgetsBindingObserver, ChangeNotifier {
  AddressBar({required this.history, required AppAddress initial, this.replaceDelay = addressReplaceDelay})
    : _value = RouteInformation(uri: initial.uri),
      _shown = Uri.parse(WidgetsBinding.instance.platformDispatcher.defaultRouteName),
      _over = history?.current.over ?? 0 {
    final history = this.history;
    if (history == null) return;
    // Back and Forward as a list of steps from the start (the engine keeps a single step and turns Back into
    // a "pop" of the app otherwise)
    SystemNavigator.selectMultiEntryHistory();
    // a reload on the step of a sheet: nothing is open any more
    if (_over > 0) _schedule();
  }

  final BrowserHistory? history;

  /// How long typing waits before the step on screen is rewritten.
  final Duration replaceDelay;

  /// Called when the browser goes to another step by itself (Back, Forward,
  /// an address typed in its bar), before the router is told: closes what is
  /// open over the page above the first `keep` things.
  void Function(int keep)? onBrowserNavigation;

  RouteInformation _value;

  // ---- what the browser shows (as last written or read)

  /// The address of the step on screen.
  Uri _shown;

  /// How many things open over the page the step on screen stands for.
  int _over;

  // ---- what the app shows, not written yet

  /// How many things are open over the page.
  int _open = 0;

  /// An address to give a step of its own.
  Uri? _step;

  /// An address typed, to rewrite the step of the tab with.
  Uri? _typed;
  bool _typingPaused = false;
  Timer? _typingTimer;

  /// The next address is a step of its own, even on the same tab.
  bool _stepMarked = false;

  // ---- the reconciler

  bool _scheduled = false;
  bool _running = false;
  bool _disposed = false;

  /// The move back the app asked the browser for: where it goes.
  ({int target, Completer<void> done, Timer timeout})? _move;

  @override
  RouteInformation get value => _value;

  /// Makes the next address a step of the history even when the tab stays:
  /// a search started from a link ("Requested by …" on the Ong Log).
  void markStep() => _stepMarked = true;

  /// [count] things are now open over the page.
  void overlaysChanged(int count) {
    _open = count;
    _schedule();
  }

  @override
  void routerReportsNewRouteInformation(
    RouteInformation routeInformation, {
    RouteInformationReportingType type = RouteInformationReportingType.none,
  }) {
    _value = routeInformation;
    final marked = _stepMarked;
    _stepMarked = false;
    if (history == null) return;
    final uri = routeInformation.uri;
    final step = _step;
    if (marked || AppAddress.parse(uri).tab != AppAddress.parse(step ?? _shown).tab) {
      // what was typed on the tab left is written first, in its own step
      _step = uri == _shown ? null : uri;
    } else if (step != null) {
      // typed on the tab of a step not written yet: that step has it
      _step = uri;
    } else if (uri == _shown) {
      // typed, then typed back
      _clearTyping();
    } else {
      _typed = uri;
      _typingPaused = false;
      _typingTimer?.cancel();
      _typingTimer = Timer(replaceDelay, () {
        _typingPaused = true;
        _schedule();
      });
    }
    _schedule();
  }

  void _clearTyping() {
    _typingTimer?.cancel();
    _typingTimer = null;
    _typed = null;
    _typingPaused = false;
  }

  void _schedule() {
    if (history == null || _scheduled || _disposed) return;
    _scheduled = true;
    // after the current event: the routes popped and pushed together (a sheet replaced) count as one change
    scheduleMicrotask(() {
      _scheduled = false;
      _run();
    });
  }

  Future<void> _run() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      for (var action = _next(); action != null && !_disposed; action = _next()) {
        await action;
      }
    } finally {
      _running = false;
    }
  }

  /// The next thing to do to bring the browser in step with the app, or null
  /// when it is.
  Future<void>? _next() {
    // a step that stands for something closed: back to the one under it
    if (_over > _open) return _go(_open - _over);
    if (_over == 0) {
      final typed = _typed;
      if (typed != null && (_typingPaused || _step != null || _open > 0)) {
        _clearTyping();
        if (typed != _shown) return _write(typed, replace: true, over: 0);
      }
      final step = _step;
      if (step != null) {
        _step = null;
        if (step != _shown) return _write(step, replace: false, over: 0);
      }
    }
    // something opened over the page: its step, at the same address
    if (_over < _open) return _write(_shown, replace: false, over: _over + 1);
    return null;
  }

  Future<void> _write(Uri uri, {required bool replace, required int over}) async {
    _shown = uri;
    _over = over;
    try {
      await SystemNavigator.selectMultiEntryHistory();
      await SystemNavigator.routeInformationUpdated(
        uri: uri,
        state: over == 0 ? null : {'over': over},
        replace: replace,
      );
    } catch (e) {
      logger.w('Cannot write the address', error: e);
    }
  }

  Future<void> _go(int delta) {
    final history = this.history!;
    final done = Completer<void>();
    final target = history.current.position + delta;
    _move = (
      target: target,
      done: done,
      timeout: Timer(historyMoveTimeout, () {
        // the browser said nothing: where is it?
        _move = null;
        _over = history.current.over;
        if (!done.isCompleted) done.complete();
      }),
    );
    history.go(delta);
    return done.future;
  }

  void _endMove() {
    final move = _move;
    if (move == null) return;
    _move = null;
    move.timeout.cancel();
    if (!move.done.isCompleted) move.done.complete();
  }

  @override
  Future<bool> didPushRouteInformation(RouteInformation routeInformation) async {
    final history = this.history;
    final over = overOfState(routeInformation.state);
    final move = _move;
    if (history != null && move != null && history.current.position == move.target) {
      // where the app asked the browser to go
      _shown = routeInformation.uri;
      _over = over;
      _endMove();
      return true;
    }
    // the user's: Back, Forward, an address typed. What the app had not written yet is for a step left behind.
    _endMove();
    _clearTyping();
    _step = null;
    _stepMarked = false;
    _shown = routeInformation.uri;
    _over = over;
    onBrowserNavigation?.call(over);
    _value = routeInformation;
    notifyListeners();
    _schedule();
    return true;
  }

  @override
  void addListener(VoidCallback listener) {
    if (!hasListeners) WidgetsBinding.instance.addObserver(this);
    super.addListener(listener);
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) WidgetsBinding.instance.removeObserver(this);
  }

  @override
  void dispose() {
    _disposed = true;
    _clearTyping();
    _endMove();
    if (hasListeners) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}

/// Follows what the navigator opens over the app's page: the routes above it.
class _OverPageObserver extends NavigatorObserver {
  _OverPageObserver(this.onChanged);

  final void Function(List<Route<dynamic>> routes) onChanged;

  /// The routes over the page, the top one last (none being popped).
  final routes = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route.isFirst) return;
    routes.add(route);
    onChanged(routes);
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (routes.remove(route)) onChanged(routes);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (routes.remove(route)) onChanged(routes);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    final index = oldRoute == null ? -1 : routes.indexOf(oldRoute);
    if (index < 0 || newRoute == null) return;
    routes[index] = newRoute;
    onChanged(routes);
  }
}

/// Builds the app's single page, [shell], under the navigator of the sheets,
/// dialogs and the licences page, and keeps the [AppAddress] and the state of
/// the app in step: the tab, the query of the list tab on screen, and what is
/// open over the page.
class AppRouterDelegate extends RouterDelegate<AppAddress>
    with ChangeNotifier, PopNavigatorRouterDelegateMixin<AppAddress> {
  AppRouterDelegate({required this.ref, required this.bar, required Widget shell}) {
    _page = MaterialPage<void>(key: const ValueKey('shell'), child: shell);
    _overPage = _OverPageObserver((routes) => bar.overlaysChanged(routes.length));
    // one navigator for the app's lifetime: rebuilding the router (each key typed) does not rebuild it
    _navigator = Navigator(key: navigatorKey, pages: [_page], observers: [_overPage], onDidRemovePage: (_) {});
    _subscriptions = [
      ref.listenManual(selectedTabProvider, (_, _) => _changed()),
      ref.listenManual(highlightFilterProvider.select((f) => f.query), (_, _) => _changed()),
      ref.listenManual(playFilterProvider.select((f) => f.query), (_, _) => _changed()),
      // reported even when nothing changes (the same search again): the mark must not wait for the next key typed
      ref.listenManual(searchStepsProvider, (_, _) {
        bar.markStep();
        _changed();
      }),
    ];
    bar.onBrowserNavigation = _closeOverPage;
  }

  final WidgetRef ref;
  final AddressBar bar;
  late final Page<void> _page;
  late final _OverPageObserver _overPage;
  late final Widget _navigator;
  late final List<ProviderSubscription<Object?>> _subscriptions;

  @override
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey(debugLabel: 'app');

  @override
  AppAddress get currentConfiguration {
    final tab = ref.read(selectedTabProvider);
    return AppAddress(tab, switch (tab) {
      AppTab.highlights => ref.read(highlightFilterProvider).query,
      AppTab.ongLog => ref.read(playFilterProvider).query,
      AppTab.about => '',
    });
  }

  void _changed() => notifyListeners();

  /// Closes what is open over the page above the first [keep] things: the
  /// browser went to a step that stands for no more.
  void _closeOverPage(int keep) {
    final navigator = navigatorKey.currentState;
    if (navigator == null) return;
    final open = _overPage.routes.length;
    if (open == keep + 1) {
      // One step back: as the system's back button does, so that a page with pages of its own goes back inside
      // first (the text of a licence, back to the list of the licences page). It then stays open, and gets a
      // step again.
      unawaited(navigator.maybePop());
      return;
    }
    // each pop takes its route out of the list at once
    for (var left = open; left > keep && _overPage.routes.length == left; left--) {
      navigator.pop();
    }
  }

  @override
  Future<void> setInitialRoutePath(AppAddress configuration) {
    // already where the address says: the providers start there (initialAddressProvider), and they cannot be
    // changed while the tree builds
    return SynchronousFuture(null);
  }

  @override
  Future<void> setNewRoutePath(AppAddress configuration) {
    if (configuration == currentConfiguration) return SynchronousFuture(null);
    // the query first: the tab change then shows the list with it
    switch (configuration.tab) {
      case AppTab.highlights:
        final notifier = ref.read(highlightFilterProvider.notifier);
        if (ref.read(highlightFilterProvider).query != configuration.query) notifier.setQuery(configuration.query);
      case AppTab.ongLog:
        final notifier = ref.read(playFilterProvider.notifier);
        if (ref.read(playFilterProvider).query != configuration.query) notifier.setQuery(configuration.query);
      case AppTab.about:
    }
    if (ref.read(selectedTabProvider) != configuration.tab) {
      FocusManager.instance.primaryFocus?.unfocus();
      ref.read(selectedTabProvider.notifier).select(configuration.tab);
    }
    return SynchronousFuture(null);
  }

  @override
  Widget build(BuildContext context) => _navigator;

  @override
  void dispose() {
    for (final s in _subscriptions) {
      s.close();
    }
    bar.onBrowserNavigation = null;
    super.dispose();
  }
}
