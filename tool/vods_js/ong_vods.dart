// The JS module `ongVods`: the app's own code for the VODs and their offsets (`VodsTool`), for the tool of the
// offsets in the browser extension. Built by tool/build_vods_js.sh, which says how; its interface is that of the
// shared specification (OFFSETS.md):
//
//   globalThis.ongVods = {
//     version, sheets: { songs, highlights }, offsetsHeader,
//     load(songsCsv, highlightsCsv), overview(vodsTsv, offsetsTsv), stream(vodsTsv, offsetsTsv, videoId),
//     replaceOffsets(offsetsTsv, key, offsetsJson),
//   }
//
// Loading the built file only defines `ongVods`: nothing else runs until a function is called. An error of a call
// (a sheet or an argument that does not read, `overview` before `load`) is thrown as a JS `Error` whose `message`
// says what.

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:ong_music/src/data/sheets.dart' show SheetUrls;
import 'package:ong_music/src/data/vod_offsets.dart';
import 'package:ong_music/src/data/vods_tool.dart';

/// What the module was built from: set by tool/build_vods_js.sh (the commit and the time of the build).
const version = String.fromEnvironment('ONG_VODS_VERSION', defaultValue: 'unknown');

/// An error of a call as JavaScript gets it: dart2js throws a JS `Error` whose `message` is the `toString` of the Dart
/// object thrown, here the message alone.
final class _CallError implements Exception {
  _CallError(this.message);

  final String message;

  @override
  String toString() => message;
}

@JS('globalThis.ongVods')
external set _ongVods(JSObject value);

/// [value], the argument [name] of a call, as a string; anything else is an error.
String _string(JSAny? value, String name) {
  if (value.isA<JSString>()) return (value as JSString).toDart;
  throw ArgumentError('$name must be a string');
}

/// [call], whose errors JavaScript gets as an `Error` with their message ([_CallError], [vodsToolErrorMessage]).
T _guard<T>(T Function() call) {
  try {
    return call();
  } catch (e) {
    throw _CallError(vodsToolErrorMessage(e));
  }
}

void main() {
  final tool = VodsTool();
  final sheets = JSObject()
    ..setProperty('songs'.toJS, SheetUrls.songs.toString().toJS)
    ..setProperty('highlights'.toJS, SheetUrls.highlights.toString().toJS);
  _ongVods = JSObject()
    ..setProperty('version'.toJS, version.toJS)
    ..setProperty('sheets'.toJS, sheets)
    ..setProperty('offsetsHeader'.toJS, OffsetFile.header.toJS)
    ..setProperty(
      'load'.toJS,
      ((JSAny? songs, JSAny? highlights) => _guard(
        () => tool.load(_string(songs, 'songsCsv'), _string(highlights, 'highlightsCsv')).toJS,
      )).toJS,
    )
    ..setProperty(
      'overview'.toJS,
      ((JSAny? vods, JSAny? offsets) => _guard(
        () => tool.overview(_string(vods, 'vodsTsv'), _string(offsets, 'offsetsTsv')).toJS,
      )).toJS,
    )
    ..setProperty(
      'stream'.toJS,
      ((JSAny? vods, JSAny? offsets, JSAny? id) => _guard(
        () => tool.stream(_string(vods, 'vodsTsv'), _string(offsets, 'offsetsTsv'), _string(id, 'videoId')).toJS,
      )).toJS,
    )
    ..setProperty(
      'replaceOffsets'.toJS,
      ((JSAny? offsets, JSAny? key, JSAny? json) => _guard(
        () => VodsTool.replaceOffsets(
          _string(offsets, 'offsetsTsv'),
          _string(key, 'key'),
          _string(json, 'offsetsJson'),
        ).toJS,
      )).toJS,
    );
}
