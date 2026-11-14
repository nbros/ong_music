import 'dart:convert';
import 'dart:typed_data';

import 'slices.dart';

/// Native platforms: a timer of zero.
Future<void> yieldToBrowser() => Future<void>.delayed(Duration.zero);

/// Native platforms: a timer of zero, then [sliceBudget].
Future<IdleDeadline> waitForIdle() => Future<void>.delayed(Duration.zero).then((_) {
  final watch = Stopwatch()..start();
  return () => sliceBudget.inMicroseconds - watch.elapsedMicroseconds;
});

/// Native platforms: Dart's decoder.
String decodeUtf8(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);
