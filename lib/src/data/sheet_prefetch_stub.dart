import 'sheets.dart';

/// Native platforms: no page, nothing prefetched.
Future<RawSheets?> takePrefetchedSheets() async => null;

/// Native platforms: nothing to forget.
void discardPrefetchedSheets() {}
