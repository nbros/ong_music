// Browser only: flutter test --platform chrome test/youtube_web_test.dart
//
// YouTube's player in a frame, followed through its messages. Nothing reaches the network: the frames come from
// the test server (a page that does not exist), and the player's messages are made up by the test.
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/web/embedded_video.dart';
import 'package:ong_music/src/web/web_platform.dart';
import 'package:ong_music/src/web/youtube_web.dart';
import 'package:web/web.dart' as web;

/// The origin of the test page: frames from it load without network.
final String origin = web.window.location.origin;

void run(String code) => globalContext.callMethod('eval'.toJS, code.toJS);

/// Gives [object] an own property [name] of [value] until the end of the test.
void shadow(JSObject object, String name, JSAny? value) {
  final descriptor = JSObject()
    ..['value'] = value
    ..['configurable'] = true.toJS;
  (globalContext['Object']! as JSObject).callMethod('defineProperty'.toJS, object, name.toJS, descriptor);
  addTearDown(() => object.delete(name.toJS));
}

/// The `message` listeners of the window, added and not removed.
int messageListeners() => (globalContext['__messageListeners']! as JSNumber).toDartInt;

/// The frame of [video].
web.HTMLIFrameElement? frameOf(YouTubeVideo video) => video.host.querySelector('iframe') as web.HTMLIFrameElement?;

Future<void> settle([Duration time = const Duration(milliseconds: 50)]) => Future<void>.delayed(time);

/// Puts [video] in the page, as its platform view does, and waits for its frame to load.
Future<web.HTMLIFrameElement> attach(YouTubeVideo video) async {
  web.document.body!.append(video.host);
  final frame = frameOf(video)!;
  for (var i = 0; i < 100; i++) {
    final document = frame.contentDocument;
    if (document != null && document.URL.contains('/embed/') && document.readyState == 'complete') break;
    await settle(const Duration(milliseconds: 20));
  }
  // its load event, and the announcement sent then
  await settle(const Duration(milliseconds: 20));
  return frame;
}

/// What the page sends to [frame] from now on, decoded, with the target origin it gives.
List<Map<String, Object?>> spy(web.HTMLIFrameElement frame) {
  final sent = <Map<String, Object?>>[];
  shadow(
    frame.contentWindow!,
    'postMessage',
    ((JSString message, JSString target) {
      sent.add({...jsonDecode(message.toDart) as Map<String, Object?>, 'to': target.toDart});
    }).toJS,
  );
  return sent;
}

/// A message of the player to the page: [data] (JSON, unless [raw]) from [source] (default: the window of
/// [frame]), said to come from [from] (default: the frames' host).
void say(web.HTMLIFrameElement frame, Object? data, {String? from, JSAny? source, bool raw = false}) {
  final init = JSObject()
    ..['data'] = raw ? data.jsify() : jsonEncode(data).toJS
    ..['origin'] = (from ?? origin).toJS
    ..['source'] = source ?? frame.contentWindow;
  final event = (globalContext['MessageEvent']! as JSFunction).callAsConstructor<JSObject>('message'.toJS, init);
  globalContext.callMethod('dispatchEvent'.toJS, event);
}

/// An embedder whose frames come from the test server.
YouTubeEmbedder local({
  Duration timeout = const Duration(seconds: 10),
  Duration revealDelay = const Duration(seconds: 10),
  Duration silentDelay = const Duration(seconds: 10),
}) => YouTubeEmbedder(host: origin, timeout: timeout, revealDelay: revealDelay, silentDelay: silentDelay);

void main() {
  setUp(() {
    // counts the message listeners of the window
    run(
      'window.__messageListeners = 0;'
      'window.addEventListener = function (t, f, o) { if (t === "message") window.__messageListeners++;'
      '  return EventTarget.prototype.addEventListener.call(this, t, f, o); };'
      'window.removeEventListener = function (t, f, o) { if (t === "message") window.__messageListeners--;'
      '  return EventTarget.prototype.removeEventListener.call(this, t, f, o); };',
    );
  });

  tearDown(() {
    for (final name in ['addEventListener', 'removeEventListener', '__messageListeners']) {
      globalContext.delete(name.toJS);
    }
  });

  test('the web app plays videos in place, and asks nothing of YouTube before the first one', () {
    expect(videoEmbedder(), isA<YouTubeEmbedder>());
    expect(web.document.querySelectorAll('iframe').length, 0);
    expect(web.document.querySelectorAll('script[src*="youtube.com"]').length, 0);
  });

  test('the frame: privacy-enhanced host, plays at once, with what it needs; no script in the page', () {
    // not put in the page: nothing loads
    final video = YouTubeEmbedder().play('aaaaaaaaaaa');
    final frame = frameOf(video)!;
    expect(
      frame.src,
      'https://www.youtube-nocookie.com/embed/aaaaaaaaaaa?autoplay=1&rel=0&playsinline=1&enablejsapi=1'
      '&origin=${Uri.encodeComponent(origin)}&widgetid=1',
    );
    for (final feature in ['autoplay', 'encrypted-media', 'picture-in-picture', 'fullscreen', 'clipboard-write']) {
      expect(frame.allow, contains(feature));
    }
    expect(frame.allowFullscreen, isTrue);
    expect(frame.referrerPolicy, 'strict-origin-when-cross-origin');
    expect(frame.title, 'YouTube video player');
    expect(web.document.querySelectorAll('script[src*="youtube.com"]').length, 0);
    expect(messageListeners(), 1);
    video.dispose();
    expect(messageListeners(), 0);
  });

  test('announces itself until the frame answers, then subscribes to the events, once', () async {
    final video = local().play('aaaaaaaaaaa');
    final frame = await attach(video);
    final sent = spy(frame);
    await settle(const Duration(milliseconds: 600));
    expect(sent.length, greaterThanOrEqualTo(2));
    expect(sent.map(jsonEncode).toSet(), {
      jsonEncode({'event': 'listening', 'id': 1, 'channel': 'widget', 'to': origin}),
    });
    sent.clear();
    say(frame, {'event': 'initialDelivery', 'info': <String, Object?>{}, 'id': 1, 'channel': 'widget'});
    say(frame, {'event': 'infoDelivery', 'info': <String, Object?>{}});
    await settle(const Duration(milliseconds: 600));
    expect(sent.map(jsonEncode), [
      for (final name in ['onReady', 'onStateChange', 'onError'])
        jsonEncode({
          'event': 'command',
          'func': 'addEventListener',
          'args': [name],
          'id': 1,
          'channel': 'widget',
          'to': origin,
        }),
    ]);
    // "readyToListen": the frame asks again
    sent.clear();
    say(frame, {'event': 'readyToListen'});
    expect(sent.single['event'], 'listening');
    video.dispose();
  });

  test('stops announcing when disposed before an answer: nothing left behind', () async {
    final video = local().play('aaaaaaaaaaa');
    final frame = await attach(video);
    final sent = spy(frame);
    video.dispose();
    expect(video.host.isConnected, isFalse);
    expect(frame.isConnected, isFalse);
    await settle(const Duration(milliseconds: 600));
    expect(sent, isEmpty);
    expect(messageListeners(), 0);
  });

  test('only the messages of its own frame count', () async {
    final video = local().play('aaaaaaaaaaa');
    final frame = await attach(video);
    final error = {'event': 'onError', 'info': 150};
    say(frame, error, from: 'https://www.example.com');
    say(frame, error, source: web.window);
    say(frame, 'not json', raw: true);
    say(frame, {'some': 'data'}, raw: true);
    say(frame, '[1, 2]', raw: true);
    expect(video.state.value, EmbeddedVideoState.loading);
    // the frame of another video
    final other = local().play('bbbbbbbbbbb');
    final otherFrame = await attach(other);
    say(otherFrame, error);
    expect(video.state.value, EmbeddedVideoState.loading);
    expect(other.state.value, EmbeddedVideoState.refused);
    say(frame, error);
    expect(video.state.value, EmbeddedVideoState.refused);
    video.dispose();
    other.dispose();
  });

  test('hidden while it loads, shown when the player shows the video', () async {
    final video = local().play('aaaaaaaaaaa');
    final frame = await attach(video);
    String style(String name) => video.host.style.getPropertyValue(name);
    expect((style('opacity'), style('pointer-events')), ('0', 'none'));
    say(frame, {
      'event': 'initialDelivery',
      'info': {'playerState': -1},
    });
    say(frame, {'event': 'onReady'});
    say(frame, {'event': 'onStateChange', 'info': -1});
    expect(video.state.value, EmbeddedVideoState.loading);
    say(frame, {
      'event': 'infoDelivery',
      'info': {
        'playerState': 3,
        'videoData': {'title': 'Seether - Rise Above This'},
      },
    });
    expect(video.state.value, EmbeddedVideoState.playing);
    expect((style('opacity'), style('pointer-events')), ('1', 'auto'));
    expect(frame.title, 'Seether - Rise Above This', reason: 'for screen readers');
    video.dispose();
  });

  test('ready, and nothing more (no autoplay): shown after a moment, for its own play button', () async {
    final video = local(revealDelay: const Duration(milliseconds: 50)).play('aaaaaaaaaaa');
    final frame = await attach(video);
    say(frame, {'event': 'onReady'});
    expect(video.state.value, EmbeddedVideoState.loading);
    await settle(const Duration(milliseconds: 120));
    expect(video.state.value, EmbeddedVideoState.playing);
    video.dispose();
  });

  for (final (code, state) in [
    (150, EmbeddedVideoState.refused),
    (101, EmbeddedVideoState.refused),
    (100, EmbeddedVideoState.refused),
    // may not happen again: not remembered
    (5, EmbeddedVideoState.failed),
    (2, EmbeddedVideoState.failed),
    (153, EmbeddedVideoState.failed),
  ]) {
    test('player error $code: ${state.name}, the frame removed, nothing left behind', () async {
      final video = local().play('aaaaaaaaaaa');
      final frame = await attach(video);
      // what a refused video sent, in the browser
      say(frame, {'event': 'readyToListen'});
      say(frame, {
        'event': 'initialDelivery',
        'info': {'playerState': -1},
      });
      say(frame, {'event': 'onReady'});
      say(frame, {'event': 'onError', 'info': code});
      expect(video.state.value, state);
      expect(frame.isConnected, isFalse);
      expect(messageListeners(), 0);
      video.dispose();
    });
  }

  test('a playback error after the video was shown: the frame goes, and it may be tried again', () async {
    final video = local().play('aaaaaaaaaaa');
    final frame = await attach(video);
    say(frame, {'event': 'onStateChange', 'info': 1});
    expect(video.state.value, EmbeddedVideoState.playing);
    say(frame, {'event': 'onError', 'info': 5});
    expect(video.state.value, EmbeddedVideoState.failed);
    expect(frame.isConnected, isFalse);
    video.dispose();
  });

  test('a frame whose host cannot be reached: failed, never shown, nothing left behind', () async {
    // (a network that blocks YouTube: the browser loads its own error page in the frame, which says nothing)
    final video = YouTubeEmbedder(
      host: 'http://127.0.0.1:1',
      silentDelay: const Duration(milliseconds: 100),
      timeout: const Duration(seconds: 10),
    ).play('aaaaaaaaaaa');
    web.document.body!.append(video.host);
    for (var i = 0; i < 150 && video.state.value == EmbeddedVideoState.loading; i++) {
      await settle(const Duration(milliseconds: 20));
    }
    expect(video.state.value, EmbeddedVideoState.failed);
    expect(video.host.style.opacity, '0');
    expect(frameOf(video), isNull);
    expect(messageListeners(), 0);
    video.dispose();
  });

  test('the host is asked once the frame has loaded, not before', () async {
    final asked = <String>[];
    final fetch = globalContext['fetch'];
    addTearDown(() => globalContext['fetch'] = fetch);
    globalContext['fetch'] = ((JSString input, JSAny? init) {
      asked.add(input.toDart);
      return JSPromise<JSAny?>(((JSFunction resolve, JSFunction reject) {}).toJS);
    }).toJS;
    // not in the page yet: its frame has not loaded
    final video = local().play('aaaaaaaaaaa');
    await settle(const Duration(milliseconds: 100));
    expect(asked, isEmpty);
    await attach(video);
    expect(asked, ['$origin/generate_204']);
    video.dispose();
  });

  test('a silent frame is not shown before its host answered', () async {
    // the request to the host held back: the frame has loaded and been silent for long enough meanwhile
    final asked = <String>[];
    final answer = <JSFunction>[];
    // (put back as it was, not deleted: `fetch` is the window's own)
    final fetch = globalContext['fetch'];
    addTearDown(() => globalContext['fetch'] = fetch);
    globalContext['fetch'] = ((JSString input, JSAny? init) {
      asked.add(input.toDart);
      return JSPromise<JSAny?>(
        ((JSFunction resolve, JSFunction reject) {
          answer.add(resolve);
        }).toJS,
      );
    }).toJS;
    final video = local(silentDelay: const Duration(milliseconds: 60)).play('aaaaaaaaaaa');
    await attach(video);
    await settle(const Duration(milliseconds: 150));
    expect(asked, ['$origin/generate_204'], reason: 'one request, to the host of the frame, once it has loaded');
    expect(video.state.value, EmbeddedVideoState.loading);
    answer.single.callAsFunction(null, web.Response());
    await settle();
    expect(video.state.value, EmbeddedVideoState.playing);
    video.dispose();
  });

  test('a frame that loads and never talks: shown as it is, not refused', () async {
    final video = local(silentDelay: const Duration(milliseconds: 100)).play('aaaaaaaaaaa');
    await attach(video);
    expect(video.state.value, EmbeddedVideoState.loading);
    await settle(const Duration(milliseconds: 200));
    expect(video.state.value, EmbeddedVideoState.playing);
    expect(video.host.style.opacity, '1');
    video.dispose();
  });

  test('a frame that talks but never gets ready: shown at the timeout', () async {
    final video = local(timeout: const Duration(milliseconds: 150)).play('aaaaaaaaaaa');
    final frame = await attach(video);
    say(frame, {'event': 'initialDelivery', 'info': <String, Object?>{}});
    await settle(const Duration(milliseconds: 250));
    expect(video.state.value, EmbeddedVideoState.playing);
    video.dispose();
  });

  test('neither a load of the frame nor a message in time: failed, nothing left behind', () async {
    // never put in the page: the frame does not load
    final video = local(timeout: const Duration(milliseconds: 50)).play('aaaaaaaaaaa');
    await settle(const Duration(milliseconds: 120));
    expect(video.state.value, EmbeddedVideoState.failed);
    expect(frameOf(video), isNull);
    expect(messageListeners(), 0);
    video.dispose();
  });

  test('the page out of sight: the timeout waits for it to be seen', () async {
    shadow(web.document, 'hidden', true.toJS);
    final video = local(timeout: const Duration(milliseconds: 50)).play('aaaaaaaaaaa');
    await settle(const Duration(milliseconds: 150));
    expect(video.state.value, EmbeddedVideoState.loading);
    web.document.delete('hidden'.toJS);
    await settle(const Duration(milliseconds: 150));
    expect(video.state.value, EmbeddedVideoState.failed);
    video.dispose();
  });

  test('offline at the tap: failed at once, no frame', () async {
    shadow(web.window.navigator, 'onLine', false.toJS);
    final video = local().play('aaaaaaaaaaa');
    expect(frameOf(video), isNull);
    expect(video.state.value, EmbeddedVideoState.loading);
    await settle(Duration.zero);
    expect(video.state.value, EmbeddedVideoState.failed);
    expect(messageListeners(), 0);
    video.dispose();
  });

  test('dispose: the frame removed, its messages ignored', () async {
    final video = local().play('aaaaaaaaaaa');
    final frame = await attach(video);
    final window = frame.contentWindow!;
    video.dispose();
    say(frame, {'event': 'onStateChange', 'info': 1}, source: window);
    say(frame, {'event': 'onError', 'info': 150}, source: window);
    expect(video.state.value, EmbeddedVideoState.loading);
    expect(messageListeners(), 0);
  });
}
