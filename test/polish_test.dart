// Stability, motion, pointer and keyboard details of the UI.
import 'dart:ui';

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/theme.dart';
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
    testWidgets('has the sizes of the design and leaves the keyboard\'s automatic correction off', (tester) async {
      await pumpApp(tester);
      for (final tab in ['Highlights', 'Ong Log']) {
        await goToTab(tester, tab);
        final field = find.byType(ListSearchField).hitTestable();
        Rect rect(Finder finder) => tester.getRect(find.descendant(of: field, matching: finder).first);
        final pill = rect(find.byType(Material));
        expect((pill.left, pill.height), (16, 52), reason: tab);
        expect(rect(find.byIcon(Icons.search)).left - pill.left, 16, reason: tab);
        expect(rect(find.byType(EditableText)).left - pill.left, 56, reason: tab);
        // titles, names and user names are not dictionary words
        expect(editable(tester).widget.autocorrect, isFalse, reason: tab);
        await tester.enterText(searchField(), 'storms');
        await tester.pump();
        expect(pill.right - rect(find.byType(IconButton)).right, 4, reason: tab);
        await tester.enterText(searchField(), '');
        await tester.pumpAndSettle();
      }
    });

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

  group('chips', () {
    testWidgets('have the sizes of the design, the first one in line with the search field', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      Rect rect(Finder finder) => tester.getRect(finder);
      Finder inChip(String label, Finder finder) => find.descendant(of: chip(label).hitTestable(), matching: finder);
      final all = rect(chip('All').hitTestable());
      final piano = rect(chip('Piano').hitTestable());
      final field = find.byType(ListSearchField).hitTestable();
      expect(all.left, rect(find.descendant(of: field, matching: find.byType(Material)).first).left);
      expect((all.height, piano.height), (32, 32));
      expect(piano.left - all.right, 8);
      final allLabel = rect(inChip('All', find.text('All')));
      // 12 px inside the 1 px border
      expect((allLabel.left - all.left, all.right - allLabel.right), (13, 13));
      final icon = rect(inChip('Piano', find.byType(Icon)));
      final label = rect(inChip('Piano', find.text('Piano')));
      expect((icon.left - piano.left, label.left - icon.right, piano.right - label.right), (13, 6, 13));
      expect(icon.size, const Size(16, 16));
    });

    testWidgets('a narrow chip takes no more room than it shows, and is 48 px high under the finger', (tester) async {
      final taps = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.light),
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final label in ['A', 'B']) ListChip(label: label, selected: false, onTap: () => taps.add(label)),
                ],
              ),
            ),
          ),
        ),
      );
      final a = tester.getRect(find.byType(FilterChip).first);
      final b = tester.getRect(find.byType(FilterChip).last);
      // 13 px of text and 13 px on each side: a tap target as wide as it is high would add 9 px around it
      expect(a.width, 39);
      expect(b.left, a.right);
      expect(tester.getSize(find.byType(Row).first).height, 48);
      for (final dy in [-20.0, 0.0, 20.0]) {
        await tester.tapAt(a.center.translate(0, dy));
        await tester.tapAt(b.center.translate(0, dy));
      }
      expect(taps, ['A', 'B', 'A', 'B', 'A', 'B']);
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

  testWidgets('a screen reader hears "Watch on YouTube" once in a highlight sheet', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester);
    await tester.tap(find.byTooltip('Details').at(1));
    await tester.pumpAndSettle();
    expect(find.byType(HighlightSheet), findsOneWidget);
    // the thumbnail opens the video too, but is not a second button of the same name
    expect(find.bySemanticsLabel('Watch on YouTube'), findsOneWidget);
    handle.dispose();
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
