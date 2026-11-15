/// The shortcuts of the launcher icon of the Android app (a long press on the
/// icon): Search, Favourites and Ong Log. None elsewhere.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:quick_actions/quick_actions.dart';

import '../logger.dart';
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
  /// Calls [onShortcut] with each shortcut used from now on, and with the one the app was opened with, if any. The
  /// same shortcut may come twice for one use (the plugin reports the one the app was opened with twice): what it
  /// does must not depend on it.
  Future<void> listen(void Function(AppShortcut shortcut) onShortcut);

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
  Future<void> listen(void Function(AppShortcut shortcut) onShortcut) async {
    try {
      await _plugin.initialize((id) {
        final shortcut = AppShortcut.byId(id);
        if (shortcut != null) onShortcut(shortcut);
      });
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

class _LauncherShortcutsScopeState extends ConsumerState<LauncherShortcutsScope> {
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
    super.dispose();
  }

  void _open(AppShortcut shortcut) {
    if (!mounted) return;
    widget.navigatorKey.currentState?.popUntil((route) => route.isFirst);
    switch (shortcut) {
      case AppShortcut.search:
        ref.read(selectedTabProvider.notifier).select(AppTab.highlights);
        // once the tab is on the screen (its field cannot take the focus before), and the app in front: a shortcut
        // comes before the window of the app has the focus, and Android does not show a keyboard for it until then
        WidgetsBinding.instance.addPostFrameCallback((_) => _whenResumed(_focusSearch));
      case AppShortcut.favourites:
        FocusManager.instance.primaryFocus?.unfocus();
        ref.read(highlightFilterProvider.notifier).showFavourites(ref.read(favouritesProvider).isNotEmpty);
        ref.read(selectedTabProvider.notifier).select(AppTab.highlights);
      case AppShortcut.ongLog:
        FocusManager.instance.primaryFocus?.unfocus();
        ref.read(selectedTabProvider.notifier).select(AppTab.ongLog);
    }
  }

  /// Puts the cursor in the search field of the Highlights tab, with its keyboard.
  void _focusSearch() {
    if (!mounted) return;
    final field = ref.read(searchFocusProvider(AppTab.highlights));
    if (field.hasFocus) {
      // focused with its keyboard closed (the keyboard's own Back keeps the focus): only the keyboard is missing
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    } else {
      field.requestFocus();
    }
    // when the app starts on the shortcut, Android does not show the keyboard yet (the window of the app does not
    // have the focus yet, though Flutter says the app is in front): asked once more, if it did not come
    _keyboardAgain?.cancel();
    _keyboardAgain = Timer(keyboardRetryDelay, () {
      if (!mounted || !field.hasFocus || View.of(context).viewInsets.bottom > 0) return;
      SystemChannels.textInput.invokeMethod<void>('TextInput.show');
    });
  }

  AppLifecycleListener? _resumed;
  Timer? _keyboardAgain;

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
