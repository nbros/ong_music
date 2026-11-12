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
  logger.i('Starting Ong Music');
  if (!kIsWeb) await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  final (prefs, _) = await (loadPreferences(), loadWebFonts()).wait;
  runApp(ProviderScope(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)], child: const OngMusicApp()));
}
