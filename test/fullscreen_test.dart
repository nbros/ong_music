// The full screen button of the web app, beside the search fields.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/fullscreen_button.dart';
import 'package:ong_music/src/web/fullscreen.dart';
import 'package:ong_music/src/web/install_hint.dart';

import 'ui_harness.dart';

void main() {
  group('offered', () {
    BrowserEnvironment browser(String userAgent, {int maxTouchPoints = 0, bool standalone = false}) =>
        BrowserEnvironment(userAgent: userAgent, maxTouchPoints: maxTouchPoints, standalone: standalone);
    const chrome =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Safari/537.36';
    const android =
        'Mozilla/5.0 (Linux; Android 14; Pixel 8) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/141.0 Mobile Safari/537.36';
    const mac =
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15';
    const ipad =
        'Mozilla/5.0 (iPad; CPU OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
    const iphone =
        'Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1';
    const ipod =
        'Mozilla/5.0 (iPod touch; CPU iPhone OS 15_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.0 Mobile/15E148 Safari/604.1';

    test('in a browser whose Fullscreen API is enabled', () {
      for (final b in [
        browser(chrome),
        browser(android),
        browser(mac),
        browser(ipad),
        browser(mac, maxTouchPoints: 5),
      ]) {
        expect(offersFullscreen(b, enabled: true), isTrue, reason: b.userAgent);
      }
    });

    test('not in the native apps, without the API, once installed, nor on an iPhone', () {
      expect(offersFullscreen(null, enabled: true), isFalse);
      expect(offersFullscreen(browser(chrome), enabled: false), isFalse);
      expect(offersFullscreen(browser(android, standalone: true), enabled: true), isFalse);
      expect(offersFullscreen(browser(ipad, standalone: true), enabled: true), isFalse);
      // videos only, even if it ever said otherwise
      expect(offersFullscreen(browser(iphone, maxTouchPoints: 5), enabled: true), isFalse);
      expect(offersFullscreen(browser(ipod, maxTouchPoints: 5), enabled: true), isFalse);
    });
  });

  testWidgets('native apps: no button, the search field as wide as before', (tester) async {
    // the real provider: the native implementation offers nothing
    final container = ProviderContainer();
    addTearDown(container.dispose);
    expect(container.read(pageFullscreenProvider), isNull);

    await pumpApp(tester);
    for (final tab in ['Highlights', 'Ong Log']) {
      await goToTab(tester, tab);
      expect(find.byType(FullscreenButton), findsNothing, reason: tab);
      final field = tester.getRect(pill());
      expect((field.left, field.right, field.height), (16, 412 - 16, 52), reason: tab);
    }
  });

  testWidgets('in the browser: beside both search fields, in the column of the ⋮ buttons', (tester) async {
    await pumpApp(tester, fullscreen: FakeFullscreen());
    for (final tab in ['Highlights', 'Ong Log']) {
      await goToTab(tester, tab);
      expect(fullscreenButton(), findsOneWidget, reason: tab);
      expectLayout(tester, left: 0, right: 412, reason: tab);
      expect(tester.getRect(pill()).height, 52, reason: tab);
    }
    await goToTab(tester, 'Highlights');
    final details = tester.getRect(find.widgetWithIcon(IconButton, Icons.more_vert).first);
    final button = tester.getRect(fullscreenButton());
    expect((details.left, details.right), (button.left, button.right));
    // the icon glyph where the ⋮ glyphs are
    final glyph = tester.getRect(find.descendant(of: fullscreenButton(), matching: find.byType(Icon)));
    expect((glyph.left, glyph.right), (412 - 36, 412 - 12));
  });

  for (final (width, scale) in [(320.0, 1.0), (320.0, 1.3), (320.0, 2.0), (412.0, 2.0)]) {
    testWidgets('in the browser: fits at $width px and text scale $scale', (tester) async {
      await pumpApp(tester, fullscreen: FakeFullscreen(), size: Size(width, 640), textScale: scale);
      for (final tab in ['Highlights', 'Ong Log']) {
        await goToTab(tester, tab);
        expect(tester.takeException(), isNull, reason: tab);
        expectLayout(tester, left: 0, right: width, reason: tab);
      }
    });
  }

  testWidgets('a tap goes full screen and back; the icon changes in place', (tester) async {
    final fullscreen = FakeFullscreen();
    await pumpApp(tester, fullscreen: fullscreen);
    final before = (tester.getRect(fullscreenButton()), tester.getRect(pill()));
    expect(find.byTooltip('Full screen'), findsOneWidget);
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen)), findsOneWidget);

    await tester.tap(fullscreenButton());
    await tester.pumpAndSettle();
    expect((fullscreen.enters, fullscreen.exits), (1, 0));
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen_exit)), findsOneWidget);
    expect(find.byTooltip('Exit full screen'), findsOneWidget);
    expect((tester.getRect(fullscreenButton()), tester.getRect(pill())), before);
    expect(
      tester.getRect(find.descendant(of: fullscreenButton(), matching: find.byType(Icon))).size,
      const Size(24, 24),
    );

    // the other tab shows the same state
    await goToTab(tester, 'Ong Log');
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen_exit)), findsOneWidget);
    await tester.tap(fullscreenButton());
    await tester.pumpAndSettle();
    expect((fullscreen.enters, fullscreen.exits), (1, 1));
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen)), findsOneWidget);
    expect((tester.getRect(fullscreenButton()), tester.getRect(pill())), before);
  });

  testWidgets('the icon follows the browser: left with Escape, then a tap goes full screen again', (tester) async {
    final fullscreen = FakeFullscreen();
    await pumpApp(tester, fullscreen: fullscreen);
    await tester.tap(fullscreenButton());
    await tester.pump();
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen_exit)), findsOneWidget);

    fullscreen.browserState = false;
    await tester.pump();
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen)), findsOneWidget);
    await tester.tap(fullscreenButton());
    await tester.pump();
    expect((fullscreen.enters, fullscreen.exits), (2, 0));
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen_exit)), findsOneWidget);
  });

  testWidgets('a refused request: the icon stays, a short message says so', (tester) async {
    final fullscreen = FakeFullscreen()..refuses = true;
    await pumpApp(tester, fullscreen: fullscreen);
    await tester.tap(fullscreenButton());
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(fullscreen.enters, 1);
    expect(find.descendant(of: fullscreenButton(), matching: find.byIcon(Icons.fullscreen)), findsOneWidget);
    expect(find.text('Couldn’t go full screen'), findsOneWidget);
    await waitForMessage(tester);
    expect(find.text('Couldn’t go full screen'), findsNothing);
  });

  testWidgets('screen readers: a "Full screen" switch, on or off', (tester) async {
    final semantics = tester.ensureSemantics();
    final fullscreen = FakeFullscreen();
    await pumpApp(tester, fullscreen: fullscreen);
    Matcher button({required bool on}) => matchesSemantics(
      label: 'Full screen',
      isButton: true,
      hasToggledState: true,
      isToggled: on,
      hasTapAction: true,
    );
    expect(tester.getSemantics(fullscreenButton()), button(on: false));

    tester.semantics.tap(find.semantics.byLabel('Full screen'));
    await tester.pump();
    expect(fullscreen.enters, 1);
    expect(tester.getSemantics(fullscreenButton()), button(on: true));
    semantics.dispose();
  });
}
