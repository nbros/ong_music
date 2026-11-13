/// The rows of the lists and sheets: a highlight, a play, a stream header and
/// a play in a song's history. Each one has the exact extent of
/// [ListMetrics] for its kind.
///
/// The sheet writes its dates and times in US Eastern time. Dates are shown as
/// written (the notes of the highlights and the videos quote them); only the
/// time of a play is shown in the zone of the device (`wallTimeProvider`).
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../state/catalogue_state.dart';
import 'format.dart';
import 'outside_link.dart';
import 'theme.dart';
import 'widgets.dart';

/// A row of the Highlights list: thumbnail, track, artist, genre · date ·
/// requester, and a ⋮ button.
///
/// In the list of an expanded window ([selected] not null), the row has the
/// selection and hover states of [InsetRoundedBorder.row], and no ⋮ button
/// (the detail pane shows what it opened).
class HighlightRow extends StatelessWidget {
  const HighlightRow({
    super.key,
    required this.catalogue,
    required this.highlight,
    required this.tokens,
    required this.me,
    required this.currentYear,
    required this.onTap,
    this.onMore,
    this.selected,
    this.onThumbnail,
  });

  final Catalogue catalogue;
  final Highlight highlight;
  final List<String> tokens;

  /// Dates of this year are shown without it.
  final int currentYear;

  /// The folded Twitch name of the user, whose name is highlighted.
  final String me;
  final VoidCallback onTap;

  /// The ⋮ button, which shows the details; none when null.
  final VoidCallback? onMore;

  /// Whether the row is the selected one of the list of an expanded window;
  /// null elsewhere.
  final bool? selected;

  /// Opens the video from the thumbnail: with a mouse, in an expanded window
  /// (with touch, the thumbnail is part of the row).
  final VoidCallback? onThumbnail;

  @override
  Widget build(BuildContext context) {
    final metrics = ListMetrics.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    final h = highlight;
    final onMore = this.onMore;
    final onThumbnail = h.youtubeId == null ? null : this.onThumbnail;
    final thumbnail = onThumbnail == null
        ? Thumbnail(youtubeId: h.youtubeId, width: ListMetrics.thumbnailWidth, label: '#${h.seq}')
        : _ThumbnailLink(youtubeId: h.youtubeId!, url: h.url, label: '#${h.seq}', onTap: onThumbnail);
    final artist = h.artist;
    final requester = catalogue.requester(h.requesterId);
    final date = formatShortDate(h.date, currentYear: currentYear);
    final meta = [h.genre.label, if (date.isNotEmpty) date].join(' · ');
    final row = SizedBox(
      height: metrics.highlightRow,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                thumbnail,
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        // clear of the ⋮ button, when there is one
                        padding: EdgeInsets.only(right: onMore == null ? 4 : 30),
                        child: MarkedText(
                          h.track,
                          tokens: tokens,
                          maxLines: artist.isEmpty ? 2 : 1,
                          style: TextStyle(
                            fontSize: 15,
                            height: 20 / 15,
                            fontWeight: FontWeight.w500,
                            color: scheme.onSurface,
                          ),
                        ),
                      ),
                      if (artist.isNotEmpty)
                        MarkedText(
                          artist,
                          tokens: tokens,
                          style: TextStyle(fontSize: 13, height: 18 / 13, color: scheme.onSurfaceVariant),
                        ),
                      const SizedBox(height: 2),
                      RequesterText(
                        TextSpan(
                          children: [
                            inlineWidget(GenreDot(h.genre)),
                            TextSpan(text: meta),
                            if (requester != null) ...[
                              const TextSpan(text: ' · '),
                              personIcon(ong.on3),
                              ...requesterSpans(
                                context,
                                requester.name,
                                tokens,
                                own: catalogue.isRequester(requester.id, me),
                              ),
                            ],
                          ],
                        ),
                        maxLines: 1,
                        style: TextStyle(fontSize: 12, height: 16 / 12, color: ong.on3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (onMore != null)
            Positioned(
              top: 0,
              right: 0,
              // no tooltip: a name for screen readers only
              child: IconButton(
                onPressed: onMore,
                icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant, semanticLabel: 'Details'),
              ),
            ),
        ],
      ),
    );
    final selected = this.selected;
    final content = h.youtubeId == null ? Opacity(opacity: 0.45, child: row) : row;
    return Semantics(
      button: true,
      selected: selected,
      hint: h.youtubeId == null || selected != null ? 'Shows the details' : 'Opens the video',
      child: selected == null
          ? InkWell(onTap: onTap, child: content)
          : _SelectableInk(selected: selected, shape: InsetRoundedBorder.row, onTap: onTap, child: content),
    );
  }
}

/// The ink of a row of a list in an expanded window, or of a fiche in the
/// detail pane: its tap, hover and focus states in [shape], and the tint of
/// [selected] behind the content. Only colours change: nothing moves.
class _SelectableInk extends StatelessWidget {
  const _SelectableInk({required this.selected, required this.shape, required this.onTap, required this.child});

  final bool selected;
  final ShapeBorder shape;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Material(
    // the ink of the row on the row: a list scrolls it with the row
    type: MaterialType.transparency,
    child: InkWell(
      onTap: onTap,
      customBorder: shape,
      hoverColor: hoveredRowColor(context),
      child: DecoratedBox(
        decoration: ShapeDecoration(color: selected ? selectedRowColor(context) : Colors.transparent, shape: shape),
        child: child,
      ),
    ),
  );
}

/// The thumbnail of a highlight row that opens its video, with a mouse in an
/// expanded window: on hover, a veil and an "open" badge over it. For the eye
/// and the mouse only: screen readers have the row, and the fiche.
class _ThumbnailLink extends StatefulWidget {
  const _ThumbnailLink({required this.youtubeId, required this.url, required this.label, required this.onTap});

  final String youtubeId;

  /// The address of the video, for the browser (web app).
  final String url;
  final String label;
  final VoidCallback onTap;

  @override
  State<_ThumbnailLink> createState() => _ThumbnailLinkState();
}

class _ThumbnailLinkState extends State<_ThumbnailLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: OutsideLink(
        url: widget.url,
        // unsaid: screen readers have the row, and the fiche
        label: '',
        video: true,
        onOpen: widget.onTap,
        builder: (context, open) => GestureDetector(
          onTap: open,
          child: Thumbnail(
            youtubeId: widget.youtubeId,
            width: ListMetrics.thumbnailWidth,
            label: widget.label,
            overlay: _hovered
                ? const ColoredBox(
                    color: Color(0x77000000),
                    child: Center(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: Color(0xAA000000), shape: BoxShape.circle),
                        child: SizedBox.square(
                          dimension: 36,
                          child: Icon(Icons.open_in_new, size: 18, color: Colors.white),
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    ),
  );
}

/// A play of the Ong Log or of a stream setlist: time (in the zone of the
/// device), track, artist · requester, video button, type icon.
class PlayRow extends ConsumerWidget {
  const PlayRow({
    super.key,
    required this.catalogue,
    required this.play,
    required this.tokens,
    required this.me,
    required this.onTap,
    required this.onVideo,
    this.tinted = false,
    this.selected,
    this.shape,
    this.start = 16,
  });

  final Catalogue catalogue;
  final Play play;
  final List<String> tokens;
  final String me;
  final VoidCallback onTap;

  /// Opens the linked video; the button is shown only when there is one.
  final void Function(Highlight highlight) onVideo;

  /// Highlighted (the play a stream sheet was opened from).
  final bool tinted;

  /// Whether the row is the selected one of the list of an expanded window
  /// (tinted the same way, in [InsetRoundedBorder.row]); null elsewhere.
  final bool? selected;

  /// The shape of the tint and the ink of a row of a fiche in the detail
  /// pane; null for a square row (a sheet).
  final ShapeBorder? shape;

  /// Space before the time.
  final double start;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final metrics = ListMetrics.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    final p = play;
    final artist = p.artist;
    final requester = catalogue.requester(p.requesterId);
    final video = catalogue.highlightOf(p);
    final subtitle = <InlineSpan>[
      ...markedSpans(artist, tokens, ong.mark, scheme.onSurface),
      if (artist.isNotEmpty && requester != null) const TextSpan(text: ' · '),
      if (requester != null) ...[
        personIcon(scheme.onSurfaceVariant),
        ...requesterSpans(context, requester.name, tokens, own: catalogue.isRequester(requester.id, me)),
      ],
      if (p.flag != PlayFlag.none) inlineWidget(Tag(p.flag.label)),
    ];
    final selected = this.selected;
    final shape = selected != null ? InsetRoundedBorder.row : this.shape;
    final body = SizedBox(
      height: metrics.playRow,
      child: Padding(
        padding: EdgeInsets.fromLTRB(start, 0, 14, 0),
        child: Row(
          children: [
            SizedBox(
              width: metrics.timeWidth,
              child: Text(
                formatPlayTime(p, ref.watch(wallTimeProvider)),
                maxLines: 1,
                style: TextStyle(fontSize: 12, color: ong.on3, fontFeatures: const [FontFeature.tabularFigures()]),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  MarkedText(
                    p.track,
                    tokens: tokens,
                    style: TextStyle(
                      fontSize: 15,
                      height: 20 / 15,
                      fontWeight: FontWeight.w500,
                      color: scheme.onSurface,
                    ),
                  ),
                  if (subtitle.isNotEmpty)
                    RequesterText(
                      TextSpan(children: subtitle),
                      maxLines: 1,
                      style: TextStyle(fontSize: 13, height: 18 / 13, color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
            if (video != null && video.youtubeId != null)
              VideoLink(
                highlight: video,
                label: VideoPill.label,
                onOpen: () => onVideo(video),
                builder: (context, open) => VideoPill(onPressed: open),
              )
            else
              const SizedBox(width: 6),
            const SizedBox(width: 6),
            PlayTypeIcon(p.type),
          ],
        ),
      ),
    );
    final tint = tinted || (selected ?? false);
    return Semantics(
      selected: selected,
      child: shape == null
          ? Material(
              color: tint ? selectedRowColor(context) : Colors.transparent,
              child: InkWell(onTap: onTap, child: body),
            )
          : _SelectableInk(selected: tint, shape: shape, onTap: onTap, child: body),
    );
  }
}

/// The header of a stream in the Ong Log: date, number of songs, duration.
///
/// In an expanded window ([selected] not null), it has the selection and
/// hover states of [InsetRoundedBorder.header], and its date in `onSurface`
/// when selected.
class StreamHeader extends StatelessWidget {
  const StreamHeader({super.key, required this.stream, required this.onTap, this.selected});

  final LiveStream stream;
  final VoidCallback onTap;

  /// Whether the header is the selected one of the list of an expanded window;
  /// null elsewhere.
  final bool? selected;

  @override
  Widget build(BuildContext context) {
    final metrics = ListMetrics.of(context);
    final scheme = Theme.of(context).colorScheme;
    final date = formatFullDate(stream.date);
    final size = formatStreamSize(stream);
    final selected = this.selected;
    final shape = selected == null ? null : InsetRoundedBorder.header;
    return Material(
      color: scheme.surface,
      child: Semantics(
        button: true,
        selected: selected,
        label: 'Stream of $date, $size',
        hint: 'Shows the setlist',
        // the ink well's own action goes with its semantics
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          customBorder: shape,
          hoverColor: shape == null ? null : hoveredRowColor(context),
          child: _Tint(
            shape: shape,
            selected: selected ?? false,
            child: SizedBox(
              height: metrics.streamHeader,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
                // the date first, whole if it fits (cut on a narrow screen with very large text, never over the
                // edge); the size of the stream gets what is left
                child: LayoutBuilder(
                  builder: (context, constraints) => Row(
                    crossAxisAlignment: CrossAxisAlignment.baseline,
                    textBaseline: TextBaseline.alphabetic,
                    children: [
                      ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: math.max(0, constraints.maxWidth - 8)),
                        child: Text(
                          date,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 20 / 13,
                            fontWeight: FontWeight.w500,
                            color: selected ?? false ? scheme.onSurface : scheme.primary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          size,
                          textAlign: TextAlign.end,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12, color: OngColors.of(context).on3),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tint of a selected header in [shape], behind [child]; [child] alone
/// without [shape].
class _Tint extends StatelessWidget {
  const _Tint({required this.shape, required this.selected, required this.child});

  final ShapeBorder? shape;
  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final shape = this.shape;
    if (shape == null) return child;
    return DecoratedBox(
      decoration: ShapeDecoration(color: selected ? selectedRowColor(context) : Colors.transparent, shape: shape),
      child: child,
    );
  }
}

/// A play in the history of a song: stream date, requester, video, type.
class HistoryRow extends StatelessWidget {
  const HistoryRow({
    super.key,
    required this.catalogue,
    required this.play,
    required this.me,
    required this.onTap,
    required this.onVideo,
    this.shape,
  });

  final Catalogue catalogue;
  final Play play;
  final String me;
  final VoidCallback onTap;
  final void Function(Highlight highlight) onVideo;

  /// The shape of the ink of a row of a fiche in the detail pane; null for a
  /// square row (a sheet).
  final ShapeBorder? shape;

  @override
  Widget build(BuildContext context) {
    final metrics = ListMetrics.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    final p = play;
    final requester = catalogue.requester(p.requesterId);
    final video = catalogue.highlightOf(p);
    return InkWell(
      onTap: onTap,
      customBorder: shape,
      hoverColor: shape == null ? null : hoveredRowColor(context),
      child: SizedBox(
        height: metrics.historyRow,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 14, 0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      formatFullDate(catalogue.streamOf(p).date),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 15, height: 20 / 15, color: scheme.onSurface),
                    ),
                    const SizedBox(height: 2),
                    RequesterText(
                      TextSpan(
                        children: [
                          if (requester == null)
                            const TextSpan(text: 'No requester')
                          else
                            ...requesterSpans(
                              context,
                              requester.name,
                              const [],
                              own: catalogue.isRequester(requester.id, me),
                            ),
                          if (p.flag != PlayFlag.none) TextSpan(text: ' · ${p.flag.label}'),
                        ],
                      ),
                      maxLines: 1,
                      style: TextStyle(fontSize: 12, height: 16 / 12, color: ong.on3),
                    ),
                  ],
                ),
              ),
              if (video != null && video.youtubeId != null)
                VideoLink(
                  highlight: video,
                  label: VideoPill.label,
                  onOpen: () => onVideo(video),
                  builder: (context, open) => VideoPill(onPressed: open),
                ),
              const SizedBox(width: 6),
              PlayTypeIcon(p.type),
            ],
          ),
        ),
      ),
    );
  }
}
