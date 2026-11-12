// The favourites in the UI: the star of a highlight sheet, the star chip of
// the Highlights list.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/settings_state.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/theme.dart';
import 'package:ong_music/src/ui/view_state.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

const _key = FavouritesNotifier.key;

/// The preferences holding [titles] (tracks of [testCatalogue]) as favourites.
Map<String, Object> _favourites(List<String> tracks) {
  final highlights = testCatalogue().highlights;
  return {
    _key: [for (final track in tracks) highlights.firstWhere((h) => h.track == track).key],
  };
}

/// Opens the sheet of the highlight row showing [track].
Future<void> _openSheet(WidgetTester tester, String track) async {
  final row = find.ancestor(of: find.text(track), matching: find.byType(HighlightRow));
  await tester.tap(find.descendant(of: row, matching: find.byTooltip('Details')));
  await tester.pumpAndSettle();
}

/// Closes the sheet on screen.
Future<void> _closeSheet(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(HighlightSheet))).pop();
  await tester.pumpAndSettle();
}

Finder _inSheet(Finder finder) => find.descendant(of: find.byType(HighlightSheet), matching: finder);

/// The star of the sheet on screen, as a button.
Finder _star() => _inSheet(
  find.byWidgetPredicate(
    (w) => w is IconButton && (w.tooltip == 'Add to favourites' || w.tooltip == 'Remove from favourites'),
  ),
);

/// The Copy button of the sheet on screen.
Finder _copy() => _inSheet(find.widgetWithIcon(IconButton, Icons.copy));

/// The title of the sheet on screen (selectable, so an editable text).
Finder _title() => _inSheet(find.byType(SelectableText)).first;

/// The room of the title and the artist: the title wraps at its right edge.
Finder _titleBlock() => find.ancestor(of: _title(), matching: find.byType(Expanded)).first;

/// The artist line of the sheet on screen.
Finder _artist(String artist) => _inSheet(find.text(artist));

Future<void> _tapStar(WidgetTester tester) async {
  await tester.tap(_star());
  await tester.pumpAndSettle();
}

ProviderContainer _container(WidgetTester tester) =>
    ProviderScope.containerOf(tester.element(find.byType(OngMusicApp)));

bool _selected(WidgetTester tester, String label) => tester.widget<FilterChip>(chip(label)).selected;

List<String> _tracks(WidgetTester tester) =>
    tester.widgetList<HighlightRow>(find.byType(HighlightRow)).map((r) => r.highlight.track).toList();

void main() {
  group('The star of a highlight sheet', () {
    testWidgets('a toggle beside the title, in line with Copy, stored at once', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpApp(tester);
      await _openSheet(tester, 'Song of Storms');
      expect(_star(), findsOneWidget);
      expect(_inSheet(find.byIcon(Icons.star_border)), findsOneWidget);
      expect(_inSheet(find.byIcon(Icons.star)), findsNothing);
      // a plain icon button, not a tonal circle like the actions below it
      final starMaterial = tester.widget<Material>(find.descendant(of: _star(), matching: find.byType(Material)).first);
      expect(starMaterial.color, Colors.transparent);
      expect(
        tester.getSemantics(_star()),
        isSemantics(
          isButton: true,
          hasToggledState: true,
          isToggled: false,
          tooltip: 'Add to favourites',
          hasTapAction: true,
        ),
      );

      // 48 px under the finger, its right edge in line with Copy's, level with the title and the artist
      final star = tester.getRect(_star());
      final copy = tester.getRect(_copy());
      expect(star.size, const Size(48, 48));
      expect(star.right, copy.right);
      final title = tester.getRect(_title());
      final artist = tester.getRect(_artist('Zelda'));
      expect(star.center.dy, (title.top + artist.bottom) / 2);
      // the title has the room up to the star
      expect(tester.getRect(_titleBlock()).right, star.left);
      expect(title.right, lessThanOrEqualTo(star.left));
      expect(artist.right, lessThanOrEqualTo(star.left));

      await _tapStar(tester);
      expect(_inSheet(find.byIcon(Icons.star_border)), findsNothing);
      final icon = tester.widget<Icon>(_inSheet(find.byIcon(Icons.star)));
      expect(icon.color, OngColors.of(tester.element(_star())).brand);
      expect(
        tester.getSemantics(_star()),
        isSemantics(isButton: true, hasToggledState: true, isToggled: true, tooltip: 'Remove from favourites'),
      );
      expect(app.prefs.getStringList(_key), [testCatalogue().highlights.first.key]);

      await _tapStar(tester);
      expect(_inSheet(find.byIcon(Icons.star_border)), findsOneWidget);
      expect(tester.getSemantics(_star()), isSemantics(isToggled: false, tooltip: 'Add to favourites'));
      expect(app.prefs.getStringList(_key), isEmpty);
      handle.dispose();
    });

    testWidgets('shows the stored state, and only for its own highlight', (tester) async {
      await pumpApp(tester, prefs: _favourites(['I Will Survive']));
      await _openSheet(tester, 'I Will Survive');
      expect(tester.widget<IconButton>(_star()).tooltip, 'Remove from favourites');
      await _closeSheet(tester);
      await _openSheet(tester, 'Song of Storms');
      expect(tester.widget<IconButton>(_star()).tooltip, 'Add to favourites');
    });

    testWidgets('nothing in the sheet moves when it is toggled', (tester) async {
      await pumpApp(tester);
      await _openSheet(tester, 'I Will Survive');
      final parts = [
        _inSheet(find.text('Popular · Highlight #2')),
        _title(),
        _artist('Gloria Gaynor'),
        _star(),
        find.descendant(of: _star(), matching: find.byType(Icon)),
        _inSheet(find.text('Watch on YouTube')),
        _copy(),
        _inSheet(find.text('Played live on Sat 2 Mar 2024')),
      ];
      List<Rect> rects() => [for (final part in parts) tester.getRect(part)];
      final before = rects();
      await _tapStar(tester);
      expect(rects(), before);
      await _tapStar(tester);
      expect(rects(), before);
    });

    // long titles wrap before the star as they wrapped before the edge of the sheet; a title alone is level with it
    for (final (scale, size) in [
      (1.0, const Size(412, 892)),
      (1.0, const Size(320, 640)),
      (1.3, const Size(320, 640)),
      (2.0, const Size(412, 892)),
      (2.0, const Size(320, 640)),
    ]) {
      testWidgets('long titles and titles without artist keep clear of it: text scale $scale, ${size.width} px wide', (
        tester,
      ) async {
        final catalogue = catalogueOf(
          highlights: [
            hRow(
              order: '1',
              title: 'An artist - And a rather long track name that wraps onto two lines at least',
              link: 'https://youtu.be/abcdefghijk',
            ),
            hRow(order: '2', title: 'Short', link: 'https://youtu.be/bcdefghijkl'),
          ],
        );
        await pumpApp(
          tester,
          textScale: scale,
          size: size,
          state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
        );
        for (final (track, artist) in [
          ('And a rather long track name that wraps onto two lines at least', 'An artist'),
          ('Short', null),
        ]) {
          await _openSheet(tester, track);
          expect(tester.takeException(), isNull, reason: track);
          final star = tester.getRect(_star());
          final title = tester.getRect(_title());
          final sheet = tester.getRect(find.byType(HighlightSheet));
          expect(tester.getRect(_titleBlock()).right, star.left, reason: track);
          expect(title.right, lessThanOrEqualTo(star.left), reason: track);
          expect(star.right, tester.getRect(_copy()).right, reason: track);
          expect(star.right, lessThanOrEqualTo(sheet.right - 20), reason: track);
          if (artist == null) {
            expect(title.height, closeTo(26 * scale, 1), reason: 'one line');
            expect(star.center.dy, title.center.dy, reason: 'level with the title');
          } else {
            expect(title.height, greaterThanOrEqualTo(2 * 26 * scale), reason: 'wraps');
            expect(tester.getRect(_artist(artist)).right, lessThanOrEqualTo(star.left));
          }
          await _closeSheet(tester);
        }
      });
    }
  });

  group('The star chip', () {
    Finder starChip() => chip('Favourites');

    testWidgets('shows with a favourite of the list, after "All", before "You", with its count', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      expect(starChip(), findsNothing);
      // a favourite that is not in the catalogue does not bring it
      await _container(tester)
          .read(favouritesProvider.notifier)
          .toggle(
            catalogueOf(
              highlights: [hRow(order: '99', title: 'Gone')],
            ).highlights.single,
          );
      await tester.pumpAndSettle();
      expect(starChip(), findsNothing);

      await _openSheet(tester, 'I Will Survive');
      await _tapStar(tester);
      await _closeSheet(tester);
      expect(starChip(), findsOneWidget);
      expect(tester.getRect(starChip()).left, greaterThan(tester.getRect(chip('All')).right));
      expect(tester.getRect(starChip()).right, lessThan(tester.getRect(chip('You')).left));
      // the star and the count, no word, but a name for screen readers
      expect(find.descendant(of: starChip(), matching: find.byIcon(Icons.star)), findsOneWidget);
      expect(chipTextOf(tester, 'Favourites'), '1');
      expect(find.text('Favourites'), findsNothing);
      expect(tester.getSemantics(starChip()), isSemantics(label: 'Favourites\n1', isButton: true));

      await _openSheet(tester, 'Song of Storms');
      await _tapStar(tester);
      await _closeSheet(tester);
      expect(chipTextOf(tester, 'Favourites'), '2');
      handle.dispose();
    });

    testWidgets('keeps only the favourites, with the count line', (tester) async {
      await pumpApp(tester, prefs: _favourites(['Song of Storms', "How Far I'll Go"]));
      expect((_selected(tester, 'All'), _selected(tester, 'Favourites')), (true, false));
      expect(find.text('2 highlights'), findsNothing);
      await tester.tap(starChip());
      await tester.pumpAndSettle();
      expect(_tracks(tester), ["How Far I'll Go", 'Song of Storms']);
      expect((_selected(tester, 'All'), _selected(tester, 'Favourites')), (false, true));
      expect(find.text('2 highlights'), findsOneWidget);
      await tester.tap(starChip());
      await tester.pumpAndSettle();
      expect(_tracks(tester), hasLength(3));
      expect(_selected(tester, 'All'), isTrue);
      expect(find.text('2 highlights'), findsNothing);
    });

    testWidgets('combines with the search, the genres and "You"; "All" clears it', (tester) async {
      // jsbach64 requested "Song of Storms" (Game OST); "How Far I'll Go" is Disney
      await pumpApp(
        tester,
        prefs: {
          'twitchName': 'jsbach64',
          ..._favourites(['Song of Storms', "How Far I'll Go"]),
        },
      );
      Future<void> tap(String label) => tapVisible(tester, chip(label));
      Future<void> search(String query) async {
        await tester.enterText(searchField(), query);
        await tester.pumpAndSettle();
      }

      await tap('Favourites');
      await search('moana');
      expect(_tracks(tester), ["How Far I'll Go"]);
      await search('survive');
      expect(_tracks(tester), isEmpty, reason: 'not a favourite');
      await search('');
      expect(_tracks(tester), hasLength(2), reason: 'a query change keeps the star');
      await tap('Disney');
      expect(_tracks(tester), ["How Far I'll Go"], reason: 'genre and star together');
      await tap('Popular');
      expect(_tracks(tester), isEmpty);
      await tap('Popular');
      expect(_tracks(tester), hasLength(2), reason: 'a genre change keeps the star');
      await tap('You');
      expect(_tracks(tester), ['Song of Storms'], reason: '"You" and star together');
      expect(find.text('1 highlight'), findsOneWidget);
      await tap('You');
      expect(_tracks(tester), hasLength(2), reason: 'a change of "You" keeps the star');
      await tap('You');
      await tap('All');
      expect(_tracks(tester), hasLength(3));
      expect(
        (_selected(tester, 'All'), _selected(tester, 'Favourites'), _selected(tester, 'You')),
        (true, false, false),
      );
      expect(_container(tester).read(highlightFilterProvider), const HighlightFilter());
    });

    testWidgets('removing a star from the filtered list: the sheet stays, the list follows, no filter is left behind', (
      tester,
    ) async {
      final app = await pumpApp(tester, prefs: _favourites(['Song of Storms', "How Far I'll Go"]));
      await tester.tap(starChip());
      await tester.pumpAndSettle();

      await _openSheet(tester, 'Song of Storms');
      await _tapStar(tester);
      expect(tester.takeException(), isNull);
      // the sheet keeps its highlight, its star off
      expect(find.byType(HighlightSheet), findsOneWidget);
      expect(_inSheet(find.text('Song of Storms')), findsOneWidget);
      expect(tester.widget<IconButton>(_star()).tooltip, 'Add to favourites');
      await _closeSheet(tester);
      expect(_tracks(tester), ["How Far I'll Go"]);
      expect(_selected(tester, 'Favourites'), isTrue);
      expect(find.text('1 highlight'), findsOneWidget);

      // the last one: the chip goes, and its filter with it
      await _openSheet(tester, "How Far I'll Go");
      await _tapStar(tester);
      expect(tester.takeException(), isNull);
      expect(_inSheet(find.text("How Far I'll Go")), findsOneWidget);
      expect(tester.widget<IconButton>(_star()).tooltip, 'Add to favourites');
      await _closeSheet(tester);
      expect(starChip(), findsNothing);
      expect(_tracks(tester), hasLength(3));
      expect(_selected(tester, 'All'), isTrue);
      expect(find.textContaining('highlights'), findsOneWidget, reason: 'the search hint, no count line');
      expect(_container(tester).read(highlightFilterProvider).favourites, isFalse);
      expect(app.prefs.getStringList(_key), isEmpty);

      // a new star brings the chip back, not selected
      await _openSheet(tester, 'I Will Survive');
      await _tapStar(tester);
      await _closeSheet(tester);
      expect(_selected(tester, 'Favourites'), isFalse);
      expect(_tracks(tester), hasLength(3));
    });

    testWidgets('a refresh without the favourites takes the chip and its filter away', (tester) async {
      final app = await pumpApp(tester, prefs: _favourites(['Song of Storms']));
      await tester.tap(starChip());
      await tester.pumpAndSettle();
      expect(_tracks(tester), ['Song of Storms']);

      final state = app.notifier.initial;
      app.notifier.emit(CatalogueState(catalogue: catalogueOf(), fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(starChip(), findsNothing);
      expect(find.byType(HighlightRow), findsOneWidget, reason: 'the one highlight of the new catalogue');
      expect(_selected(tester, 'All'), isTrue);
      expect(_container(tester).read(highlightFilterProvider).favourites, isFalse);
      // still stored: it comes back with the highlight, not selected
      expect(app.prefs.getStringList(_key), hasLength(1));
      app.notifier.emit(state);
      await tester.pumpAndSettle();
      expect(_selected(tester, 'Favourites'), isFalse);
      expect(_tracks(tester), hasLength(3));
    });

    testWidgets('the Ong Log has no star chip', (tester) async {
      await pumpApp(tester, prefs: _favourites(['Song of Storms']));
      expect(starChip(), findsOneWidget);
      await goToTab(tester, 'Ong Log');
      expect(starChip(), findsNothing);
      expect(find.byIcon(Icons.star), findsNothing);
    });
  });

  group('Scroll position', () {
    /// 100 highlights, all favourites.
    Future<(TestApp, ScrollPosition)> pumpMany(WidgetTester tester) async {
      final catalogue = catalogueOf(
        highlights: [for (var i = 0; i < 100; i++) hRow(order: '${i + 1}', title: 'Video $i')],
      );
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: catalogue, fetchedAt: testNow),
        prefs: {
          _key: [for (final h in catalogue.highlights) h.key],
        },
      );
      final list = find.descendant(of: find.byType(HighlightsPage), matching: find.byType(CustomScrollView));
      final position = tester
          .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
          .position;
      return (app, position);
    }

    testWidgets('the star chip goes back to the top', (tester) async {
      final (_, position) = await pumpMany(tester);
      for (final _ in [1, 2]) {
        position.jumpTo(1234);
        await tester.pump();
        await tester.tap(chip('Favourites'));
        await tester.pumpAndSettle();
        expect(position.pixels, 0);
      }
    });

    testWidgets('a star removed under the star chip leaves the rows above it in place', (tester) async {
      final (_, position) = await pumpMany(tester);
      await tester.tap(chip('Favourites'));
      await tester.pumpAndSettle();
      position.jumpTo(1234);
      await tester.pump();
      final rows = find.byType(HighlightRow).hitTestable();
      final shown = tester.widgetList<HighlightRow>(rows).map((r) => r.highlight.title).toList();
      final top = tester.getRect(rows.first).top;
      // the third row on screen
      await _openSheet(tester, shown[2]);
      await _tapStar(tester);
      await _closeSheet(tester);
      expect(position.pixels, 1234);
      final after = tester.widgetList<HighlightRow>(rows).map((r) => r.highlight.title).toList();
      expect(after.take(4), [shown[0], shown[1], shown[3], shown[4]]);
      expect(tester.getRect(rows.first).top, top);
    });
  });
}
