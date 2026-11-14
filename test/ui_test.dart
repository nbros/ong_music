import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/view_state.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// [testCatalogue] with counts of one and two digits on the Highlights chips:
/// 10 more Game OST highlights by jsbach64, 11 more Popular ones by
/// shadowvanta. Totals: Popular 12, Game OST 11, Disney 1; jsbach64 11.
Catalogue _countedCatalogue() => testCatalogue(
  moreHighlights: [
    for (var i = 0; i < 10; i++) hRow(order: '${10 + i}', title: 'Zelda - Track $i', requester: 'jsbach64'),
    for (var i = 0; i < 11; i++)
      hRow(order: '${20 + i}', title: 'Pop Song $i', genre: 'POPULAR MUSIC', requester: 'shadowvanta'),
  ],
);

/// Pumps [_countedCatalogue] as jsbach64, the highlights titled [favourites]
/// (default: Song of Storms and "Pop Song 0" to "Pop Song 9") in the
/// favourites.
Future<TestApp> _pumpCounted(WidgetTester tester, {bool Function(String title)? favourites, Size? size}) {
  final catalogue = _countedCatalogue();
  final favourite =
      favourites ?? (t) => t == 'Zelda - Song of Storms' || t.startsWith('Pop Song') && t != 'Pop Song 10';
  return pumpApp(
    tester,
    state: CatalogueState(catalogue: catalogue, fetchedAt: testNow.subtract(const Duration(hours: 2))),
    prefs: {
      'twitchName': 'jsbach64',
      FavouritesNotifier.key: [
        for (final h in catalogue.highlights)
          if (favourite(h.title)) h.key,
      ],
    },
    size: size ?? const Size(412, 892),
  );
}

void main() {
  group('Highlights', () {
    testWidgets('lists the highlights, newest first, with genre chips', (tester) async {
      await pumpApp(tester);
      expect(find.text('Search 3 highlights'), findsOneWidget);
      final rows = tester.widgetList<HighlightRow>(find.byType(HighlightRow)).map((r) => r.highlight.track).toList();
      expect(rows, ["How Far I'll Go", 'I Will Survive', 'Song of Storms']);
      for (final label in ['All', 'Game OST', 'Popular', 'Disney']) {
        expect(chip(label), findsOneWidget, reason: label);
      }
      expect(chip('Other'), findsNothing);
      // no count line without a filter
      expect(find.textContaining('highlights'), findsOneWidget);
    });

    testWidgets('selecting a chip or typing a search does not move or resize the chips', (tester) async {
      // counts with one and two digits, that fall to 0 with "You", the star, a genre or a search;
      // wide enough for the chips tapped to be on screen (the content keeps 640 px)
      await _pumpCounted(tester, size: const Size(700, 892));
      (String, Future<void> Function()) tap(String label) => (
        'tap on $label',
        () async {
          await tester.tap(chip(label));
          await tester.pumpAndSettle();
        },
      );
      (String, Future<void> Function()) type(String query) => (
        'search "$query"',
        () async {
          await tester.enterText(searchField(), query);
          await tester.pumpAndSettle();
        },
      );
      for (final (tab, page, labels, counted, steps) in [
        (
          'Highlights',
          HighlightsPage,
          ['All', 'Favourites', 'You', 'Popular', 'Game OST', 'Disney'],
          ['Favourites', 'You', 'Popular', 'Game OST', 'Disney'],
          [
            for (final label in ['Game OST', 'You', 'Popular', 'You', 'All', 'You', 'All', 'Favourites', 'You'])
              tap(label),
            tap('Favourites'),
            type('song'),
            tap('Popular'),
            tap('Favourites'),
            type('zelda'),
            tap('You'),
            type('zelda track 1'),
            tap('All'),
            type('moana'),
            type(''),
          ],
        ),
        (
          'Ong Log',
          OngLogPage,
          ['All', 'You', 'Piano', 'Loop', 'With video'],
          <String>[],
          [
            for (final label in ['You', 'Piano', 'You', 'All', 'You', 'All']) tap(label),
          ],
        ),
      ]) {
        await goToTab(tester, tab);
        List<Rect> rects() => [for (final label in labels) tester.getRect(chip(label))];
        final list = find.descendant(of: find.byType(page), matching: find.byType(CustomScrollView));
        final before = rects();
        final shown = {
          for (final label in counted) label: <String>{chipTextOf(tester, label)},
        };
        // with any filter, the list has one place, the same with "You" and the star as with the others
        final listTops = <double>{};
        for (final (i, (step, run)) in steps.indexed) {
          await run();
          expect(rects(), before, reason: '$tab: after step $i, $step');
          for (final label in counted) {
            shown[label]!.add(chipTextOf(tester, label));
          }
          if (find.descendant(of: find.byType(page), matching: find.byType(CountLine)).evaluate().isNotEmpty) {
            listTops.add(tester.getRect(list).top);
          }
        }
        expect(listTops, hasLength(1), reason: tab);
        // the counts did change, from two digits to one and to 0
        for (final label in counted) {
          expect(shown[label]!.length, greaterThan(1), reason: '$label: $shown');
        }
        if (tab == 'Highlights') {
          expect(shown['Popular'], containsAll(['Popular  12', 'Popular  10', 'Popular  0']));
          expect(shown['You'], containsAll(['You  11', 'You  1', 'You  0']));
          expect(shown['Favourites'], containsAll(['11', '1', '0']));
        }
      }
    });

    testWidgets('filters by query, highlights hits, links to the Ong Log', (tester) async {
      await pumpApp(tester);
      await tester.enterText(searchField(), 'storms');
      await tester.pumpAndSettle();
      expect(find.byType(HighlightRow), findsOneWidget);
      expect(find.text('1 highlight'), findsOneWidget);
      final title = tester.widget<RichText>(richText('Song of Storms'));
      final marked = <String>[];
      title.text.visitChildren((span) {
        if (span is TextSpan && span.style?.backgroundColor != null) marked.add(span.text!);
        return true;
      });
      expect(marked, ['Storms']);

      await tester.tap(find.text('1 in the Ong Log →'));
      await tester.pumpAndSettle();
      expect(
        searchField().evaluate().single.widget,
        isA<TextField>().having((f) => f.controller!.text, 'text', 'storms'),
      );
      expect(find.byType(PlayRow).hitTestable(), findsOneWidget);
      expect(find.text('1 song · 1 stream'), findsOneWidget);
    });

    testWidgets('empty result says where to look', (tester) async {
      await pumpApp(tester);
      await tester.enterText(searchField(), 'lost woods');
      await tester.pumpAndSettle();
      expect(find.text('No highlight matches'), findsOneWidget);
      expect(find.text('The song may still be in the Ong Log.'), findsOneWidget);
      await tester.enterText(searchField(), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('Try fewer words.'), findsOneWidget);
      // the clear button empties the field
      await tester.tap(find.byTooltip('Clear').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(HighlightRow), findsNWidgets(3));
    });

    testWidgets('filters by genre chip', (tester) async {
      await pumpApp(tester);
      await tapVisible(tester, chip('Popular'));
      expect(find.byType(HighlightRow), findsOneWidget);
      expect(find.text('I Will Survive'), findsOneWidget);
      expect(find.text('1 highlight'), findsOneWidget);
      await tapVisible(tester, chip('All'));
      expect(find.byType(HighlightRow), findsNWidgets(3));
    });

    testWidgets('a tap opens the video, or the sheet without video', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.text('Song of Storms'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      await tester.tap(find.text("How Far I'll Go"));
      await tester.pumpAndSettle();
      expect(find.byType(HighlightSheet), findsOneWidget);
      expect(find.text('Video unavailable'), findsOneWidget);
    });
  });

  group('Ong Log', () {
    testWidgets('groups plays by stream under headers', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      expect(find.text('Search 4 songs played live'), findsOneWidget);
      expect(find.text('Sat 2 Mar 2024'), findsOneWidget);
      expect(find.text('Fri 1 Mar 2024'), findsOneWidget);
      expect(find.text('2 songs · 2 h 03'), findsOneWidget);
      expect(find.text('TIER 3'), findsOneWidget);
      final rows = tester.widgetList<PlayRow>(find.byType(PlayRow)).map((r) => r.play.title).toList();
      expect(rows, [
        'Gloria Gaynor - I Will Survive',
        'Zelda - Song of Storms',
        'Zelda - Lost Woods',
        'Gloria Gaynor - I Will Survive',
      ]);
    });

    testWidgets('filters by query and chips', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await tapVisible(tester, chip('Loop'));
      expect(find.byType(PlayRow), findsNWidgets(2));
      expect(find.text('2 songs · 2 streams'), findsOneWidget);
      await tapVisible(tester, chip('With video'));
      expect(find.byType(PlayRow), findsOneWidget);
      await tapVisible(tester, chip('All'));
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      expect(find.byType(PlayRow), findsNWidgets(2));
      await tester.enterText(searchField(), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('Never played… yet'), findsOneWidget);
    });

    testWidgets('the play button opens the video; a header opens the setlist', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      final storms = find.ancestor(of: find.text('Song of Storms').hitTestable(), matching: find.byType(PlayRow));
      await tester.tap(find.descendant(of: storms, matching: find.byType(VideoPill)));
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      expect(find.byType(StreamSheet), findsOneWidget);
      expect(find.text('Stream setlist'), findsOneWidget);
    });

    testWidgets('the pinned header stays put while the next header slides over it', (tester) async {
      // three streams of 20 plays, newest first: Sun 3, Sat 2, Fri 1 Mar 2024
      final catalogue = catalogueOf(
        songs: [
          for (var day = 1; day <= 3; day++) ...[
            start('2024-03-0$day'),
            for (var i = 0; i < 20; i++) sRow(date: '2024-03-0$day 20:${10 + i}:00', title: 'Song $day-$i'),
          ],
        ],
      );
      await pumpApp(
        tester,
        state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
      );
      await goToTab(tester, 'Ong Log');
      final list = find.descendant(of: find.byType(OngLogPage), matching: find.byType(CustomScrollView));
      final top = tester.getRect(list).top;
      final position = tester
          .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
          .position;
      final header = tester.getSize(find.byType(StreamHeader).first).height;
      final secondHeader = header + 20 * tester.getSize(find.byType(PlayRow).first).height;
      Finder headerOf(String date) => find.widgetWithText(StreamHeader, date);

      // in the middle of the first stream: its header is pinned, whole
      position.jumpTo(secondHeader / 2);
      await tester.pump();
      expect(tester.getRect(headerOf('Sun 3 Mar 2024')).top, top);
      expect(
        tester.getSize(find.ancestor(of: headerOf('Sun 3 Mar 2024'), matching: find.byType(ClipRect)).first).height,
        header,
      );

      // the next header has covered its lower half: it has not moved
      position.jumpTo(secondHeader - header / 2);
      await tester.pump();
      expect(tester.getRect(headerOf('Sun 3 Mar 2024')).top, top);
      expect(
        tester.getSize(find.ancestor(of: headerOf('Sun 3 Mar 2024'), matching: find.byType(ClipRect)).first).height,
        header / 2,
      );
      expect(tester.getRect(headerOf('Sat 2 Mar 2024')).top, top + header / 2);
      // a tap on the visible part of each header opens its own stream
      await tester.tapAt(Offset(60, top + header * 3 / 4));
      await tester.pumpAndSettle();
      expect(tester.widget<StreamSheet>(find.byType(StreamSheet)).stream.date.day, 2);
      Navigator.of(tester.element(find.byType(StreamSheet))).pop();
      await tester.pumpAndSettle();

      // the next header reached the top and took its place
      position.jumpTo(secondHeader);
      await tester.pump();
      expect(headerOf('Sun 3 Mar 2024'), findsNothing);
      for (final element in headerOf('Sat 2 Mar 2024').evaluate()) {
        expect(tester.getRect(find.byElementPredicate((e) => e == element)).top, top);
      }
    });

    testWidgets('keeps the query when switching tabs', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await tester.enterText(searchField(), 'zelda');
      await goToTab(tester, 'About');
      await goToTab(tester, 'Ong Log');
      expect(find.byType(PlayRow), findsNWidgets(2));
      await goToTab(tester, 'Highlights');
      expect(find.byType(HighlightRow), findsNWidgets(3));
    });
  });

  group('Sheets', () {
    testWidgets('without a share sheet (most browsers on a computer) "Share" is not offered, "Copy" is', (
      tester,
    ) async {
      await pumpApp(tester, canShare: false);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      expect(find.byTooltip('Share'), findsNothing);
      expect(find.byIcon(Icons.share), findsNothing);
      expect(find.byTooltip('Copy title and link'), findsOneWidget);
    });

    testWidgets('highlight sheet: facts, actions, links', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(detailsButtons().at(1)); // I Will Survive
      await tester.pumpAndSettle();
      expect(find.text('Popular · Highlight #2'), findsOneWidget);
      expect(find.text('Played live on Sat 2 Mar 2024'), findsOneWidget);
      expect(find.text('Uploaded 6 Mar 2024'), findsOneWidget);
      expect(find.text('Requested by shadowvanta'), findsOneWidget);
      expect(find.text('Played 2 times live'), findsOneWidget);
      expect(find.text('With vocals'), findsOneWidget);
      expect(find.text('An improvised arrangement.'), findsOneWidget);

      await tester.tap(find.text('Watch on YouTube'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.last.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');

      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      expect(app.effects.shared.single, 'Gloria Gaynor - I Will Survive — https://youtu.be/bbbbbbbbbbb');

      app.effects.shareWorks = false;
      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive — https://youtu.be/bbbbbbbbbbb');
      expect(find.text('Sharing isn’t available here: link copied'), findsOneWidget);
      await waitForMessage(tester);

      // "Copy" copies what "Share" shares: the title and the link
      app.effects.clipboard = null;
      await tester.tap(find.byTooltip('Copy title and link'));
      await tester.pump();
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive — https://youtu.be/bbbbbbbbbbb');
      // confirmed on the button (a check mark), not by a second notification
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byTooltip('Copied'), findsOneWidget);
      expect(find.text('Copied'), findsNothing);
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.copy), findsOneWidget);

      // a clipboard that refuses: said so, no check mark
      app.effects.clipboardWorks = false;
      await tester.tap(find.byTooltip('Copy title and link'));
      await tester.pump();
      expect(find.text('Couldn’t copy'), findsOneWidget);
      expect(find.byIcon(Icons.check), findsNothing);
      await waitForMessage(tester);
      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      expect(find.text('Sharing isn’t available here'), findsOneWidget);
      expect(app.effects.clipboard, 'Gloria Gaynor - I Will Survive — https://youtu.be/bbbbbbbbbbb');
      await waitForMessage(tester);
    });

    testWidgets('highlight without video: "Copy" copies the title alone, as "Share" shares it', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(detailsButtons().first);
      await tester.pumpAndSettle();
      expect(find.text('Video unavailable'), findsOneWidget);
      await tester.tap(find.byTooltip('Share'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Copy title'));
      await tester.pump();
      expect(app.effects.clipboard, isNotNull);
      expect(app.effects.clipboard, app.effects.shared.single);
      expect(app.effects.clipboard, isNot(contains('http')));
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
    });

    testWidgets('highlight sheet → song sheet → stream sheet, each replacing the last', (tester) async {
      await pumpApp(tester);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Played 2 times live'));
      await tester.pumpAndSettle();
      expect(find.byType(HighlightSheet), findsNothing);
      expect(find.byType(SongSheet), findsOneWidget);
      expect(find.text('Every time it was played'), findsOneWidget);
      expect(find.text('first played'), findsOneWidget);
      // every play, newest first, with stream dates
      final dates = tester.widgetList<HistoryRow>(find.byType(HistoryRow)).map((r) => r.play.id).toList();
      expect(dates, [3, 0]);
      expect(find.text('Sat 2 Mar 2024'), findsOneWidget);
      expect(find.text('MannyHub'), findsOneWidget);

      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsNothing);
      final tinted = tester.widgetList<PlayRow>(find.byType(PlayRow)).where((r) => r.tinted).toList();
      expect(tinted.single.play.id, 0);
    });

    testWidgets('played-live fact opens the stream with that play tinted', (tester) async {
      await pumpApp(tester);
      await tester.tap(detailsButtons().at(2)); // Song of Storms
      await tester.pumpAndSettle();
      await tester.tap(find.text('Played live on Sat 2 Mar 2024'));
      await tester.pumpAndSettle();
      final tinted = tester.widgetList<PlayRow>(find.byType(PlayRow)).where((r) => r.tinted).toList();
      expect(tinted.single.play.title, 'Zelda - Song of Storms');
      expect(tester.takeException(), isNull);
    });

    testWidgets('a requester opens the Ong Log on their requests, filters reset', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await tapVisible(tester, chip('Loop'));
      await goToTab(tester, 'Highlights');
      await tester.tap(detailsButtons().at(2));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Requested by jsbach64'));
      await tester.pumpAndSettle();
      expect(find.byType(HighlightSheet), findsNothing);
      expect(
        searchField().evaluate().single.widget,
        isA<TextField>().having((f) => f.controller!.text, 'text', 'jsbach64'),
      );
      expect(find.byType(PlayRow).hitTestable(), findsNWidgets(2));
      expect(find.text('2 songs · 2 streams'), findsOneWidget);
    });
  });

  group('Highlights chip counts', () {
    Map<String, String> counts(WidgetTester tester) => {
      for (final label in ['Favourites', 'You', 'Popular', 'Game OST', 'Disney']) label: chipTextOf(tester, label),
    };
    Map<String, String> expected(int favourites, int you, int popular, int gameOst, int disney) => {
      'Favourites': '$favourites',
      'You': 'You  $you',
      'Popular': 'Popular  $popular',
      'Game OST': 'Game OST  $gameOst',
      'Disney': 'Disney  $disney',
    };
    Future<void> tap(WidgetTester tester, String label) async {
      await tester.tap(chip(label));
      await tester.pumpAndSettle();
    }

    Future<void> search(WidgetTester tester, String query) async {
      await tester.enterText(searchField(), query);
      await tester.pumpAndSettle();
    }

    testWidgets('each count is what the list would show with that chip selected', (tester) async {
      await _pumpCounted(tester, size: const Size(700, 892));
      // nothing filtered: the totals
      expect(counts(tester), expected(11, 11, 12, 11, 1));
      // the search: "Pop Song …" and Song of Storms
      await search(tester, 'song');
      expect(counts(tester), expected(11, 1, 11, 1, 0));
      expect(find.text('12 highlights'), findsOneWidget);
      await search(tester, '');
      // "You": the genres, the star; its own count is the length of the list
      await tap(tester, 'You');
      expect(counts(tester), expected(1, 11, 0, 11, 0));
      expect(find.text('11 highlights'), findsOneWidget);
      // "You" and the star
      await tap(tester, 'Favourites');
      expect(counts(tester), expected(1, 1, 0, 1, 0));
      expect(find.text('1 highlight'), findsOneWidget);
      // the star alone
      await tap(tester, 'You');
      expect(counts(tester), expected(11, 1, 10, 1, 0));
      expect(find.text('11 highlights'), findsOneWidget);
      // the star and a genre: the other genres do not follow the genre selected
      await tap(tester, 'Popular');
      expect(counts(tester), expected(10, 0, 10, 1, 0));
      expect(find.text('10 highlights'), findsOneWidget);
      // a genre alone
      await tap(tester, 'Favourites');
      expect(counts(tester), expected(10, 0, 12, 11, 1));
      expect(find.text('12 highlights'), findsOneWidget);
      // a genre and the search
      await search(tester, 'pop song 1');
      expect(counts(tester), expected(1, 0, 2, 0, 0));
      expect(find.text('2 highlights'), findsOneWidget);
      // the search, the genre, "You" and the star together
      await search(tester, 'zelda');
      await tap(tester, 'Game OST');
      await tap(tester, 'You');
      await tap(tester, 'Favourites');
      expect(counts(tester), expected(1, 1, 0, 1, 0));
      // "All" clears the chips, the search stays
      await tap(tester, 'All');
      expect(counts(tester), expected(1, 11, 0, 11, 0));
    });

    testWidgets('screen readers hear the count shown', (tester) async {
      final semantics = tester.ensureSemantics();
      await _pumpCounted(tester);
      expect(tester.getSemantics(chip('Popular')), isSemantics(label: 'Popular  12', isButton: true));
      expect(tester.getSemantics(chip('Favourites')), isSemantics(label: 'Favourites\n11', isButton: true));
      await tap(tester, 'You');
      expect(tester.getSemantics(chip('Popular')), isSemantics(label: 'Popular  0', isButton: true));
      expect(tester.getSemantics(chip('Favourites')), isSemantics(label: 'Favourites\n1', isButton: true));
      expect(
        tester.getSemantics(chip('You')),
        isSemantics(label: 'You  11', isButton: true, isSelected: true, hasSelectedState: true),
      );
      semantics.dispose();
    });

    testWidgets('a chip whose count falls to 0 stays in place, and can be selected', (tester) async {
      await _pumpCounted(tester, size: const Size(700, 892));
      final popular = tester.getRect(chip('Popular'));
      await tap(tester, 'You');
      expect(chipTextOf(tester, 'Popular'), 'Popular  0');
      expect(tester.getRect(chip('Popular')), popular);
      await tap(tester, 'Popular');
      expect(chipTextOf(tester, 'Popular'), 'Popular  0');
      expect(find.text('0 highlights'), findsOneWidget);
      expect(find.text('No highlight matches'), findsOneWidget);
      // the star and "You" at 0 stay too
      await tap(tester, 'All');
      await search(tester, 'moana');
      expect((chipTextOf(tester, 'Favourites'), chipTextOf(tester, 'You')), ('0', 'You  0'));
    });

    testWidgets('the star chip gone, its filter no longer narrows the counts', (tester) async {
      final app = await _pumpCounted(tester, favourites: (t) => t == 'Zelda - Song of Storms');
      await tap(tester, 'Favourites');
      expect(counts(tester), expected(1, 1, 0, 1, 0));
      final container = ProviderScope.containerOf(tester.element(find.byType(OngMusicApp)));
      final catalogue = container.read(currentCatalogueProvider)!;
      await container
          .read(favouritesProvider.notifier)
          .toggle(catalogue.highlights.firstWhere((h) => h.title == 'Zelda - Song of Storms'));
      await tester.pumpAndSettle();
      expect(chip('Favourites'), findsNothing);
      expect({
        for (final label in ['You', 'Popular', 'Game OST', 'Disney']) label: chipTextOf(tester, label),
      }, expected(0, 11, 12, 11, 1)..remove('Favourites'));
      expect(find.byType(HighlightRow), findsWidgets);
      expect(app.prefs.getStringList(FavouritesNotifier.key), isEmpty);
    });

    testWidgets('the "You" chip gone, its filter no longer narrows the counts', (tester) async {
      await _pumpCounted(tester);
      await tap(tester, 'You');
      expect(chipTextOf(tester, 'Popular'), 'Popular  0');
      // MannyHub requested a play, no highlight: a requester whose filter would keep nothing
      for (final name in ['mannyhub', 'nobody']) {
        await goToTab(tester, 'About');
        await tester.enterText(find.descendant(of: find.byType(AboutPage), matching: find.byType(TextField)), name);
        await tester.pump();
        await goToTab(tester, 'Highlights');
        expect(chip('You'), findsNothing, reason: name);
        expect(
          (chipTextOf(tester, 'Favourites'), chipTextOf(tester, 'Popular'), chipTextOf(tester, 'Game OST')),
          ('11', 'Popular  12', 'Game OST  11'),
          reason: name,
        );
      }
    });
  });

  group('"You" chip', () {
    bool selected(WidgetTester tester, String label) => tester.widget<FilterChip>(chip(label)).selected;

    Finder twitchNameField() => find.descendant(of: find.byType(AboutPage), matching: find.byType(TextField));
    ProviderContainer container(WidgetTester tester) =>
        ProviderScope.containerOf(tester.element(find.byType(OngMusicApp)));

    testWidgets('keeps only the user’s requests, placed and drawn like its neighbours', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'JSBACH64'});
      // Highlights: after "All", before the genres, with its count
      expect(chipTextOf(tester, 'You'), 'You  1');
      expect(find.descendant(of: chip('You'), matching: find.byIcon(Icons.person)), findsOneWidget);
      expect(tester.getRect(chip('You')).left, greaterThan(tester.getRect(chip('All')).right));
      expect(tester.getRect(chip('You')).right, lessThan(tester.getRect(chip('Game OST')).left));
      expect(selected(tester, 'You'), isFalse);
      await tester.tap(chip('You'));
      await tester.pumpAndSettle();
      expect(tester.widgetList<HighlightRow>(find.byType(HighlightRow)).map((r) => r.highlight.track), [
        'Song of Storms',
      ]);
      expect((selected(tester, 'You'), selected(tester, 'All')), (true, false));
      expect(find.text('1 highlight'), findsOneWidget);

      // Ong Log: right after "All" too, before the types, without count
      await goToTab(tester, 'Ong Log');
      expect(chipTextOf(tester, 'You'), 'You');
      expect(find.descendant(of: chip('You'), matching: find.byIcon(Icons.person)), findsOneWidget);
      expect(tester.getRect(chip('You')).left, greaterThan(tester.getRect(chip('All')).right));
      expect(tester.getRect(chip('You')).right, lessThan(tester.getRect(chip('Piano')).left));
      expect(tester.getRect(chip('Popular')).left, greaterThan(tester.getRect(find.byType(ChipSeparator)).right));
      await tapVisible(tester, chip('You'));
      expect(tester.widgetList<PlayRow>(find.byType(PlayRow)).map((r) => r.play.title), [
        'Zelda - Song of Storms',
        'Zelda - Lost Woods',
      ]);
      expect((selected(tester, 'You'), selected(tester, 'All')), (true, false));
      expect(find.text('2 songs · 2 streams'), findsOneWidget);
    });

    testWidgets('shows only in a list holding requests of the user', (tester) async {
      await pumpApp(tester);
      expect(chip('You'), findsNothing);
      await goToTab(tester, 'Ong Log');
      expect(chip('You'), findsNothing);
      // MannyHub requested a play, no highlight
      await goToTab(tester, 'About');
      await tester.enterText(twitchNameField(), 'mannyhub');
      await tester.pump();
      await goToTab(tester, 'Ong Log');
      expect(chip('You'), findsOneWidget);
      await goToTab(tester, 'Highlights');
      expect(chip('You'), findsNothing);
      // no request under that name
      await goToTab(tester, 'About');
      await tester.enterText(twitchNameField(), 'nobody');
      await tester.pump();
      await goToTab(tester, 'Ong Log');
      expect(chip('You'), findsNothing);
      await goToTab(tester, 'Highlights');
      expect(chip('You'), findsNothing);
    });

    testWidgets('combines with the search and the other chips; "All" clears it', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      Future<void> tap(String label) => tapVisible(tester, chip(label));
      Future<void> search(String query) async {
        await tester.enterText(searchField(), query);
        await tester.pumpAndSettle();
      }

      // Highlights: jsbach64 requested "Song of Storms" (Game OST)
      int highlights() => find.byType(HighlightRow).evaluate().length;
      await tap('You');
      await search('zelda');
      expect(highlights(), 1);
      await search('');
      expect(highlights(), 1, reason: 'a query change keeps "You"');
      await tap('Popular');
      expect(highlights(), 0, reason: 'genre and "You" together');
      await tap('Popular');
      expect(highlights(), 1, reason: 'a genre change keeps "You"');
      await tap('All');
      expect(highlights(), 3);
      expect((selected(tester, 'All'), selected(tester, 'You')), (true, false));
      expect(find.text('3 highlights'), findsNothing, reason: 'no count line without filter');

      // Ong Log: jsbach64 requested two piano plays, one with a video
      await goToTab(tester, 'Ong Log');
      int plays() => find.byType(PlayRow).evaluate().length;
      await tap('You');
      expect(plays(), 2);
      await tap('Loop');
      expect(plays(), 0, reason: 'type and "You" together');
      await tap('Loop');
      expect(plays(), 2);
      await tap('With video');
      expect(plays(), 1, reason: 'with video and "You" together');
      await tap('With video');
      await tap('Popular');
      expect(plays(), 0, reason: 'genre and "You" together');
      await tap('Popular');
      expect(plays(), 2);
      await search('z');
      await search('');
      expect(plays(), 2, reason: 'a query change keeps "You"');
      await tap('All');
      expect(plays(), 4);
      expect((selected(tester, 'All'), selected(tester, 'You')), (true, false));
      expect(find.text('4 songs · 2 streams'), findsNothing, reason: 'no count line without filter');
    });

    testWidgets('leaves no filter behind when it goes away', (tester) async {
      final app = await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      Future<void> selectBoth() async {
        await goToTab(tester, 'Highlights');
        await tapVisible(tester, chip('You'));
        expect(find.byType(HighlightRow), findsOneWidget);
        await goToTab(tester, 'Ong Log');
        await tapVisible(tester, chip('You'));
        expect(find.byType(PlayRow), findsNWidgets(2));
      }

      Future<void> expectUnfiltered() async {
        await goToTab(tester, 'Highlights');
        expect(chip('You'), findsNothing);
        expect(find.byType(HighlightRow), findsNWidgets(3));
        expect(selected(tester, 'All'), isTrue);
        expect(find.textContaining('highlights'), findsOneWidget, reason: 'the search hint, no count line');
        await goToTab(tester, 'Ong Log');
        expect(chip('You'), findsNothing);
        expect(find.byType(PlayRow), findsNWidgets(4));
        expect(selected(tester, 'All'), isTrue);
        expect(container(tester).read(highlightFilterProvider).mine, isFalse);
        expect(container(tester).read(playFilterProvider).mine, isFalse);
      }

      Future<void> expectBackUnselected() async {
        await goToTab(tester, 'Highlights');
        expect(selected(tester, 'You'), isFalse);
        expect(find.byType(HighlightRow), findsNWidgets(3));
        await goToTab(tester, 'Ong Log');
        expect(selected(tester, 'You'), isFalse);
        expect(find.byType(PlayRow), findsNWidgets(4));
      }

      // the name is cleared, then typed again
      await selectBoth();
      await goToTab(tester, 'About');
      await tester.enterText(twitchNameField(), '');
      await tester.pump();
      await expectUnfiltered();
      await goToTab(tester, 'About');
      await tester.enterText(twitchNameField(), 'jsbach64');
      await tester.pump();
      await expectBackUnselected();

      // a refresh brings a catalogue without their requests, then one with them
      await selectBoth();
      final state = app.notifier.initial;
      app.notifier.emit(CatalogueState(catalogue: catalogueOf(), fetchedAt: testNow));
      await tester.pumpAndSettle();
      await goToTab(tester, 'Highlights');
      expect(chip('You'), findsNothing);
      expect(find.byType(HighlightRow), findsOneWidget, reason: 'the one highlight of the new catalogue');
      expect(container(tester).read(highlightFilterProvider).mine, isFalse);
      expect(container(tester).read(playFilterProvider).mine, isFalse);
      app.notifier.emit(state);
      await tester.pumpAndSettle();
      await expectBackUnselected();
    });

    testWidgets('links to the Ong Log reset it', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      await goToTab(tester, 'Ong Log');
      await tapVisible(tester, chip('You'));
      // "N in the Ong Log →": two plays of "I Will Survive", none requested by jsbach64
      await goToTab(tester, 'Highlights');
      await tester.enterText(searchField(), 'survive');
      await tester.pumpAndSettle();
      await tester.tap(find.text('2 in the Ong Log →'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayRow).hitTestable(), findsNWidgets(2));
      expect(selected(tester, 'You'), isFalse);

      // "Requested by shadowvanta" in a highlight sheet
      await tapVisible(tester, chip('You'));
      expect(find.byType(PlayRow).hitTestable(), findsNothing);
      await goToTab(tester, 'Highlights');
      await tester.enterText(searchField(), '');
      await tester.pumpAndSettle();
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Requested by shadowvanta'));
      await tester.pumpAndSettle();
      expect(find.byType(PlayRow).hitTestable(), findsOneWidget);
      expect(selected(tester, 'You'), isFalse);
    });
  });

  group('About', () {
    testWidgets('theme switch applies and persists', (tester) async {
      final app = await pumpApp(tester, prefs: {'themeMode': 'dark'});
      await goToTab(tester, 'About');
      expect(Theme.of(tester.element(find.text('Jonathan Ong'))).brightness, Brightness.dark);
      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(Theme.of(tester.element(find.text('Jonathan Ong'))).brightness, Brightness.light);
      expect(app.prefs.getString('themeMode'), 'light');
    });

    testWidgets('Twitch name helper texts', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'About');
      final field = find.widgetWithText(TextField, 'Optional');
      expect(find.text('Your name will show in orange in every list.'), findsOneWidget);
      await tester.enterText(field, 'JSBach64 ');
      await tester.pump();
      expect(
        find.text('Found 2 requests by jsbach64, now in orange. Tap the “You” chip to see only yours.'),
        findsOneWidget,
      );
      expect(app.prefs.getString('twitchName'), 'JSBach64');
      await tester.enterText(field, 'nobody');
      await tester.pump();
      expect(find.text('No request under that name yet.'), findsOneWidget);
      await tester.enterText(field, '');
      await tester.pump();
      expect(find.text('Your name will show in orange in every list.'), findsOneWidget);
      expect(app.prefs.containsKey('twitchName'), isFalse);
    });

    testWidgets('data: counts, refresh, clear with confirmation, links', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'About');
      await tester.scrollUntilVisible(find.text('Clear downloaded data'), 200, scrollable: aboutScrollable());
      expect(find.text('Updated 2 hours ago'), findsOneWidget);
      expect(find.text('4 songs · 2 streams'), findsOneWidget);
      expect(find.textContaining('at most every 6 hours'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      expect(app.notifier.refreshes, 1);

      final clear = find.widgetWithText(TextButton, 'Clear');
      await tapVisible(tester, clear);
      expect(find.text('Clear downloaded data?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(app.notifier.clears, 0);
      await tapVisible(tester, clear);
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Clear')));
      await tester.pumpAndSettle();
      expect(app.notifier.clears, 1);

      await tester.scrollUntilVisible(find.text('Privacy policy'), 200, scrollable: aboutScrollable());
      await tester.tap(find.text('Privacy policy'));
      await tester.tap(find.text('Community spreadsheet'));
      expect(app.effects.opened.map((u) => u.toString()), [
        'https://ongmusic.nbros.dev/privacy-policy',
        'https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4',
      ]);
    });

    testWidgets('refreshing and failed refresh are shown in the data row', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'About');
      final catalogue = app.notifier.state.catalogue;
      app.notifier.emit(CatalogueState(catalogue: catalogue, fetchedAt: testNow, isRefreshing: true));
      await tester.pump();
      await tester.scrollUntilVisible(find.text('Clear downloaded data'), 200, scrollable: aboutScrollable());
      expect(find.text('Updating…'), findsOneWidget);
      app.notifier.emit(
        CatalogueState(
          catalogue: catalogue,
          fetchedAt: testNow,
          lastError: SheetHttpException(Uri.parse('https://x'), 503),
        ),
      );
      await tester.pump();
      expect(find.text('Updated just now'), findsOneWidget);
      expect(
        find.textContaining('The last refresh failed. Google Sheets answered with an error (HTTP 503).'),
        findsOneWidget,
      );
    });

    testWidgets('the footer opens the licences of the software the app is made with', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'About');
      await tester.scrollUntilVisible(find.text('Licences'), 200, scrollable: aboutScrollable());
      await tester.tap(find.text('Licences'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<LicensePage>(find.byType(LicensePage)).applicationName,
        'Ong Music',
        reason: 'not the name of the package',
      );
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsNothing);
      expect(tester.widget<NavigationBar>(find.byType(NavigationBar)).selectedIndex, 2);
    });

    testWidgets('link tiles open their sites', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'About');
      await tester.tap(find.text('Watch on Twitch'));
      await tester.tap(find.text('Stickers'));
      expect(app.effects.opened.map((u) => u.toString()), [
        'https://www.twitch.tv/jonathanong',
        'https://stukem.com/collections/jonathanong',
      ]);
    });

    testWidgets('a link that nothing can open: said so', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'About');
      app.effects.openWorks = false;
      await tester.tap(find.text('Stickers'));
      await tester.pump();
      expect(find.text('Couldn’t open the link'), findsOneWidget);
      await waitForMessage(tester);
    });
  });

  group('Loading', () {
    testWidgets('first download: progress', (tester) async {
      await pumpApp(tester, state: CatalogueState(isRefreshing: true), settle: false);
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      expect(find.text('Loading the highlights…').hitTestable(), findsOneWidget);
    });

    testWidgets('first download failed: message and Retry', (tester) async {
      final app = await pumpApp(
        tester,
        state: CatalogueState(lastError: Exception('SocketException: failed host lookup')),
      );
      expect(find.text('Couldn’t download the highlights').hitTestable(), findsOneWidget);
      expect(
        find.text('Couldn’t reach Google Sheets. Check your connection and try again.').hitTestable(),
        findsOneWidget,
      );
      expect(find.textContaining('SocketException'), findsNothing);
      await tester.tap(find.text('Retry').hitTestable());
      expect(app.notifier.refreshes, 1);
      // About still works without data
      await goToTab(tester, 'About');
      await tester.scrollUntilVisible(find.text('Not downloaded yet'), 200, scrollable: aboutScrollable());
      expect(find.textContaining('The last refresh failed.'), findsOneWidget);
    });

    testWidgets('background refresh: thin progress bar, list kept', (tester) async {
      final app = await pumpApp(tester);
      app.notifier.emit(
        CatalogueState(catalogue: app.notifier.state.catalogue, fetchedAt: testNow, isRefreshing: true),
      );
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsOneWidget);
      expect(find.byType(HighlightRow), findsNWidgets(3));
    });

    testWidgets('pull to refresh calls refresh', (tester) async {
      final app = await pumpApp(tester);
      await tester.fling(find.text('Song of Storms'), const Offset(0, 400), 1000);
      await tester.pumpAndSettle();
      expect(app.notifier.refreshes, 1);
    });

    testWidgets('resuming the app checks for stale data', (tester) async {
      final app = await pumpApp(tester);
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
      expect(app.notifier.staleChecks, 1);
      expect(app.notifier.foreground, [true, false, false, false, true, true]);
    });

    testWidgets('an app that starts in the background (a tab opened behind another) says so at once', (tester) async {
      // no lifecycle event tells it: the automatic refreshes would run in a tab nobody looks at
      final hidden = await pumpApp(tester, startsInBackground: true);
      expect(hidden.notifier.foreground, [false]);
      await tester.pumpWidget(const SizedBox());
      final shown = await pumpApp(tester);
      expect(shown.notifier.foreground, isEmpty);
    });
  });

  group('Back button', () {
    testWidgets('goes back to Highlights first, then leaves the app', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'About');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(app.effects.exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.effects.exits, 1);
    });

    testWidgets('closes an open sheet and stays on the tab', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      expect(find.byType(StreamSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(StreamSheet), findsNothing);
      expect(selectedTab(tester), 1);
      expect(app.effects.exits, 0);
    });
  });

  group('Scroll position', () {
    // [days] streams of 20 plays and 20 highlights per day, newest first
    Catalogue catalogueOfDays(int days) => catalogueOf(
      highlights: [
        for (var day = 1; day <= days; day++)
          for (var i = 0; i < 20; i++)
            hRow(order: '${day * 100 + i}', title: 'Video d$day n$i', upload: '2024-03-0$day'),
      ],
      songs: [
        for (var day = 1; day <= days; day++) ...[
          start('2024-03-0$day'),
          for (var i = 0; i < 20; i++) sRow(date: '2024-03-0$day 20:${10 + i}:00', title: 'Song d$day n$i'),
        ],
      ],
    );
    CatalogueState stateOfDays(int days) => CatalogueState(catalogue: catalogueOfDays(days), fetchedAt: testNow);

    Finder listOf(Type page) => find.descendant(of: find.byType(page), matching: find.byType(CustomScrollView));
    ScrollPosition positionOf(WidgetTester tester, Type page) =>
        tester.state<ScrollableState>(find.descendant(of: listOf(page), matching: find.byType(Scrollable))).position;

    /// The row of [finder] crossing the top edge of the list of [page], and
    /// how much of it is above that edge (0 to 1).
    (Widget, double) rowAtTop(WidgetTester tester, Type page, Finder finder) {
      final top = tester.getRect(listOf(page)).top;
      for (final element in finder.evaluate()) {
        final rect = tester.getRect(find.byElementPredicate((e) => e == element));
        if (rect.top <= top && top < rect.bottom) return (element.widget, (top - rect.top) / rect.height);
      }
      fail('No row at the top of the list');
    }

    testWidgets('Ong Log: a refresh adding plays keeps the rows on screen in place', (tester) async {
      final app = await pumpApp(tester, state: stateOfDays(2));
      await goToTab(tester, 'Ong Log');
      final position = positionOf(tester, OngLogPage);
      // at the top: stays at the top, the new stream shows up
      app.notifier.emit(stateOfDays(3));
      await tester.pump();
      expect(position.pixels, 0);
      expect(find.text('Sun 3 Mar 2024'), findsOneWidget);

      position.jumpTo(777);
      await tester.pump();
      final (row, hidden) = rowAtTop(tester, OngLogPage, find.byType(PlayRow));
      app.notifier.emit(stateOfDays(4));
      await tester.pump();
      final (rowAfter, hiddenAfter) = rowAtTop(tester, OngLogPage, find.byType(PlayRow));
      expect((rowAfter as PlayRow).play.title, (row as PlayRow).play.title);
      expect(hiddenAfter, closeTo(hidden, 1e-6));
      expect(position.pixels, greaterThan(777));
      // the pinned header followed
      expect(find.text('Sun 3 Mar 2024').hitTestable(), findsOneWidget);
      expect(find.text('Mon 4 Mar 2024'), findsNothing);
    });

    testWidgets('Ong Log: a text size change keeps the row at the top in place', (tester) async {
      await pumpApp(tester, state: stateOfDays(3));
      await goToTab(tester, 'Ong Log');
      final position = positionOf(tester, OngLogPage);
      position.jumpTo(1234);
      await tester.pump();
      final (row, hidden) = rowAtTop(tester, OngLogPage, find.byType(PlayRow));
      final height = tester.getSize(find.byType(PlayRow).first).height;
      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      await tester.pump();
      expect(tester.getSize(find.byType(PlayRow).first).height, greaterThan(height));
      final (rowAfter, hiddenAfter) = rowAtTop(tester, OngLogPage, find.byType(PlayRow));
      expect((rowAfter as PlayRow).play.title, (row as PlayRow).play.title);
      expect(hiddenAfter, closeTo(hidden, 1e-6));
    });

    testWidgets('Highlights: a refresh adding highlights keeps the rows on screen in place', (tester) async {
      final app = await pumpApp(tester, state: stateOfDays(2));
      final position = positionOf(tester, HighlightsPage);
      app.notifier.emit(stateOfDays(3));
      await tester.pump();
      expect(position.pixels, 0);
      expect(find.text('Video d3 n19'), findsOneWidget);

      position.jumpTo(777);
      await tester.pump();
      final (row, hidden) = rowAtTop(tester, HighlightsPage, find.byType(HighlightRow));
      app.notifier.emit(stateOfDays(4));
      await tester.pump();
      final (rowAfter, hiddenAfter) = rowAtTop(tester, HighlightsPage, find.byType(HighlightRow));
      expect((rowAfter as HighlightRow).highlight.title, (row as HighlightRow).highlight.title);
      expect(hiddenAfter, closeTo(hidden, 1e-6));
    });

    testWidgets('Highlights: a text size change keeps the row at the top in place', (tester) async {
      await pumpApp(tester, state: stateOfDays(3));
      final position = positionOf(tester, HighlightsPage);
      position.jumpTo(1234);
      await tester.pump();
      final (row, hidden) = rowAtTop(tester, HighlightsPage, find.byType(HighlightRow));
      final height = tester.getSize(find.byType(HighlightRow).first).height;
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      await tester.pump();
      expect(tester.getSize(find.byType(HighlightRow).first).height, greaterThan(height));
      final (rowAfter, hiddenAfter) = rowAtTop(tester, HighlightsPage, find.byType(HighlightRow));
      expect((rowAfter as HighlightRow).highlight.title, (row as HighlightRow).highlight.title);
      expect(hiddenAfter, closeTo(hidden, 1e-6));
    });

    testWidgets('a refresh and a text size change in the same frame keep the row at the top in place', (tester) async {
      final app = await pumpApp(tester, state: stateOfDays(3));
      positionOf(tester, HighlightsPage).jumpTo(777);
      await tester.pump();
      final (highlight, highlightHidden) = rowAtTop(tester, HighlightsPage, find.byType(HighlightRow));
      await goToTab(tester, 'Ong Log');
      positionOf(tester, OngLogPage).jumpTo(1234);
      await tester.pump();
      final (play, playHidden) = rowAtTop(tester, OngLogPage, find.byType(PlayRow));

      tester.platformDispatcher.textScaleFactorTestValue = 1.5;
      app.notifier.emit(stateOfDays(4));
      await tester.pump();
      final (playAfter, playHiddenAfter) = rowAtTop(tester, OngLogPage, find.byType(PlayRow));
      expect((playAfter as PlayRow).play.title, (play as PlayRow).play.title);
      expect(playHiddenAfter, closeTo(playHidden, 1e-6));
      await goToTab(tester, 'Highlights');
      final (highlightAfter, highlightHiddenAfter) = rowAtTop(tester, HighlightsPage, find.byType(HighlightRow));
      expect((highlightAfter as HighlightRow).highlight.title, (highlight as HighlightRow).highlight.title);
      expect(highlightHiddenAfter, closeTo(highlightHidden, 1e-6));
    });

    testWidgets('switching tabs keeps the position of both lists', (tester) async {
      await pumpApp(tester, state: stateOfDays(3));
      positionOf(tester, HighlightsPage).jumpTo(555);
      await goToTab(tester, 'Ong Log');
      positionOf(tester, OngLogPage).jumpTo(1234);
      await goToTab(tester, 'About');
      await goToTab(tester, 'Ong Log');
      expect(positionOf(tester, OngLogPage).pixels, 1234);
      await goToTab(tester, 'Highlights');
      expect(positionOf(tester, HighlightsPage).pixels, 555);
    });

    testWidgets('a refresh that changes nothing does not move the lists', (tester) async {
      final catalogue = catalogueOfDays(3);
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
      );
      positionOf(tester, HighlightsPage).jumpTo(555);
      await goToTab(tester, 'Ong Log');
      positionOf(tester, OngLogPage).jumpTo(1234);
      await tester.pump();
      app.notifier.emit(CatalogueState(catalogue: catalogue, fetchedAt: testNow, isRefreshing: true));
      await tester.pump();
      app.notifier.emit(CatalogueState(catalogue: catalogue, fetchedAt: testNow.add(const Duration(minutes: 1))));
      await tester.pump();
      expect(positionOf(tester, OngLogPage).pixels, 1234);
      await goToTab(tester, 'Highlights');
      expect(positionOf(tester, HighlightsPage).pixels, 555);
    });

    testWidgets('a filter change goes back to the top', (tester) async {
      await pumpApp(tester, state: stateOfDays(3));
      await goToTab(tester, 'Ong Log');
      final position = positionOf(tester, OngLogPage);
      position.jumpTo(1234);
      await tester.pump();
      await tester.tap(chip('Piano'));
      await tester.pumpAndSettle();
      expect(position.pixels, 0);
    });

    testWidgets('"You" goes back to the top too', (tester) async {
      // 100 highlights and plays, every other one requested by jsbach64
      final catalogue = catalogueOf(
        highlights: [
          for (var i = 0; i < 100; i++)
            hRow(order: '${i + 1}', title: 'Video $i', requester: i.isEven ? 'jsbach64' : 'someone'),
        ],
        songs: [
          start('2024-03-01'),
          for (var i = 0; i < 100; i++)
            sRow(date: '2024-03-01 20:00:00', title: 'Song $i', requester: i.isEven ? 'jsbach64' : 'someone'),
        ],
      );
      await pumpApp(
        tester,
        state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
        prefs: {'twitchName': 'jsbach64'},
      );
      for (final (tab, page) in [('Highlights', HighlightsPage), ('Ong Log', OngLogPage)]) {
        await goToTab(tester, tab);
        final position = positionOf(tester, page);
        position.jumpTo(1234);
        await tester.pump();
        // brings the chip on screen without moving the list
        await tapVisible(tester, chip('You'));
        expect(position.pixels, 0, reason: tab);
      }
    });
  });

  group('Large text and wide screens', () {
    for (final scale in [1.3, 2.0]) {
      testWidgets('no overflow at text scale $scale', (tester) async {
        await pumpApp(tester, textScale: scale, prefs: {'twitchName': 'jsbach64'});
        expect(tester.takeException(), isNull);
        await tester.tap(detailsButtons().at(1));
        await tester.pumpAndSettle();
        await tapVisible(tester, find.text('Played 2 times live'));
        await tapVisible(tester, find.text('Fri 1 Mar 2024'));
        expect(tester.takeException(), isNull);
        Navigator.of(tester.element(find.byType(StreamSheet))).pop();
        await tester.pumpAndSettle();
        await goToTab(tester, 'Ong Log');
        await goToTab(tester, 'About');
        await tester.drag(find.text('Jonathan Ong'), const Offset(0, -2000));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('wide and low window: a list keeps a column of 720 px, centred right of the rail', (tester) async {
      // (too low for the list and detail panes of an expanded window)
      await pumpApp(tester, size: const Size(1400, 470));
      final list = tester.getRect(find.byType(CustomScrollView).first);
      expect(list.width, 720);
      expect(list.center.dx, 80 + (1400 - 80) / 2);
    });
  });
}
