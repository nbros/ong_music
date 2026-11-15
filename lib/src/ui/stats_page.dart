/// The statistics page, opened from the About tab: the totals of the catalogue, and every song, artist, genre or
/// requester of the Ong Log, the most played (or requesting) first.
library;

import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../data/rankings.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import 'app.dart';
import 'format.dart';
import 'instant_feedback.dart';
import 'list_scaffold.dart';
import 'sheets.dart';
import 'theme.dart';
import 'view_state.dart';
import 'widgets.dart';

/// The title of the page, and the label of the row of the About tab that opens it.
const String statsTitle = 'Statistics';

/// The labels of the rankings, in the order of the segmented choice.
const Map<RankingKind, String> rankingLabels = {
  RankingKind.songs: 'Songs',
  RankingKind.artists: 'Artists',
  RankingKind.genres: 'Genres',
  RankingKind.requesters: 'Requesters',
};

/// The hint of a row that opens the Ong Log on its plays (an artist, a genre, a requester).
const String _inOngLogHint = 'Shows them in the Ong Log';

/// Opens the statistics page over the app. Its back arrow, the system's back button, the browser's Back (the page
/// has a step of its own in the history, at the address of the About tab, as the licences page) and Escape close
/// it.
Future<void> showStatsPage(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (context) => const StatsPage()));

/// The totals of the head: `1,426 streams · 31,430 plays · 10,644 songs · 1,955 highlights`. The songs are those
/// played live, which the Songs ranking lists.
String statsTotals(Catalogue catalogue, CatalogueRankings rankings) => [
  plural(catalogue.streamCount, 'stream'),
  plural(catalogue.playCount, 'play'),
  plural(rankings.songs.length, 'song'),
  plural(catalogue.highlightCount, 'highlight'),
].join(' · ');

/// What the line over a ranking says it holds: `10,644 songs`, `5,617 artists · 2,691 plays without artist`,
/// `14 genres`, `1,670 requesters` (all of them, the user's own row alone in the list with "You").
String rankingCountLine(RankingKind kind, CatalogueRankings rankings) => switch (kind) {
  RankingKind.songs => plural(rankings.songs.length, 'song'),
  RankingKind.artists =>
    rankings.playsWithoutArtist == 0
        ? plural(rankings.artists.length, 'artist')
        : '${plural(rankings.artists.length, 'artist')} · '
              '${plural(rankings.playsWithoutArtist, 'play')} without artist',
  RankingKind.genres => plural(rankings.genres.length, 'genre'),
  RankingKind.requesters => plural(rankings.requesterCount, 'requester'),
};

/// The extent of a row of a ranking: a title, a subtitle and the bar (64 px at the default text size).
double rankingRowExtent(ListMetrics metrics) => math.max(64, 16 + metrics.title + metrics.subtitle + 6 + _barHeight);

const double _barHeight = 4;

/// The statistics page.
///
/// Under its title, pinned: the totals of the catalogue, the choice of the ranking, and the "You" chip when the
/// Twitch name has requests (with the number of entries of the ranking). Then the ranking, every entry of it in a
/// lazy list of rows of one extent.
///
/// It needs the Songs sheet, which it asks for as the Ong Log does; meanwhile, and when it fails, it shows what the
/// Ong Log shows. Going to a tab from what opens over it (a link of a fiche) closes it.
class StatsPage extends ConsumerStatefulWidget {
  const StatsPage({super.key});

  @override
  ConsumerState<StatsPage> createState() => _StatsPageState();
}

class _StatsPageState extends ConsumerState<StatsPage> implements ListModel {
  final _scroll = ScrollController();
  late final _keyboard = ListKeyboard(tab: null, model: this, scroll: _scroll);

  /// The ranking as the list was built last, and what its rows open.
  _Shown? _shown;

  @override
  void initState() {
    super.initState();
    // before the focused widget: a segment would take the arrows, a button Escape
    FocusManager.instance.addEarlyKeyEventHandler(_onKey);
    // after the first frame, which must not wait for it, and never while building
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ref.read(catalogueProvider.notifier).songsWanted(SongsTrigger.stats);
    });
  }

  @override
  void dispose() {
    FocusManager.instance.removeEarlyKeyEventHandler(_onKey);
    _keyboard.dispose();
    _scroll.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(KeyEvent event) {
    if (!mounted) return KeyEventResult.ignored;
    // Escape closes the page, as it closes a sheet; not under a sheet or a dialog, which it closes first
    if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
      if (!nothingOver(context) || isEditingText()) return KeyEventResult.ignored;
      Navigator.of(context).maybePop();
      return KeyEventResult.handled;
    }
    return _keyboard.handle(event);
  }

  /// Closes the page and what is over it: the app went to a tab (a link of a fiche opened over the page).
  void _close() {
    if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
  }

  // the list for the keyboard: one item per entry, every one a row; ↑ and ↓ stop at those that open something

  @override
  int get itemCount => _shown?.ranking.length ?? 0;

  @override
  double offsetOf(int item) => item * _shown!.extent;

  @override
  double extentOf(int item) => _shown!.extent;

  @override
  int itemAt(double offset) => (offset / _shown!.extent).floor().clamp(0, math.max(0, itemCount - 1));

  @override
  bool stopsAt(int item) => _shown!.opens(item);

  @override
  bool isHeader(int item) => false;

  @override
  int? headerOf(int item) => null;

  @override
  int? get pinnedHeader => null;

  @override
  double get inset => 0;

  @override
  Object keyOf(int item) => _shown!.keyOf(item);

  @override
  int itemOf(Object key) => _shown?.itemOf(key) ?? -1;

  @override
  int? get selected => null;

  @override
  void choose(int item) => _shown!.open(context, ref, item);

  @override
  void openDetails(int item) => _shown!.open(context, ref, item);

  @override
  bool start() => false;

  @override
  Widget build(BuildContext context) {
    ref.listen(selectedTabProvider, (_, _) => _close());
    ref.listen(statsViewProvider.select((v) => v.kind), (_, _) {
      if (_scroll.hasClients) _scroll.jumpTo(0);
    });
    final catalogue = ref.watch(currentCatalogueProvider);
    final Widget body;
    if (catalogue == null) {
      _shown = null;
      body = const CatalogueStatusView(ongLog: true);
    } else if (!catalogue.hasSongs) {
      // the highlights are there, the Songs sheet not yet: the page waits for it as the Ong Log does
      _shown = null;
      body = const CatalogueStatusView(songs: true);
    } else {
      body = _content(catalogue);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text(statsTitle),
        // the bar stays as it is when the list scrolls: it is not over the list (the head is between them)
        notificationPredicate: (_) => false,
      ),
      body: SafeArea(
        bottom: false,
        child: ContentColumn(maxWidth: maxContentWidth, child: body),
      ),
    );
  }

  Widget _content(Catalogue catalogue) {
    final view = ref.watch(statsViewProvider);
    final hasMine = ref.watch(myPlayCountProvider) > 0;
    // without own request there is no "You" chip, and no filter on it
    final mine = view.mine && hasMine;
    final rankings = ref.watch(rankingsProvider(mine))!;
    final all = mine ? ref.watch(rankingsProvider(false))! : rankings;
    final extent = rankingRowExtent(ListMetrics.of(context));
    final me = ref.watch(myRequesterKeyProvider);
    final old = _shown;
    // the same rows as before (another build of the page): the same object, and the rows found again cheaply
    final shown = _shown =
        old != null &&
            identical(old.rankings, rankings) &&
            old.kind == view.kind &&
            old.extent == extent &&
            old.me == me
        ? old
        : _Shown.of(rankings, view.kind, extent, me: me);
    final notifier = ref.read(statsViewProvider.notifier);
    final on3 = OngColors.of(context).on3;
    return LayoutBuilder(
      builder: (context, constraints) {
        // a window too low for the whole head and a few rows (a phone held sideways, large text): the choice of the
        // ranking alone, the list under it
        final scaler = MediaQuery.textScalerOf(context);
        final head = scaler.scale(12) * 16 / 12 * 2 + 12 + 48 + 48;
        final noRoom = constraints.maxHeight - head < 2.5 * shown.extent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!noRoom)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  statsTotals(catalogue, all),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, height: 16 / 12, color: on3),
                ),
              ),
            _RankingChoice(selected: view.kind, onSelected: notifier.show),
            if (!noRoom)
              _CountLine(
                text: rankingCountLine(view.kind, rankings),
                chip: hasMine
                    ? ListChip(label: 'You', icon: Icons.person, selected: mine, onTap: notifier.toggleMine)
                    : null,
              )
            else
              const SizedBox(height: 4),
            Expanded(
              child: ListFrame(
                controller: _scroll,
                keyboard: _keyboard,
                songs: true,
                slivers: [
                  _RankingList(
                    shown: shown,
                    // the column of the ranks as wide in every ranking: the titles do not move from one to the next
                    // (the songs have the largest ranks, of every play)
                    widestRank: math.max(_lastRank(all.songs), _lastRank(shown.ranking)),
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The rank of the last entry of [ranking], 1 when it has none.
int _lastRank(Ranking<Object> ranking) => ranking.isEmpty ? 1 : ranking.ranks.last;

/// The choice of the ranking: four segments across the column, which scroll sideways when their labels need more
/// room than it has (a narrow phone with large text).
class _RankingChoice extends StatelessWidget {
  const _RankingChoice({required this.selected, required this.onSelected});

  final RankingKind selected;
  final void Function(RankingKind kind) onSelected;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => HorizontalScroll(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      arrows: true,
      child: ConstrainedBox(
        // as wide as the column when the labels fit: the segments share it
        constraints: BoxConstraints(minWidth: math.max(0, constraints.maxWidth - 32)),
        child: SegmentedButton<RankingKind>(
          showSelectedIcon: false,
          // the labels of 360 px wide phones at the default text size: little room around them
          style: const ButtonStyle(padding: WidgetStatePropertyAll(EdgeInsets.symmetric(horizontal: 4))),
          segments: [
            for (final MapEntry(key: kind, value: label) in rankingLabels.entries)
              ButtonSegment(value: kind, label: Text(label, maxLines: 1, softWrap: false)),
          ],
          selected: {selected},
          onSelectionChanged: (selection) => onSelected(selection.single),
        ),
      ),
    ),
  );
}

/// The line under the choice: the "You" chip when there is one, and what the ranking holds.
class _CountLine extends StatelessWidget {
  const _CountLine({required this.text, required this.chip});

  final String text;
  final Widget? chip;

  @override
  Widget build(BuildContext context) {
    final chip = this.chip;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, chip == null ? 8 : 0, 16, chip == null ? 8 : 0),
      child: Row(
        children: [
          if (chip != null) ...[chip, const SizedBox(width: 12)],
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, height: 16 / 12, color: OngColors.of(context).on3),
            ),
          ),
        ],
      ),
    );
  }
}

/// A ranking as the list shows it: what each of its rows says and opens. Made once per ranking shown.
sealed class _Shown {
  _Shown(this.rankings, this.extent, this.me);

  /// The ranking of [kind] of [rankings], its rows [extent] high; [me] is the folded Twitch name.
  factory _Shown.of(CatalogueRankings rankings, RankingKind kind, double extent, {required String me}) =>
      switch (kind) {
        RankingKind.songs => _Songs(rankings, extent, me),
        RankingKind.artists => _Artists(rankings, extent, me),
        RankingKind.genres => _Genres(rankings, extent, me),
        RankingKind.requesters => _Requesters(rankings, extent, me),
      };

  final CatalogueRankings rankings;
  final double extent;
  final String me;

  RankingKind get kind;
  Catalogue get catalogue => rankings.catalogue;

  /// Whether the ranking counts the user's own requests alone.
  bool get mine => rankings.requesterId != null;

  Ranking<Object> get ranking;

  /// What finds the row of [item] again in the same ranking of another catalogue (a refresh): its [kind] and what
  /// stays of its entry.
  (RankingKind, Object) keyOf(int item) => (kind, _keyOf(item));

  Object _keyOf(int item);

  /// The item of [key], or -1; only a key of this [kind] is looked for (the map of the rows is made then).
  int itemOf(Object key) {
    if (key is! (RankingKind, Object) || key.$1 != kind) return -1;
    final items = _items ??= {for (var i = 0; i < ranking.length; i++) _keyOf(i): i};
    return items[key.$2] ?? -1;
  }

  Map<Object, int>? _items;

  /// The title of the row of [item], as screen readers read it too.
  String title(int item);

  /// The line under the title, or null.
  String? subtitle(int item);

  /// The unit of the count, said to screen readers: `12 plays`.
  String spokenCount(int item) => plural(ranking.counts[item], 'play');

  /// The colour of the bar of [item].
  Color barColor(BuildContext context, int item) => Theme.of(context).colorScheme.primary;

  /// Whether [item] opens something.
  bool opens(int item) => true;

  /// Opens what the row of [item] shows.
  void open(BuildContext context, WidgetRef ref, int item);

  /// The hint of a row that [opens] something.
  String get hint => _inOngLogHint;

  /// The title as a span, for a title that is not plain text (the user's own name).
  InlineSpan? titleSpan(BuildContext context, int item) => null;

  /// Whether [subtitle] is part of the name of the entry (the artist of a song), said before the count; otherwise
  /// it is said after it (the songs of an artist, the share of a genre).
  bool get subtitleNames => false;

  /// The whole row in one sentence, for screen readers: `Rank 1, Song of Storms, Zelda, 245 plays`, `Rank 2, Zelda,
  /// 1,234 plays, 56 songs`.
  String sentence(int item) {
    final subtitle = this.subtitle(item);
    return [
      'Rank ${formatCount(ranking.ranks[item])}',
      title(item),
      if (subtitleNames) ?subtitle,
      spokenCount(item),
      if (!subtitleNames) ?subtitle,
    ].join(', ');
  }
}

final class _Songs extends _Shown {
  _Songs(super.rankings, super.extent, super.me);

  @override
  RankingKind get kind => RankingKind.songs;

  @override
  late final Ranking<Song> ranking = rankings.songs;

  @override
  Object _keyOf(int item) => ranking.entries[item].key;

  @override
  String title(int item) => ranking.entries[item].track;

  @override
  String? subtitle(int item) {
    final artist = ranking.entries[item].artist;
    return artist.isEmpty ? null : artist;
  }

  @override
  bool get subtitleNames => true;

  @override
  String get hint => 'Shows the details';

  @override
  void open(BuildContext context, WidgetRef ref, int item) => showSongSheet(context, catalogue, ranking.entries[item]);
}

final class _Artists extends _Shown {
  _Artists(super.rankings, super.extent, super.me);

  @override
  RankingKind get kind => RankingKind.artists;

  @override
  late final Ranking<Artist> ranking = rankings.artists;

  @override
  Object _keyOf(int item) => ranking.entries[item].folded;

  @override
  String title(int item) => ranking.entries[item].name;

  @override
  String subtitle(int item) => plural(ranking.entries[item].songCount, 'song');

  /// The Ong Log searching the artist's name (which finds the titles holding it elsewhere too).
  @override
  void open(BuildContext context, WidgetRef ref, int item) {
    Navigator.of(context).pop();
    showInOngLog(ref, query: ranking.entries[item].name, mine: mine);
  }
}

final class _Genres extends _Shown {
  _Genres(super.rankings, super.extent, super.me);

  @override
  RankingKind get kind => RankingKind.genres;

  @override
  late final Ranking<Genre> ranking = rankings.genres;

  @override
  Object _keyOf(int item) => ranking.entries[item];

  @override
  String title(int item) => ranking.entries[item].label;

  @override
  String subtitle(int item) => formatShare(ranking.counts[item], ranking.total);

  @override
  Color barColor(BuildContext context, int item) => genreColors[ranking.entries[item]]!;

  /// The genres of the chips of the Ong Log: not "Other", which has none.
  @override
  bool opens(int item) => ranking.entries[item] != Genre.other;

  /// The Ong Log on the chip of the genre.
  @override
  void open(BuildContext context, WidgetRef ref, int item) {
    if (!opens(item)) return;
    Navigator.of(context).pop();
    showInOngLog(ref, genre: ranking.entries[item], mine: mine);
  }
}

final class _Requesters extends _Shown {
  _Requesters(super.rankings, super.extent, super.me);

  @override
  RankingKind get kind => RankingKind.requesters;

  @override
  late final Ranking<Requester> ranking = rankings.requesters;

  bool _own(int item) => catalogue.isRequester(ranking.entries[item].id, me);

  @override
  Object _keyOf(int item) => ranking.entries[item].folded;

  @override
  String title(int item) => ranking.entries[item].name;

  /// The different songs they asked for.
  @override
  String subtitle(int item) => plural(rankings.songsRequestedBy(ranking.entries[item]), 'song');

  @override
  String sentence(int item) => [
    'Rank ${formatCount(ranking.ranks[item])}',
    if (_own(item)) '${title(item)}, you' else title(item),
    spokenCount(item),
    subtitle(item),
  ].join(', ');

  @override
  String spokenCount(int item) => plural(ranking.counts[item], 'request');

  @override
  Color barColor(BuildContext context, int item) =>
      _own(item) ? OngColors.of(context).brand : super.barColor(context, item);

  @override
  InlineSpan? titleSpan(BuildContext context, int item) =>
      _own(item) ? TextSpan(children: requesterSpans(context, ranking.entries[item].name, const [], own: true)) : null;

  /// The Ong Log on the requests of the requester, as "Requested by …" of a fiche.
  @override
  void open(BuildContext context, WidgetRef ref, int item) {
    Navigator.of(context).pop();
    showRequesterInOngLog(ref, ranking.entries[item].name);
  }
}

/// The rows of a ranking, built lazily, all of one extent.
class _RankingList extends ConsumerWidget {
  const _RankingList({required this.shown, required this.widestRank});

  final _Shown shown;

  /// The rank the column of the ranks is as wide as.
  final int widestRank;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shown = this.shown;
    final ranking = shown.ranking;
    // the widths of the rank and count columns, from their largest numbers in tabular figures: once per list built,
    // never per row
    final rankWidth = _textWidth(context, formatCount(widestRank), _RankRow.rankStyle);
    final countWidth = _textWidth(
      context,
      formatCount(ranking.isEmpty ? 1 : ranking.counts.first),
      _RankRow.countStyle,
    );
    return SliverFixedExtentList(
      itemExtent: shown.extent,
      delegate: SliverChildBuilderDelegate(
        childCount: ranking.length,
        // a refresh moves the rows on screen instead of building new ones: a row keeps its keyboard focus
        findChildIndexCallback: (key) {
          if (key is! ValueKey<Object>) return null;
          final item = shown.itemOf(key.value);
          return item < 0 ? null : item;
        },
        (context, item) => _RankRow(
          key: ValueKey<Object>(shown.keyOf(item)),
          rank: formatCount(ranking.ranks[item]),
          title: shown.title(item),
          titleSpan: shown.titleSpan(context, item),
          subtitle: shown.subtitle(item),
          count: formatCount(ranking.counts[item]),
          // never less than a sliver: a row with a count of 1 far down a long ranking still has a bar
          share: ranking.top == 0 ? 0 : math.max(0.01, ranking.counts[item] / ranking.top),
          barColor: shown.barColor(context, item),
          rankWidth: rankWidth,
          countWidth: countWidth,
          label: shown.sentence(item),
          hint: shown.hint,
          onTap: shown.opens(item) ? () => shown.open(context, ref, item) : null,
        ),
      ),
    );
  }

  /// The width of [text] in [style] at the text scale of [context], rounded up.
  static double _textWidth(BuildContext context, String text, TextStyle style) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: DefaultTextStyle.of(context).style.merge(style)),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width.ceilToDouble();
    painter.dispose();
    return width;
  }
}

/// A row of a ranking: its rank, its title over a subtitle, its count on the right, and under them a bar as long,
/// against the first row's, as its count. Read by screen readers as one sentence ([label]).
class _RankRow extends StatelessWidget {
  const _RankRow({
    super.key,
    required this.rank,
    required this.title,
    required this.titleSpan,
    required this.subtitle,
    required this.count,
    required this.share,
    required this.barColor,
    required this.rankWidth,
    required this.countWidth,
    required this.label,
    required this.hint,
    required this.onTap,
  });

  final String rank;
  final String title;

  /// The title when it is not plain text (the user's own name), or null.
  final InlineSpan? titleSpan;
  final String? subtitle;
  final String count;

  /// The length of the bar, from 0 to 1.
  final double share;
  final Color barColor;

  /// The widths of the columns of the ranks and of the counts, the same in every row of the list.
  final double rankWidth;
  final double countWidth;

  final String label;
  final String hint;

  /// Opens what the row shows; null when it opens nothing.
  final VoidCallback? onTap;

  static const rankStyle = TextStyle(
    fontSize: 13,
    height: 20 / 13,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const countStyle = TextStyle(
    fontSize: 15,
    height: 20 / 15,
    fontWeight: FontWeight.w500,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    final titleStyle = TextStyle(fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w500, color: scheme.onSurface);
    final subtitle = this.subtitle;
    final titleSpan = this.titleSpan;
    final indent = rankWidth + 12;
    final body = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // centred, not on one baseline: the rank's smaller text would make the line a fraction of a pixel higher
          // than the title's (the extent of the row is the sum of its lines)
          Row(
            children: [
              SizedBox(
                width: rankWidth,
                child: Text(
                  rank,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  style: rankStyle.copyWith(color: ong.on3),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: titleSpan == null
                    ? Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: titleStyle)
                    : RequesterText(titleSpan, maxLines: 1, style: titleStyle),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: countWidth,
                child: Text(
                  count,
                  textAlign: TextAlign.end,
                  maxLines: 1,
                  style: countStyle.copyWith(color: scheme.onSurface),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: EdgeInsets.only(left: indent),
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, height: 18 / 13, color: scheme.onSurfaceVariant),
              ),
            ),
          Padding(
            padding: EdgeInsets.only(left: indent, top: 6),
            child: _Bar(share: share, color: barColor, track: scheme.onSurface.withValues(alpha: 0.06)),
          ),
        ],
      ),
    );
    final onTap = this.onTap;
    return Semantics(
      container: true,
      button: onTap != null,
      label: label,
      hint: onTap == null ? null : hint,
      // the ink well's own action goes with its semantics
      onTap: onTap,
      excludeSemantics: true,
      child: onTap == null ? body : AppInkWell(onTap: onTap, child: body),
    );
  }
}

/// The bar of a row: [share] of its width in [color], over a [track] the whole width.
class _Bar extends StatelessWidget {
  const _Bar({required this.share, required this.color, required this.track});

  final double share;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(_barHeight / 2),
    child: SizedBox(
      height: _barHeight,
      child: ColoredBox(
        color: track,
        child: FractionallySizedBox(
          alignment: AlignmentDirectional.centerStart,
          widthFactor: share.clamp(0, 1),
          child: DecoratedBox(
            decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(_barHeight / 2)),
          ),
        ),
      ),
    ),
  );
}
