import 'sheet_prefetch.dart';
import 'sheets.dart';

/// Native platforms: no page, nothing prefetched.
Future<RawSheets?> takePrefetchedSheets({required Duration timeout}) async => null;

/// Native platforms: nothing to forget.
void discardPrefetchedSheets() {}

/// Nothing was started outside a browser.
void discardPrefetchedSnapshot() {}

/// Native platforms: no page, nothing prefetched.
Future<SnapshotTexts?> takePrefetchedSnapshot({required Duration timeout}) async => null;
