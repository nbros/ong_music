import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final expandOptionProvider = StateNotifierProvider<ExpandOptionNotifier, bool>((ref) => ExpandOptionNotifier());

class ExpandOptionNotifier extends StateNotifier<bool> {
  ExpandOptionNotifier() : super(true);
  void toggle() {
    state = !state;
  }
}

final themeProvider = StateNotifierProvider<DarkThemeOptionNotifier, ThemeMode>((ref) => DarkThemeOptionNotifier());

class DarkThemeOptionNotifier extends StateNotifier<ThemeMode> {
  DarkThemeOptionNotifier() : super(ThemeMode.system);
  void switchTheme() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
  }

  set themeMode(ThemeMode themeMode) {
    state = themeMode;
  }
}
