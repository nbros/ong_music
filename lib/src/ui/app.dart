/// The app root: themes, lifecycle refresh and the three-tab shell.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import '../web/web_platform.dart';
import 'about_page.dart';
import 'highlights_page.dart';
import 'install_banner.dart';
import 'ong_log_page.dart';
import 'theme.dart';
import 'view_state.dart';

/// Content wider than this is centred (desktop window, browser, tablet).
const double maxContentWidth = 640;

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
      builder: (context, child) => _browserUses24HourClock == true
          ? MediaQuery(data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child!)
          : child!,
      home: const AppShell(),
    );
  }
}

/// The navigation bar and the three tabs, each one kept alive with its query,
/// filters and scroll position.
class AppShell extends ConsumerWidget {
  const AppShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(selectedTabProvider);
    final theme = Theme.of(context);
    // web: theme-color tags of index.html, color-scheme and page background in the app theme, which may
    // differ from the system one (no-op in the native apps)
    final dark = theme.brightness == Brightness.dark;
    final surface = theme.colorScheme.surface;
    WidgetsBinding.instance.addPostFrameCallback((_) => setBrowserTheme(background: surface, dark: dark));
    // Android back: from another tab, go back to Highlights before leaving the app (an open sheet is a
    // route of its own and closes first)
    return PopScope(
      canPop: tab == AppTab.highlights,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(selectedTabProvider.notifier).select(AppTab.highlights);
      },
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        // on web, the engine turns statusBarColor into the page's theme-color (Safari's bars, the iOS
        // status bar of the installed app): the app background there, transparent (edge to edge) elsewhere
        value: kIsWeb ? systemBarsStyle(theme).copyWith(statusBarColor: surface) : systemBarsStyle(theme),
        child: Scaffold(
          body: SafeArea(
            bottom: false,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxContentWidth),
                child: Column(
                  children: [
                    const InstallBanner(),
                    Expanded(
                      child: IndexedStack(
                        index: tab.index,
                        children: [
                          for (final t in AppTab.values)
                            TickerMode(
                              enabled: t == tab,
                              child: switch (t) {
                                AppTab.highlights => const HighlightsPage(),
                                AppTab.ongLog => const OngLogPage(),
                                AppTab.about => const AboutPage(),
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          bottomNavigationBar: ColoredBox(
            color: theme.colorScheme.surfaceContainer,
            child: Center(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: maxContentWidth),
                child: NavigationBar(
                  selectedIndex: tab.index,
                  onDestinationSelected: (i) {
                    FocusManager.instance.primaryFocus?.unfocus();
                    ref.read(selectedTabProvider.notifier).select(AppTab.values[i]);
                  },
                  destinations: const [
                    NavigationDestination(icon: Icon(Icons.video_library), label: 'Highlights'),
                    NavigationDestination(icon: Icon(Icons.queue_music), label: 'Ong Log'),
                    NavigationDestination(icon: Icon(Icons.person), label: 'About'),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
