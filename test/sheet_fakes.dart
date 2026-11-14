// Fakes of the network, the daily copy and the parser, a sheet at a time, for the tests of the loading.
import 'dart:async';

import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/repository.dart';
import 'package:ong_music/src/data/sheet_cache.dart';
import 'package:ong_music/src/data/sheet_snapshot.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/data/slices.dart';

const highlights = Sheet.highlights, songs = Sheet.songs;

/// Google: each call for a sheet answers the next of its [results] (a text, or an error to throw), once its gate
/// (when set) completes.
class FakeGoogle implements SheetFetcher {
  final results = {for (final sheet in Sheet.values) sheet: <Object>[]};
  final calls = {for (final sheet in Sheet.values) sheet: 0};
  final gates = <Sheet, Completer<void>>{};

  /// Called at each call, before its gate.
  void Function(Sheet sheet)? onFetch;

  /// Queues the text of each sheet of [sheets] (a [RawSheets]), or one error for each.
  void add(Object sheets) {
    for (final sheet in Sheet.values) {
      results[sheet]!.add(sheets is RawSheets ? sheets[sheet] : sheets);
    }
  }

  /// Queues [result] (a text or an error) for [sheet] only.
  void addFor(Sheet sheet, Object result) => results[sheet]!.add(result);

  /// Gates [sheet]: its answers wait for the completer returned.
  Completer<void> gate(Sheet sheet) => gates[sheet] = Completer<void>();

  int get total => calls.values.fold(0, (a, b) => a + b);

  @override
  Future<String> fetch(Sheet sheet) async {
    calls[sheet] = calls[sheet]! + 1;
    onFetch?.call(sheet);
    final gate = gates[sheet];
    if (gate != null) await gate.future;
    final r = results[sheet]!.removeAt(0);
    if (r is String) return r;
    throw r;
  }
}

/// The daily copy: for each sheet its result (a [CachedSheet], or an error to throw), once its gate (when set)
/// completes.
class FakeSnapshot implements SnapshotFetcher {
  FakeSnapshot([Map<Sheet, Object>? results]) : results = {...?results};

  final Map<Sheet, Object> results;
  final calls = {for (final sheet in Sheet.values) sheet: 0};
  final gates = <Sheet, Completer<void>>{};

  /// Sets the copy of both sheets of [sheets], made at [madeAt].
  void set(RawSheets sheets, DateTime madeAt) {
    for (final sheet in Sheet.values) {
      results[sheet] = CachedSheet(text: sheets[sheet], fetchedAt: madeAt);
    }
  }

  Completer<void> gate(Sheet sheet) => gates[sheet] = Completer<void>();

  @override
  Future<CachedSheet> fetch(Sheet sheet) async {
    calls[sheet] = calls[sheet]! + 1;
    final gate = gates[sheet];
    if (gate != null) await gate.future;
    final r = results[sheet] ?? StateError('No snapshot of ${sheet.name}');
    if (r is CachedSheet) return r;
    throw r;
  }
}

/// A parse the [RecordingParser] was asked for.
typedef ParseCall = ({Sheet sheet, String tag, bool background, bool Function()? isAbandoned, bool Function()? hurry});

/// The tag of the first highlight or song of [csv] (`Video <tag>`, `Song <tag>` of `sampleSheets`), after the
/// header.
String tagOf(String csv) =>
    RegExp(r'"(?:Video|Song) (\w+)"').allMatches(csv).map((m) => m[1]!).where((tag) => tag != 'Title').firstOrNull ??
    '?';

/// Parses on the calling isolate ([ParseOnCurrentIsolate]) and records each call. A parse can be held ([gates], by
/// sheet and tag), made deaf to its abandonment ([deaf]: it runs to its end, as on a background isolate) or failed
/// ([failures], by sheet: thrown by the next parses of that sheet, one each).
class RecordingParser implements SheetParser {
  final calls = <ParseCall>[];
  final gates = <(Sheet, String), Completer<void>>{};
  final deaf = <(Sheet, String)>{};
  final failures = {for (final sheet in Sheet.values) sheet: <Object>[]};

  /// The tags parsed for [sheet], in order.
  List<String> of(Sheet sheet) => [
    for (final c in calls)
      if (c.sheet == sheet) c.tag,
  ];

  Future<void> _before(
    Sheet sheet,
    String csv,
    bool Function()? isAbandoned,
    bool background, [
    bool Function()? hurry,
  ]) async {
    final tag = tagOf(csv);
    calls.add((sheet: sheet, tag: tag, background: background, isAbandoned: isAbandoned, hurry: hurry));
    final gate = gates[(sheet, tag)];
    if (gate != null) await gate.future;
    if (failures[sheet]!.isNotEmpty) throw failures[sheet]!.removeAt(0);
    if (!deaf.contains((sheet, tag)) && (isAbandoned?.call() ?? false)) throw const LoadAbandoned();
  }

  @override
  Future<Catalogue> highlights(String csv, {bool Function()? isAbandoned, bool background = false}) async {
    await _before(Sheet.highlights, csv, isAbandoned, background);
    return const ParseOnCurrentIsolate().highlights(csv);
  }

  @override
  Future<SongsPart> songs(
    Catalogue highlights,
    String csv, {
    bool Function()? isAbandoned,
    bool background = false,
    bool Function()? hurry,
  }) async {
    await _before(Sheet.songs, csv, isAbandoned, background, hurry);
    return const ParseOnCurrentIsolate().songs(highlights, csv);
  }
}

/// A cache holding both sheets of [sheets] (only the Highlights sheet when not [withSongs]), downloaded at [at].
MemorySheetCache cacheOf(RawSheets sheets, DateTime at, {bool withSongs = true, DateTime? songsAt}) => MemorySheetCache(
  highlights: CachedSheet(text: sheets.highlightsCsv, fetchedAt: at),
  songs: withSongs ? CachedSheet(text: sheets.songsCsv, fetchedAt: songsAt ?? at) : null,
);
