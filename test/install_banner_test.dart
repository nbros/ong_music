import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/ui/install_banner.dart';
import 'package:ong_music/src/web/install_hint.dart';

import 'ui_harness.dart';

const addToHomeScreen = InstallHint(InstallHintKind.addToHomeScreen);
const title = 'Install Ong Music on your iPhone';

/// The banner title (the About section has the same one).
Finder bannerTitle() => find.descendant(of: find.byType(InstallBanner), matching: find.text(title));

/// The About section title.
Finder sectionTitle() => find.descendant(of: find.byType(InstallSection), matching: find.text(title));

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
}
