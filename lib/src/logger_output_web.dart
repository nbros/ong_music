import 'package:logger/logger.dart';

/// Web: the browser console (no file system).
Future<LogOutput> createLogOutput() async => ConsoleOutput();

/// The browser console does not render ANSI colours.
const bool logColors = false;
