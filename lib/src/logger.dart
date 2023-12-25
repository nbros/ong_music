import 'dart:io';

import 'package:args/args.dart';
import 'package:flutter/foundation.dart';
import 'package:logger/logger.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';

late final Logger logger;

// initialize the logger
Future<void> configureLogger(List<String> arguments) async {
  // take the log level from the command line argument "-log=<level>"
  final parser = ArgParser()..addOption('log');
  final args = parser.parse(arguments);
  final String? logArg = args['log'];
  Logger.level = Level.values.firstWhere(
    (level) => level.name.toLowerCase() == logArg,
    orElse: () => Level.info,
  );

  // print formatted logs
  final printer = PrettyPrinter(
    methodCount: 0,
    excludeBox: {Level.trace: true, Level.debug: true, Level.info: true, Level.warning: true},
    printTime: true,
    colors: kDebugMode,
  );
  // only log in debug mode if '-log' is not provided
  // final logFilter = logArg == null ? DevelopmentFilter() : ProductionFilter();
  final LogOutput output;
  if (kDebugMode) {
    output = ConsoleOutput();
  } else {
    // log goes into:
    // Windows: C:\Users\%username%\AppData\Roaming\nbros\ong_music\ong_music.log
    // Android: /data/user/0/nbros.ong_music/files
    final dir = await getApplicationSupportDirectory();
    output = FileOutput(file: File(join(dir.path, 'ong_music.log')));
  }

  logger = Logger(printer: printer, filter: ProductionFilter(), output: output);
}
