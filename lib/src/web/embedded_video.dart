/// A YouTube video played inside the page, in place of its preview: what the
/// app needs from it. Pure logic, so that it can be tested anywhere; the
/// browser side is `videoEmbedder()` (web platform).
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Where videos can be played inside the app: the web app only.
abstract interface class VideoEmbedder {
  /// A player of the YouTube video [youtubeId], which starts loading at once
  /// and plays the video as soon as it can. Nothing of YouTube is loaded
  /// before the first call.
  EmbeddedVideo play(String youtubeId);
}

/// One video playing in the page. It plays until [dispose].
abstract interface class EmbeddedVideo {
  /// What the page shows of it: YouTube's player, at the size it is given.
  /// Built in one place only, for as long as the video is shown: on the web,
  /// an element over the app's canvas, which a second copy would load again.
  Widget get view;

  /// Where it is: [EmbeddedVideoState.loading] first, then playing, or one of
  /// the two failures. A failure is final.
  ValueListenable<EmbeddedVideoState> get state;

  /// Stops the video and removes the player.
  void dispose();
}

/// What an [EmbeddedVideo] does.
enum EmbeddedVideoState {
  /// The player is on its way: the preview stays on screen, and [EmbeddedVideo.view]
  /// shows nothing.
  loading,

  /// The player is on screen, playing or about to (it may wait for a tap of
  /// its own where the browser refuses to start a video by itself), or showing
  /// whatever it shows when it tells the app nothing.
  playing,

  /// YouTube's player refused the video ([youTubeLastingErrors]): its owner
  /// allows it on YouTube only (about one video in twelve), or it is gone or
  /// private. It will be the same next time.
  refused,

  /// The player could not be had, or stopped on another error: offline, its
  /// host out of reach, its frame neither loaded nor said anything in time
  /// ([embeddedVideoTimeout]), a playback error. It may work another time.
  failed;

  /// Whether the video cannot be played in the page: the preview comes back
  /// with "Watch on YouTube" over it.
  bool get isFailure => this == refused || this == failed;
}

/// How long YouTube's player has to show a sign of life (its frame loaded, or
/// a message from it), from the tap, before the app gives up and offers
/// YouTube instead.
const Duration embeddedVideoTimeout = Duration(seconds: 15);

/// How long after its frame loaded a player that sends no message at all
/// stays hidden: then it is shown as it is (its messages are not a documented
/// contract, and may change).
const Duration embeddedVideoSilentDelay = Duration(seconds: 3);

/// How long after getting ready the player stays hidden when it says nothing
/// more: the browser did not start the video by itself (iPhone), and YouTube's
/// own play button must be seen. A refused video tells so well before.
const Duration embeddedVideoRevealDelay = Duration(milliseconds: 1500);

/// The errors of YouTube's player (`onError`) that will be the same next
/// time: the video is gone or private (100), or its owner allows it on
/// YouTube only (101, and 150 which means the same). Any other one (2, 5,
/// 153…) may not happen again.
const Set<int> youTubeLastingErrors = {100, 101, 150};

/// The states of YouTube's player (`onStateChange`) that mean it shows the
/// video: ended (0), playing (1), paused (2), buffering (3), cued (5). Not
/// "unstarted" (-1), which a refused video also goes through.
const Set<int> youTubeShownStates = {0, 1, 2, 3, 5};
