import 'dart:math';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/grouped_list.dart';

/// Group sizes like the real Ong Log: 31,430 rows in 1,413 streams.
GroupedListLayout ongLogSized({double header = 40, double row = 56}) {
  final random = Random(7);
  final starts = <int>[0];
  var rows = 0;
  while (starts.length < 1413) {
    rows += 1 + random.nextInt(43);
    starts.add(rows);
  }
  return GroupedListLayout.scan(
    rowCount: 31430,
    startsGroup: (i) => _binarySearch(starts, i),
    headerExtent: header,
    rowExtent: row,
  );
}

bool _binarySearch(List<int> sorted, int value) {
  var lo = 0, hi = sorted.length - 1;
  while (lo <= hi) {
    final mid = (lo + hi) >> 1;
    if (sorted[mid] == value) return true;
    if (sorted[mid] < value) {
      lo = mid + 1;
    } else {
      hi = mid - 1;
    }
  }
  return false;
}

void main() {
  group('GroupedListLayout', () {
    test('matches a brute-force walk of the items', () {
      final random = Random(1);
      for (var round = 0; round < 50; round++) {
        final rowCount = 1 + random.nextInt(60);
        final starts = {0, for (var i = 0; i < random.nextInt(rowCount); i++) random.nextInt(rowCount)};
        final layout = GroupedListLayout.scan(
          rowCount: rowCount,
          startsGroup: starts.contains,
          headerExtent: 30 + random.nextDouble() * 20,
          rowExtent: 50 + random.nextDouble() * 20,
        );
        // brute force: items in order
        final kinds = <int>[]; // -1 header, else row index
        for (var r = 0; r < rowCount; r++) {
          if (starts.contains(r)) kinds.add(-1);
          kinds.add(r);
        }
        expect(layout.itemCount, kinds.length);
        var offset = 0.0;
        for (var i = 0; i < kinds.length; i++) {
          final extent = kinds[i] < 0 ? layout.headerExtent : layout.rowExtent;
          expect(layout.rowOfItem(i), kinds[i]);
          expect(layout.itemOffset(i), closeTo(offset, 1e-6));
          expect(layout.itemExtent(i), extent);
          expect(layout.itemAtOffset(offset), i, reason: 'start of $i');
          expect(layout.itemAtOffset(offset + extent / 2), i);
          if (i > 0) expect(layout.lastItemBefore(offset), i - 1);
          expect(layout.lastItemBefore(offset + extent / 2), i);
          offset += extent;
        }
        expect(layout.totalExtent, closeTo(offset, 1e-6));
        expect(layout.itemAtOffset(offset + 1), layout.itemCount);
        expect(layout.lastItemBefore(offset + 1), layout.itemCount - 1);
      }
    });

    test('groupAtOffset finds the header above an offset', () {
      final layout = GroupedListLayout.scan(rowCount: 5, startsGroup: (r) => r == 2, headerExtent: 40, rowExtent: 60);
      // group 0: header 0..40, rows 40..160; group 1: header 160..200, rows 200..380
      expect(layout.groupAtOffset(0), 0);
      expect(layout.groupAtOffset(159), 0);
      expect(layout.groupAtOffset(160), 1);
      expect(layout.groupAtOffset(10000), 1);
    });
  });

  group('SliverGroupedList', () {
    Future<ScrollController> pumpList(
      WidgetTester tester,
      Widget Function(GroupedListLayout) sliver,
      GroupedListLayout layout,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        Directionality(
          textDirection: TextDirection.ltr,
          child: CustomScrollView(controller: controller, slivers: [sliver(layout)]),
        ),
      );
      return controller;
    }

    SliverChildBuilderDelegate delegate(GroupedListLayout layout) => SliverChildBuilderDelegate(
      childCount: layout.itemCount,
      (context, i) => Text('item $i', textDirection: TextDirection.ltr),
    );

    testWidgets('exact extent and positions with 33k items', (tester) async {
      final layout = ongLogSized();
      final controller = await pumpList(tester, (l) => SliverGroupedList(layout: l, delegate: delegate(l)), layout);
      final viewport = tester.getSize(find.byType(CustomScrollView)).height;
      expect(controller.position.maxScrollExtent, layout.totalExtent - viewport);
      for (final item in [1, 777, 16000, layout.itemCount - 30]) {
        controller.jumpTo(layout.itemOffset(item));
        await tester.pump();
        expect(tester.getTopLeft(find.text('item $item')).dy, 0, reason: 'item $item at the top');
      }
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(tester.getBottomLeft(find.text('item ${layout.itemCount - 1}')).dy, viewport);
    });

    testWidgets('cost per frame at the end of 33k items, vs SliverVariedExtentList', (tester) async {
      final layout = ongLogSized();
      Future<double> microsPerFrame(Widget Function(GroupedListLayout) sliver) async {
        final controller = await pumpList(tester, sliver, layout);
        final max = controller.position.maxScrollExtent;
        // warm up, then scroll frame by frame near the end (like a fling)
        controller.jumpTo(max - 5000);
        await tester.pump();
        final watch = Stopwatch()..start();
        const frames = 100;
        for (var f = 0; f < frames; f++) {
          controller.jumpTo(max - 5000 + f * 40);
          await tester.pump();
        }
        return watch.elapsedMicroseconds / frames;
      }

      final grouped = await microsPerFrame((l) => SliverGroupedList(layout: l, delegate: delegate(l)));
      await tester.pumpWidget(const SizedBox());
      final varied = await microsPerFrame(
        (l) => SliverVariedExtentList(
          delegate: delegate(l),
          itemExtentBuilder: (i, _) => i < l.itemCount ? l.itemExtent(i) : null,
        ),
      );
      // ignore: avoid_print
      print(
        'per frame at the end of ${layout.itemCount} items: SliverGroupedList ${(grouped / 1000).toStringAsFixed(2)} ms, '
        'SliverVariedExtentList ${(varied / 1000).toStringAsFixed(2)} ms',
      );
      // Measured 17 times faster. A wide margin: two timings taken one after the other on a shared build machine.
      expect(grouped * 2, lessThan(varied));
    });
  });
}
