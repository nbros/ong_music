// What the user sees when Google's answer replaces the daily copy of the sheets shown on a first load: the states
// CatalogueNotifier goes through (test/sheet_snapshot_test.dart), on the screen. The hand-over is that of any
// refresh of kept data.
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

void main() {
  // the copy, made 20 hours before the visit; Google's answer has one highlight more
  final madeAt = testNow.subtract(const Duration(hours: 20));
  final older = [for (var i = 0; i < 30; i++) hRow(order: '${10 + i}', title: 'Tune $i', upload: '2024-02-01')];
  final snapshot = testCatalogue(moreHighlights: older);
  final google = testCatalogue(
    moreHighlights: [
      ...older,
      hRow(order: '99', title: 'Brand new', upload: '2024-04-01'),
    ],
  );

  // the list of the visible tab (not the row of chips, which scrolls sideways)
  ScrollPosition listScroll(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down).hitTestable().first,
      )
      .position;

  /// The titles of the highlight rows on the screen, top to bottom, with their top edge.
  List<(String, double)> rowsShown(WidgetTester tester) {
    final rows = [
      for (final e in find.byType(HighlightRow).hitTestable().evaluate())
        ((e.widget as HighlightRow).highlight.title, tester.getRect(find.byWidget(e.widget)).top),
    ]..sort((a, b) => a.$2.compareTo(b.$2));
    return rows;
  }

  testWidgets('Google replaces the snapshot: the list stays, scrolled where it was, the search kept', (tester) async {
    final app = await pumpApp(
      tester,
      state: CatalogueState(catalogue: snapshot, fetchedAt: madeAt, isRefreshing: true),
      // the bar of a refresh never settles
      settle: false,
    );
    await tester.pump(const Duration(seconds: 1));
    // the list at once, with the thin bar of a refresh, not the first-download screen
    expect(find.byType(HighlightRow), findsWidgets);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('Downloading the highlights and the Ong Log…'), findsNothing);
    listScroll(tester).jumpTo(300);
    await tester.pump(const Duration(seconds: 1));
    final before = rowsShown(tester);
    app.notifier.emit(CatalogueState(catalogue: google, fetchedAt: testNow));
    await tester.pump();
    expect(find.byType(HighlightRow), findsWidgets, reason: 'no frame without the list');
    await tester.pumpAndSettle();
    // the rows stay where they were on the screen, the new one above them, out of sight
    expect(before, hasLength(greaterThan(4)));
    expect(rowsShown(tester), containsAllInOrder(before));
    expect(listScroll(tester).pixels, greaterThan(300));
    expect(find.byType(LinearProgressIndicator), findsNothing);

    await tester.enterText(searchField(), 'tune 1');
    await tester.pumpAndSettle();
    app.notifier.emit(CatalogueState(catalogue: snapshot, fetchedAt: madeAt, isRefreshing: true));
    await tester.pump(const Duration(seconds: 1));
    app.notifier.emit(CatalogueState(catalogue: google, fetchedAt: testNow));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(searchField()).controller!.text, 'tune 1');
    final titles = [for (final (title, _) in rowsShown(tester)) title];
    expect(titles, isNotEmpty);
    expect(titles.every((t) => t.contains('1')), isTrue, reason: 'still filtered: $titles');
  });

  group('expanded window, the fiche the app opened by itself', () {
    const desk = Size(1440, 900);
    String paneTitle(WidgetTester tester) =>
        tester.widget<HighlightSheet>(find.byType(HighlightSheet).first).highlight.title;

    testWidgets('over the snapshot it follows the newest highlight when Google brings newer ones', (tester) async {
      final app = await pumpApp(
        tester,
        size: desk,
        desktop: true,
        state: CatalogueState(catalogue: snapshot, fetchedAt: madeAt, isRefreshing: true, isSnapshot: true),
        settle: false,
      );
      await tester.pump(const Duration(seconds: 1));
      expect(paneTitle(tester), 'Tune 29');
      app.notifier.emit(CatalogueState(catalogue: google, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(paneTitle(tester), 'Brand new');
    });

    testWidgets('a row the user chose over the snapshot stays', (tester) async {
      final app = await pumpApp(
        tester,
        size: desk,
        desktop: true,
        state: CatalogueState(catalogue: snapshot, fetchedAt: madeAt, isRefreshing: true, isSnapshot: true),
        settle: false,
      );
      await tester.pump(const Duration(seconds: 1));
      await tester.tap(find.text('Tune 27'));
      await tester.pump(const Duration(seconds: 1));
      expect(paneTitle(tester), 'Tune 27');
      app.notifier.emit(CatalogueState(catalogue: google, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(paneTitle(tester), 'Tune 27');
    });

    testWidgets('over kept data (no snapshot) a refresh leaves it where it was', (tester) async {
      final app = await pumpApp(
        tester,
        size: desk,
        desktop: true,
        state: CatalogueState(catalogue: snapshot, fetchedAt: madeAt),
      );
      expect(paneTitle(tester), 'Tune 29');
      app.notifier.emit(CatalogueState(catalogue: google, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(paneTitle(tester), 'Tune 29');
    });

    testWidgets('the snapshot still there after a failed download, then a later answer: it follows', (tester) async {
      final app = await pumpApp(
        tester,
        size: desk,
        desktop: true,
        state: CatalogueState(catalogue: snapshot, fetchedAt: madeAt, isRefreshing: true, isSnapshot: true),
        settle: false,
      );
      await tester.pump(const Duration(seconds: 1));
      app.notifier.emit(
        CatalogueState(
          catalogue: snapshot,
          fetchedAt: madeAt,
          lastError: SheetHttpException(SheetUrls.songs, 503),
          isSnapshot: true,
        ),
      );
      await tester.pumpAndSettle();
      expect(paneTitle(tester), 'Tune 29');
      app.notifier.emit(CatalogueState(catalogue: google, fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(paneTitle(tester), 'Brand new');
    });
  });

  testWidgets('Google fails after the snapshot: no message on the list, the About tab says it as for kept data', (
    tester,
  ) async {
    final app = await pumpApp(
      tester,
      state: CatalogueState(catalogue: snapshot, fetchedAt: madeAt, isRefreshing: true),
      // the bar of a refresh never settles
      settle: false,
    );
    await tester.pump(const Duration(seconds: 1));
    app.notifier.emit(
      CatalogueState(catalogue: snapshot, fetchedAt: madeAt, lastError: SheetHttpException(SheetUrls.songs, 503)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(HighlightRow), findsWidgets);
    expect(find.byType(SnackBar), findsNothing);
    expect(find.text('Couldn’t download the songs'), findsNothing);
    await goToTab(tester, 'About');
    await tester.scrollUntilVisible(find.text('Clear downloaded data'), 200, scrollable: aboutScrollable());
    expect(find.text('Updated 20 hours ago'), findsOneWidget, reason: 'the age of the copy, not "just now"');
    expect(find.textContaining('The last refresh failed.'), findsOneWidget);
  });
}
