import 'dart:async';
import 'dart:collection';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

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

final web.TextDecoder _decoder = web.TextDecoder('utf-8', web.TextDecoderOptions(fatal: false));

/// Web: the browser's decoder (a leading byte order mark is dropped, as `utf8.decode` does).
String decodeUtf8(Uint8List bytes) => _decoder.decode(bytes.toJS);
