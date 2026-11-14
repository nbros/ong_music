import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'slices.dart';

/// The pauses waiting for their message, in the order of their messages (loads may run side by side).
final Queue<Completer<void>> _waiting = Queue();

web.MessageChannel? _channel;

/// Web: a message posted to the page itself, whose task comes after the frame the browser has due.
Future<void> yieldToBrowser() {
  final channel = _channel ??= web.MessageChannel()
    ..port1.onmessage = ((web.MessageEvent _) => _waiting.removeFirst().complete()).toJS;
  final done = Completer<void>();
  _waiting.add(done);
  channel.port2.postMessage(null);
  return done.future;
}

/// Whether the browser has idle callbacks (Safari has not).
final bool _hasIdleCallbacks = globalContext.has('requestIdleCallback');

/// The longest a slice of background work runs in an idle period: the browser grants up to 50 ms when no frame is
/// due, and an input that comes meanwhile (a wheel, a touch) would wait for the slice. 5 ms, the time a 120 Hz frame
/// leaves after drawing a list.
const double _idleSliceMs = 5;

/// Web: an idle period of the page, at most a second away, and at most [_idleSliceMs] of it; without idle
/// callbacks, the task of [yieldToBrowser] and 4 ms from its start.
Future<IdleDeadline> waitForIdle() {
  if (!_hasIdleCallbacks) {
    return yieldToBrowser().then((_) {
      final end = web.window.performance.now() + 4;
      return () => ((end - web.window.performance.now()) * 1000).round();
    });
  }
  final done = Completer<IdleDeadline>();
  web.window.requestIdleCallback(
    ((web.IdleDeadline deadline) {
      final end = web.window.performance.now() + _idleSliceMs;
      done.complete(() => (math.min(deadline.timeRemaining(), end - web.window.performance.now()) * 1000).round());
    }).toJS,
    web.IdleRequestOptions(timeout: 1000),
  );
  return done.future;
}

final web.TextDecoder _decoder = web.TextDecoder('utf-8', web.TextDecoderOptions(fatal: false));

/// Web: the browser's decoder (a leading byte order mark is dropped, as `utf8.decode` does).
String decodeUtf8(Uint8List bytes) => _decoder.decode(bytes.toJS);
