/// Whether and how to tell the user to install the web app on an iPhone or
/// iPad, where the browser never offers it by itself, or the Android app on
/// Android. Pure logic over what the browser reports, so that it can be tested
/// anywhere.
library;

import 'package:flutter/foundation.dart';

/// What the browser tells about itself (see `currentBrowser()`).
@immutable
class BrowserEnvironment {
  const BrowserEnvironment({required this.userAgent, required this.maxTouchPoints, required this.standalone});

  /// `navigator.userAgent`.
  final String userAgent;

  /// `navigator.maxTouchPoints`: tells an iPad (whose Safari claims to be a
  /// Mac) from a Mac.
  final int maxTouchPoints;

  /// Launched from the home screen: `navigator.standalone` (iOS), or the
  /// `standalone` / `fullscreen` display mode.
  final bool standalone;
}

/// The advice to show.
enum InstallHintKind {
  /// Nothing: native app, installed web app, desktop.
  none,

  /// A browser that can add to the home screen: Share → Add to Home Screen.
  addToHomeScreen,

  /// The web view of another app (Instagram, Facebook, …), which cannot add
  /// to the home screen: open the page in Safari first.
  openInSafari,

  /// A browser on Android (any, including the web view of another app): the
  /// Android app on Google Play.
  playStore,
}

/// The install advice for one device.
@immutable
class InstallHint {
  const InstallHint(this.kind, {this.device = 'iPhone'});

  /// Nothing to show.
  static const none = InstallHint(InstallHintKind.none);

  final InstallHintKind kind;

  /// "iPhone" or "iPad", for the text ("Android" for [InstallHintKind.playStore]).
  final String device;

  /// Whether there is something to show.
  bool get isVisible => kind != InstallHintKind.none;

  @override
  bool operator ==(Object other) => other is InstallHint && other.kind == kind && other.device == device;

  @override
  int get hashCode => Object.hash(kind, device);

  @override
  String toString() => 'InstallHint($kind, $device)';
}

/// User agent tokens of in-app browsers that are known to be web views
/// (no "Add to Home Screen"), even when they also say "Safari".
const List<String> inAppBrowserTokens = [
  'FBAN/', 'FBAV/', 'FB_IAB/', // Facebook, Messenger
  'Instagram', 'LinkedInApp', 'Snapchat', 'Pinterest',
  ' Line/', 'KAKAOTALK', 'MicroMessenger', // LINE, KakaoTalk, WeChat
  'musical_ly', 'BytedanceWebview', 'TikTok', // TikTok
  'GSA/', // Google app
];

/// The install advice for [browser] (null: not a browser, i.e. a native app).
///
/// On Android (the `Android` token, which every Android browser and web view
/// sends, and no iOS one does): the Android app. Its "desktop site" mode
/// sends a Linux or Windows user agent instead: nothing then. Nor on Amazon's
/// Fire tablets (Silk browser), which have no Google Play.
///
/// Otherwise shown only on iPhone and iPad (including an iPad whose Safari asks
/// for desktop sites and claims to be a Mac). Never once installed. In a web
/// view of another app: "open in Safari", when that can be told reliably, from a
/// known in-app token or the missing `Safari/` token (iOS browsers and Safari
/// view controllers all send it, plain web views do not). Other in-app
/// browsers look exactly like Safari: they get the normal advice, whose text
/// mentions Safari for that case.
InstallHint installHintFor(BrowserEnvironment? browser) {
  if (browser == null || browser.standalone) return InstallHint.none;
  final ua = browser.userAgent;
  if (ua.contains('Android')) {
    return ua.contains('Silk/') ? InstallHint.none : const InstallHint(InstallHintKind.playStore, device: 'Android');
  }
  final String device;
  if (ua.contains('iPhone') || ua.contains('iPod')) {
    device = 'iPhone';
  } else if (ua.contains('iPad') || (ua.contains('Macintosh') && browser.maxTouchPoints > 1)) {
    device = 'iPad';
  } else {
    return InstallHint.none;
  }
  final inApp = !ua.contains('Safari/') || inAppBrowserTokens.any(ua.contains);
  return InstallHint(inApp ? InstallHintKind.openInSafari : InstallHintKind.addToHomeScreen, device: device);
}
