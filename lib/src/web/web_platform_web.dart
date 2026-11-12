import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/services.dart';
import 'package:web/web.dart' as web;

import '../logger.dart';
import 'install_hint.dart';

/// The browser, or null outside a browser (native apps).
BrowserEnvironment? currentBrowser() {
  final navigator = web.window.navigator;
  // navigator.standalone: iOS only, true when launched from the home screen
  final iosStandalone = (navigator as JSObject).getProperty<JSAny?>('standalone'.toJS);
  final standalone =
      (iosStandalone.isA<JSBoolean>() && (iosStandalone as JSBoolean).toDart) ||
      web.window.matchMedia('(display-mode: standalone)').matches ||
      web.window.matchMedia('(display-mode: fullscreen)').matches;
  return BrowserEnvironment(
    userAgent: navigator.userAgent,
    maxTouchPoints: navigator.maxTouchPoints,
    standalone: standalone,
  );
}

/// Registers Roboto Medium (a web-only asset) in the `Roboto` family, next to
/// the Roboto Regular that `flutter build web --no-web-resources-cdn`
/// bundles: without it, every medium (500) text renders as regular.
Future<void> loadWebFonts() async {
  try {
    await (FontLoader('Roboto')..addFont(rootBundle.load('assets/fonts/Roboto-Medium.ttf'))).load();
  } catch (e) {
    logger.w('Cannot load Roboto Medium', error: e);
  }
}

@JS('Date')
extension type _JsDate._(JSObject _) implements JSObject {
  external factory _JsDate(int year, int monthIndex, int day, int hours);
  external String toLocaleTimeString();
}

/// Whether the browser shows times on a 24-hour clock, from how it writes
/// 1 pm in its own locale ("13:00:00" or "1:00:00 PM"). Flutter has no such
/// setting on web and would always use AM/PM. Null when it cannot tell.
bool? browserUses24HourClock() {
  try {
    return _JsDate(2020, 0, 1, 13).toLocaleTimeString().contains('13');
  } catch (e) {
    logger.w('Cannot read the clock format of the browser', error: e);
    return null;
  }
}

/// Whether the page is hidden right now (a tab opened behind another one).
bool pageIsHidden() => web.document.hidden;

String _hex(Color color) => '#${(color.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

/// Colours the browser bars (theme-color) and the page behind the app with
/// the app theme, which may differ from the system one (theme setting).
///
/// Every theme-color tag gets the colour: the two of index.html (one per
/// system theme) and the engine's own (`#flutterweb-theme`, written by the
/// `Title` of `MaterialApp`, transparent here), which would win otherwise.
void setBrowserTheme({required Color background, required bool dark}) {
  final document = web.document;
  final color = _hex(background);
  final metas = document.querySelectorAll('meta[name="theme-color"]');
  for (var i = 0; i < metas.length; i++) {
    final meta = metas.item(i) as web.HTMLMetaElement?;
    meta?.removeAttribute('media');
    meta?.content = color;
  }
  (document.querySelector('meta[name="color-scheme"]') as web.HTMLMetaElement?)?.content = dark ? 'dark' : 'light';
  final root = document.documentElement as web.HTMLElement?;
  root?.setAttribute('data-theme', dark ? 'dark' : 'light');
  root?.style.backgroundColor = color;
}
