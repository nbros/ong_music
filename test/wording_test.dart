// Texts that must be true in every state, and the colour of the search hits.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/parser.dart';
import 'package:ong_music/src/data/sheets.dart';
import 'package:ong_music/src/ui/list_scaffold.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/theme.dart';

import 'ui_harness.dart';

void main() {
  test('each kind of failed download has its own words', () {
    final texts = {
      for (final Object error in [
        SheetHttpException(SheetUrls.songs, 503),
        SheetNotCsvException(SheetUrls.songs),
        const CatalogueFormatException('Songs: no row'),
        TimeoutException('No stream event'),
        Exception('offline'),
      ])
        describeLoadError(error),
    };
    expect(texts, hasLength(5));
    // a Wi-Fi sign-in page is not a fault of the spreadsheets, and has a remedy
    expect(describeLoadError(SheetNotCsvException(SheetUrls.songs)), contains('sign in'));
    expect(describeLoadError(SheetNotCsvException(SheetUrls.songs)), isNot(contains('format')));
  });

  group('empty lists', () {
    testWidgets('Highlights: the advice fits what was asked', (tester) async {
      await pumpApp(tester, prefs: {'twitchName': 'jsbach64'});
      // a filter that has nothing with another one, no word typed
      await tapVisible(tester, chip('You'));
      await tapVisible(tester, chip('Disney'));
      expect(find.byType(HighlightRow), findsNothing);
      expect(find.text('No highlight matches'), findsOneWidget);
      expect(find.text('Try fewer filters.'), findsOneWidget);
      // words and filters
      await tester.enterText(searchField(), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('Try fewer words, or fewer filters.'), findsOneWidget);
      // words alone
      await tapVisible(tester, chip('All'));
      expect(find.text('Try fewer words.'), findsOneWidget);
    });

    testWidgets('Ong Log: no spelling to check when nothing was typed', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      // loops with a video of the Game OST genre: none
      await tapVisible(tester, chip('Loop'));
      await tapVisible(tester, chip('Game OST'));
      expect(find.byType(PlayRow), findsNothing);
      expect(find.text('No song matches'), findsOneWidget);
      expect(find.text('Try fewer filters.'), findsOneWidget);
      expect(find.textContaining('spelling'), findsNothing);
      await tester.enterText(searchField(), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('Never played… yet'), findsOneWidget);
      expect(find.text('Check the spelling, or request it on stream.'), findsOneWidget);
    });
  });

  testWidgets('sharing a highlight without video where sharing is missing: "title copied", not "link"', (tester) async {
    final app = await pumpApp(tester);
    app.effects.shareWorks = false;
    // the first highlight has no video
    await tester.tap(detailsButtons().first);
    await tester.pumpAndSettle();
    expect(find.byType(HighlightSheet), findsOneWidget);
    await tester.tap(find.byTooltip('Share'));
    await tester.pump();
    expect(find.text('Sharing isn’t available here: title copied'), findsOneWidget);
    expect(app.effects.clipboard, "Moana - How Far I'll Go");
    await waitForMessage(tester);
  });

  testWidgets('a failed pull to refresh says "Refresh failed", then why', (tester) async {
    final app = await pumpApp(tester);
    app.notifier.refreshError = Exception('offline');
    await tester.fling(find.byType(HighlightRow).first, const Offset(0, 400), 1000);
    await tester.pumpAndSettle();
    expect(
      find.text('Refresh failed. Couldn’t reach Google Sheets. Check your connection and try again.'),
      findsOneWidget,
    );
    await waitForMessage(tester);
  });

  testWidgets('a short message shows above the keyboard', (tester) async {
    final app = await pumpApp(tester);
    app.effects.shareWorks = false;
    await tester.tap(detailsButtons().at(1));
    await tester.pumpAndSettle();
    Future<Rect> message() async {
      await tester.tap(find.byTooltip('Share'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      final rect = tester.getRect(find.text('Sharing isn’t available here: link copied'));
      await waitForMessage(tester);
      return rect;
    }

    // above the navigation bar
    expect((await message()).bottom, lessThan(892 - 96));
    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    final above = await message();
    expect(above.bottom, lessThan(892 - 300));
    expect(above.bottom, greaterThan(892 - 300 - 60));
  });

  for (final brightness in Brightness.values) {
    testWidgets('search hits are written in the main text colour on their mark: ${brightness.name} theme', (
      tester,
    ) async {
      tester.platformDispatcher.platformBrightnessTestValue = brightness;
      addTearDown(tester.platformDispatcher.clearPlatformBrightnessTestValue);
      await pumpApp(tester);
      // a requester: every hit is in the grey line under the titles
      await tester.enterText(searchField(), 'shadowvanta');
      await tester.pumpAndSettle();
      final context = tester.element(find.byType(HighlightRow).first);
      final scheme = Theme.of(context).colorScheme;
      final ong = OngColors.of(context);
      expect(scheme.brightness, brightness);
      final hits = <(Color?, Color?)>[];
      for (final text in tester.widgetList<RichText>(
        find.descendant(of: find.byType(HighlightRow), matching: find.byType(RichText)),
      )) {
        text.text.visitChildren((span) {
          if (span is TextSpan && span.text == 'shadowvanta') {
            hits.add((span.style?.backgroundColor, span.style?.color));
          }
          return true;
        });
      }
      expect(hits, [(ong.mark, scheme.onSurface)]);
      // WCAG AA for small text: the grey of the line was at 2.2 to 1 on the mark of the dark theme
      expect(_contrast(scheme.onSurface, ong.mark), greaterThan(4.5));
      expect(_contrast(ong.on3, ong.mark), lessThan(4.5), reason: 'what the hit was written in');
    });
  }
}

double _contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}
