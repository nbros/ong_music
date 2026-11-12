import 'sheet_cache.dart';

/// Platforms with neither `dart:io` nor JS interop: no cache.
SheetCache createPlatformSheetCache() => const NoSheetCache();
