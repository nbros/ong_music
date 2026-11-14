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

class _OngLogPageState extends ConsumerState<OngLogPage> implements ListModel {
  late final TextEditingController _search;
  final _scroll = ScrollController();
  late final _keyboard = ListKeyboard(tab: AppTab.ongLog, model: this, scroll: _scroll);
  late final _onKey = _keyboard.handle;

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

  // the list for the keyboard: the headers of the streams and their plays, as the list builds them; ↑ and ↓ stop
  // at the plays that have a fiche (a play without song has none: passed over)

  @override
  int get itemCount => _layoutCatalogue == null ? 0 : _layout?.itemCount ?? 0;

  @override
  double offsetOf(int item) => _layout!.itemOffset(item);

  @override
  double extentOf(int item) => _layout!.itemExtent(item);

  @override
  int itemAt(double offset) => _layout!.itemAtOffset(offset).clamp(0, math.max(0, itemCount - 1));

  @override
  bool stopsAt(int item) {
    final row = _layout!.rowOfItem(item);
    return row >= 0 && _layoutCatalogue!.songOfPlay(_layoutResults![row]) != null;
  }

  @override
  bool isHeader(int item) => _layout!.isHeader(item);

  @override
  int? headerOf(int item) => _layout!.headerItem(_layout!.groupOfItem(item));

  @override
  int? get pinnedHeader {
    final layout = _layout;
    if (layout == null || layout.groupCount == 0 || !_scroll.hasClients || _scroll.offset <= 0) return null;
    return layout.headerItem(layout.groupAtOffset(_scroll.offset));
  }

  @override
  double get inset => _layout?.headerExtent ?? 0;

  @override
  Object keyOf(int item) {
    final layout = _layout!;
    final row = layout.rowOfItem(item);
    // a header by its stream, a row by its play
    return row < 0
        ? ('stream', _layoutResults![layout.groupStarts[layout.groupOfItem(item)]].streamId)
        : _layoutResults!.ids[row];
  }

  @override
  int itemOf(Object key) {
    final results = _layoutResults;
    final layout = _layout;
    if (results == null || layout == null) return -1;
    if (key case ('stream', final int stream)) {
      final row = _layoutCatalogue == null ? -1 : results.firstOf(_layoutCatalogue!.streams[stream]);
      return row < 0 ? -1 : layout.itemOfRow(row) - 1;
    }
    final row = key is int ? results.indexOf(key) : -1;
    return row < 0 ? -1 : layout.itemOfRow(row);
  }

  @override
  int? get selected {
    final stack = ref.read(detailPaneProvider(AppTab.ongLog));
    final play = selectedPlayId(stack);
    final stream = selectedStreamId(stack);
    final item = play != null ? itemOf(play) : (stream != null ? itemOf(('stream', stream)) : -1);
    return item < 0 ? null : item;
  }

  @override
  void choose(int item) => openDetails(item);

  /// The setlist of a header, the song of a play.
  @override
  void openDetails(int item) {
    final catalogue = _layoutCatalogue!;
    final row = _layout!.rowOfItem(item);
    if (row < 0) {
      showStreamSheet(
        context,
        catalogue,
        catalogue.streamOf(_layoutResults![_layout!.groupStarts[_layout!.groupOfItem(item)]]),
      );
      return;
    }
    final play = _layoutResults![row];
    final song = catalogue.songOfPlay(play);
    if (song != null) showSongSheet(context, catalogue, song, play: play);
  }

  @override
  bool start() => false;

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    _keyboard.dispose();
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
    if (catalogue == null) return const CatalogueStatusView(ongLog: true);
    // the highlights are there, the Songs sheet not yet: the Ong Log waits for it as the app waits for both
    if (!catalogue.hasSongs) return const CatalogueStatusView(songs: true);
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
            keyboard: _keyboard,
            songs: true,
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
      delegate: SliverChildBuilderDelegate(
        childCount: layout.itemCount,
        // a refresh adding plays moves the rows on screen instead of building new ones: a row keeps its state, its
        // keyboard focus among it
        findChildIndexCallback: (key) {
          if (key is! ValueKey) return null;
          final row = switch (key.value) {
            final int play => results.indexOf(play),
            ('s', final int stream) when stream < catalogue.streams.length => results.firstOf(
              catalogue.streams[stream],
            ),
            _ => -1,
          };
          if (row < 0) return null;
          final item = layout.itemOfRow(row);
          return key.value is int ? item : item - 1;
        },
        (context, item) {
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
        },
      ),
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
