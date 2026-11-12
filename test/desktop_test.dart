// The Windows app and desktop browsers. In a file of their own: the themes of
// the app are built once, for the platform of the first test of a file.
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('desktop: controls keep the sizes of the design', (tester) async {
    await pumpApp(tester);
    // the chips and their row as on a phone
    expect(tester.getSize(chip('All')).height, 32);
    expect(tester.getSize(find.byType(ChipRow).hitTestable()).height, 48);
    await tester.tap(find.byTooltip('Details').at(1));
    await tester.pumpAndSettle();
    // the "Watch" button as high as the round buttons beside it
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Watch on YouTube')).height, 40);
    expect(tester.getSize(find.widgetWithIcon(IconButton, Icons.share)).height, 40);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('desktop: a mouse wheel beside the content scrolls what is at that height', (tester) async {
    // a wide and low window: 380 px of empty space on each side of the content, and lists longer than the window
    await pumpApp(tester, size: const Size(1400, 320));
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
    await tester.tap(find.byTooltip('Details').hitTestable().first);
    await tester.pumpAndSettle();
    expect(find.byType(HighlightSheet), findsOneWidget);
    await wheel(beside);
    expect(underSheet.pixels, 120);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));

  testWidgets('desktop: the scrollbars shown at all times have a scroll view to follow', (tester) async {
    // without a controller of their own they used the primary one, which desktop does not attach by
    // itself: an assertion failed
    await pumpApp(tester);
    expect(tester.takeException(), isNull);
    await goToTab(tester, 'About');
    await tester.drag(find.text('Jonathan Ong'), const Offset(0, -300));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await goToTab(tester, 'Highlights');
    await tester.tap(find.byTooltip('Details').at(1));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final thumbs = find.byWidgetPredicate((w) => w is RawScrollbar && w.thumbVisibility == true);
    expect(thumbs, findsWidgets);
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
