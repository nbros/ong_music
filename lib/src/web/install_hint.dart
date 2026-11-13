/// Whether and how to tell the user to install the web app on an iPhone or
/// iPad, where the browser never offers it by itself, or the Android app on
/// Android. Pure logic over what the browser reports, so that it can be tested
/// anywhere.
library;

import 'package:flutter/foundation.dart';

/// What the browser tells about itself (see `currentBrowser()`).
@immutable
class BrowserEnvironment {
  const BrowserEnvironment({
    required this.userAgent,
    required this.maxTouchPoints,
    required this.standalone,
    this.platform = '',
    this.clientHintsPlatform,
  });

  /// `navigator.userAgent`.
  final String userAgent;

  /// `navigator.platform` (`Linux armv81`, `MacIntel`, `Win32`): the system
  /// the browser was built for, which a browser asking for desktop sites
  /// leaves as it is.
  final String platform;

  /// `navigator.userAgentData.platform` (`Android`, `Linux`, `Chrome OS`,
  /// `Windows`, `macOS`), in the browsers that give it (Chromium-based ones);
  /// null elsewhere.
  final String? clientHintsPlatform;

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

/// Where Safari keeps "Share", the way to "Add to Home Screen".
enum SafariShare {
  /// A Share button in Safari's own bar: before Safari 26.
  inBar,

  /// Behind the More button (three dots) next to the address: Safari 26.
  behindMore,

  /// Behind the menu button (three lines) next to the address: Safari 27 and
  /// later.
  behindMenu,
}

/// The install advice for one device.
@immutable
class InstallHint {
  const InstallHint(this.kind, {this.device = 'iPhone', this.share = SafariShare.behindMenu});

  /// Nothing to show.
  static const none = InstallHint(InstallHintKind.none);

  final InstallHintKind kind;

  /// "iPhone" or "iPad", for the text ("Android" for [InstallHintKind.playStore]).
  final String device;

  /// For [InstallHintKind.addToHomeScreen]: where the Safari of the device
  /// keeps "Share". The latest known place when the version cannot be told.
  final SafariShare share;

  /// Whether there is something to show.
  bool get isVisible => kind != InstallHintKind.none;

  @override
  bool operator ==(Object other) =>
      other is InstallHint && other.kind == kind && other.device == device && other.share == share;

  @override
  int get hashCode => Object.hash(kind, device, share);

  @override
  String toString() => 'InstallHint($kind, $device, ${share.name})';
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

/// User agent tokens of systems that say "Android" and have no Google Play:
/// Amazon's Fire tablets (Silk browser), Huawei's HarmonyOS and its phones
/// without Google services, KaiOS.
const List<String> noGooglePlayTokens = ['Silk/', 'HarmonyOS', 'OpenHarmony', 'HMSCore', 'KAIOS'];

/// The install advice for [browser] (null: not a browser, i.e. a native app).
///
/// On Android (the `Android` token, which every Android browser and web view
/// sends, and no iOS one does): the Android app. Its "desktop site" mode
/// sends a Linux or Windows user agent instead: nothing then. Nor where there
/// is no Google Play ([noGooglePlayTokens]).
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
    return noGooglePlayTokens.any(ua.contains)
        ? InstallHint.none
        : const InstallHint(InstallHintKind.playStore, device: 'Android');
  }
  final String device;
  if (ua.contains('iPhone') || ua.contains('iPod')) {
    device = 'iPhone';
  } else if (isIPad(browser)) {
    device = 'iPad';
  } else {
    return InstallHint.none;
  }
  final inApp = !ua.contains('Safari/') || inAppBrowserTokens.any(ua.contains);
  if (inApp) return InstallHint(InstallHintKind.openInSafari, device: device);
  return InstallHint(InstallHintKind.addToHomeScreen, device: device, share: _safariShare(ua));
}

/// Whether [browser] runs on Android, including a browser asking for desktop
/// sites (Chrome's "Desktop site", the default on large tablets), which sends
/// the user agent of a Linux computer (`X11; Linux x86_64`) without the
/// `Android` token.
///
/// In this order of trust: the client hints, where the browser gives them
/// (Chromium-based browsers keep `Android` there; another system named there
/// is not Android); the `Android` token; then a Linux user agent from a
/// browser built for ARM (`navigator.platform` `Linux armv…` or
/// `Linux aarch64`) on a touch screen. A Linux or Windows laptop with a touch
/// screen and a Linux computer without one are not Android; nor is a
/// Chromebook, whose user agent says `CrOS`, never `Linux`, and whose client
/// hints say `Chrome OS`.
bool isAndroid(BrowserEnvironment browser) {
  final hinted = browser.clientHintsPlatform;
  if (hinted == 'Android') return true;
  final ua = browser.userAgent;
  if (ua.contains('Android')) return true;
  // a computer that says what it is
  if (hinted != null && hinted.isNotEmpty && hinted != 'Linux') return false;
  if (!ua.contains('Linux') || browser.maxTouchPoints == 0) return false;
  final platform = browser.platform.toLowerCase();
  return platform.contains('arm') || platform.contains('aarch64');
}

/// Whether [browser] is on an iPad, including an iPad whose Safari asks for
/// desktop sites and claims to be a Mac: a Mac has no touch screen.
bool isIPad(BrowserEnvironment browser) {
  final ua = browser.userAgent;
  return ua.contains('iPad') || (ua.contains('Macintosh') && browser.maxTouchPoints > 1);
}

/// Where the Safari of the device whose browser sends [ua] keeps "Share".
///
/// Safari says its version in `Version/26.0`. Other browsers (Chrome, Firefox)
/// only give the system version, in `OS 18_5`: it tells an older Safari apart
/// up to 18.5 only, as Safari 26 and later all say `OS 18_6`, and so may these
/// browsers.
SafariShare _safariShare(String ua) {
  final safari = int.tryParse(_safariVersion.firstMatch(ua)?[1] ?? '');
  if (safari != null) {
    if (safari < 26) return SafariShare.inBar;
    return safari == 26 ? SafariShare.behindMore : SafariShare.behindMenu;
  }
  final system = _systemVersion.firstMatch(ua);
  if (system != null) {
    final major = int.parse(system[1]!), minor = int.parse(system[2]!);
    if (major < 18 || (major == 18 && minor < 6)) return SafariShare.inBar;
    if (major == 26) return SafariShare.behindMore;
  }
  return SafariShare.behindMenu;
}

final _safariVersion = RegExp(r'Version/(\d+)');

// "CPU iPhone OS 18_5" or "CPU OS 17_7" (iPad); not the "Mac OS X 10_15_7" of an iPad asking for desktop sites
final _systemVersion = RegExp(r'OS (\d{1,3})_(\d{1,3})');
