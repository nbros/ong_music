// Stability, motion, pointer and keyboard details of the UI.
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'ui_harness.dart';

/// The text field of the search field of the visible tab.
EditableTextState editable(WidgetTester tester) =>
    tester.state<EditableTextState>(find.descendant(of: searchField(), matching: find.byType(EditableText)));

void main() {
  testWidgets('the Highlights list does not move when the Ong Log link comes and goes', (tester) async {
    await pumpApp(tester);
    final list = find.descendant(of: find.byType(HighlightsPage), matching: find.byType(CustomScrollView));
    double top() => tester.getRect(list).top;

    // "storms": a link to the Ong Log; "moana": none (never played); "zzz": nothing at all
    final tops = <String, double>{};
    for (final query in ['storms', 'moana', 'zzz', 'storms']) {
      await tester.enterText(searchField(), query);
      await tester.pumpAndSettle();
      tops[query] = top();
    }
    expect(find.text('1 in the Ong Log →'), findsOneWidget);
    expect(tops.values.toSet(), hasLength(1), reason: '$tops');

    // a genre alone shows the count without a link, at the same place
    await tester.enterText(searchField(), '');
    await tapVisible(tester, chip('Disney'));
    expect(find.text('1 highlight'), findsOneWidget);
    expect(top(), tops['storms']);
  });

  group('Search field', () {
    testWidgets('Escape clears it, then leaves it', (tester) async {
      await pumpApp(tester);
      await tester.enterText(searchField(), 'storms');
      await tester.pumpAndSettle();
      expect(find.text('1 highlight'), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(editable(tester).textEditingValue.text, '');
      expect(find.text('1 highlight'), findsNothing);
      expect(editable(tester).widget.focusNode.hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(editable(tester).widget.focusNode.hasFocus, isFalse);
    });

    testWidgets('Ctrl+F or / reaches the search field of the tab on screen', (tester) async {
      await pumpApp(tester);
      expect(editable(tester).widget.focusNode.hasFocus, isFalse);
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      expect(editable(tester).widget.focusNode.hasFocus, isTrue);

      await goToTab(tester, 'Ong Log');
      expect(editable(tester).widget.focusNode.hasFocus, isFalse);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pump();
      expect(editable(tester).widget.focusNode.hasFocus, isTrue);
      expect(
        find.descendant(of: find.byType(OngLogPage), matching: find.byWidget(editable(tester).widget)),
        findsOneWidget,
      );

      // not under a sheet
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.tap(find.text('Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.slash);
      await tester.pump();
      expect(find.byType(StreamSheet), findsOneWidget);
      final field = find.descendant(of: find.byType(OngLogPage), matching: find.byType(EditableText));
      expect(tester.widget<EditableText>(field).focusNode.hasFocus, isFalse);
    });
  });

  testWidgets('a mouse wheel scrolls the chips sideways', (tester) async {
    await pumpApp(tester, size: const Size(320, 700));
    await goToTab(tester, 'Ong Log');
    final row = find.descendant(of: find.byType(OngLogPage), matching: find.byType(ChipRow));
    final position = tester
        .state<ScrollableState>(find.descendant(of: row, matching: find.byType(Scrollable)))
        .position;
    expect(position.maxScrollExtent, greaterThan(0));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(tester.getCenter(row)));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 60)));
    await tester.pumpAndSettle();
    expect(position.pixels, 60);
    // the list under the row did not move
    final list = find.descendant(of: find.byType(OngLogPage), matching: find.byType(CustomScrollView));
    expect(
      tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position.pixels,
      0,
    );
  });

  testWidgets('the video thumbnail of a highlight sheet shows the click cursor', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Details').at(1));
    await tester.pumpAndSettle();
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(gesture.removePointer);
    await gesture.addPointer(location: tester.getCenter(find.byType(Thumbnail).last) + const Offset(60, 0));
    await tester.pump();
    expect(RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1), SystemMouseCursors.click);
  });

  group('Motion', () {
    Finder message(String text) => find.ancestor(of: find.text(text), matching: find.byType(Opacity));

    testWidgets('a message fades out instead of vanishing', (tester) async {
      final app = await pumpApp(tester);
      app.effects.shareWorks = false;
      await tester.tap(find.byTooltip('Details').at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      const text = 'Sharing isn’t available here: link copied';
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.widget<Opacity>(message(text)).opacity, 1);
      await tester.pump(const Duration(milliseconds: 2200)); // 2.5 s
      await tester.pump(const Duration(milliseconds: 20));
      final fading = tester.widget<Opacity>(message(text)).opacity;
      expect(fading, inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text(text), findsNothing);
    });

    testWidgets('with less motion, sheets and messages appear without sliding', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue = const FakeAccessibilityFeatures(
        disableAnimations: true,
      );
      addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      final app = await pumpApp(tester);
      await tester.tap(find.byTooltip('Details').at(1));
      await tester.pump();
      await tester.pump();
      final shown = tester.getRect(find.byType(HighlightSheet));
      await tester.pumpAndSettle();
      expect(shown, tester.getRect(find.byType(HighlightSheet)));

      app.effects.shareWorks = false;
      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final text = find.text('Sharing isn’t available here: link copied');
      final at = tester.getRect(text);
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getRect(text), at);
      await waitForMessage(tester);
    });
  });
}
