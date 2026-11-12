/// Downloading the raw CSV text of the two sheets.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'sheet_prefetch.dart';

/// Tells whether two downloads have the same content, without keeping the
/// megabytes of text around: lengths and `String.hashCode` of both sheets.
/// Only comparable within one run of the app.
typedef SheetsFingerprint = ({int highlightsLength, int highlightsHash, int songsLength, int songsHash});

/// The raw CSV text of both sheets, as downloaded.
final class RawSheets {
  /// Bundles the two payloads.
  const RawSheets({required this.highlightsCsv, required this.songsCsv});

  /// "Youtube Catalogue" sheet.
  final String highlightsCsv;

  /// "Songs" sheet (the Ong Log).
  final String songsCsv;

  /// See [SheetsFingerprint].
  SheetsFingerprint get fingerprint => (
    highlightsLength: highlightsCsv.length,
    highlightsHash: highlightsCsv.hashCode,
    songsLength: songsCsv.length,
    songsHash: songsCsv.hashCode,
  );

  /// The record form taken by `parseCatalogueRecord`.
  ({String highlightsCsv, String songsCsv}) toRecord() => (highlightsCsv: highlightsCsv, songsCsv: songsCsv);
}

/// [RawSheets] with the time they were downloaded.
final class CachedSheets {
  /// Bundles sheets and download time.
  const CachedSheets({required this.sheets, required this.fetchedAt});

  final RawSheets sheets;

  /// When the download succeeded (UTC).
  final DateTime fetchedAt;
}

/// Downloads both sheets.
abstract interface class SheetFetcher {
  /// Downloads both sheets; throws on any network or HTTP error.
  Future<RawSheets> fetch();
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

/// [SheetFetcher] over HTTP: both sheets in parallel, body decoded as UTF-8
/// from the bytes whatever the declared charset.
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
  Future<RawSheets> fetch() async {
    // web, first download: the one the page started while the app was loading, if any
    final prefetched = await takePrefetchedSheets(timeout: timeout).timeout(maxDuration);
    if (prefetched != null) return prefetched;
    final client = _client ?? http.Client();
    try {
      final results = await Future.wait([
        _get(client, SheetUrls.highlights),
        _get(client, SheetUrls.songs),
      ]).timeout(maxDuration);
      return RawSheets(highlightsCsv: results[0], songsCsv: results[1]);
    } finally {
      // also ends the downloads still running after a failure or a timeout
      if (_client == null) client.close();
    }
  }

  Future<String> _get(http.Client client, Uri uri) async {
    final response = await client.send(http.Request('GET', uri)).timeout(timeout);
    if (response.statusCode != 200) {
      unawaited(response.stream.listen(null).cancel());
      throw SheetHttpException(uri, response.statusCode);
    }
    // a silence throws into the stream, which toBytes then stops listening to
    final bytes = await http.ByteStream(response.stream.timeout(timeout)).toBytes();
    return sheetCsv(utf8.decode(bytes, allowMalformed: true), uri);
  }
}
