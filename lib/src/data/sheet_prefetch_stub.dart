import 'sheets.dart';

/// Native platforms: no page, nothing prefetched.
Future<RawSheets?> takePrefetchedSheets({required Duration timeout}) async => null;

/// Native platforms: nothing to forget.
void discardPrefetchedSheets() {}
