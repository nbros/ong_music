// The address of the web app (§7a): the tab and the search in the fragment, a step of the browser's history per tab
// change and none per key typed, Back and Forward, an address opened cold or typed while the app runs, the native
// apps (no address, Android's back button as before).
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/address.dart';
import 'package:ong_music/src/ui/detail_pane.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/ong_log_page.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/video_preview.dart';
import 'package:ong_music/src/ui/view_state.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/embedded_video.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// A desktop browser window: expanded.
const desk = Size(1440, 900);

/// The text of the search field of the tab on screen.
String searchText(WidgetTester tester) => tester.widget<TextField>(searchField()).controller!.text;

/// Types [text] in the search field of the tab on screen, as keys typed one after the other: one frame per key.
Future<void> typeKeys(WidgetTester tester, String text) async {
  await tester.tap(searchField());
  await tester.pump();
  for (var i = 1; i <= text.length; i++) {
    await tester.enterText(searchField(), text.substring(0, i));
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Lets the address catch up with what was typed.
Future<void> pause(WidgetTester tester) async {
  // the frame that reports the address, then the wait
  await tester.pump();
  await tester.pump(addressReplaceDelay);
  await tester.pumpAndSettle();
}

/// 100 highlights.
CatalogueState longCatalogueState() => CatalogueState(
  catalogue: catalogueOf(
    highlights: [for (var i = 0; i < 100; i++) hRow(order: '${i + 1}', title: 'Video $i')],
  ),
  fetchedAt: testNow,
);

/// The scroll offset of the Highlights list.
double highlightsOffset(WidgetTester tester) {
  final list = find.descendant(of: find.byType(HighlightsPage), matching: find.byType(CustomScrollView));
  return tester.state<ScrollableState>(find.descendant(of: list, matching: find.byType(Scrollable))).position.pixels;
}

/// The titles of the plays the Ong Log shows.
List<String> ongLogTitles(WidgetTester tester) => [
  for (final row in tester.widgetList<PlayRow>(
    find.descendant(of: find.byType(OngLogPage), matching: find.byType(PlayRow)),
  ))
    row.play.track,
];

void main() {
  group('addresses', () {
    test('a tab and its query, read and written', () {
      AppAddress parse(String s) => AppAddress.parse(Uri.parse(s));
      expect(parse('/'), AppAddress.home);
      expect(parse(''), AppAddress.home);
      expect(parse('/log'), const AppAddress(AppTab.ongLog));
      expect(parse('/log/'), const AppAddress(AppTab.ongLog));
      expect(parse('/log?q=zelda'), const AppAddress(AppTab.ongLog, 'zelda'));
      expect(parse('/?q=storms'), const AppAddress(AppTab.highlights, 'storms'));
      expect(parse('/about'), const AppAddress(AppTab.about));
      // About has no search
      expect(parse('/about?q=x'), const AppAddress(AppTab.about));
      // anything else: Highlights, without its query
      for (final unknown in ['/nope', '/nope?q=x', '/Log', '/log/x', '/privacy-policy', '/index.html']) {
        expect(parse(unknown), AppAddress.home, reason: unknown);
      }
      expect(AppAddress.home.uri.toString(), '/');
      expect(const AppAddress(AppTab.ongLog).uri.toString(), '/log');
      expect(const AppAddress(AppTab.about).uri.toString(), '/about');
      expect(const AppAddress(AppTab.ongLog, 'zelda').uri.toString(), '/log?q=zelda');
    });

    test('any text in the query comes back as it was typed', () {
      for (final query in [
        'lost woods',
        'a&b=c',
        '#1 hit?',
        '50% + 1',
        'Pokémon',
        'ロック',
        '🎹 piano 🎹',
        '  spaces  ',
        'q=1&q=2',
        r'back\slash/"quote"',
      ]) {
        final uri = AppAddress(AppTab.ongLog, query).uri;
        // the address the engine puts after '#': nothing in it ends the fragment or starts another parameter
        expect(uri.query, isNot(contains('#')), reason: query);
        expect(uri.query.split('&'), hasLength(1), reason: query);
        expect(AppAddress.parse(Uri.parse(uri.toString())).query, query, reason: query);
      }
      expect(const AppAddress(AppTab.highlights, 'a b').uri.toString(), '/?q=a+b');
      // the same query written another way by hand
      expect(AppAddress.parse(Uri.parse('/log?q=a%20b')).query, 'a b');
    });

    test('a query that cannot be read is dropped, its tab kept', () {
      // an accent written the old way, a link cut in the middle of a character
      for (final bad in ['/log?q=caf%E9', '/log?q=%E0%A4', '/?q=zelda%E9']) {
        expect(AppAddress.parse(Uri.parse(bad)).query, '', reason: bad);
      }
      expect(AppAddress.parse(Uri.parse('/log?q=caf%E9')), const AppAddress(AppTab.ongLog));
      // text that only looks like an escape is text
      expect(AppAddress.parse(Uri.parse('/log?q=100%zz')).query, '100%zz');
    });

    test('a very long query is cut in the address, never inside a character', () {
      final long = '🎹' * (maxAddressQueryLength + 10);
      final cut = AppAddress.parse(AppAddress(AppTab.ongLog, long).uri).query;
      expect(cut.runes, hasLength(maxAddressQueryLength));
      expect(cut, '🎹' * maxAddressQueryLength);
      final short = 'x' * maxAddressQueryLength;
      expect(AppAddress.parse(AppAddress(AppTab.ongLog, short).uri).query, short);
    });
  });

  group('the address follows the app', () {
    testWidgets('a step per tab; Highlights is the bare address', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      expect(browser.multiEntry, isTrue);
      expect(browser.writes, isEmpty);
      await goToTab(tester, 'Ong Log');
      await goToTab(tester, 'About');
      await goToTab(tester, 'Highlights');
      expect(browser.steps, ['/', '/log', '/about', '/']);
      expect(browser.index, 3);
      // the same tab again: nothing
      await goToTab(tester, 'Highlights');
      expect(browser.steps, hasLength(4));
    });

    testWidgets('typing rewrites the step on screen once the typing pauses: no step, no write per key', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await goToTab(tester, 'Ong Log');
      await typeKeys(tester, 'zelda');
      // the list follows every key
      expect(ongLogTitles(tester), ['Song of Storms', 'Lost Woods']);
      expect(browser.writes, ['push /log']);
      await pause(tester);
      expect(browser.writes, ['push /log', 'replace /log?q=zelda']);
      expect(browser.steps, ['/', '/log?q=zelda']);
      // cleared: the step says so too
      await tester.tap(find.byTooltip('Clear').hitTestable());
      await pause(tester);
      expect(browser.steps, ['/', '/log']);
      // typed and typed back before the pause: nothing to write
      await typeKeys(tester, 'x');
      await tester.enterText(searchField(), '');
      await pause(tester);
      expect(browser.writes, ['push /log', 'replace /log?q=zelda', 'replace /log']);
    });

    testWidgets('a tab changed right after typing: the step left keeps what was typed', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await typeKeys(tester, 'storms');
      await goToTab(tester, 'Ong Log');
      expect(browser.writes, ['replace /?q=storms', 'push /log']);
      expect(browser.steps, ['/?q=storms', '/log']);
    });

    testWidgets('the chips, the favourites and "You" are not in the address', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser, prefs: {'twitchName': 'jsbach64'});
      await tapVisible(tester, chip('Game OST'));
      await tapVisible(tester, chip('You'));
      await pause(tester);
      await goToTab(tester, 'Ong Log');
      await tapVisible(tester, chip('Piano'));
      await pause(tester);
      expect(browser.steps, ['/', '/log']);
    });

    testWidgets('"N in the Ong Log →": one step, with the tab and the query', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await typeKeys(tester, 'storms');
      await tester.pumpAndSettle();
      await tester.tap(find.textContaining('in the Ong Log'));
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      expect(browser.steps, ['/?q=storms', '/log?q=storms']);
      expect(browser.writes.where((w) => w.startsWith('push')), ['push /log?q=storms']);
    });

    testWidgets('"Requested by …": one step, with the tab and the query', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, size: desk, browser: browser);
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: find.byType(DetailPane).first,
          matching: find.textContaining('Requested by', findRichText: true),
        ),
      );
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 1);
      expect(browser.steps, ['/', '/log?q=shadowvanta']);
    });

    testWidgets('"Requested by" in a fiche opened from the Ong Log: a step, though the tab stays the same', (
      tester,
    ) async {
      // a highlight of "Lost Woods" without video: its picture in the song's fiche opens its own fiche
      final state = CatalogueState(
        catalogue: testCatalogue(
          moreHighlights: [hRow(order: '4', title: 'Zelda - Lost Woods', requester: 'jsbach64', stream: '2024-03-01')],
        ),
        fetchedAt: testNow,
      );
      final browser = FakeBrowser('/log');
      await pumpApp(tester, size: desk, browser: browser, state: state);
      final pane = find.byWidgetPredicate((w) => w is DetailPane && w.tab == AppTab.ongLog);
      await tester.tap(find.descendant(of: find.byType(OngLogPage), matching: find.text('Lost Woods')));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: pane, matching: find.byType(Thumbnail)));
      await tester.pumpAndSettle();
      expect(find.descendant(of: pane, matching: find.byType(HighlightSheet)), findsOneWidget);
      await tester.tap(find.descendant(of: pane, matching: find.textContaining('Requested by', findRichText: true)));
      await tester.pumpAndSettle();
      await pause(tester);
      expect(selectedTab(tester), 1);
      expect(searchText(tester), 'jsbach64');
      expect(browser.steps, ['/log', '/log?q=jsbach64']);
      // and Back returns to the Ong Log without search
      await browser.back();
      expect(searchText(tester), '');
    });

    testWidgets('a search started from a link is a step even on the same tab; typing after it rewrites it', (
      tester,
    ) async {
      // what the address bar is told and writes, without the app
      final writes = <String>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, (call) async {
        if (call.method == 'routeInformationUpdated') {
          final arguments = call.arguments as Map;
          writes.add('${arguments['replace'] as bool ? 'replace' : 'push'} ${arguments['uri']}');
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.navigation, null),
      );
      tester.platformDispatcher.defaultRouteNameTestValue = '/log';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      final bar = AddressBar(history: FakeBrowser('/log'), initial: const AppAddress(AppTab.ongLog));
      addTearDown(bar.dispose);
      void report(String uri) => bar.routerReportsNewRouteInformation(RouteInformation(uri: Uri.parse(uri)));
      report('/log?q=a');
      await tester.pump(addressReplaceDelay);
      bar.markStep();
      report('/log?q=bob');
      report('/log?q=bobx');
      await tester.pump(addressReplaceDelay);
      // the same search again: no step
      bar.markStep();
      report('/log?q=bobx');
      report('/log?q=bobxy');
      await tester.pump(addressReplaceDelay);
      // typed in the same instant as the search started: one step, with what was typed
      expect(writes, ['replace /log?q=a', 'push /log?q=bobx', 'replace /log?q=bobxy']);
      // outside a browser: nothing
      final native = AddressBar(history: null, initial: AppAddress.home);
      addTearDown(native.dispose);
      native.routerReportsNewRouteInformation(RouteInformation(uri: Uri.parse('/log')));
      await tester.pump(addressReplaceDelay);
      expect(writes, hasLength(3));
    });
  });

  group('Back and Forward', () {
    testWidgets('restore the tab and the query of each step', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await goToTab(tester, 'Ong Log');
      await typeKeys(tester, 'zelda');
      await pause(tester);
      await goToTab(tester, 'About');
      await goToTab(tester, 'Highlights');
      await typeKeys(tester, 'survive');
      await pause(tester);
      expect(browser.steps, ['/', '/log?q=zelda', '/about', '/?q=survive']);

      await browser.back();
      expect(selectedTab(tester), 2);
      expect(find.byType(AboutPage).hitTestable(), findsOneWidget);
      await browser.back();
      expect(selectedTab(tester), 1);
      expect(searchText(tester), 'zelda');
      expect(ongLogTitles(tester), ['Song of Storms', 'Lost Woods']);
      await browser.back();
      expect(selectedTab(tester), 0);
      expect(searchText(tester), '');
      expect(find.text('I Will Survive').hitTestable(), findsOneWidget);
      await browser.forward();
      await browser.forward();
      await browser.forward();
      expect(selectedTab(tester), 0);
      expect(searchText(tester), 'survive');
      // following the browser writes nothing
      await pause(tester);
      expect(browser.steps, ['/', '/log?q=zelda', '/about', '/?q=survive']);
      expect(browser.index, 3);
    });

    testWidgets('a tab whose query does not change keeps its list where it was', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, size: const Size(412, 500), browser: browser, state: longCatalogueState());
      await tester.drag(find.byType(HighlightsPage), const Offset(0, -400));
      await tester.pumpAndSettle();
      final offset = highlightsOffset(tester);
      expect(offset, greaterThan(0));
      await goToTab(tester, 'Ong Log');
      await browser.back();
      expect(selectedTab(tester), 0);
      expect(highlightsOffset(tester), offset);
    });

    testWidgets('an expanded window: the panes keep what they show', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, size: desk, browser: browser);
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      // a second fiche over the first one
      await tester.tap(
        find.descendant(of: find.byType(DetailPane).first, matching: find.textContaining('Played live on')),
      );
      await tester.pumpAndSettle();
      final container = ProviderScope.containerOf(tester.element(find.byType(HighlightsPage)));
      final highlights = container.read(detailPaneProvider(AppTab.highlights));
      expect(highlights, hasLength(2));
      await goToTab(tester, 'Ong Log');
      final ongLog = container.read(detailPaneProvider(AppTab.ongLog));
      await browser.back();
      expect(selectedTab(tester), 0);
      expect(container.read(detailPaneProvider(AppTab.highlights)), highlights);
      await browser.forward();
      expect(container.read(detailPaneProvider(AppTab.ongLog)), ongLog);
    });

    testWidgets('a tab left by Back stops the video playing in place', (tester) async {
      final browser = FakeBrowser();
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, browser: browser, videos: videos);
      await goToTab(tester, 'Ong Log');
      await browser.back();
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(VideoPreview).hitTestable());
      await tester.pump();
      videos.videos.last.playerState = EmbeddedVideoState.playing;
      await tester.pumpAndSettle();
      expect(videos.alive, hasLength(1));
      await browser.forward();
      expect(selectedTab(tester), 1);
      expect(videos.alive, isEmpty);
    });
  });

  group('what opens over the page has a step of its own', () {
    /// Opens the fiche of the second highlight (its ⋮ button), in a sheet.
    Future<void> openFiche(WidgetTester tester) async {
      await tester.tap(detailsButtons().at(1));
      await settle(tester);
      expect(find.byType(HighlightSheet), findsOneWidget);
    }

    testWidgets('Back closes it and the page stays as it was, on the very first step too', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, size: const Size(412, 500), browser: browser, state: longCatalogueState());
      await tester.drag(find.byType(HighlightsPage), const Offset(0, -400));
      await tester.pumpAndSettle();
      final offset = highlightsOffset(tester);
      await openFiche(tester);
      expect(browser.history, ['/', '/ +1']);
      expect(browser.index, 1);
      await browser.back();
      expect(find.byType(HighlightSheet), findsNothing);
      expect(browser.left, isFalse);
      expect(browser.index, 0);
      expect(selectedTab(tester), 0);
      expect(highlightsOffset(tester), offset);
      // Forward onto the step of the sheet closed: nothing to show, back at once
      await browser.forward();
      expect(find.byType(HighlightSheet), findsNothing);
      expect(browser.index, 0);
      expect(browser.moves, [-1]);
      // and Back now leaves the site, as a browser does
      await browser.back();
      expect(browser.left, isTrue);
    });

    testWidgets('a query being typed is written before the step of the sheet', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await goToTab(tester, 'Ong Log');
      await typeKeys(tester, 'lost');
      await tester.tap(find.text('Lost Woods').hitTestable());
      await settle(tester);
      expect(find.byType(SongSheet), findsOneWidget);
      expect(browser.writes, ['push /log', 'replace /log?q=lost', 'push /log?q=lost +1']);
      await browser.back();
      expect(find.byType(SongSheet), findsNothing);
      expect(selectedTab(tester), 1);
      expect(searchText(tester), 'lost');
      expect(browser.history, ['/', '/log?q=lost', '/log?q=lost +1']);
      expect(browser.index, 1);
    });

    for (final (how, close) in <(String, Future<void> Function(WidgetTester))>[
      ('the scrim', (tester) => tester.tapAt(const Offset(206, 40))),
      (
        'a drag down',
        // from the drag handle, over the sheet's content
        (tester) => tester.flingFrom(
          tester.getTopLeft(find.byType(SongSheet)) + const Offset(150, -16),
          const Offset(0, 600),
          2000,
        ),
      ),
      ('Escape', (tester) => tester.sendKeyEvent(LogicalKeyboardKey.escape)),
      ('the system Back routed to the navigator', (tester) => tester.binding.handlePopRoute()),
    ]) {
      testWidgets('closed by $how, it takes its step back: Back then goes where it went before', (tester) async {
        final browser = FakeBrowser();
        await pumpApp(tester, browser: browser);
        await goToTab(tester, 'Ong Log');
        await tester.tap(find.text('Lost Woods').hitTestable());
        await settle(tester);
        expect(browser.history, ['/', '/log', '/log +1']);
        await close(tester);
        await settle(tester);
        expect(find.byType(SongSheet), findsNothing);
        expect(browser.index, 1, reason: 'no step left that shows nothing');
        expect(browser.moves, [-1]);
        await browser.back();
        expect(selectedTab(tester), 0);
        expect(browser.left, isFalse);
      });
    }

    testWidgets('closed by its own means on a cold open: Back leaves the site', (tester) async {
      final browser = FakeBrowser('/log');
      await pumpApp(tester, browser: browser);
      await tester.tap(find.text('Lost Woods').hitTestable());
      await settle(tester);
      await tester.tapAt(const Offset(206, 40));
      await settle(tester);
      expect(browser.index, 0);
      await browser.back();
      expect(browser.left, isTrue);
    });

    testWidgets('a sheet replaced by another one (a link of the fiche) is still one step', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Lost Woods').hitTestable());
      await settle(tester);
      await tester.tap(find.descendant(of: find.byType(SongSheet), matching: find.byType(HistoryRow)).first);
      await settle(tester);
      expect(find.byType(StreamSheet), findsOneWidget);
      expect(browser.history, ['/', '/log', '/log +1']);
      expect(browser.writes.where((w) => w.endsWith('+1')), hasLength(1));
      await browser.back();
      expect(find.byType(StreamSheet), findsNothing);
      expect(selectedTab(tester), 1);
    });

    testWidgets('a sheet that moves into the pane (the window widened) gives its step back', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.text('Lost Woods').hitTestable());
      await settle(tester);
      expect(browser.index, 2);
      tester.view.physicalSize = desk;
      await settle(tester);
      expect(find.byType(DetailPane), findsWidgets);
      expect(browser.index, 1);
      expect(browser.overs[browser.index], 0);
    });

    testWidgets('"Requested by" in a sheet: one step for the Ong Log, none left for the sheet', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await goToTab(tester, 'About');
      await goToTab(tester, 'Highlights');
      await openFiche(tester);
      await tester.tap(find.textContaining('Requested by', findRichText: true).hitTestable());
      await settle(tester);
      expect(selectedTab(tester), 1);
      expect(searchText(tester), 'shadowvanta');
      expect(browser.history, ['/', '/about', '/', '/log?q=shadowvanta']);
      await browser.back();
      expect(selectedTab(tester), 0);
      expect(find.byType(HighlightSheet), findsNothing);
      await browser.back();
      expect(selectedTab(tester), 2);
    });

    testWidgets('a dialog over a sheet: two steps, Back closes the dialog only, then the sheet', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await openFiche(tester);
      showDialog<void>(
        context: tester.element(find.byType(HighlightSheet)),
        builder: (context) => const AlertDialog(content: Text('Over the sheet')),
      );
      await settle(tester);
      expect(browser.history, ['/', '/ +1', '/ +2']);
      await browser.back();
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(HighlightSheet), findsOneWidget);
      await browser.back();
      expect(find.byType(HighlightSheet), findsNothing);
      expect(browser.index, 0);
      // both closed at once by their own means: both steps go
      await openFiche(tester);
      showDialog<void>(
        context: tester.element(find.byType(HighlightSheet)),
        builder: (context) => const AlertDialog(content: Text('Over the sheet')),
      );
      await settle(tester);
      Navigator.of(tester.element(find.byType(AlertDialog))).popUntil((route) => route.isFirst);
      await settle(tester);
      expect(browser.index, 0);
      expect(browser.moves.last, -2);
    });

    testWidgets('the licences page and the "Clear downloaded data?" dialog', (tester) async {
      final browser = FakeBrowser('/about');
      await pumpApp(tester, browser: browser);
      await tester.drag(aboutScrollable(), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Licences'));
      await settle(tester);
      expect(find.byType(LicensePage), findsOneWidget);
      expect(browser.history, ['/about', '/about +1']);
      await browser.back();
      expect(find.byType(LicensePage), findsNothing);
      expect(selectedTab(tester), 2);
      expect(browser.left, isFalse);
      await tapVisible(tester, find.widgetWithText(TextButton, 'Clear'));
      await settle(tester);
      expect(find.byType(AlertDialog), findsOneWidget);
      await browser.back();
      expect(find.byType(AlertDialog), findsNothing);
      expect(selectedTab(tester), 2);
      // closed by its own button: its step goes
      await tapVisible(tester, find.widgetWithText(TextButton, 'Clear'));
      await settle(tester);
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await settle(tester);
      expect(browser.index, 0);
      expect(browser.overs, [0, 1], reason: 'only the step ahead, which Forward leaves at once');
    });

    testWidgets('Back inside the licences page: from the text of a licence to the list, then out of the page', (
      tester,
    ) async {
      LicenseRegistry.addLicense(() async* {
        yield const LicenseEntryWithLineBreaks(['a_package_of_the_test'], 'The text of its licence.');
      });
      final browser = FakeBrowser('/about');
      await pumpApp(tester, browser: browser);
      await tester.drag(aboutScrollable(), const Offset(0, -3000));
      await tester.pumpAndSettle();
      await tapVisible(tester, find.text('Licences'));
      await settle(tester);
      await tester.tap(find.text('a_package_of_the_test'));
      await settle(tester);
      expect(find.text('The text of its licence.'), findsOneWidget);
      // Back: the list of the page again, as the system's back button does, not About
      await browser.back();
      await settle(tester);
      expect(find.byType(LicensePage), findsOneWidget);
      expect(find.text('The text of its licence.'), findsNothing);
      expect(browser.left, isFalse);
      // the page is still open: it has its step, and Back closes it
      expect(browser.current.over, 1);
      await browser.back();
      await settle(tester);
      expect(find.byType(LicensePage), findsNothing);
      expect(selectedTab(tester), 2);
      expect(browser.left, isFalse);
    });

    testWidgets('opened and closed at once, opened again while the browser moves, Back twice', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await goToTab(tester, 'Ong Log');
      // opened and closed in the same moment
      await tester.tap(find.text('Lost Woods').hitTestable());
      await tester.pump();
      await tester.binding.handlePopRoute();
      await settle(tester);
      expect(find.byType(SongSheet), findsNothing);
      expect(browser.index, 1);
      expect(browser.overs[browser.index], 0);
      // closed by the scrim, and another one opened before the browser has moved back
      await tester.tap(find.text('Lost Woods').hitTestable());
      await settle(tester);
      await tester.tapAt(const Offset(206, 40));
      await tester.pump();
      await tester.tap(find.text('Song of Storms').hitTestable().first, warnIfMissed: false);
      await settle(tester);
      expect(find.byType(SongSheet), findsOneWidget);
      expect(browser.history.sublist(0, browser.index + 1), ['/', '/log', '/log +1']);
      // Back twice
      await browser.back();
      await browser.back();
      expect(find.byType(SongSheet), findsNothing);
      expect(selectedTab(tester), 0);
      expect(browser.left, isFalse);
    });

    testWidgets('a reload on the step of a sheet goes back to the step under it', (tester) async {
      final browser = FakeBrowser('/log');
      browser
        ..steps.add('/log')
        ..overs.add(1)
        ..index = 1;
      await pumpApp(tester, browser: browser);
      await settle(tester);
      expect(browser.index, 0);
      expect(selectedTab(tester), 1);
    });

    testWidgets('an expanded window: no sheet, the tab steps only', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, size: desk, browser: browser);
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await settle(tester);
      await goToTab(tester, 'Ong Log');
      expect(browser.history, ['/', '/log']);
    });
  });

  group('an address opened', () {
    testWidgets('cold: its tab and its search, as soon as the catalogue is there', (tester) async {
      final browser = FakeBrowser('/log?q=zelda');
      final app = await pumpApp(tester, browser: browser, state: const CatalogueState(), settle: false);
      expect(selectedTab(tester), 1);
      app.notifier.emit(CatalogueState(catalogue: testCatalogue(), fetchedAt: testNow));
      await tester.pumpAndSettle();
      expect(searchText(tester), 'zelda');
      expect(ongLogTitles(tester), ['Song of Storms', 'Lost Woods']);
      // nothing to write: the address is already the app's
      expect(browser.writes, isEmpty);
      // Highlights has no search of its own
      await goToTab(tester, 'Highlights');
      expect(searchText(tester), '');
    });

    testWidgets('cold, on Highlights with a search; the expanded pane shows its first row', (tester) async {
      final browser = FakeBrowser('/?q=survive');
      await pumpApp(tester, size: desk, browser: browser);
      expect(selectedTab(tester), 0);
      expect(searchText(tester), 'survive');
      expect(find.descendant(of: find.byType(DetailPane).first, matching: find.text('I Will Survive')), findsWidgets);
    });

    testWidgets('an unknown address: Highlights, and the address says so', (tester) async {
      final browser = FakeBrowser('/nope?q=x');
      await pumpApp(tester, browser: browser);
      expect(selectedTab(tester), 0);
      expect(searchText(tester), '');
      await pause(tester);
      expect(browser.steps, ['/']);
    });

    testWidgets('an address whose query cannot be read: its tab, no search, and the app goes on', (tester) async {
      final browser = FakeBrowser('/log?q=caf%E9');
      await pumpApp(tester, browser: browser);
      expect(tester.takeException(), isNull);
      expect(selectedTab(tester), 1);
      expect(searchText(tester), '');
      await pause(tester);
      // the address says what the app shows, on the same step
      expect(browser.steps, ['/log']);
      // and the next steps are written as usual
      await goToTab(tester, 'About');
      await pause(tester);
      expect(browser.steps, ['/log', '/about']);

      // The same typed in the bar while the app runs. (Flutter itself reports an error for each of its observers
      // that reads such an address, and goes on: the app's own part must not fail.)
      await browser.type('/log?q=%E0%A4');
      expect('${tester.takeException()}', isNot(contains('address.dart')));
      expect(selectedTab(tester), 1);
      expect(searchText(tester), '');
      await goToTab(tester, 'Highlights');
      await pause(tester);
      expect(browser.address, '/');
    });

    testWidgets('typed in the bar while the app runs', (tester) async {
      final browser = FakeBrowser();
      await pumpApp(tester, browser: browser);
      await browser.type('/log?q=lost%20woods');
      expect(selectedTab(tester), 1);
      expect(searchText(tester), 'lost woods');
      expect(ongLogTitles(tester), ['Lost Woods']);
      await pause(tester);
      // written the app's way, on the same step
      expect(browser.steps, ['/', '/log?q=lost+woods']);
      await browser.type('/about');
      expect(selectedTab(tester), 2);
      await browser.type('/whatever');
      expect(selectedTab(tester), 0);
    });
  });

  group('native apps', () {
    testWidgets('no address: nothing goes to the navigation channel', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await goToTab(tester, 'Ong Log');
      await typeKeys(tester, 'zelda');
      await tester.pumpAndSettle();
      await goToTab(tester, 'About');
      expect(app.effects.navigation, isEmpty);
    });

    testWidgets('a start address of the system does not move the app', (tester) async {
      tester.platformDispatcher.defaultRouteNameTestValue = '/log?q=zelda';
      addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);
      await pumpApp(tester);
      expect(selectedTab(tester), 0);
      expect(searchText(tester), '');
    });

    testWidgets('Android back: a sheet first, then Highlights, then out; the query stays', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await typeKeys(tester, 'zelda');
      await tester.pumpAndSettle();
      await tester.tap(find.text('Lost Woods').hitTestable());
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsNothing);
      expect(selectedTab(tester), 1);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(selectedTab(tester), 0);
      expect(app.effects.exits, 0);
      await goToTab(tester, 'Ong Log');
      expect(searchText(tester), 'zelda');
      await goToTab(tester, 'Highlights');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.effects.exits, 1);
    });

    testWidgets('Android back in an expanded window: the fiche under the one on screen first', (tester) async {
      final app = await pumpApp(tester, size: desk);
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: find.byType(DetailPane).first, matching: find.textContaining('Played live on')),
      );
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(DetailPane).first, matching: find.byType(StreamSheet)), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(DetailPane).first, matching: find.byType(HighlightSheet)), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(app.effects.exits, 1);
    });
  });
}
