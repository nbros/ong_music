/// The app root: themes, lifecycle refresh and the three-tab shell.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import '../web/web_platform.dart';
import 'about_page.dart';
import 'detail_pane.dart';
import 'highlights_page.dart';
import 'install_banner.dart';
import 'layout.dart';
import 'nav_rail.dart';
import 'ong_log_page.dart';
import 'theme.dart';
import 'view_state.dart';
import 'widgets.dart';

/// The widest the content is in a compact window, and the About tab in any
/// window: wider windows centre it.
const double maxContentWidth = 640;

/// The widest the column of a list tab is beside the navigation rail.
const double maxListColumnWidth = 720;

/// The widest the content right of the rail is in an expanded window (list
/// and detail pane, or About): wider windows centre it.
const double maxExpandedWidth = 1520;

/// The width of the list pane of an expanded window whose content (right of
/// the rail) is [width] wide.
double listPaneWidth(double width) => (0.4 * width).clamp(360, 520);

/// The three destinations, in the order of [AppTab].
const List<NavDestination> _destinations = [
  (icon: Icons.video_library, label: 'Highlights'),
  (icon: Icons.queue_music, label: 'Ong Log'),
  (icon: Icons.person, label: 'About'),
];

final _lightTheme = buildTheme(Brightness.light);
final _darkTheme = buildTheme(Brightness.dark);

// web only (null in the native apps, where the system setting reaches Flutter)
final bool? _browserUses24HourClock = browserUses24HourClock();

/// The app.
class OngMusicApp extends ConsumerStatefulWidget {
  const OngMusicApp({super.key});

  @override
  ConsumerState<OngMusicApp> createState() => _OngMusicAppState();
}

class _OngMusicAppState extends ConsumerState<OngMusicApp> {
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.read(catalogueProvider.notifier).refreshIfStale(),
      // the automatic refreshes of an app left open (desktop window, browser tab) stop in the background
      onStateChange: (state) => ref
          .read(catalogueProvider.notifier)
          .setForeground(state == AppLifecycleState.resumed || state == AppLifecycleState.inactive),
    );
    // already in the background at the start: no change of state will tell
    if (ref.read(startsInBackgroundProvider)) ref.read(catalogueProvider.notifier).setForeground(false);
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // start loading the catalogue at once, whatever the first tab
    ref.watch(catalogueProvider.select((s) => s.hasData));
    return MaterialApp(
      title: 'Ong Music',
      debugShowCheckedModeBanner: false,
      themeMode: ref.watch(themePreferenceProvider).themeMode,
      theme: _lightTheme,
      darkTheme: _darkTheme,
      builder: (context, child) => AppLayout(
        child: _browserUses24HourClock == true
            ? MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!)
            : child!,
      ),
      home: const AppShell(),
    );
  }
}

/// Whether the app starts in the background: a browser tab opened behind
/// another one (the web engine reports "resumed" until the page is first shown
/// and hidden again, so the page itself is asked), or a native app started
/// hidden. Overridden in tests.
final startsInBackgroundProvider = Provider<bool>((ref) {
  final state = WidgetsBinding.instance.lifecycleState;
  return state == AppLifecycleState.hidden || state == AppLifecycleState.paused || pageIsHidden();
});

/// The navigation (a bar at the bottom of a compact window, a rail on the
/// left of the others) and the three tabs, each one kept alive with its query,
/// filters and scroll position, whatever the window mode.
class AppShell extends ConsumerStatefulWidget {
  const AppShell({super.key});

  @override
  ConsumerState<AppShell> createState() => _AppShellState();
}

class _AppShellState extends ConsumerState<AppShell> {
  // Each page keeps its state (search field, scroll positions) wherever a mode change puts it.
  final _pages = {for (final tab in AppTab.values) tab: GlobalKey(debugLabel: tab.name)};

  void _select(int index) {
    FocusManager.instance.primaryFocus?.unfocus();
    ref.read(selectedTabProvider.notifier).select(AppTab.values[index]);
  }

  @override
  Widget build(BuildContext context) {
    final tab = ref.watch(selectedTabProvider);
    final mode = AppLayout.modeOf(context);
    final rail = mode.hasRail;
    final theme = Theme.of(context);
    // web: theme-color tags of index.html, color-scheme and page background in the app theme, which may
    // differ from the system one (no-op in the native apps)
    final dark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    WidgetsBinding.instance.addPostFrameCallback((_) => setBrowserTheme(background: surface, dark: dark));
    // Android back: a fiche stacked in the detail pane goes back to the one under it; then, from another tab,
    // back to Highlights before leaving the app (an open sheet is a route of its own and closes first)
    final stacked =
        mode == WindowMode.expanded &&
        tab != AppTab.about &&
        ref.watch(detailPaneProvider(tab).select((stack) => stack.length > 1));
    return PopScope(
      canPop: tab == AppTab.highlights && !stacked,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (stacked) {
          ref.read(detailPaneProvider(tab).notifier).pop();
        } else {
          ref.read(selectedTabProvider.notifier).select(AppTab.highlights);
        }
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // on web, the engine turns statusBarColor into the page's theme-color (Safari's bars, the iOS
        // status bar of the installed app): the app background there, transparent (edge to edge) elsewhere
        value: kIsWeb ? systemBarsStyle(theme).copyWith(statusBarColor: surface) : systemBarsStyle(theme),
        child: TypingInLowWindow(
          // read here: under the scaffold, the keyboard is no longer in the media query
          value:
              MediaQuery.viewInsetsOf(context).bottom > 0 &&
              MediaQuery.sizeOf(context).height < InstallBanner.minHeight,
          child: Scaffold(
            body: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (rail)
                  _Region(
                    // expanded: the rail, the list pane, the detail pane, in that order for the Tab key
                    enabled: mode == WindowMode.expanded,
                    child: AppNavigationRail(
                      destinations: _destinations,
                      selectedIndex: tab.index,
                      onDestinationSelected: _select,
                    ),
                  ),
                Expanded(
                  // the rail takes the safe area on the left (a camera cutout of a phone held sideways)
                  child: MediaQuery.removePadding(
                    context: context,
                    removeLeft: rail,
                    child: SafeArea(
                      bottom: false,
                      child: mode == WindowMode.expanded ? _expandedContent(tab) : _content(tab, rail),
                    ),
                  ),
                ),
              ],
            ),
            bottomNavigationBar: rail
                ? null
                : ColoredBox(
                    color: theme.colorScheme.surfaceContainer,
                    child: Center(
                      heightFactor: 1,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: maxContentWidth),
                        child: NavigationBar(
                          selectedIndex: tab.index,
                          onDestinationSelected: _select,
                          destinations: [
                            // no tooltip: it would only repeat the label under the icon
                            for (final d in _destinations)
                              NavigationDestination(icon: Icon(d.icon), label: d.label, tooltip: ''),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  /// The install banner over the tab on screen, each tab in its column.
  Widget _content(AppTab tab, bool rail) {
    final listWidth = rail ? maxListColumnWidth : maxContentWidth;
    return Column(
      children: [
        // as wide as the lists, whatever the tab: it does not change size when the tab changes
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: listWidth),
            child: const InstallBanner(),
          ),
        ),
        Expanded(
          child: _SearchShortcut(
            child: IndexedStack(
              index: tab.index,
              children: [
                for (final t in AppTab.values)
                  TickerMode(
                    enabled: t == tab,
                    child: _ContentColumn(
                      maxWidth: t == AppTab.about ? maxContentWidth : listWidth,
                      child: KeyedSubtree(
                        key: _pages[t],
                        child: switch (t) {
                          AppTab.highlights => const HighlightsPage(),
                          AppTab.ongLog => const OngLogPage(),
                          AppTab.about => const AboutPage(),
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// An expanded window: the install banner over the tab on screen, a list
  /// tab as a list pane and its detail pane, About across both; at most
  /// [maxExpandedWidth] wide, centred.
  Widget _expandedContent(AppTab tab) => LayoutBuilder(
    builder: (context, constraints) {
      final width = constraints.maxWidth < maxExpandedWidth ? constraints.maxWidth : maxExpandedWidth;
      final listWidth = listPaneWidth(constraints.maxWidth);
      return Center(
        child: SizedBox(
          width: width,
          child: Column(
            children: [
              const InstallBanner(),
              Expanded(
                child: _SearchShortcut(
                  child: IndexedStack(
                    index: tab.index,
                    sizing: StackFit.expand,
                    children: [
                      for (final t in AppTab.values)
                        TickerMode(
                          enabled: t == tab,
                          child: t == AppTab.about
                              ? KeyedSubtree(key: _pages[t], child: const AboutPage())
                              // the list first, then the pane: the order of screen readers and of the Tab key
                              : Row(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: listWidth,
                                      child: _Region(
                                        child: KeyedSubtree(
                                          key: _pages[t],
                                          child: t == AppTab.highlights ? const HighlightsPage() : const OngLogPage(),
                                        ),
                                      ),
                                    ),
                                    Expanded(
                                      child: _Region(child: DetailPane(tab: t)),
                                    ),
                                  ],
                                ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
}

/// A region of an expanded window (the rail, the list pane, the detail pane),
/// gone through as a whole by the Tab key and by screen readers: side by side,
/// they would otherwise be read row by row across the three.
class _Region extends StatelessWidget {
  const _Region({this.enabled = true, required this.child});

  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) =>
      enabled ? FocusTraversalGroup(child: Semantics(container: true, explicitChildNodes: true, child: child)) : child;
}

/// A column centred and at most [maxWidth] wide.
///
/// In a wider window, a mouse wheel turned in the empty space beside the
/// column scrolls what is at that height in it, as on a web page: without
/// this, the wheel would do nothing there.
class _ContentColumn extends StatefulWidget {
  const _ContentColumn({required this.maxWidth, required this.child});

  final double maxWidth;
  final Widget child;

  @override
  State<_ContentColumn> createState() => _ContentColumnState();
}

class _ContentColumnState extends State<_ContentColumn> {
  final _content = GlobalKey();

  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    final content = _content.currentContext?.findRenderObject();
    if (content is! RenderBox || !content.hasSize) return;
    final local = content.globalToLocal(event.position);
    if (local.dx >= 0 && local.dx < content.size.width) return;
    // the same event, as if the pointer were in the middle of the content at the same height
    final position = content.localToGlobal(Offset(content.size.width / 2, local.dy));
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, event.viewId);
    WidgetsBinding.instance.dispatchEvent((event.original ?? event).copyWith(position: position), result);
  }

  @override
  Widget build(BuildContext context) => Listener(
    // translucent: the listener hears the events of the empty space too
    behavior: HitTestBehavior.translucent,
    onPointerSignal: _onPointerSignal,
    child: Center(
      child: ConstrainedBox(
        key: _content,
        constraints: BoxConstraints(maxWidth: widget.maxWidth),
        child: widget.child,
      ),
    ),
  );
}

/// Ctrl+F (⌘F on Apple devices) or `/` puts the cursor in the search field of
/// the list on screen, as on most sites with a search field.
class _SearchShortcut extends ConsumerStatefulWidget {
  const _SearchShortcut({required this.child});

  final Widget child;

  @override
  ConsumerState<_SearchShortcut> createState() => _SearchShortcutState();
}

class _SearchShortcutState extends ConsumerState<_SearchShortcut> {
  @override
  void initState() {
    super.initState();
    // a key handler, not Shortcuts: those only hear keys while something below them has the focus
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || !mounted) return false;
    // not under a sheet or a dialog
    if (!(ModalRoute.of(context)?.isCurrent ?? true)) return false;
    final tab = ref.read(selectedTabProvider);
    if (tab == AppTab.about) return false;
    final keyboard = HardwareKeyboard.instance;
    final find =
        event.logicalKey == LogicalKeyboardKey.keyF &&
        (keyboard.isControlPressed || keyboard.isMetaPressed) &&
        !keyboard.isAltPressed &&
        !keyboard.isShiftPressed;
    // `/` is typed as text in a text field
    final slash = event.character == '/' && !isEditingText();
    if (!find && !slash) return false;
    ref.read(searchFocusProvider(tab)).requestFocus();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
