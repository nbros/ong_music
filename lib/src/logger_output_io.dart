import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

/// The log file starts again from empty beyond this size.
const int maxLogFileBytes = 256 * 1024;

/// Debug builds log to the console; release builds to a file:
/// Windows: `C:\Users\%username%\AppData\Roaming\nbros\ong_music\ong_music.log`,
/// Android: `/data/user/0/nbros.ong_music/files/ong_music.log`.
Future<LogOutput> createLogOutput() async {
  if (kDebugMode) return ConsoleOutput();
  final dir = await getApplicationSupportDirectory();
  return FileOutput(file: await openLogFile(File(join(dir.path, 'ong_music.log'))));
}

/// [file], emptied first when it has grown beyond [maxLogFileBytes]: the app
/// appends a few lines at each start and never reads them back, so the file
/// would otherwise grow for as long as the app is installed.
Future<File> openLogFile(File file) async {
  try {
    if (await file.exists() && await file.length() > maxLogFileBytes) await file.delete();
  } on FileSystemException {
    // keep appending
  }
  return file;
}

/// ANSI colours only make sense in a debug terminal.
const bool logColors = kDebugMode;
