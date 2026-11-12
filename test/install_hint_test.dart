import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/web/install_hint.dart';

// Real user agents.
const iPhoneSafari =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Version/18.5 Mobile/15E148 Safari/604.1';
const iPhoneChrome =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'CriOS/138.0.7204.119 Mobile/15E148 Safari/604.1';
const iPhoneFirefox =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'FxiOS/141.0 Mobile/15E148 Safari/605.1.15';
const iPadSafari =
    'Mozilla/5.0 (iPad; CPU OS 17_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Version/17.7 Mobile/15E148 Safari/604.1';
// iPadOS Safari asks for desktop sites by default: same user agent as a Mac
const macSafari =
    'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Version/18.5 Safari/605.1.15';
const iPhoneInstagram =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Mobile/15E148 Instagram 389.0.0.29.88 (iPhone15,3; iOS 18_5; en_US; en; scale=3.00; 1290x2796; 745215040)';
const iPhoneFacebook =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'Mobile/15E148 [FBAN/FBIOS;FBAV/519.0.0.38.105;FBBV/736054011;FBDV/iPhone15,3;FBMD/iPhone;FBSN/iOS;'
    'FBSV/18.5;FBSS/3;FBCR/;FBID/phone;FBLC/en_US;FBOP/80]';
const iPhoneGoogleApp =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) '
    'GSA/380.0.775543463 Mobile/15E148 Safari/604.1';
// a WKWebView with the default user agent (no "Version/… Safari/…")
const iPhoneWebView =
    'Mozilla/5.0 (iPhone; CPU iPhone OS 18_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148';
const androidChrome =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36';
const windowsChrome =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';

InstallHint hintFor(String userAgent, {int touchPoints = 5, bool standalone = false}) =>
    installHintFor(BrowserEnvironment(userAgent: userAgent, maxTouchPoints: touchPoints, standalone: standalone));

void main() {
  test('native apps: nothing', () {
    expect(installHintFor(null), InstallHint.none);
  });

  test('iPhone browsers: add to the home screen', () {
    for (final ua in [iPhoneSafari, iPhoneChrome, iPhoneFirefox]) {
      expect(hintFor(ua), const InstallHint(InstallHintKind.addToHomeScreen), reason: ua);
    }
  });

  test('iPad, including the desktop-site user agent', () {
    const iPad = InstallHint(InstallHintKind.addToHomeScreen, device: 'iPad');
    expect(hintFor(iPadSafari), iPad);
    expect(hintFor(macSafari, touchPoints: 5), iPad);
  });

  test('a Mac (no touch) gets nothing', () {
    expect(hintFor(macSafari, touchPoints: 0), InstallHint.none);
  });

  test('installed (standalone): nothing', () {
    for (final ua in [iPhoneSafari, iPadSafari, iPhoneInstagram]) {
      expect(hintFor(ua, standalone: true), InstallHint.none, reason: ua);
    }
  });

  test('Android and desktop: nothing', () {
    expect(hintFor(androidChrome), InstallHint.none);
    expect(hintFor(windowsChrome, touchPoints: 0), InstallHint.none);
    expect(hintFor(windowsChrome, touchPoints: 10), InstallHint.none);
  });

  test('in-app web views: open in Safari', () {
    for (final ua in [iPhoneInstagram, iPhoneFacebook, iPhoneGoogleApp, iPhoneWebView]) {
      expect(hintFor(ua), const InstallHint(InstallHintKind.openInSafari), reason: ua);
    }
  });
}
