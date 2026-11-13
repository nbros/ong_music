/// A lazy list of rows grouped under headers, with exact extents.
///
/// Every header has one extent and every row another, so the scroll offset of
/// any item, the item at any offset and the total extent are computed exactly
/// with a binary search over the groups (O(log groups)), never by summing the
/// items before it. [SliverVariedExtentList] would give exact extents too, but
/// it sums them from index 0 on every lookup: O(index) several times per frame.
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Positions of the items of a grouped list.
///
/// The list shows `rowCount` rows split into consecutive groups; each group is
/// a header item followed by its row items. Item indices count both kinds.
@immutable
final class GroupedListLayout {
  /// [groupStarts] holds the index (among rows) of the first row of each
  /// group, ascending, starting with 0 when there is any row.
  GroupedListLayout({
    required this.groupStarts,
    required this.rowCount,
    required this.headerExtent,
    required this.rowExtent,
  }) : assert(rowCount == 0 || (groupStarts.isNotEmpty && groupStarts.first == 0)),
       assert(headerExtent > 0 && rowExtent > 0);

  /// Groups starting wherever [startsGroup] is true for a row index (row 0
  /// always starts one). O(rowCount): build it once per data set, not per frame.
  factory GroupedListLayout.scan({
    required int rowCount,
    required bool Function(int row) startsGroup,
    required double headerExtent,
    required double rowExtent,
  }) {
    final starts = <int>[];
    for (var i = 0; i < rowCount; i++) {
      if (i == 0 || startsGroup(i)) starts.add(i);
    }
    return GroupedListLayout(
      groupStarts: Int32List.fromList(starts),
      rowCount: rowCount,
      headerExtent: headerExtent,
      rowExtent: rowExtent,
    );
  }

  final Int32List groupStarts;
  final int rowCount;
  final double headerExtent;
  final double rowExtent;

  /// Same groups with other extents (text scale changed).
  GroupedListLayout withExtents({required double headerExtent, required double rowExtent}) =>
      headerExtent == this.headerExtent && rowExtent == this.rowExtent
      ? this
      : GroupedListLayout(
          groupStarts: groupStarts,
          rowCount: rowCount,
          headerExtent: headerExtent,
          rowExtent: rowExtent,
        );

  int get groupCount => groupStarts.length;
  int get itemCount => rowCount + groupCount;
  double get totalExtent => rowCount * rowExtent + groupCount * headerExtent;

  /// Number of rows in group [g].
  int groupSize(int g) => (g + 1 < groupCount ? groupStarts[g + 1] : rowCount) - groupStarts[g];

  /// Item index of the header of group [g].
  int headerItem(int g) => groupStarts[g] + g;

  /// Scroll offset of the header of group [g].
  double headerOffset(int g) => groupStarts[g] * rowExtent + g * headerExtent;

  /// The group item [item] belongs to (its header or one of its rows).
  int groupOfItem(int item) {
    var lo = 0, hi = groupCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (headerItem(mid) <= item) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The item index of row [row].
  int itemOfRow(int row) {
    var lo = 0, hi = groupCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (groupStarts[mid] <= row) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return row + lo + 1;
  }

  /// Whether item [item] is a header.
  bool isHeader(int item) => headerItem(groupOfItem(item)) == item;

  /// The row index of item [item], or -1 for a header.
  int rowOfItem(int item) {
    final g = groupOfItem(item);
    final h = headerItem(g);
    return item == h ? -1 : groupStarts[g] + item - h - 1;
  }

  /// Extent of item [item].
  double itemExtent(int item) => isHeader(item) ? headerExtent : rowExtent;

  /// Scroll offset of item [item]; [totalExtent] for `item >= itemCount`.
  double itemOffset(int item) {
    if (item <= 0) return 0;
    if (item >= itemCount) return totalExtent;
    final g = groupOfItem(item);
    final h = headerItem(g);
    final offset = headerOffset(g);
    return item == h ? offset : offset + headerExtent + (item - h - 1) * rowExtent;
  }

  /// The group whose header is at or above [offset] (0 above the first one).
  int groupAtOffset(double offset) {
    var lo = 0, hi = groupCount - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (headerOffset(mid) <= offset + precisionErrorTolerance) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// The item covering [offset]: the later one on a boundary; [itemCount] at or
  /// past the end.
  int itemAtOffset(double offset) {
    if (offset <= 0) return 0;
    if (offset >= totalExtent - precisionErrorTolerance) return itemCount;
    final g = groupAtOffset(offset);
    final inGroup = offset - headerOffset(g);
    if (inGroup < headerExtent - precisionErrorTolerance) return headerItem(g);
    final exact = (inGroup - headerExtent) / rowExtent;
    final round = exact.round();
    final k = (exact - round).abs() * rowExtent < precisionErrorTolerance ? round : exact.floor();
    return headerItem(g) + 1 + math.min(k, groupSize(g) - 1);
  }

  /// The last item starting before [offset] (the one covering it, or the
  /// earlier one on a boundary).
  int lastItemBefore(double offset) {
    if (offset <= 0 || itemCount == 0) return 0;
    final item = itemAtOffset(offset);
    if (item >= itemCount) return itemCount - 1;
    return item > 0 && (itemOffset(item) - offset).abs() < precisionErrorTolerance ? item - 1 : item;
  }
}

/// The sliver: builds item `i` with [delegate] (whose child count must be
/// [GroupedListLayout.itemCount]) and gives it its exact extent.
class SliverGroupedList extends SliverMultiBoxAdaptorWidget {
  /// Creates the sliver.
  const SliverGroupedList({super.key, required super.delegate, required this.layout});

  final GroupedListLayout layout;

  @override
  RenderSliverGroupedList createRenderObject(BuildContext context) =>
      RenderSliverGroupedList(childManager: context as SliverMultiBoxAdaptorElement, groupedLayout: layout);

  @override
  void updateRenderObject(BuildContext context, RenderSliverGroupedList renderObject) {
    renderObject.groupedLayout = layout;
  }
}

/// Render object of [SliverGroupedList]: the fixed-extent machinery of the
/// framework with O(log groups) lookups.
class RenderSliverGroupedList extends RenderSliverFixedExtentBoxAdaptor {
  /// Creates the render object.
  RenderSliverGroupedList({required super.childManager, required GroupedListLayout groupedLayout})
    : _layout = groupedLayout;

  GroupedListLayout _layout;
  GroupedListLayout get groupedLayout => _layout;
  set groupedLayout(GroupedListLayout value) {
    if (identical(value, _layout)) return;
    _layout = value;
    markNeedsLayout();
  }

  @override
  double? get itemExtent => null;

  @override
  ItemExtentBuilder? get itemExtentBuilder => _extentOf;

  double? _extentOf(int index, SliverLayoutDimensions dimensions) =>
      index < 0 || index >= _layout.itemCount ? null : _layout.itemExtent(index);

  @override
  double indexToLayoutOffset(double itemExtent, int index) => _layout.itemOffset(index);

  @override
  int getMinChildIndexForScrollOffset(double scrollOffset, double itemExtent) => _layout.itemAtOffset(scrollOffset);

  @override
  int getMaxChildIndexForScrollOffset(double scrollOffset, double itemExtent) => _layout.lastItemBefore(scrollOffset);

  @override
  double computeMaxScrollOffset(SliverConstraints constraints, double itemExtent) => _layout.totalExtent;

  @override
  double estimateMaxScrollOffset(
    SliverConstraints constraints, {
    int? firstIndex,
    int? lastIndex,
    double? leadingScrollOffset,
    double? trailingScrollOffset,
  }) => _layout.totalExtent;
}
