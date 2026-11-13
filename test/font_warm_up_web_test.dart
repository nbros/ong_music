// Browser only: flutter test --platform chrome test/font_warm_up_web_test.dart (and with --wasm)
@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:ui' as ui;
import 'dart:ui_web' as ui_web;

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/font_warm_up.dart';
import 'package:ong_music/src/web/font_network_web.dart';
import 'package:web/web.dart' as web;

/// The font Google Fonts' CSS API gives for `family=Noto Sans JP&text=暁鎮`: those two characters of Noto Sans JP
/// (SIL Open Font License 1.1), 1,824 bytes of WOFF2.
final kitBytes = base64Decode(
  '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'
  'X123pcGS/1qXrKtIcBHoYWQiFWlIAwAA',
);

/// The test runner turns the engine's fallback fonts off, and draws all text in its test font
/// ([ui_web.TestEnvironment.flutterTester]): the same environment with the fallback on, and the families of the text
/// respected.
const _withFallbackFonts = ui_web.TestEnvironment(
  ignorePlatformMessages: true,
  forceTestFonts: false,
  disableFontFallbacks: false,
  keepSemanticsDisabledOnUpdate: true,
  defaultToTestUrlStrategy: true,
);

/// Lays out [text] in Roboto, with [fallback] as the app's theme gives it.
void layOut(String text, List<String> fallback) {
  final builder = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: 'Roboto'))
    ..pushStyle(ui.TextStyle(fontFamilyFallback: fallback))
    ..addText(text);
  final paragraph = builder.build()..layout(const ui.ParagraphConstraints(width: 1000));
  paragraph.dispose();
}

void main() {
  // What the engine asks Google Fonts for: answered 404 here, without the network.
  final asked = <String>[];
  late JSFunction realFetch;

  setUp(() {
    asked.clear();
    realFetch = web.window.getProperty<JSFunction>('fetch'.toJS);
    web.window.setProperty(
      'fetch'.toJS,
      ((JSAny input) {
        final url = input.isA<JSString>() ? (input as JSString).toDart : '';
        if (!url.startsWith('https://fonts.gstatic.com/')) return realFetch.callAsFunction(web.window, input);
        asked.add(url);
        return Future<web.Response>.value(web.Response(null, web.ResponseInit(status: 404))).toJS;
      }).toJS,
    );
    ui_web.TestEnvironment.setUp(_withFallbackFonts);
  });

  tearDown(() {
    ui_web.TestEnvironment.setUp(const ui_web.TestEnvironment.flutterTester());
    web.window.setProperty('fetch'.toJS, realFetch);
  });

  /// Waits until [done] holds, a generous while at most (a slow machine of the CI).
  Future<void> until(bool Function() done, {Duration timeout = const Duration(seconds: 20)}) async {
    final end = DateTime.now().add(timeout);
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('still not so after $timeout');
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
  }

  test('a kit registered by the app draws its characters: the engine looks for no font of its own for them; it still '
      'does for the others', () async {
    const kit = (name: 'Ong JP 1', family: 'Noto Sans JP', text: '暁鎮');
    await registerFontKits([(kit, kitBytes)]);

    // in the same turn: the characters of the kit, and an Arabic one no font here draws; the engine looks for fonts
    // for all the characters it lacks at once (a Han font for the first if it lacked them, an Arabic font)
    layOut('Linked Horizon - 暁 鎮', ['Roboto', 'Ong JP 1']);
    layOut('Khayal ا', ['Roboto', 'Ong JP 1']);
    await until(() => asked.any((url) => url.contains('/notosansarabic/')));
    final han = RegExp('/notosans(jp|sc|tc|hk|kr)/');
    expect(asked.where(han.hasMatch), isEmpty, reason: '$asked');
  });

  test('the browser online and offline', () {
    final network = BrowserFontNetwork();
    expect(network.online.value, web.window.navigator.onLine);
    web.window.dispatchEvent(web.Event('offline'));
    expect(network.online.value, isFalse);
    web.window.dispatchEvent(web.Event('online'));
    expect(network.online.value, isTrue);
  });
}
