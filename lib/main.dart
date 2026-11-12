import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/logger.dart';
import 'src/state/settings_state.dart';
import 'src/ui/app.dart';
import 'src/web/web_platform.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await configureLogger(arguments);
  logUncaughtErrors();
  logger.i('Starting Ong Music');
  if (!kIsWeb) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final (prefs, _) = await (loadPreferences(), loadWebFonts()).wait;
  runApp(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)], child: const OngMusicApp()));
}

/// Sends the errors nobody caught to the log (a file in native release builds,
/// where the console is not seen): errors of the framework (build, layout,
/// paint, gestures; the default handling, a console dump, still follows) and
/// asynchronous errors that reach the root zone. The app goes on running.
void logUncaughtErrors() {
  final presentError = FlutterError.onError;
  FlutterError.onError = (details) {
    _logError('Flutter error', details.exception, details.stack);
    presentError?.call(details);
  };
  PlatformDispatcher.instance.onError = (error, stack) {
    _logError('Uncaught error', error, stack);
    return true;
  };
}

void _logError(String message, Object error, StackTrace? stack) {
  try {
    logger.e(message, error: error, stackTrace: stack);
  } catch (_) {
    // the log itself is broken: nothing better to do
  }
}
