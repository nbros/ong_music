/// YouTube's embedded player in a frame of the privacy-enhanced host
/// (`www.youtube-nocookie.com`), followed through the messages the frame
/// sends to the page. Web build only (see `web_platform.dart`).
///
/// No script of YouTube runs in the page: the IFrame Player API, a script of
/// `www.youtube.com`, would carry the visitor's YouTube cookies there. The
/// page talks to the frame the way that script does (`postMessage`, JSON):
/// it announces itself ("listening") until the frame answers, subscribes to
/// the player's events, and reads `onReady`, `onStateChange`, `infoDelivery`
/// and `onError`. That protocol is not documented: messages are only taken
/// from the frame itself, and a frame that says nothing is shown as it is
/// (see [YouTubeVideo]), once its host is known to answer.
///
/// Nothing is asked of YouTube before the first video: until then the page
/// loads only the thumbnails (`i.ytimg.com`).
library;

import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:web/web.dart' as web;

import '../logger.dart';
import 'embedded_video.dart';

/// The host of the player's frame: no cookie until the visitor plays a video.
const String youTubePlayerHost = 'https://www.youtube-nocookie.com';

/// What the frame may do: play with sound after the visitor's tap, protected
/// media, picture in picture, full screen, copy its link, share.
const String youTubeFrameAllow =
    'accelerometer; autoplay; clipboard-write; encrypted-media; fullscreen; gyroscope; picture-in-picture; '
    'web-share';

/// How often the page announces itself to a frame that has not answered yet
/// (as the IFrame Player API does).
const Duration youTubeAnnounceInterval = Duration(milliseconds: 250);

/// [VideoEmbedder] of the browser.
final class YouTubeEmbedder implements VideoEmbedder {
  /// [host], [timeout], [revealDelay] and [silentDelay]: other values for the
  /// tests only.
  YouTubeEmbedder({
    this.host = youTubePlayerHost,
    this.timeout = embeddedVideoTimeout,
    this.revealDelay = embeddedVideoRevealDelay,
    this.silentDelay = embeddedVideoSilentDelay,
  });

  /// Where the frame comes from, and the only origin whose messages count.
  final String host;
  final Duration timeout;
  final Duration revealDelay;
  final Duration silentDelay;

  /// Tells the frames of the page apart in their messages (`id`).
  int _lastId = 0;

  @override
  YouTubeVideo play(String youtubeId) => YouTubeVideo._(this, youtubeId, ++_lastId);
}

/// A video of [YouTubeEmbedder]: a `<div>` in a platform view, holding the
/// frame of YouTube's player, transparent until the player shows the video.
///
/// What depends on the player's messages, and what happens without them:
/// - the frame stays hidden (the preview and its spinner seen) until the
///   player shows the video (`onStateChange`, `infoDelivery`), or a moment
///   after `onReady` ([YouTubeEmbedder.revealDelay]); without messages, until a
///   moment after the frame loaded ([YouTubeEmbedder.silentDelay]);
/// - a refused video ([EmbeddedVideoState.refused], which the app remembers)
///   is only known from `onError`; without messages, YouTube's own "Video
///   unavailable" screen is seen in the frame instead, and nothing is
///   remembered.
///
/// [EmbeddedVideoState.failed] does not depend on them: offline at the tap,
/// neither a load of the frame nor a message from it before
/// [YouTubeEmbedder.timeout], or a frame that loaded and says nothing while
/// its host cannot be reached (a network that blocks YouTube, an unknown
/// name: the browser then "loads" its own error page in the frame, which must
/// not be shown as the player).
final class YouTubeVideo implements EmbeddedVideo {
  YouTubeVideo._(this._embedder, this._youtubeId, this._id) {
    host.style
      ..width = '100%'
      ..height = '100%'
      // the preview under it stays seen while the player loads; neither YouTube's loading screen nor its "video
      // unavailable" screen shows before the app knows; a second tap meanwhile must not pause the hidden player
      ..opacity = '0'
      ..pointerEvents = 'none';
    if (!web.window.navigator.onLine) {
      // nothing to wait for (in a timer: the state changes once its listener is there)
      _timeout = Timer(Duration.zero, () => _fail(EmbeddedVideoState.failed, 'offline'));
      return;
    }
    final origin = web.window.location.origin;
    _frame
      ..src =
          '${_embedder.host}/embed/${Uri.encodeComponent(_youtubeId)}'
          '?autoplay=1&rel=0&playsinline=1&enablejsapi=1&origin=${Uri.encodeComponent(origin)}&widgetid=$_id'
      ..title = 'YouTube video player'
      ..allow = youTubeFrameAllow
      ..allowFullscreen = true
      // the site's address, which the player requires (error 153 without it), and nothing more of it
      ..referrerPolicy = 'strict-origin-when-cross-origin';
    _frame.style
      ..width = '100%'
      ..height = '100%'
      ..border = '0'
      ..display = 'block';
    _frame.addEventListener('load', _onLoad);
    web.window.addEventListener('message', _onMessage);
    _listening = true;
    host.append(_frame);
    _announcing = Timer.periodic(youTubeAnnounceInterval, (_) => _announce());
    _timeout = Timer(_embedder.timeout, _timedOut);
  }

  final YouTubeEmbedder _embedder;
  final String _youtubeId;
  final int _id;

  /// What the platform view shows: the frame, in a box of its size.
  @visibleForTesting
  final host = web.HTMLDivElement();

  final _frame = web.HTMLIFrameElement();
  final _state = ValueNotifier(EmbeddedVideoState.loading);
  late Timer _timeout;
  Timer? _announcing;
  Timer? _silent;
  Timer? _reveal;
  bool _loaded = false;
  bool _heard = false;
  bool _disposed = false;

  /// Whether the host of the frame answered a request of the page ([_probe]).
  bool _reachable = false;
  bool _probed = false;

  /// Whether the frame has been loaded and silent for [YouTubeEmbedder.silentDelay].
  bool _silentElapsed = false;

  /// Whether the page was out of sight when the timeout last ran out.
  bool _hiddenAtTimeout = false;

  /// Whether its listeners are on the frame and the window.
  bool _listening = false;

  late final JSFunction _onLoad = ((web.Event _) => _frameLoaded()).toJS;
  late final JSFunction _onMessage = ((web.MessageEvent event) => _received(event)).toJS;

  @override
  late final Widget view = HtmlElementView.fromTagName(
    tagName: 'div',
    onElementCreated: (element) => (element as web.HTMLElement).append(host),
  );

  @override
  ValueListenable<EmbeddedVideoState> get state => _state;

  void _send(Map<String, Object?> message) {
    final window = _frame.contentWindow;
    if (window == null) return;
    try {
      window.postMessage(jsonEncode({...message, 'id': _id, 'channel': 'widget'}).toJS, _embedder.host.toJS);
    } catch (e) {
      logger.w('Cannot talk to the YouTube player', error: e);
    }
  }

  /// "The page listens": repeated until the frame answers (its first message).
  void _announce() => _send({'event': 'listening'});

  void _frameLoaded() {
    if (_disposed) return;
    _loaded = true;
    if (_heard) return;
    // a document in the frame: announce from now, as long as it says nothing
    _announcing?.cancel();
    _announce();
    _announcing = Timer.periodic(youTubeAnnounceInterval, (_) => _announce());
    _probe();
    _silent ??= Timer(_embedder.silentDelay, () {
      _silentElapsed = true;
      if (_reachable) _showSilent();
    });
  }

  /// Asks the host of the frame for nothing in particular, to know whether it
  /// can be reached at all. The frame cannot tell: when its host is blocked or
  /// unknown, the browser still loads a page in it, its own error page. No
  /// cookie goes with the request, and nothing of the answer is read.
  void _probe() {
    if (_probed) return;
    _probed = true;
    final init = web.RequestInit(mode: 'no-cors', credentials: 'omit', cache: 'no-store');
    web.window
        .fetch('${_embedder.host}/generate_204'.toJS, init)
        .toDart
        .then<void>(
          (_) {
            if (_disposed) return;
            _reachable = true;
            if (_silentElapsed) _showSilent();
          },
          onError: (Object _) {
            // nothing of the host can be had: what the frame shows is not the player
            if (!_heard) _fail(EmbeddedVideoState.failed, 'the host of the player cannot be reached');
          },
        );
  }

  /// A frame of a host that answers, loaded for a while, which says nothing.
  void _showSilent() {
    if (_disposed || _heard || _state.value != EmbeddedVideoState.loading) return;
    logger.i('The YouTube player of $_youtubeId says nothing: shown as it is');
    _show();
  }

  void _received(web.MessageEvent event) {
    // the frame of this video, and nothing else
    final window = _frame.contentWindow;
    final source = event.source;
    if (_disposed || event.origin != _embedder.host || window == null || source == null) return;
    if (!source.strictEquals(window).toDart) return;
    final data = event.data;
    if (data == null || !data.isA<JSString>()) return;
    final Object? message;
    try {
      message = jsonDecode((data as JSString).toDart);
    } catch (_) {
      return;
    }
    if (message is! Map<String, Object?>) return;
    if (!_heard) {
      _heard = true;
      _announcing?.cancel();
      _silent?.cancel();
      // what the IFrame Player API subscribes to, for the events the app follows
      for (final name in ['onReady', 'onStateChange', 'onError']) {
        _send({
          'event': 'command',
          'func': 'addEventListener',
          'args': [name],
        });
      }
    }
    final info = message['info'];
    switch (message['event']) {
      case 'readyToListen':
        _announce();
      case 'onReady':
        _ready();
      case 'onStateChange':
        _changed(info);
      case 'initialDelivery' || 'infoDelivery':
        if (info is Map<String, Object?>) {
          _changed(info['playerState']);
          // the title of the video, for screen readers (as the API does)
          final video = info['videoData'];
          final title = video is Map<String, Object?> ? video['title'] : null;
          if (title is String && title.isNotEmpty) _frame.title = title;
        }
      case 'onError':
        // gone, private or allowed on YouTube only: the same next time; any other error may not happen again
        _fail(
          youTubeLastingErrors.contains(info) ? EmbeddedVideoState.refused : EmbeddedVideoState.failed,
          'player error $info',
        );
    }
  }

  void _ready() {
    if (_disposed || _state.value != EmbeddedVideoState.loading) return;
    _reveal ??= Timer(_embedder.revealDelay, _show);
  }

  void _changed(Object? state) {
    if (state is int && youTubeShownStates.contains(state)) _show();
  }

  void _timedOut() {
    final nothing = !_loaded && !_heard;
    if (nothing && (web.document.hidden || _hiddenAtTimeout)) {
      // A page out of sight draws nothing: the frame is not in it yet. It gets its whole time once the page is
      // seen (one more round after the one during which it came back).
      _hiddenAtTimeout = web.document.hidden;
      _timeout = Timer(_embedder.timeout, _timedOut);
    } else if (_heard || (_loaded && _reachable)) {
      // the frame is there and may play: YouTube's own screens do the rest
      _show();
    } else {
      _fail(
        EmbeddedVideoState.failed,
        nothing ? 'the frame did not load in time' : 'the host of the player did not answer in time',
      );
    }
  }

  void _show() {
    if (_disposed || _state.value != EmbeddedVideoState.loading) return;
    _timeout.cancel();
    _silent?.cancel();
    _reveal?.cancel();
    host.style
      ..opacity = '1'
      ..pointerEvents = 'auto';
    _state.value = EmbeddedVideoState.playing;
  }

  void _fail(EmbeddedVideoState state, String reason) {
    if (_disposed || _state.value.isFailure) return;
    logger.i('Video $_youtubeId not played in the app: $reason');
    // no sound from a player the app no longer shows
    _remove();
    _state.value = state;
  }

  /// Removes the frame (which stops the video at once), its listeners and timers.
  void _remove() {
    _timeout.cancel();
    _announcing?.cancel();
    _silent?.cancel();
    _reveal?.cancel();
    if (_listening) {
      _listening = false;
      _frame.removeEventListener('load', _onLoad);
      web.window.removeEventListener('message', _onMessage);
    }
    _frame.remove();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _remove();
    host.remove();
    // (the state is not disposed: its listener may be the one disposing the video, while it is being notified)
  }
}
