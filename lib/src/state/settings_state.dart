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

import '../data/model.dart';
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

/// The user's Twitch name (trimmed), empty when not set. Used to highlight
/// their name in their own requests.
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

/// The keys (`Highlight.key`) of the user's favourite highlights, in the order
/// they were added. Keys of highlights absent from the current catalogue stay:
/// the highlight may come back with a later refresh.
final favouritesProvider = NotifierProvider<FavouritesNotifier, Set<String>>(FavouritesNotifier.new);

/// Persists the favourites under [key], a list of `Highlight.key`.
class FavouritesNotifier extends Notifier<Set<String>> {
  /// Preference key.
  static const key = 'favouriteHighlights';

  /// The writes still to do, one after the other.
  Future<void> _writes = Future.value();
  int _pending = 0;

  @override
  Set<String> build() => _stored(ref.watch(sharedPreferencesProvider));

  static Set<String> _stored(SharedPreferences prefs) {
    try {
      return Set.unmodifiable(prefs.getStringList(key) ?? const <String>[]);
    } catch (e, st) {
      // something else than a list of strings under the key: none, until the next star replaces it
      logger.w('Unreadable favourites', error: e, stackTrace: st);
      return const {};
    }
  }

  /// Adds [highlight] to the favourites, or removes it, and persists the list.
  ///
  /// The star changes at once. The list is then read again from the storage
  /// before the change is written to it: another tab of the browser may have
  /// added favourites since this one read them, which writing this tab's own
  /// list would erase. Not so on Windows, where the plugin never reads its
  /// file again: two instances of the app overwrite each other's settings.
  Future<void> toggle(Highlight highlight) {
    final k = highlight.key;
    final add = !state.contains(k);
    state = Set.unmodifiable(add ? {...state, k} : ({...state}..remove(k)));
    final prefs = ref.read(sharedPreferencesProvider);
    _pending++;
    return _writes = _writes.then((_) async {
      try {
        await prefs.reload();
        final merged = add ? {..._stored(prefs), k} : ({..._stored(prefs)}..remove(k));
        // false, not an exception, when the platform could not write
        if (!await prefs.setStringList(key, merged.toList())) logger.w('The favourites were not stored');
        // what the other windows added shows here too, once no later change of this one waits
        if (--_pending == 0 && ref.mounted) state = Set.unmodifiable(merged);
      } catch (e, st) {
        _pending--;
        // kept in memory for this session
        logger.w('Cannot store the favourites', error: e, stackTrace: st);
      }
    });
  }
}
