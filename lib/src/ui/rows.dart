/// The rows of the lists and sheets: a highlight, a play, a stream header and
/// a play in a song's history. Each one has the exact extent of
/// [ListMetrics] for its kind.
library;

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import 'format.dart';
import 'theme.dart';
import 'widgets.dart';

/// A row of the Highlights list: thumbnail, track, artist, genre · date ·
/// requester, and a ⋮ button.
class HighlightRow extends StatelessWidget {
  const HighlightRow({
    super.key,
    required this.catalogue,
    required this.highlight,
    required this.tokens,
    required this.me,
    required this.currentYear,
    required this.onTap,
    required this.onMore,
  });

  final Catalogue catalogue;
  final Highlight highlight;
  final List<String> tokens;

  /// Dates of this year are shown without it.
  final int currentYear;

  /// The folded Twitch name of the user, whose name is highlighted.
  final String me;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final metrics = ListMetrics.of(context);
    final scheme = Theme.of(context).colorScheme;
    final ong = OngColors.of(context);
    final h = highlight;
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
                Thumbnail(youtubeId: h.youtubeId, width: ListMetrics.thumbnailWidth, label: '#${h.seq}'),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 30),
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
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Details',
              onPressed: onMore,
              icon: Icon(Icons.more_vert, color: scheme.onSurfaceVariant),
            ),
          ),
        ],
      ),
    );
    return Semantics(
      button: true,
      hint: h.youtubeId == null ? 'Shows the details' : 'Opens the video',
      child: InkWell(
        onTap: onTap,
        child: h.youtubeId == null ? Opacity(opacity: 0.45, child: row) : row,
      ),
    );
  }
}

/// A play of the Ong Log or of a stream setlist: time, track, artist ·
/// requester, video button, type icon.
class PlayRow extends StatelessWidget {
  const PlayRow({
    super.key,
    required this.catalogue,
    required this.play,
    required this.tokens,
    required this.me,
    required this.onTap,
    required this.onVideo,
    this.tinted = false,
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

  @override
  Widget build(BuildContext context) {
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
    return Material(
      color: tinted ? scheme.primary.withValues(alpha: 0.16) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: metrics.playRow,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 14, 0),
            child: Row(
              children: [
                SizedBox(
                  width: metrics.timeWidth,
                  child: Text(
                    p.time.isEmpty ? '–' : p.time,
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
                  VideoPill(onPressed: () => onVideo(video))
                else
                  const SizedBox(width: 6),
                const SizedBox(width: 6),
                PlayTypeIcon(p.type),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The header of a stream in the Ong Log: date, number of songs, duration.
class StreamHeader extends StatelessWidget {
  const StreamHeader({super.key, required this.stream, required this.onTap});

  final LiveStream stream;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final metrics = ListMetrics.of(context);
    final scheme = Theme.of(context).colorScheme;
    final date = formatFullDate(stream.date);
    final size = formatStreamSize(stream);
    return Material(
      color: scheme.surface,
      child: Semantics(
        button: true,
        label: 'Stream of $date, $size',
        hint: 'Shows the setlist',
        // the ink well's own action goes with its semantics
        onTap: onTap,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
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
                          color: scheme.primary,
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
  });

  final Catalogue catalogue;
  final Play play;
  final String me;
  final VoidCallback onTap;
  final void Function(Highlight highlight) onVideo;

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
              if (video != null && video.youtubeId != null) VideoPill(onPressed: () => onVideo(video)),
              const SizedBox(width: 6),
              PlayTypeIcon(p.type),
            ],
          ),
        ),
      ),
    );
  }
}
