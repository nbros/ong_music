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
import 'layout.dart';
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
  Catalogue? _layoutCatalogue;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(playFilterProvider).query);
    // before the focused widget: the search field would move its cursor with the arrows
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  /// ↑ and ↓ select the previous or next play (not the headers), in an
  /// expanded window.
  KeyEventResult _onKey(KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    final key = listKeyOf(event, ref.read(searchFocusProvider(AppTab.ongLog)));
    if (key == null || key == ListKey.enter || !listHasKeys(context, ref, AppTab.ongLog)) {
      return KeyEventResult.ignored;
    }
    final results = _layoutResults;
    final layout = _layout;
    final catalogue = _layoutCatalogue;
    if (results == null || layout == null || catalogue == null || results.isEmpty) return KeyEventResult.handled;
    final step = key == ListKey.next ? 1 : -1;
    final stack = ref.read(detailPaneProvider(AppTab.ongLog));
    final play = selectedPlayId(stack);
    final stream = selectedStreamId(stack);
    var index = play == null ? -1 : results.ids.indexOf(play);
    int next;
    if (index >= 0) {
      next = index + step;
    } else {
      // a selected header: its first row, or the row above it
      index = stream == null ? -1 : _firstRowOf(results, layout, stream);
      next = index < 0 ? 0 : (step > 0 ? index : index - 1);
    }
    // a play without a song has no fiche: passed over
    while (next >= 0 && next < results.length && catalogue.songOfPlay(results[next]) == null) {
      next += step;
    }
    if (next < 0 || next >= results.length) return KeyEventResult.handled;
    final p = results[next];
    showSongSheet(context, catalogue, catalogue.songOfPlay(p)!, play: p);
    // in view below the pinned header (the row's own header, for the first row of a stream)
    revealExtent(_scroll, layout.itemOffset(layout.itemOfRow(next)), layout.rowExtent, inset: layout.headerExtent);
    return KeyEventResult.handled;
  }

  /// The first row of stream [stream] in [results], or -1.
  static int _firstRowOf(PlayResults results, GroupedListLayout layout, int stream) {
    for (final row in layout.groupStarts) {
      if (results[row].streamId == stream) return row;
    }
    return -1;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
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
    final hasMine = ref.watch(myPlayCountProvider) > 0;
    // without own play there is no "You" chip, and no filter on it
    final mine = filter.mine && hasMine;
    final anyChip = filter.type != null || filter.genre != null || filter.withVideo || mine;
    final layout = _layoutOf(results, filter, ListMetrics.of(context));
    _layoutCatalogue = catalogue;
    final noRoom = FiltersOutOfRoom.of(context);
    final searching = results.tokens.isNotEmpty;
    return Column(
      children: [
        ListSearchField(
          controller: _search,
          focusNode: ref.watch(searchFocusProvider(AppTab.ongLog)),
          hint: 'Search ${formatCount(catalogue.playCount)} songs played live',
          onChanged: notifier.setQuery,
        ),
        // kept, with its scroll position, while it is out of the way
        Visibility(
          visible: !noRoom,
          maintainState: true,
          child: ChipRow(
            children: [
              ListChip(label: 'All', selected: !anyChip, onTap: notifier.clearChips),
              // right after "All", near where the Highlights list has it: in sight on a phone without scrolling the row
              if (hasMine) ListChip(label: 'You', icon: Icons.person, selected: mine, onTap: notifier.toggleMine),
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
        ),
        if (!noRoom && (searching || anyChip))
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
                SliverToBoxAdapter(
                  child: searching
                      ? const EmptyMessage(
                          title: 'Never played… yet',
                          text: 'Check the spelling, or request it on stream.',
                        )
                      : const EmptyMessage(title: 'No song matches', text: 'Try fewer filters.'),
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
    final expanded = AppLayout.modeOf(context) == WindowMode.expanded;
    return SliverGroupedList(
      layout: layout,
      delegate: SliverChildBuilderDelegate(childCount: layout.itemCount, (context, item) {
        final row = layout.rowOfItem(item);
        if (row < 0) {
          final stream = _streamOfRow(catalogue, results, layout.groupStarts[layout.groupOfItem(item)]);
          void onTap() => showStreamSheet(context, catalogue, stream);
          if (expanded) {
            return _SelectableHeader(key: ValueKey(('s', stream.id)), stream: stream, onTap: onTap);
          }
          return StreamHeader(key: ValueKey(('s', stream.id)), stream: stream, onTap: onTap);
        }
        final play = results[row];
        void onTap() {
          final song = catalogue.songOfPlay(play);
          if (song != null) showSongSheet(context, catalogue, song, play: play);
        }

        if (expanded) {
          // only the rows whose state changes are built again when the selection changes
          return Consumer(
            key: ValueKey(play.id),
            builder: (context, ref, _) => PlayRow(
              catalogue: catalogue,
              play: play,
              tokens: results.tokens,
              me: me,
              selected: ref.watch(detailPaneProvider(AppTab.ongLog).select((s) => selectedPlayId(s) == play.id)),
              onTap: onTap,
              onVideo: (h) => openVideo(context, ref, h),
            ),
          );
        }
        return PlayRow(
          key: ValueKey(play.id),
          catalogue: catalogue,
          play: play,
          tokens: results.tokens,
          me: me,
          onTap: onTap,
          onVideo: (h) => openVideo(context, ref, h),
        );
      }),
    );
  }
}

/// The header of [stream] in an expanded window, marked when its setlist is
/// the selected fiche.
class _SelectableHeader extends ConsumerWidget {
  const _SelectableHeader({super.key, required this.stream, required this.onTap});

  final LiveStream stream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) => StreamHeader(
    stream: stream,
    onTap: onTap,
    selected: ref.watch(detailPaneProvider(AppTab.ongLog).select((s) => selectedStreamId(s) == stream.id)),
  );
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
      void onTap() => showStreamSheet(context, catalogue, stream);
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
              // the state of the header it stands for
              child: AppLayout.modeOf(context) == WindowMode.expanded
                  ? _SelectableHeader(stream: stream, onTap: onTap)
                  : StreamHeader(stream: stream, onTap: onTap),
            ),
          ),
        ),
      );
    },
  );
}
