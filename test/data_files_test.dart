// The files of the branch `data` (vods.tsv, aliases.txt): downloaded with the sheets, kept, read again offline, and
// never in the way of the catalogue.
import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ong_music/src/data/data_file_cache_io.dart';
import 'package:ong_music/src/data/data_files.dart';
import 'package:ong_music/src/data/requester_aliases.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_snapshot.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/vods_state.dart';

import 'fixtures.dart';
import 'sheet_fakes.dart';

/// The branch `data`: each call for a file answers the next of its results (a text, or an error to throw), the last
/// one again once they are used up, after its gate when set.
class FakeDataBranch implements DataFileFetcher {
  FakeDataBranch([Map<DataFile, List<Object>>? results])
    : results = {
        for (final file in DataFile.values) file: [...?results?[file]],
      };

  final Map<DataFile, List<Object>> results;
  final calls = {for (final file in DataFile.values) file: 0};
  final gates = <DataFile, Completer<void>>{};

  Completer<void> gate(DataFile file) => gates[file] = Completer<void>();

  @override
  Future<String> fetch(DataFile file) async {
    calls[file] = calls[file]! + 1;
    final gate = gates[file];
    if (gate != null) await gate.future;
    final queue = results[file]!;
    final r = queue.isEmpty ? SheetHttpException(_missing, 404) : (queue.length > 1 ? queue.removeAt(0) : queue.first);
    if (r is String) return r;
    throw r;
  }
}

final _missing = Uri.parse('https://raw.githubusercontent.com/nbros/ong_music/data/x');

const _vods = 'date\tpart\tid\tseconds\tposted\ttitle\n2024-01-02\t1\tabcdefghijk\t21600\t2024-01-03\tVOD';

/// Amy and her other name, the table of the tests.
const _aliases = 'Amy, Amyy\n';

final _now = DateTime.utc(2026, 11, 15, 12);

/// The sheets of [tag]: a highlight requested by "Amyy", a play by "Amy", on 1 January 2024 (2 January in Sydney).
RawSheets _sheets(String tag) => RawSheets(
  highlightsCsv: highlightsCsv([hRow(title: 'Video $tag', requester: 'Amyy')]),
  songsCsv: songsCsv([
    start('2024-01-01 20:00:00'),
    sRow(date: '2024-01-01 20:30:00', uptime: '0:30:00', title: 'Song $tag', requester: 'Amy'),
  ]),
);

void main() {
  late ProviderContainer container;
  late FakeGoogle google;
  late FakeDataBranch branch;
  late MemoryDataFileCache dataCache;
  late RecordingParser parser;

  CatalogueNotifier notifier() => container.read(catalogueProvider.notifier);
  CatalogueState state() => container.read(catalogueProvider);

  /// Starts the app: the sheets kept [sheetsAge] ago (none when null), the data files of [kept].
  void startWith({Duration? sheetsAge, Map<DataFile, CachedSheet>? kept, MemoryDataFileCache? cache}) {
    google = FakeGoogle();
    parser = RecordingParser();
    dataCache = cache ?? MemoryDataFileCache(kept);
    container = ProviderContainer.test(
      overrides: [
        sheetFetcherProvider.overrideWithValue(google),
        snapshotFetcherProvider.overrideWithValue(const NoSnapshot()),
        sheetCacheProvider.overrideWithValue(
          sheetsAge == null ? MemorySheetCache() : cacheOf(_sheets('kept'), _now.subtract(sheetsAge)),
        ),
        sheetParserProvider.overrideWithValue(parser),
        dataFileFetcherProvider.overrideWithValue(branch),
        dataFileCacheProvider.overrideWithValue(dataCache),
        clockProvider.overrideWithValue(() => _now),
        songsDeferralProvider.overrideWithValue(() async {}),
        prefetchDiscarderProvider.overrideWithValue(() {}),
      ],
    );
    container.listen(catalogueProvider, (_, _) {});
  }

  CachedSheet copy(String text, {Duration age = const Duration(hours: 1)}) =>
      CachedSheet(text: text, fetchedAt: _now.subtract(age));

  /// Whether Amy and Amyy are one requester in the catalogue on the screen.
  bool joined() {
    final c = state().catalogue!;
    return c.requesterNamed('Amy') != null && identical(c.requesterNamed('Amy'), c.requesterNamed('Amyy'));
  }

  setUp(() => branch = FakeDataBranch());

  group('the branch does not exist, or no network', () {
    for (final (name, error) in [
      ('404', SheetHttpException(_missing, 404)),
      ('a timeout', TimeoutException('silence')),
      ('no network', const SocketException('offline')),
    ]) {
      test('$name: the app as before, silently: no VOD, the bundled table', () async {
        branch = FakeDataBranch({
          DataFile.vods: [error],
          DataFile.aliases: [error],
        });
        startWith();
        google.add(_sheets('v1'));
        notifier().songsWanted(SongsTrigger.ongLog);
        await notifier().idle;
        expect(state().hasSongs, isTrue);
        expect(state().lastError, isNull, reason: 'not an error of the sheets');
        expect(state().songsError, isNull);
        expect(container.read(vodFileProvider), isNull);
        expect(branch.calls, {DataFile.vods: 1, DataFile.aliases: 1});
        expect(dataCache.writes, isEmpty);
        expect(parser.aliases, [same(RequesterAliases.bundled)]);
        expect(identical(state().catalogue!.aliases, RequesterAliases.bundled), isTrue);
        expect(joined(), isFalse);
      });
    }
    test('a failure of the files alone, the sheets fresh: no error of a sheet, then or later', () async {
      branch = FakeDataBranch({
        DataFile.vods: [SheetHttpException(_missing, 404)],
        DataFile.aliases: [SheetHttpException(_missing, 404)],
      });
      startWith(sheetsAge: const Duration(hours: 1));
      await notifier().idle;
      expect(branch.calls.values, [1, 1], reason: 'asked at the start, none being kept');
      // what shows the state again: the Songs sheet asked for
      notifier().songsWanted(SongsTrigger.ongLog);
      await notifier().idle;
      expect(state().hasSongs, isTrue);
      expect(state().lastError, isNull);
      expect(state().songsError, isNull);
      expect(state().isUpdating, isFalse);
      expect(google.total, 0, reason: 'no download of the sheets for them');
    });
  });

  group('downloads', () {
    test('with the Highlights sheet: the VODs taken at once and kept, the table kept for the next parse', () async {
      branch = FakeDataBranch({
        DataFile.vods: [_vods],
        DataFile.aliases: [_aliases],
      });
      // the table comes after the parse it was asked with
      final table = branch.gate(DataFile.aliases);
      startWith();
      google.add(_sheets('v1'));
      await pumpEventQueue();
      expect(parser.of(highlights), ['v1']);
      table.complete();
      await notifier().idle;
      final file = container.read(vodFileProvider)!;
      expect(file.lines.single.id, 'abcdefghijk');
      expect(dataCache.values.keys.toSet(), {DataFile.vods, DataFile.aliases});
      expect(dataCache.values[DataFile.vods]!.text, _vods);
      expect(dataCache.values[DataFile.vods]!.fetchedAt, _now);
      expect(parser.of(highlights), ['v1'], reason: 'no second parse for the new table');
      expect(joined(), isFalse, reason: 'the parse came before the table');
      // the next parse of the highlights takes it
      google.addFor(highlights, _sheets('v2').highlightsCsv);
      await notifier().refresh(waitForSongs: false);
      await notifier().idle;
      expect(parser.of(highlights), ['v1', 'v2']);
      expect(parser.aliases.last!.keyOf('amyy'), parser.aliases.last!.keyOf('amy'));
      expect(joined(), isTrue);
      expect(branch.calls, {DataFile.vods: 2, DataFile.aliases: 2}, reason: 'asked with each download of the sheet');
    });

    test('the catalogue never waits for them; nothing is shown of them until they come', () async {
      final vods = branch.gate(DataFile.vods);
      final aliases = branch.gate(DataFile.aliases);
      branch.results[DataFile.vods]!.add(_vods);
      startWith();
      google.add(_sheets('v1'));
      notifier().songsWanted(SongsTrigger.ongLog);
      await pumpEventQueue();
      expect(state().hasSongs, isTrue, reason: 'shown while both files are on their way');
      expect(container.read(vodFileProvider), isNull);
      vods.complete();
      await pumpEventQueue();
      expect(container.read(vodFileProvider), isNotNull);
      aliases.complete();
      await notifier().idle;
    });

    test(
      'a table that does not read is neither kept nor taken; a file that does not read leaves the kept one',
      () async {
        branch = FakeDataBranch({
          DataFile.vods: [SheetNotCsvException(_missing)],
          DataFile.aliases: ['# no group\nCarol\n'],
        });
        startWith(
          sheetsAge: const Duration(days: 1),
          kept: {
            DataFile.vods: copy(_vods, age: const Duration(days: 1)),
            DataFile.aliases: copy(_aliases),
          },
        );
        google.add(_sheets('v1'));
        await notifier().idle;
        expect(dataCache.writes, isEmpty);
        expect(container.read(vodFileProvider)!.lines.single.id, 'abcdefghijk', reason: 'the kept VODs stay');
        expect(parser.aliases.map((a) => a?.keyOf('amyy') == a?.keyOf('amy')), [true, true]);
      },
    );

    test('an unchanged file is not taken again', () async {
      branch = FakeDataBranch({
        DataFile.vods: [_vods],
        DataFile.aliases: [_aliases],
      });
      startWith(
        sheetsAge: const Duration(days: 1),
        kept: {DataFile.vods: copy(_vods, age: const Duration(days: 1))},
      );
      final taken = [];
      container.listen(vodFileProvider, (_, next) => taken.add(next));
      google.add(_sheets('v1'));
      await notifier().idle;
      expect(taken, hasLength(1), reason: 'the kept copy only');
      expect(dataCache.values[DataFile.vods]!.fetchedAt, _now, reason: 'kept again, with its new time');
    });
  });

  group('answers that are not the file', () {
    for (final (name, answer) in [
      ('an error of a proxy', 'upstream connect error or disconnect/reset before headers. reset reason: overflow'),
      ('an empty answer', ''),
      ('a table of another kind', 'id\tdate\tpart\nabcdefghijk\t2024-01-02\t1\n'),
    ]) {
      test('$name, status 200: the VODs kept stay, in use and kept, at the next start offline too', () async {
        branch = FakeDataBranch({
          DataFile.vods: [answer],
          DataFile.aliases: [_aliases],
        });
        startWith(
          sheetsAge: const Duration(days: 1),
          kept: {DataFile.vods: copy(_vods, age: const Duration(days: 1))},
        );
        google.add(_sheets('v1'));
        await notifier().idle;
        expect(container.read(vodFileProvider)!.lines.single.id, 'abcdefghijk');
        expect(dataCache.writes, [DataFile.aliases], reason: 'the table only');
        expect(dataCache.values[DataFile.vods]!.text, _vods);
        // the next start, offline
        final kept = dataCache;
        branch = FakeDataBranch({
          DataFile.vods: [const SocketException('offline')],
          DataFile.aliases: [const SocketException('offline')],
        });
        startWith(sheetsAge: const Duration(days: 1), cache: kept);
        google.add(const SocketException('offline'));
        await notifier().idle;
        expect(container.read(vodFileProvider)!.lines.single.id, 'abcdefghijk');
      });
    }

    test('the header alone is a real file without any VOD: taken and kept', () async {
      const header = '# the VODs\n\ndate\tpart\tid\tseconds\tposted\ttitle\n';
      branch = FakeDataBranch({
        DataFile.vods: [header],
      });
      startWith(
        sheetsAge: const Duration(days: 1),
        kept: {DataFile.vods: copy(_vods, age: const Duration(days: 1))},
      );
      google.add(_sheets('v1'));
      await notifier().idle;
      expect(container.read(vodFileProvider)!.isEmpty, isTrue);
      expect(dataCache.values[DataFile.vods]!.text, header);
    });

    test('a table of names that does not read: the kept one stays kept, and is the next start\'s', () async {
      branch = FakeDataBranch({
        DataFile.aliases: ['upstream connect error or disconnect/reset before headers'],
      });
      startWith(
        sheetsAge: const Duration(days: 1),
        kept: {DataFile.aliases: copy(_aliases, age: const Duration(days: 1))},
      );
      google.add(_sheets('v1'));
      await notifier().idle;
      expect(dataCache.writes, isEmpty);
      expect(dataCache.values[DataFile.aliases]!.text, _aliases);
      final kept = dataCache;
      branch = FakeDataBranch();
      startWith(sheetsAge: const Duration(hours: 1), cache: kept);
      await notifier().idle;
      expect(parser.aliases.single!.keyOf('amyy'), parser.aliases.single!.keyOf('amy'));
    });

    test('larger than its bound: a failed download, whatever the fetcher', () async {
      final big = '$_vods\n${'#' * maxVodsBytes}';
      final bigTable = '$_aliases${'#' * maxAliasesBytes}';
      branch = FakeDataBranch({
        DataFile.vods: [big],
        DataFile.aliases: [bigTable],
      });
      startWith(
        sheetsAge: const Duration(days: 1),
        kept: {DataFile.aliases: copy(_aliases, age: const Duration(days: 1))},
      );
      google.add(_sheets('v1'));
      await notifier().idle;
      expect(container.read(vodFileProvider), isNull);
      expect(dataCache.writes, isEmpty);
      expect(maxVodsBytes, 2 * 1024 * 1024);
      expect(maxAliasesBytes, 256 * 1024);
    });
  });

  group('kept copies', () {
    test('offline: the kept VODs shown, the kept table given to the first parse', () async {
      branch = FakeDataBranch({
        DataFile.vods: [const SocketException('offline')],
        DataFile.aliases: [const SocketException('offline')],
      });
      startWith(
        sheetsAge: const Duration(days: 1),
        kept: {DataFile.vods: copy(_vods), DataFile.aliases: copy(_aliases)},
      );
      google.add(const SocketException('offline'));
      notifier().songsWanted(SongsTrigger.ongLog);
      await notifier().idle;
      expect(state().hasSongs, isTrue);
      expect(container.read(vodFileProvider)!.lines.single.id, 'abcdefghijk');
      expect(parser.aliases.single!.keyOf('amyy'), parser.aliases.single!.keyOf('amy'));
      expect(joined(), isTrue);
      expect(dataCache.reads.toSet(), {DataFile.vods, DataFile.aliases});
    });

    test('a kept table that does not read: the bundled one', () async {
      startWith(sheetsAge: const Duration(hours: 1), kept: {DataFile.aliases: copy('<html></html>')});
      await notifier().idle;
      expect(parser.aliases, [same(RequesterAliases.bundled)]);
    });

    test(
      'fresh sheets, fresh files: nothing downloaded; files missing or stale: downloaded without the sheets',
      () async {
        startWith(
          sheetsAge: const Duration(hours: 1),
          kept: {DataFile.vods: copy(_vods), DataFile.aliases: copy(_aliases)},
        );
        await notifier().idle;
        expect(google.total, 0);
        expect(branch.calls.values, [0, 0]);

        startWith(sheetsAge: const Duration(hours: 1), kept: {DataFile.vods: copy(_vods)});
        await notifier().idle;
        expect(google.total, 0);
        expect(branch.calls.values, [1, 1], reason: 'the table missing');

        branch = FakeDataBranch();
        startWith(
          sheetsAge: const Duration(hours: 1),
          kept: {
            DataFile.vods: copy(_vods, age: const Duration(hours: 7)),
            DataFile.aliases: copy(_aliases),
          },
        );
        await notifier().idle;
        expect(branch.calls.values, [1, 1], reason: 'the VODs stale');
      },
    );

    test('"Clear downloaded data" clears them too, and downloads them again', () async {
      branch = FakeDataBranch({
        DataFile.vods: [_vods],
        DataFile.aliases: [_aliases],
      });
      startWith(
        sheetsAge: const Duration(hours: 1),
        kept: {DataFile.vods: copy(_vods), DataFile.aliases: copy(_aliases)},
      );
      await notifier().idle;
      google.add(_sheets('v1'));
      await notifier().clearDownloadedData();
      await notifier().idle;
      expect(dataCache.clears, 1);
      expect(dataCache.values.keys.toSet(), {DataFile.vods, DataFile.aliases});
      expect(branch.calls.values, [1, 1]);
    });
  });

  group('over HTTP', () {
    test('the files of the branch data of the repository, unless --dart-define names another place', () {
      expect(
        DataFileUrls.of(DataFile.vods).toString(),
        'https://raw.githubusercontent.com/nbros/ong_music/data/vods.tsv',
      );
      expect(DataFileUrls.of(DataFile.aliases).toString(), endsWith('/data/aliases.txt'));
    });

    test('a 200 is the file, as UTF-8; a 404 or a web page throws', () async {
      final asked = <Uri>[];
      final fetcher = HttpDataFileFetcher(
        client: MockClient((request) async {
          asked.add(request.url);
          return switch (request.url.pathSegments.last) {
            'vods.tsv' => http.Response.bytes([0xC3, 0xA9], 200),
            _ => http.Response('404: Not Found', 404),
          };
        }),
      );
      expect(await fetcher.fetch(DataFile.vods), 'é');
      await expectLater(fetcher.fetch(DataFile.aliases), throwsA(isA<SheetHttpException>()));
      final page = HttpDataFileFetcher(
        client: MockClient((request) async => http.Response('<html>sign in</html>', 200)),
      );
      await expectLater(page.fetch(DataFile.vods), throwsA(isA<SheetNotCsvException>()));
      expect(asked.map((u) => u.path), ['/nbros/ong_music/data/vods.tsv', '/nbros/ong_music/data/aliases.txt']);
    });

    test('beyond its bound, the body is not read further: a failure', () async {
      var sent = 0;
      Stream<List<int>> body() async* {
        // 64 KB at a time, for ever unless the reader stops
        for (var i = 0; i < 1000; i++) {
          sent++;
          yield List.filled(64 * 1024, 0x23);
        }
      }

      final fetcher = HttpDataFileFetcher(
        client: MockClient.streaming((request, _) async => http.StreamedResponse(body(), 200)),
      );
      await expectLater(fetcher.fetch(DataFile.aliases), throwsA(isA<DataFileTooLargeException>()));
      expect(sent, lessThan(10), reason: 'stopped after 256 KB');
      sent = 0;
      await expectLater(fetcher.fetch(DataFile.vods), throwsA(isA<DataFileTooLargeException>()));
      expect(sent, lessThan(40), reason: 'stopped after 2 MB');
      // a declared length beyond the bound: not read at all
      sent = 0;
      final declared = HttpDataFileFetcher(
        client: MockClient.streaming(
          (request, _) async => http.StreamedResponse(body(), 200, contentLength: maxAliasesBytes + 1),
        ),
      );
      await expectLater(declared.fetch(DataFile.aliases), throwsA(isA<DataFileTooLargeException>()));
      expect(sent, lessThanOrEqualTo(1));
      // at the bound: read
      final exact = HttpDataFileFetcher(
        client: MockClient((request) async => http.Response.bytes(List.filled(maxAliasesBytes, 0x23), 200)),
      );
      expect((await exact.fetch(DataFile.aliases)).length, maxAliasesBytes);
    });

    test('a silence is a failure, not a wait for ever', () async {
      final fetcher = HttpDataFileFetcher(
        client: MockClient((request) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      );
      await expectLater(fetcher.fetch(DataFile.vods), throwsA(isA<TimeoutException>()));
    });
  });

  group('the files on the device', () {
    late Directory dir;
    setUp(() async => dir = await Directory.systemTemp.createTemp('data_files_test'));
    tearDown(() async => dir.delete(recursive: true));

    test('written, read back with their time, cleared', () async {
      final cache = FileDataFileCache(() async => Directory('${dir.path}/data'));
      expect(await cache.read(DataFile.vods), isNull);
      await cache.write(DataFile.vods, CachedSheet(text: _vods, fetchedAt: _now));
      final read = (await cache.read(DataFile.vods))!;
      expect(read.text, _vods);
      expect(read.fetchedAt, _now);
      expect(await cache.read(DataFile.aliases), isNull);
      await cache.clear();
      expect(await cache.read(DataFile.vods), isNull);
    });

    test('a text without its time is no copy (a write that did not finish)', () async {
      final cache = FileDataFileCache(() async => Directory(dir.path));
      await File('${dir.path}/vods.tsv').writeAsString(_vods);
      expect(await cache.read(DataFile.vods), isNull);
    });
  });
}
