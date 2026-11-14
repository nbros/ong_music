// Generates lib/src/data/noto_coverage.g.dart: the characters that the Google Fonts families the app asks symbols
// and other rare characters of (see lib/src/data/font_kits.dart) draw, as ranges of code points, read from the table
// the Flutter web engine chooses its own fallback fonts with.
//
//   dart run tool/gen_noto_coverage.dart > lib/src/data/noto_coverage.g.dart
//
// The table is `engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart` of the Flutter SDK running the
// tool (FLUTTER_ROOT, or the SDK of `dart`), generated there by `dev/roll_fallback_fonts.dart` from the fonts Google
// Fonts serves. Run it again when Flutter changes; test/noto_coverage_test.dart fails until then.
//
// ignore_for_file: avoid_print

import 'dart:io';

/// The families of the table to write, by the folder of their fonts' addresses (a split family's slices are fonts of
/// their own, named after it with a number: "Noto Sans Symbols 2 0" is a slice of Noto Sans Symbols 2, not of Noto
/// Sans Symbols): the name the app asks Google Fonts for.
const Map<String, String> notoFamilies = {
  'notosans': 'Noto Sans',
  'notosanssymbols2': 'Noto Sans Symbols 2',
  'notosanssymbols': 'Noto Sans Symbols',
  'notosansmath': 'Noto Sans Math',
};

/// The path of the engine's table in the Flutter SDK at [flutterRoot].
String fallbackDataPath(String flutterRoot) =>
    '$flutterRoot/engine/src/flutter/lib/web_ui/lib/src/engine/font_fallback_data.dart';

// the encoding of the table (the engine's noto_font_encoding.dart)
const int _prefixDigit0 = 48, _prefixRadix = 10;
const int _fontIndexDigit0 = 97, _fontIndexRadix = 26;
const int _rangeSizeDigit0 = 97, _rangeSizeRadix = 26;
const int _rangeValueDigit0 = 65, _rangeValueRadix = 26;
const int _maxCodePoint = 0x10FFFF;

/// The string constant [name] of [source]: its literals, joined.
String _constant(String source, String name) {
  final start = source.indexOf('const String $name =');
  if (start < 0) throw FormatException('No $name in the table');
  final end = source.indexOf(';', start);
  return [
    for (final literal in RegExp(r"^\s*'([^']*)'", multiLine: true).allMatches(source.substring(start, end)))
      literal[1]!,
  ].join();
}

/// The characters each family of [notoFamilies] draws, by its name, as first and last code point of each range,
/// ascending, from the [source] of the engine's table: its fonts (each with the folder of its address), the sets of
/// fonts that share characters (`encodedFontSets`), and which set each range of code points belongs to
/// (`encodedFontSetRanges`), decoded as the engine does (`font_fallbacks.dart`).
Map<String, List<int>> notoRangesOf(String source) {
  final folders = <int, String>{
    for (final font in RegExp(r"NotoFont\(\s*'[^']+',\s*'([^/']+)/[^']*',\s*index: (\d+)").allMatches(source))
      int.parse(font[2]!): font[1]!,
  };
  final sets = <Set<String>>[];
  for (final data in _constant(source, 'encodedFontSets').split(',')) {
    final set = <String>{};
    var previous = -1, prefix = 0;
    for (final code in data.codeUnits) {
      if (code >= _fontIndexDigit0 && code < _fontIndexDigit0 + _fontIndexRadix) {
        previous += prefix * _fontIndexRadix + (code - _fontIndexDigit0) + 1;
        final family = notoFamilies[folders[previous] ?? (throw FormatException('No font $previous'))];
        if (family != null) set.add(family);
        prefix = 0;
      } else {
        prefix = prefix * _prefixRadix + (code - _prefixDigit0);
      }
    }
    sets.add(set);
  }
  final ranges = {for (final family in notoFamilies.values) family: <int>[]};
  var start = 0, prefix = 0, size = 1;
  for (final code in _constant(source, 'encodedFontSetRanges').codeUnits) {
    if (code >= _rangeValueDigit0 && code < _rangeValueDigit0 + _rangeValueRadix) {
      for (final family in sets[prefix * _rangeValueRadix + (code - _rangeValueDigit0)]) {
        final list = ranges[family]!;
        if (list.isNotEmpty && list.last == start - 1) {
          list.last = start + size - 1;
        } else {
          list.addAll([start, start + size - 1]);
        }
      }
      start += size;
      prefix = 0;
      size = 1;
    } else if (code >= _rangeSizeDigit0 && code < _rangeSizeDigit0 + _rangeSizeRadix) {
      size = prefix * _rangeSizeRadix + (code - _rangeSizeDigit0) + 2;
      prefix = 0;
    } else {
      prefix = prefix * _prefixRadix + (code - _prefixDigit0);
    }
  }
  if (start != _maxCodePoint + 1) throw FormatException('The ranges end at $start');
  for (final MapEntry(:key, :value) in ranges.entries) {
    if (value.isEmpty) throw FormatException('No character of $key');
  }
  return ranges;
}

/// The root of the Flutter SDK: FLUTTER_ROOT, or the directory above the `bin/cache` of [executable].
String? flutterRootOf(String executable) {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root != null && root.isNotEmpty) return root;
  final path = executable.replaceAll(r'\', '/');
  final cache = path.indexOf('/bin/cache/');
  return cache < 0 ? null : path.substring(0, cache);
}

void main() {
  final root = flutterRootOf(Platform.resolvedExecutable);
  if (root == null) {
    stderr.writeln('The Flutter SDK is unknown: set FLUTTER_ROOT');
    exit(64);
  }
  final ranges = notoRangesOf(File(fallbackDataPath(root)).readAsStringSync());
  final out = StringBuffer()
    ..writeln(
      '// GENERATED by tool/gen_noto_coverage.dart from the font fallback table of the Flutter web engine. Do '
      'not edit.',
    )
    ..writeln('// dart format off')
    ..writeln()
    ..writeln(
      '/// The characters some Google Fonts families draw, as the Flutter web engine knows them: by family, first '
      'and last',
    )
    ..writeln('/// code point of each range, ascending.')
    ..writeln('const Map<String, List<int>> notoRanges = {');
  for (final MapEntry(:key, :value) in ranges.entries) {
    var count = 0;
    for (var i = 0; i < value.length; i += 2) {
      count += value[i + 1] - value[i] + 1;
    }
    out.writeln("  // $count characters\n  '$key': [");
    for (var i = 0; i < value.length; i += 16) {
      final line = [
        for (var j = i; j < i + 16 && j < value.length; j++)
          '0x${value[j].toRadixString(16).toUpperCase().padLeft(4, '0')}',
      ];
      out.writeln('    ${line.join(', ')},');
    }
    out.writeln('  ],');
  }
  out.writeln('};');
  stdout.write(out);
}
