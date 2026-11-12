/// The three detail sheets: a highlight, a song (every time it was played)
/// and a stream setlist.
///
/// A sheet keeps the [Catalogue] it was opened with: ids are only valid with
/// their catalogue, and a background refresh may replace it meanwhile.
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../state/catalogue_state.dart';
import '../state/settings_state.dart';
import 'actions.dart';
import 'format.dart';
import 'rows.dart';
import 'theme.dart';
import 'view_state.dart';
import 'widgets.dart';

/// Shows a detail sheet. Called from inside a sheet, it replaces that sheet.
Future<void> showDetailSheet(BuildContext context, WidgetBuilder builder) {
  final navigator = Navigator.of(context);
  if (ModalRoute.of(context) is ModalBottomSheetRoute) navigator.pop();
  final host = navigator.context;
  final size = MediaQuery.sizeOf(host);
  return showModalBottomSheet<void>(
    context: host,
    isScrollControlled: true,
    showDragHandle: true,
    useSafeArea: true,
    constraints: BoxConstraints(maxWidth: 640, maxHeight: size.height * 0.9),
    // no slide when the system asks for less motion
    sheetAnimationStyle: MediaQuery.disableAnimationsOf(host) ? AnimationStyle.noAnimation : null,
    builder: builder,
  );
}

/// Shows the sheet of [highlight].
Future<void> showHighlightSheet(BuildContext context, Catalogue catalogue, Highlight highlight) =>
    showDetailSheet(context, (_) => HighlightSheet(catalogue: catalogue, highlight: highlight));

/// Shows the sheet of [song].
Future<void> showSongSheet(BuildContext context, Catalogue catalogue, Song song) =>
    showDetailSheet(context, (_) => SongSheet(catalogue: catalogue, song: song));

/// Shows the setlist of [stream], scrolled to [play] (tinted) when given.
Future<void> showStreamSheet(BuildContext context, Catalogue catalogue, LiveStream stream, {Play? play}) =>
    showDetailSheet(context, (_) => StreamSheet(catalogue: catalogue, stream: stream, play: play));

/// Closes the sheet and searches the requests of [requester] in the Ong Log.
void _showRequester(BuildContext context, WidgetRef ref, Requester requester) {
  Navigator.of(context).pop();
  showRequesterInOngLog(ref, requester.name);
}

// ------------------------------------------------------------------ layout

/// The scrollable body of a sheet: content height, at most the sheet's.
class _SheetBody extends StatelessWidget {
  const _SheetBody({required this.slivers, this.controller});

  final List<Widget> slivers;
  final ScrollController? controller;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewPaddingOf(context).bottom;
    return Scrollbar(
      controller: controller,
      thumbVisibility: alwaysShowScrollbars(context),
      child: CustomScrollView(
        controller: controller,
        // without a controller, the scrollbar follows the primary one: desktop does not attach it by itself
        primary: controller == null,
        shrinkWrap: true,
        scrollBehavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        slivers: [
          ...slivers,
          SliverPadding(padding: EdgeInsets.only(bottom: 28 + bottom)),
        ],
      ),
    );
  }
}

/// The small line above a sheet title: `● Popular · Highlight #1951`.
class _Overline extends StatelessWidget {
  const _Overline({this.genre, required this.text});

  final Genre? genre;
  final String text;

  @override
  Widget build(BuildContext context) {
    final genre = this.genre;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          if (genre != null) GenreDot(genre),
          Flexible(
            child: Text(
              text,
              style: TextStyle(fontSize: 12, height: 16 / 12, color: OngColors.of(context).on3),
            ),
          ),
        ],
      ),
    );
  }
}

/// Title and artist of a sheet.
class _Title extends StatelessWidget {
  const _Title({required this.title, this.subtitle = ''});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SelectableText(
          title,
          style: TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w500, color: scheme.onSurface),
        ),
        if (subtitle.isNotEmpty)
          Text(
            subtitle,
            style: TextStyle(fontSize: 15, height: 22 / 15, color: scheme.onSurfaceVariant),
          ),
      ],
    );
  }
}

/// A line of facts: icon, text with an optional small line, chevron when it
/// leads somewhere.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text, this.detail, this.trailing, this.onTap});

  final IconData icon;
  final String text;
  final String? detail;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final on3 = OngColors.of(context).on3;
    final detail = this.detail;
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
        child: Row(
          children: [
            SizedBox(width: 24, child: Icon(icon, size: 20, color: on3)),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: text),
                        if (trailing != null) inlineWidget(trailing!),
                      ],
                    ),
                    style: TextStyle(fontSize: 14, height: 20 / 14, color: scheme.onSurface),
                  ),
                  if (detail != null)
                    Text(
                      detail,
                      style: TextStyle(fontSize: 12, height: 16 / 12, color: on3),
                    ),
                ],
              ),
            ),
            if (onTap != null) Icon(Icons.chevron_right, size: 20, color: on3),
          ],
        ),
      ),
    );
    // a tappable fact is announced as a button, in one piece; the others are read as text
    return onTap == null
        ? MergeSemantics(child: body)
        : Semantics(
            button: true,
            child: InkWell(onTap: onTap, child: body),
          );
  }
}

/// A tonal round icon button (Share, Copy).
class _TonalIcon extends StatelessWidget {
  const _TonalIcon({super.key, required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 20,
    style: IconButton.styleFrom(minimumSize: const Size(40, 40), fixedSize: const Size(40, 40)),
    icon: Icon(icon),
  );
}

/// Copies the title and the link of the video, the text "Share" shares, then
/// shows a check mark for a moment instead of a message (and tells screen
/// readers).
class _CopyButton extends StatefulWidget {
  const _CopyButton({required this.highlight});

  final Highlight highlight;

  @override
  State<_CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<_CopyButton> {
  Timer? _reset;

  bool get _copied => _reset?.isActive ?? false;

  Future<void> _copy() async {
    final view = View.of(context);
    final direction = Directionality.of(context);
    final copied = await copyHighlight(widget.highlight);
    if (!mounted) return;
    if (!copied) return showMessage(context, 'Couldn’t copy');
    _reset?.cancel();
    setState(
      () => _reset = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() {});
      }),
    );
    SemanticsService.sendAnnouncement(view, 'Copied', direction);
  }

  @override
  void dispose() {
    _reset?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 150),
    child: _TonalIcon(
      key: ValueKey(_copied),
      icon: _copied ? Icons.check : Icons.copy,
      tooltip: _copied
          ? 'Copied'
          : widget.highlight.youtubeId == null
          ? 'Copy title'
          : 'Copy title and link',
      onPressed: _copy,
    ),
  );
}

/// The star of a highlight sheet: adds the highlight to the favourites, or
/// removes it. A state, not an action: a plain icon, not a tonal circle like
/// [_TonalIcon]. Its tap target follows the theme as theirs does (48 px on
/// touch screens, 40 with a mouse), so that it stays in line with the Copy
/// button below it.
class _FavouriteButton extends ConsumerWidget {
  const _FavouriteButton({required this.highlight});

  final Highlight highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = highlight.key;
    final favourite = ref.watch(favouritesProvider.select((keys) => keys.contains(key)));
    return IconButton(
      tooltip: favourite ? 'Remove from favourites' : 'Add to favourites',
      onPressed: () => ref.read(favouritesProvider.notifier).toggle(highlight),
      // a toggle for screen readers, with its state
      icon: Semantics(
        toggled: favourite,
        child: favourite
            ? Icon(Icons.star, color: OngColors.of(context).brand)
            : Icon(Icons.star_border, color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}

// ------------------------------------------------------------------ highlight

/// Details of a highlight: big thumbnail, actions, stream, requester, other
/// plays, vocals and notes.
class HighlightSheet extends ConsumerWidget {
  const HighlightSheet({super.key, required this.catalogue, required this.highlight});

  final Catalogue catalogue;
  final Highlight highlight;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myRequesterKeyProvider);
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    final h = highlight;
    final hasVideo = h.youtubeId != null;
    final requester = catalogue.requester(h.requesterId);
    final song = catalogue.songOfHighlight(h);
    final play = catalogue.playOf(h);
    final year = ref.watch(clockProvider)().toLocal().year;
    final streamDate = h.streamDate;
    final uploadDate = h.uploadDate;
    return _SheetBody(
      slivers: [
        if (hasVideo)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
              // for the eye and the finger only: screen readers get the "Watch on YouTube" button below,
              // which does the same
              child: ExcludeSemantics(
                child: GestureDetector(
                  onTap: () => openVideo(context, ref, h),
                  child: MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        alignment: Alignment.center,
                        children: [
                          Thumbnail(youtubeId: h.youtubeId, width: constraints.maxWidth, big: true, radius: 16),
                          Container(
                            width: 56,
                            height: 56,
                            decoration: const BoxDecoration(color: Color(0xAA000000), shape: BoxShape.circle),
                            child: const Icon(Icons.play_arrow, size: 32, color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Overline(genre: h.genre, text: '${h.genre.label} · Highlight #${h.seq}'),
                // the star always has its place: the title wraps before it, and nothing moves when it changes
                Row(
                  children: [
                    Expanded(
                      child: _Title(title: h.track, subtitle: h.artist),
                    ),
                    _FavouriteButton(highlight: h),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 6),
                  child: Row(
                    spacing: 8,
                    children: [
                      Expanded(
                        child: hasVideo
                            ? FilledButton.icon(
                                onPressed: () => openVideo(context, ref, h),
                                style: FilledButton.styleFrom(
                                  backgroundColor: ong.brand,
                                  foregroundColor: ong.onBrand,
                                  minimumSize: const Size(0, 40),
                                  textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                ),
                                icon: const Icon(Icons.play_arrow, size: 20),
                                label: const Text('Watch on YouTube'),
                              )
                            : FilledButton.tonal(
                                onPressed: null,
                                style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                                child: const Text('Video unavailable'),
                              ),
                      ),
                      _TonalIcon(icon: Icons.share, tooltip: 'Share', onPressed: () => shareHighlight(context, ref, h)),
                      _CopyButton(highlight: h),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              children: [
                if (streamDate != null)
                  _Fact(
                    icon: Icons.calendar_today,
                    text: 'Played live on ${formatFullDate(streamDate)}',
                    detail: uploadDate == null ? null : 'Uploaded ${formatShortDate(uploadDate, currentYear: year)}',
                    onTap: play == null
                        ? null
                        : () => showStreamSheet(context, catalogue, catalogue.streamOf(play), play: play),
                  )
                else if (uploadDate != null)
                  _Fact(icon: Icons.calendar_today, text: 'Uploaded ${formatFullDate(uploadDate)}'),
                if (requester != null)
                  _Fact(
                    icon: Icons.person,
                    text: 'Requested by ${requester.name}',
                    trailing: catalogue.isRequester(requester.id, me) ? const Tag.you() : null,
                    detail: '${plural(requester.requestCount, 'request')} in the Ong Log',
                    onTap: () => _showRequester(context, ref, requester),
                  ),
                if (song != null && song.playIds.length > 1)
                  _Fact(
                    icon: Icons.history,
                    text: 'Played ${formatCount(song.playIds.length)} times live',
                    detail: [
                      if (song.highlightIds.length > 1) plural(song.highlightIds.length, 'video'),
                      if (song.firstPlayed != null) 'first in ${song.firstPlayed!.year}',
                    ].join(' · '),
                    onTap: () => showSongSheet(context, catalogue, song),
                  ),
                if (h.vocals != Vocals.unknown)
                  _Fact(
                    icon: h.vocals == Vocals.yes ? Icons.mic : Icons.piano,
                    text: h.vocals == Vocals.yes ? 'With vocals' : 'Instrumental',
                  ),
              ],
            ),
          ),
        ),
        if (h.notes.isNotEmpty)
          SliverToBoxAdapter(
            child: Container(
              margin: const EdgeInsets.fromLTRB(20, 8, 20, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
              child: SelectableText(
                h.notes,
                style: TextStyle(fontSize: 13, height: 19 / 13, color: scheme.onSurfaceVariant),
              ),
            ),
          ),
      ],
    );
  }
}

// ------------------------------------------------------------------ song

/// Every time a song was played, with its videos.
class SongSheet extends ConsumerWidget {
  const SongSheet({super.key, required this.catalogue, required this.song});

  final Catalogue catalogue;
  final Song song;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(myRequesterKeyProvider);
    final scheme = Theme.of(context).colorScheme;
    final on3 = OngColors.of(context).on3;
    final metrics = ListMetrics.of(context);
    final s = song;
    final plays = s.playIds;
    final videos = s.highlightIds.reversed.map((id) => catalogue.highlights[id]).toList();
    final year = ref.watch(clockProvider)().toLocal().year;
    // read as "13 plays", not as two separate pieces
    Widget stat(String value, String label) => Expanded(
      child: MergeSemantics(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(color: scheme.surfaceContainerHigh, borderRadius: BorderRadius.circular(12)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value,
                maxLines: 1,
                style: TextStyle(fontSize: 20, height: 26 / 20, fontWeight: FontWeight.w500, color: scheme.onSurface),
              ),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, height: 16 / 12, color: on3),
              ),
            ],
          ),
        ),
      ),
    );
    return _SheetBody(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _Overline(genre: s.genre, text: s.genre.label),
                _Title(title: s.track, subtitle: s.artist),
                Padding(
                  padding: const EdgeInsets.only(top: 16, bottom: 8),
                  child: IntrinsicHeight(
                    child: Row(
                      spacing: 8,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        stat(formatCount(plays.length), plays.length == 1 ? 'play' : 'plays'),
                        stat(s.firstPlayed?.year.toString() ?? '–', 'first played'),
                        stat(formatCount(videos.length), videos.length == 1 ? 'video' : 'videos'),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (videos.isNotEmpty)
          SliverToBoxAdapter(
            child: HorizontalScroll(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
              child: Row(
                spacing: 12,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final v in videos)
                    Semantics(
                      button: true,
                      label: 'Video of ${formatShortDate(v.date, currentYear: year)}',
                      excludeSemantics: true,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => v.youtubeId == null
                            ? showHighlightSheet(context, catalogue, v)
                            : openVideo(context, ref, v),
                        child: SizedBox(
                          width: 150,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Thumbnail(youtubeId: v.youtubeId, width: 150),
                              const SizedBox(height: 2),
                              Text(
                                formatShortDate(v.date, currentYear: year),
                                style: TextStyle(fontSize: 12, height: 16 / 12, color: on3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        if (plays.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 2),
              child: Text(
                'Every time it was played',
                style: TextStyle(fontSize: 13, height: 20 / 13, fontWeight: FontWeight.w500, color: scheme.primary),
              ),
            ),
          ),
          SliverFixedExtentList(
            itemExtent: metrics.historyRow,
            delegate: SliverChildBuilderDelegate(childCount: plays.length, (context, i) {
              final play = catalogue.plays[plays[plays.length - 1 - i]];
              return HistoryRow(
                catalogue: catalogue,
                play: play,
                me: me,
                onTap: () => showStreamSheet(context, catalogue, catalogue.streamOf(play), play: play),
                onVideo: (h) => openVideo(context, ref, h),
              );
            }),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------------------ stream

/// The setlist of a stream, in order.
class StreamSheet extends ConsumerStatefulWidget {
  const StreamSheet({super.key, required this.catalogue, required this.stream, this.play});

  final Catalogue catalogue;
  final LiveStream stream;

  /// The play the sheet was opened from: tinted and scrolled into view.
  final Play? play;

  @override
  ConsumerState<StreamSheet> createState() => _StreamSheetState();
}

class _StreamSheetState extends ConsumerState<StreamSheet> {
  final _controller = ScrollController();
  final _headerKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (widget.play != null) SchedulerBinding.instance.addPostFrameCallback((_) => _scrollToPlay());
  }

  /// Centres the tinted row once the header has its size.
  void _scrollToPlay() {
    final play = widget.play;
    final header = _headerKey.currentContext?.size?.height;
    if (!mounted || play == null || header == null || !_controller.hasClients) return;
    final rowExtent = ListMetrics.of(context).playRow;
    final position = _controller.position;
    final index = play.id - widget.stream.firstPlayId;
    final target = header + index * rowExtent - (position.viewportDimension - rowExtent) / 2;
    _controller.jumpTo(target.clamp(0, position.maxScrollExtent));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final me = ref.watch(myRequesterKeyProvider);
    final catalogue = widget.catalogue;
    final s = widget.stream;
    final metrics = ListMetrics.of(context);
    final videos = s.highlightIds.length;
    return _SheetBody(
      controller: _controller,
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            key: _headerKey,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _Overline(text: 'Stream setlist'),
                _Title(title: formatFullDate(s.date)),
                const SizedBox(height: 2),
                Text(
                  '${formatStreamSize(s)}${videos > 0 ? ' · ${plural(videos, 'video')}' : ''}',
                  style: TextStyle(
                    fontSize: 13,
                    height: 18 / 13,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverFixedExtentList(
          itemExtent: metrics.playRow,
          delegate: SliverChildBuilderDelegate(childCount: s.playCount, (context, i) {
            final play = catalogue.plays[s.firstPlayId + i];
            return PlayRow(
              catalogue: catalogue,
              play: play,
              tokens: const [],
              me: me,
              tinted: play.id == widget.play?.id,
              onTap: () {
                final song = catalogue.songOfPlay(play);
                if (song != null) showSongSheet(context, catalogue, song);
              },
              onVideo: (h) => openVideo(context, ref, h),
            );
          }),
        ),
      ],
    );
  }
}
