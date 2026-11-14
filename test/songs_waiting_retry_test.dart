// The Retry of a failed load while a text of the Songs sheet waits for the highlights.
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_snapshot.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/state/catalogue_state.dart';

import 'fixtures.dart';
import 'sheet_fakes.dart';

void main() {
  final now = DateTime.utc(2026, 11, 12, 12);
  late DateTime clock;
  late FakeGoogle google;
  late RecordingParser parser;
  late ProviderContainer container;
  late List<String> log;

  CatalogueNotifier notifier() => container.read(catalogueProvider.notifier);
  CatalogueState state() => container.read(catalogueProvider);

  void startWith({MemorySheetCache? cached, SnapshotFetcher snapshot = const NoSnapshot()}) {
    parser = RecordingParser();
    log = [];
    google.onFetch = (s) => log.add('${clock.difference(now).inSeconds}s ${s.name}');
    container = ProviderContainer.test(
      overrides: [
        sheetFetcherProvider.overrideWithValue(google),
        snapshotFetcherProvider.overrideWithValue(snapshot),
        sheetCacheProvider.overrideWithValue(cached ?? MemorySheetCache()),
        sheetParserProvider.overrideWithValue(parser),
        songsDeferralProvider.overrideWithValue(() async {}),
        clockProvider.overrideWithValue(() => clock),
        prefetchDiscarderProvider.overrideWithValue(() {}),
      ],
    );
    container.listen(catalogueProvider, (_, _) {}, fireImmediately: true);
  }

  Future<void> run(WidgetTester tester, Duration total, {Duration step = const Duration(seconds: 5)}) async {
    final end = clock.add(total);
    while (clock.isBefore(end)) {
      clock = clock.add(step);
      await tester.pump(step);
    }
  }

  void many(Sheet sheet, Object result, [int n = 400]) {
    for (var i = 0; i < n; i++) {
      google.addFor(sheet, result);
    }
  }

  setUp(() {
    clock = now;
    google = FakeGoogle();
  });

  testWidgets('Retry while only the Highlights sheet fails: the Songs sheet, in and waiting, is not downloaded again', (
    tester,
  ) async {
    startWith();
    many(highlights, const SocketException('offline'));
    many(songs, sampleSheets().songsCsv);
    notifier().songsWanted(SongsTrigger.ongLog);
    await tester.pump(Duration.zero);
    await run(tester, const Duration(seconds: 5), step: const Duration(seconds: 1));
    expect(state().isFailed, isTrue);
    final before = google.calls[highlights]!;
    for (var i = 0; i < 3; i++) {
      await notifier().refresh();
      await tester.pump(Duration.zero);
    }
    expect(google.calls[highlights], before + 3);
    expect(google.calls[songs], 1);
    container.dispose();
  });
}
