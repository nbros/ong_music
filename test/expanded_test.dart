// An expanded window: the list pane and the detail pane (what a row shows, the links of a fiche, the back bar,
// Escape and the back button, the keyboard, refreshes, mode changes), and the About tab in two cards.
import 'package:flutter/gestures.dart';
import 'dart:ui' show Tristate;

import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/detail_pane.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/install_banner.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/nav_rail.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/view_state.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/install_hint.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// A desktop browser window: expanded.
const desk = Size(1440, 900);

/// A window too narrow for the two panes.
const medium = Size(830, 900);

/// The detail pane of [tab].
Finder pane([AppTab tab = AppTab.highlights]) => find.byWidgetPredicate((w) => w is DetailPane && w.tab == tab);

/// The card of the detail pane of [tab].
Finder paneCard([AppTab tab = AppTab.highlights]) =>
    find.descendant(of: pane(tab), matching: find.byType(Material)).first;

/// [matching] inside the detail pane of [tab].
Finder inPane(Finder matching, [AppTab tab = AppTab.highlights]) => find.descendant(of: pane(tab), matching: matching);

/// The fiche the pane of [tab] shows: its widget.
Widget paneFiche(WidgetTester tester, [AppTab tab = AppTab.highlights]) => tester.widget(
  inPane(find.byWidgetPredicate((w) => w is HighlightSheet || w is SongSheet || w is StreamSheet), tab),
);

/// The title of the highlight the pane of the Highlights tab shows.
String paneHighlight(WidgetTester tester) => (paneFiche(tester) as HighlightSheet).highlight.track;

/// The back bar of the pane of [tab].
Finder backButton([AppTab tab = AppTab.highlights]) => inPane(find.byTooltip('Back'), tab);

/// The row of the Highlights list showing [track].
Finder highlightRow(String track) => find.ancestor(
  of: find.descendant(of: find.byType(HighlightsPage), matching: find.text(track)),
  matching: find.byType(HighlightRow),
);

/// Whether the row of [track] is the selected one.
bool? selected(WidgetTester tester, String track) => tester.widget<HighlightRow>(highlightRow(track)).selected;

/// The row of the Ong Log showing play [id].
Finder playRow(int id) => find.byWidgetPredicate((w) => w is PlayRow && w.play.id == id && w.selected != null);

/// The highlights of the list, in order.
List<String> listed(WidgetTester tester) => [
  for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow))) row.highlight.track,
];

/// Presses [key] and lets the frame through.
Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await tester.pumpAndSettle();
}

/// The test catalogue with [count] more highlights ("Song 1"…), older than the others.
CatalogueState moreHighlights(int count) => CatalogueState(
  catalogue: testCatalogue(
    moreHighlights: [for (var i = 1; i <= count; i++) hRow(order: '${3 + i}', title: 'Song $i')],
  ),
  fetchedAt: testNow,
);

/// The test catalogue with [streams] more streams of 6 plays each, newer than the others.
CatalogueState moreStreams(int streams) => CatalogueState(
  catalogue: testCatalogue(
    moreSongs: [
      for (var s = 0; s < streams; s++) ...[
        start('2024-04-${(s + 1).toString().padLeft(2, '0')}'),
        for (var p = 0; p < 6; p++)
          sRow(date: '2024-04-${(s + 1).toString().padLeft(2, '0')} 20:0$p:00', title: 'Tune $s.$p', type: 'Piano'),
      ],
    ],
  ),
  fetchedAt: testNow,
);

/// The test catalogue with a stream of 40 plays ("Tune 0"…"Tune 39") after the others: a setlist longer than the
/// pane.
CatalogueState longStream() => CatalogueState(
  catalogue: testCatalogue(
    moreSongs: [
      start('2024-04-01'),
      for (var i = 0; i < 40; i++)
        sRow(date: '2024-04-01 20:${i.toString().padLeft(2, '0')}:00', title: 'Tune $i', type: 'Piano'),
    ],
  ),
  fetchedAt: testNow,
);

/// Opens, in the Ong Log of an expanded window, the setlist of the long stream of [longStream] from the history
/// of "Tune 20": the setlist scrolled to that play, over the song.
Future<void> openLongSetlist(WidgetTester tester) async {
  await goToTab(tester, 'Ong Log');
  await tester.enterText(searchField(), 'tune 20');
  await tester.pumpAndSettle();
  await tester.tap(find.byWidgetPredicate((w) => w is PlayRow && w.play.title == 'Tune 20' && w.selected != null));
  await tester.pumpAndSettle();
  await tester.tap(inPane(find.byType(HistoryRow), AppTab.ongLog));
  await tester.pumpAndSettle();
  expect(paneFiche(tester, AppTab.ongLog), isA<StreamSheet>());
}

/// The scroll position of the fiche in the pane of [tab].
ScrollPosition paneScroll(WidgetTester tester, [AppTab tab = AppTab.highlights]) =>
    tester.state<ScrollableState>(inPane(find.byType(Scrollable), tab).first).position;

void main() {
  group('panes', () {
    for (final (width, height) in [(840.0, 800.0), (1180.0, 820.0), (1440.0, 900.0), (1920.0, 1080.0)]) {
      testWidgets('${width.round()} px wide: the list pane, the detail card, the fiche in the middle of it', (
        tester,
      ) async {
        await pumpApp(tester, size: Size(width, height), pointer: PointerKind.touch);
        // at most 1520 px right of the rail, centred
        final area = (width - railWidth).clamp(0.0, 1520.0);
        final left = railWidth + (width - railWidth - area) / 2;
        final list = (0.4 * (width - railWidth)).clamp(360.0, 520.0);
        expect(tester.getRect(find.byType(HighlightsPage)), Rect.fromLTWH(left, 0, list, height));
        final card = Rect.fromLTRB(left + list + 4, 12, left + area - 12, height - 12);
        expect(tester.getRect(paneCard()), card);
        // the fiche: at most 640 px wide, in the middle of the card (its buttons 20 px from its edges, the round
        // one 40 px wide in a target of 48)
        final content = card.width < 640 ? card.width : 640.0;
        final button = tester.getRect(inPane(find.widgetWithText(FilledButton, 'Video unavailable')));
        final copy = tester.getRect(inPane(find.byTooltip('Copy title')));
        expect(button.left - 20, moreOrLessEquals(card.center.dx - content / 2));
        expect(copy.right + 4 + 20, moreOrLessEquals(card.center.dx + content / 2));
        expect(tester.takeException(), isNull);
      });
    }

    testWidgets('with a mouse, the scroll bar of the pane at the edge of the card', (tester) async {
      await pumpApp(tester, size: const Size(1920, 1080), pointer: PointerKind.mouse);
      final card = tester.getRect(paneCard());
      final scroll = inPane(find.byType(CustomScrollView));
      expect(tester.getRect(scroll).right, card.right - scrollbarLane);
      // the fiche in the middle of what the lane leaves
      final copy = tester.getRect(inPane(find.byTooltip('Copy title')));
      expect(copy.right + 4 + 20, moreOrLessEquals(card.left + (card.width - scrollbarLane + 640) / 2));
    });

    testWidgets('the install banner above both panes', (tester) async {
      await pumpApp(
        tester,
        size: desk,
        installHint: const InstallHint(InstallHintKind.addToHomeScreen, share: SafariShare.behindMore),
      );
      final banner = tester.getRect(find.byType(InstallBanner));
      expect(banner.top, 0);
      expect(tester.getRect(find.byType(HighlightsPage)).top, greaterThanOrEqualTo(banner.bottom));
      expect(tester.getRect(paneCard()).top, banner.bottom + 12);
      expect(banner.right - banner.left, greaterThan(tester.getRect(find.byType(HighlightsPage)).width));
    });

    testWidgets('a window too low for them stays medium: one column, sheets', (tester) async {
      await pumpApp(tester, size: const Size(1440, 470));
      expect(pane(), findsNothing);
      expect(detailsButtons(), findsWidgets);
    });
  });

  group('list and detail', () {
    testWidgets('at first, the pane shows the newest highlight, and the Ong Log the song of the newest play', (
      tester,
    ) async {
      await pumpApp(tester, size: desk);
      expect(listed(tester).first, "How Far I'll Go");
      expect(paneHighlight(tester), "How Far I'll Go");
      expect(selected(tester, "How Far I'll Go"), isTrue);
      expect(selected(tester, 'I Will Survive'), isFalse);
      await goToTab(tester, 'Ong Log');
      final song = paneFiche(tester, AppTab.ongLog) as SongSheet;
      expect(song.song.track, 'I Will Survive');
      // the newest play of the log is its row, selected
      expect(tester.widget<PlayRow>(playRow(3)).selected, isTrue);
      expect(tester.widget<PlayRow>(playRow(0)).selected, isFalse);
      expect(backButton(AppTab.ongLog), findsNothing);
    });

    testWidgets('the first row of the list when it is filtered as the pane first shows', (tester) async {
      await pumpApp(tester, size: medium);
      await tester.enterText(searchField(), 'storms');
      await tester.pumpAndSettle();
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'Song of Storms');
    });

    testWidgets('a row shows its fiche in the pane and does not open the video', (tester) async {
      final app = await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'Song of Storms');
      expect(selected(tester, 'Song of Storms'), isTrue);
      expect(selected(tester, "How Far I'll Go"), isFalse);
      expect(app.effects.opened, isEmpty);
      expect(find.byType(BottomSheet), findsNothing);
    });

    testWidgets('a medium window: a row still opens its video, and has its ⋮ button', (tester) async {
      final app = await pumpApp(tester, size: medium);
      expect(detailsButtons(), findsNWidgets(3));
      await tester.tap(find.text('Song of Storms'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      expect(pane(), findsNothing);
    });

    testWidgets('no ⋮ button: the title has its room', (tester) async {
      await pumpApp(tester, size: desk);
      expect(detailsButtons(), findsNothing);
      expect(find.byIcon(Icons.more_vert), findsNothing);
      // the title may take the width up to 4 px from the padding of the row, not 30 (the place of the button):
      // 16 + thumbnail 124 + 12 on the left, 12 on the right
      final row = tester.getRect(highlightRow('I Will Survive'));
      final title = find.descendant(of: highlightRow('I Will Survive'), matching: find.byType(MarkedText)).first;
      expect(tester.renderObject<RenderBox>(title).constraints.maxWidth, row.width - 16 - 124 - 12 - 12 - 4);
    });

    testWidgets('with a mouse, the thumbnail opens the video, with a veil on hover', (tester) async {
      final app = await pumpApp(tester, size: desk, pointer: PointerKind.mouse);
      final thumbnail = find.descendant(of: highlightRow('Song of Storms'), matching: find.byType(Thumbnail));
      expect(find.byIcon(Icons.open_in_new), findsNothing);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(thumbnail)));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.open_in_new), findsOneWidget);
      await tester.tap(thumbnail, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      expect(paneHighlight(tester), "How Far I'll Go", reason: 'the selection stays');
      // a highlight without video: the thumbnail is part of the row
      await tester.tap(find.descendant(of: highlightRow("How Far I'll Go"), matching: find.byType(Thumbnail)));
      await tester.pumpAndSettle();
      expect(app.effects.opened, hasLength(1));
    });

    testWidgets('with touch, the thumbnail selects its row', (tester) async {
      final app = await pumpApp(tester, size: desk, pointer: PointerKind.touch);
      await tester.tap(find.descendant(of: highlightRow('Song of Storms'), matching: find.byType(Thumbnail)));
      await tester.pumpAndSettle();
      expect(app.effects.opened, isEmpty);
      expect(paneHighlight(tester), 'Song of Storms');
      expect(find.byIcon(Icons.open_in_new), findsNothing);
    });

    testWidgets('the pane stays when the query or the filters change, even without its row', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      expect(highlightRow('I Will Survive'), findsNothing);
      expect(paneHighlight(tester), 'I Will Survive');
      await tester.enterText(searchField(), '');
      await tester.tap(chip('Disney'));
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'I Will Survive');
      await tester.tap(chip('All'));
      await tester.pumpAndSettle();
      expect(selected(tester, 'I Will Survive'), isTrue, reason: 'marked again when back in the list');
    });

    testWidgets('the Ong Log: a play shows its song, a header its setlist; the video pill opens the video', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: desk);
      await goToTab(tester, 'Ong Log');
      await tester.tap(playRow(2));
      await tester.pumpAndSettle();
      expect((paneFiche(tester, AppTab.ongLog) as SongSheet).song.track, 'Song of Storms');
      expect(tester.widget<PlayRow>(playRow(2)).selected, isTrue);
      expect(tester.widget<PlayRow>(playRow(3)).selected, isFalse);

      final header = find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == 0);
      await tester.tap(header);
      await tester.pumpAndSettle();
      final setlist = paneFiche(tester, AppTab.ongLog) as StreamSheet;
      expect((setlist.stream.id, setlist.play), (0, null));
      expect(tester.widget<StreamHeader>(header).selected, isTrue);
      expect(tester.widget<PlayRow>(playRow(2)).selected, isFalse);

      await tester.tap(find.descendant(of: playRow(2), matching: find.byType(VideoPill)));
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      expect(paneFiche(tester, AppTab.ongLog), isA<StreamSheet>());
    });
  });

  group('states', () {
    testWidgets('a selected stream header: its date in onSurface, announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: desk);
      await goToTab(tester, 'Ong Log');
      final scheme = Theme.of(tester.element(find.byType(OngLogPage))).colorScheme;
      Finder header(int id) => find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == id);
      Color? dateColor(int id) =>
          tester.widget<Text>(find.descendant(of: header(id), matching: find.textContaining('Mar 2024'))).style?.color;
      await tester.tap(header(0));
      await tester.pumpAndSettle();
      expect(dateColor(0), scheme.onSurface);
      expect(dateColor(1), scheme.primary);
      expect(tester.getSemantics(header(0)).getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.getSemantics(header(1)).getSemanticsData().flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('the pinned header shows the state of the header it stands for', (tester) async {
      await pumpApp(tester, size: desk, state: moreStreams(12));
      await goToTab(tester, 'Ong Log');
      final list = find.descendant(of: find.byType(OngLogPage), matching: find.byType(CustomScrollView));
      final pinned = find.descendant(
        of: find.descendant(of: find.byType(OngLogPage), matching: find.byType(OverflowBox)),
        matching: find.byType(StreamHeader),
      );
      // the first header selected, the list scrolled past it: the pinned one stands for it
      final first = find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == 13);
      await tester.tap(first);
      await tester.pumpAndSettle();
      tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position.jumpTo(100);
      await tester.pumpAndSettle();
      expect(tester.widget<StreamHeader>(pinned).stream.id, 13);
      expect(tester.widget<StreamHeader>(pinned).selected, isTrue);
      // another header chosen: the pinned one is not selected any more
      await tester.tap(find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == 12));
      await tester.pumpAndSettle();
      expect(tester.widget<StreamHeader>(pinned).stream.id, 13);
      expect(tester.widget<StreamHeader>(pinned).selected, isFalse);
    });

    testWidgets('the hover of a row: onSurface at 6 %, in the shape of the selection', (tester) async {
      await pumpApp(tester, size: desk, pointer: PointerKind.mouse);
      final onSurface = Theme.of(tester.element(find.byType(HighlightsPage))).colorScheme.onSurface;
      InkWell ink(Finder row) => tester.widget<InkWell>(find.descendant(of: row, matching: find.byType(InkWell)).first);
      for (final row in [highlightRow('I Will Survive'), highlightRow('Song of Storms')]) {
        expect(ink(row).hoverColor, onSurface.withValues(alpha: 0.06));
        expect(ink(row).customBorder, InsetRoundedBorder.row);
      }
      await goToTab(tester, 'Ong Log');
      expect(ink(playRow(1)).hoverColor, onSurface.withValues(alpha: 0.06));
      // a medium window: the hover of today
      tester.view.physicalSize = medium;
      await tester.pumpAndSettle();
      await goToTab(tester, 'Highlights');
      expect(
        tester
            .widget<InkWell>(find.ancestor(of: find.text('Song of Storms'), matching: find.byType(InkWell)).first)
            .hoverColor,
        isNull,
      );
    });

    testWidgets('the tabs out of sight do not animate', (tester) async {
      await pumpApp(tester, size: desk);
      // (the tabs out of sight are offstage)
      Finder page(Type type) => find.byType(type, skipOffstage: false);
      Finder tabPane(AppTab tab) => find.byWidgetPredicate((w) => w is DetailPane && w.tab == tab, skipOffstage: false);
      bool animates(Finder finder) => TickerMode.valuesOf(tester.element(finder)).enabled;
      expect(animates(page(HighlightsPage)), isTrue);
      expect(animates(tabPane(AppTab.highlights)), isTrue);
      expect(animates(page(OngLogPage)), isFalse);
      expect(animates(tabPane(AppTab.ongLog)), isFalse);
      expect(animates(page(AboutPage)), isFalse);
      await goToTab(tester, 'Ong Log');
      expect(animates(page(HighlightsPage)), isFalse);
      expect(animates(tabPane(AppTab.highlights)), isFalse);
      expect(animates(page(OngLogPage)), isTrue);
      expect(animates(tabPane(AppTab.ongLog)), isTrue);
    });
  });

  group('inside the pane', () {
    testWidgets('a link opens the next fiche over the current one, the back bar returns to it', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      expect(backButton(), findsNothing);
      await tester.tap(inPane(find.text('Played live on Sat 2 Mar 2024')));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      final setlist = paneFiche(tester) as StreamSheet;
      expect(setlist.play?.title, 'Gloria Gaynor - I Will Survive', reason: 'the play of the highlight, tinted');
      // the bar: back, and the title of the fiche it returns to
      expect(backButton(), findsOneWidget);
      expect(inPane(find.text('I Will Survive')), findsWidgets);
      final bar = find.ancestor(
        of: backButton(),
        matching: find.byWidgetPredicate((w) => w is ConstrainedBox && w.constraints.minHeight == 56),
      );
      expect(tester.getSize(bar).height, 56);
      // the selected row of the list is still the one chosen
      expect(selected(tester, 'I Will Survive'), isTrue);

      // a setlist row: the song, a third fiche
      // (the highlight's play is the one of the first stream in the test catalogue)
      await tester.tap(inPane(find.text('Lost Woods')));
      await tester.pumpAndSettle();
      expect((paneFiche(tester) as SongSheet).song.track, 'Lost Woods');
      expect(inPane(find.text('Fri 1 Mar 2024')), findsWidgets);

      await tester.tap(backButton());
      await tester.pumpAndSettle();
      expect(paneFiche(tester), isA<StreamSheet>());
      await tester.tap(backButton());
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'I Will Survive');
      expect(backButton(), findsNothing);
    });

    testWidgets('"Played N times live" and a history row stack too', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      expect(paneFiche(tester), isA<SongSheet>());
      await tester.tap(inPane(find.text('Fri 1 Mar 2024')));
      await tester.pumpAndSettle();
      expect((paneFiche(tester) as StreamSheet).play?.id, 0);
      expect(tester.state<NavigatorState>(find.byType(Navigator)).canPop(), isFalse, reason: 'no sheet');
    });

    testWidgets('Escape goes back in the pane, but not from the search field', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      // in the search field, Escape is the field's (it leaves it)
      await tester.tap(searchField());
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.escape);
      expect(paneFiche(tester), isA<SongSheet>());
      await press(tester, LogicalKeyboardKey.escape);
      expect(paneHighlight(tester), 'I Will Survive');
      // nothing under the first fiche
      await press(tester, LogicalKeyboardKey.escape);
      expect(paneHighlight(tester), 'I Will Survive');
    });

    testWidgets('Android back goes back in the pane first, then the usual way', (tester) async {
      final app = await pumpApp(tester, size: const Size(1280, 800));
      await goToTab(tester, 'Ong Log');
      await tester.tap(playRow(3));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.text('Fri 1 Mar 2024'), AppTab.ongLog));
      await tester.pumpAndSettle();
      expect(paneFiche(tester, AppTab.ongLog), isA<StreamSheet>());
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(paneFiche(tester, AppTab.ongLog), isA<SongSheet>());
      expect(selectedTab(tester), 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0, reason: 'back to Highlights');
      expect(app.effects.exits, 0);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.effects.exits, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('Android back on the Highlights tab: back in the pane before leaving', (tester) async {
      final app = await pumpApp(tester, size: const Size(1280, 800));
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.effects.exits, 0);
      expect(paneHighlight(tester), 'I Will Survive');
      expect(backButton(), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.effects.exits, 1);
    }, variant: TargetPlatformVariant.only(TargetPlatform.android));

    testWidgets('a row chosen in the list replaces the whole stack', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'Song of Storms');
      expect(backButton(), findsNothing);
      // the selected row again: alone, no back bar
      await tester.tap(inPane(find.text('Played live on Sat 2 Mar 2024')));
      await tester.pumpAndSettle();
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'Song of Storms');
      expect(backButton(), findsNothing);
    });

    testWidgets('"Requested by" switches to the Ong Log with that search, each pane as it was', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.textContaining('Requested by', findRichText: true)));
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      expect(find.text('shadowvanta').hitTestable(), findsWidgets);
      expect(tester.widget<TextField>(searchField()).controller!.text, 'shadowvanta');
      expect((paneFiche(tester, AppTab.ongLog) as SongSheet).song.track, 'I Will Survive');
      await goToTab(tester, 'Highlights');
      expect(paneHighlight(tester), 'I Will Survive');
    });

    testWidgets('a setlist in the pane opens with its play in the middle, its rows rounded', (tester) async {
      await pumpApp(tester, size: desk, state: longStream());
      await openLongSetlist(tester);
      final viewport = tester.getRect(inPane(find.byType(CustomScrollView), AppTab.ongLog));
      final tinted = inPane(find.byWidgetPredicate((w) => w is PlayRow && w.tinted), AppTab.ongLog);
      expect(tester.widget<PlayRow>(tinted).play.title, 'Tune 20');
      expect(paneScroll(tester, AppTab.ongLog).pixels, greaterThan(0));
      expect(tester.getRect(tinted).center.dy, moreOrLessEquals(viewport.center.dy, epsilon: 0.5));
      // rounded as the rows of the lists, in line with the title
      final row = tester.widget<PlayRow>(tinted);
      expect((row.shape, row.start), (RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), 20));
      await tester.tap(backButton(AppTab.ongLog));
      await tester.pumpAndSettle();
      final history = tester.widget<HistoryRow>(inPane(find.byType(HistoryRow), AppTab.ongLog));
      expect(history.shape, RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)));
    });

    testWidgets('a setlist first in the pane (from a sheet) has its play in the middle too, below the space on top', (
      tester,
    ) async {
      await pumpApp(tester, size: medium, state: longStream());
      await goToTab(tester, 'Ong Log');
      await tester.enterText(searchField(), 'tune 20');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Tune 20'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(HistoryRow));
      await tester.pumpAndSettle();
      expect(find.byType(StreamSheet), findsOneWidget);
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(backButton(AppTab.ongLog), findsNothing);
      final viewport = tester.getRect(inPane(find.byType(CustomScrollView), AppTab.ongLog));
      final tinted = inPane(find.byWidgetPredicate((w) => w is PlayRow && w.tinted), AppTab.ongLog);
      expect(tester.widget<PlayRow>(tinted).play.title, 'Tune 20');
      expect(tester.getRect(tinted).center.dy, moreOrLessEquals(viewport.center.dy, epsilon: 0.5));
    });

    testWidgets('in a sheet, the rows of a fiche stay square', (tester) async {
      await pumpApp(tester, size: medium);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      final rows = tester.widgetList<PlayRow>(
        find.descendant(of: find.byType(StreamSheet), matching: find.byType(PlayRow)),
      );
      expect(rows.map((r) => (r.shape, r.start)).toSet(), {(null, 16.0)});
    });

    testWidgets('a refresh keeps the fiche of the pane where it was scrolled', (tester) async {
      final app = await pumpApp(tester, size: desk, state: longStream());
      await openLongSetlist(tester);
      final scrolled = paneScroll(tester, AppTab.ongLog).pixels + 200;
      paneScroll(tester, AppTab.ongLog).jumpTo(scrolled);
      await tester.pumpAndSettle();
      final fresh = testCatalogue(
        moreSongs: [
          ...[
            start('2024-04-01'),
            for (var i = 0; i < 40; i++)
              sRow(date: '2024-04-01 20:${i.toString().padLeft(2, '0')}:00', title: 'Tune $i', type: 'Piano'),
          ],
          start('2024-04-02'),
          sRow(date: '2024-04-02 20:00:00', title: 'Chopin - Ballade'),
        ],
      );
      app.notifier.emit(CatalogueState(catalogue: fresh, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect((paneFiche(tester, AppTab.ongLog) as StreamSheet).catalogue, same(fresh));
      expect(paneScroll(tester, AppTab.ongLog).pixels, scrolled);
    });

    testWidgets('the star of a fiche in the pane keeps its place', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      final star = inPane(find.byTooltip('Add to favourites'));
      final before = tester.getRect(star);
      final title = tester.getRect(inPane(find.text('I Will Survive')).first);
      await tester.tap(star);
      await tester.pumpAndSettle();
      expect(tester.getRect(inPane(find.byTooltip('Remove from favourites'))), before);
      expect(tester.getRect(inPane(find.text('I Will Survive')).first), title);
      expect(paneHighlight(tester), 'I Will Survive');
    });
  });

  group('pane state', () {
    testWidgets('each tab keeps its pane, across tabs and window modes', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.text('Played live on Sat 2 Mar 2024')));
      await tester.pumpAndSettle();
      await goToTab(tester, 'Ong Log');
      final header = find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == 0);
      await tester.tap(header);
      await tester.pumpAndSettle();
      await goToTab(tester, 'About');
      await goToTab(tester, 'Highlights');
      expect(paneFiche(tester), isA<StreamSheet>());
      expect(backButton(), findsOneWidget);
      expect(selected(tester, 'Song of Storms'), isTrue);

      // a medium window, then expanded again: nothing opened meanwhile, the panes as they were
      tester.view.physicalSize = medium;
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(pane(), findsNothing);
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(paneFiche(tester), isA<StreamSheet>());
      await goToTab(tester, 'Ong Log');
      expect((paneFiche(tester, AppTab.ongLog) as StreamSheet).stream.id, 0);
      expect(tester.widget<StreamHeader>(header).selected, isTrue);
    });

    testWidgets('a sheet open when the window widens moves into the pane; narrowing opens nothing', (tester) async {
      await pumpApp(tester, size: medium);
      await tester.tap(detailsButtons().at(2));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect(paneHighlight(tester), 'Song of Storms');
      expect(selected(tester, 'Song of Storms'), isTrue);
      expect(backButton(), findsNothing);
      tester.view.physicalSize = medium;
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      // a sheet opened from inside a sheet (another fiche): it too
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Played 2 times live'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsOneWidget);
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expect((paneFiche(tester) as SongSheet).song.track, 'I Will Survive');
      // a fiche that is no row of the list: none selected
      expect(find.byWidgetPredicate((w) => w is HighlightRow && (w.selected ?? false)), findsNothing);
    });

    testWidgets('a refresh: the same fiches on the new catalogue, the same row selected', (tester) async {
      final app = await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.text('Played live on Sat 2 Mar 2024')));
      await tester.pumpAndSettle();
      // a new highlight and a new stream come first
      final fresh = testCatalogue(
        moreHighlights: [hRow(order: '4', title: 'Chopin - Ballade', link: 'https://youtu.be/ccccccccccc')],
        moreSongs: [
          start('2024-04-01'),
          sRow(date: '2024-04-01 20:00:00', title: 'Chopin - Ballade'),
        ],
      );
      app.notifier.emit(CatalogueState(catalogue: fresh, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(listed(tester).first, 'Ballade');
      final setlist = paneFiche(tester) as StreamSheet;
      expect(setlist.catalogue, same(fresh), reason: 'never the items of the old catalogue');
      expect((setlist.stream.date.toString(), setlist.play?.title), ('2024-03-02', 'Zelda - Song of Storms'));
      expect(backButton(), findsOneWidget);
      expect(selected(tester, 'Song of Storms'), isTrue);
      expect(selected(tester, 'Ballade'), isFalse);
      await tester.tap(backButton());
      await tester.pumpAndSettle();
      expect((paneFiche(tester) as HighlightSheet).catalogue, same(fresh));
    });

    testWidgets('a refresh without the item: the first row of the list', (tester) async {
      final app = await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      final without = catalogueOf(
        highlights: [hRow(order: '1', title: 'Chopin - Nocturne', link: 'https://youtu.be/ddddddddddd')],
      );
      app.notifier.emit(CatalogueState(catalogue: without, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'Nocturne');
      expect((paneFiche(tester) as HighlightSheet).catalogue, same(without));
      expect(selected(tester, 'Nocturne'), isTrue);
      expect(tester.takeException(), isNull);
    });

    testWidgets('downloaded data cleared: the card waits, then shows the same fiche again', (tester) async {
      final app = await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('Song of Storms'));
      await tester.pumpAndSettle();
      app.notifier.emit(const CatalogueState());
      await tester.pump();
      expect(paneCard(), findsOneWidget);
      expect(inPane(find.byType(HighlightSheet)), findsNothing);
      final again = testCatalogue();
      app.notifier.emit(CatalogueState(catalogue: again, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), 'Song of Storms');
      expect((paneFiche(tester) as HighlightSheet).catalogue, same(again));
    });

    testWidgets('a refresh of the Ong Log: the selected play stays marked', (tester) async {
      final app = await pumpApp(tester, size: desk);
      await goToTab(tester, 'Ong Log');
      await tester.tap(playRow(1));
      await tester.pumpAndSettle();
      final fresh = moreStreams(1).catalogue!;
      app.notifier.emit(CatalogueState(catalogue: fresh, fetchedAt: testNow));
      await tester.pumpAndSettle();
      final song = paneFiche(tester, AppTab.ongLog) as SongSheet;
      expect(song.catalogue, same(fresh));
      expect(song.song.track, 'Lost Woods');
      // the same play, its id unchanged here (the new plays come after it)
      expect(tester.widget<PlayRow>(playRow(1)).selected, isTrue);
      expect(find.byWidgetPredicate((w) => w is PlayRow && (w.selected ?? false)), findsOneWidget);
    });
  });

  group('keyboard', () {
    testWidgets('↓ and ↑ select the next and previous highlight; Enter starts its video', (tester) async {
      final app = await pumpApp(tester, size: desk);
      expect(paneHighlight(tester), "How Far I'll Go");
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(paneHighlight(tester), 'I Will Survive');
      expect(selected(tester, 'I Will Survive'), isTrue);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(paneHighlight(tester), 'Song of Storms', reason: 'the last row stays');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(paneHighlight(tester), 'I Will Survive');
      await press(tester, LogicalKeyboardKey.enter);
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
      // a fiche on top: the selected row still moves, and replaces the stack
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(paneHighlight(tester), 'Song of Storms');
      expect(backButton(), findsNothing);
    });

    testWidgets('the arrows work from the search field, which keeps its text and cursor', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(searchField());
      await tester.enterText(searchField(), 'i');
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(searchField());
      field.controller!.selection = const TextSelection.collapsed(offset: 1);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(paneHighlight(tester), 'I Will Survive');
      expect(field.controller!.text, 'i');
      expect(field.controller!.selection, const TextSelection.collapsed(offset: 1));
      // Enter in the field is the field's
      await press(tester, LogicalKeyboardKey.enter);
      expect(paneHighlight(tester), 'I Will Survive');
    });

    testWidgets('with nothing selected in the list, ↓ selects its first row', (tester) async {
      await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(paneHighlight(tester), 'Song of Storms');
    });

    testWidgets('the list scrolls just enough to keep the selected row in view', (tester) async {
      await pumpApp(tester, size: desk, state: moreHighlights(30));
      final list = tester.getRect(
        find.descendant(of: find.byType(HighlightsPage), matching: find.byType(CustomScrollView)),
      );
      final position = tester
          .state<ScrollableState>(
            find.descendant(of: find.byType(HighlightsPage), matching: find.byType(Scrollable)).last,
          )
          .position;
      Rect selectedRow() => tester.getRect(find.byWidgetPredicate((w) => w is HighlightRow && (w.selected ?? false)));
      for (var i = 0; i < 15; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(selectedRow().bottom, moreOrLessEquals(list.bottom), reason: 'just in view at the bottom');
      final offset = position.pixels;
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(position.pixels, offset, reason: 'in view already: no scroll');
      for (var i = 0; i < 12; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(selectedRow().top, moreOrLessEquals(list.top), reason: 'just in view at the top');
    });

    testWidgets('the Ong Log: the plays, not the headers, in view under the pinned header', (tester) async {
      await pumpApp(tester, size: desk, state: moreStreams(12));
      await goToTab(tester, 'Ong Log');
      final list = find.descendant(of: find.byType(OngLogPage), matching: find.byType(CustomScrollView));
      final listRect = tester.getRect(list);
      final position = tester
          .state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable)))
          .position;
      Finder selectedPlay() => find.byWidgetPredicate((w) => w is PlayRow && (w.selected ?? false));
      final first = tester.widget<PlayRow>(selectedPlay()).play;
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(tester.widget<PlayRow>(selectedPlay()).play.id, first.id - 1);
      // past the end of the first stream: over its header, to the first play of the next one
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      final next = tester.widget<PlayRow>(selectedPlay()).play;
      expect(next.streamId, first.streamId - 1);
      expect(next.id, first.id - 6);
      expect(paneFiche(tester, AppTab.ongLog), isA<SongSheet>());
      // further down: the list follows
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(position.pixels, greaterThan(0));
      expect(tester.getRect(selectedPlay()).bottom, moreOrLessEquals(listRect.bottom));
      // back up: each row comes out below the pinned header, never under it
      final header = ListMetrics.of(tester.element(list)).streamHeader;
      for (var i = 0; i < 12; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(tester.getRect(selectedPlay()).top, greaterThanOrEqualTo(listRect.top + header - 0.01));
        expect(tester.getRect(selectedPlay()).bottom, lessThanOrEqualTo(listRect.bottom + 0.01));
      }
    });

    testWidgets('a selected header: ↓ its first play, ↑ the play above it', (tester) async {
      await pumpApp(tester, size: desk);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == 0));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(tester.widget<PlayRow>(playRow(1)).selected, isTrue);
      await tester.tap(find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == 0));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(tester.widget<PlayRow>(playRow(2)).selected, isTrue);
    });

    testWidgets('no arrows in a medium window, nor under a sheet', (tester) async {
      await pumpApp(tester, size: medium);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(find.byType(BottomSheet), findsNothing);
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(paneHighlight(tester), "How Far I'll Go");
    });

    testWidgets('/ and Ctrl+F still reach the search field', (tester) async {
      await pumpApp(tester, size: desk);
      FocusNode field() => tester.widget<TextField>(searchField()).focusNode!;
      await press(tester, LogicalKeyboardKey.slash);
      expect(field().hasFocus, isTrue);
      field().unfocus();
      await tester.pumpAndSettle();
      expect(field().hasFocus, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(field().hasFocus, isTrue);
      expect(tester.widget<TextField>(searchField()).controller!.text, isEmpty);
    });

    testWidgets('Enter on a focused control is the control\'s', (tester) async {
      final app = await pumpApp(tester, size: desk);
      await tester.tap(highlightRow('I Will Survive'));
      await tester.pumpAndSettle();
      // the keyboard focus on another row (Tab would bring it there): Enter chooses that row, it starts no video
      Focus.of(
        tester.element(find.descendant(of: highlightRow('Song of Storms'), matching: find.text('Song of Storms'))),
      ).requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter);
      expect(app.effects.opened, isEmpty);
      expect(paneHighlight(tester), 'Song of Storms');
    });
  });

  group('nothing moves', () {
    /// The rects of what row [row] draws.
    List<Rect> partsOf(WidgetTester tester, Finder row) => [
      for (final e
          in find
              .descendant(of: row, matching: find.byWidgetPredicate((w) => w is RichText || w is RawImage || w is Icon))
              .evaluate())
        tester.getRect(find.byElementPredicate((x) => x == e)),
    ];

    testWidgets('selecting and hovering a row change colours only', (tester) async {
      await pumpApp(tester, size: desk, pointer: PointerKind.mouse);
      final row = highlightRow('I Will Survive');
      final before = partsOf(tester, row);
      final rowRect = tester.getRect(row);
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(tester.getCenter(row) + const Offset(100, 0)));
      await tester.pumpAndSettle();
      expect(partsOf(tester, row), before);
      await tester.tap(row, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(selected(tester, 'I Will Survive'), isTrue);
      expect(partsOf(tester, row), before);
      expect(tester.getRect(row), rowRect);

      await goToTab(tester, 'Ong Log');
      final header = find.byWidgetPredicate((w) => w is StreamHeader && w.stream.id == 0);
      final headerParts = partsOf(tester, header);
      await tester.tap(header, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(tester.widget<StreamHeader>(header).selected, isTrue);
      expect(partsOf(tester, header), headerParts);
      final play = playRow(1);
      final playParts = partsOf(tester, play);
      await tester.tap(play, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(partsOf(tester, play), playParts);
    });

    testWidgets('a selection change builds the two rows concerned again, not the list', (tester) async {
      await pumpApp(tester, size: desk, state: moreHighlights(10));
      final builds = <String, int>{};
      // count the builds through the rows' semantics, which every build of a row makes again
      final shown = tester.widgetList<HighlightRow>(find.byType(HighlightRow)).map((r) => r.highlight.track).toList();
      final before = {for (final t in shown) t: tester.widget<HighlightRow>(highlightRow(t))};
      await tester.tap(highlightRow(shown[1]));
      await tester.pumpAndSettle();
      for (final t in shown) {
        if (!identical(tester.widget<HighlightRow>(highlightRow(t)), before[t])) builds[t] = 1;
      }
      expect(builds.keys.toSet(), {shown[0], shown[1]});
    });
  });

  group('screen readers and focus', () {
    testWidgets('the selected row is announced as selected', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: desk);
      expect(tester.getSemantics(highlightRow("How Far I'll Go")), isSemantics(isSelected: true, isButton: true));
      expect(tester.getSemantics(highlightRow('I Will Survive')), isSemantics(isSelected: false, isButton: true));
      await goToTab(tester, 'Ong Log');
      expect(tester.getSemantics(playRow(3)).getSemanticsData().flagsCollection.isSelected, Tristate.isTrue);
      expect(tester.getSemantics(playRow(2)).getSemanticsData().flagsCollection.isSelected, Tristate.isFalse);
      handle.dispose();
    });

    testWidgets('a compact window says nothing of a selection', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      final data = tester.getSemantics(find.byType(HighlightRow).first).getSemanticsData();
      expect(data.flagsCollection.isSelected, Tristate.none);
      handle.dispose();
    });

    testWidgets('the rail, then the list, then the pane', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, size: desk);
      final order = <String>[];
      void visit(SemanticsNode node) {
        final label = node.label;
        if (label.isNotEmpty) order.add(label);
        for (final child in node.debugListChildrenInOrder(DebugSemanticsDumpOrder.traversalOrder)) {
          visit(child);
        }
      }

      visit(tester.binding.renderViews.first.owner!.semanticsOwner!.rootSemanticsNode!);
      int at(Pattern label) => order.indexWhere((l) => l.contains(label));
      expect(at('Ong Log'), greaterThanOrEqualTo(0));
      expect(at('Ong Log'), lessThan(at('Search')));
      expect(at('Search'), lessThan(at('Song of Storms')));
      // the fiche of the pane after every row of the list
      expect(at('Highlight #3'), greaterThan(at('Song of Storms')));
      expect(at('Video unavailable'), greaterThan(at('Song of Storms')));
      handle.dispose();
    });

    testWidgets('Tab goes through the rail, the list pane, then the detail pane', (tester) async {
      await pumpApp(tester, size: desk);
      final rail = tester.getRect(find.byType(AppNavigationRail));
      final list = tester.getRect(find.byType(HighlightsPage));
      final card = tester.getRect(paneCard());
      final regions = <int>[];
      for (var i = 0; i < 40; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        final focus = FocusManager.instance.primaryFocus;
        if (focus == null || focus.context == null) continue;
        final center = focus.rect.center;
        final region = rail.contains(center) ? 0 : (list.contains(center) ? 1 : (card.contains(center) ? 2 : -1));
        if (region < 0) continue;
        if (regions.isEmpty || regions.last != region) regions.add(region);
        if (region == 2) break;
      }
      expect(regions, [0, 1, 2]);
    });
  });

  group('About', () {
    testWidgets('two cards side by side, the footer under both', (tester) async {
      await pumpApp(tester, size: desk);
      await goToTab(tester, 'About');
      final name = tester.getRect(find.text('Jonathan Ong'));
      final appearance = tester.getRect(find.text('Appearance'));
      expect(appearance.left, greaterThan(name.right), reason: 'the settings on the right');
      expect(appearance.top, lessThan(name.top));
      // together 1040 px at most with their margins, centred right of the rail, 16 px apart, 12 from the top
      final cards = tester
          .widgetList<Container>(find.descendant(of: find.byType(AboutPage), matching: find.byType(Container)))
          .where((c) => c.decoration is BoxDecoration && (c.decoration! as BoxDecoration).borderRadius != null)
          .toList();
      final rects = [
        for (final c in cards)
          if ((c.decoration! as BoxDecoration).borderRadius == BorderRadius.circular(28))
            tester.getRect(find.byWidget(c)),
      ];
      expect(rects, hasLength(2));
      const middle = railWidth + (1440 - railWidth) / 2;
      expect(rects[0].top, 12);
      expect(rects[1].left - rects[0].right, 16);
      expect(rects[0].width, rects[1].width);
      expect(rects[1].right - rects[0].left, 1040 - 24);
      expect((rects[0].left + rects[1].right) / 2, middle);
      final footer = tester.getRect(find.text('Fan-made, not affiliated with Jonathan Ong.'));
      expect(footer.top, greaterThan(rects[0].bottom));
      expect(footer.center.dx, middle);
      expect(pane(), findsNothing);
    });

    testWidgets('in the cards, the ring of the picture and the link tiles take the card\'s colours', (tester) async {
      Color ring() => tester
          .widgetList<Container>(find.descendant(of: find.byType(AboutPage), matching: find.byType(Container)))
          .map((c) => c.decoration)
          .whereType<BoxDecoration>()
          .firstWhere((d) => d.boxShadow != null)
          .boxShadow!
          .last
          .color;
      Set<Color?> tiles() => {
        for (final c in tester.widgetList<Container>(
          find.descendant(of: find.byType(AboutPage), matching: find.byType(Container)),
        ))
          if (c.decoration case BoxDecoration(:final borderRadius?) when borderRadius == BorderRadius.circular(18))
            (c.decoration! as BoxDecoration).color,
      };
      await pumpApp(tester, size: desk);
      await goToTab(tester, 'About');
      final scheme = Theme.of(tester.element(find.byType(AboutPage))).colorScheme;
      expect(ring(), scheme.surfaceContainer);
      expect(tiles(), {scheme.surfaceContainerHigh});
      // one column: on the background, as before
      tester.view.physicalSize = medium;
      await tester.pumpAndSettle();
      expect(ring(), scheme.surface);
      expect(tiles(), {scheme.surfaceContainer});
    });

    testWidgets('one column in a medium window', (tester) async {
      await pumpApp(tester, size: medium);
      await goToTab(tester, 'About');
      final name = tester.getRect(find.text('Jonathan Ong'));
      final appearance = tester.getRect(find.text('Appearance'));
      expect(appearance.top, greaterThan(name.bottom));
      expect(tester.getRect(find.byType(AboutPage)).width, 640);
    });
  });
}
