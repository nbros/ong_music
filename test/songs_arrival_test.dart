// The Highlights list from the Highlights sheet alone, and the Songs sheet coming after it (songsWanted): what each
// tab shows meanwhile, what asks for the Songs sheet, and what the arrival changes on the screen (nothing the user
// is looking at moves, no row is built again unless what it shows changed). The states are those CatalogueNotifier
// goes through (test/catalogue_state_test.dart).
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'expanded_test.dart' show desk, highlightRow, inPane, paneHighlight;
import 'fixtures.dart';
import 'keyboard_test.dart' show focusedTrack, intoList, Look, listPosition, press, region;
import 'ui_harness.dart';

void main() {
  // the Songs sheet spells shadowvanta otherwise, more often: the name of their rows changes when it comes
  final moreSongs = [
    start('2024-03-09'),
    for (var i = 0; i < 3; i++) sRow(date: '2024-03-09 20:0$i:00', title: 'Other $i', requester: 'ShadowVanta'),
  ];
  final complete = testCatalogue(moreSongs: moreSongs);
  final alone = complete.highlightsOnly;
  // a list to scroll: tunes by them and by others, newer than the three highlights
  final long = testCatalogue(
    moreSongs: [
      start('2024-03-09'),
      for (var i = 0; i < 20; i++)
        sRow(date: '2024-03-09 20:${10 + i}:00', title: 'Other $i', requester: 'ShadowVanta'),
    ],
    moreHighlights: [
      for (var i = 0; i < 30; i++)
        hRow(order: '${10 + i}', title: 'Tune $i', upload: '2024-02-01', requester: i.isEven ? 'shadowvanta' : 'amy'),
    ],
  );
  final fetchedAt = testNow.subtract(const Duration(hours: 1));
  CatalogueState highlightsOnly({bool loading = true, Object? songsError}) =>
      CatalogueState(catalogue: alone, fetchedAt: fetchedAt, isLoadingSongs: loading, songsError: songsError);
  CatalogueState withSongs({DateTime? songsAt}) =>
      CatalogueState(catalogue: complete, fetchedAt: fetchedAt, songsFetchedAt: songsAt ?? fetchedAt);

  /// Where the parts of the fiche on the screen are (in the detail pane with [pane]), and its chevrons.
  Map<String, Object> ficheLayout(WidgetTester tester, {bool pane = false}) {
    Finder scoped(Finder f) => pane ? inPane(f) : f;
    Rect at(Finder f) => tester.getRect(scoped(f).first);
    return {
      'watch': at(find.text('Watch on YouTube')),
      'date': at(find.textContaining('Played live on')),
      // the room of its text, which a chevron takes from
      'date room': tester.getRect(
        find.ancestor(of: scoped(find.textContaining('Played live on')).first, matching: find.byType(Expanded)).first,
      ),
      'requester': at(find.textContaining('Requested by', findRichText: true)),
      'vocals': at(find.text('With vocals')),
      'notes': at(find.text('An improvised arrangement.')),
      'chevrons': scoped(find.byIcon(Icons.chevron_right)).evaluate().length,
    };
  }

  test('the catalogue of the test: the same highlights, one requester spelt otherwise once the songs are in', () {
    expect(alone.hasSongs, isFalse);
    expect(identical(alone.highlights, complete.highlights), isTrue);
    final survive = alone.highlights.firstWhere((h) => h.title.contains('Survive'));
    expect(alone.requester(survive.requesterId)!.name, 'shadowvanta');
    expect(complete.requester(survive.requesterId)!.name, 'ShadowVanta');
  });

  group('what asks for the Songs sheet', () {
    testWidgets('the first frame of the Highlights list, then the Ong Log and About tabs when shown', (tester) async {
      final app = await pumpApp(tester, state: highlightsOnly());
      expect(app.notifier.songTriggers, [SongsTrigger.highlightsShown], reason: 'once, after its first frame');
      // the Ong Log waits for the songs: its spinner turns, nothing settles
      await tester.tap(find.text('Ong Log').last);
      await tester.pump(const Duration(seconds: 1));
      expect(app.notifier.songTriggers.last, SongsTrigger.ongLog);
      await tester.tap(find.text('About').last);
      await tester.pump(const Duration(seconds: 1));
      expect(app.notifier.songTriggers.last, SongsTrigger.about);
      await tester.tap(find.text('Highlights').last);
      await tester.pump(const Duration(seconds: 1));
      expect(app.notifier.songTriggers, [SongsTrigger.highlightsShown, SongsTrigger.ongLog, SongsTrigger.about]);
    });

    testWidgets('nothing before the list is drawn: the first download asks for nothing', (tester) async {
      final app = await pumpApp(tester, state: CatalogueState(isRefreshing: true), settle: false);
      await tester.pump(const Duration(seconds: 1));
      expect(app.notifier.songTriggers, isEmpty);
      app.notifier.emit(highlightsOnly());
      await tester.pump();
      await tester.pump();
      expect(app.notifier.songTriggers, [SongsTrigger.highlightsShown]);
    });

    testWidgets('an address of the Ong Log asks at the start', (tester) async {
      final app = await pumpApp(tester, state: highlightsOnly(), browser: FakeBrowser('/log?q=zelda'), settle: false);
      await tester.pump(const Duration(seconds: 1));
      expect(app.notifier.songTriggers, contains(SongsTrigger.ongLog));
      expect(app.notifier.songTriggers.first, SongsTrigger.ongLog, reason: 'before the list of the hidden tab');
    });

    testWidgets('"Requested by" in a fiche, and the history of the browser back to the Ong Log', (tester) async {
      final browser = FakeBrowser('/');
      // failed: the Ong Log shows no spinner, the history of the browser can settle
      final app = await pumpApp(
        tester,
        state: highlightsOnly(loading: false, songsError: const SocketException('x')),
        size: desk,
        desktop: true,
        browser: browser,
      );
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.textContaining('Requested by')));
      await tester.pump(const Duration(seconds: 1));
      expect(selectedTab(tester), 1);
      expect(app.notifier.songTriggers.last, SongsTrigger.ongLog);
      await tester.tap(find.text('Highlights').last);
      await tester.pump(const Duration(seconds: 1));
      app.notifier.songTriggers.clear();
      await browser.back();
      await tester.pump(const Duration(seconds: 1));
      expect(selectedTab(tester), 1);
      expect(app.notifier.songTriggers, [SongsTrigger.ongLog]);
    });
  });

  group('the Ong Log while the Songs sheet is not there', () {
    testWidgets('waiting: the first download screen, its words', (tester) async {
      await pumpApp(tester, state: highlightsOnly(), settle: false);
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Ong Log').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Loading the Ong Log…').hitTestable(), findsOneWidget);
      expect(find.byType(CircularProgressIndicator).hitTestable(), findsOneWidget);
    });

    testWidgets('opened before the highlights are in: the same words; the Highlights tab says it waits for both', (
      tester,
    ) async {
      await pumpApp(
        tester,
        state: const CatalogueState(isRefreshing: true),
        settle: false,
        browser: FakeBrowser('/log'),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Loading the Ong Log…').hitTestable(), findsOneWidget);
      await tester.tap(find.text('Highlights').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Loading the highlights…').hitTestable(), findsOneWidget);
    });

    testWidgets('not asked for yet (before the first frame of the list asked for it): the same screen', (tester) async {
      await pumpApp(tester, state: highlightsOnly(loading: false), settle: false);
      await tester.tap(find.text('Ong Log').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Loading the Ong Log…').hitTestable(), findsOneWidget);
    });

    testWidgets('failed: the failure screen, its Retry downloads the Songs sheet alone', (tester) async {
      final app = await pumpApp(tester, state: highlightsOnly(loading: false, songsError: const SocketException('x')));
      await goToTab(tester, 'Ong Log');
      expect(find.text('Couldn’t download the Ong Log').hitTestable(), findsOneWidget);
      expect(find.text('Couldn’t reach Google Sheets. Check your connection and try again.'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect((app.notifier.songRetries, app.notifier.refreshes), (1, 0));
    });

    testWidgets('arrived: the list', (tester) async {
      final app = await pumpApp(tester, state: highlightsOnly());
      await tester.tap(find.text('Ong Log').last);
      await tester.pump(const Duration(seconds: 1));
      app.notifier.emit(withSongs());
      await tester.pumpAndSettle();
      expect(find.byType(PlayRow), findsWidgets);
      expect(find.text('Loading the Ong Log…'), findsNothing);
    });

    testWidgets('the Highlights tab shows nothing of it: no bar while it loads, no word of its failure', (
      tester,
    ) async {
      final app = await pumpApp(tester, state: highlightsOnly(), settle: false);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(HighlightRow), findsWidgets);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      app.notifier.emit(highlightsOnly(loading: false, songsError: const SocketException('x')));
      await tester.pumpAndSettle();
      expect(find.textContaining('Couldn’t'), findsNothing);
      expect(find.byType(HighlightRow), findsWidgets);
      // the songs refreshed under the Highlights list: no bar there either, the Ong Log has it
      app.notifier.emit(
        CatalogueState(catalogue: complete, fetchedAt: fetchedAt, songsFetchedAt: fetchedAt, isLoadingSongs: true),
      );
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LinearProgressIndicator).hitTestable(), findsNothing);
      await tester.tap(find.text('Ong Log').last);
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(LinearProgressIndicator).hitTestable(), findsOneWidget);
    });

    testWidgets('a pull on the Highlights list waits for the highlights only, and says only their failure', (
      tester,
    ) async {
      final app = await pumpApp(tester, state: highlightsOnly(loading: false, songsError: const SocketException('x')));
      await tester.fling(find.byType(HighlightRow).first, const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(app.notifier.refreshes, 1);
      expect(find.textContaining('Refresh failed'), findsNothing);
    });
  });

  group('the arrival of the Songs sheet', () {
    testWidgets('a phone: the list stays scrolled, the search kept, no row built again, no name spelt otherwise', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: long.highlightsOnly, fetchedAt: fetchedAt),
      );
      await tester.enterText(searchField(), 'u');
      await tester.pumpAndSettle();
      listPosition(tester).jumpTo(250);
      await tester.pumpAndSettle();
      final before = {for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow))) row.highlight: row};
      final rects = {for (final h in before.keys) h: tester.getRect(find.byWidget(before[h]!))};
      expect(before.length, greaterThan(5));
      app.notifier.emit(CatalogueState(catalogue: long, fetchedAt: fetchedAt));
      await tester.pump();
      expect(listPosition(tester).pixels, 250);
      expect(tester.widget<TextField>(searchField()).controller!.text, 'u');
      final after = {for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow))) row.highlight: row};
      expect(after.keys.toSet(), before.keys.toSet(), reason: 'the same rows: the same highlight objects');
      for (final h in before.keys) {
        expect(tester.getRect(find.byWidget(after[h]!)), rects[h], reason: '${h.title} did not move');
        expect(identical(after[h], before[h]), isTrue, reason: '${h.title}: nothing it shows changed');
      }
      // the list keeps the spelling of the Highlights sheet, which the Songs sheet would change
      expect(before.values.where((row) => row.requester == 'shadowvanta').length, greaterThan(1));
      expect(
        long.requester(before.keys.firstWhere((h) => before[h]!.requester == 'shadowvanta').requesterId)!.name,
        'ShadowVanta',
        reason: 'the Ong Log and the fiches spell it so',
      );
      expect(find.textContaining('ShadowVanta', findRichText: true), findsNothing);
    });

    testWidgets('a computer: the selection, the focus and the fiche of the pane stay, the fiche as it was laid out', (
      tester,
    ) async {
      final app = await pumpApp(tester, state: highlightsOnly(), size: desk, desktop: true);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await intoList(tester, Look.deskWide);
      // the arrows move the selection with the focus: back to the chosen row
      while (focusedTrack() != 'I Will Survive') {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      final focusedNode = FocusManager.instance.primaryFocus;
      expect(paneHighlight(tester), 'I Will Survive');
      expect(inPane(find.textContaining('in the Ong Log')), findsNothing);
      expect(inPane(find.textContaining('times live')), findsNothing);
      final rows = {for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow))) row.highlight: row};
      final layout = ficheLayout(tester, pane: true);
      app.notifier.emit(withSongs());
      await tester.pumpAndSettle();
      expect(ficheLayout(tester, pane: true), layout, reason: 'the fiche the user chose keeps its layout');
      expect(paneHighlight(tester), 'I Will Survive');
      expect(identical(FocusManager.instance.primaryFocus, focusedNode), isTrue, reason: 'the focus did not move');
      expect(region(), 'list');
      expect(tester.widget<HighlightRow>(highlightRow('I Will Survive')).selected, isTrue);
      expect(inPane(find.text('4 requests in the Ong Log')), findsOneWidget);
      expect(inPane(find.textContaining('times live')), findsNothing, reason: 'until it is chosen again');
      for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow))) {
        expect(identical(row, rows[row.highlight]), isTrue, reason: '${row.highlight.title} built again');
      }
    });

    testWidgets('an open sheet keeps its size: only the requests fill the line kept for them', (tester) async {
      final app = await pumpApp(tester, state: highlightsOnly());
      await tester.tap(find.descendant(of: highlightRow('I Will Survive'), matching: find.byIcon(Icons.more_vert)));
      await tester.pumpAndSettle();
      expect(find.textContaining('in the Ong Log'), findsNothing);
      expect(find.textContaining('times live'), findsNothing);
      final before = ficheLayout(tester);
      app.notifier.emit(withSongs());
      await tester.pumpAndSettle();
      expect(ficheLayout(tester), before, reason: 'nothing of the sheet moves, nothing becomes tappable');
      expect(find.text('4 requests in the Ong Log'), findsOneWidget);
      expect(find.textContaining('times live'), findsNothing, reason: 'its facts are those it was opened with');
      // opened again: with the facts of the Ong Log
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: highlightRow('I Will Survive'), matching: find.byIcon(Icons.more_vert)));
      await tester.pumpAndSettle();
      expect(find.text('Played 2 times live'), findsOneWidget);
      expect(find.textContaining('Played live on'), findsOneWidget);
      final opened = ficheLayout(tester);
      expect(
        (opened['date'] as Rect).width,
        (before['date'] as Rect).width,
        reason: 'the room of its chevron was kept',
      );
    });

    testWidgets('the fiche the app opened by itself in the pane completes as the page finishes loading', (
      tester,
    ) async {
      // the newest highlight, which the pane shows at the start, is a song played twice
      final newest = testCatalogue(
        moreSongs: moreSongs,
        moreHighlights: [
          hRow(
            order: '4',
            title: 'Gloria Gaynor - I Will Survive',
            link: 'https://youtu.be/ccccccccccc',
            requester: 'shadowvanta',
            stream: '2024-03-02',
            upload: '2024-03-08',
            vocals: 'Yes',
            notes: 'An improvised arrangement.',
          ),
        ],
      );
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: newest.highlightsOnly, fetchedAt: fetchedAt, isLoadingSongs: true),
        size: desk,
        desktop: true,
      );
      expect(paneHighlight(tester), 'I Will Survive');
      expect(inPane(find.textContaining('times live')), findsNothing);
      final before = ficheLayout(tester, pane: true);
      app.notifier.emit(CatalogueState(catalogue: newest, fetchedAt: fetchedAt, songsFetchedAt: fetchedAt));
      await tester.pumpAndSettle();
      expect(inPane(find.text('Played 2 times live')), findsOneWidget);
      expect(inPane(find.text('4 requests in the Ong Log')), findsOneWidget);
      final after = ficheLayout(tester, pane: true);
      for (final part in ['watch', 'date', 'date room', 'requester']) {
        expect(after[part], before[part], reason: '$part, above the facts that come, does not move');
      }
    });

    testWidgets('the "in the Ong Log" link of a search comes, in the place kept for it', (tester) async {
      final app = await pumpApp(tester, state: highlightsOnly());
      await tester.enterText(searchField(), 'survive');
      await tester.pumpAndSettle();
      expect(find.textContaining('in the Ong Log'), findsNothing);
      final line = tester.getRect(find.byType(CountLine));
      final firstRow = tester.getRect(find.byType(HighlightRow).first);
      app.notifier.emit(withSongs());
      await tester.pumpAndSettle();
      expect(find.text('2 in the Ong Log →'), findsOneWidget);
      expect(tester.getRect(find.byType(CountLine)), line);
      expect(tester.getRect(find.byType(HighlightRow).first), firstRow);
    });

    testWidgets('About: the highlights alone, then the songs and streams; "Updated" is the older sheet', (
      tester,
    ) async {
      final app = await pumpApp(tester, state: highlightsOnly(loading: false), prefs: {'twitchName': 'jsbach64'});
      await goToTab(tester, 'About');
      await tester.scrollUntilVisible(find.text('Clear downloaded data'), 200, scrollable: aboutScrollable());
      expect(find.text('3 highlights'), findsOneWidget);
      expect(find.text('Your name will show in orange in every list.'), findsOneWidget);
      expect(
        find.textContaining('Found 2 requests'),
        findsNothing,
        reason: 'the requests are counted in the Songs sheet',
      );
      expect(find.text('Updated 1 hour ago'), findsOneWidget);
      app.notifier.emit(withSongs(songsAt: testNow.subtract(const Duration(hours: 3))));
      await tester.pumpAndSettle();
      expect(find.text('7 songs · 3 streams'), findsOneWidget);
      expect(find.textContaining('Found 2 requests by jsbach64'), findsOneWidget);
      expect(find.text('Updated 3 hours ago'), findsOneWidget);
      app.notifier.emit(
        CatalogueState(
          catalogue: complete,
          fetchedAt: fetchedAt,
          songsFetchedAt: fetchedAt,
          songsError: const SocketException('x'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('The last refresh failed.'), findsOneWidget, reason: 'either sheet');
    });
  });

  test('a catalogue completed with the songs keeps the row keys of its highlights', () {
    for (final h in alone.highlights) {
      expect(highlightRowKey(complete, h), highlightRowKey(alone, h));
    }
    expect(complete, isA<Catalogue>());
  });
}
