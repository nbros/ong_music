/// The Highlights tab: search, genre chips, and the videos, newest first.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import 'actions.dart';
import 'format.dart';
import 'layout.dart';
import 'list_scaffold.dart';
import 'rows.dart';
import 'sheets.dart';
import 'view_state.dart';
import 'widgets.dart';

/// The Highlights tab.
class HighlightsPage extends ConsumerStatefulWidget {
  const HighlightsPage({super.key});

  @override
  ConsumerState<HighlightsPage> createState() => _HighlightsPageState();
}

class _HighlightsPageState extends ConsumerState<HighlightsPage> {
  late final TextEditingController _search;
  final _scroll = ScrollController();

  HighlightResults? _shownResults;
  HighlightFilter? _shownFilter;
  Catalogue? _shownCatalogue;
  double _shownRowExtent = 0;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController(text: ref.read(highlightFilterProvider).query);
    // before the focused widget: the search field would move its cursor with the arrows
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
  }

  /// ↑ and ↓ select the previous or next highlight, Enter starts the video of
  /// the selected one (an expanded window).
  KeyEventResult _onKey(KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    final key = listKeyOf(event, ref.read(searchFocusProvider(AppTab.highlights)));
    if (key == null || !listHasKeys(context, ref, AppTab.highlights)) return KeyEventResult.ignored;
    final stack = ref.read(detailPaneProvider(AppTab.highlights));
    if (key == ListKey.enter) {
      final selected = stack.firstOrNull;
      if (selected is! HighlightFiche || selected.highlight.youtubeId == null) return KeyEventResult.ignored;
      startVideo(context, ref, selected.highlight);
      return KeyEventResult.handled;
    }
    final results = _shownResults;
    final catalogue = _shownCatalogue;
    if (results == null || catalogue == null || results.isEmpty) return KeyEventResult.handled;
    final selected = selectedHighlightId(stack);
    final index = selected == null ? -1 : results.ids.indexOf(selected);
    // nothing selected in the list (filtered out): its first row
    final next = index < 0 ? 0 : (index + (key == ListKey.next ? 1 : -1)).clamp(0, results.length - 1);
    if (next != index) showHighlightSheet(context, catalogue, catalogue.highlights[results.ids[next]]);
    revealExtent(_scroll, next * _shownRowExtent, _shownRowExtent);
    return KeyEventResult.handled;
  }

  /// Keeps what is on screen there when the rows change under the same
  /// [filter] (a filter change jumps to the top instead).
  void _keepPosition(Catalogue catalogue, HighlightResults results, HighlightFilter filter, double rowExtent) {
    final shown = _shownResults;
    if (shown != null && identical(results, shown)) {
      // the text size changed: the row at the top of the list stays there
      final oldExtent = _shownRowExtent;
      if (rowExtent != oldExtent) reanchorScroll(_scroll, (offset) => offset * rowExtent / oldExtent);
    } else if (shown != null && filter == _shownFilter && !identical(catalogue, _shownCatalogue)) {
      // a refresh brought another catalogue: new highlights come first, the
      // rows on screen keep their distance to the end of the list (after the
      // text size correction, should both change in the same frame)
      final resize = rowExtent / _shownRowExtent;
      reanchorScroll(_scroll, (offset) => offset * resize + (results.length - shown.length) * rowExtent);
    }
    // otherwise the same catalogue lost or gained rows in place (a star removed under the star chip): the offset
    // stays, the rows below move up
    _shownResults = results;
    _shownFilter = filter;
    _shownCatalogue = catalogue;
    _shownRowExtent = rowExtent;
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(highlightFilterProvider, (previous, next) {
      if (_search.text != next.query) _search.text = next.query;
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    final catalogue = ref.watch(currentCatalogueProvider);
    if (catalogue == null) return const CatalogueStatusView();
    final filter = ref.watch(highlightFilterProvider);
    final results = ref.watch(highlightResultsProvider(filter))!;
    _keepPosition(catalogue, results, filter, ListMetrics.of(context).highlightRow);
    final searching = results.tokens.isNotEmpty;
    final inOngLog = searching ? ref.watch(playCountForQueryProvider(filter.query)) : 0;
    final notifier = ref.read(highlightFilterProvider.notifier);
    final myCount = ref.watch(myHighlightCountProvider);
    final favouriteCount = ref.watch(favouriteCountProvider);
    // without own highlight there is no "You" chip, and no filter on it; the same for the favourites
    final mine = filter.mine && myCount > 0;
    final favourites = filter.favourites && favouriteCount > 0;
    final counts = results.counts;
    final noRoom = FiltersOutOfRoom.of(context);
    final anyChip = filter.genre != null || mine || favourites;
    return Column(
      children: [
        ListSearchField(
          controller: _search,
          focusNode: ref.watch(searchFocusProvider(AppTab.highlights)),
          hint: 'Search ${formatCount(catalogue.highlightCount)} highlights',
          onChanged: notifier.setQuery,
        ),
        // kept, with its scroll position, while it is out of the way
        Visibility(
          visible: !noRoom,
          maintainState: true,
          child: ChipRow(
            children: [
              ListChip(label: 'All', selected: !anyChip, onTap: notifier.clearChips),
              // each count is what the list would show with that chip selected, the rest unchanged; each chip keeps
              // the width of its count over the whole catalogue, the largest it can show
              if (favouriteCount > 0)
                ListChip(
                  label: 'Favourites',
                  showLabel: false,
                  icon: Icons.star,
                  count: counts.keys,
                  maxCount: favouriteCount,
                  selected: favourites,
                  onTap: notifier.toggleFavourites,
                ),
              if (myCount > 0)
                ListChip(
                  label: 'You',
                  icon: Icons.person,
                  count: counts.requester,
                  maxCount: myCount,
                  selected: mine,
                  onTap: notifier.toggleMine,
                ),
              for (final g in catalogue.highlightGenreCounts)
                if (g.genre != Genre.other)
                  ListChip(
                    label: g.genre.label,
                    count: counts.genre(g.genre),
                    maxCount: g.count,
                    selected: filter.genre == g.genre,
                    onTap: () => notifier.toggleGenre(g.genre),
                  ),
            ],
          ),
        ),
        if (!noRoom && (searching || anyChip))
          CountLine(
            text: plural(results.length, 'highlight'),
            link: inOngLog > 0 ? '${formatCount(inOngLog)} in the Ong Log' : null,
            onLink: () => showOngLogFor(ref, filter.query),
          )
        else
          const SizedBox(height: 4),
        Expanded(
          child: ListFrame(
            controller: _scroll,
            slivers: [
              if (results.isEmpty)
                SliverToBoxAdapter(
                  child: EmptyMessage(
                    title: 'No highlight matches',
                    text: inOngLog > 0
                        ? 'The song may still be in the Ong Log.'
                        : (searching
                              ? (anyChip ? 'Try fewer words, or fewer filters.' : 'Try fewer words.')
                              : 'Try fewer filters.'),
                  ),
                )
              else
                _HighlightList(catalogue: catalogue, results: results),
            ],
          ),
        ),
      ],
    );
  }
}

class _HighlightList extends ConsumerWidget {
  const _HighlightList({required this.catalogue, required this.results});

  final Catalogue catalogue;
  final HighlightResults results;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myRequesterKeyProvider);
    final currentYear = ref.watch(clockProvider)().toLocal().year;
    final expanded = AppLayout.modeOf(context) == WindowMode.expanded;
    final mouse = expanded && AppLayout.mouseOf(context);
    return SliverFixedExtentList(
      itemExtent: ListMetrics.of(context).highlightRow,
      delegate: SliverChildBuilderDelegate(childCount: results.length, (context, i) {
        final h = catalogue.highlights[results.ids[i]];
        if (expanded) {
          // a row shows its fiche in the pane; only the rows whose state changes are built again when the
          // selection changes
          return Consumer(
            key: ValueKey(h.id),
            builder: (context, ref, _) => HighlightRow(
              catalogue: catalogue,
              highlight: h,
              tokens: results.tokens,
              me: me,
              currentYear: currentYear,
              selected: ref.watch(
                detailPaneProvider(AppTab.highlights).select((stack) => selectedHighlightId(stack) == h.id),
              ),
              onTap: () => showHighlightSheet(context, catalogue, h),
              onThumbnail: mouse ? () => openVideo(context, ref, h) : null,
            ),
          );
        }
        return HighlightRow(
          key: ValueKey(h.id),
          catalogue: catalogue,
          highlight: h,
          tokens: results.tokens,
          me: me,
          currentYear: currentYear,
          onTap: () => h.youtubeId == null ? showHighlightSheet(context, catalogue, h) : openVideo(context, ref, h),
          onMore: () => showHighlightSheet(context, catalogue, h),
        );
      }),
    );
  }
}
