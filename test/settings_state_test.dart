import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' show ThemeMode;
import 'package:ong_music/src/state/settings_state.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  Future<(ProviderContainer, SharedPreferences)> withPrefs(Map<String, Object> values) async {
    SharedPreferences.setMockInitialValues(values);
    final prefs = await SharedPreferences.getInstance();
    return (ProviderContainer.test(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]), prefs);
  }

  group('storage', () {
    test('settings live in memory when the platform refuses storage', () async {
      SharedPreferences.setMockInitialValues({'themeMode': 'dark'});
      var attempts = 0;
      final prefs = await loadPreferences(
        open: () {
          attempts++;
          // what a browser with site data blocked does (a JavaScript error, not an Exception)
          throw StateError('SecurityError: The operation is insecure.');
        },
      );
      expect(attempts, 1);
      expect(prefs.getKeys(), isEmpty, reason: 'a fresh store, not the one that failed');
      final c = ProviderContainer.test(overrides: [sharedPreferencesProvider.overrideWithValue(prefs)]);
      expect(c.read(themePreferenceProvider), ThemePreference.system);
      await c.read(themePreferenceProvider.notifier).set(ThemePreference.dark);
      expect(c.read(themePreferenceProvider), ThemePreference.dark);
    });

    test('opens the stored settings otherwise', () async {
      SharedPreferences.setMockInitialValues({'themeMode': 'dark'});
      final prefs = await loadPreferences();
      expect(prefs.getString('themeMode'), 'dark');
    });
  });

  group('theme', () {
    test('defaults to system', () async {
      final (c, _) = await withPrefs({});
      expect(c.read(themePreferenceProvider), ThemePreference.system);
      expect(ThemePreference.system.themeMode, ThemeMode.system);
    });

    for (final legacy in ['dark', 'light']) {
      test('adopts the legacy "$legacy" value', () async {
        final (c, prefs) = await withPrefs({'DarkThemeOptionNotifier': legacy});
        expect(c.read(themePreferenceProvider).name, legacy);
        expect(prefs.getString('themeMode'), legacy);
      });
    }

    test('ignores an unknown legacy value', () async {
      final (c, _) = await withPrefs({'DarkThemeOptionNotifier': 'purple'});
      expect(c.read(themePreferenceProvider), ThemePreference.system);
    });

    test('the new key wins over the legacy one', () async {
      final (c, _) = await withPrefs({'DarkThemeOptionNotifier': 'dark', 'themeMode': 'system'});
      expect(c.read(themePreferenceProvider), ThemePreference.system);
    });

    test('set persists', () async {
      final (c, prefs) = await withPrefs({});
      await c.read(themePreferenceProvider.notifier).set(ThemePreference.dark);
      expect(c.read(themePreferenceProvider), ThemePreference.dark);
      expect(prefs.getString('themeMode'), 'dark');
      final (c2, _) = await withPrefs({'themeMode': 'dark'});
      expect(c2.read(themePreferenceProvider), ThemePreference.dark);
    });
  });

  group('Twitch name', () {
    test('empty by default; set trims and persists; blank clears', () async {
      final (c, prefs) = await withPrefs({});
      expect(c.read(twitchNameProvider), '');
      expect(c.read(myRequesterKeyProvider), '');
      await c.read(twitchNameProvider.notifier).set('  Élodie_42 ');
      expect(c.read(twitchNameProvider), 'Élodie_42');
      expect(c.read(myRequesterKeyProvider), 'elodie_42');
      expect(prefs.getString('twitchName'), 'Élodie_42');
      await c.read(twitchNameProvider.notifier).set('   ');
      expect(c.read(twitchNameProvider), '');
      expect(prefs.containsKey('twitchName'), isFalse);
    });

    test('is read back', () async {
      final (c, _) = await withPrefs({'twitchName': 'Alinsa'});
      expect(c.read(myRequesterKeyProvider), 'alinsa');
    });
  });
}
