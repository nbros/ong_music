/// Full screen display of the whole page in a browser: where to offer it, and
/// what the app needs from the browser to drive it. Pure logic, so that it can
/// be tested anywhere; the browser side is `pageFullscreen()` (web platform).
library;

import 'package:flutter/foundation.dart';

import 'install_hint.dart';

/// The browser's full screen mode for the whole page.
abstract interface class PageFullscreen {
  /// Whether the page is full screen now. Follows the browser, not the calls
  /// to [enter] and [exit]: Escape, the browser's own gesture or button, or
  /// the browser refusing all change it.
  ValueListenable<bool> get isFullscreen;

  /// Asks the browser to show the page full screen; completes with false when
  /// the browser refuses. Must be called in a user gesture (tap, key press),
  /// without waiting for anything first: browsers refuse it otherwise.
  Future<bool> enter();

  /// Leaves full screen.
  Future<void> exit();
}

/// Whether to offer full screen in [browser] (null: not a browser, i.e. a
/// native app), whose Fullscreen API for page elements is [enabled]
/// (`document.fullscreenEnabled`, or `webkitFullscreenEnabled` in Safari before
/// 16.4).
///
/// Never once installed (standalone or fullscreen display mode): there is no
/// browser bar to hide. Never on an iPhone or iPod, whose Safari shows only
/// videos full screen, even if it ever reported the API as enabled.
bool offersFullscreen(BrowserEnvironment? browser, {required bool enabled}) {
  if (browser == null || browser.standalone || !enabled) return false;
  final ua = browser.userAgent;
  return !ua.contains('iPhone') && !ua.contains('iPod');
}
