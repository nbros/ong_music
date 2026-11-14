import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'page_thread.dart';
import 'sheet_prefetch.dart';
import 'sheet_snapshot.dart';
import 'sheets.dart';

/// The global set by the script of `web/index.html`: a promise of null (no
/// download started) or of `{highlights, songs}`, two promises of [web.Response].
const prefetchGlobal = 'ongMusicSheetPrefetch';

/// Web: forgets the download started by the page.
void discardPrefetchedSheets() => globalContext.delete(prefetchGlobal.toJS);

/// Web: takes the download started by the page, once. Each answer must start
/// within [timeout]; the caller bounds the whole.
Future<RawSheets?> takePrefetchedSheets({required Duration timeout}) async {
  final pending = globalContext[prefetchGlobal];
  if (pending == null) return null;
  globalContext.delete(prefetchGlobal.toJS);
  final started = await (pending as JSPromise<JSObject?>).toDart;
  if (started == null) return null;
  final texts = await Future.wait([
    _text(started['highlights']! as JSPromise<web.Response>, SheetUrls.highlights, timeout),
    _text(started['songs']! as JSPromise<web.Response>, SheetUrls.songs, timeout),
  ]);
  return RawSheets(highlightsCsv: texts[0], songsCsv: texts[1]);
}

/// The global set by the script of `web/index.html` for the snapshot: a promise of null (no download started) or of
/// `{base, highlights, songs, meta}`, the address it downloaded from and three promises of [web.Response].
const snapshotPrefetchGlobal = 'ongMusicSnapshotPrefetch';

/// Web: forgets the snapshot downloads the page may have started (another tab kept data in between): never used,
/// they must not stay in memory for the life of the page.
void discardPrefetchedSnapshot() => globalContext.delete(snapshotPrefetchGlobal.toJS);

/// Web: takes the snapshot downloads started by the page, once, when they come from [SnapshotUrls.base]. Each answer
/// must start within [timeout]; the caller bounds the whole.
Future<SnapshotTexts?> takePrefetchedSnapshot({required Duration timeout}) async {
  final pending = globalContext[snapshotPrefetchGlobal];
  if (pending == null) return null;
  globalContext.delete(snapshotPrefetchGlobal.toJS);
  final started = await (pending as JSPromise<JSObject?>).toDart;
  if (started == null) return null;
  // the address is written in index.html: an app built with another one (SHEETS_SNAPSHOT_URL) downloads by itself
  if ((started['base'] as JSString?)?.toDart != SnapshotUrls.base) return null;
  final texts = await Future.wait([
    _text(started['highlights']! as JSPromise<web.Response>, SnapshotUrls.highlights, timeout),
    _text(started['songs']! as JSPromise<web.Response>, SnapshotUrls.songs, timeout),
    _text(started['meta']! as JSPromise<web.Response>, SnapshotUrls.meta, timeout),
  ]);
  return (highlights: texts[0], songs: texts[1], meta: texts[2]);
}

/// The body of a response as [HttpSheetFetcher] reads it (UTF-8 from the bytes, [decodeUtf8]),
/// with its errors: [SheetHttpException], [SheetNotCsvException],
/// [http.ClientException], and a [TimeoutException] when the answer has not
/// started after [timeout].
Future<String> _text(JSPromise<web.Response> pending, Uri uri, Duration timeout) async {
  final web.Response response;
  final JSArrayBuffer body;
  try {
    response = await pending.toDart.timeout(timeout);
    body = await response.arrayBuffer().toDart;
  } on TimeoutException {
    rethrow;
  } catch (e) {
    throw http.ClientException('$e', uri);
  }
  if (response.status != 200) throw SheetHttpException(uri, response.status);
  return sheetCsv(decodeUtf8(body.toDart.asUint8List()), uri);
}
