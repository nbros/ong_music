import 'data_files.dart';

/// Platforms with neither `dart:io` nor JS interop: no cache.
DataFileCache createPlatformDataFileCache() => const NoDataFileCache();
