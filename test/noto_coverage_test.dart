// The table of the characters of the Google Fonts families the app asks rare characters of, against the one of the
// Flutter web engine it was generated from.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/noto_coverage.g.dart';

import '../tool/gen_noto_coverage.dart';

void main() {
  final root = flutterRootOf(Platform.resolvedExecutable);
  final table = root == null ? null : File(fallbackDataPath(root));
  final skip = table == null
      ? 'the Flutter SDK is unknown (no FLUTTER_ROOT, a test runner outside it)'
      : !table.existsSync()
      ? 'the Flutter SDK has no ${table.path} (not a checkout of the repository)'
      : false;

  test('the characters of Noto Sans and the symbol fonts are those of the Flutter web engine\'s table: if not, run '
      'tool/gen_noto_coverage.dart again', () {
    expect(notoRangesOf(table!.readAsStringSync()), notoRanges);
  }, skip: skip);

  test('what Google Fonts answers for the symbols of the real sheets (checked by hand on 2026-11-14)', () {
    bool draws(String family, String c) {
      final ranges = notoRanges[family]!, code = c.runes.single;
      for (var i = 0; i < ranges.length; i += 2) {
        if (code >= ranges[i] && code <= ranges[i + 1]) return true;
      }
      return false;
    }

    String drawn(String family) => [
      for (final c in '→↓−∞△☆♡♪♫♭♯'.split(''))
        if (draws(family, c)) c,
    ].join();
    expect(drawn('Noto Sans'), '−');
    expect(drawn('Noto Sans Symbols 2'), '−△☆♡');
    expect(drawn('Noto Sans Symbols'), '→↓−♪♫♭♯');
    expect(drawn('Noto Sans Math'), '→↓−∞△☆♡♪♫♭♯');
  });
}
