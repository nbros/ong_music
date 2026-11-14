/// The Highlights tab: search, genre chips, and the videos, newest first.
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

class _HighlightsPageState extends ConsumerState<HighlightsPage> implements ListModel {
  late final TextEditingController _search;
  final _scroll = ScrollController();
  late final _keyboard = ListKeyboard(tab: AppTab.highlights, model: this, scroll: _scroll);
  late final _onKey = _keyboard.handle;

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

  // the list for the keyboard: one item per highlight shown, every one a row

  @override
  int get itemCount => _shownCatalogue == null ? 0 : _shownResults?.length ?? 0;

  @override
  double offsetOf(int item) => item * _shownRowExtent;

  @override
  double extentOf(int item) => _shownRowExtent;

  @override
  int itemAt(double offset) => (offset / _shownRowExtent).floor().clamp(0, math.max(0, itemCount - 1));

  @override
  bool stopsAt(int item) => true;

  @override
  bool isHeader(int item) => false;

  @override
  int? headerOf(int item) => null;

  @override
  int? get pinnedHeader => null;

  @override
  double get inset => 0;

  Highlight _highlight(int item) => _shownCatalogue!.highlights[_shownResults!.ids[item]];

  /// A highlight by its key, which a refresh keeps (not by its id, its place in the sheet, which changes when a
  /// highlight above it goes).
  @override
  Object keyOf(int item) => highlightRowKey(_shownCatalogue!, _highlight(item));

  @override
  int itemOf(Object key) {
    final results = _shownResults;
    final catalogue = _shownCatalogue;
    if (results == null || catalogue == null || key is! String) return -1;
    return rowOfKey(catalogue, results, key);
  }

  @override
  int? get selected {
    final id = selectedHighlightId(ref.read(detailPaneProvider(AppTab.highlights)));
    final item = id == null ? -1 : _shownResults?.indexOf(id) ?? -1;
    return item < 0 ? null : item;
  }

  @override
  void choose(int item) => showHighlightSheet(context, _shownCatalogue!, _highlight(item));

  @override
  void openDetails(int item) => showHighlightSheet(context, _shownCatalogue!, _highlight(item));

  /// Enter on the selected row, or with nothing focused: the video of the highlight of the pane (its row may be
  /// filtered out), in the pane (with nothing over its fiche) or on YouTube.
  @override
  bool start() {
    // the video of the fiche of the list, not of one stacked on it
    final fiche = ref.read(detailPaneProvider(AppTab.highlights)).firstOrNull;
    if (fiche is! HighlightFiche || fiche.highlight.youtubeId == null) return false;
    startVideo(context, ref, fiche.highlight);
    return true;
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
    _keyboard.dispose();
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
            keyboard: _keyboard,
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
      delegate: SliverChildBuilderDelegate(
        childCount: results.length,
        // a refresh adding highlights moves the rows on screen instead of building new ones: a row keeps its state,
        // its keyboard focus among it
        findChildIndexCallback: (key) =>
            key is ValueKey<String> ? _orNull(rowOfKey(catalogue, results, key.value)) : null,
        (context, i) {
          final h = catalogue.highlights[results.ids[i]];
          if (expanded) {
            // a row shows its fiche in the pane; only the rows whose state changes are built again when the
            // selection changes
            return Consumer(
              key: ValueKey(highlightRowKey(catalogue, h)),
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
            key: ValueKey(highlightRowKey(catalogue, h)),
            catalogue: catalogue,
            highlight: h,
            tokens: results.tokens,
            me: me,
            currentYear: currentYear,
            onTap: () => h.youtubeId == null ? showHighlightSheet(context, catalogue, h) : openVideo(context, ref, h),
            onMore: () => showHighlightSheet(context, catalogue, h),
          );
        },
      ),
    );
  }
}

/// [index], or null when it is -1.
int? _orNull(int index) => index < 0 ? null : index;

/// The rows of each result by the keys of their highlights, made when first needed (a key press, a list built
/// again over rows already there): once per result.
final _rowsByKey = Expando<Map<String, int>>('rows by key');

/// The row keys of the highlights of each catalogue, by id, made when first needed: once per catalogue.
final _rowKeys = Expando<List<String>>('row keys');

/// What tells the row of [highlight] from every other one and stays the same after a refresh: its
/// [Highlight.key], which highlights showing the same video share (two rows with one key would be taken for each
/// other when the list is built again), followed for the second and later ones, counted from the oldest so that
/// new highlights change nothing, by their rank among them.
String highlightRowKey(Catalogue catalogue, Highlight highlight) {
  final keys = _rowKeys[catalogue] ??= () {
    final seen = <String, int>{};
    return [
      for (final h in catalogue.highlights)
        switch (seen.update(h.key, (n) => n + 1, ifAbsent: () => 0)) {
          0 => h.key,
          final n => '${h.key}\n$n',
        },
    ];
  }();
  return keys[highlight.id];
}

/// The row of the highlight of [key] in [results] of [catalogue], or -1.
///
/// Rows are known by the keys of their highlights, which a refresh keeps: their ids are their places in the sheet,
/// which change when a highlight above them goes (the next one would take the row of the one gone, and its focus).
int rowOfKey(Catalogue catalogue, HighlightResults results, String key) {
  final rows = _rowsByKey[results] ??= {
    for (var i = results.length - 1; i >= 0; i--) highlightRowKey(catalogue, catalogue.highlights[results.ids[i]]): i,
  };
  return rows[key] ?? -1;
}
