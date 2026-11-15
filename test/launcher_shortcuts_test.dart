// The shortcuts of the launcher icon of the Android app (a long press on the icon): Search, Favourites, Ong Log.
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/launcher_shortcuts.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';

import 'ui_harness.dart';

/// The preferences of a user whose favourite is "Song of Storms".
Map<String, Object> _aFavourite() => {
  FavouritesNotifier.key: [testCatalogue().highlights.firstWhere((h) => h.track == 'Song of Storms').key],
};

List<String> _tracks(WidgetTester tester) =>
    tester.widgetList<HighlightRow>(find.byType(HighlightRow)).map((r) => r.highlight.track).toList();

/// The search field of the Highlights tab.
TextField _highlightsField(WidgetTester tester) =>
    tester.widget<TextField>(find.descendant(of: find.byType(HighlightsPage), matching: find.byType(TextField)));

/// The app in front, as on a phone (a test starts without a lifecycle state).
void _inFront(WidgetTester tester) => tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);

/// How many times the app asked for the keyboard.
int _keyboardRequests(WidgetTester tester) =>
    tester.testTextInput.log.where((call) => call.method == 'TextInput.show').length;

void main() {
  testWidgets('only the Android app has shortcuts', (tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(launcherShortcutsProvider), isNotNull, reason: 'Android');
    for (final platform in [TargetPlatform.windows, TargetPlatform.iOS, TargetPlatform.macOS, TargetPlatform.linux]) {
      debugDefaultTargetPlatformOverride = platform;
      try {
        expect(ProviderContainer().read(launcherShortcutsProvider), isNull, reason: '$platform');
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    }
  });

  testWidgets('the launcher shows Search and Ong Log, and Favourites while there are favourites', (tester) async {
    final shortcuts = FakeLauncherShortcuts();
    await pumpApp(tester, shortcuts: shortcuts);
    expect(shortcuts.offered, [
      [AppShortcut.search, AppShortcut.ongLog],
    ]);
    expect([for (final s in AppShortcut.values) s.label], ['Search', 'Favourites', 'Ong Log']);

    final row = find.ancestor(of: find.text('Song of Storms'), matching: find.byType(HighlightRow));
    await tester.tap(find.descendant(of: row, matching: detailsButtons()));
    await tester.pumpAndSettle();
    final star = find.descendant(of: find.byType(HighlightSheet), matching: find.byIcon(Icons.star_border));
    await tester.tap(star);
    await tester.pumpAndSettle();
    expect(shortcuts.offered.last, [AppShortcut.search, AppShortcut.favourites, AppShortcut.ongLog]);
    await tester.tap(find.descendant(of: find.byType(HighlightSheet), matching: find.byIcon(Icons.star)));
    await tester.pumpAndSettle();
    expect(shortcuts.offered.last, [AppShortcut.search, AppShortcut.ongLog]);
    expect(shortcuts.offered, hasLength(3), reason: 'once per change, not at each build');
  });

  group('Search', () {
    testWidgets('closes the sheet over the Ong Log, shows Highlights with the cursor in its field', (tester) async {
      _inFront(tester);
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      expect(find.byType(StreamSheet), findsOneWidget);

      shortcuts.use(AppShortcut.search);
      await tester.pumpAndSettle();
      expect(find.byType(StreamSheet), findsNothing);
      expect(selectedTab(tester), 0);
      expect(_highlightsField(tester).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue, reason: 'the keyboard up');
    });

    testWidgets('searches among every highlight: the chips left on go, what is typed stays', (tester) async {
      _inFront(tester);
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts, prefs: _aFavourite());
      await tester.enterText(searchField(), 'o');
      await tester.pumpAndSettle();
      final typed = _tracks(tester);
      await tester.tap(chip('Favourites'));
      await tester.pumpAndSettle();
      expect(_tracks(tester), isNot(typed));
      await goToTab(tester, 'Ong Log');

      shortcuts.use(AppShortcut.search);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(tester.widget<FilterChip>(chip('Favourites')).selected, isFalse);
      expect(_tracks(tester), typed);
      expect(_highlightsField(tester).controller!.text, 'o');
    });

    testWidgets('a field focused with its keyboard closed gets its keyboard back', (tester) async {
      _inFront(tester);
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts);
      await tester.tap(searchField());
      await tester.pumpAndSettle();
      // the keyboard's own Back closed it, the field keeping the focus: the app hears nothing of it
      tester.testTextInput.log.clear();
      const before = 0;

      shortcuts.use(AppShortcut.search);
      await tester.pumpAndSettle();
      expect(_highlightsField(tester).focusNode!.hasFocus, isTrue);
      expect(_keyboardRequests(tester), greaterThan(before));
    });

    testWidgets('waits for the app to be in front before asking for the keyboard', (tester) async {
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts);
      shortcuts.use(AppShortcut.search);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(_highlightsField(tester).focusNode!.hasFocus, isFalse, reason: 'Android would not show its keyboard');

      // on its way to the front, the app draws again before it has the focus of the window (inactive)
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pumpAndSettle();
      expect(_highlightsField(tester).focusNode!.hasFocus, isFalse);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(_highlightsField(tester).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('a start on the shortcut: asks for the keyboard once more when it did not come', (tester) async {
      _inFront(tester);
      await pumpApp(tester, shortcuts: FakeLauncherShortcuts(launch: AppShortcut.search));
      expect(_highlightsField(tester).focusNode!.hasFocus, isTrue);
      final asked = _keyboardRequests(tester);
      expect(asked, greaterThan(0));
      // Android ignored it (the app's window did not have the focus yet): no keyboard in the window
      await tester.pump(keyboardRetryDelay);
      expect(_keyboardRequests(tester), asked + 1);
      await tester.pump(keyboardRetryDelay * 2);
      expect(_keyboardRequests(tester), asked + 1, reason: 'once');
    });

    testWidgets('a start on the shortcut, the keyboard up: not asked again', (tester) async {
      _inFront(tester);
      await pumpApp(tester, shortcuts: FakeLauncherShortcuts(launch: AppShortcut.search));
      final asked = _keyboardRequests(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump(keyboardRetryDelay);
      expect(_keyboardRequests(tester), asked);
    });

    testWidgets('a start on the shortcut, the keyboard closed by the user meanwhile: not opened again', (tester) async {
      _inFront(tester);
      await pumpApp(tester, shortcuts: FakeLauncherShortcuts(launch: AppShortcut.search));
      final asked = _keyboardRequests(tester);
      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      await tester.pump(const Duration(milliseconds: 200));
      // the keyboard's own Back: the app only sees the room it took come back
      tester.view.viewInsets = FakeViewPadding.zero;
      await tester.pump(keyboardRetryDelay);
      expect(_keyboardRequests(tester), asked);
    });

    testWidgets('a start on the shortcut, the user doing something else meanwhile: not asked again', (tester) async {
      _inFront(tester);
      await pumpApp(tester, shortcuts: FakeLauncherShortcuts(launch: AppShortcut.search));
      final asked = _keyboardRequests(tester);
      // a finger on the list (a scroll begins)
      final finger = await tester.startGesture(tester.getCenter(find.byType(HighlightRow).first));
      await finger.moveBy(const Offset(0, -40));
      await tester.pump(keyboardRetryDelay);
      await finger.up();
      expect(_keyboardRequests(tester), asked);
    });

    testWidgets('the app already in front: asked once, not again', (tester) async {
      _inFront(tester);
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts);
      shortcuts.use(AppShortcut.search);
      await tester.pumpAndSettle();
      expect(_highlightsField(tester).focusNode!.hasFocus, isTrue);
      final asked = _keyboardRequests(tester);
      // no keyboard in the window: a keyboard of its own (a computer), or the user closed it already
      await tester.pump(keyboardRetryDelay * 2);
      expect(_keyboardRequests(tester), asked);
    });

    testWidgets('before the catalogue: the cursor in the field when the list comes, if the user waited', (
      tester,
    ) async {
      _inFront(tester);
      final shortcuts = FakeLauncherShortcuts(launch: AppShortcut.search);
      // (the status view animates: frames one by one)
      final app = await pumpApp(tester, shortcuts: shortcuts, state: const CatalogueState(), settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(HighlightRow), findsNothing);
      expect(_keyboardRequests(tester), 0, reason: 'no field yet');
      app.notifier.emit(loadedState(testCatalogue(), testNow));
      await tester.pumpAndSettle();
      expect(_highlightsField(tester).focusNode!.hasFocus, isTrue);
      expect(tester.testTextInput.isVisible, isTrue);
    });

    testWidgets('before the catalogue, then the Ong Log: the field never takes the focus later', (tester) async {
      _inFront(tester);
      final shortcuts = FakeLauncherShortcuts(launch: AppShortcut.search);
      final app = await pumpApp(tester, shortcuts: shortcuts, state: const CatalogueState(), settle: false);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.descendant(of: navigation(), matching: find.text('Ong Log')));
      await tester.pump(const Duration(milliseconds: 500));
      app.notifier.emit(loadedState(testCatalogue(), testNow));
      await tester.pumpAndSettle();
      await tester.pump(keyboardRetryDelay * 2);
      await goToTab(tester, 'Highlights');
      expect(_highlightsField(tester).focusNode!.hasFocus, isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
      expect(_keyboardRequests(tester), 0);
    });
  });

  group('Favourites', () {
    testWidgets('closes the dialog over About, shows the favourites alone', (tester) async {
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts, prefs: _aFavourite());
      await tester.enterText(searchField(), 'gloria');
      await tester.pumpAndSettle();
      await tester.tap(chip('Popular'));
      await tester.pumpAndSettle();
      await goToTab(tester, 'About');
      await tester.drag(aboutScrollable(), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.widgetWithText(TextButton, 'Clear'));
      expect(find.byType(AlertDialog), findsOneWidget);

      shortcuts.use(AppShortcut.favourites);
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(selectedTab(tester), 0);
      expect(_tracks(tester), ['Song of Storms'], reason: 'without the query and the genre of before');
      expect(tester.widget<FilterChip>(chip('Favourites')).selected, isTrue);
      expect(find.text('gloria'), findsNothing);
      // twice for one use (the plugin may report the one the app was opened with twice): still on
      shortcuts.use(AppShortcut.favourites);
      await tester.pumpAndSettle();
      expect(_tracks(tester), ['Song of Storms']);
    });

    testWidgets('opens the app on the favourites', (tester) async {
      await pumpApp(
        tester,
        shortcuts: FakeLauncherShortcuts(launch: AppShortcut.favourites),
        prefs: _aFavourite(),
      );
      expect(selectedTab(tester), 0);
      expect(_tracks(tester), ['Song of Storms']);
    });

    testWidgets('without favourite (a shortcut pinned on the home screen), every highlight', (tester) async {
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts);
      await tester.tap(chip('Disney'));
      await tester.pumpAndSettle();
      await goToTab(tester, 'Ong Log');
      shortcuts.use(AppShortcut.favourites);
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(_tracks(tester), hasLength(3));
    });
  });

  group('Ong Log', () {
    testWidgets('closes the licences page, shows the Ong Log, without keyboard', (tester) async {
      final shortcuts = FakeLauncherShortcuts();
      await pumpApp(tester, shortcuts: shortcuts);
      await tester.tap(searchField());
      await tester.pumpAndSettle();
      await goToTab(tester, 'About');
      await tester.drag(aboutScrollable(), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Licences'));
      expect(find.byType(LicensePage), findsOneWidget);

      shortcuts.use(AppShortcut.ongLog);
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(selectedTab(tester), 1);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('opens the app on the Ong Log', (tester) async {
      await pumpApp(tester, shortcuts: FakeLauncherShortcuts(launch: AppShortcut.ongLog));
      expect(selectedTab(tester), 1);
    });
  });
}
