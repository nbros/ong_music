import 'dart:convert';
import 'dart:typed_data';

/// Native platforms: a timer of zero.
Future<void> yieldToBrowser() => Future<void>.delayed(Duration.zero);

/// Native platforms: Dart's decoder.
String decodeUtf8(Uint8List bytes) => utf8.decode(bytes, allowMalformed: true);
