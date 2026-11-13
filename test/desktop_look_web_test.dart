// Browser only: flutter test --platform chrome test/desktop_look_web_test.dart
@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/web/web_platform.dart';

final JSObject navigator = globalContext['navigator']! as JSObject;

/// Gives [object] an own property [name] of [value], hiding the browser's
/// one (on a prototype) until the end of the test.
void shadow(JSObject object, String name, JSAny? value) {
  final descriptor = JSObject()
    ..['value'] = value
    ..['configurable'] = true.toJS;
  (globalContext['Object']! as JSObject).callMethod('defineProperty'.toJS, object, name.toJS, descriptor);
  addTearDown(() => object.delete(name.toJS));
}

/// The browser tells what [userAgent], [platform], [touchPoints] and the
/// client hints' [hints] say (none: no `navigator.userAgentData`).
void browserSays(String userAgent, String platform, int touchPoints, [String? hints]) {
  shadow(navigator, 'userAgent', userAgent.toJS);
  shadow(navigator, 'platform', platform.toJS);
  shadow(navigator, 'maxTouchPoints', touchPoints.toJS);
  shadow(navigator, 'userAgentData', hints == null ? null : (JSObject()..['platform'] = hints.toJS));
}

const linuxUa = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/157.0.0.0 Safari/537.36';

void main() {
  test('the browser says the system it was built for, and its client hints where it gives them', () {
    browserSays(linuxUa, 'Linux armv81', 5, 'Android');
    final browser = currentBrowser()!;
    expect(
      (browser.userAgent, browser.platform, browser.maxTouchPoints, browser.clientHintsPlatform),
      (linuxUa, 'Linux armv81', 5, 'Android'),
    );
    browserSays(linuxUa, 'Linux x86_64', 0);
    expect(currentBrowser()!.clientHintsPlatform, isNull);
  });

  // (flutter test gives the app the Android platform: the platform Flutter would report is given here)
  test('Android asking for desktop sites keeps the phone and tablet look, read from the browser', () {
    browserSays(linuxUa, 'Linux armv81', 5, 'Android');
    expect(isDesktopPlatform(TargetPlatform.linux, currentBrowser()), isFalse);
    // client hints empty (as Chrome gives them under an emulated user agent) or missing
    browserSays(linuxUa, 'Linux armv81', 5, '');
    expect(isDesktopPlatform(TargetPlatform.linux, currentBrowser()), isFalse);
    browserSays(linuxUa, 'Linux aarch64', 10);
    expect(isDesktopPlatform(TargetPlatform.linux, currentBrowser()), isFalse);
  });

  test('a Chromebook and a Linux laptop with a touch screen keep the desktop look, read from the browser', () {
    browserSays(
      'Mozilla/5.0 (X11; CrOS aarch64 15359.0.0) AppleWebKit/537.36 Chrome/157.0.0.0 Safari/537.36',
      'Linux aarch64',
      10,
      'Chrome OS',
    );
    expect(isDesktopPlatform(TargetPlatform.linux, currentBrowser()), isTrue);
    browserSays(linuxUa, 'Linux x86_64', 10, 'Linux');
    expect(isDesktopPlatform(TargetPlatform.linux, currentBrowser()), isTrue);
  });
}
