// The controls that open an outside address as links of the browser (§7b): a link of the page laid over a control
// only while a mouse rests on it, one node said as a link for screen readers, a plain click as before, a click the
// browser handles itself left to it (the video playing in place goes on, unless the browser shows the link in front),
// nothing over the player, nothing that moves; the native apps unchanged.
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/outside_link.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/video_preview.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/embedded_video.dart';

import 'ui_harness.dart';

/// A desktop browser window: expanded.
const desk = Size(1440, 900);

/// The links of the page on screen.
Finder anchors() => find.byType(FakeAnchor);

/// A mouse, in a corner: the app knows the pointer is a mouse (its scroll bars have their lane, the expanded
/// thumbnails open the video).
Future<TestGesture> mouse(WidgetTester tester) async {
  final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
  await gesture.addPointer(location: const Offset(1, 1));
  addTearDown(gesture.removePointer);
  await gesture.moveTo(const Offset(2, 2));
  await tester.pumpAndSettle();
  return gesture;
}

/// Moves [gesture] onto the middle of [finder], from a pixel away, and lets it rest there.
Future<Offset> hover(WidgetTester tester, TestGesture gesture, Finder finder) async {
  final center = tester.getCenter(finder);
  await gesture.moveTo(center - const Offset(1, 0));
  await gesture.moveTo(center);
  await tester.pump(linkAnchorDelay);
  await tester.pumpAndSettle();
  return center;
}

/// A click of [gesture] at [at], with [keys] held.
Future<void> click(
  WidgetTester tester,
  TestGesture gesture,
  Offset at, {
  List<LogicalKeyboardKey> keys = const [],
}) async {
  for (final key in keys) {
    await tester.sendKeyDownEvent(key);
  }
  await gesture.down(at);
  await gesture.up();
  for (final key in keys) {
    await tester.sendKeyUpEvent(key);
  }
  await tester.pumpAndSettle();
}

/// The data of the one semantics node labelled [label].
SemanticsData node(Pattern label, {int at = 0}) =>
    find.semantics.byLabel(label).at(at).evaluate().single.getSemanticsData();

void main() {
  group('native apps', () {
    testWidgets('the controls as they were: no link of the page, said as buttons', (tester) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester);
      expect(ProviderScope.containerOf(tester.element(find.byType(HighlightsPage))).read(linkAnchorsProvider), isNull);
      await goToTab(tester, 'Ong Log');
      final gesture = await mouse(tester);
      await hover(tester, gesture, find.byType(VideoPill).first);
      expect(anchors(), findsNothing);
      expect(
        find.descendant(of: find.byType(OutsideLink), matching: find.byType(Stack)),
        findsNothing,
        reason: 'nothing added around the control',
      );
      final pill = node('Watch the video');
      expect(pill.flagsCollection.isButton, isTrue);
      expect(pill.flagsCollection.isLink, isFalse);
      expect(pill.linkUrl, isNull);
      handle.dispose();
    });
  });

  group('screen readers', () {
    testWidgets('one node per link, said as a link to its address, with its name and its action', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpApp(tester, links: FakeLinkAnchors());

      Future<void> check(Pattern label, {int count = 1}) async {
        expect(find.semantics.byLabel(label), findsNWidgets(count), reason: '$label');
        final data = node(label);
        expect(data.flagsCollection.isLink, isTrue, reason: '$label');
        expect(data.hasAction(SemanticsAction.tap), isTrue, reason: '$label');
        final opened = app.effects.opened.length;
        tester.semantics.tap(find.semantics.byLabel(label).first);
        await tester.pumpAndSettle();
        expect(app.effects.opened, hasLength(opened + 1), reason: '$label');
        expect(data.linkUrl, app.effects.opened.last, reason: '$label: the address it says is the one it opens');
      }

      // the video button of a fiche
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await check('Watch on YouTube');
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // the video pills of the Ong Log, and the videos of a song fiche
      await goToTab(tester, 'Ong Log');
      final pills = find.byType(VideoPill).hitTestable().evaluate().length;
      await check('Watch the video', count: pills);
      await tester.tap(find.text('I Will Survive').hitTestable().first);
      await tester.pumpAndSettle();
      await check(RegExp('^Video of '));
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();

      // About: the tiles, Twitch, the footer
      await goToTab(tester, 'About');
      for (final (label, _, _) in aboutLinks) {
        await check(label);
      }
      await check('Watch on Twitch');
      await tester.drag(aboutScrollable(), const Offset(0, -2000));
      await tester.pumpAndSettle();
      await check('Privacy policy');
      await check('Community spreadsheet');
      handle.dispose();
    });

    testWidgets('the tests of a native app hold: the pill is a node of its own, not merged into its row', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpApp(tester, links: FakeLinkAnchors());
      await goToTab(tester, 'Ong Log');
      final pills = find.byType(VideoPill).hitTestable();
      expect(find.semantics.byLabel('Watch the video'), findsNWidgets(pills.evaluate().length));
      // the row's own node keeps its title and no link
      final row = node(RegExp('^21:00\nI Will Survive'));
      expect(row.flagsCollection.isLink, isFalse);
      handle.dispose();
    });
  });

  group('with a mouse', () {
    testWidgets('a link of the page over the control the mouse rests on, exactly over it; gone when it leaves', (
      tester,
    ) async {
      await pumpApp(tester, links: FakeLinkAnchors());
      await goToTab(tester, 'Ong Log');
      expect(anchors(), findsNothing);
      final gesture = await mouse(tester);
      final pill = find.byType(VideoPill).first;
      final before = tester.getRect(pill);
      await hover(tester, gesture, pill);
      expect(anchors(), findsOneWidget);
      expect(tester.getRect(anchors()), before);
      final first = tester.widget<FakeAnchor>(anchors()).uri.toString();
      expect(first, startsWith('https://www.youtube.com/watch?v='));
      // nothing moved
      expect(tester.getRect(pill), before);
      await hover(tester, gesture, find.text('Lost Woods'));
      expect(anchors(), findsNothing);
      // the next pill: its own address
      await hover(tester, gesture, find.byType(VideoPill).at(1));
      final second = tester.widget<FakeAnchor>(anchors()).uri.toString();
      expect(second, startsWith('https://www.youtube.com/watch?v='));
      expect(second, isNot(first));
    });

    testWidgets('none for a control that only passes under a mouse at rest (a list scrolled by the wheel)', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      var opened = 0;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [linkAnchorsProvider.overrideWithValue(FakeLinkAnchors())],
          child: MaterialApp(
            home: ListView(
              controller: controller,
              itemExtent: 100,
              children: [
                for (var i = 0; i < 20; i++)
                  Center(
                    child: OutsideLink(
                      url: 'https://example.com/$i',
                      label: 'Link $i',
                      onOpen: () => opened++,
                      builder: (context, open) => SizedBox(width: 50, height: 50, child: GestureDetector(onTap: open)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      final gesture = await mouse(tester);
      // between two controls
      await gesture.moveTo(const Offset(400, 100));
      await tester.pump();
      controller.jumpTo(50);
      await tester.pump();
      await tester.pump();
      expect(anchors(), findsNothing);
      // the mouse moves and stays: the control under it gets its link
      await gesture.moveTo(const Offset(401, 100));
      await tester.pump();
      expect(anchors(), findsNothing);
      await tester.pump(linkAnchorDelay);
      expect(anchors(), findsOneWidget);
      expect(tester.widget<FakeAnchor>(anchors()).uri.toString(), 'https://example.com/1');
      // moving on before the delay: none
      await gesture.moveTo(const Offset(400, 300));
      await tester.pump(linkAnchorDelay ~/ 2);
      await gesture.moveTo(const Offset(400, 600));
      await tester.pump(linkAnchorDelay);
      expect(anchors(), findsNothing);
      expect(opened, 0);
    });

    testWidgets('every place: the video of a fiche, a song fiche, the expanded thumbnail, About and its footer', (
      tester,
    ) async {
      await pumpApp(tester, size: desk, links: FakeLinkAnchors());
      final gesture = await mouse(tester);
      Future<String> linkOver(Finder finder) async {
        await hover(tester, gesture, finder);
        expect(anchors(), findsOneWidget, reason: '$finder');
        // over the whole control (a tile: its picture and its name)
        final control = find.ancestor(of: finder, matching: find.byType(OutsideLink)).first;
        expect(tester.getRect(anchors()), tester.getRect(control), reason: '$finder');
        return tester.widget<FakeAnchor>(anchors()).uri.toString();
      }

      // the thumbnail of a row of an expanded window, with a mouse
      final thumbnail = find.descendant(of: find.byType(HighlightRow).at(1), matching: find.byType(Thumbnail));
      expect(await linkOver(thumbnail), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      expect(
        await linkOver(find.widgetWithText(FilledButton, 'Watch on YouTube')),
        'https://www.youtube.com/watch?v=bbbbbbbbbbb',
      );
      // the large preview plays in place on the web: not a link
      await hover(tester, gesture, find.byType(VideoPreview));
      expect(anchors(), findsNothing);
      await goToTab(tester, 'About');
      expect(await linkOver(find.text('Stickers')), contains('http'));
      expect(await linkOver(find.widgetWithText(FilledButton, 'Watch on Twitch')), 'https://www.twitch.tv/jonathanong');
      expect(await linkOver(find.text('Privacy policy')), 'https://ongmusic.nbros.dev/privacy-policy');
      await hover(tester, gesture, find.text('Licences'));
      expect(anchors(), findsNothing);
    });
  });

  group('clicks', () {
    testWidgets('a plain click opens the address as before; one the browser handles itself is left to it', (
      tester,
    ) async {
      final app = await pumpApp(tester, links: FakeLinkAnchors());
      await goToTab(tester, 'Ong Log');
      final gesture = await mouse(tester);
      final at = await hover(tester, gesture, find.byType(VideoPill).first);
      await click(tester, gesture, at);
      expect(app.effects.opened, hasLength(1));
      for (final key in [
        LogicalKeyboardKey.controlLeft,
        LogicalKeyboardKey.metaLeft,
        LogicalKeyboardKey.shiftLeft,
        LogicalKeyboardKey.altLeft,
      ]) {
        await click(tester, gesture, at, keys: [key]);
        expect(app.effects.opened, hasLength(1), reason: '$key: the browser opens it, not the app as well');
      }
      // the row keeps its own tap
      expect(find.byType(SongSheet), findsNothing);
    });

    testWidgets('without a link of the page (a touch), a click with a key held still opens it', (tester) async {
      final app = await pumpApp(tester, links: FakeLinkAnchors());
      await goToTab(tester, 'Ong Log');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.byType(VideoPill).first);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
      expect(app.effects.opened, hasLength(1));
    });

    testWidgets('a video playing in place: a plain click stops it, Ctrl/⌘ leaves it playing, Shift stops it', (
      tester,
    ) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, links: FakeLinkAnchors(), videos: videos);
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      Future<void> playIt() async {
        await tester.tap(find.byType(VideoPreview).hitTestable());
        await tester.pump();
        videos.videos.last.playerState = EmbeddedVideoState.playing;
        await tester.pumpAndSettle();
        expect(videos.alive, hasLength(1));
      }

      await playIt();
      // nothing of the page over the player
      final gesture = await mouse(tester);
      await hover(tester, gesture, find.byType(FakePlayerView));
      expect(anchors(), findsNothing);

      final button = find.widgetWithText(FilledButton, 'Watch on YouTube');
      final at = await hover(tester, gesture, button);
      for (final key in [LogicalKeyboardKey.controlLeft, LogicalKeyboardKey.metaLeft]) {
        await click(tester, gesture, at, keys: [key]);
        expect(videos.alive, hasLength(1), reason: '$key: a tab behind, the video goes on');
      }
      await click(tester, gesture, at, keys: [LogicalKeyboardKey.shiftLeft]);
      expect(videos.alive, isEmpty, reason: 'a window in front: never two sounds');
      expect(app.effects.opened, isEmpty);

      await playIt();
      await hover(tester, gesture, button);
      await click(tester, gesture, at);
      expect(videos.alive, isEmpty);
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
    });

    testWidgets('the "Watch on YouTube" of a refused video is a link: the player is gone', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, links: FakeLinkAnchors(), videos: videos);
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(VideoPreview).hitTestable());
      await tester.pump();
      videos.videos.last.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      final over = find.descendant(of: find.byType(VideoPreview), matching: find.byType(FilledButton));
      final gesture = await mouse(tester);
      await hover(tester, gesture, over);
      expect(anchors(), findsOneWidget);
      expect(tester.getRect(anchors()), tester.getRect(over));
      expect(find.byType(FakePlayerView), findsNothing);
    });
  });

  testWidgets('nothing moves: the controls are where they are in the native apps', (tester) async {
    Future<List<Rect>> layout({required bool links}) async {
      await tester.pumpWidget(const SizedBox());
      await pumpApp(tester, size: desk, links: links ? FakeLinkAnchors() : null);
      // the newest highlight has no video
      await tester.tap(find.descendant(of: find.byType(HighlightsPage), matching: find.text('I Will Survive')));
      await tester.pumpAndSettle();
      final rects = <Rect>[
        tester.getRect(find.widgetWithText(FilledButton, 'Watch on YouTube')),
        tester.getRect(find.descendant(of: find.byType(HighlightRow).first, matching: find.byType(Thumbnail))),
      ];
      await goToTab(tester, 'Ong Log');
      rects.add(tester.getRect(find.byType(VideoPill).first));
      await goToTab(tester, 'About');
      rects
        ..add(tester.getRect(find.text('Stickers')))
        ..add(tester.getRect(find.widgetWithText(FilledButton, 'Watch on Twitch')))
        ..add(tester.getRect(find.text('Privacy policy')));
      return rects;
    }

    expect(await layout(links: true), await layout(links: false));
  });
}
