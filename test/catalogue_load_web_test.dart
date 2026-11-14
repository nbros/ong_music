// Browser only: flutter test --platform chrome test/catalogue_load_web_test.dart
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/page_thread.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:web/web.dart' as web;

import 'catalogue_dump.dart';
import 'fixtures.dart';

/// The longest the page went without a frame (`requestAnimationFrame`) while [work] ran, in milliseconds, and the
/// number of frames.
Future<({double gap, int frames})> framesDuring(Future<void> Function() work) async {
  final performance = web.window.performance;
  var last = performance.now(), gap = 0.0, frames = 0, running = true;
  late final JSFunction onFrame;
  onFrame = ((JSNumber _) {
    final now = performance.now();
    gap = max(gap, now - last);
    last = now;
    frames++;
    if (running) web.window.requestAnimationFrame(onFrame);
  }).toJS;
  web.window.requestAnimationFrame(onFrame);
  await work();
  running = false;
  return (gap: max(gap, performance.now() - last), frames: frames);
}

void main() {
  // the size of the real Songs sheet: 30,000 rows
  final large = generatedSheets(9, plays: 30000);

  test(
    'the page keeps drawing while the catalogue loads in slices; it does not while it is parsed in one go',
    () async {
      // 50 ms: three frames at 60 Hz, a slice and a step on a slow machine
      const bound = 50.0;
      late final Catalogue oneShot, sliced;
      final atOnce = await framesDuring(() async {
        oneShot = parseCatalogue(large.highlightsCsv, large.songsCsv);
      });
      final inSlices = await framesDuring(() async {
        sliced = await parseInSlices(large);
        await fingerprintInSlices(large);
      });
      expect(dumpCatalogue(sliced), dumpCatalogue(oneShot));
      expect(atOnce.gap, greaterThan(bound), reason: 'the one-shot parse is long enough to show the difference');
      // against the one-shot parse on the same machine, and a bound a loaded test machine still meets (a slice took
      // 51 ms once on GitHub's)
      final reason = '${inSlices.gap} ms in ${inSlices.frames} frames, against ${atOnce.gap} ms at once';
      expect(inSlices.gap, lessThan(atOnce.gap / 3), reason: reason);
      expect(inSlices.gap, lessThan(2 * bound), reason: reason);
      expect(inSlices.frames, greaterThan(5));
    },
  );

  // Strings whose TextHash the VM computes: the web, whatever its compiler, must find the same values.
  final hashed = {
    '': 0,
    'a': 170824770,
    'Zoé ♪ 😀 \u0000\uFFFF': 65371428,
    List.generate(5000, (i) => String.fromCharCode(32 + i * 7 % 3000)).join(): 125228775,
  };

  test('the hash in slices gives the values of the VM', () {
    for (final MapEntry(key: text, value: expected) in hashed.entries) {
      final hash = TextHash(text);
      while (hash.add(4093)) {}
      expect(hash.value, expected, reason: '${text.length} code units');
    }
  });

  test(
    'under dart2js, the hash in slices is String.hashCode, the fingerprint in slices RawSheets.fingerprint',
    () async {
      for (final text in [...hashed.keys, large.songsCsv.substring(0, 100000)]) {
        final hash = TextHash(text);
        while (hash.add(4093)) {}
        expect(hash.value, text.hashCode, reason: '${text.length} code units');
      }
      final sheets = generatedSheets(2, plays: 2000);
      expect(await fingerprintInSlices(sheets), sheets.fingerprint);
    },
    // nothing relies on it (see TextHash): it only shows what its comment says
    skip: const bool.fromEnvironment('dart.tool.dart2wasm') ? 'dart2wasm hashes strings its own way' : false,
  );

  test('the browser decoder gives the text of utf8.decode, malformed input included', () {
    final samples = <List<int>>[
      utf8.encode('plain ASCII, then é, ♪, 😀 and 千と千尋, long enough for the browser decoder'),
      [0xC3],
      [0x41, 0xFF, 0x42],
      [0xC0, 0xAF, 0x41],
      [0xED, 0xA0, 0x80, 0x41],
      [0xF0, 0x9F, 0x98, 0x41],
      [0xF4, 0x90, 0x80, 0x80],
      [0xE2, 0x82],
      // long (the browser decoder first in utf8.decode), with malformed bytes in it, and a U+FFFD typed in a cell
      [...utf8.encode('"Title","Genre"\n"Zoé '), 0xE9, 0x80, ...utf8.encode('� x", "y"\n'), 0xF8, 0x88, 0x80],
    ];
    for (final bytes in samples) {
      final data = Uint8List.fromList(bytes);
      expect(decodeUtf8(data), utf8.decode(data, allowMalformed: true), reason: '$bytes');
    }
    // a byte order mark is dropped, as utf8.decode does on the web (the parser drops it anyway)
    final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('"Upload Date","Order","Video Title"')]);
    expect(decodeUtf8(bom), utf8.decode(bom, allowMalformed: true));
    expect(decodeUtf8(bom).startsWith('"Upload'), isTrue);
  });

  test('pauses come back in order, side by side', () async {
    final order = <int>[];
    await Future.wait([for (var i = 0; i < 5; i++) yieldToBrowser().then((_) => order.add(i))]);
    expect(order, [0, 1, 2, 3, 4]);
  });

  test('the web loads in slices', () {
    final container = ProviderContainer.test();
    expect(container.read(loadsInSlicesProvider), isTrue);
    expect(identical(container.read(catalogueParserProvider), parseInSlices), isTrue);
    expect(identical(container.read(sheetsFingerprintProvider), fingerprintInSlices), isTrue);
  });
}
