// The keyboard of the lists: two highlights of one video, and a key held after it brought the cursor back.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';

import 'fixtures.dart';
import 'keyboard_test.dart' as kt;
import 'ui_harness.dart';

/// Two highlights sharing one YouTube video (as two neighbours of the real sheet do), among others.
CatalogueState twins({bool brandNew = false}) => CatalogueState(
  catalogue: testCatalogue(
    moreHighlights: [
      for (var i = 1; i <= 3; i++) hRow(order: '${3 + i}', title: 'Song $i'),
      hRow(order: '20', title: 'Shiki - Day and Night', genre: 'ANIME', link: 'https://youtu.be/h4w8Ax3Welk'),
      hRow(order: '21', title: 'Demon Slayer - Demon Squad', genre: 'ANIME', link: 'https://youtu.be/h4w8Ax3Welk'),
      for (var i = 4; i <= 6; i++) hRow(order: '${30 + i}', title: 'Song $i'),
      if (brandNew) hRow(order: '99', title: 'Brand new'),
    ],
  ),
  fetchedAt: testNow,
);

Map<String, Element> rowElements() => {
  for (final e in find.byType(HighlightRow, skipOffstage: false).evaluate())
    (e.widget as HighlightRow).highlight.track: e,
};

/// The rings painted around the tags (the keyboard focus on a computer).
int tagRings(WidgetTester tester) => tester
    .widgetList<CustomPaint>(find.byType(CustomPaint))
    .where((p) => p.foregroundPainter.runtimeType.toString() == '_ChipRingPainter')
    .length;

void main() {
  group('the ring of the keyboard focus on a tag', () {
    testWidgets('on a computer: on the tag the keyboard focused, gone once the mouse is used', (tester) async {
      await kt.pumpLook(tester, kt.Look.deskWide, kt.moreHighlights(30));
      expect(tagRings(tester), 0);
      await kt.focusSearch(tester);
      await kt.press(tester, LogicalKeyboardKey.tab);
      expect(kt.region(), 'chips');
      await tester.pump();
      expect(tagRings(tester), 1);
      await kt.press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump();
      expect(tagRings(tester), 1, reason: 'it follows the focus');
      // a click on a tag gives it the focus, without a ring
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(find.byType(FilterChip).at(2)));
      await mouse.down(tester.getCenter(find.byType(FilterChip).at(2)));
      await mouse.up();
      await tester.pumpAndSettle();
      expect(tagRings(tester), 0);
      await mouse.removePointer();
    });

    testWidgets('none on a phone', (tester) async {
      await kt.pumpLook(tester, kt.Look.phone, kt.moreHighlights(30));
      await kt.focusSearch(tester);
      await kt.press(tester, LogicalKeyboardKey.tab);
      await tester.pump();
      expect(kt.region(), 'chips');
      expect(tagRings(tester), 0);
    });
  });

  for (final look in kt.Look.values) {
    testWidgets('${look.name}: two highlights of one video are two rows: a refresh keeps each, the focus on its own', (
      tester,
    ) async {
      final app = await kt.pumpLook(tester, look, twins());
      await kt.intoList(tester, look);
      for (var i = 0; i < 12 && kt.focusedTrack() != 'Day and Night'; i++) {
        await kt.press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(kt.focusedTrack(), 'Day and Night');
      final before = rowElements();
      app.notifier.emit(twins(brandNew: true));
      await tester.pumpAndSettle();
      final after = rowElements();
      expect(kt.focusedTrack(), 'Day and Night');
      for (final track in ['Day and Night', 'Demon Squad']) {
        expect(identical(before[track], after[track]), isTrue, reason: '$track keeps its row');
      }
      if (look == kt.Look.deskWide) {
        expect(tester.widget<HighlightSheet>(find.byType(HighlightSheet).first).highlight.track, 'Day and Night');
      }
      // away and back: on the same one of the two
      await kt.press(tester, LogicalKeyboardKey.tab, shift: true);
      await kt.press(tester, LogicalKeyboardKey.tab);
      expect(kt.focusedTrack(), 'Day and Night');
    });

    for (final key in [LogicalKeyboardKey.space, LogicalKeyboardKey.enter]) {
      testWidgets('${look.name}: ${key.keyLabel} held on a focused row out of view lands and opens nothing', (
        tester,
      ) async {
        final app = await kt.pumpLook(tester, look, kt.moreHighlights(30));
        await kt.intoList(tester, look);
        await kt.press(tester, LogicalKeyboardKey.arrowDown);
        kt.listPosition(tester).jumpTo(1500);
        await tester.pumpAndSettle();
        final selected = look == kt.Look.deskWide
            ? tester.widget<HighlightSheet>(find.byType(HighlightSheet).first).highlight.track
            : null;
        await tester.sendKeyDownEvent(key);
        await tester.pump();
        final landed = kt.focusedTrack();
        expect(landed, isNotNull);
        for (var i = 0; i < 3; i++) {
          await tester.sendKeyRepeatEvent(key);
          await tester.pump(const Duration(milliseconds: 30));
        }
        await tester.sendKeyUpEvent(key);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing);
        expect(app.effects.opened, isEmpty);
        expect(kt.focusedTrack(), landed);
        if (selected != null) {
          // expanded: the selection follows the cursor to the row landed on, as for any move, and no further
          expect(tester.widget<HighlightSheet>(find.byType(HighlightSheet).first).highlight.track, landed);
        }
        // released: the key acts again
        await kt.press(tester, key);
        await tester.pumpAndSettle();
        if (look != kt.Look.deskWide) {
          expect(find.byType(BottomSheet).evaluate().isNotEmpty || app.effects.opened.isNotEmpty, isTrue);
        }
      });
    }
  }
}
