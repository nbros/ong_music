import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:ong_music/main.dart';
import 'package:ong_music/src/logger.dart';

/// Keeps the lines logged.
class _MemoryOutput extends LogOutput {
  final lines = <String>[];

  @override
  void output(OutputEvent event) => lines.addAll(event.lines);
}

void main() {
  test('uncaught errors go to the log, and count as handled', () {
    final previousLogger = logger;
    final previousFlutterOnError = FlutterError.onError;
    final previousPlatformOnError = PlatformDispatcher.instance.onError;
    final presented = <FlutterErrorDetails>[];
    FlutterError.onError = presented.add;
    addTearDown(() {
      logger = previousLogger;
      FlutterError.onError = previousFlutterOnError;
      PlatformDispatcher.instance.onError = previousPlatformOnError;
    });
    final output = _MemoryOutput();
    logger = Logger(printer: SimplePrinter(colors: false), filter: ProductionFilter(), output: output);

    logUncaughtErrors();
    FlutterError.onError!(FlutterErrorDetails(exception: StateError('build failed')));
    expect(output.lines.join('\n'), allOf(contains('Flutter error'), contains('build failed')));
    expect(presented, hasLength(1), reason: 'the default handling still follows');

    output.lines.clear();
    expect(PlatformDispatcher.instance.onError!(StateError('async failure'), StackTrace.empty), isTrue);
    expect(output.lines.join('\n'), allOf(contains('Uncaught error'), contains('async failure')));
  });
}
