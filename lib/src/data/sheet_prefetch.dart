/// The sheets download that `web/index.html` starts while the web app loads,
/// when the cache is missing or stale (first visit): the app takes it instead
/// of starting its own, a second or more later.
library;

import 'sheets.dart';

import 'sheet_prefetch_stub.dart' if (dart.library.js_interop) 'sheet_prefetch_web.dart' as platform;

/// The sheets downloaded by the page, or null when it started no download
/// (cache fresh, not on the web) or when they were already taken: only the first
/// call can return them. Throws like [HttpSheetFetcher.fetch] when that download
/// failed.
Future<RawSheets?> takePrefetchedSheets() => platform.takePrefetchedSheets();
