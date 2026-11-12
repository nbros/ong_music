/// The Ong Log tab: search, type and genre chips, and every play, newest
/// first, grouped by stream under headers that stay pinned while their rows
/// scroll.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import 'actions.dart';
import 'format.dart';
import 'grouped_list.dart';
import 'list_scaffold.dart';
import 'rows.dart';
import 'sheets.dart';
import 'view_state.dart';
import 'widgets.dart';

/// The Ong Log tab.
class OngLogPage extends ConsumerStatefulWidget {
  const OngLogPage({super.key});

  @override
  ConsumerState<OngLogPage> createState() => _OngLogPageState();
}

class _OngLogPageState extends ConsumerState<OngLogPage> {
  late final TextEditingController _search;
  final _scroll = ScrollController();

  PlayResults? _layoutResults;
  PlayFilter? _layoutFilter;
  GroupedListLayout? _layout;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(playFilterProvider).query);
  }

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// The layout of [results] at the current text scale; the groups are
  /// scanned once per result set (O(results)), never per frame.
  ///
  /// What is on screen stays there when the layout changes under the same
  /// [filter] (a filter change jumps to the top instead).
  GroupedListLayout _layoutOf(PlayResults results, PlayFilter filter, ListMetrics metrics) {
    final old = _layout;
    final GroupedListLayout layout;
    if (old != null && identical(results, _layoutResults)) {
      layout = old.withExtents(headerExtent: metrics.streamHeader, rowExtent: metrics.playRow);
      // the text size changed: the item at the top of the list stays there
      if (!identical(layout, old)) reanchorScroll(_scroll, (offset) => _sameItem(old, layout, offset));
    } else {
      layout = GroupedListLayout.scan(
        rowCount: results.length,
        startsGroup: results.startsStream,
        headerExtent: metrics.streamHeader,
        rowExtent: metrics.playRow,
      );
      // a refresh brought another catalogue: new plays come first, the rows on
      // screen keep their distance to the end of the list (after the text size
      // correction, should both change in the same frame)
      if (old != null && filter == _layoutFilter) {
        final resized = old.withExtents(headerExtent: metrics.streamHeader, rowExtent: metrics.playRow);
        reanchorScroll(_scroll, (offset) => _sameItem(old, resized, offset) + layout.totalExtent - resized.totalExtent);
      }
    }
    _layoutResults = results;
    _layoutFilter = filter;
    return _layout = layout;
  }

  /// The offset in [to] showing what [offset] shows in [from]: the same item,
  /// scrolled by the same share of its height. Both hold the same groups.
  static double _sameItem(GroupedListLayout from, GroupedListLayout to, double offset) {
    if (identical(from, to)) return offset;
    final item = from.itemAtOffset(offset);
    if (item >= from.itemCount) return to.totalExtent + offset - from.totalExtent;
    final shown = (offset - from.itemOffset(item)) / from.itemExtent(item);
    return to.itemOffset(item) + shown * to.itemExtent(item);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(playFilterProvider, (previous, next) {
      if (_search.text != next.query) _search.text = next.query;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    final catalogue = ref.watch(currentCatalogueProvider);
    if (catalogue == null) return const CatalogueStatusView();
    final filter = ref.watch(playFilterProvider);
    final results = ref.watch(playResultsProvider(filter))!;
    final notifier = ref.read(playFilterProvider.notifier);
    final anyChip = filter.type != null || filter.genre != null || filter.withVideo;
    final layout = _layoutOf(results, filter, ListMetrics.of(context));
    return Column(
      children: [
        ListSearchField(
          controller: _search,
          focusNode: ref.watch(searchFocusProvider(AppTab.ongLog)),
          hint: 'Search ${formatCount(catalogue.playCount)} songs played live',
          onChanged: notifier.setQuery,
        ),
        ChipRow(
          children: [
            ListChip(label: 'All', selected: !anyChip, onTap: notifier.clearChips),
            ListChip(
              label: 'Piano',
              icon: Icons.piano,
              selected: filter.type == PlayType.piano,
              onTap: () => notifier.toggleType(PlayType.piano),
            ),
            ListChip(
              label: 'Loop',
              icon: Icons.repeat,
              selected: filter.type == PlayType.loop,
              onTap: () => notifier.toggleType(PlayType.loop),
            ),
            ListChip(
              label: 'With video',
              icon: Icons.play_arrow,
              selected: filter.withVideo,
              onTap: notifier.toggleWithVideo,
            ),
            const ChipSeparator(),
            for (final g in catalogue.playGenreCounts)
              if (g.genre != Genre.other)
                ListChip(
                  label: g.genre.label,
                  selected: filter.genre == g.genre,
                  onTap: () => notifier.toggleGenre(g.genre),
                ),
          ],
        ),
        if (results.tokens.isNotEmpty || anyChip)
          CountLine(text: '${plural(results.length, 'song')} · ${plural(results.streamCount, 'stream')}')
        else
          const SizedBox(height: 4),
        Expanded(
          child: ListFrame(
            controller: _scroll,
            overlay: results.isEmpty
                ? null
                : _PinnedHeader(controller: _scroll, layout: layout, catalogue: catalogue, results: results),
            slivers: [
              if (results.isEmpty)
                const SliverToBoxAdapter(
                  child: EmptyMessage(title: 'Never played… yet', text: 'Check the spelling, or request it on stream.'),
                )
              else
                _PlayList(catalogue: catalogue, results: results, layout: layout),
            ],
          ),
        ),
      ],
    );
  }
}

/// The stream of row [row] of [results].
LiveStream _streamOfRow(Catalogue catalogue, PlayResults results, int row) => catalogue.streamOf(results[row]);

class _PlayList extends ConsumerWidget {
  const _PlayList({required this.catalogue, required this.results, required this.layout});

  final Catalogue catalogue;
  final PlayResults results;
  final GroupedListLayout layout;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myRequesterKeyProvider);
    return SliverGroupedList(
      layout: layout,
      delegate: SliverChildBuilderDelegate(childCount: layout.itemCount, (context, item) {
        final row = layout.rowOfItem(item);
        if (row < 0) {
          final stream = _streamOfRow(catalogue, results, layout.groupStarts[layout.groupOfItem(item)]);
          return StreamHeader(
            key: ValueKey(('s', stream.id)),
            stream: stream,
            onTap: () => showStreamSheet(context, catalogue, stream),
          );
        }
        final play = results[row];
        return PlayRow(
          key: ValueKey(play.id),
          catalogue: catalogue,
          play: play,
          tokens: results.tokens,
          me: me,
          onTap: () {
            final song = catalogue.songOfPlay(play);
            if (song != null) showSongSheet(context, catalogue, song);
          },
          onVideo: (h) => openVideo(context, ref, h),
        );
      }),
    );
  }
}

/// The header of the stream at the top of the viewport, drawn over the list.
///
/// It never moves: the next header of the list slides over it and takes its
/// place, so nothing but the scrolled content moves. O(log streams) per scroll
/// frame.
class _PinnedHeader extends StatelessWidget {
  const _PinnedHeader({required this.controller, required this.layout, required this.catalogue, required this.results});

  final ScrollController controller;
  final GroupedListLayout layout;
  final Catalogue catalogue;
  final PlayResults results;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) {
      if (!controller.hasClients || controller.positions.length != 1) return const SizedBox.shrink();
      final offset = controller.offset;
      // at the top (or overscrolled) the first header is in place already
      if (offset <= 0 || layout.groupCount == 0) return const SizedBox.shrink();
      final g = layout.groupAtOffset(offset);
      final next = g + 1 < layout.groupCount ? layout.headerOffset(g + 1) : double.infinity;
      // what the next header, on its way up, has not covered yet
      final visible = math.min(layout.headerExtent, next - offset);
      final stream = _streamOfRow(catalogue, results, layout.groupStarts[g]);
      return Positioned(
        top: 0,
        left: 0,
        right: 0,
        height: visible,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topCenter,
            minHeight: layout.headerExtent,
            maxHeight: layout.headerExtent,
            // screen readers get the header of the list while it is on screen
            child: ExcludeSemantics(
              excluding: offset < layout.headerOffset(g) + layout.headerExtent,
              child: StreamHeader(stream: stream, onTap: () => showStreamSheet(context, catalogue, stream)),
            ),
          ),
        ),
      );
    },
  );
}
