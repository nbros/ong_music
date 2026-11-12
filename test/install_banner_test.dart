import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/install_banner.dart';
import 'package:ong_music/src/web/install_hint.dart';

import 'ui_harness.dart';

const addToHomeScreen = InstallHint(InstallHintKind.addToHomeScreen);
const title = 'Install Ong Music on your iPhone';

const playStore = InstallHint(InstallHintKind.playStore, device: 'Android');
const playTitle = 'Get the Android app';
const playButton = 'Open the Play Store';
const playAdvice = 'Install Ong Music from the Play Store for better performance.';

/// The banner title (the About section has the same one).
Finder bannerTitle() => find.descendant(of: find.byType(InstallBanner), matching: find.text(title));

/// The About section title.
Finder sectionTitle() => find.descendant(of: find.byType(InstallSection), matching: find.text(title));

/// [text] in the banner.
Finder inBanner(String text) => find.descendant(of: find.byType(InstallBanner), matching: find.text(text));

/// [text] in the About section.
Finder inSection(String text) => find.descendant(of: find.byType(InstallSection), matching: find.text(text));

/// Scrolls the About tab to its install section.
Future<void> scrollToSection(WidgetTester tester) async {
  await tester.scrollUntilVisible(find.byType(InstallSection), 200, scrollable: aboutScrollable());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('native app: no banner, no About section', (tester) async {
    await pumpApp(tester);
    expect(find.textContaining('Install Ong Music'), findsNothing);
    await goToTab(tester, 'About');
    expect(find.textContaining('Install Ong Music'), findsNothing);
    expect(find.textContaining('Add to Home Screen'), findsNothing);
  });

  testWidgets('iPhone browser: banner on every tab until dismissed for good, then still in About', (tester) async {
    final app = await pumpApp(tester, installHint: addToHomeScreen);
    expect(bannerTitle(), findsOneWidget);
    expect(find.textContaining('View More and “Add to Home Screen”.'), findsOneWidget);
    await goToTab(tester, 'Ong Log');
    expect(bannerTitle(), findsOneWidget);
    await goToTab(tester, 'About');
    expect(bannerTitle(), findsOneWidget);
    await scrollToSection(tester);
    expect(sectionTitle(), findsOneWidget);

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(bannerTitle(), findsNothing);
    expect(sectionTitle(), findsOneWidget);
    expect(app.prefs.getBool(InstallBannerDismissedNotifier.key), isTrue);
    await goToTab(tester, 'Highlights');
    expect(find.text(title), findsNothing);
  });

  testWidgets('a dismissal is remembered', (tester) async {
    await pumpApp(tester, installHint: addToHomeScreen, prefs: {InstallBannerDismissedNotifier.key: true});
    expect(find.text(title), findsNothing);
    await goToTab(tester, 'About');
    await scrollToSection(tester);
    expect(sectionTitle(), findsOneWidget);
  });

  testWidgets('iPad wording', (tester) async {
    await pumpApp(tester, installHint: const InstallHint(InstallHintKind.addToHomeScreen, device: 'iPad'));
    expect(find.text('Install Ong Music on your iPad'), findsOneWidget);
  });

  testWidgets('in-app web view: open in Safari, with a Copy link button', (tester) async {
    final app = await pumpApp(tester, installHint: const InstallHint(InstallHintKind.openInSafari));
    expect(find.text('Open in Safari to install Ong Music'), findsOneWidget);
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    expect(app.effects.clipboard, isNotEmpty);
    expect(find.text('Link copied: paste it in Safari'), findsOneWidget);
    await waitForMessage(tester);

    // an in-app web view may refuse the clipboard: say so, with the other way out
    app.effects.clipboardWorks = false;
    await tester.tap(find.text('Copy link'));
    await tester.pump();
    expect(find.textContaining('Couldn’t copy the link'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await waitForMessage(tester);
  });

  testWidgets('Android browser: the Play app, on every tab until dismissed for good, then still in About', (
    tester,
  ) async {
    final app = await pumpApp(tester, installHint: playStore);
    expect(inBanner(playTitle), findsOneWidget);
    expect(inBanner(playAdvice), findsOneWidget);
    expect(find.textContaining('Home Screen'), findsNothing);
    await tester.tap(inBanner(playButton));
    await tester.pumpAndSettle();
    expect(app.effects.opened, [Uri.parse('https://play.google.com/store/apps/details?id=nbros.ong_music')]);

    await goToTab(tester, 'Ong Log');
    expect(inBanner(playTitle), findsOneWidget);
    await goToTab(tester, 'About');
    await scrollToSection(tester);
    expect(inSection(playTitle), findsOneWidget);
    expect(inSection(playAdvice), findsOneWidget);
    await tester.tap(inSection(playButton));
    await tester.pumpAndSettle();
    expect(app.effects.opened, hasLength(2));
    expect(app.effects.opened.last, Uri.parse(playStoreUrl));

    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(inBanner(playTitle), findsNothing);
    expect(inSection(playTitle), findsOneWidget);
    expect(app.prefs.getBool(InstallBannerDismissedNotifier.key), isTrue);
    await goToTab(tester, 'Highlights');
    expect(find.text(playTitle), findsNothing);
  });

  testWidgets('Android: a dismissal is remembered', (tester) async {
    await pumpApp(tester, installHint: playStore, prefs: {InstallBannerDismissedNotifier.key: true});
    expect(find.text(playTitle), findsNothing);
    await goToTab(tester, 'About');
    await scrollToSection(tester);
    expect(inSection(playTitle), findsOneWidget);
    expect(inSection(playButton), findsOneWidget);
  });

  testWidgets('no banner on a window too low for it (a phone held sideways); the About tab keeps the advice', (
    tester,
  ) async {
    for (final hint in [playStore, addToHomeScreen]) {
      await pumpApp(tester, installHint: hint, size: const Size(740, 300));
      expect(tester.takeException(), isNull);
      expect(find.descendant(of: find.byType(InstallBanner), matching: find.byType(Text)), findsNothing);
      // the list has the room it has without any hint
      final withHint = tester.getSize(find.byType(CustomScrollView).hitTestable()).height;
      await goToTab(tester, 'About');
      await scrollToSection(tester);
      expect(find.byType(InstallSection), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, size: const Size(740, 300));
      expect(tester.getSize(find.byType(CustomScrollView).hitTestable()).height, withHint);
      await tester.pumpWidget(const SizedBox());
    }
    // upright again: the banner is back
    await pumpApp(tester, installHint: playStore, size: const Size(360, 740));
    expect(inBanner(playTitle), findsOneWidget);
  });

  testWidgets('the banner scrolls by itself, without taking the scroll controller of the pages', (tester) async {
    await pumpApp(tester, installHint: playStore);
    final scroll = tester.widget<SingleChildScrollView>(
      find.descendant(of: find.byType(InstallBanner), matching: find.byType(SingleChildScrollView)),
    );
    expect(scroll.primary, isFalse);
  });

  testWidgets('desktop browser: no banner, no About section', (tester) async {
    const windowsChrome =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/138.0.0.0 '
        'Safari/537.36';
    final hint = installHintFor(
      const BrowserEnvironment(userAgent: windowsChrome, maxTouchPoints: 0, standalone: false),
    );
    await pumpApp(tester, installHint: hint);
    expect(find.text(playTitle), findsNothing);
    expect(find.text(playButton), findsNothing);
    await goToTab(tester, 'About');
    await tester.scrollUntilVisible(find.text('Data'), 200, scrollable: aboutScrollable());
    expect(find.text(playTitle), findsNothing);
    expect(find.text(playButton), findsNothing);
    expect(find.textContaining('Install Ong Music'), findsNothing);
  });

  // 320 px is the narrowest phone; large text makes the banner scroll rather than push the page out
  for (final hint in [addToHomeScreen, const InstallHint(InstallHintKind.openInSafari), playStore]) {
    for (final scale in [1.0, 1.3, 2.0]) {
      testWidgets('${hint.kind.name}: banner and About section fit 320 × 568 at text scale $scale', (tester) async {
        await pumpApp(tester, installHint: hint, size: const Size(320, 568), textScale: scale);
        expect(tester.takeException(), isNull);
        // half the screen, plus the margins around the banner
        expect(tester.getSize(find.byType(InstallBanner)).height, lessThanOrEqualTo(568 / 2 + 12));
        expect(find.byTooltip('Dismiss').hitTestable(), findsOneWidget);
        await goToTab(tester, 'About');
        await scrollToSection(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }
}
