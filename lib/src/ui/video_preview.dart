/// The large preview of a highlight fiche, and in the web app the video
/// played in its place: YouTube's player, at the same place and size, as long
/// as the fiche is on screen; in the mini player over the app when the fiche
/// goes (see `mini_player.dart`).
library;

import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
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
  ref.onDispose(videos.dispose);
  return videos;
});

/// The video playing inside the app: the highlight, and its player.
typedef PlayingVideo = ({Highlight highlight, EmbeddedVideo video});

/// The videos played inside the app, through [embedder] (null: none, they
/// open on YouTube): the one [playing], the ones YouTube refused this session,
/// the previews on screen. Listeners hear when the video starts, shows, fails,
/// stops or changes places.
///
/// The video plays in place of the preview of its fiche while that preview is
/// on screen, and in the mini player over the app otherwise: another fiche,
/// the sheet closed, another tab, a page over the fiche. It stops only when
/// asked ([stop], the close button of the mini player, anything opening
/// YouTube), when another one starts, or when it fails.
class InPlaceVideos extends ChangeNotifier {
  InPlaceVideos(this.embedder);

  final VideoEmbedder? embedder;

  /// The videos YouTube's player refused, by YouTube id: their previews say so
  /// at once for the rest of the session.
  final Set<String> refused = {};

  PlayingVideo? _playing;

  /// The previews alive, and among them those on screen, the latest one last:
  /// the last one of the playing video shows it.
  final _previews = <_VideoPreviewState>{};
  final _shown = <_VideoPreviewState>{};

  /// The place whose last build showed the video's view: a preview, or
  /// [_miniPlayer].
  Object? _shownBy;

  /// The mini player, as a place of the video.
  static const Object _miniPlayer = #miniPlayer;

  bool _handOverScheduled = false;

  /// Whether a video can play in place of its preview.
  bool get available => embedder != null;

  /// The video playing, loading or shown, if any.
  PlayingVideo? get playing => _playing;

  /// Whether the video plays in the mini player: no preview of it on screen.
  bool get inMiniPlayer => _playing != null && _previewShowing() == null;

  /// The view of the video for the mini player to build, when it is there
  /// ([inMiniPlayer]); called by each of its builds.
  Widget? miniPlayerView() => _viewFor(_miniPlayer, here: inMiniPlayer);

  /// Plays the video of [highlight] in place of its preview (which must be
  /// on screen), stopping the one playing: never two sounds.
  void play(Highlight highlight) {
    final embedder = this.embedder;
    final id = highlight.youtubeId;
    if (embedder == null || id == null || refused.contains(id) || _playing?.highlight.youtubeId == id) return;
    _end();
    final video = embedder.play(id);
    _playing = (highlight: highlight, video: video);
    video.state.addListener(_stateChanged);
    notifyListeners();
  }

  /// Stops the video playing inside the app, if any; its preview comes back,
  /// the mini player goes.
  void stop() {
    if (_end()) notifyListeners();
  }

  /// Stops the video without telling: false when there was none.
  bool _end() {
    final playing = _playing;
    if (playing == null) return false;
    _playing = null;
    _shownBy = null;
    playing.video.state.removeListener(_stateChanged);
    playing.video.dispose();
    return true;
  }

  void _stateChanged() {
    final playing = _playing;
    if (playing == null) return;
    final state = playing.video.state.value;
    if (state.isFailure) {
      if (state == EmbeddedVideoState.refused) refused.add(playing.highlight.youtubeId!);
      // the preview that showed it says so; the mini player just goes
      _previewShowing()?._failedHere();
      _end();
    }
    notifyListeners();
  }

  /// Plays [highlight] in place of its preview in the detail pane of [tab]
  /// (Enter in an expanded window); false when there is none to play it in,
  /// or it cannot play there (refused before, or no in-place player).
  bool playInPane(AppTab tab, Highlight highlight) {
    final id = highlight.youtubeId;
    if (!available || id == null || refused.contains(id)) return false;
    for (final preview in _previews) {
      if (preview.mounted && preview.widget.highlight.youtubeId == id && preview.paneTab == tab) {
        play(preview.widget.highlight);
        return true;
      }
    }
    return false;
  }

  /// The preview that shows the playing video: the last one of it put on
  /// screen.
  _VideoPreviewState? _previewShowing() {
    final id = _playing?.highlight.youtubeId;
    if (id == null) return null;
    _VideoPreviewState? last;
    for (final p in _shown) {
      if (p._id == id) last = p;
    }
    return last;
  }

  /// The view of the playing video for [place] to build, if it is the place
  /// of the video ([here]) and no other place shows it: null otherwise.
  ///
  /// A place takes the view only once the one before has let it go (in its
  /// next build, a frame later): the view, an element over the canvas of the
  /// web app, must not be drawn at two places in one frame. The video plays
  /// on meanwhile: the player is the video's, not the view's (see
  /// [EmbeddedVideo.view]).
  Widget? _viewFor(Object place, {required bool here}) {
    final playing = _playing;
    if (playing == null) return null;
    if (here && (_shownBy == null || identical(_shownBy, place))) {
      _shownBy = place;
      return playing.video.view;
    }
    if (here || identical(_shownBy, place)) {
      // waiting for the other place to let it go, or letting it go: the places build again after this frame
      if (identical(_shownBy, place)) _shownBy = null;
      _handOver();
    }
    return null;
  }

  /// [place] is gone: the place of the video now takes it.
  void _gone(Object place) {
    if (!identical(_shownBy, place)) return;
    _shownBy = null;
    _handOver();
  }

  /// Builds the places again after this frame: called during builds, which
  /// cannot rebuild other widgets.
  void _handOver() {
    if (_handOverScheduled) return;
    _handOverScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _handOverScheduled = false;
      if (hasListeners) notifyListeners();
    });
  }

  @override
  void dispose() {
    _end();
    super.dispose();
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
/// The video goes to the mini player when the preview leaves the screen:
/// another fiche, the sheet closing, another tab; it comes back in place when
/// the preview does.
class VideoPreview extends ConsumerStatefulWidget {
  const VideoPreview({super.key, required this.highlight});

  final Highlight highlight;

  @override
  ConsumerState<VideoPreview> createState() => _VideoPreviewState();
}

class _VideoPreviewState extends ConsumerState<VideoPreview> {
  late final InPlaceVideos _videos = ref.read(inPlaceVideosProvider);

  /// The video could not be had (not refused): until the preview goes.
  bool _failed = false;

  /// The failure happened here and now: screen readers are told.
  bool _failedNow = false;

  /// The sheet of the preview is closing: the video leaves at once, not at
  /// the end of the slide.
  bool _leaving = false;

  Animation<double>? _routeAnimation;

  String get _id => widget.highlight.youtubeId!;

  /// The list tab whose detail pane shows the preview, or null in a sheet.
  AppTab? get paneTab => DetailPaneScope.maybeOf(context)?.tab;

  @override
  void initState() {
    super.initState();
    _videos._previews.add(this);
    _videos.addListener(_changed);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final animation = ModalRoute.of(context)?.animation;
    if (!identical(animation, _routeAnimation)) {
      _routeAnimation?.removeStatusListener(_routeChanged);
      _routeAnimation = animation?..addStatusListener(_routeChanged);
    }
  }

  void _routeChanged(AnimationStatus status) {
    final leaving = status == AnimationStatus.reverse || status == AnimationStatus.dismissed;
    if (leaving != _leaving && mounted) setState(() => _leaving = leaving);
  }

  /// The video started, showed, failed or stopped.
  void _changed() {
    if (mounted) setState(() {});
  }

  /// The video failed while this preview showed it.
  void _failedHere() {
    if (mounted) setState(() => _failed = _failedNow = true);
  }

  @override
  void didUpdateWidget(VideoPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    // another video for the same fiche (its link changed in a refresh): the old one goes to the mini player
    if (oldWidget.highlight.youtubeId != widget.highlight.youtubeId) _failed = _failedNow = false;
  }

  @override
  void deactivate() {
    // out of the tree (another fiche, the pane gone), maybe for good: the video goes to the mini player
    _videos
      .._shown.remove(this)
      .._gone(this);
    super.deactivate();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_routeChanged);
    _videos
      .._previews.remove(this)
      ..removeListener(_changed);
    super.dispose();
  }

  /// The tap: the video in place, or on YouTube.
  void _tap() {
    if (!_videos.available) {
      openVideo(context, ref, widget.highlight);
    } else {
      setState(() => _failed = _failedNow = false);
      _videos.play(widget.highlight);
    }
  }

  @override
  Widget build(BuildContext context) {
    final h = widget.highlight;
    final inPlace = _videos.available;
    // on screen: its tab, its route neither closing nor under a page
    if (TickerMode.valuesOf(context).enabled && !_leaving) {
      // (one shown before keeps its rank)
      _videos._shown.add(this);
    } else {
      _videos._shown.remove(this);
    }
    final playing = _videos._playing;
    final here = playing != null && identical(_videos._previewShowing(), this);
    final view = _videos._viewFor(this, here: here);
    final video = here ? playing.video : null;
    final showing = video != null && video.state.value == EmbeddedVideoState.playing;
    final loading = video != null && !showing;
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
                else if (!showing)
                  Center(child: _PlayBadge(loading: loading)),
                // last: YouTube's player over the canvas (transparent while it loads, the badge seen through it);
                // keyed, so that it keeps its element when the badge goes: a new one would load the player again
                ?view,
              ],
            ),
          ),
        );
        // The same widgets in every state, only their settings change: the player must keep its element.
        final tappable = !failed && !showing;
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
                label: watchOnYouTubeText,
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
                  label: const Text(watchOnYouTubeText),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
