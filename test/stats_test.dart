// The statistics page: its entry in About, its head, the four rankings, "You", what the rows open, how it closes,
// its loading, and its keyboard.
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/rankings.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/stats_page.dart';
import 'package:ong_music/src/ui/view_state.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// Opens the statistics page from the About tab.
Future<void> openStats(WidgetTester tester) async {
  await goToTab(tester, 'About');
  await tester.scrollUntilVisible(find.text('Statistics'), 200, scrollable: aboutScrollable());
  await tester.ensureVisible(find.text('Statistics'));
  await tester.tap(find.text('Statistics'));
  await tester.pumpAndSettle();
}

/// Shows the ranking [label], its segment scrolled into view (the letters of the font of the tests are squares:
/// the segments need more room than a phone has).
Future<void> showRanking(WidgetTester tester, String label) async {
  final segment = find.descendant(of: find.byType(SegmentedButton<RankingKind>), matching: find.text(label));
  await tester.ensureVisible(segment);
  await tester.pumpAndSettle();
  await tester.tap(segment);
  await tester.pumpAndSettle();
}

/// The rows of the ranking on screen, in order.
Finder rows() => find.descendant(
  of: find.byType(SliverFixedExtentList),
  matching: find.byWidgetPredicate((w) => w is Semantics && (w.properties.label ?? '').startsWith('Rank ')),
);

/// The scroll view of the ranking.
Finder rankingScrollable() =>
    find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;

/// What screen readers read of the rows of the ranking on screen, in order.
List<String> rowSentences(WidgetTester tester) => [
  for (final row in tester.widgetList<Semantics>(rows())) row.properties.label!,
];

/// The texts of the rows in [style] (a font size of the row), from the first row to the last.
List<Text> rowTexts(WidgetTester tester, double fontSize) => tester
    .widgetList<Text>(
      find.descendant(
        of: find.byType(SliverFixedExtentList),
        matching: find.byWidgetPredicate((w) => w is Text && w.style?.fontSize == fontSize),
      ),
    )
    .toList();

/// The units under the counts of the rows, from the first row to the last (13 px, at the end, of normal weight; the
/// ranks are of the same size, heavier).
List<Text> unitTexts(WidgetTester tester) =>
    rowTexts(tester, 13).where((t) => t.textAlign == TextAlign.end && t.style?.fontWeight == null).toList();

/// The provider container of the app.
ProviderContainer container(WidgetTester tester) => ProviderScope.containerOf(tester.element(find.byType(OngMusicApp)));

void main() {
  group('the entry in About', () {
    testWidgets('a row under the links opens the page, with its title and a back arrow', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'About');
      // under the link tiles, above the settings
      expect(tester.getTopLeft(find.text('Statistics')).dy, greaterThan(tester.getTopLeft(find.text('Merch')).dy));
      expect(tester.getTopLeft(find.text('Statistics')).dy, lessThan(tester.getTopLeft(find.text('Appearance')).dy));
      await openStats(tester);
      expect(find.byType(StatsPage), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Statistics'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(StatsPage), findsNothing);
      expect(selectedTab(tester), 2);
    });

    testWidgets('it does not move when the Songs sheet comes', (tester) async {
      final complete = testCatalogue();
      final fetchedAt = testNow.subtract(const Duration(hours: 1));
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: complete.highlightsOnly, fetchedAt: fetchedAt),
        prefs: {'twitchName': 'jsbach64'},
      );
      await goToTab(tester, 'About');
      final before = tester.getRect(find.text('Statistics'));
      app.notifier.emit(CatalogueState(catalogue: complete, fetchedAt: fetchedAt, songsFetchedAt: fetchedAt));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('Statistics')), before);
    });

    testWidgets('the tables of the rankings are made ahead once About has stayed on screen, not before', (
      tester,
    ) async {
      final catalogue = testCatalogue();
      await pumpApp(tester, state: loadedState(catalogue, testNow.subtract(const Duration(hours: 2))));
      // on another tab: never
      await tester.pump(rankingsAheadDelay * 3);
      expect(hasRankingTables(catalogue), isFalse);
      await goToTab(tester, 'About');
      expect(hasRankingTables(catalogue), isFalse);
      await tester.pump(rankingsAheadDelay);
      expect(hasRankingTables(catalogue), isTrue);
    });

    testWidgets('they are not made while something moves, nor without the Songs sheet', (tester) async {
      final catalogue = testCatalogue();
      final fetchedAt = testNow.subtract(const Duration(hours: 1));
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: catalogue.highlightsOnly, fetchedAt: fetchedAt),
      );
      await goToTab(tester, 'About');
      await tester.pump(rankingsAheadDelay * 2);
      expect(hasRankingTables(catalogue.highlightsOnly), isFalse);
      app.notifier.emit(CatalogueState(catalogue: catalogue, fetchedAt: fetchedAt, songsFetchedAt: fetchedAt));
      await tester.pumpAndSettle();
      // a frame is waiting when the delay ends (a scroll, an animation): later
      tester.binding.scheduleFrame();
      await tester.binding.delayed(rankingsAheadDelay);
      expect(hasRankingTables(catalogue), isFalse);
      await tester.pump();
      await tester.pump(rankingsAheadDelay);
      expect(hasRankingTables(catalogue), isTrue);
    });

    testWidgets('nor while a finger holds the page in the middle of a drag', (tester) async {
      final catalogue = testCatalogue();
      await pumpApp(tester, state: loadedState(catalogue, testNow.subtract(const Duration(hours: 2))));
      await goToTab(tester, 'About');
      final finger = await tester.startGesture(tester.getCenter(aboutScrollable()));
      await finger.moveBy(const Offset(0, -40));
      await finger.moveBy(const Offset(0, -40));
      await tester.pump();
      // resting: no frame is asked for
      await tester.binding.delayed(rankingsAheadDelay * 2);
      expect(hasRankingTables(catalogue), isFalse);
      await finger.up();
      await tester.pumpAndSettle();
      await tester.pump(rankingsAheadDelay * 2);
      expect(hasRankingTables(catalogue), isTrue);
    });

    testWidgets('one button for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await goToTab(tester, 'About');
      expect(
        tester.getSemantics(find.ancestor(of: find.text('Statistics'), matching: find.byType(Semantics)).first),
        matchesSemantics(label: 'Statistics', isButton: true, hasTapAction: true),
      );
      handle.dispose();
    });
  });

  group('the head', () {
    testWidgets('the totals, the choice, what the ranking holds', (tester) async {
      await pumpApp(tester);
      await openStats(tester);
      expect(find.text('2 streams · 4 plays · 3 songs · 3 highlights'), findsOneWidget);
      for (final label in ['Songs', 'Artists', 'Genres', 'Requesters']) {
        expect(
          find.descendant(of: find.byType(SegmentedButton<RankingKind>), matching: find.text(label)),
          findsOneWidget,
        );
      }
      expect(find.text('3 songs'), findsOneWidget);
      await showRanking(tester, 'Artists');
      expect(find.text('2 artists'), findsOneWidget);
      await showRanking(tester, 'Genres');
      expect(find.text('2 genres'), findsOneWidget);
      await showRanking(tester, 'Requesters');
      expect(find.text('3 requesters'), findsOneWidget);
    });

    testWidgets('the list stays where it is when the "You" chip goes and comes back', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'shadowvanta'});
      await openStats(tester);
      expect(chip('You'), findsOneWidget);
      final withChip = tester.getRect(rows().first);
      final name = container(tester).read(twitchNameProvider.notifier);
      await name.set('nobody');
      await tester.pumpAndSettle();
      expect(chip('You'), findsNothing);
      expect(tester.getRect(rows().first), withChip);
      await name.set('shadowvanta');
      await tester.pumpAndSettle();
      expect(chip('You'), findsOneWidget);
      expect(tester.getRect(rows().first), withChip);
    });

    testWidgets('no "You" chip without a Twitch name, nor for a name without request', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'nobody'});
      await openStats(tester);
      expect(chip('You'), findsNothing);
    });

    testWidgets('the titles without artist are counted under the artists', (tester) async {
      await pumpApp(
        tester,
        state: loadedState(
          testCatalogue(
            moreSongs: [
              sRow(date: '2024-03-02 22:00:00', title: 'Improvisation', type: 'Improv'),
              sRow(date: '2024-03-02 22:10:00', title: 'Improvisation', type: 'Improv'),
            ],
          ),
          testNow,
        ),
      );
      await openStats(tester);
      await showRanking(tester, 'Artists');
      expect(find.text('2 artists · 2 plays without artist'), findsOneWidget);
    });

    testWidgets('a 360 px wide phone with large text: nothing overflows, the choice scrolls sideways', (tester) async {
      await pumpApp(tester, size: const Size(360, 740), textScale: 2, prefs: {'twitchName': 'jsbach64'});
      await openStats(tester);
      expect(tester.takeException(), isNull);
      // (the letters of the font of the tests are squares: the segments need more room than the phone has)
      final choice = find.byType(SegmentedButton<RankingKind>);
      expect(tester.getSize(choice).width, greaterThan(360 - 32));
      await showRanking(tester, 'Songs');
      await tester.drag(find.text('Songs').last, const Offset(-400, 0));
      await tester.pumpAndSettle();
      await showRanking(tester, 'Requesters');
      expect(tester.takeException(), isNull);
      expect(rowSentences(tester).first, 'Rank 1, jsbach64, you, 2 requests, 2 songs');
    });

    testWidgets('switching rankings moves nothing of the head', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      await openStats(tester);
      Rect at(Finder finder) => tester.getRect(finder);
      // the row of the segments (they scroll in it with the letters of the font of the tests), and the list
      final segments = find.ancestor(
        of: find.byType(SegmentedButton<RankingKind>),
        matching: find.byType(SingleChildScrollView),
      );
      final totals = at(find.text('2 streams · 4 plays · 3 songs · 3 highlights'));
      final choice = at(segments);
      final you = at(chip('You'));
      final list = at(rankingScrollable());
      for (final label in ['Artists', 'Genres', 'Requesters', 'Songs']) {
        await showRanking(tester, label);
        expect(at(find.text('2 streams · 4 plays · 3 songs · 3 highlights')), totals);
        expect(at(segments), choice);
        expect(at(chip('You')), you);
        expect(at(rankingScrollable()), list);
      }
      await tester.tap(chip('You'));
      await tester.pumpAndSettle();
      expect(at(chip('You')), you);
      expect(at(segments), choice);
      expect(at(rankingScrollable()), list);
    });
  });

  group('the rankings', () {
    testWidgets('songs: by plays, each its own rank, equal counts the first played first', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await openStats(tester);
      expect(rowSentences(tester), [
        'Rank 1, I Will Survive, Gloria Gaynor, 2 plays',
        'Rank 2, Lost Woods, Zelda, 1 play',
        'Rank 3, Song of Storms, Zelda, 1 play',
      ]);
      handle.dispose();
    });

    testWidgets('artists, genres and requesters', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await openStats(tester);
      await showRanking(tester, 'Artists');
      expect(rowSentences(tester), ['Rank 1, Gloria Gaynor, 2 plays, 1 song', 'Rank 2, Zelda, 2 plays, 2 songs']);
      await showRanking(tester, 'Genres');
      // Popular was played first (the first row of the sheet), Game OST after it
      expect(rowSentences(tester), ['Rank 1, Popular, 2 plays, 50.0%', 'Rank 2, Game OST, 2 plays, 50.0%']);
      await showRanking(tester, 'Requesters');
      // MannyHub asked first
      expect(rowSentences(tester), [
        'Rank 1, jsbach64, 2 requests, 2 songs',
        'Rank 2, MannyHub, 1 request, 1 song',
        'Rank 3, shadowvanta, 1 request, 1 song',
      ]);
      handle.dispose();
    });

    testWidgets('the ranks and the counts in columns, the bars against the first row', (tester) async {
      await pumpApp(
        tester,
        state: loadedState(
          testCatalogue(
            moreSongs: [for (var i = 0; i < 12; i++) sRow(date: '2024-03-02 23:00:00', title: 'Zelda - Lost Woods')],
          ),
          testNow,
        ),
      );
      await openStats(tester);
      // the counts (15 px) end at one place, in tabular figures, their units (13 px) under them; the ranks (13 px,
      // as heavy as the counts) end at one place too
      final counts = rowTexts(tester, 15).where((t) => t.textAlign == TextAlign.end).toList();
      expect([for (final t in counts) t.data], ['13', '2', '1']);
      expect({for (final t in counts) tester.getRect(find.byWidget(t)).right}, hasLength(1));
      final ranks = rowTexts(
        tester,
        13,
      ).where((t) => t.textAlign == TextAlign.end && t.style?.fontWeight == FontWeight.w500).toList();
      expect([for (final t in ranks) t.data], ['1', '2', '3']);
      expect({for (final t in ranks) tester.getRect(find.byWidget(t)).right}, hasLength(1));
      expect(tester.getRect(find.text('Lost Woods')).left, tester.getRect(find.text('Song of Storms')).left);
      for (final t in [...counts, ...ranks]) {
        expect(t.style!.fontFeatures, contains(const FontFeature.tabularFigures()));
      }
      final bars = tester.widgetList<FractionallySizedBox>(find.byType(FractionallySizedBox)).toList();
      expect([for (final bar in bars) bar.widthFactor], [1, 2 / 13, 1 / 13]);
    });

    testWidgets('the titles stand at one place in every ranking, whatever its largest rank', (tester) async {
      await pumpApp(
        tester,
        state: loadedState(
          testCatalogue(
            moreSongs: [
              // songs played 1 to 12 times: ranks up to 15 among the songs, 2 among the genres
              for (var n = 1; n <= 12; n++)
                for (var i = 0; i < n; i++) sRow(date: '2024-03-02 23:00:00', title: 'Song $n'),
            ],
          ),
          testNow,
        ),
      );
      await openStats(tester);
      double titleLeft() => tester.getRect(find.byWidget(rowTexts(tester, 15).first)).left;
      final left = titleLeft();
      for (final label in ['Artists', 'Genres', 'Requesters']) {
        await showRanking(tester, label);
        expect(titleLeft(), left, reason: label);
      }
    });

    testWidgets('the user\'s own name in orange among the requesters; "You" keeps their requests alone', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, prefs: {'twitchName': 'shadowvanta'});
      await openStats(tester);
      await showRanking(tester, 'Requesters');
      expect(rowSentences(tester)[2], 'Rank 3, shadowvanta, you, 1 request, 1 song');
      await tester.tap(chip('You'));
      await tester.pumpAndSettle();
      // their own row alone, at its rank among all; the count line still says how many there are
      expect(rowSentences(tester), ['Rank 3, shadowvanta, you, 1 request, 1 song']);
      expect(find.text('3'), findsOneWidget);
      expect(find.text('3 requesters'), findsOneWidget);
      final bar = tester.widget<FractionallySizedBox>(find.byType(FractionallySizedBox));
      expect(bar.widthFactor, 0.5);
      await showRanking(tester, 'Songs');
      expect(rowSentences(tester), ['Rank 1, I Will Survive, Gloria Gaynor, 1 play']);
      await showRanking(tester, 'Genres');
      expect(rowSentences(tester), ['Rank 1, Popular, 1 play, 100.0%']);
      // the totals stay those of the catalogue
      expect(find.text('2 streams · 4 plays · 3 songs · 3 highlights'), findsOneWidget);
      handle.dispose();
    });

    testWidgets('every count over its unit, in the singular for 1: plays, and requests for the requesters', (
      tester,
    ) async {
      await pumpApp(tester);
      await openStats(tester);

      /// The units of the rows, and checks that each one stands right under its count, ending where it ends.
      List<String?> units() {
        final counts = rowTexts(tester, 15).where((t) => t.textAlign == TextAlign.end).toList();
        final units = unitTexts(tester);
        expect(units, hasLength(counts.length));
        for (var i = 0; i < units.length; i++) {
          final count = tester.getRect(find.byWidget(counts[i]));
          final unit = tester.getRect(find.byWidget(units[i]));
          expect(unit.right, count.right);
          expect(unit.top, count.bottom);
        }
        return [for (final t in units) t.data];
      }

      expect(units(), ['plays', 'play', 'play']);
      await showRanking(tester, 'Artists');
      expect(units(), ['plays', 'plays']);
      await showRanking(tester, 'Genres');
      expect(units(), ['plays', 'plays']);
      await showRanking(tester, 'Requesters');
      expect(units(), ['requests', 'request', 'request']);
      // the second line on the left stays what it was
      expect(find.text('2 songs'), findsOneWidget);
      await tester.tap(find.text('jsbach64'));
      await tester.pumpAndSettle();
      expect(units(), ['request', 'request']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await showRanking(tester, 'Artists');
      await tester.tap(find.text('Zelda'));
      await tester.pumpAndSettle();
      expect(units(), ['play', 'play']);
    });

    testWidgets(
      'the column of the counts as wide as its widest number or unit, in every row: nothing moves from row to '
      'row',
      (tester) async {
        await pumpApp(
          tester,
          prefs: {'twitchName': 'shadowvanta'},
          state: loadedState(
            testCatalogue(
              moreSongs: [for (var i = 0; i < 12; i++) sRow(date: '2024-03-02 23:00:00', title: 'Zelda - Lost Woods')],
            ),
            testNow,
          ),
        );
        await openStats(tester);

        /// The width of the column of the counts, the same for the count and the unit of every row; and the titles and
        /// the bars, which end and begin at one place.
        double column() {
          final texts = [...rowTexts(tester, 15).where((t) => t.textAlign == TextAlign.end), ...unitTexts(tester)];
          final widths = {for (final t in texts) tester.getSize(find.byWidget(t)).width};
          expect(widths, hasLength(1));
          final titles = rowTexts(tester, 15).where((t) => t.textAlign != TextAlign.end);
          expect({for (final t in titles) tester.getRect(find.byWidget(t)).right}, hasLength(1));
          final bars = find.byType(FractionallySizedBox);
          expect({for (final e in bars.evaluate()) tester.getRect(find.byWidget(e.widget)).left}, hasLength(1));
          expect({for (final e in bars.evaluate()) tester.getRect(find.byWidget(e.widget)).right}, hasLength(1));
          return widths.single;
        }

        // the letters of the font of the tests are squares, as wide as the size of the font: "plays" (5 × 13) is wider
        // than "13" (2 × 15)
        expect(column(), 5 * 13);
        await showRanking(tester, 'Requesters');
        expect(column(), 8 * 13, reason: 'requests');
        // the user's own row alone, of 1 request: "request"
        await tester.tap(chip('You'));
        await tester.pumpAndSettle();
        expect(column(), 7 * 13);
        // the songs of an artist
        await tester.tap(chip('You'));
        await tester.pumpAndSettle();
        await showRanking(tester, 'Artists');
        await tester.tap(find.text('Zelda'));
        await tester.pumpAndSettle();
        expect(column(), 5 * 13);
      },
    );

    testWidgets('a 360 px wide phone with large text: counts in thousands and their units fit in every ranking', (
      tester,
    ) async {
      await pumpApp(
        tester,
        size: const Size(360, 740),
        textScale: 2,
        prefs: {'twitchName': 'jsbach64'},
        state: loadedState(
          testCatalogue(
            moreSongs: [
              for (var i = 0; i < 1200; i++)
                sRow(date: '2024-03-02 23:00:00', title: 'Zelda - Lost Woods', requester: 'jsbach64'),
            ],
          ),
          testNow,
        ),
      );
      await openStats(tester);
      expect(tester.takeException(), isNull);
      expect(find.text('1,201'), findsOneWidget);
      for (final label in ['Artists', 'Genres', 'Requesters']) {
        await showRanking(tester, label);
        expect(tester.takeException(), isNull, reason: label);
      }
      expect(find.text('1,202'), findsOneWidget);
      expect(find.text('requests'), findsOneWidget);
      // the unit inside the screen, whole
      final unit = tester.getRect(find.text('requests'));
      expect(unit.right, lessThanOrEqualTo(360 - 16));
      // their own row, the first
      await tester.tap(rows().first);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('requests'), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(chip('You'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(rowSentences(tester), ['Rank 1, jsbach64, you, 1,202 requests, 2 songs']);
    });

    testWidgets('a long ranking is built lazily, in rows of one extent', (tester) async {
      await pumpApp(
        tester,
        state: loadedState(
          testCatalogue(
            moreSongs: [for (var i = 0; i < 500; i++) sRow(date: '2024-03-02 23:00:00', title: 'Artist $i - Track $i')],
          ),
          testNow,
        ),
      );
      await openStats(tester);
      expect(rows().evaluate().length, lessThan(40));
      expect(tester.widget<SliverFixedExtentList>(find.byType(SliverFixedExtentList)).itemExtent, 64);
      final position = tester.state<ScrollableState>(rankingScrollable()).position;
      expect(position.maxScrollExtent, greaterThan(500 * 64 - 892));
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(find.text('Track 499'), findsOneWidget, reason: 'the last played of the tracks');
      expect(rowSentences(tester).last, 'Rank 503, Track 499, Artist 499, 1 play');
    });
  });

  group('what the rows open', () {
    testWidgets('a song: its fiche, over the page', (tester) async {
      await pumpApp(tester);
      await openStats(tester);
      await tester.tap(find.text('Lost Woods'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsOneWidget);
      expect(find.byType(StatsPage), findsOneWidget);
    });

    testWidgets('a song in an expanded window: its fiche in a sheet over the page too', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800));
      await openStats(tester);
      await tester.tap(find.text('Lost Woods'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsOneWidget);
      expect(find.byType(StatsPage), findsOneWidget);
    });

    testWidgets('an artist: the ranking of its songs over the page, counted as its row', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await openStats(tester);
      await showRanking(tester, 'Artists');
      expect(tester.widget<Semantics>(rows().last).properties.hint, 'Shows the songs');
      await tester.tap(find.text('Zelda'));
      await tester.pumpAndSettle();
      expect(find.byType(EntrySongsPage), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Zelda'), findsOneWidget);
      expect(find.byType(BackButton), findsOneWidget);
      expect(find.text('2 songs · 2 plays'), findsOneWidget);
      expect(rowSentences(tester), ['Rank 1, Lost Woods, Zelda, 1 play', 'Rank 2, Song of Storms, Zelda, 1 play']);
      expect(tester.widget<Semantics>(rows().first).properties.hint, 'Shows the details');
      // nothing left the statistics
      expect(container(tester).read(selectedTabProvider), AppTab.about);
      expect(container(tester).read(playFilterProvider), const PlayFilter());
      handle.dispose();
    });

    testWidgets('a genre, "Other" included: its songs', (tester) async {
      await pumpApp(
        tester,
        state: loadedState(
          testCatalogue(
            moreSongs: [sRow(date: '2024-03-02 22:00:00', title: 'Odd One', genre: 'SOMETHING ELSE')],
          ),
          testNow,
        ),
      );
      await openStats(tester);
      await showRanking(tester, 'Genres');
      await tester.tap(find.text('Other'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Other'), findsOneWidget);
      expect(rowSentences(tester), ['Rank 1, Odd One, 1 play']);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Popular'));
      await tester.pumpAndSettle();
      expect(find.text('1 song · 2 plays'), findsOneWidget);
      expect(rowSentences(tester), ['Rank 1, I Will Survive, Gloria Gaynor, 2 plays']);
    });

    testWidgets('a requester: their requests, song by song, in the statistics', (tester) async {
      await pumpApp(tester);
      await openStats(tester);
      await showRanking(tester, 'Requesters');
      await tester.tap(find.text('jsbach64'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'jsbach64'), findsOneWidget);
      expect(find.text('2 songs · 2 requests'), findsOneWidget);
      expect(rowSentences(tester), [
        'Rank 1, Lost Woods, Zelda, 1 request',
        'Rank 2, Song of Storms, Zelda, 1 request',
      ]);
      expect(container(tester).read(selectedTabProvider), AppTab.about);
      expect(container(tester).read(playFilterProvider).query, isEmpty);
    });

    testWidgets('with "You": the user\'s own requests alone, their name in orange on the line', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'shadowvanta'});
      await openStats(tester);
      await tester.tap(chip('You'));
      await tester.pumpAndSettle();
      await showRanking(tester, 'Genres');
      await tester.tap(find.text('Popular'));
      await tester.pumpAndSettle();
      // I Will Survive was played twice, once at their request
      expect(rowSentences(tester), ['Rank 1, I Will Survive, Gloria Gaynor, 1 play']);
      final line = find.descendant(of: find.byType(EntrySongsPage), matching: find.byType(RequesterText));
      expect(line, findsOneWidget);
      expect(tester.widget<RequesterText>(line).span.toPlainText(), contains('1 song · 1 play · '));
      expect(tester.widget<RequesterText>(line).span.toPlainText(), contains('shadowvanta'));
      // the chip is not there
      expect(chip('You'), findsNothing);
    });

    testWidgets('a song of the page of an entry opens its fiche; Escape closes one, then the other', (tester) async {
      await pumpApp(tester);
      await openStats(tester);
      await showRanking(tester, 'Artists');
      await tester.tap(find.text('Zelda'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lost Woods'));
      await tester.pumpAndSettle();
      expect(tester.widget<SongSheet>(find.byType(SongSheet)).song.track, 'Lost Woods');
      for (final shown in [EntrySongsPage, StatsPage, AboutPage]) {
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(shown), findsOneWidget, reason: '$shown');
      }
      expect(find.byType(StatsPage), findsNothing);
    });

    for (final (name, back) in [
      ('the back arrow', (WidgetTester tester) => tester.tap(find.byType(BackButton))),
      ('the system Back', (WidgetTester tester) => tester.binding.handlePopRoute()),
      ('Escape', (WidgetTester tester) => tester.sendKeyEvent(LogicalKeyboardKey.escape)),
    ]) {
      testWidgets('$name returns to the ranking, at the place it was left', (tester) async {
        await pumpApp(
          tester,
          state: loadedState(
            testCatalogue(
              moreSongs: [
                for (var i = 0; i < 200; i++) sRow(date: '2024-03-02 23:00:00', title: 'Artist $i - Track $i'),
              ],
            ),
            testNow,
          ),
        );
        await openStats(tester);
        await showRanking(tester, 'Artists');
        final position = tester.state<ScrollableState>(rankingScrollable()).position;
        position.jumpTo(3000);
        await tester.pumpAndSettle();
        await tester.tap(rows().hitTestable().first);
        await tester.pumpAndSettle();
        expect(find.byType(EntrySongsPage), findsOneWidget);
        await back(tester);
        await tester.pumpAndSettle();
        expect(find.byType(EntrySongsPage), findsNothing);
        expect(find.byType(StatsPage), findsOneWidget);
        expect(tester.state<ScrollableState>(rankingScrollable()).position.pixels, 3000);
        expect(container(tester).read(statsViewProvider).kind, RankingKind.artists);
      });
    }

    testWidgets('a refresh: the page of an entry follows it in the new catalogue, and closes when it is gone', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await openStats(tester);
      await showRanking(tester, 'Artists');
      await tester.tap(find.text('Zelda'));
      await tester.pumpAndSettle();
      app.notifier.emit(
        loadedState(
          testCatalogue(
            moreSongs: [sRow(date: '2024-03-02 23:00:00', title: 'zelda - Gerudo Valley')],
          ),
          testNow,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('3 songs · 3 plays'), findsOneWidget);
      expect(find.text('Gerudo Valley'), findsOneWidget);
      // cleared: it waits, as the statistics do
      app.notifier.emit(const CatalogueState(isRefreshing: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Loading the Ong Log…'), findsOneWidget);
      expect(find.widgetWithText(AppBar, 'Zelda'), findsOneWidget);
      expect(tester.takeException(), isNull);
      // back with a catalogue without Zelda: back to the ranking
      app.notifier.emit(loadedState(catalogueOf(), testNow));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(EntrySongsPage), findsNothing);
      expect(find.byType(StatsPage), findsOneWidget);
      expect(find.text('Some song'), findsNothing, reason: 'the ranking of artists: Some song has none');
    });

    testWidgets('a tab reached from a fiche over the page closes both', (tester) async {
      await pumpApp(tester);
      await openStats(tester);
      await tester.tap(find.text('Lost Woods'));
      await tester.pumpAndSettle();
      // what "Requested by …" of a fiche does: the fiche closes, the Ong Log comes
      Navigator.of(tester.element(find.byType(SongSheet))).pop();
      container(tester).read(selectedTabProvider.notifier).select(AppTab.ongLog);
      await tester.pumpAndSettle();
      expect(find.byType(StatsPage), findsNothing);
      expect(selectedTab(tester), 1);
    });
  });

  group('closing', () {
    for (final (name, close) in [
      ('the system Back', (WidgetTester tester) => tester.binding.handlePopRoute()),
      ('Escape', (WidgetTester tester) => tester.sendKeyEvent(LogicalKeyboardKey.escape)),
    ]) {
      testWidgets('$name closes the page, About under it', (tester) async {
        await pumpApp(tester);
        await openStats(tester);
        await close(tester);
        await tester.pumpAndSettle();
        expect(find.byType(StatsPage), findsNothing);
        expect(selectedTab(tester), 2);
      });
    }

    testWidgets('Escape closes a fiche over the page first', (tester) async {
      await pumpApp(tester);
      await openStats(tester);
      await tester.tap(find.text('Lost Woods'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsNothing);
      expect(find.byType(StatsPage), findsOneWidget);
    });

    testWidgets('the browser\'s Back: the page has a step of its own, at the address of About', (tester) async {
      final browser = FakeBrowser('/about');
      await pumpApp(tester, browser: browser);
      await tester.ensureVisible(find.text('Statistics'));
      await tester.tap(find.text('Statistics'));
      await settle(tester);
      expect(browser.history, ['/about', '/about +1']);
      await browser.back();
      expect(find.byType(StatsPage), findsNothing);
      expect(selectedTab(tester), 2);
      expect(browser.left, isFalse);
    });

    testWidgets('in the web app, the page of an entry has a step of its own too: Back, then Back again', (
      tester,
    ) async {
      final browser = FakeBrowser('/about');
      await pumpApp(tester, browser: browser);
      await tester.ensureVisible(find.text('Statistics'));
      await tester.tap(find.text('Statistics'));
      await settle(tester);
      await showRanking(tester, 'Requesters');
      await tester.tap(find.text('MannyHub'));
      await settle(tester);
      expect(browser.history, ['/about', '/about +1', '/about +2']);
      await browser.back();
      expect(find.byType(EntrySongsPage), findsNothing);
      expect(find.byType(StatsPage), findsOneWidget);
      await browser.back();
      expect(find.byType(StatsPage), findsNothing);
      expect(selectedTab(tester), 2);
      expect(browser.left, isFalse);
    });
  });

  group('refreshes', () {
    testWidgets('a complete catalogue replaced while the page is open: the ranking chosen stays', (tester) async {
      final app = await pumpApp(tester);
      await openStats(tester);
      await showRanking(tester, 'Genres');
      app.notifier.emit(
        loadedState(
          testCatalogue(
            moreSongs: [sRow(date: '2024-03-02 23:00:00', title: 'Moana - Shiny', genre: 'DISNEY')],
          ),
          testNow,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(container(tester).read(statsViewProvider).kind, RankingKind.genres);
      expect(find.text('3 genres'), findsOneWidget);
      expect(rowSentences(tester).last, 'Rank 3, Disney, 1 play, 20.0%');
    });

    testWidgets('"You" on, then the user\'s requests gone: the chip and its filter go, nothing thrown', (tester) async {
      final app = await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      await openStats(tester);
      await tester.tap(chip('You'));
      await tester.pumpAndSettle();
      await showRanking(tester, 'Requesters');
      expect(rowSentences(tester), hasLength(1));
      // jsbach64 still requested a highlight, but no song
      app.notifier.emit(
        loadedState(
          catalogueOf(
            highlights: [hRow(title: 'Zelda - Song of Storms', requester: 'jsbach64')],
            songs: [
              start('2024-03-01'),
              for (final requester in ['MannyHub', 'shadowvanta'])
                sRow(date: '2024-03-01 20:00:00', title: 'Gloria Gaynor - I Will Survive', requester: requester),
            ],
          ),
          testNow,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(chip('You'), findsNothing);
      expect(container(tester).read(statsViewProvider).mine, isFalse);
      expect(rowSentences(tester), ['Rank 1, MannyHub, 1 request, 1 song', 'Rank 2, shadowvanta, 1 request, 1 song']);
    });

    testWidgets('a change of ranking is said: the line of what it holds is a live region', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      await openStats(tester);
      await showRanking(tester, 'Artists');
      expect(tester.getSemantics(find.text('2 artists')), matchesSemantics(label: '2 artists', isLiveRegion: true));
      handle.dispose();
    });
  });

  group('loading', () {
    testWidgets('without the Songs sheet: what the Ong Log shows, and the page asks for it', (tester) async {
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: testCatalogue().highlightsOnly, fetchedAt: testNow),
        settle: false,
      );
      await goToTab(tester, 'About');
      app.notifier.songTriggers.clear();
      await tester.ensureVisible(find.text('Statistics'));
      await tester.tap(find.text('Statistics'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Loading the Ong Log…'), findsOneWidget);
      expect(app.notifier.songTriggers, contains(SongsTrigger.stats));
      expect(find.byType(SegmentedButton<RankingKind>), findsNothing);
      // the sheet comes: the rankings
      app.notifier.emit(loadedState(testCatalogue(), testNow));
      await tester.pumpAndSettle();
      expect(find.text('I Will Survive'), findsOneWidget);
    });

    testWidgets('its failure, with Retry', (tester) async {
      final app = await pumpApp(
        tester,
        state: CatalogueState(
          catalogue: testCatalogue().highlightsOnly,
          fetchedAt: testNow,
          songsError: Exception('offline'),
        ),
      );
      await openStats(tester);
      expect(find.text('Couldn’t download the Ong Log'), findsOneWidget);
      await tester.tap(find.text('Retry'));
      expect(app.notifier.songRetries, 1);
    });

    testWidgets('no catalogue at all (cleared): the Ong Log\'s loading, nothing thrown', (tester) async {
      final app = await pumpApp(tester);
      await openStats(tester);
      app.notifier.emit(const CatalogueState(isRefreshing: true));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('Loading the Ong Log…'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('the keyboard', () {
    testWidgets('↓ brings the focus to the first row, the arrows go from row to row, Enter opens it', (tester) async {
      await pumpApp(tester, desktop: true, pointer: PointerKind.mouse, size: const Size(1280, 800));
      await openStats(tester);
      String? focused() =>
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Semantics>()?.properties.label;
      // in an expanded window too, the arrows move the focus, and open nothing: the page has no detail pane
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsNothing);
      expect(focused(), 'Rank 1, I Will Survive, Gloria Gaynor, 2 plays');
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsNothing);
      expect(focused(), 'Rank 2, Lost Woods, Zelda, 1 play');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(tester.widget<SongSheet>(find.byType(SongSheet)).song.track, 'Lost Woods');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsNothing);
      expect(find.byType(StatsPage), findsOneWidget);
    });
  });
}
