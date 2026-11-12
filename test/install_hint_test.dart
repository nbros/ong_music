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
// a tablet: no "Mobile"
const androidChromeTablet =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';
const androidFirefox = 'Mozilla/5.0 (Android 15; Mobile; rv:141.0) Gecko/141.0 Firefox/141.0';
const androidFirefoxTablet = 'Mozilla/5.0 (Android 15; Tablet; rv:141.0) Gecko/141.0 Firefox/141.0';
const androidSamsung =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/28.0 '
    'Chrome/130.0.0.0 Mobile Safari/537.36';
const androidEdge =
    'Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Mobile Safari/537.36 '
    'EdgA/138.0.0.0';
// web views of other apps ("wv"), with the in-app tokens of their iOS versions
const androidInstagram =
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Build/AP2A.240805.005; wv) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Version/4.0 Chrome/127.0.6533.103 Mobile Safari/537.36 Instagram 343.0.0.32.112 Android (34/14; 420dpi; '
    '1080x2205; Google/google; Pixel 8; shiba; shiba; en_US; 629237468)';
const androidFacebook =
    'Mozilla/5.0 (Linux; Android 14; SM-S918B Build/UP1A.231005.007; wv) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Version/4.0 Chrome/130.0.6723.107 Mobile Safari/537.36 [FB_IAB/FB4A;FBAV/490.0.0.48.82;]';
// "Desktop site" on Android: Chrome, Firefox, Samsung Internet
const androidChromeDesktopSite =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 Safari/537.36';
const androidFirefoxDesktopSite = 'Mozilla/5.0 (X11; Linux x86_64; rv:141.0) Gecko/20100101 Firefox/141.0';
const androidSamsungDesktopSite =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) SamsungBrowser/28.0 Chrome/130.0.0.0 '
    'Safari/537.36';
// Amazon Fire tablet: no Google Play
const fireSilk =
    'Mozilla/5.0 (Linux; Android 11; KFRASWI) AppleWebKit/537.36 (KHTML, like Gecko) Silk/131.6.1 '
    'like Chrome/131.0.6778.260 Safari/537.36';
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
    for (final ua in [iPhoneSafari, iPadSafari, iPhoneInstagram, androidChrome, androidSamsung]) {
      expect(hintFor(ua, standalone: true), InstallHint.none, reason: ua);
    }
  });

  test('Android browsers and web views, phones and tablets: the Play app', () {
    const playStore = InstallHint(InstallHintKind.playStore, device: 'Android');
    for (final ua in [
      androidChrome,
      androidChromeTablet,
      androidFirefox,
      androidFirefoxTablet,
      androidSamsung,
      androidEdge,
      androidInstagram,
      androidFacebook,
    ]) {
      expect(hintFor(ua), playStore, reason: ua);
    }
  });

  test('Android "desktop site" and Fire tablets: nothing', () {
    for (final ua in [androidChromeDesktopSite, androidFirefoxDesktopSite, androidSamsungDesktopSite, fireSilk]) {
      expect(hintFor(ua), InstallHint.none, reason: ua);
    }
  });

  test('desktop: nothing', () {
    expect(hintFor(windowsChrome, touchPoints: 0), InstallHint.none);
    expect(hintFor(windowsChrome, touchPoints: 10), InstallHint.none);
  });

  test('in-app web views: open in Safari', () {
    for (final ua in [iPhoneInstagram, iPhoneFacebook, iPhoneGoogleApp, iPhoneWebView]) {
      expect(hintFor(ua), const InstallHint(InstallHintKind.openInSafari), reason: ua);
    }
  });
}
