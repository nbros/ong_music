// Moving the favourites: the Favourites section of the About tab, the exported text, and its import.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/favourites_transfer.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

const _key = FavouritesNotifier.key;

/// The key of the highlight of [testCatalogue] without video (Moana - How Far I'll Go).
final String _moana = testCatalogue().highlights[2].key;

/// More highlights: a nocturne with a video, and a second "How Far I'll Go" without video.
final _more = [
  hRow(
    order: '4',
    title: 'Chopin - Nocturne Op. 9 No. 2',
    genre: 'CLASSICAL',
    link: 'https://youtu.be/wxyzABCDEFG',
    upload: '2024-03-08',
  ),
  hRow(order: '5', title: "Moana - How Far I'll Go", genre: 'DISNEY', upload: '2024-03-09'),
];

CatalogueState _state() => loadedState(testCatalogue(moreHighlights: _more), testNow);

/// The About tab, scrolled to the Favourites section.
Future<void> _toSection(WidgetTester tester) async {
  await goToTab(tester, 'About');
  // the buttons, with some room under them
  await tester.scrollUntilVisible(find.text('Data'), 100, scrollable: aboutScrollable());
  await tester.pumpAndSettle();
}

Finder _button(String label) => find.widgetWithText(TextButton, label);

bool _enabled(WidgetTester tester, String label) => tester.widget<TextButton>(_button(label).first).onPressed != null;

/// The favourites of the running app.
Set<String> _favourites(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OngMusicApp))).read(favouritesProvider);

/// Opens the import dialog and types [text] in it.
Future<void> _importText(WidgetTester tester, String text) async {
  await tapVisible(tester, _button('Import').first);
  expect(find.text('Import favourites'), findsOneWidget);
  await tester.enterText(find.byType(TextField).last, text);
  await tester.pump();
  await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: _button('Import')));
  await tester.pumpAndSettle();
}

void main() {
  test('the export: one line per favourite in the order they were added, the number of lines first', () {
    final catalogue = testCatalogue(moreHighlights: _more);
    final lines = favouriteLines({
      'aaaaaaaaaaa',
      // a video that left the catalogue: its link alone
      'lmnopqrstuv',
      'wxyzABCDEFG',
      // a highlight without video that left it: nothing would find it again
      '9 gone without video',
      _moana,
    }, catalogue);
    expect(favouritesExportText(lines), '''
My Ong Music favourites (4)
Zelda - Song of Storms — https://youtu.be/aaaaaaaaaaa
https://youtu.be/lmnopqrstuv
Chopin - Nocturne Op. 9 No. 2 — https://youtu.be/wxyzABCDEFG
Moana - How Far I'll Go''');
    // without catalogue, the videos alone
    expect(favouriteLines({'aaaaaaaaaaa', _moana}, null), ['https://youtu.be/aaaaaaaaaaa']);
  });

  test('the import reads every YouTube link wherever it is, and the titles of the highlights without video', () {
    final catalogue = testCatalogue(moreHighlights: _more);
    const forwarded = '''
Forwarded message:
> My Ong Music favourites (4)
> Chopin - Nocturne Op. 9 No. 2 —
> https://youtu.be/wxyzABCDEFG
> Zelda - Song of Storms — https://www.youtube.com/watch?v=aaaaaaaaaaa&t=42s and also
https://m.youtube.com/watch?feature=share&v=bbbbbbbbbbb (Gloria) https://youtu.be/notInTheApp
  Moana - How Far I'll Go
Moana - How Far I'll Go
Moana - How Far I'll Go
Moana - How Far I'll Go
Sent from my phone''';
    final keys = favouriteKeysIn(forwarded, catalogue);
    final moanas = [
      for (final h in catalogue.highlights.reversed)
        if (h.youtubeId == null) h.key,
    ];
    // in the order of the text; the two highlights titled so, the newest first, once each; nothing else
    expect(keys, ['wxyzABCDEFG', 'aaaaaaaaaaa', 'bbbbbbbbbbb', ...moanas]);
    expect(favouriteKeysIn('My Ong Music favourites (0)\nhello', catalogue), isEmpty);
  });

  testWidgets('the section: the number of favourites, Export only with some, Import once the highlights are in', (
    tester,
  ) async {
    final app = await pumpApp(tester, state: const CatalogueState(isRefreshing: true), settle: false);
    // the spinner of the list turns: no settling
    await tester.tap(find.descendant(of: navigation(), matching: find.text('About')));
    await tester.pump(const Duration(seconds: 1));
    await tester.scrollUntilVisible(find.text('Data'), 100, scrollable: aboutScrollable());
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('0 favourites'), findsOneWidget);
    expect(_enabled(tester, 'Export'), isFalse);
    expect(_enabled(tester, 'Import'), isFalse);
    app.notifier.emit(_state());
    await tester.pumpAndSettle();
    await _toSection(tester);
    expect(_enabled(tester, 'Import'), isTrue);

    // the count changes in place: the buttons stay where they are
    final export = tester.getRect(_button('Export'));
    final import = tester.getRect(_button('Import'));
    final below = tester.getRect(find.text('Data'));
    await ProviderScope.containerOf(
      tester.element(find.byType(OngMusicApp)),
    ).read(favouritesProvider.notifier).toggle(testCatalogue().highlights[0]);
    await tester.pumpAndSettle();
    expect(find.text('1 favourite'), findsOneWidget);
    expect(_enabled(tester, 'Export'), isTrue);
    expect((tester.getRect(_button('Export')), tester.getRect(_button('Import'))), (export, import));
    expect(tester.getRect(find.text('Data')), below);
  });

  testWidgets('Export gives the text to the share sheet, or copies it where there is none', (tester) async {
    final prefs = {
      _key: ['aaaaaaaaaaa', _moana],
    };
    const text =
        "My Ong Music favourites (2)\nZelda - Song of Storms — https://youtu.be/aaaaaaaaaaa\nMoana - How Far I'll Go";
    final app = await pumpApp(tester, prefs: prefs, state: _state());
    await _toSection(tester);
    expect(find.text('2 favourites'), findsOneWidget);
    await tapVisible(tester, _button('Export'));
    expect(app.effects.shared, [text]);
    expect(find.text('Copied'), findsNothing);

    await tester.pumpWidget(const SizedBox());
    final desktop = await pumpApp(tester, prefs: prefs, state: _state(), canShare: false);
    await _toSection(tester);
    await tapVisible(tester, _button('Export'));
    expect(desktop.effects.shared, isEmpty);
    expect(desktop.effects.clipboard, text);
    expect(find.text('Copied'), findsOneWidget);
    await waitForMessage(tester);
  });

  testWidgets('Import adds what the text names after the favourites there, and says how many', (tester) async {
    final app = await pumpApp(
      tester,
      prefs: {
        _key: ['bbbbbbbbbbb'],
      },
      state: _state(),
    );
    await _toSection(tester);
    await _importText(
      tester,
      "My Ong Music favourites (3)\nMoana - How Far I'll Go\nhttps://youtu.be/wxyzABCDEFG\nGloria https://youtu.be/bbbbbbbbbbb",
    );
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('2 favourites added'), findsOneWidget);
    final moana = testCatalogue(moreHighlights: _more).highlights[4].key;
    expect(_favourites(tester).toList(), ['bbbbbbbbbbb', moana, 'wxyzABCDEFG']);
    expect(app.prefs.getStringList(_key), ['bbbbbbbbbbb', moana, 'wxyzABCDEFG']);
    expect(find.text('3 favourites'), findsOneWidget);
    await waitForMessage(tester);

    await _importText(tester, 'https://youtu.be/aaaaaaaaaaa');
    expect(find.text('1 favourite added'), findsOneWidget);
    await waitForMessage(tester);

    // all of it there already
    await _importText(tester, 'https://youtu.be/aaaaaaaaaaa https://youtu.be/wxyzABCDEFG');
    expect(find.text('Already in your favourites'), findsOneWidget);
    expect(_favourites(tester), hasLength(4));
    await waitForMessage(tester);
  });

  testWidgets('a text naming nothing keeps the dialog open with its error, which goes with the next change', (
    tester,
  ) async {
    await pumpApp(tester, state: _state());
    await _toSection(tester);
    await tapVisible(tester, _button('Import').first);
    expect(find.text('Paste the exported text'), findsOneWidget);
    final actions = tester.getRect(find.text('Cancel'));
    await tester.enterText(find.byType(TextField).last, 'https://youtu.be/notInTheApp\nNo such song');
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: _button('Import')));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('That text holds no favourites.'), findsOneWidget);
    // the error took a line kept for it
    expect(tester.getRect(find.text('Cancel')), actions);
    await tester.enterText(find.byType(TextField).last, 'https://youtu.be/notInTheApp\nNo such song!');
    await tester.pumpAndSettle();
    expect(find.text('That text holds no favourites.'), findsNothing);
    expect(_favourites(tester), isEmpty);
  });

  testWidgets('Android Back and Escape close the dialog, Cancel too, adding nothing', (tester) async {
    await pumpApp(tester, state: _state());
    await _toSection(tester);
    for (final close in <Future<void> Function()>[
      () => tester.binding.handlePopRoute(),
      () => tester.sendKeyEvent(LogicalKeyboardKey.escape),
      () => tester.tap(find.text('Cancel')),
    ]) {
      await tapVisible(tester, _button('Import').first);
      await tester.enterText(find.byType(TextField).last, 'https://youtu.be/aaaaaaaaaaa');
      await close();
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
    }
    expect(_favourites(tester), isEmpty);
    expect(find.textContaining('added'), findsNothing);
  });

  testWidgets('on a small phone, the keyboard up, the buttons of the dialog stay above it', (tester) async {
    await pumpApp(tester, state: _state(), size: const Size(320, 568));
    await _toSection(tester);
    await tapVisible(tester, _button('Import').first);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.enterText(find.byType(TextField).last, List.filled(12, 'https://youtu.be/aaaaaaaaaaa').join('\n'));
    await tester.pumpAndSettle();
    for (final label in ['Cancel', 'Import']) {
      final button = find.descendant(of: find.byType(AlertDialog), matching: _button(label));
      expect(button.hitTestable(), findsOneWidget, reason: label);
      expect(tester.getRect(button).bottom, lessThanOrEqualTo(568 - 260), reason: label);
    }
    // and the field keeps the room of a few lines, its text scrolling in it
    expect(tester.getRect(find.byType(TextField).last).height, greaterThan(100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('what one device exports, another imports whole', (tester) async {
    // a title read back names the newest highlight without video of that title
    final keys = ['wxyzABCDEFG', testCatalogue(moreHighlights: _more).highlights[4].key, 'aaaaaaaaaaa'];
    await pumpApp(tester, prefs: {_key: keys}, state: _state());
    final text = favouritesExportText(favouriteLines(_favourites(tester), testCatalogue(moreHighlights: _more)));
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, state: _state());
    await _toSection(tester);
    await _importText(tester, text);
    expect(find.text('3 favourites added'), findsOneWidget);
    expect(_favourites(tester).toList(), keys);
    await waitForMessage(tester);
  });
}
