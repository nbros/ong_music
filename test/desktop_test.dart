// The Windows app and desktop browsers. In a file of their own: the themes of
// the app are built once, for the platform of the first test of a file.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

void main() {
  testWidgets('desktop: controls keep the sizes of the design', (tester) async {
    await pumpApp(tester, pointer: PointerKind.mouse);
    // the chips and their row as on a phone
    expect(tester.getSize(chip('All')).height, 32);
    expect(tester.getSize(find.byType(ChipRow).hitTestable()).height, 48);
    await tester.tap(detailsButtons().at(1));
    await tester.pumpAndSettle();
    // the "Watch" button as high as the round buttons beside it
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Watch on YouTube')).height, 40);
    expect(tester.getSize(find.widgetWithIcon(IconButton, Icons.share)).height, 40);
    // the star as big as its round neighbours, and still in line with Copy
    final star = tester.getRect(find.widgetWithIcon(IconButton, Icons.star_border));
    expect(star.size, const Size(40, 40));
    expect(star.right, tester.getRect(find.widgetWithIcon(IconButton, Icons.copy)).right);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('desktop browser: the full screen button at the right of the content column', (tester) async {
    // (a medium window: an expanded one has no ⋮ buttons)
    await pumpApp(tester, fullscreen: FakeFullscreen(), size: const Size(830, 900), pointer: PointerKind.mouse);
    // the column of 720 px in the middle of what the rail leaves; with a mouse, the button over the ⋮ buttons,
    // which the lane of the scroll bar keeps 12 px from the right edge of the column
    const left = railWidth + (830 - railWidth - 720) / 2, right = left + 720;
    for (final tab in ['Highlights', 'Ong Log']) {
      await goToTab(tester, tab);
      expectLayout(tester, left: left, right: right - scrollbarLane, column: 40, reason: tab);
    }
    await goToTab(tester, 'Highlights');
    final details = tester.getRect(find.widgetWithIcon(IconButton, Icons.more_vert).first);
    final button = tester.getRect(fullscreenButton());
    expect((details.left, details.right), (button.left, button.right));
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('desktop: a mouse wheel beside the content scrolls what is at that height', (tester) async {
    // a wide and low window: 300 px of empty space on each side of the content, and lists longer than the window
    // (two more highlights than the test catalogue: the rail of a low window gives the list the height of the bar)
    await pumpApp(
      tester,
      size: const Size(1400, 320),
      pointer: PointerKind.mouse,
      state: CatalogueState(
        catalogue: testCatalogue(
          moreHighlights: [
            hRow(order: '4', title: 'Chopin - Nocturne'),
            hRow(order: '5', title: 'Chopin - Ballade'),
          ],
        ),
        fetchedAt: testNow,
      ),
    );
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    Future<void> wheel(Offset at) async {
      await tester.sendEventToBinding(pointer.hover(at));
      await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
      await tester.pumpAndSettle();
    }

    ScrollPosition position(Finder scrollView) => tester
        .state<ScrollableState>(find.descendant(of: scrollView, matching: find.byType(Scrollable)).first)
        .position;

    final list = find.byType(CustomScrollView).hitTestable();
    expect(position(list).maxScrollExtent, greaterThan(40));
    final beside = Offset(100, tester.getCenter(list).dy);
    await wheel(beside);
    expect(position(list).pixels, 40);
    await wheel(Offset(1300, beside.dy));
    expect(position(list).pixels, 80);
    // over the content: once, not twice
    await wheel(tester.getCenter(list));
    expect(position(list).pixels, 120);

    await goToTab(tester, 'About');
    await wheel(beside);
    expect(position(find.byType(ListView).hitTestable()).pixels, 40);

    // not through a sheet
    await goToTab(tester, 'Highlights');
    final underSheet = position(list);
    expect(underSheet.pixels, 120);
    await tester.tap(detailsButtons().hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(HighlightSheet), findsOneWidget);
    await wheel(beside);
    expect(underSheet.pixels, 120);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('desktop: the scrollbars shown at all times have a scroll view to follow', (tester) async {
    // without a controller of their own they used the primary one, which desktop does not attach by
    // itself: an assertion failed
    await pumpApp(tester, pointer: PointerKind.mouse);
    expect(tester.takeException(), isNull);
    await goToTab(tester, 'About');
    await tester.drag(find.text('Jonathan Ong'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await goToTab(tester, 'Highlights');
    await tester.tap(detailsButtons().at(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final thumbs = find.byWidgetPredicate((w) => w is RawScrollbar && w.thumbVisibility == true);
    expect(thumbs, findsWidgets);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
