import 'dart:async';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/csv.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/data/slices.dart';
import 'package:ong_music/src/data/text.dart';
import 'package:ong_music/src/state/catalogue_state.dart';

import 'catalogue_dump.dart';
import 'fixtures.dart';

/// Runs [load] to its end with [runInSlices], pausing at once (no event loop turn), and returns its catalogue.
Future<Catalogue> runLoad(CatalogueLoad load, {Duration budget = Duration.zero}) async {
  await runInSlices(load.step, pause: () async {}, budget: budget);
  return load.catalogue;
}

/// What [parseCatalogue] throws for [sheets], or null.
Object? oneShotError(RawSheets sheets) {
  try {
    parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);
    return null;
  } catch (e) {
    return e;
  }
}

class FakeFetcher implements SheetFetcher {
  FakeFetcher(this.sheets);
  RawSheets sheets;

  @override
  Future<RawSheets> fetch() async => sheets;
}

void main() {
  final fixtures = <String, RawSheets>{
    'sample': sampleSheets(),
    'sample with extra plays': sampleSheets(tag: 'x', extraPlays: 40),
    'default catalogue': RawSheets(
      highlightsCsv: highlightsCsv([hRow(title: 'Some video')]),
      songsCsv: songsCsv([start('2024-01-01'), sRow(date: '2024-01-01 20:00:00', title: 'Some song')]),
    ),
    'decomposed accents, BOM, CRLF': RawSheets(
      highlightsCsv: '﻿${highlightsCsv([hRow(title: 'Léon'), hRow(title: 'Zoé - Á')])}',
      songsCsv: songsCsv([
        start('2024-01-01'),
        sRow(date: '2024-01-01 20:00:00', title: 'Léon', requester: 'Zoé'),
      ]).replaceAll('\n', '\r\n'),
    ),
  };

  group('a load in steps gives the catalogue of the one-shot parse', () {
    // pause intervals: every row and unit, odd ones that fall anywhere in a row, the defaults
    const intervals = [(1, 1), (2, 3), (7, 101), (rowsPerPause, unitsPerPause)];

    for (final MapEntry(key: name, value: sheets) in fixtures.entries) {
      test('fixture: $name', () async {
        final expected = dumpCatalogue(parseCatalogue(sheets.highlightsCsv, sheets.songsCsv));
        for (final (rows, units) in intervals) {
          final load = CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, rowsPerStep: rows, unitsPerStep: units);
          expect(dumpCatalogue(await runLoad(load)), expected, reason: '$rows rows, $units units per step');
        }
      });
    }

    test('generated sheets, every pause interval and budget', () async {
      for (var seed = 1; seed <= 6; seed++) {
        final sheets = generatedSheets(seed, plays: 300 + seed * 150);
        final expected = dumpCatalogue(parseCatalogue(sheets.highlightsCsv, sheets.songsCsv));
        for (final (rows, units) in intervals) {
          for (final budget in [Duration.zero, const Duration(microseconds: 200), sliceBudget]) {
            final load = CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, rowsPerStep: rows, unitsPerStep: units);
            expect(
              dumpCatalogue(await runLoad(load, budget: budget)),
              expected,
              reason: 'seed $seed, $rows rows, $units units per step, budget $budget',
            );
          }
        }
      }
    });

    test('generated sheets hold what they are meant to (the comparison above is not of near-empty catalogues)', () {
      final sheets = generatedSheets(3, plays: 2000);
      final c = parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);
      expect(c.playCount, greaterThan(1500));
      expect(c.streamCount, greaterThan(40));
      expect(c.highlights.where((h) => h.playId != null), isNotEmpty);
      expect(c.requesters.map((r) => r.name), containsAll(['Alice', 'Bob', 'Zoé', 'Chloë']));
      expect(c.requesters.length, 4, reason: 'spellings merged, decomposed accents composed');
      expect(c.plays.where((p) => p.loggedMinute == null), isNotEmpty);
      expect(c.highlights.where((h) => h.notes.contains('\n')), isNotEmpty);
    });

    test('the pieces in steps give the text of the one-shot functions, however the text is cut', () {
      const texts = [
        '',
        'e',
        'é',
        '́e',
        'Léon é́ àb ố',
        'x́̂y',
        'plain text without marks, long enough to be cut',
      ];
      for (final text in texts) {
        for (var units = 1; units <= text.length + 1; units++) {
          final composer = MarkComposer(text);
          while (composer.compose(units)) {}
          expect(composer.result, composeMarks(text), reason: '"$text" by $units');
        }
      }
      const csv = [
        '',
        'a',
        'a,b\nc',
        '"a,b","line 1\nline 2","say ""hi""",""\n"x"',
        'a\r\nb\nc\rd\r\n',
        '\n\n,\n"",""\nz',
        '"open',
        'a,"b""',
      ];
      for (final text in csv) {
        for (var rows = 0; rows <= 6; rows++) {
          final reader = CsvReader(text);
          while (reader.read(rows)) {}
          expect(reader.rows, decodeCsv(text), reason: '"$text" by $rows rows');
        }
      }
    });
  });

  group('slices', () {
    test('a slice stops as soon as it has used its budget, and not before', () async {
      final rng = Random(7);
      final sheets = generatedSheets(1, plays: 1500);
      final load = CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, rowsPerStep: 16, unitsPerStep: 2000);
      // the clock moves with the work: each step takes 0 to 1.5 ms
      var now = 0, lastStep = 0;
      final slices = <({int length, int lastStep})>[];
      var sliceStart = 0;
      const budget = Duration(milliseconds: 5);
      await runInSlices(
        () {
          lastStep = rng.nextInt(1500);
          now += lastStep;
          return load.step();
        },
        clock: () => now,
        budget: budget,
        pause: () async {
          // the first pause comes before any work
          if (now > 0) slices.add((length: now - sliceStart, lastStep: lastStep));
          sliceStart = now;
        },
      );
      expect(slices.length, greaterThan(20));
      for (final s in slices) {
        // at or over budget, but by less than its last step: the slice went on no longer than one pause interval
        expect(s.length, greaterThanOrEqualTo(budget.inMicroseconds));
        expect(s.length - s.lastStep, lessThan(budget.inMicroseconds));
      }
      expect(dumpCatalogue(load.catalogue), dumpCatalogue(parseCatalogue(sheets.highlightsCsv, sheets.songsCsv)));
    });

    test('with a budget of zero it pauses before every step, and still ends', () async {
      final load = CatalogueLoad(sampleSheets().highlightsCsv, sampleSheets().songsCsv, rowsPerStep: 1);
      var steps = 0, pauses = 0;
      await runInSlices(
        () {
          steps++;
          return load.step();
        },
        budget: Duration.zero,
        clock: () => 0,
        pause: () async => pauses++,
      );
      expect(steps, greaterThan(10));
      expect(pauses, steps);
      expect(load.catalogue.playCount, 1);
    });

    group('with a longest budget, slices lengthen while the pauses are long', () {
      /// The slices of a run whose steps take 500 µs and whose pauses take what [pauseCost] says (by pause number),
      /// in µs.
      Future<List<int>> slices(int Function(int pause) pauseCost, {Duration? maxBudget, int steps = 400}) async {
        var now = 0, done = 0, pauses = 0, sliceStart = 0;
        final lengths = <int>[];
        await runInSlices(
          () {
            now += 500;
            return ++done < steps;
          },
          clock: () => now,
          maxBudget: maxBudget,
          pause: () async {
            if (pauses > 0) lengths.add(now - sliceStart);
            now += pauseCost(pauses++);
            sliceStart = now;
          },
        );
        return lengths;
      }

      test('costly pauses (frames of a slow device): up to the longest budget, half as long again at most', () async {
        final lengths = await slices((_) => 15000, maxBudget: longestSlice, steps: 2000);
        expect(lengths.length, greaterThan(10));
        expect(lengths.first, lessThanOrEqualTo(sliceBudget.inMicroseconds * 1.5 + 500));
        for (var i = 1; i < lengths.length; i++) {
          expect(lengths[i], lessThanOrEqualTo(lengths[i - 1] * 1.5 + 500), reason: 'slice $i: $lengths');
        }
        expect(lengths.reduce(max), lessThanOrEqualTo(longestSlice.inMicroseconds + 500));
        expect(lengths[5], greaterThanOrEqualTo(longestSlice.inMicroseconds), reason: 'four times 15 ms is over 50');
      });

      test('cheap pauses (frames of a fast machine): slices of the budget', () async {
        final lengths = await slices((_) => 1500, maxBudget: longestSlice);
        expect(lengths.toSet(), {sliceBudget.inMicroseconds});
      });

      test('one long pause among cheap ones: one slice a little longer, then the budget again', () async {
        final lengths = await slices((pause) => pause == 10 ? 40000 : 100, maxBudget: longestSlice);
        expect(lengths.reduce(max), lessThanOrEqualTo(sliceBudget.inMicroseconds * 1.5 + 500));
        expect(lengths.sublist(16).toSet(), {sliceBudget.inMicroseconds});
      });

      test('without a longest budget (in the background), slices of the budget however long the pauses', () async {
        expect((await slices((_) => 30000)).toSet(), {sliceBudget.inMicroseconds});
        expect((await slices((_) => 30000, maxBudget: sliceBudget)).toSet(), {sliceBudget.inMicroseconds});
      });
    });

    group('no step does work that grows with the sheets: the steps of a load at one row or code unit each', () {
      // Every loop over the text, the rows, the plays, the titles, the requesters or the songs has a pause point at
      // each of its rows here: a row added to a sheet adds one step per loop that goes over it, a code unit one step.
      // A loop that loses its pause point does its whole work in one step, and the counts below change.

      /// The number of steps of a load of [sheets], one row or one code unit per step.
      int steps(RawSheets sheets) {
        final load = CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, rowsPerStep: 1, unitsPerStep: 1);
        var n = 0;
        while (load.step()) {
          n++;
        }
        return n;
      }

      /// One song and one highlight of it; [newSongs] rows of other songs by other requesters, [replays] rows of the
      /// same song by the same requester, [highlights] more highlights of it, [note] in the first highlight.
      RawSheets sheets({int newSongs = 0, int replays = 0, int highlights = 0, String note = ''}) => RawSheets(
        highlightsCsv: highlightsCsv([
          hRow(title: 'Base song', notes: note),
          for (var i = 0; i < highlights; i++) hRow(order: '${i + 2}', title: 'Base song'),
        ]),
        songsCsv: songsCsv([
          start('2024-01-01'),
          sRow(date: '2024-01-01 20:00:00', title: 'Base song', requester: 'Alice'),
          for (var i = 0; i < newSongs; i++) sRow(date: '2024-01-01 21:00:00', title: 'New $i', requester: 'Req $i'),
          for (var i = 0; i < replays; i++) sRow(date: '2024-01-01 22:00:00', title: 'Base song', requester: 'Alice'),
        ]),
      );
      final base = sheets();
      int units(RawSheets s) => s.highlightsCsv.length + s.songsCsv.length;

      /// The steps [variant] takes beyond those of [base], its added code units left out.
      int rowSteps(RawSheets variant) => steps(variant) - steps(base) - (units(variant) - units(base));

      test('a code unit more: one step (composing the marks)', () {
        final longer = sheets(note: 'x' * 500);
        expect(steps(longer) - steps(base), 500);
      });

      test('a row of the Ong Log with a new song and a new requester: 11 steps', () {
        // CSV, spellings, play drafts, plays by song, plays, requests, requesters, songs by plays, songs, title folds,
        // genres of the plays
        expect(rowSteps(sheets(newSongs: 40)), 40 * 11);
      });

      test('a row of the Ong Log with a song and a requester seen before: 8 steps', () {
        // CSV, spellings, play drafts, plays by song, plays, requests, songs by plays, genres of the plays
        expect(rowSteps(sheets(replays: 40)), 40 * 8);
      });

      test('a row of highlight of a song seen before: 4 steps', () {
        // CSV, spellings, highlights, highlight fields
        expect(rowSteps(sheets(highlights: 40)), 40 * 4);
      });
    });

    test('a malformed sheet throws the same exception through the slices', () async {
      final good = sampleSheets();
      final bad = <String, RawSheets>{
        'HTML highlights': RawSheets(highlightsCsv: '<!DOCTYPE html><html>Sign in</html>', songsCsv: good.songsCsv),
        'HTML songs': RawSheets(highlightsCsv: good.highlightsCsv, songsCsv: '\n <html></html>'),
        'empty': RawSheets(highlightsCsv: '', songsCsv: good.songsCsv),
        'no title header': RawSheets(
          highlightsCsv: good.highlightsCsv,
          songsCsv: csvOf([
            const ['a', 'b'],
            const ['1'],
          ]),
        ),
        'no highlight': RawSheets(highlightsCsv: highlightsCsv([]), songsCsv: good.songsCsv),
        'no play': RawSheets(highlightsCsv: good.highlightsCsv, songsCsv: songsCsv([start('2024-01-01')])),
        // a large sheet that fails late, after many pauses
        'large, no play': RawSheets(
          highlightsCsv: generatedSheets(2, plays: 3000).highlightsCsv,
          songsCsv: songsCsv([for (var i = 0; i < 2000; i++) start('2024-01-01')]),
        ),
      };
      for (final MapEntry(key: name, value: sheets) in bad.entries) {
        final expected = oneShotError(sheets);
        expect(expected, isA<CatalogueFormatException>(), reason: name);
        for (final rows in [1, rowsPerPause]) {
          final load = CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, rowsPerStep: rows, unitsPerStep: rows);
          await expectLater(
            runLoad(load),
            throwsA(
              isA<CatalogueFormatException>().having(
                (e) => e.message,
                'message',
                (expected! as FormatException).message,
              ),
            ),
            reason: name,
          );
        }
      }
    });

    test('an abandoned load stops at the next pause and does no more work', () async {
      final sheets = generatedSheets(4, plays: 1500);
      final load = CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, rowsPerStep: 8);
      var steps = 0, pauses = 0, stepsWhenAbandoned = -1;
      final run = runInSlices(
        () {
          steps++;
          return load.step();
        },
        budget: Duration.zero,
        pause: () async {
          if (++pauses == 5) stepsWhenAbandoned = steps;
        },
        isAbandoned: () => pauses >= 5,
      );
      await expectLater(run, throwsA(isA<LoadAbandoned>()));
      expect(stepsWhenAbandoned, 4, reason: 'one step after each of the 4 pauses before');
      expect(steps, stepsWhenAbandoned);
      expect(() => load.catalogue, throwsStateError);

      var called = false;
      await expectLater(
        runInSlices(() => called = true, pause: () async {}, isAbandoned: () => true),
        throwsA(isA<LoadAbandoned>()),
      );
      expect(called, isFalse, reason: 'abandoned before it started');
    });

    test('parseInSlices lets the event loop run between slices, and gives the one-shot catalogue', () async {
      final sheets = generatedSheets(6, plays: 3000);
      var ticks = 0;
      final timer = Timer.periodic(Duration.zero, (_) => ticks++);
      try {
        // every read of the clock is a millisecond of work: dozens of slices, whatever the machine
        var now = 0;
        final catalogue = await parseInSlices(sheets, clock: () => now += 1000);
        expect(ticks, greaterThan(20), reason: 'timers ran while it parsed');
        expect(dumpCatalogue(catalogue), dumpCatalogue(parseCatalogue(sheets.highlightsCsv, sheets.songsCsv)));
      } finally {
        timer.cancel();
      }
    });

    group('a load the user waits for may lengthen its slices; one in the background keeps them short', () {
      /// The slices of [run] (but the last), in µs, when every read of the clock costs [readCost] µs of work and
      /// every pause 30 ms (costly frames).
      Future<List<int>> slicesOf(
        Future<void> Function(Future<void> Function() pause, int Function() clock) run, {
        required int readCost,
      }) async {
        var now = 0, sliceStart = -1;
        final lengths = <int>[];
        await run(() async {
          if (sliceStart >= 0) lengths.add(now - sliceStart);
          now += 30000;
          sliceStart = now;
        }, () => now += readCost);
        return lengths;
      }

      final sheets = generatedSheets(8, plays: 6000);
      final texts = RawSheets(highlightsCsv: 'h' * 3000000, songsCsv: 's' * 3000000);
      Future<List<int>> parse(bool background) => slicesOf(
        (pause, clock) => parseInSlices(sheets, background: background, pause: pause, clock: clock),
        readCost: 400,
      );
      Future<List<int>> fingerprint(bool background) => slicesOf(
        (pause, clock) => fingerprintInSlices(texts, background: background, pause: pause, clock: clock),
        readCost: 2000,
      );

      test('parse', () async {
        final background = await parse(true), waited = await parse(false);
        expect(background.length, greaterThan(15));
        expect(background.reduce(max), lessThanOrEqualTo(sliceBudget.inMicroseconds + 1200));
        expect(waited.reduce(max), greaterThanOrEqualTo(longestSlice.inMicroseconds));
        expect(waited.reduce(max), lessThanOrEqualTo(longestSlice.inMicroseconds + 1200));
      });

      test('fingerprint', () async {
        final background = await fingerprint(true), waited = await fingerprint(false);
        expect(background.length, greaterThan(10));
        expect(background.reduce(max), lessThanOrEqualTo(sliceBudget.inMicroseconds + 6000));
        expect(waited.reduce(max), greaterThanOrEqualTo(longestSlice.inMicroseconds));
        expect(waited.reduce(max), lessThanOrEqualTo(longestSlice.inMicroseconds + 6000));
      });
    });

    test('a step of nothing is refused: the load would never end', () {
      final sheets = sampleSheets();
      expect(() => CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, rowsPerStep: 0), throwsArgumentError);
      expect(() => CatalogueLoad(sheets.highlightsCsv, sheets.songsCsv, unitsPerStep: 0), throwsArgumentError);
      expect(() => MarkComposer('ab').compose(0), throwsA(isA<AssertionError>()));
      expect(() => TextHash('ab').add(0), throwsA(isA<AssertionError>()));
    });
  });

  group('fingerprint in slices', () {
    test('the hash is the same however the text is cut, and that of the web', () {
      // String.hashCode as dart2js computes it (js_string.dart), written out: the browser test checks the real one
      int reference(String text) {
        var hash = 0;
        for (final unit in text.codeUnits) {
          hash = 0x1fffffff & (hash + unit);
          hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
          hash ^= hash >> 6;
        }
        hash = 0x1fffffff & (hash + ((0x03ffffff & hash) << 3));
        hash ^= hash >> 11;
        return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
      }

      for (final text in ['', 'a', 'Zoé ♪ 😀', generatedSheets(1, plays: 50).songsCsv]) {
        for (final units in [1, 3, 64, text.length + 1]) {
          final hash = TextHash(text);
          while (hash.add(units)) {}
          expect(hash.value, reference(text), reason: '${text.length} units by $units');
        }
      }
      expect(() => TextHash('abc').value, throwsStateError);
    });

    test('equal sheets give equal fingerprints, a change of one character in either sheet another one', () async {
      final a = generatedSheets(2, plays: 400);
      final b = RawSheets(highlightsCsv: a.highlightsCsv, songsCsv: a.songsCsv.replaceFirst('Zelda', 'Zeldb'));
      final fa = await fingerprintInSlices(a), fb = await fingerprintInSlices(b);
      expect(await fingerprintInSlices(RawSheets(highlightsCsv: a.highlightsCsv, songsCsv: a.songsCsv)), fa);
      expect(fb.songsLength, fa.songsLength);
      expect(fb, isNot(fa));
      final c = RawSheets(highlightsCsv: a.highlightsCsv.replaceFirst('Zelda', 'Zeldb'), songsCsv: a.songsCsv);
      final fc = await fingerprintInSlices(c);
      expect(fc.highlightsLength, fa.highlightsLength);
      expect(fc, isNot(fa), reason: 'a change in the highlights only');
      await expectLater(fingerprintInSlices(a, isAbandoned: () => true), throwsA(isA<LoadAbandoned>()));
    });
  });

  group('wiring', () {
    test('native platforms parse on a background isolate, the web in slices', () {
      final native = ProviderContainer.test();
      expect(native.read(loadsInSlicesProvider), isFalse, reason: 'the VM is not the web');
      expect(identical(native.read(catalogueParserProvider), parseInBackground), isTrue);
      expect(identical(native.read(sheetsFingerprintProvider), fingerprintAtOnce), isTrue);
      final web = ProviderContainer.test(
        overrides: [
          loadsInSlicesProvider.overrideWithValue(true),
          sheetCacheProvider.overrideWithValue(MemorySheetCache()),
        ],
      );
      expect(identical(web.read(catalogueParserProvider), parseInSlices), isTrue);
      expect(identical(web.read(sheetsFingerprintProvider), fingerprintInSlices), isTrue);
      final repository = web.read(catalogueRepositoryProvider);
      expect(identical(repository.parse, parseInSlices), isTrue);
      expect(identical(repository.fingerprint, fingerprintInSlices), isTrue);
    });

    test('the parse on a background isolate gives the one-shot catalogue', () async {
      final sheets = generatedSheets(3);
      expect(
        dumpCatalogue(await parseInBackground(sheets)),
        dumpCatalogue(parseCatalogue(sheets.highlightsCsv, sheets.songsCsv)),
      );
    });

    test('the state, loaded in slices: cache shown, refreshes found unchanged keep its instance', () async {
      final sheets = generatedSheets(4, plays: 3000);
      final cache = MemorySheetCache(CachedSheets(sheets: sheets, fetchedAt: DateTime.utc(2000)));
      final container = ProviderContainer.test(
        overrides: [
          loadsInSlicesProvider.overrideWithValue(true),
          sheetFetcherProvider.overrideWithValue(FakeFetcher(sheets)),
          sheetCacheProvider.overrideWithValue(cache),
          prefetchDiscarderProvider.overrideWithValue(() {}),
        ],
      );
      final shownCatalogues = <Catalogue>{};
      container.listen(catalogueProvider, (_, next) {
        if (next.catalogue != null) shownCatalogues.add(next.catalogue!);
      });
      await container.read(catalogueProvider.notifier).idle;
      expect(shownCatalogues, hasLength(1), reason: 'the download matched the fingerprint of the cache: kept');
      final state = container.read(catalogueProvider);
      expect(state.lastError, isNull);
      expect(state.fetchedAt, isNot(DateTime.utc(2000)), reason: 'the stale cache was refreshed');
      expect(dumpCatalogue(state.catalogue!), dumpCatalogue(parseCatalogue(sheets.highlightsCsv, sheets.songsCsv)));
      final shown = state.catalogue;
      await container.read(catalogueProvider.notifier).refresh();
      expect(identical(container.read(catalogueProvider).catalogue, shown), isTrue, reason: 'same fingerprint');
    });

    test('a load the state no longer wants is told so: rebuilt or disposed, its parse is abandoned', () async {
      final asked = <bool Function()?>[];
      final backgrounds = <bool>[];
      final release = Completer<void>();
      Future<Catalogue> parser(RawSheets sheets, {bool Function()? isAbandoned, bool background = false}) async {
        asked.add(isAbandoned);
        backgrounds.add(background);
        await release.future;
        if (isAbandoned?.call() ?? false) throw const LoadAbandoned();
        return parseCatalogue(sheets.highlightsCsv, sheets.songsCsv);
      }

      final cache = MemorySheetCache(CachedSheets(sheets: sampleSheets(), fetchedAt: DateTime.utc(2000)));
      final container = ProviderContainer.test(
        overrides: [
          catalogueParserProvider.overrideWithValue(parser),
          sheetFetcherProvider.overrideWithValue(FakeFetcher(sampleSheets(tag: 'new'))),
          sheetCacheProvider.overrideWithValue(cache),
          prefetchDiscarderProvider.overrideWithValue(() {}),
        ],
      );
      container.listen(catalogueProvider, (_, _) {});
      await pumpEventQueue();
      expect(asked, hasLength(1), reason: 'the cache is being parsed');
      expect(asked.single!(), isFalse);
      container.invalidate(catalogueProvider);
      container.read(catalogueProvider);
      expect(asked.single!(), isTrue, reason: 'rebuilt: the first load is abandoned');
      await pumpEventQueue();
      expect(asked, hasLength(2), reason: 'the new build parses the cache again');
      expect(asked.last!(), isFalse);
      release.complete();
      await container.read(catalogueProvider.notifier).idle;
      expect(cache.clears, 0, reason: 'an abandoned load is not a broken cache');
      expect(container.read(catalogueProvider).lastError, isNull);
      expect(container.read(catalogueProvider).catalogue!.highlights.single.title, 'Video new');
      final download = asked.last!;
      container.dispose();
      expect(download(), isTrue, reason: 'disposed: the download is abandoned too');
      // the cache (twice), then the download that replaces the cached catalogue on the screen
      expect(backgrounds, [false, false, true]);
    });

    test('an abandoned load of the cache keeps the cache and throws LoadAbandoned', () async {
      final cache = MemorySheetCache(CachedSheets(sheets: sampleSheets(), fetchedAt: DateTime.utc(2000)));
      final repository = CatalogueRepository(
        fetcher: FakeFetcher(sampleSheets()),
        cache: cache,
        parse: parseInSlices,
        fingerprint: fingerprintInSlices,
      );
      await expectLater(repository.loadCached(isAbandoned: () => true), throwsA(isA<LoadAbandoned>()));
      await expectLater(repository.fetch(isAbandoned: () => true), throwsA(isA<LoadAbandoned>()));
      expect((cache.clears, cache.writes), (0, 0));
      expect((await repository.loadCached())!.catalogue.playCount, 1);
    });

    test('the repository hands the fingerprint what it hands the parser', () async {
      final asked = <(bool Function()?, bool)>[];
      Future<SheetsFingerprint> fingerprint(RawSheets sheets, {bool Function()? isAbandoned, bool background = false}) {
        asked.add((isAbandoned, background));
        return fingerprintInSlices(sheets);
      }

      final repository = CatalogueRepository(
        fetcher: FakeFetcher(sampleSheets(tag: 'new')),
        cache: MemorySheetCache(CachedSheets(sheets: sampleSheets(), fetchedAt: DateTime.utc(2000))),
        parse: parseOnCurrentIsolate,
        fingerprint: fingerprint,
      );
      bool cacheAbandoned() => false;
      bool fetchAbandoned() => false;
      await repository.loadCached(isAbandoned: cacheAbandoned);
      await repository.fetch(isAbandoned: fetchAbandoned, background: true);
      expect(asked, [(cacheAbandoned, false), (fetchAbandoned, true)]);
    });
  });
}
