/// The shortcuts of the launcher icon of the Android app (a long press on the
/// icon): Search, Favourites and Ong Log. None elsewhere.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quick_actions/quick_actions.dart';

import '../logger.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import 'view_state.dart';

/// A shortcut of the launcher icon: its [id] for the system, its [label] in
/// the launcher's menu, and its [icon], a drawable of the Android app
/// (`android/app/src/main/res`).
enum AppShortcut {
  search(id: 'search', label: 'Search', icon: 'ic_shortcut_search'),
  favourites(id: 'favourites', label: 'Favourites', icon: 'ic_shortcut_favourites'),
  ongLog(id: 'ong_log', label: 'Ong Log', icon: 'ic_shortcut_ong_log');

  const AppShortcut({required this.id, required this.label, required this.icon});

  final String id;
  final String label;
  final String icon;

  /// The shortcut of [id], or null (one from an older version of the app, still pinned on a home screen).
  static AppShortcut? byId(String id) {
    for (final s in values) {
      if (s.id == id) return s;
    }
    return null;
  }
}

/// How long after the Search shortcut put the cursor in the search field its keyboard is asked for again, if it did
/// not come.
const Duration keyboardRetryDelay = Duration(milliseconds: 800);

/// The shortcuts the launcher shows: Favourites only while the user has some.
List<AppShortcut> offeredShortcuts({required bool hasFavourites}) => [
  AppShortcut.search,
  if (hasFavourites) AppShortcut.favourites,
  AppShortcut.ongLog,
];

/// What the system knows of the shortcuts.
abstract interface class LauncherShortcuts {
  /// Calls [onShortcut] with each shortcut used from now on, and with the one the app was opened with, if any
  /// ([launch] true for that one). The same shortcut may come twice for one use (the plugin reports the one the app
  /// was opened with twice): what it does must not depend on it.
  Future<void> listen(void Function(AppShortcut shortcut, {required bool launch}) onShortcut);

  /// Shows [shortcuts] in the launcher's menu, in that order.
  Future<void> offer(List<AppShortcut> shortcuts);
}

/// The shortcuts of the Android app; null elsewhere (the web app, Windows), which have none. Overridden in tests.
final launcherShortcutsProvider = Provider<LauncherShortcuts?>(
  (ref) => !kIsWeb && defaultTargetPlatform == TargetPlatform.android ? _QuickActions() : null,
);

/// The dynamic shortcuts of Android, through the quick_actions plugin.
class _QuickActions implements LauncherShortcuts {
  final _plugin = const QuickActions();

  @override
  Future<void> listen(void Function(AppShortcut shortcut, {required bool launch}) onShortcut) async {
    // what comes before the plugin is ready is the shortcut the app was opened with (both times it reports it)
    var starting = true;
    try {
      await _plugin.initialize((id) {
        final shortcut = AppShortcut.byId(id);
        if (shortcut != null) onShortcut(shortcut, launch: starting);
      });
      starting = false;
    } catch (e) {
      logger.w('Cannot listen to the launcher shortcuts', error: e);
    }
  }

  @override
  Future<void> offer(List<AppShortcut> shortcuts) async {
    try {
      await _plugin.setShortcutItems([
        for (final s in shortcuts) ShortcutItem(type: s.id, localizedTitle: s.label, icon: s.icon),
      ]);
    } catch (e) {
      logger.w('Cannot set the launcher shortcuts', error: e);
    }
  }
}

/// Offers the shortcuts of the launcher icon while it is built (Favourites
/// while there are favourites), and opens what a shortcut leads to: the
/// Highlights tab with its search field focused (and the keyboard up), the
/// Highlights tab on the favourites, the Ong Log tab. What is open over the
/// lists (a sheet, a dialog, the licences page) closes first: it would hide
/// where the shortcut leads.
class LauncherShortcutsScope extends ConsumerStatefulWidget {
  const LauncherShortcutsScope({super.key, required this.navigatorKey, required this.child});

  /// The navigator of the app's page and of what opens over it.
  final GlobalKey<NavigatorState> navigatorKey;
  final Widget child;

  @override
  ConsumerState<LauncherShortcutsScope> createState() => _LauncherShortcutsScopeState();
}

class _LauncherShortcutsScopeState extends ConsumerState<LauncherShortcutsScope> with WidgetsBindingObserver {
  ProviderSubscription<bool>? _favourites;

  @override
  void initState() {
    super.initState();
    final shortcuts = ref.read(launcherShortcutsProvider);
    if (shortcuts == null) return;
    _favourites = ref.listenManual(
      favouritesProvider.select((keys) => keys.isNotEmpty),
      (_, hasFavourites) => unawaited(shortcuts.offer(offeredShortcuts(hasFavourites: hasFavourites))),
      fireImmediately: true,
    );
    // what the user does after the Search shortcut, before its field could take the focus or before its keyboard is
    // asked for again, wins over it
    _tab = ref.listenManual(selectedTabProvider, (_, tab) {
      if (tab != AppTab.highlights) _userActed();
    });
    _listening = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_onPointer);
    HardwareKeyboard.instance.addHandler(_onKey);
    WidgetsBinding.instance.addObserver(this);
    // after the first frame: the shortcut the app was opened with changes the tab and the filters, which cannot change
    // while the app builds
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(shortcuts.listen(_open));
    });
  }

  @override
  void dispose() {
    _resumed?.dispose();
    _keyboardAgain?.cancel();
    _favourites?.close();
    _tab?.close();
    _catalogue?.close();
    if (_listening) {
      GestureBinding.instance.pointerRouter.removeGlobalRoute(_onPointer);
      HardwareKeyboard.instance.removeHandler(_onKey);
      WidgetsBinding.instance.removeObserver(this);
    }
    super.dispose();
  }

  ProviderSubscription<AppTab>? _tab;

  /// Whether it follows the pointer, the keys and the size of the window (the Android app only).
  bool _listening = false;

  /// The Search shortcut waiting for its field (the list not on the screen yet: the catalogue is not there), and
  /// whether it came while the app was starting or in the background.
  ({bool cold})? _search;
  ProviderSubscription<bool>? _catalogue;

  /// Asks for the keyboard of the search field once more, if it did not come (a shortcut the app started on).
  Timer? _keyboardAgain;

  /// Whether the keyboard came up since the cursor was put in the field: closed since, it was the user.
  bool _keyboardCame = false;

  void _onPointer(PointerEvent event) {
    if (event is PointerDownEvent) _userActed();
  }

  bool _onKey(KeyEvent event) {
    if (event is KeyDownEvent) _userActed();
    return false;
  }

  @override
  void didChangeMetrics() {
    if (_keyboardAgain == null || !mounted) return;
    if (View.of(context).viewInsets.bottom > 0) _keyboardCame = true;
  }

  /// The user did something: the Search shortcut gives up what it was still waiting for.
  void _userActed() {
    _search = null;
    _catalogue?.close();
    _catalogue = null;
    _keyboardAgain?.cancel();
    _keyboardAgain = null;
  }

  void _open(AppShortcut shortcut, {required bool launch}) {
    if (!mounted) return;
    _userActed();
    widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    switch (shortcut) {
      case AppShortcut.search:
        // the app starting on the shortcut, or coming back from the background for it: its window may not have the
        // focus yet when the field takes it, and Android shows no keyboard until then
        final request = (cold: launch || WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed);
        _search = request;
        // a search among every highlight: a chip left on (a genre, "You", the favourites, "New") would narrow it
        // without a word on the screen the shortcut opens; what is already typed stays
        ref.read(highlightFilterProvider.notifier).clearChips();
        ref.read(selectedTabProvider.notifier).select(AppTab.highlights);
        // once the tab is on the screen (its field cannot take the focus before), and the app in front
        WidgetsBinding.instance.addPostFrameCallback((_) => _whenResumed(() => _focusSearch(request)));
      case AppShortcut.favourites:
        FocusManager.instance.primaryFocus?.unfocus();
        ref.read(highlightFilterProvider.notifier).showFavourites(ref.read(favouritesProvider).isNotEmpty);
        ref.read(selectedTabProvider.notifier).select(AppTab.highlights);
      case AppShortcut.ongLog:
        FocusManager.instance.primaryFocus?.unfocus();
        ref.read(selectedTabProvider.notifier).select(AppTab.ongLog);
    }
  }

  /// Puts the cursor in the search field of the Highlights tab, with its keyboard, for [request] if it still waits.
  ///
  /// Without catalogue, the tab shows its status instead of its list, and has no field: the cursor goes there once,
  /// when the list first comes, if the user did nothing meanwhile (a focus asked for the missing field would come
  /// whenever it appears, much later, the keyboard with it).
  void _focusSearch(({bool cold}) request) {
    if (!mounted || !identical(_search, request)) return;
    final field = ref.read(searchFocusProvider(AppTab.highlights));
    if (field.context == null) {
      _catalogue ??= ref.listenManual(currentCatalogueProvider.select((c) => c != null), (_, there) {
        if (!there) return;
        _catalogue?.close();
        _catalogue = null;
        // the list is built in the next frame
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !identical(_search, request)) return;
          if (ref.read(selectedTabProvider) != AppTab.highlights ||
              ref.read(searchFocusProvider(AppTab.highlights)).context == null) {
            _search = null;
            return;
          }
          _focusSearch(request);
        });
      });
      return;
    }
    _search = null;
    if (field.hasFocus) {
      // focused with its keyboard closed (the keyboard's own Back keeps the focus): only the keyboard is missing
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      field.requestFocus();
    }
    if (!request.cold) return;
    // when the app starts on the shortcut, Android does not show the keyboard yet (the window of the app does not
    // have the focus yet, though Flutter says the app is in front): asked once more, if it did not come, and if the
    // user did nothing meanwhile (closing the keyboard among it)
    _keyboardCame = false;
    _keyboardAgain = Timer(keyboardRetryDelay, () {
      _keyboardAgain = null;
      if (!mounted || !field.hasFocus || _keyboardCame || View.of(context).viewInsets.bottom > 0) return;
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  AppLifecycleListener? _resumed;

  /// Calls [action] now if the app is in front, else as soon as it is (the last one asked only).
  void _whenResumed(VoidCallback action) {
    _resumed?.dispose();
    _resumed = null;
    if (!mounted) return;
    if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) return action();
    _resumed = AppLifecycleListener(
      onResume: () {
        _resumed?.dispose();
        _resumed = null;
        action();
      },
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
