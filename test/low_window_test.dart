// Windows much lower than a phone held upright: a phone held sideways, with or without its keyboard, a window
// turned under an open sheet, large text in a small window.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'ui_harness.dart';

/// A phone held sideways, and what its status bar and keyboard take.
const _sideways = Size(800, 360);
const _statusBar = 24.0;
const _keyboard = 200.0;

void _showKeyboard(WidgetTester tester, {bool shown = true}) {
  tester.view.padding = const FakeViewPadding(top: _statusBar);
  tester.view.viewPadding = const FakeViewPadding(top: _statusBar);
  tester.view.viewInsets = FakeViewPadding(bottom: shown ? _keyboard : 0);
}

void main() {
  for (final (tab, page, row) in [('Highlights', HighlightsPage, HighlightRow), ('Ong Log', OngLogPage, PlayRow)]) {
    testWidgets('$tab, phone held sideways: while typing, the search field and the list alone', (tester) async {
      await pumpApp(tester, size: _sideways);
      await goToTab(tester, tab);
      final list = find.descendant(of: find.byType(page), matching: find.byType(CustomScrollView));
      final chips = find.descendant(of: find.byType(page), matching: find.byType(ChipRow));
      // the row of chips is kept as it is, scrolled or not, while it is out of the way
      final scroll = tester.state<ScrollableState>(find.descendant(of: chips, matching: find.byType(Scrollable)));
      expect(chips.hitTestable(), findsOneWidget);

      await tester.tap(searchField());
      _showKeyboard(tester);
      await tester.enterText(searchField(), 'survive');
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(chips.hitTestable(), findsNothing);
      expect(find.byType(CountLine), findsNothing);
      // above the keyboard: the search field, then most of a row
      final visible = tester.getRect(list);
      expect(visible.bottom, _sideways.height - _keyboard);
      expect(visible.height, greaterThan(50));
      // the first row, under the header of its stream in the Ong Log: its title at least
      expect(tester.getRect(find.byType(row).first).top, lessThanOrEqualTo(visible.bottom - 28));
      expect(find.descendant(of: find.byType(row).first, matching: richText('I Will Survive')), findsOneWidget);

      // the keyboard goes: everything back, where it was
      _showKeyboard(tester, shown: false);
      await tester.pumpAndSettle();
      expect(chips.hitTestable(), findsOneWidget);
      expect(find.descendant(of: find.byType(page), matching: find.byType(CountLine)).hitTestable(), findsOneWidget);
      expect(
        tester.state<ScrollableState>(find.descendant(of: chips, matching: find.byType(Scrollable))),
        same(scroll),
      );
    });
  }

  testWidgets('a phone held upright keeps its chips and its count line while typing', (tester) async {
    await pumpApp(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.enterText(searchField(), 'survive');
    await tester.pumpAndSettle();
    expect(find.byType(ChipRow).hitTestable(), findsOneWidget);
    expect(find.text('1 highlight'), findsOneWidget);
  });

  group('highlight sheet', () {
    Finder thumbnail() => find.descendant(of: find.byType(HighlightSheet), matching: find.byType(Thumbnail));

    testWidgets('phone held sideways: the title and the buttons show under a lower thumbnail', (tester) async {
      await pumpApp(tester, size: _sideways);
      // the second highlight: the first has no video
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final picture = tester.getRect(thumbnail());
      expect(picture.height, closeTo(_sideways.height * 0.4, 0.5));
      expect(picture.width / picture.height, closeTo(16 / 9, 0.01));
      // in the middle of the sheet, which is in the middle of what the navigation rail leaves
      expect(picture.center.dx, railWidth + (_sideways.width - railWidth) / 2);
      expect(find.text('Watch on YouTube').hitTestable(), findsOneWidget);
      expect(find.byTooltip('Share').hitTestable(), findsOneWidget);
    });

    testWidgets('phone held upright: the thumbnail as wide as the sheet, as before', (tester) async {
      await pumpApp(tester);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final picture = tester.getRect(thumbnail());
      expect((picture.left, picture.right), (20, 412 - 20));
      expect(picture.height, closeTo(372 * 9 / 16, 0.01));
    });

    testWidgets('a window turned under an open sheet: the sheet follows, a strip stays to close it', (tester) async {
      await pumpApp(tester);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      Rect sheet() => tester.getRect(find.byType(BottomSheet));
      expect(sheet().bottom, 892);
      expect(sheet().height, lessThanOrEqualTo(892 * 0.9));

      tester.view.physicalSize = const Size(892, 412);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(sheet().bottom, 412);
      expect(sheet().height, closeTo(412 * 0.9, 0.01), reason: 'nine tenths of the window, handle included');

      tester.view.physicalSize = const Size(412, 892);
      await tester.pumpAndSettle();
      expect(sheet().height, greaterThan(412), reason: 'not kept as low as the window was');
      expect(sheet().height, lessThanOrEqualTo(892 * 0.9));
    });
  });

  group('after a sheet', () {
    /// Whether the search field has the focus (and so its keyboard, on a phone) after a sheet opened and closed.
    /// The sheet is opened without a tap: on a computer, a tap gives the focus to the button tapped.
    Future<bool> focusAfterSheet(WidgetTester tester) async {
      final app = await pumpApp(tester);
      await tester.tap(searchField());
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      expect(tester.testTextInput.isVisible, isTrue);
      final catalogue = app.notifier.state.catalogue!;
      unawaited(showHighlightSheet(tester.element(find.byType(HighlightsPage)), catalogue, catalogue.highlights.first));
      await tester.pumpAndSettle();
      expect(find.byType(HighlightSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(HighlightSheet), findsNothing);
      expect(find.text('zelda'), findsOneWidget, reason: 'the search stays');
      return tester
          .state<EditableTextState>(find.descendant(of: searchField(), matching: find.byType(EditableText)))
          .widget
          .focusNode
          .hasFocus;
    }

    testWidgets('on a phone, the keyboard does not come back over the list', (tester) async {
      expect(await focusAfterSheet(tester), isFalse);
      expect(tester.testTextInput.isVisible, isFalse);
    });

    testWidgets('on a computer, the focus goes back to where it was, for the keyboard', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      try {
        expect(await focusAfterSheet(tester), isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  for (final (size, scale) in [(const Size(320, 568), 2.0), (const Size(360, 300), 1.3), (const Size(360, 300), 2.0)]) {
    testWidgets('the "Clear downloaded data?" dialog keeps its buttons in reach at $size, text scale $scale', (
      tester,
    ) async {
      final app = await pumpApp(tester, size: size, textScale: scale);
      await goToTab(tester, 'About');
      await tester.scrollUntilVisible(find.text('Clear downloaded data'), 100, scrollable: aboutScrollable());
      await tapVisible(tester, find.text('Clear'));
      expect(tester.takeException(), isNull);
      final clear = find.descendant(of: find.byType(AlertDialog), matching: find.text('Clear'));
      await tester.ensureVisible(clear);
      await tester.pumpAndSettle();
      expect(clear.hitTestable(), findsOneWidget);
      await tester.tap(clear);
      await tester.pumpAndSettle();
      expect(app.notifier.clears, 1);
    });
  }
}
