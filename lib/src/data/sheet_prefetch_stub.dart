import 'sheets.dart';

/// Native platforms: no page, nothing prefetched.
Future<String?> takePrefetchedSheet(Sheet sheet, {required Duration timeout}) async => null;

/// Native platforms: nothing to forget.
void discardPrefetchedSheets() {}

/// Nothing was started outside a browser.
void discardPrefetchedSnapshot() {}

/// Native platforms: no page, nothing prefetched.
Future<String?> takePrefetchedSnapshotFile(String name, {required Duration timeout}) async => null;
