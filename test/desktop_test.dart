// The Windows app and desktop browsers. In a file of their own: the themes of
// the app are built once, for the platform of the first test of a file.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'ui_harness.dart';

void main() {
  testWidgets('desktop: controls keep the sizes of the design', (tester) async {
    await pumpApp(tester);
    // the chips and their row as on a phone
    expect(tester.getSize(chip('All')).height, 48);
    await tester.tap(find.byTooltip('Details').at(1));
    await tester.pumpAndSettle();
    // the "Watch" button as high as the round buttons beside it
    expect(tester.getSize(find.widgetWithText(FilledButton, 'Watch on YouTube')).height, 40);
    expect(tester.getSize(find.widgetWithIcon(IconButton, Icons.share)).height, 40);
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
