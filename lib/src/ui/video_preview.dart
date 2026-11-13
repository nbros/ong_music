/// The large preview of a highlight fiche, and in the web app the video
/// played in its place: YouTube's player, at the same place and size, as long
/// as the fiche is on screen.
library;

import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/model.dart';
import '../web/embedded_video.dart';
import '../web/web_platform.dart';
import 'actions.dart';
import 'instant_feedback.dart';
import 'outside_link.dart';
import 'sheets.dart';
import 'theme.dart';
import 'view_state.dart';
import 'widgets.dart';

/// Where videos play inside the app; null where they open on YouTube (the
/// native apps). Overridden in tests.
final videoEmbedderProvider = Provider<VideoEmbedder?>((ref) => videoEmbedder());

/// The videos played inside the app: at most one at a time.
final inPlaceVideosProvider = Provider<InPlaceVideos>((ref) {
  final videos = InPlaceVideos(ref.watch(videoEmbedderProvider));
  // both list tabs stay alive out of sight: a video of the tab left would go on playing unseen
  ref.listen(selectedTabProvider, (_, _) => videos.stop());
  ref.onDispose(videos.stop);
  return videos;
});

/// The videos played inside the app, through [embedder] (null: none, they
/// open on YouTube): the one playing, the ones YouTube refused this session,
/// the previews on screen.
class InPlaceVideos {
  InPlaceVideos(this.embedder);

  final VideoEmbedder? embedder;

  /// The videos YouTube's player refused, by YouTube id: their previews say so
  /// at once for the rest of the session.
  final Set<String> refused = {};

  final _previews = <_VideoPreviewState>{};
  _VideoPreviewState? _playing;

  /// Whether a video can play in place of its preview.
  bool get available => embedder != null;

  /// Stops the video playing inside the app, if any; its preview comes back.
  void stop() => _playing?._stop();

  /// Plays [highlight] in place of its preview in the detail pane of [tab]
  /// (Enter in an expanded window); false when there is none to play it in,
  /// or it cannot play there (refused before, or no in-place player).
  bool playInPane(AppTab tab, Highlight highlight) {
    final id = highlight.youtubeId;
    if (!available || id == null || refused.contains(id)) return false;
    for (final preview in _previews) {
      if (preview.mounted && preview.widget.highlight.youtubeId == id && preview.paneTab == tab) {
        preview._play();
        return true;
      }
    }
    return false;
  }
}

/// The large preview of [highlight] (which must have a video), as wide as
/// it can, at most two fifths of the window high.
///
/// Native apps: a tap opens the video on YouTube; screen readers skip it, the
/// "Watch on YouTube" button under it doing the same. Web app: a tap plays
/// the video right there ([InPlaceVideos]); when YouTube refuses it, the
/// preview comes back darkened, with "Watch on YouTube" over it.
///
/// The video stops and goes away with the preview: another fiche, the sheet
/// closed, another tab, or anything opening a video on YouTube ([openVideo]).
class VideoPreview extends ConsumerStatefulWidget {
  const VideoPreview({super.key, required this.highlight});

  final Highlight highlight;

  @override
  ConsumerState<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends ConsumerState<VideoPreview> {
  late final InPlaceVideos _videos = ref.read(inPlaceVideosProvider);
  EmbeddedVideo? _video;

  /// The video could not be had (not refused): until the preview goes.
  bool _failed = false;

  /// The failure happened here and now: screen readers are told.
  bool _failedNow = false;

  Animation<double>? _routeAnimation;

  String get _id => widget.highlight.youtubeId!;

  /// The list tab whose detail pane shows the preview, or null in a sheet.
  AppTab? get paneTab => DetailPaneScope.maybeOf(context)?.tab;

  @override
  void initState() {
    super.initState();
    _videos._previews.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // a sheet closing (its route going away) stops the video at once, not at the end of the slide
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_routeChanged);
      _routeAnimation = animation?..addStatusListener(_routeChanged);
    }
  }

  void _routeChanged(AnimationStatus status) {
    if (status == AnimationStatus.reverse || status == AnimationStatus.dismissed) _stop();
  }

  @override
  void didUpdateWidget(VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // another video for the same fiche (its link changed in a refresh): the old one stops
    if (oldWidget.highlight.youtubeId != widget.highlight.youtubeId) {
      _stop(rebuild: false);
      _failed = _failedNow = false;
    }
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeChanged);
    _stop(rebuild: false);
    _videos._previews.remove(this);
    super.dispose();
  }

  /// The tap: the video in place, or on YouTube.
  void _tap() {
    if (!_videos.available) {
      openVideo(context, ref, widget.highlight);
    } else {
      _play();
    }
  }

  void _play() {
    final embedder = _videos.embedder;
    if (embedder == null || _video != null || _videos.refused.contains(_id)) return;
    // never two sounds
    _videos.stop();
    final video = embedder.play(_id);
    video.state.addListener(_stateChanged);
    _videos._playing = this;
    setState(() {
      _video = video;
      _failed = _failedNow = false;
    });
  }

  void _stateChanged() {
    final video = _video;
    if (video == null) return;
    final state = video.state.value;
    if (state.isFailure) {
      if (state == EmbeddedVideoState.refused) _videos.refused.add(_id);
      _stop(rebuild: false);
      if (mounted) {
        setState(() => _failed = _failedNow = true);
      }
    } else if (mounted) {
      setState(() {});
    }
  }

  /// Stops the video and removes the player; the preview comes back.
  void _stop({bool rebuild = true}) {
    final video = _video;
    if (video == null) return;
    _video = null;
    if (identical(_videos._playing, this)) _videos._playing = null;
    video.state.removeListener(_stateChanged);
    video.dispose();
    if (rebuild && mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.highlight;
    final inPlace = _videos.available;
    final video = _video;
    final playing = video != null && video.state.value == EmbeddedVideoState.playing;
    final loading = video != null && !playing;
    final failed = inPlace && video == null && (_failed || _videos.refused.contains(_id));
    return LayoutBuilder(
      builder: (context, constraints) {
        // As wide as the fiche, unless that makes it higher than two fifths of the window: on a phone held sideways
        // it would fill the sheet, the title and the buttons out of sight.
        final width = math.min(constraints.maxWidth, MediaQuery.sizeOf(context).height * 0.4 * 16 / 9);
        // one box for the three states: nothing moves when the video comes or goes
        final preview = SizedBox(
          width: width,
          height: width * 9 / 16,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              alignment: Alignment.center,
              children: [
                Thumbnail(youtubeId: h.youtubeId, width: width, big: true, radius: 16),
                if (failed)
                  _Refused(highlight: h, announce: _failedNow)
                else if (!playing)
                  Center(child: _PlayBadge(loading: loading)),
                // last: YouTube's player over the canvas (transparent while it loads, the badge seen through it);
                // keyed, so that it keeps its element when the badge goes: a new one would load the player again
                if (video != null) KeyedSubtree(key: ObjectKey(video), child: video.view),
              ],
            ),
          ),
        );
        // The same widgets in every state, only their settings change: the player must keep its element.
        final tappable = !failed && !playing;
        return Center(
          child: Semantics(
            // the web app: a button of its own, the one under it opening YouTube; the player then speaks for itself
            button: inPlace && tappable && !loading,
            label: !inPlace || !tappable ? null : (loading ? 'Loading the video' : 'Play the video here'),
            onTap: inPlace && tappable && !loading ? _tap : null,
            child: ExcludeSemantics(
              // native apps: for the eye and the finger only, screen readers get the "Watch on YouTube" button
              // below, which does the same
              excluding: !inPlace || tappable,
              child: GestureDetector(
                onTap: tappable ? _tap : null,
                child: MouseRegion(
                  cursor: tappable && !loading ? SystemMouseCursors.click : MouseCursor.defer,
                  child: preview,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The round play button over the preview, a spinner in it while the player
/// loads.
class _PlayBadge extends StatelessWidget {
  const _PlayBadge({required this.loading});

  final bool loading;

  @override
  Widget build(BuildContext context) => Container(
    width: 56,
    height: 56,
    alignment: Alignment.center,
    decoration: const BoxDecoration(color: Color(0xAA000000), shape: BoxShape.circle),
    child: loading
        ? const SizedBox.square(dimension: 28, child: CircularProgressIndicator(strokeWidth: 3, color: Colors.white))
        : const Icon(Icons.play_arrow, size: 32, color: Colors.white),
  );
}

/// What a refused video shows over its darkened preview.
class _Refused extends ConsumerWidget {
  const _Refused({required this.highlight, required this.announce});

  final Highlight highlight;

  /// Whether screen readers read the text as it appears (the video was just
  /// refused, not known to be before).
  final bool announce;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ong = OngColors.of(context);
    return ColoredBox(
      color: const Color(0xB3000000),
      child: Padding(
        padding: const EdgeInsets.all(16),
        // whatever the text size, inside the preview
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            spacing: 14,
            children: [
              Semantics(
                liveRegion: announce,
                child: const Text(
                  'This video only plays on YouTube.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 14, height: 20 / 14, color: Colors.white),
                ),
              ),
              // no link of the page over the player: the player is gone when this shows
              VideoLink(
                highlight: highlight,
                label: 'Watch on YouTube',
                builder: (context, open) => FilledButton.icon(
                  onPressed: open,
                  style: platformButtonStyle(
                    context,
                    FilledButton.styleFrom(
                      backgroundColor: ong.brand,
                      foregroundColor: ong.onBrand,
                      minimumSize: const Size(0, 40),
                      textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                  ),
                  icon: const Icon(Icons.open_in_new, size: 18),
                  label: const Text('Watch on YouTube'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
