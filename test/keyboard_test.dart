// The keyboard in the lists and the chips: one stop of the Tab key each, the arrows inside, the page and end keys
// (⌘↑ ⌘↓ on Apple devices, Ctrl+Home Ctrl+End elsewhere), the controls of a row, the search field's own keys, the
// cursor kept while its row is scrolled away, and what a move builds again.
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show listEquals;

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/detail_pane.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/instant_feedback.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/list_scaffold.dart';
import 'package:ong_music/src/ui/nav_rail.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/top_bar.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// A desktop browser window: expanded.
const desk = Size(1440, 900);

/// A window too narrow for the detail pane: medium.
const narrow = Size(700, 900);

/// The test catalogue with [count] more highlights ("Song 1"…, without video), in genres enough for the chips to
/// scroll on a phone.
CatalogueState moreHighlights(int count) => CatalogueState(
  catalogue: testCatalogue(
    moreHighlights: [
      for (var i = 1; i <= count; i++)
        hRow(
          order: '${3 + i}',
          title: 'Song $i',
          genre: const [
            'ANIME',
            'CLASSICAL',
            'MUSICALS',
            'JAZZ/STANDARDS',
            'CHRISTMAS MUSIC',
            'FILM/TELEVISION',
          ][i % 6],
        ),
    ],
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

/// Presses [key] with the modifiers asked, lets the frames through; whether the app handled it.
Future<bool> press(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
  bool control = false,
  bool meta = false,
}) async {
  final modifiers = [
    if (shift) LogicalKeyboardKey.shiftLeft,
    if (control) LogicalKeyboardKey.controlLeft,
    if (meta) LogicalKeyboardKey.metaLeft,
  ];
  for (final m in modifiers) {
    await tester.sendKeyDownEvent(m);
  }
  final handled = await tester.sendKeyEvent(key);
  for (final m in modifiers.reversed) {
    await tester.sendKeyUpEvent(m);
  }
  await tester.pumpAndSettle();
  return handled;
}

/// The context of the focused node.
BuildContext? focused() => FocusManager.instance.primaryFocus?.context;

/// Whether the focus is under a widget of [type].
bool focusUnder<T extends Widget>() => focused()?.findAncestorWidgetOfExactType<T>() != null;

/// The index (in the list as it builds its items) of the row or header with the focus, or of the row of the focused
/// control; null out of the list.
int? focusedIndex() {
  int? index;
  focused()?.visitAncestorElements((e) {
    final w = e.widget;
    if (w is IndexedSemantics) index = w.index;
    return index == null;
  });
  return index;
}

/// Where the focus is: the search field, the chips, the list, the detail pane, the top bar, the navigation, or
/// elsewhere ('none' without focus).
String region() {
  final context = focused();
  if (context == null || FocusManager.instance.primaryFocus is FocusScopeNode) return 'none';
  // the list's own node, which holds the focus when the focused row is gone
  if (FocusManager.instance.primaryFocus?.debugLabel == 'list') return 'list';
  if (context.findAncestorWidgetOfExactType<ListSearchField>() != null) return 'search';
  if (context.findAncestorWidgetOfExactType<ChipRow>() != null) return 'chips';
  if (context.findAncestorWidgetOfExactType<DetailPane>() != null) return 'pane';
  if (context.findAncestorWidgetOfExactType<AppTopBar>() != null) return 'bar';
  if (context.findAncestorWidgetOfExactType<NavigationBar>() != null ||
      context.findAncestorWidgetOfExactType<AppNavigationRail>() != null) {
    return 'nav';
  }
  if (focusedIndex() != null || context.findAncestorWidgetOfExactType<StreamHeader>() != null) return 'list';
  return 'elsewhere';
}

/// The stops of Tab (or Shift+Tab) from where the focus is, as regions, until the focus comes back to [until]
/// (default: where it started), at most [max].
Future<List<String>> tabStops(WidgetTester tester, {bool back = false, String? until, int max = 30}) async {
  final first = until ?? region();
  final stops = <String>[];
  for (var i = 0; i < max; i++) {
    await press(tester, LogicalKeyboardKey.tab, shift: back);
    final stop = region();
    if (stop == first) break;
    stops.add(stop);
  }
  return stops;
}

/// The scroll position of the list of [page].
ScrollPosition listPosition(WidgetTester tester, [Type page = HighlightsPage]) => tester
    .state<ScrollableState>(
      find.descendant(
        of: find.descendant(of: find.byType(page), matching: find.byType(CustomScrollView)),
        matching: find.byType(Scrollable),
      ),
    )
    .position;

/// The rect of the list of [page] on screen.
Rect listRect(WidgetTester tester, [Type page = HighlightsPage]) =>
    tester.getRect(find.descendant(of: find.byType(page), matching: find.byType(CustomScrollView)));

/// The rect on screen of the focused node.
Rect focusRect() => FocusManager.instance.primaryFocus!.rect;

/// The index of the highlight the detail pane shows, in the list.
int paneIndex(WidgetTester tester) {
  final shown = tester
      .widget<HighlightSheet>(find.descendant(of: find.byType(DetailPane), matching: find.byType(HighlightSheet)))
      .highlight;
  final rows = tester.widgetList<HighlightRow>(find.byType(HighlightRow)).toList();
  final row = rows.firstWhere((r) => r.highlight.id == shown.id);
  return tester
      .widget<IndexedSemantics>(find.ancestor(of: find.byWidget(row), matching: find.byType(IndexedSemantics)).first)
      .index;
}

/// The index of the selected row of the list (an expanded window).
int selectedIndex(WidgetTester tester) => tester
    .widget<IndexedSemantics>(
      find
          .ancestor(
            of: find.byWidgetPredicate(
              (w) => (w is HighlightRow || w is PlayRow) && ((w as dynamic).selected ?? false),
            ),
            matching: find.byType(IndexedSemantics),
          )
          .first,
    )
    .index;

/// Puts the focus in the search field of the tab on screen, without pointer (a touch would change the highlight
/// mode).
Future<void> focusSearch(WidgetTester tester) async {
  tester.widget<TextField>(searchField()).focusNode!.requestFocus();
  await tester.pumpAndSettle();
}

/// Brings the focus to the list of a narrow window (↓ from the search field).
Future<void> enterList(WidgetTester tester) async {
  await focusSearch(tester);
  await press(tester, LogicalKeyboardKey.arrowDown);
  expect(region(), 'list');
}

/// The three looks: a phone or tablet (Material's ink), and a computer (the desktop look) in a window without and
/// with the detail pane.
enum Look { phone, deskNarrow, deskWide }

/// Pumps the app in [look] with [state].
Future<TestApp> pumpLook(WidgetTester tester, Look look, CatalogueState state) => pumpApp(
  tester,
  state: state,
  size: switch (look) {
    Look.phone => const Size(412, 892),
    Look.deskNarrow => narrow,
    Look.deskWide => desk,
  },
  desktop: look != Look.phone,
);

/// Brings the focus to the first row of the list, as a keyboard user would in [look].
Future<void> intoList(WidgetTester tester, Look look) async {
  if (look == Look.deskWide) {
    await focusSearch(tester);
    await press(tester, LogicalKeyboardKey.tab);
    await press(tester, LogicalKeyboardKey.tab);
    expect(region(), 'list');
  } else {
    await enterList(tester);
  }
}

/// The highlight of the focused row, or null.
String? focusedTrack() => focused()?.findAncestorWidgetOfExactType<HighlightRow>()?.highlight.track;

/// The first highlight row in full view of the list of the Highlights tab.
int firstInFullView(WidgetTester tester) {
  final extent = ListMetrics.of(tester.element(find.byType(HighlightsPage))).highlightRow;
  return (listPosition(tester).pixels / extent - 0.001).ceil();
}

/// [moreHighlights] with, newest of all, "Brand new" (refreshed: a new highlight at the top of the list), and
/// without the highlights titled in [without].
CatalogueState refreshed(int count, {bool brandNew = true, Set<String> without = const {}}) => CatalogueState(
  catalogue: testCatalogue(
    moreHighlights: [
      for (var i = 1; i <= count; i++)
        if (!without.contains('Song $i'))
          hRow(
            order: '${3 + i}',
            title: 'Song $i',
            genre: const [
              'ANIME',
              'CLASSICAL',
              'MUSICALS',
              'JAZZ/STANDARDS',
              'CHRISTMAS MUSIC',
              'FILM/TELEVISION',
            ][i % 6],
          ),
      if (brandNew) hRow(order: '999', title: 'Brand new', genre: 'ANIME'),
    ],
  ),
  fetchedAt: testNow,
);

/// The test catalogue with a newest stream of [blank] plays without fiche (titles without letter or digit), and,
/// unless [only], [moreStreams]' 12 streams under it.
CatalogueState blankPlays(int blank, {bool only = false}) => CatalogueState(
  catalogue: only
      ? catalogueOf(
          highlights: [hRow(title: 'Some video')],
          songs: [
            for (var s = 0; s < 3; s++) ...[
              start('2024-05-0${s + 1}'),
              for (var p = 0; p < blank; p++)
                sRow(date: '2024-05-0${s + 1} 20:${p.toString().padLeft(2, '0')}:00', title: '—'),
            ],
          ],
        )
      : testCatalogue(
          moreSongs: [
            for (var s = 0; s < 12; s++) ...[
              start('2024-04-${(s + 1).toString().padLeft(2, '0')}'),
              for (var p = 0; p < 6; p++)
                sRow(
                  date: '2024-04-${(s + 1).toString().padLeft(2, '0')} 20:0$p:00',
                  title: 'Tune $s.$p',
                  type: 'Piano',
                ),
            ],
            start('2024-05-01'),
            for (var p = 0; p < blank; p++) sRow(date: '2024-05-01 20:${p.toString().padLeft(2, '0')}:00', title: '—'),
          ],
        ),
  fetchedAt: testNow,
);

/// The pixels [box] shows on screen.
Future<Uint8List> pixelsOf(WidgetTester tester, RenderBox box) async {
  final root = tester.binding.renderViews.first;
  final rect = MatrixUtils.transformRect(box.getTransformTo(root), Offset.zero & box.size);
  final image = await (root.debugLayer! as OffsetLayer).toImage(rect);
  final data = await tester.runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba));
  image.dispose();
  return data!.buffer.asUint8List();
}

final mac = TargetPlatformVariant.only(TargetPlatform.macOS);
final windows = TargetPlatformVariant.only(TargetPlatform.windows);

void main() {
  group('the keys', () {
    test('what each key asks of a list, on Apple devices and elsewhere', () {
      // the decoding reads the modifiers of the hardware keyboard: none here
      KeyDownEvent down(LogicalKeyboardKey key) =>
          KeyDownEvent(physicalKey: PhysicalKeyboardKey.keyA, logicalKey: key, timeStamp: Duration.zero);
      expect(listCommandOf(down(LogicalKeyboardKey.pageDown)), ListCommand.pageDown);
      expect(listCommandOf(down(LogicalKeyboardKey.home)), ListCommand.home);
      expect(listCommandOf(down(LogicalKeyboardKey.contextMenu)), ListCommand.menu);
      expect(listCommandOf(down(LogicalKeyboardKey.keyA)), isNull);
      expect(
        listCommandOf(
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.arrowDown,
            logicalKey: LogicalKeyboardKey.arrowDown,
            timeStamp: Duration.zero,
          ),
        ),
        ListCommand.down,
        reason: 'a held arrow repeats',
      );
      expect(
        listCommandOf(
          const KeyRepeatEvent(
            physicalKey: PhysicalKeyboardKey.enter,
            logicalKey: LogicalKeyboardKey.enter,
            timeStamp: Duration.zero,
          ),
        ),
        isNull,
        reason: 'a held Enter starts nothing again',
      );
      expect(
        listCommandOf(
          const KeyUpEvent(
            physicalKey: PhysicalKeyboardKey.arrowDown,
            logicalKey: LogicalKeyboardKey.arrowDown,
            timeStamp: Duration.zero,
          ),
        ),
        isNull,
      );
    });
  });

  group('Tab: the list and the chips are one stop each', () {
    testWidgets('a phone: the search field, the chips, the list, the navigation; and back', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await focusSearch(tester);
      final forward = await tabStops(tester);
      expect(forward.where((s) => s == 'chips'), hasLength(1));
      expect(forward.where((s) => s == 'list'), hasLength(1));
      expect(forward.take(3), ['chips', 'list', 'nav']);
      // in the list: the first row, the list where it was
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'list');
      expect(focusedIndex(), 0);
      expect(listPosition(tester).pixels, 0);
      // backwards: one stop too
      final backward = await tabStops(tester, back: true, until: 'list');
      expect(backward.take(2), ['chips', 'search']);
      expect(backward.where((s) => s == 'list'), isEmpty);
    });

    testWidgets('the desktop look, expanded: the bar, the search field, the chips, the list, the pane', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      await focusSearch(tester);
      final stops = await tabStops(tester);
      final regions = <String>[];
      for (final s in stops) {
        if (regions.isEmpty || regions.last != s) regions.add(s);
      }
      expect(regions, ['chips', 'list', 'pane', 'bar']);
      expect(stops.where((s) => s == 'chips' || s == 'list'), hasLength(2));
      // Shift+Tab from the pane: the list, on its selected row
      while (region() != 'pane') {
        await press(tester, LogicalKeyboardKey.tab);
      }
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(region(), 'list');
      expect(focusedIndex(), selectedIndex(tester));
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(region(), 'chips');
    });

    testWidgets('the Ong Log: one stop, headers, rows and video buttons together', (tester) async {
      await pumpApp(tester, size: narrow, desktop: true, state: moreStreams(4));
      await goToTab(tester, 'Ong Log');
      await focusSearch(tester);
      final stops = await tabStops(tester);
      expect(stops.where((s) => s == 'list'), hasLength(1));
      expect(stops.take(2), ['chips', 'list']);
    });

    testWidgets('from a control of a row, Tab leaves the list, Shift+Tab too', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<IconButton>(), isTrue, reason: 'the ⋮ of the row');
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'nav');
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(region(), 'chips');
    });
  });

  group('the arrows in the list', () {
    testWidgets('a phone: ↓ from the search field brings the focus to the list, ↓ and ↑ go from row to row', (
      tester,
    ) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      expect(focusedIndex(), 0);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), 2);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIndex(), 1);
      // the row itself, not one of its controls
      expect(focusUnder<IconButton>(), isFalse);
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIndex(), 0, reason: 'the first row stays');
      // held down: the focused row stays in view at the bottom
      final list = listRect(tester);
      for (var i = 0; i < 20; i++) {
        await tester.sendKeyRepeatEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(focusedIndex(), 20);
      expect(focusRect().bottom, moreOrLessEquals(list.bottom));
    });

    testWidgets('with nothing focused on a phone, ↓ brings the focus to the list; ↑ too', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      expect(region(), 'none');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), 0);
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIndex(), 0, reason: 'back on the row left, still in view');
    });

    testWidgets('expanded: the focus and the selection move together, one cursor', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'list');
      expect(focusedIndex(), 0);
      for (var i = 0; i < 3; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedIndex(), i + 1);
        expect(selectedIndex(tester), i + 1);
        expect(paneIndex(tester), i + 1);
      }
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIndex(), 2);
      expect(selectedIndex(tester), 2);
    });

    testWidgets('expanded: Enter on the focused selected row starts its video; Space chooses a row as a click does', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: desk, desktop: true);
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      // "How Far I'll Go" (no video), then "I Will Survive"
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(selectedIndex(tester), 1);
      // the focus on another row without choosing it (as Tab could bring it there): Space chooses it, as a click
      Focus.of(
        tester.element(find.descendant(of: find.byType(HighlightRow).at(2), matching: find.byType(Text)).first),
      ).requestFocus();
      await tester.pumpAndSettle();
      expect(focusedIndex(), 2);
      expect(selectedIndex(tester), 1);
      await press(tester, LogicalKeyboardKey.space);
      expect(selectedIndex(tester), 2, reason: 'chosen');
      expect(app.effects.opened, isEmpty, reason: 'Space does not start the video');
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.enter);
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
    });

    testWidgets('the Ong Log: ← goes to the header of the stream, → back to the play, ↓ to its first play', (
      tester,
    ) async {
      await pumpApp(tester, size: narrow, desktop: true, state: moreStreams(12));
      await goToTab(tester, 'Ong Log');
      await enterList(tester);
      // item 0 is the header of the first stream, item 1 its first play
      expect(focusedIndex(), 1);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), 3);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusUnder<StreamHeader>(), isTrue);
      expect(focusedIndex(), 0);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIndex(), 3, reason: 'the play it was left for');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), 1, reason: 'the play under the header');
      // → from a header reached otherwise than by ←: its first play
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedIndex(), 1, reason: 'the first play stays');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedIndex(), 0);
      // the six plays of the stream, then over the next header to the next play
      for (var i = 0; i < 7; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedIndex(), 8);
      expect(focusUnder<StreamHeader>(), isFalse);
    });

    testWidgets('the Ong Log: ← on a play whose header went up shows the focus on the pinned header', (tester) async {
      await pumpApp(tester, size: narrow, desktop: true, state: moreStreams(12));
      await goToTab(tester, 'Ong Log');
      await enterList(tester);
      for (var i = 0; i < 20; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      final position = listPosition(tester, OngLogPage);
      // the play 100 px below the top of the list, its header above it: the pinned header stands for it
      position.jumpTo(position.pixels + focusRect().top - listRect(tester, OngLogPage).top - 100);
      await tester.pumpAndSettle();
      expect(focusUnder<PlayRow>(), isTrue);
      final index = focusedIndex()!;
      final pixels = position.pixels;
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusUnder<StreamHeader>(), isTrue);
      expect(focusedIndex(), isNull, reason: 'not the header of the list, under the pinned one');
      expect(focusRect().top, moreOrLessEquals(listRect(tester, OngLogPage).top));
      expect(position.pixels, pixels, reason: 'nothing moved');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<StreamHeader>(), isFalse);
      expect(focusedIndex(), lessThanOrEqualTo(index));
    });

    testWidgets('a control of a row: → to it, ← back, ↓ to the next row; Enter is its own', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<IconButton>(), isTrue);
      expect(focusedIndex(), 0);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<IconButton>(), isTrue, reason: 'the last control stays');
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusUnder<IconButton>(), isFalse);
      expect(focusedIndex(), 0);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusUnder<IconButton>(), isFalse);
      expect(focusedIndex(), 1);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(BottomSheet), findsOneWidget, reason: 'the details of the ⋮');
    });

    testWidgets('a play: → to its video button, ← back; a play without video has none', (tester) async {
      await pumpApp(tester, size: narrow, desktop: true);
      await goToTab(tester, 'Ong Log');
      await enterList(tester);
      // the first play has no video: → stays on it
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<VideoPill>(), isFalse);
      expect(focusedIndex(), 1);
      // "Song of Storms" has the video of highlight #1
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<VideoPill>(), isTrue);
      expect(focusedIndex(), 2);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusUnder<VideoPill>(), isFalse);
      expect(focusedIndex(), 2);
    });

    testWidgets('the context-menu key and Shift+F10 open the details of the row', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(find.byType(BottomSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(region(), 'list', reason: 'the focus back on the row');
      await press(tester, LogicalKeyboardKey.f10, shift: true);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('the page and end keys', () {
    testWidgets('Page Down and Page Up: a page further, the cursor at the same height; ↓ goes on from there', (
      tester,
    ) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final position = listPosition(tester);
      final top = focusRect().top;
      final before = focusedIndex()!;
      expect(await press(tester, LogicalKeyboardKey.pageDown), isTrue);
      expect(position.pixels, moreOrLessEquals(position.viewportDimension));
      final after = focusedIndex()!;
      expect(after, greaterThan(before + 5));
      expect(focusRect().top, moreOrLessEquals(top, epsilon: 86));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), after + 1, reason: 'from what the list shows, not back');
      await press(tester, LogicalKeyboardKey.pageUp);
      expect(position.pixels, 0);
      expect(focusedIndex(), lessThanOrEqualTo(before + 1));
      await press(tester, LogicalKeyboardKey.pageUp);
      expect(focusedIndex(), 0, reason: 'at the top: the first row');
      // to the end, a page at a time: the last row
      for (var i = 0; i < 6; i++) {
        await press(tester, LogicalKeyboardKey.pageDown);
      }
      expect(position.pixels, position.maxScrollExtent);
      expect(focusedIndex(), 32);
    });

    testWidgets('Home and End: the first and the last row', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      final position = listPosition(tester);
      await press(tester, LogicalKeyboardKey.end);
      expect(focusedIndex(), 32);
      expect(position.pixels, position.maxScrollExtent);
      await press(tester, LogicalKeyboardKey.home);
      expect(focusedIndex(), 0);
      expect(position.pixels, 0);
    });

    testWidgets('⌘↓ and ⌘↑ on a Mac; Ctrl+End is nothing there', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      final position = listPosition(tester);
      await press(tester, LogicalKeyboardKey.arrowDown, meta: true);
      expect(focusedIndex(), 32);
      expect(position.pixels, position.maxScrollExtent);
      await press(tester, LogicalKeyboardKey.arrowUp, meta: true);
      expect(focusedIndex(), 0);
      await press(tester, LogicalKeyboardKey.end, control: true);
      expect(focusedIndex(), 0);
    }, variant: mac);

    testWidgets('Ctrl+End and Ctrl+Home elsewhere; ⌘↓ is nothing there', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.end, control: true);
      expect(focusedIndex(), 32);
      await press(tester, LogicalKeyboardKey.home, control: true);
      expect(focusedIndex(), 0);
      expect(await press(tester, LogicalKeyboardKey.arrowDown, meta: true), isFalse);
      expect(focusedIndex(), 0);
    }, variant: windows);

    testWidgets('with nothing focused on a phone, they scroll the list, the focus left out of it', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      final position = listPosition(tester);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(position.pixels, moreOrLessEquals(position.viewportDimension));
      expect(region(), 'none');
      await press(tester, LogicalKeyboardKey.end);
      expect(position.pixels, position.maxScrollExtent);
      await press(tester, LogicalKeyboardKey.home);
      expect(position.pixels, 0);
      await press(tester, LogicalKeyboardKey.pageDown);
      // ↓ then enters the list on what it shows
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(region(), 'list');
      expect(focusRect().top, greaterThanOrEqualTo(listRect(tester).top));
      expect(position.pixels, moreOrLessEquals(position.viewportDimension));
    });

    testWidgets('expanded, nothing focused: they move the selection, the list follows', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      final position = listPosition(tester);
      await press(tester, LogicalKeyboardKey.pageDown);
      final paged = selectedIndex(tester);
      expect(paged, greaterThan(5));
      expect(position.pixels, greaterThan(0));
      expect(paneIndex(tester), paged);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(selectedIndex(tester), paged + 1);
      await press(tester, LogicalKeyboardKey.end);
      expect(selectedIndex(tester), 32);
      await press(tester, LogicalKeyboardKey.home);
      expect(selectedIndex(tester), 0);
      expect(position.pixels, 0);
      expect(region(), 'none');
    });

    testWidgets('the Ong Log: Page Down keeps the focused play below the pinned header', (tester) async {
      await pumpApp(tester, size: narrow, desktop: true, state: moreStreams(12));
      await goToTab(tester, 'Ong Log');
      await enterList(tester);
      final list = listRect(tester, OngLogPage);
      final header = ListMetrics.of(tester.element(find.byType(OngLogPage))).streamHeader;
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.pageDown);
        expect(focusUnder<PlayRow>(), isTrue);
        expect(focusRect().top, greaterThanOrEqualTo(list.top + header - 0.01));
        expect(focusRect().bottom, lessThanOrEqualTo(list.bottom + 0.01));
      }
      for (var i = 0; i < 5; i++) {
        await press(tester, LogicalKeyboardKey.pageUp);
        expect(focusRect().top, greaterThanOrEqualTo(list.top + header - 0.01));
      }
    });
  });

  group('the search field keeps the keys of its line', () {
    /// The search field with "song" in it, its cursor after "so"; its controller.
    Future<TextEditingController> typed(WidgetTester tester) async {
      await focusSearch(tester);
      await tester.enterText(searchField(), 'song');
      await tester.pumpAndSettle();
      final controller = tester.widget<TextField>(searchField()).controller!;
      controller.selection = const TextSelection.collapsed(offset: 2);
      return controller;
    }

    testWidgets('Home, End, ← and → move its cursor; the list stays', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      final controller = await typed(tester);
      final position = listPosition(tester);
      await press(tester, LogicalKeyboardKey.home);
      expect(controller.selection.extentOffset, 0);
      await press(tester, LogicalKeyboardKey.end);
      expect(controller.selection.extentOffset, 4);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(controller.selection.extentOffset, 3);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(controller.selection.extentOffset, 4);
      expect(position.pixels, 0);
      expect(region(), 'search');
      // Ctrl+Home: the list's (in one line, the same as Home for the field)
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(position.pixels, greaterThan(0));
      await press(tester, LogicalKeyboardKey.home, control: true);
      expect(position.pixels, 0);
      expect(controller.selection.extentOffset, 4);
      expect(region(), 'search');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(region(), 'search', reason: '↑ stays the field\'s');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(region(), 'list');
    });

    testWidgets('a Mac: ⌘← and Home are the field\'s, Page Down and ⌘↓ the list\'s', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      final controller = await typed(tester);
      final position = listPosition(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft, meta: true);
      expect(controller.selection.extentOffset, 0, reason: "the field's ⌘←");
      controller.selection = const TextSelection.collapsed(offset: 2);
      // a Mac field does not move its cursor with Home: nothing moves
      await press(tester, LogicalKeyboardKey.home);
      expect(controller.selection.extentOffset, 2);
      expect(position.pixels, 0);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(position.pixels, greaterThan(0));
      await press(tester, LogicalKeyboardKey.arrowUp, meta: true);
      expect(position.pixels, 0);
      await press(tester, LogicalKeyboardKey.arrowDown, meta: true);
      expect(position.pixels, position.maxScrollExtent);
      expect(region(), 'search');
      expect(controller.text, 'song');
      expect(controller.selection.extentOffset, 2);
    }, variant: mac);

    testWidgets('expanded: Page Down from the search field moves the selection, the focus stays', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(selectedIndex(tester), greaterThan(5));
      expect(region(), 'search');
      await press(tester, LogicalKeyboardKey.home);
      expect(selectedIndex(tester), greaterThan(5), reason: 'Home is the field\'s');
    });

    testWidgets('/ from the list still reaches the search field, Escape still clears it', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.slash);
      expect(region(), 'search');
      await tester.enterText(searchField(), 'song');
      await press(tester, LogicalKeyboardKey.escape);
      expect(tester.widget<TextField>(searchField()).controller!.text, isEmpty);
    });
  });

  group('the cursor while its row is away', () {
    testWidgets('Tab comes back on the row left when it is in view, on the first row in view otherwise', (
      tester,
    ) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), 2);
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'nav');
      final position = listPosition(tester);
      // scrolled away: the row is no longer built
      position.jumpTo(1500);
      await tester.pumpAndSettle();
      expect(find.text('Song 28'), findsNothing);
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(region(), 'list');
      final extent = ListMetrics.of(tester.element(find.byType(HighlightsPage))).highlightRow;
      expect(focusedIndex(), (1500 / extent).ceil(), reason: 'the first row in full view');
      expect(position.pixels, 1500, reason: 'the list stays where it is');
      // the row left in view again: Tab comes back to it
      await press(tester, LogicalKeyboardKey.home);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.tab);
      position.jumpTo(40);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(focusedIndex(), 2);
      expect(position.pixels, 40);
    });

    testWidgets('a focused row scrolled away: the keys go on from what the list shows', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final position = listPosition(tester);
      position.jumpTo(1500);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(region(), 'list');
      final extent = ListMetrics.of(tester.element(find.byType(HighlightsPage))).highlightRow;
      expect(focusedIndex(), (1500 / extent).ceil());
      expect(position.pixels, 1500);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), (1500 / extent).ceil() + 1);
    });

    testWidgets('expanded: the selection scrolled away, ↓ selects the first row in view', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      final position = listPosition(tester);
      position.jumpTo(1000);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      final extent = ListMetrics.of(tester.element(find.byType(HighlightsPage))).highlightRow;
      expect(selectedIndex(tester), (1000 / extent).ceil());
      expect(position.pixels, 1000);
    });
  });

  group('the chips', () {
    /// The labels of the chips, in order.
    List<String> chipLabels(WidgetTester tester) => [
      for (final c in tester.widgetList<ListChip>(
        find.descendant(of: find.byType(HighlightsPage), matching: find.byType(ListChip)),
      ))
        c.label,
    ];

    /// The label of the chip with the focus.
    String? focusedChip() => focused()?.findAncestorWidgetOfExactType<ListChip>()?.label;

    /// The rect of the row of chips.
    Rect chipRow(WidgetTester tester) =>
        tester.getRect(find.descendant(of: find.byType(HighlightsPage), matching: find.byType(ChipRow)));

    testWidgets('Tab enters on the selected chip; ← → go from chip to chip without selecting, into view', (
      tester,
    ) async {
      await pumpApp(tester, state: moreHighlights(30), pointer: PointerKind.mouse);
      final labels = chipLabels(tester);
      expect(labels.length, greaterThan(6));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focusedChip(), 'All');
      final row = chipRow(tester);
      for (var i = 1; i < labels.length; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedChip(), labels[i]);
        // in view, clear of the arrow at the end (with a mouse)
        expect(focusRect().right, lessThanOrEqualTo(row.right - 16));
        expect(focusRect().left, greaterThanOrEqualTo(row.left));
      }
      expect(
        tester.widget<ListChip>(find.byWidgetPredicate((w) => w is ListChip && w.label == 'All')).selected,
        isTrue,
        reason: 'moving selects nothing',
      );
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedChip(), labels.last, reason: 'the last stays');
      await press(tester, LogicalKeyboardKey.home);
      expect(focusedChip(), 'All');
      expect(focusRect().left, greaterThanOrEqualTo(row.left));
      await press(tester, LogicalKeyboardKey.end);
      expect(focusedChip(), labels.last);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedChip(), labels[labels.length - 2]);
      // Space selects, as a click
      await press(tester, LogicalKeyboardKey.space);
      expect(
        tester
            .widget<ListChip>(find.byWidgetPredicate((w) => w is ListChip && w.label == labels[labels.length - 2]))
            .selected,
        isTrue,
      );
      // Tab leaves the chips for the list; Shift+Tab comes back on the selected chip, scrolled into view
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'list');
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: find.byType(ChipRow).hitTestable(), matching: find.byType(Scrollable)),
      );
      scroll.position.jumpTo(0);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(focusedChip(), labels[labels.length - 2]);
      expect(focusRect().right, lessThanOrEqualTo(row.right - 16));
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(region(), 'search');
    });

    testWidgets('↑ ↓ and the page keys from a chip are the list\'s', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'chips');
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(listPosition(tester).pixels, greaterThan(0));
      expect(region(), 'chips');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(region(), 'list');
    });
  });

  group('the focus shows for the keyboard only', () {
    testWidgets('desktop: the row, the chip and the ⋮ show the focus layer; a click on a row takes it away', (
      tester,
    ) async {
      await pumpApp(tester, size: narrow, desktop: true, pointer: PointerKind.mouse, state: moreHighlights(30));

      /// Whether the state layer of the focused control paints (its focus tint).
      bool layerShows() {
        final control = find.byElementPredicate((e) => e == focused());
        final layer = find.descendant(of: control, matching: find.byType(StateLayer)).first;
        final paint = find.descendant(of: layer, matching: find.byType(CustomPaint)).first;
        return (tester.widget<CustomPaint>(paint).painter! as dynamic).color != null;
      }

      await enterList(tester);
      expect(layerShows(), isTrue, reason: 'the row');
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<IconButton>(), isTrue);
      expect(layerShows(), isTrue, reason: 'the ⋮');
      // the chip: its theme colours follow its states (no state layer): it looks other with the focus than without
      await press(tester, LogicalKeyboardKey.tab, shift: true);
      expect(region(), 'chips');
      final chip = focused()!.findRenderObject()! as RenderBox;
      final withFocus = await pixelsOf(tester, chip);
      final node = FocusManager.instance.primaryFocus!;
      node.unfocus();
      await tester.pumpAndSettle();
      expect(listEquals(withFocus, await pixelsOf(tester, chip)), isFalse, reason: 'the chip');
      node.requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'list');
      // a click on another row: the focus leaves the list, no ring is left behind
      await tester.tap(find.byType(HighlightRow).at(3), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(region(), isNot('list'));
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      // and Tab comes back on the row clicked
      FocusManager.instance.primaryFocus?.unfocus();
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(focusedIndex(), 3);
    });

    testWidgets('expanded: a click on a row selects it and takes the keyboard focus out of the list', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, pointer: PointerKind.mouse, state: moreHighlights(30));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedIndex(), 1);
      await tester.tap(find.byType(HighlightRow).at(4), kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      expect(selectedIndex(tester), 4);
      expect(region(), isNot('list'), reason: 'no focus left on row 1 beside the selection on row 4');
      // the keys go on from the row clicked
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(selectedIndex(tester), 5);
    });

    testWidgets('a phone without keyboard: a tap gives the list no focus, the rows are as before', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(find.byType(HighlightRow).at(1));
      await tester.pumpAndSettle();
      expect(region(), 'none');
      expect(FocusManager.instance.highlightMode, FocusHighlightMode.touch);
      expect(app.effects.opened, hasLength(1), reason: 'the row opens its video, as before');
    });
  });

  group('what a move builds again', () {
    /// The row widgets on screen, by index.
    Map<int, Widget> rows(WidgetTester tester) => {
      for (final e in find.byType(HighlightRow).evaluate())
        tester
            .widget<IndexedSemantics>(
              find.ancestor(of: find.byElementPredicate((x) => x == e), matching: find.byType(IndexedSemantics)).first,
            )
            .index: e
            .widget,
    };

    testWidgets('a phone: no row', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      final before = rows(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final after = rows(tester);
      expect([
        for (final i in before.keys)
          if (!identical(before[i], after[i])) i,
      ], isEmpty);
    });

    testWidgets('a sheet opening and closing over the list builds no row again', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      Future<void> sheet(Future<void> Function() open) async {
        await open();
        expect(find.byType(BottomSheet), findsOneWidget);
        Navigator.of(tester.element(find.byType(BottomSheet))).pop();
        await tester.pumpAndSettle();
      }

      // the keys, a sheet from the keyboard, a sheet from a ⋮: then one more
      await press(tester, LogicalKeyboardKey.pageDown);
      await press(tester, LogicalKeyboardKey.home);
      await enterList(tester);
      await sheet(() => press(tester, LogicalKeyboardKey.contextMenu));
      await sheet(() async {
        await tester.tap(detailsButtons().first);
        await tester.pumpAndSettle();
      });
      final before = rows(tester);
      await sheet(() async {
        await tester.tap(detailsButtons().at(1));
        await tester.pumpAndSettle();
      });
      final after = rows(tester);
      expect([
        for (final i in before.keys)
          if (!identical(before[i], after[i])) i,
      ], isEmpty);
    });

    testWidgets('expanded: the two rows whose selection changes, not the list', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final before = rows(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      final after = rows(tester);
      expect(
        [
          for (final i in before.keys)
            if (!identical(before[i], after[i])) i,
        ],
        [1, 2],
      );
    });
  });

  group('elsewhere', () {
    testWidgets('the arrows in the detail pane are not the list\'s', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      final first = selectedIndex(tester);
      // a control of the pane
      await focusSearch(tester);
      while (region() != 'pane') {
        await press(tester, LogicalKeyboardKey.tab);
      }
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(selectedIndex(tester), first);
    });

    testWidgets('a sheet over the list takes the keys', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.contextMenu);
      final position = listPosition(tester);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(position.pixels, 0);
    });

    testWidgets('no keys on the About tab', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await goToTab(tester, 'About');
      expect(await press(tester, LogicalKeyboardKey.pageDown), isFalse);
      await goToTab(tester, 'Highlights');
      expect(listPosition(tester).pixels, 0);
    });
  });

  group('the focused row goes away', () {
    for (final look in Look.values) {
      testWidgets(
        '${look.name}: scrolled out of view, the focus stays in the list; Space types nothing, ↓ lands in view',
        (tester) async {
          await pumpLook(tester, look, moreHighlights(30));
          await intoList(tester, look);
          await press(tester, LogicalKeyboardKey.arrowDown);
          await press(tester, LogicalKeyboardKey.arrowDown);
          final selection = look == Look.deskWide ? selectedIndex(tester) : null;
          // every place the focus goes through, not only where it ends
          final through = <String>[];
          void follow() => through.add(region());
          FocusManager.instance.addListener(follow);
          addTearDown(() => FocusManager.instance.removeListener(follow));
          // the wheel, or the scroll bar
          listPosition(tester).jumpTo(1500);
          await tester.pumpAndSettle();
          expect(region(), 'list', reason: 'not the search field, not a chip');
          expect(through, everyElement('list'), reason: 'the row kept alive: the focus never left it, even a moment');
          FocusManager.instance.removeListener(follow);
          await press(tester, LogicalKeyboardKey.space);
          expect(tester.widget<TextField>(searchField()).controller!.text, isEmpty);
          expect(find.byType(BottomSheet), findsNothing);
          if (look == Look.deskWide) {
            expect(selectedIndex(tester), isNot(selection), reason: 'the cursor came to what shows');
          }
          expect(focusedIndex(), firstInFullView(tester), reason: 'Space lands on the first row in full view');
          await press(tester, LogicalKeyboardKey.arrowDown);
          expect(focusedIndex(), firstInFullView(tester) + 1);
          expect(region(), 'list');
        },
      );

      testWidgets('${look.name}: a refresh brings a new highlight: the focus stays on its row', (tester) async {
        final app = await pumpLook(tester, look, moreHighlights(30));
        await intoList(tester, look);
        await press(tester, LogicalKeyboardKey.arrowDown);
        await press(tester, LogicalKeyboardKey.arrowDown);
        final track = focusedTrack();
        expect(track, isNotNull);
        final node = FocusManager.instance.primaryFocus;
        app.notifier.emit(refreshed(30));
        await tester.pumpAndSettle();
        expect(region(), 'list');
        expect(focusedTrack(), track);
        expect(FocusManager.instance.primaryFocus, same(node), reason: 'the row moved, it was not built anew');
        expect(focusedIndex(), 3, reason: 'one row further down, under the new one');
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedIndex(), 4);
      });

      testWidgets(
        '${look.name}: the focused row removed by a refresh: the list keeps the focus, nothing else gets it',
        (tester) async {
          final app = await pumpLook(tester, look, moreHighlights(30));
          await intoList(tester, look);
          await press(tester, LogicalKeyboardKey.arrowDown);
          final track = focusedTrack()!;
          expect(track, startsWith('Song '));
          app.notifier.emit(refreshed(30, brandNew: false, without: {track}));
          await tester.pumpAndSettle();
          expect(region(), 'list');
          await press(tester, LogicalKeyboardKey.space);
          expect(tester.widget<TextField>(searchField()).controller!.text, isEmpty);
          expect(find.byType(BottomSheet), findsNothing);
          expect(focusedIndex(), isNotNull, reason: 'Space lands on a row in view');
          await press(tester, LogicalKeyboardKey.tab);
          expect(region(), isNot('list'), reason: 'Tab leaves the list');
          expect(region(), isNot('chips'));
        },
      );

      testWidgets('${look.name}: the window crosses the width of the detail pane: the focus stays on the row', (
        tester,
      ) async {
        await pumpLook(tester, look, moreHighlights(30));
        await intoList(tester, look);
        await press(tester, LogicalKeyboardKey.arrowDown);
        final track = focusedTrack();
        tester.view.physicalSize = look == Look.deskWide ? narrow : desk;
        await tester.pumpAndSettle();
        expect(region(), 'list');
        expect(focusedTrack(), track);
        tester.view.physicalSize = look == Look.deskWide ? desk : narrow;
        await tester.pumpAndSettle();
        expect(region(), 'list');
        expect(focusedTrack(), track);
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedIndex(), 2);
      });
    }
  });

  testWidgets('the Ong Log: a refresh brings new plays: the focused play keeps its row and its focus', (tester) async {
    final app = await pumpApp(tester, size: narrow, desktop: true, state: moreStreams(4));
    await goToTab(tester, 'Ong Log');
    await enterList(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    final play = focused()!.findAncestorWidgetOfExactType<PlayRow>()!.play.title;
    final node = FocusManager.instance.primaryFocus;
    app.notifier.emit(moreStreams(5));
    await tester.pumpAndSettle();
    expect(focused()!.findAncestorWidgetOfExactType<PlayRow>()!.play.title, play);
    expect(FocusManager.instance.primaryFocus, same(node));
    expect(focusedIndex(), 9, reason: 'under the new stream: its header and six plays');
  });

  group('review: the pinned header', () {
    /// In the Ong Log of a narrow desktop window, the focus on a play 100 px below the top of the list, its header
    /// above the top: returns the index of the play.
    Future<int> deepPlay(WidgetTester tester) async {
      await pumpApp(tester, size: narrow, desktop: true, state: moreStreams(12));
      await goToTab(tester, 'Ong Log');
      await enterList(tester);
      for (var i = 0; i < 20; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      final position = listPosition(tester, OngLogPage);
      position.jumpTo(position.pixels + focusRect().top - listRect(tester, OngLogPage).top - 100);
      await tester.pumpAndSettle();
      return focusedIndex()!;
    }

    testWidgets('a sheet opened from the pinned header closes without scrolling the list', (tester) async {
      await deepPlay(tester);
      final position = listPosition(tester, OngLogPage);
      final pixels = position.pixels;
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusUnder<StreamHeader>(), isTrue);
      await press(tester, LogicalKeyboardKey.enter);
      expect(find.byType(StreamSheet), findsOneWidget);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(position.pixels, pixels);
      await press(tester, LogicalKeyboardKey.contextMenu);
      Navigator.of(tester.element(find.byType(BottomSheet))).pop();
      await tester.pumpAndSettle();
      expect(position.pixels, pixels);
    });

    testWidgets('→ from the pinned header returns to the play it came from; ↓ to the play under it', (tester) async {
      final play = await deepPlay(tester);
      final position = listPosition(tester, OngLogPage);
      final pixels = position.pixels;
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedIndex(), play);
      expect(position.pixels, pixels);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(position.pixels, pixels, reason: 'the play under the pinned header, not the first of the stream');
      expect(focusRect().top, greaterThanOrEqualTo(listRect(tester, OngLogPage).top));
    });
  });

  group('review: a focused row off screen', () {
    for (final key in [
      LogicalKeyboardKey.enter,
      LogicalKeyboardKey.space,
      LogicalKeyboardKey.contextMenu,
      LogicalKeyboardKey.arrowRight,
    ]) {
      testWidgets('${key.keyLabel}: lands on the first row in full view, without opening it', (tester) async {
        final app = await pumpApp(tester, size: narrow, desktop: true, state: moreHighlights(30));
        await enterList(tester);
        await press(tester, LogicalKeyboardKey.arrowDown);
        listPosition(tester).jumpTo(1500);
        await tester.pumpAndSettle();
        await press(tester, key);
        expect(find.byType(BottomSheet), findsNothing);
        expect(app.effects.opened, isEmpty);
        expect(focusedIndex(), firstInFullView(tester));
        expect(focusUnder<IconButton>(), isFalse);
      });
    }
  });

  group('review: Enter and the pane', () {
    testWidgets('expanded, nothing focused: Enter starts the video of the pane, its row filtered out', (tester) async {
      final app = await pumpApp(tester, size: desk, desktop: true);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(selectedIndex(tester), 1, reason: '"I Will Survive", with a video');
      await focusSearch(tester);
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus!.unfocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.enter);
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
    });
  });

  group('review: no row in view can take the cursor', () {
    testWidgets('Tab and ↓ reach what is in view (a header, a play without fiche); nothing moves later', (
      tester,
    ) async {
      await pumpApp(tester, size: narrow, desktop: true, state: blankPlays(30));
      await goToTab(tester, 'Ong Log');
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'list', reason: 'Tab does not skip the list');
      final list = listRect(tester, OngLogPage);
      expect(focusRect().top, greaterThanOrEqualTo(list.top - 0.01));
      expect(focusRect().bottom, lessThanOrEqualTo(list.bottom + 0.01));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(region(), 'list', reason: '↓ is not swallowed');
      final focus = FocusManager.instance.primaryFocus;
      // later frames (a scroll by the wheel) do not move the focus
      final position = listPosition(tester, OngLogPage);
      position.jumpTo(position.maxScrollExtent / 2);
      await tester.pumpAndSettle();
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus, same(focus));
    });

    testWidgets('no play with a fiche at all: Tab still reaches the list, on a header', (tester) async {
      await pumpApp(tester, size: narrow, desktop: true, state: blankPlays(8, only: true));
      await goToTab(tester, 'Ong Log');
      await focusSearch(tester);
      final stops = await tabStops(tester);
      expect(stops.where((s) => s == 'list'), hasLength(1));
    });
  });

  group('review: guards', () {
    testWidgets('the search field composing a word (IME) keeps its keys', (tester) async {
      await pumpApp(tester, size: desk, desktop: true, state: moreHighlights(30));
      await focusSearch(tester);
      final first = selectedIndex(tester);
      tester.widget<TextField>(searchField()).controller!.value = const TextEditingValue(
        text: 'zel',
        selection: TextSelection.collapsed(offset: 3),
        composing: TextRange(start: 0, end: 3),
      );
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.pageDown);
      expect(selectedIndex(tester), first);
    });
  });

  group('review: more keys', () {
    testWidgets('Page Down held faster than the frames: each page counts, the focus ends on the last', (tester) async {
      await pumpApp(tester, state: moreHighlights(60));
      await enterList(tester);
      final position = listPosition(tester);
      // three repeats with no frame between them: the rows of the pages are not built yet
      await tester.sendKeyEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
      await tester.sendKeyRepeatEvent(LogicalKeyboardKey.pageDown);
      await tester.pumpAndSettle();
      expect(position.pixels, moreOrLessEquals(3 * position.viewportDimension));
      expect(region(), 'list');
      expect(focusedIndex(), firstInFullView(tester));
    });

    testWidgets('Ctrl+Home and Ctrl+End from a chip are the list\'s', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      expect(region(), 'chips');
      await press(tester, LogicalKeyboardKey.end, control: true);
      expect(listPosition(tester).pixels, listPosition(tester).maxScrollExtent);
      expect(region(), 'chips');
      await press(tester, LogicalKeyboardKey.home, control: true);
      expect(listPosition(tester).pixels, 0);
    }, variant: windows);

    testWidgets('↑ and ↓ on the rail are its own: the selection stays', (tester) async {
      await pumpApp(tester, size: desk, state: moreHighlights(30));
      final first = selectedIndex(tester);
      Focus.of(
        tester.element(find.descendant(of: find.byType(AppNavigationRail), matching: find.text('Highlights'))),
      ).requestFocus();
      await tester.pumpAndSettle();
      expect(region(), 'nav');
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(selectedIndex(tester), first);
    });

    testWidgets('the context-menu key on a header opens its setlist', (tester) async {
      await pumpApp(tester, size: narrow, desktop: true, state: moreStreams(4));
      await goToTab(tester, 'Ong Log');
      await enterList(tester);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusUnder<StreamHeader>(), isTrue);
      await press(tester, LogicalKeyboardKey.contextMenu);
      expect(find.byType(StreamSheet), findsOneWidget);
    });

    testWidgets('numpad Enter on the focused selected row starts its video', (tester) async {
      final app = await pumpApp(tester, size: desk, desktop: true);
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.numpadEnter);
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
    });

    testWidgets('Enter on a tag selects it, as a click', (tester) async {
      await pumpApp(tester, state: moreHighlights(30));
      await focusSearch(tester);
      await press(tester, LogicalKeyboardKey.tab);
      await press(tester, LogicalKeyboardKey.arrowRight);
      final label = focused()!.findAncestorWidgetOfExactType<ListChip>()!.label;
      await press(tester, LogicalKeyboardKey.enter);
      expect(
        tester.widget<ListChip>(find.byWidgetPredicate((w) => w is ListChip && w.label == label)).selected,
        isTrue,
      );
      expect(region(), 'chips');
    });
  });
}
