import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/font_coverage.g.dart';

/// The code points [font] maps to a glyph (its `cmap` table, formats 4 and 12, every subtable), as
/// tool/gen_font_coverage.py reads them.
Set<int> codePointsOf(Uint8List font) {
  final data = ByteData.sublistView(font);
  final tables = <String, int>{};
  for (var i = 0; i < data.getUint16(4); i++) {
    final at = 12 + 16 * i;
    tables[String.fromCharCodes(font.sublist(at, at + 4))] = data.getUint32(at + 8);
  }
  final cmap = tables['cmap']!;
  final found = <int>{};
  for (var i = 0; i < data.getUint16(cmap + 2); i++) {
    final o = cmap + data.getUint32(cmap + 8 + 8 * i);
    switch (data.getUint16(o)) {
      case 4:
        final segments = data.getUint16(o + 6) ~/ 2;
        final ends = o + 14, starts = ends + 2 * segments + 2, deltas = starts + 2 * segments;
        final offsets = deltas + 2 * segments;
        for (var s = 0; s < segments; s++) {
          final start = data.getUint16(starts + 2 * s), end = data.getUint16(ends + 2 * s);
          final delta = data.getInt16(deltas + 2 * s), offset = data.getUint16(offsets + 2 * s);
          for (var c = start; c <= end; c++) {
            if (c == 0xFFFF) continue;
            var glyph = 0;
            if (offset == 0) {
              glyph = (c + delta) & 0xFFFF;
            } else {
              glyph = data.getUint16(offsets + 2 * s + offset + 2 * (c - start));
              if (glyph != 0) glyph = (glyph + delta) & 0xFFFF;
            }
            if (glyph != 0) found.add(c);
          }
        }
      case 12:
        for (var g = 0; g < data.getUint32(o + 12); g++) {
          final at = o + 16 + 12 * g;
          for (var c = data.getUint32(at); c <= data.getUint32(at + 4); c++) {
            found.add(c);
          }
        }
    }
  }
  return found;
}

/// The root of the Flutter SDK running the tests: `FLUTTER_ROOT`, or the directory above the `bin/cache` of the
/// test runner; null when neither says.
String? flutterRoot() {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return root;
  final executable = Platform.resolvedExecutable.replaceAll(r'\', '/');
  final cache = executable.indexOf('/bin/cache/');
  return cache < 0 ? null : executable.substring(0, cache);
}

void main() {
  final root = flutterRoot();
  final regular = root == null ? null : File('$root/engine/src/flutter/txt/third_party/fonts/Roboto-Regular.ttf');
  final skip = regular == null
      ? 'the Flutter SDK is unknown (no FLUTTER_ROOT, a test runner outside it)'
      : !regular.existsSync()
      ? 'the Flutter SDK has no ${regular.path} (not a checkout of the repository)'
      : false;

  test('the table of the characters the web app\'s fonts draw is that of Roboto Regular (as the build bundles it) and '
      'Roboto Medium: if not, run tool/gen_font_coverage.py again', () {
    final drawn = codePointsOf(regular!.readAsBytesSync())
      ..retainAll(codePointsOf(File('assets/fonts/Roboto-Medium.ttf').readAsBytesSync()));
    final table = <int>{
      for (var i = 0; i < bundledFontRanges.length; i += 2)
        for (var c = bundledFontRanges[i]; c <= bundledFontRanges[i + 1]; c++) c,
    };
    expect(table.length, drawn.length);
    expect(table.difference(drawn), isEmpty);
    expect(drawn.difference(table), isEmpty);
  }, skip: skip);
}
