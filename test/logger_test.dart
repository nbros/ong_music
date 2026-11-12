import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:ong_music/src/logger.dart';
import 'package:ong_music/src/logger_output_io.dart';

void main() {
  test('the log level comes from --log=<level> or -log=<level>', () async {
    await configureLogger(['-log=debug']);
    expect(Logger.level, Level.debug);
    await configureLogger(['--log=WARNING']);
    expect(Logger.level, Level.warning);
    await configureLogger(['--some-unknown-flag']);
    expect(Logger.level, Level.info);
    await configureLogger([]);
    expect(Logger.level, Level.info);
  });

  test('the log file starts again from empty once it is too large', () async {
    final dir = await Directory.systemTemp.createTemp('ong_music_log_test');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/ong_music.log');
    // missing: left alone
    expect((await openLogFile(file)).existsSync(), isFalse);
    // small: kept
    file.writeAsStringSync('a few lines');
    await openLogFile(file);
    expect(file.readAsStringSync(), 'a few lines');
    // too large: removed, the logger creates it again
    file.writeAsBytesSync(List.filled(maxLogFileBytes + 1, 0x61));
    await openLogFile(file);
    expect(file.existsSync(), isFalse);
  });
}
