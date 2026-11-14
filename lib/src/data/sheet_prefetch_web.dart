import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:http/http.dart' as http;
import 'package:web/web.dart' as web;

import 'page_thread.dart';
import 'sheet_snapshot.dart';
import 'sheets.dart';

/// The global set by the script of `web/index.html`: a promise of null (no download started) or of an object with
/// a promise of [web.Response] per sheet it downloads, under the name of the sheet (`highlights`).
const prefetchGlobal = 'ongMusicSheetPrefetch';

/// Web: forgets the downloads started by the page.
void discardPrefetchedSheets() => globalContext.delete(prefetchGlobal.toJS);

/// Web: takes the download of [sheet] started by the page, once. Its answer must start within [timeout]; the caller
/// bounds the whole.
Future<String?> takePrefetchedSheet(Sheet sheet, {required Duration timeout}) async {
  final response = await _take(prefetchGlobal, sheet.name);
  return response == null ? null : _text(response, SheetUrls.of(sheet), timeout);
}

/// The global set by the script of `web/index.html` for the snapshot: a promise of null (no download started) or of
/// `{base, files}`, the address it downloaded from and a promise of [web.Response] per file it downloads, under its
/// name (`highlights.csv`, `snapshot.json`).
const snapshotPrefetchGlobal = 'ongMusicSnapshotPrefetch';

/// Web: forgets the snapshot downloads the page may have started (another tab kept data in between): never used,
/// they must not stay in memory for the life of the page.
void discardPrefetchedSnapshot() => globalContext.delete(snapshotPrefetchGlobal.toJS);

/// Web: takes the download of the snapshot file [name] started by the page, once, when it comes from
/// [SnapshotUrls.base]. Its answer must start within [timeout]; the caller bounds the whole.
Future<String?> takePrefetchedSnapshotFile(String name, {required Duration timeout}) async {
  final pending = globalContext[snapshotPrefetchGlobal];
  if (pending == null) return null;
  final started = await (pending as JSPromise<JSObject?>).toDart;
  // the address is written in index.html: an app built with another one (SHEETS_SNAPSHOT_URL) downloads by itself
  if (started == null || (started['base'] as JSString?)?.toDart != SnapshotUrls.base) {
    discardPrefetchedSnapshot();
    return null;
  }
  final response = await _take(snapshotPrefetchGlobal, name, inside: 'files');
  return response == null ? null : _text(response, Uri.parse('${SnapshotUrls.base}$name'), timeout);
}

/// The promise of [name] in the object the page's promise [global] resolves to (in its property [inside] when
/// given), taken out of it: none for the next caller. The global goes once nothing is left in it.
Future<JSPromise<web.Response>?> _take(String global, String name, {String? inside}) async {
  final pending = globalContext[global];
  if (pending == null) return null;
  final started = await (pending as JSPromise<JSObject?>).toDart;
  if (started == null) {
    globalContext.delete(global.toJS);
    return null;
  }
  // discarded meanwhile (the app found its data fresh after all), or the last download taken by another caller
  if (globalContext[global] == null) return null;
  final holder = inside == null ? started : started[inside] as JSObject?;
  final response = holder?[name];
  if (holder == null || response == null) return null;
  holder.delete(name.toJS);
  if (_isEmpty(holder)) globalContext.delete(global.toJS);
  return response as JSPromise<web.Response>;
}

bool _isEmpty(JSObject object) =>
    (globalContext['Object'] as JSObject).callMethod<JSArray<JSAny?>>('keys'.toJS, object).toDart.isEmpty;

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
