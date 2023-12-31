import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

bool platformHasScrollbar = kIsWeb || Platform.isWindows || Platform.isMacOS || Platform.isLinux;

class ToggleOptionNotifier extends StateNotifier<bool> {
  String optionName;

  ToggleOptionNotifier(super.initialState, this.optionName) {
    _loadState();
  }

  Future<void> _loadState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(optionName) ?? state;
  }

  void toggle() {
    state = !state;
    _saveState();
  }

  Future<void> _saveState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setBool(optionName, state);
  }
}

typedef DividersOptionNotifier = ToggleOptionNotifier;

final dividersOptionProvider = StateNotifierProvider<DividersOptionNotifier, bool>((ref) => DividersOptionNotifier(true, "dividers"));

class DarkThemeOptionNotifier extends StateNotifier<ThemeMode> {
  DarkThemeOptionNotifier() : super(initialThemeMode()) {
    _loadState();
  }

  static ThemeMode initialThemeMode() {
    final brightness = WidgetsBinding.instance.platformDispatcher.platformBrightness;
    return brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light;
  }

  Future<void> _loadState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? strValue = prefs.getString(runtimeType.toString());
    if (strValue != null) {
      state = strValue == ThemeMode.dark.name ? ThemeMode.dark : ThemeMode.light;
    }
  }

  void switchTheme() {
    state = state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    _saveState();
  }

  Future<void> _saveState() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    prefs.setString(runtimeType.toString(), state.name);
  }

  set themeMode(ThemeMode themeMode) {
    state = themeMode;
    _saveState();
  }

  ThemeMode get themeMode => state;
}

final themeProvider = StateNotifierProvider<DarkThemeOptionNotifier, ThemeMode>((ref) => DarkThemeOptionNotifier());
