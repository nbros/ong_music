import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';

import 'ui_harness.dart';

void main() {
  final complete = testCatalogue();
  final alone = complete.highlightsOnly;
  final fetchedAt = testNow.subtract(const Duration(hours: 1));
  for (final name in ['', 'jsbach64']) {
    testWidgets('About: nothing below the name help and the counts moves when the songs arrive, name "$name"', (
      tester,
    ) async {
      final app = await pumpApp(
        tester,
        state: CatalogueState(catalogue: alone, fetchedAt: fetchedAt),
        prefs: {'twitchName': name},
      );
      await goToTab(tester, 'About');
      ScrollPosition pos() => tester.state<ScrollableState>(aboutScrollable()).position;
      final below = find.text('Clear downloaded data');
      await tester.scrollUntilVisible(below, 200, scrollable: aboutScrollable());
      await tester.pumpAndSettle();
      final top = tester.getRect(below).top, p0 = pos().pixels, max0 = pos().maxScrollExtent;
      final count0 = tester.getRect(find.text('3 highlights')).top;
      app.notifier.emit(CatalogueState(catalogue: complete, fetchedAt: fetchedAt, songsFetchedAt: fetchedAt));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(find.textContaining(' songs · '), findsOneWidget);
      if (name.isNotEmpty) expect(find.textContaining('Found '), findsOneWidget);
      expect(tester.getRect(below).top, top);
      expect((pos().pixels, pos().maxScrollExtent), (p0, max0));
      expect(tester.getRect(below).top, top);
      expect(tester.getRect(find.text('3 highlights')).top, count0);
    });
  }
}
