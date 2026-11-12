import 'package:args/args.dart';
import 'package:logger/logger.dart';

import 'logger_output_web.dart' if (dart.library.io) 'logger_output_io.dart';

/// The app logger. Usable before [configureLogger] (console, info level), so
/// that code running in tests or before `main` finishes can log safely.
Logger logger = Logger(printer: SimplePrinter(colors: false), filter: ProductionFilter(), output: ConsoleOutput());

/// Configures [logger]: level from the command line argument `--log=<level>`
/// (`-log=<level>` is accepted too; trace, debug, info, warning, error, fatal,
/// off; default info), output to the
/// console in debug builds and on web, to a file in native release builds.
Future<void> configureLogger(List<String> arguments) async {
  String? logArg;
  try {
    final parser = ArgParser()..addOption('log');
    // package:args reads "-log=x" as the short options l, o, g: accept that documented form
    final normalized = [for (final a in arguments) a.startsWith('-log=') ? '-$a' : a];
    logArg = (parser.parse(normalized)['log'] as String?)?.toLowerCase();
  } on FormatException {
    // unknown arguments: keep the default level
  }
  Logger.level = Level.values.firstWhere((level) => level.name.toLowerCase() == logArg, orElse: () => Level.info);

  // print formatted logs
  final printer = PrettyPrinter(
    methodCount: 0,
    excludeBox: {Level.trace: true, Level.debug: true, Level.info: true, Level.warning: true},
    dateTimeFormat: DateTimeFormat.dateAndTime,
    colors: logColors,
  );
  final LogOutput output;
  try {
    output = await createLogOutput();
  } catch (e) {
    logger.w('Cannot open the log file, logging to the console: $e');
    logger = Logger(printer: printer, filter: ProductionFilter(), output: ConsoleOutput());
    return;
  }
  logger = Logger(printer: printer, filter: ProductionFilter(), output: output);
}
