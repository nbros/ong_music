import 'dart:ui' show Color;

import 'install_hint.dart';

/// The browser, or null outside a browser (native apps).
BrowserEnvironment? currentBrowser() => null;

/// Registers the fonts that the web build needs and does not get by itself.
Future<void> loadWebFonts() async {}

/// Whether the browser shows times on a 24-hour clock; null outside a browser,
/// where the system tells Flutter itself.
bool? browserUses24HourClock() => null;

/// Colours the browser bars (theme-color) and the page behind the app.
void setBrowserTheme({required Color background, required bool dark}) {}
