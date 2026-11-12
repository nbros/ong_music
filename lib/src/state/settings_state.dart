/// User settings persisted with `shared_preferences` (works on web too).
///
/// [sharedPreferencesProvider] must be overridden at startup:
/// ```dart
/// final prefs = await loadPreferences();
/// runApp(ProviderScope(
///   overrides: [sharedPreferencesProvider.overrideWithValue(prefs)],
///   child: const App(),
/// ));
/// ```
/// so that settings are read synchronously (no theme flash on start).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:shared_preferences/shared_preferences.dart';

import '../data/text.dart';
import '../logger.dart';

/// Opens the stored settings.
///
/// A browser may refuse storage altogether (site data blocked, "Block All
/// Cookies" in Safari): the settings then live in memory for this visit instead
/// of keeping the app from starting. [open] is replaced in tests.
Future<SharedPreferences> loadPreferences({
  Future<SharedPreferences> Function() open = SharedPreferences.getInstance,
}) async {
  try {
    return await open();
  } catch (e, st) {
    logger.w('Settings storage is unavailable: settings are kept in memory', error: e, stackTrace: st);
    // the only way to replace the store and forget the failed attempt
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    return SharedPreferences.getInstance();
  }
}

/// The loaded preferences; override it with the instance from
/// [loadPreferences].
final sharedPreferencesProvider = Provider<SharedPreferences>(
  (ref) => throw UnimplementedError('Override sharedPreferencesProvider with SharedPreferences.getInstance()'),
);

/// Theme setting.
enum ThemePreference {
  system(ThemeMode.system),
  light(ThemeMode.light),
  dark(ThemeMode.dark);

  const ThemePreference(this.themeMode);

  /// For `MaterialApp.themeMode`.
  final ThemeMode themeMode;
}

/// The theme setting, [ThemePreference.system] by default.
final themePreferenceProvider = NotifierProvider<ThemePreferenceNotifier, ThemePreference>(ThemePreferenceNotifier.new);

/// Persists [ThemePreference] under [key]. On first use, adopts the value of
/// the previous app versions (key [legacyKey], `dark` or `light`).
class ThemePreferenceNotifier extends Notifier<ThemePreference> {
  /// Preference key.
  static const key = 'themeMode';

  /// Key used before the redesign (the runtime type name of its notifier).
  static const legacyKey = 'DarkThemeOptionNotifier';

  @override
  ThemePreference build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    final stored = _parse(prefs.getString(key));
    if (stored != null) return stored;
    final legacy = prefs.getString(legacyKey);
    if (legacy == 'dark' || legacy == 'light') {
      final adopted = _parse(legacy)!;
      prefs.setString(key, adopted.name);
      return adopted;
    }
    return ThemePreference.system;
  }

  static ThemePreference? _parse(String? value) {
    for (final p in ThemePreference.values) {
      if (p.name == value) return p;
    }
    return null;
  }

  /// Changes and persists the setting.
  Future<void> set(ThemePreference value) async {
    state = value;
    await ref.read(sharedPreferencesProvider).setString(key, value.name);
  }
}

/// The user's Twitch name (trimmed), empty when not set. Used to badge their
/// own requests.
final twitchNameProvider = NotifierProvider<TwitchNameNotifier, String>(TwitchNameNotifier.new);

/// Persists the Twitch name under [key].
class TwitchNameNotifier extends Notifier<String> {
  /// Preference key.
  static const key = 'twitchName';

  @override
  String build() => ref.watch(sharedPreferencesProvider).getString(key) ?? '';

  /// Changes and persists the name; an empty (or blank) one clears it.
  Future<void> set(String name) async {
    final value = name.trim();
    state = value;
    final prefs = ref.read(sharedPreferencesProvider);
    if (value.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setString(key, value);
    }
  }
}

/// The folded Twitch name, empty when not set: compare it with
/// `Requester.folded`, or pass it to `Catalogue.isRequester`.
final myRequesterKeyProvider = Provider<String>((ref) => fold(ref.watch(twitchNameProvider)));
