/// Downloading the raw CSV text of the two sheets.
library;

import 'dart:async';

import 'package:http/http.dart' as http;

import 'page_thread.dart';
import 'sheet_prefetch.dart';

/// The two sheets of the spreadsheet. Each one is downloaded, kept and refreshed on its own: the Highlights list
/// needs only [highlights], and [songs] is seven times larger (see `CatalogueNotifier.songsWanted`).
enum Sheet {
  /// "Youtube Catalogue": the highlights.
  highlights,

  /// "Songs": the Ong Log.
  songs,
}

/// Tells whether two downloads of a sheet have the same content, without keeping the megabytes of text around: its
/// length and a hash of it. Only comparable within one run of the app, and with fingerprints of the same function.
typedef TextFingerprint = ({int length, int hash});

/// The raw CSV text of both sheets, as downloaded: the scripts and the tests, which parse them at once
/// (`parseCatalogue`).
final class RawSheets {
  /// Bundles the two payloads.
  const RawSheets({required this.highlightsCsv, required this.songsCsv});

  /// "Youtube Catalogue" sheet.
  final String highlightsCsv;

  /// "Songs" sheet (the Ong Log).
  final String songsCsv;

  /// The text of [sheet].
  String operator [](Sheet sheet) => switch (sheet) {
    Sheet.highlights => highlightsCsv,
    Sheet.songs => songsCsv,
  };
}

/// A hash of a text computed a piece at a time ([add]), for the fingerprint of the sheets on the web
/// (`fingerprintInSlices`): `String.hashCode` is a loop over the code units there, a dozen milliseconds for the
/// Songs sheet, too long for one task of the page.
///
/// The same [value] on every platform. Its function is the one dart2js gives `String.hashCode` (a browser test checks
/// they agree under dart2js); the VM and dart2wasm hash otherwise. Nothing relies on that: a fingerprint is never
/// stored, and both sides of every comparison come from the same function (`CatalogueRepository.fingerprint`).
final class TextHash {
  /// The hash of [_text], nothing added yet.
  TextHash(this._text);

  final String _text;
  int _i = 0, _hash = 0;

  /// Adds [units] (at least 1) more code units of the text, or what is left of it. Returns whether there is more to
  /// add.
  bool add(int units) {
    assert(units > 0, 'a step of nothing would never end');
    final text = _text;
    final stop = units >= text.length - _i ? text.length : _i + units;
    var hash = _hash;
    for (var i = _i; i < stop; i++) {
      hash = 0x1fffffff & (hash + text.codeUnitAt(i));
      hash = 0x1fffffff & (hash + ((0x0007ffff & hash) << 10));
      hash ^= hash >> 6;
    }
    _hash = hash;
    _i = stop;
    return stop < text.length;
  }

  /// The hash of the whole text, once [add] returned false.
  int get value {
    if (_i < _text.length) throw StateError('The text is not hashed yet');
    var hash = 0x1fffffff & (_hash + ((0x03ffffff & _hash) << 3));
    hash ^= hash >> 11;
    return 0x1fffffff & (hash + ((0x00003fff & hash) << 15));
  }
}

/// The text of a sheet with the time it was downloaded.
final class CachedSheet {
  /// Bundles the text and its download time.
  const CachedSheet({required this.text, required this.fetchedAt});

  /// The CSV text, as downloaded.
  final String text;

  /// When the download succeeded (UTC); for the daily copy, when the copy was made.
  final DateTime fetchedAt;
}

/// Downloads the sheets.
abstract interface class SheetFetcher {
  /// Downloads [sheet]; throws on any network or HTTP error.
  Future<String> fetch(Sheet sheet);
}

/// Public CSV export (gviz) of the Google spreadsheet.
///
/// `headers=1`: the first row is the header. Left to guess, Google looks at the content of the first rows, and
/// could one day take two of them for the header: neither sheet would then be read. The answers are the same,
/// byte for byte, with and without it (checked in November 2026).
abstract final class SheetUrls {
  static const _base =
      'https://docs.google.com/spreadsheets/d/14ARzE_zSMNhp0ZQV34ti2741PbA-5wAjsXRAW8EgJ-4/gviz/tq?tqx=out:csv&headers=1&sheet=';

  /// "Youtube Catalogue" sheet.
  static final Uri highlights = Uri.parse('${_base}Youtube%20Catalogue');

  /// "Songs" sheet (the Ong Log).
  static final Uri songs = Uri.parse('${_base}Songs');

  /// The address of [sheet].
  static Uri of(Sheet sheet) => switch (sheet) {
    Sheet.highlights => highlights,
    Sheet.songs => songs,
  };
}

/// A non-200 answer of the sheet server.
class SheetHttpException implements Exception {
  /// Creates the exception.
  const SheetHttpException(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode for $uri';
}

/// An answer that is a web page instead of the CSV export: the sign-in page
/// of a Wi-Fi network, or Google's when the spreadsheet is not public. Not a
/// fault of the sheets (a `FormatException` would say so): the next try may
/// well work.
class SheetNotCsvException implements Exception {
  /// Creates the exception.
  const SheetNotCsvException(this.uri);

  final Uri uri;

  @override
  String toString() => 'A web page instead of CSV for $uri';
}

/// [text], the body answered for [uri]; throws a [SheetNotCsvException] when
/// it is a web page.
String sheetCsv(String text, Uri uri) {
  if (text.trimLeft().startsWith('<')) throw SheetNotCsvException(uri);
  return text;
}

/// [SheetFetcher] over HTTP: body decoded as UTF-8 from the bytes whatever the declared charset.
final class HttpSheetFetcher implements SheetFetcher {
  /// Uses [client] (a new one per fetch when null).
  HttpSheetFetcher({
    http.Client? client,
    this.timeout = const Duration(seconds: 45),
    this.maxDuration = const Duration(minutes: 10),
  }) : _client = client;

  final http.Client? _client;

  /// The longest silence of the server: before its answer starts, then between
  /// two pieces of it. Not the time of a whole download: the megabyte of the
  /// Songs sheet takes minutes on a slow connection, and must still arrive.
  final Duration timeout;

  /// The longest a whole download may take.
  final Duration maxDuration;

  @override
  Future<String> fetch(Sheet sheet) async {
    // web, first download of the sheet: the one the page started while the app was loading, if any
    final prefetched = await takePrefetchedSheet(sheet, timeout: timeout).timeout(maxDuration);
    if (prefetched != null) return prefetched;
    final client = _client ?? http.Client();
    try {
      return await getSheetText(client, SheetUrls.of(sheet), timeout).timeout(maxDuration);
    } finally {
      // also ends a download still running after a failure or a timeout
      if (_client == null) client.close();
    }
  }
}

/// The body of [uri] as [HttpSheetFetcher] reads it: UTF-8 from the bytes whatever the declared charset, a
/// [SheetHttpException] for an answer that is not a 200, a [SheetNotCsvException] for a web page. [timeout] is the
/// longest silence of the server ([HttpSheetFetcher.timeout]).
Future<String> getSheetText(http.Client client, Uri uri, Duration timeout) async {
  final response = await client.send(http.Request('GET', uri)).timeout(timeout);
  if (response.statusCode != 200) {
    unawaited(response.stream.listen(null).cancel());
    throw SheetHttpException(uri, response.statusCode);
  }
  // a silence throws into the stream, which toBytes then stops listening to
  final bytes = await http.ByteStream(response.stream.timeout(timeout)).toBytes();
  return sheetCsv(decodeUtf8(bytes), uri);
}
