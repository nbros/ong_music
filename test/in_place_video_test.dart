// The video of a highlight played in place of its preview (the web app): its three states at one place, its
// failures, how long it lives, never two sounds, Enter, screen readers; and the native apps, unchanged.
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/detail_pane.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/list_scaffold.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/theme.dart';
import 'package:ong_music/src/ui/video_preview.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/embedded_video.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// A desktop browser window: expanded.
const desk = Size(1440, 900);

/// A window too narrow for the two panes: sheets.
const medium = Size(830, 900);

const refusedText = 'This video only plays on YouTube.';

/// The large preview on screen.
Finder preview() => find.byType(VideoPreview).hitTestable();

/// The box of the preview, in every state.
Finder previewBox() => find.descendant(of: find.byType(VideoPreview), matching: find.byType(ClipRRect)).first;

/// The fake player on screen.
Finder player() => find.byType(FakePlayerView);

/// The spinner of a video on its way.
Finder spinner() => find.descendant(of: find.byType(VideoPreview), matching: find.byType(CircularProgressIndicator));

/// The play button drawn over the preview.
Finder playBadge() => find.descendant(of: find.byType(VideoPreview), matching: find.byIcon(Icons.play_arrow));

/// The row of the Highlights list showing [track].
Finder highlightRow(String track) => find.ancestor(of: find.text(track), matching: find.byType(HighlightRow));

/// [matching] inside the detail pane of the Highlights tab.
Finder inPane(Finder matching) => find.descendant(of: find.byType(DetailPane).first, matching: matching);

/// Chooses the row of [track] in the list of an expanded window.
Future<void> choose(WidgetTester tester, String track) async {
  await tester.tap(highlightRow(track).first);
  await tester.pumpAndSettle();
}

/// Taps the preview: the player is on its way (its spinner turns: no settling).
Future<void> tapPreview(WidgetTester tester) async {
  await tester.tap(preview());
  await tester.pump();
}

/// Taps the preview, and YouTube's player plays.
Future<FakeVideo> play(WidgetTester tester, FakeVideoEmbedder videos) async {
  await tapPreview(tester);
  final video = videos.videos.last;
  video.playerState = EmbeddedVideoState.playing;
  await tester.pumpAndSettle();
  return video;
}

/// The mini player: its box, the bar and the video.
Finder miniPlayer() => find.ancestor(of: find.byTooltip('Close'), matching: find.byType(Positioned));

/// [video] plays in the mini player: the same player, alive, the only one.
void expectInMiniPlayer(WidgetTester tester, FakeVideo video, FakeVideoEmbedder videos, {String? reason}) {
  expect(video.disposed, isFalse, reason: reason);
  expect(videos.alive, [video], reason: reason);
  expect(miniPlayer(), findsOneWidget, reason: reason);
  expect(player(), findsOneWidget, reason: reason);
  final box = tester.getRect(miniPlayer());
  expect(
    tester.getRect(player()),
    Rect.fromLTRB(box.left, box.top + 40, box.right, box.bottom),
    reason: '$reason: under the bar',
  );
}

/// [video] plays in place of the preview of its fiche, the mini player gone.
void expectInPlace(WidgetTester tester, FakeVideo video, FakeVideoEmbedder videos, {String? reason}) {
  expect(video.disposed, isFalse, reason: reason);
  expect(videos.alive, [video], reason: reason);
  expect(miniPlayer(), findsNothing, reason: reason);
  expect(tester.getRect(player()), tester.getRect(previewBox()), reason: reason);
}

/// Where the parts of a highlight fiche are: nothing may move when the video comes or goes.
List<Rect> ficheLayout(WidgetTester tester) => [
  tester.getRect(previewBox()),
  tester.getRect(find.descendant(of: find.byType(HighlightSheet), matching: find.byType(SelectableText)).first),
  tester.getRect(find.widgetWithText(FilledButton, 'Watch on YouTube').last),
  tester.getRect(find.byTooltip('Share').last),
];

void main() {
  group('native apps', () {
    test('no in-place player outside a browser', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(videoEmbedderProvider), isNull);
      expect(container.read(inPlaceVideosProvider).available, isFalse);
    });

    testWidgets('the preview opens the video on YouTube; screen readers skip it', (tester) async {
      final handle = tester.ensureSemantics();
      final app = await pumpApp(tester, size: desk);
      await choose(tester, 'I Will Survive');
      expect(find.bySemanticsLabel('Play the video here'), findsNothing);
      await tester.tap(preview());
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
      expect(spinner(), findsNothing);
      expect(playBadge(), findsOneWidget);
      // Enter too
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.effects.opened, hasLength(2));
      // nothing over the navigator: no mini player
      expect(find.ancestor(of: find.byType(Navigator), matching: find.byType(Overlay)), findsNothing);
      handle.dispose();
    });

    testWidgets('a sheet: the same', (tester) async {
      final app = await pumpApp(tester);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await tester.tap(preview());
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
    });
  });

  group('three states at one place', () {
    testWidgets('in the pane: the preview, the player, the refusal; nothing of the fiche moves', (tester) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final before = ficheLayout(tester);
      expect(playBadge(), findsOneWidget);
      expect(player(), findsNothing);

      await tapPreview(tester);
      expect(videos.only.youtubeId, 'bbbbbbbbbbb');
      expect(app.effects.opened, isEmpty, reason: 'played here, not on YouTube');
      // on its way: the preview stays, a spinner in the badge, the player already there (transparent)
      expect(spinner(), findsOneWidget);
      expect(playBadge(), findsNothing);
      expect(tester.getRect(player()), tester.getRect(previewBox()));
      expect(ficheLayout(tester), before);

      videos.only.playerState = EmbeddedVideoState.playing;
      await tester.pumpAndSettle();
      expect(spinner(), findsNothing);
      expect(playBadge(), findsNothing);
      expect(tester.getRect(player()), tester.getRect(previewBox()));
      expect(ficheLayout(tester), before);
      expect(videos.only.mounts, 1, reason: 'the player keeps its element when the badge goes');

      videos.only.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      expect(videos.alive, isEmpty);
      expect(player(), findsNothing);
      expect(find.text(refusedText), findsOneWidget);
      final refusedButton = find.descendant(
        of: find.byType(VideoPreview),
        matching: find.widgetWithText(FilledButton, 'Watch on YouTube'),
      );
      expect(tester.getRect(previewBox()).contains(tester.getCenter(refusedButton)), isTrue);
      expect(ficheLayout(tester), before);
    });

    testWidgets('in a sheet: the same', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, videos: videos);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final before = ficheLayout(tester);
      await tapPreview(tester);
      expect(ficheLayout(tester), before);
      expect(tester.getRect(player()), tester.getRect(previewBox()));
      videos.only.playerState = EmbeddedVideoState.playing;
      await tester.pumpAndSettle();
      expect(ficheLayout(tester), before);
      videos.only.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      expect(find.text(refusedText), findsOneWidget);
      expect(ficheLayout(tester), before);
    });

    testWidgets('the refusal fits a low preview at large text', (tester) async {
      final videos = FakeVideoEmbedder();
      // a phone held sideways: the preview is two fifths of the window high
      await pumpApp(tester, size: const Size(892, 412), textScale: 2, videos: videos);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await tapPreview(tester);
      videos.only.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final box = tester.getRect(previewBox());
      final text = tester.getRect(find.text(refusedText));
      expect(box.contains(text.topLeft) && box.contains(text.bottomRight), isTrue);
    });
  });

  group('when the video cannot play here', () {
    testWidgets('refused: Watch on YouTube over the preview, remembered for the session', (tester) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      await tapPreview(tester);
      videos.only.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: find.byType(VideoPreview), matching: find.text('Watch on YouTube')));
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');

      // another fiche and back: refused at once, nothing tried again
      await choose(tester, 'Song of Storms');
      expect(playBadge(), findsOneWidget);
      await choose(tester, 'I Will Survive');
      expect(find.text(refusedText), findsOneWidget);
      expect(playBadge(), findsNothing);
      await tester.tap(previewBox(), warnIfMissed: false);
      await tester.pump();
      expect(videos.videos, hasLength(1));
      // in a sheet too
      tester.view.physicalSize = medium;
      await tester.pumpAndSettle();
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      expect(find.text(refusedText), findsOneWidget);
    });

    testWidgets('failed (no script, no player in time): the same, but tried again next time', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      await tapPreview(tester);
      videos.only.playerState = EmbeddedVideoState.failed;
      await tester.pumpAndSettle();
      expect(videos.alive, isEmpty);
      expect(find.text(refusedText), findsOneWidget);
      await choose(tester, 'Song of Storms');
      await choose(tester, 'I Will Survive');
      expect(find.text(refusedText), findsNothing);
      expect(playBadge(), findsOneWidget);
      await tapPreview(tester);
      expect(videos.videos, hasLength(2));
      expect(spinner(), findsOneWidget);
    });

    testWidgets('a failure after the video was shown: the same', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final video = await play(tester, videos);
      video.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      expect(player(), findsNothing);
      expect(find.text(refusedText), findsOneWidget);
    });
  });

  group('lifetime', () {
    testWidgets('another row: the same player goes on in the mini player, and back in place with its row', (
      tester,
    ) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final video = await play(tester, videos);
      expect(miniPlayer(), findsNothing);
      await choose(tester, 'Song of Storms');
      expectInMiniPlayer(tester, video, videos);
      expect(playBadge(), findsOneWidget, reason: 'the other fiche, its own preview');
      // where it first appears: the bottom right corner of the window
      expect(tester.getRect(miniPlayer()), const Rect.fromLTWH(1440 - 16 - 320, 900 - 16 - 40 - 180, 320, 220));
      // with the keyboard too, and back
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, video, videos);
      await choose(tester, 'I Will Survive');
      expectInPlace(tester, video, videos);
    });

    testWidgets('a link of the fiche: in the mini player; Back: in place again', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final video = await play(tester, videos);
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, video, videos);
      await tester.tap(inPane(find.byTooltip('Back')));
      await tester.pumpAndSettle();
      expectInPlace(tester, video, videos);
    });

    testWidgets('another tab (both panes stay alive out of sight): the mini player over it, until the tab is back', (
      tester,
    ) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final video = await play(tester, videos);
      for (final tab in ['Ong Log', 'About']) {
        await goToTab(tester, tab);
        expectInMiniPlayer(tester, video, videos);
      }
      await goToTab(tester, 'Highlights');
      expectInPlace(tester, video, videos);
      // "Requested by" switches tabs too
      await tester.tap(inPane(find.textContaining('Requested by')));
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, video, videos);
    });

    testWidgets('the sheet closing: the mini player at once, not at the end of its slide; in place when it opens', (
      tester,
    ) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, videos: videos);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final video = await play(tester, videos);
      for (final (how, close) in [
        ('the scrim', () => tester.tapAt(const Offset(206, 20))),
        ('back', () => tester.binding.handlePopRoute()),
        // by its drag handle: under a finger, the content scrolls
        (
          'a fling',
          () => tester.flingFrom(
            tester.getTopLeft(find.byType(BottomSheet)) + const Offset(206, 18),
            const Offset(0, 600),
            2000,
          ),
        ),
      ]) {
        await close();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(BottomSheet), findsOneWidget, reason: '$how: still sliding');
        expectInMiniPlayer(tester, video, videos, reason: how);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing, reason: how);
        expectInMiniPlayer(tester, video, videos, reason: how);
        await tester.tap(detailsButtons().at(1));
        await tester.pumpAndSettle();
        expectInPlace(tester, video, videos, reason: how);
      }
      // above the navigation bar of a phone
      await tester.tapAt(const Offset(206, 20));
      await tester.pumpAndSettle();
      final width = (412 - 2 * 16) * 2 / 3;
      expect(
        tester.getRect(miniPlayer()),
        Rect.fromLTWH(412 - 16 - width, 892 - 68 - 16 - 40 - width * 9 / 16, width, 40 + width * 9 / 16),
      );
      // a link of the sheet replaces it
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Played 2 times live'));
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, video, videos);
    });

    testWidgets('window modes: the video follows its fiche from the sheet to the pane and back', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: medium, videos: videos);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final video = await play(tester, videos);
      // compact ↔ medium keeps the sheet, and its video where it is
      tester.view.physicalSize = const Size(412, 892);
      await tester.pumpAndSettle();
      expectInPlace(tester, video, videos);
      expect(video.mounts, 1);
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);
      expectInPlace(tester, video, videos);
      expect(inPane(find.byType(VideoPreview)), findsOneWidget);
      expect(videos.videos, hasLength(1), reason: 'nothing starts by itself');
      // the pane goes when the window narrows
      tester.view.physicalSize = medium;
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, video, videos);
    });

    testWidgets('goes on through scrolling, searching, filtering, the star, a refresh, the pointer, a resize', (
      tester,
    ) async {
      final videos = FakeVideoEmbedder();
      // more rows than the list shows, each with a video
      final more = [
        for (var i = 1; i <= 30; i++)
          hRow(order: '${3 + i}', title: 'Song $i', link: 'https://youtu.be/${i.toString().padLeft(11, 's')}'),
      ];
      final app = await pumpApp(
        tester,
        size: desk,
        videos: videos,
        state: CatalogueState(
          catalogue: testCatalogue(moreHighlights: more),
          fetchedAt: testNow,
        ),
      );
      await choose(tester, 'Song 29');
      final video = await play(tester, videos);
      final listView = find.descendant(of: find.byType(ListFrame).first, matching: find.byType(Scrollable)).first;

      await tester.drag(listView, const Offset(0, -300));
      await tester.pumpAndSettle();
      await tester.drag(listView, const Offset(0, 300));
      await tester.pumpAndSettle();
      await tester.enterText(searchField(), 'zelda');
      await tester.pumpAndSettle();
      expect(highlightRow('Song 29'), findsNothing, reason: 'its row gone, the fiche stays');
      await tester.enterText(searchField(), 'song 2');
      await tester.pumpAndSettle();
      await tester.enterText(searchField(), '');
      await tester.pumpAndSettle();
      await tester.tap(chip('Disney'));
      await tester.pumpAndSettle();
      await tester.tap(chip('Game OST'));
      await tester.pumpAndSettle();
      await tester.tap(chip('All'));
      await tester.pumpAndSettle();
      // the star chip appears with the first favourite
      await tester.tap(inPane(find.byTooltip('Add to favourites')));
      await tester.pumpAndSettle();
      await tester.tap(inPane(find.byTooltip('Remove from favourites')));
      await tester.pumpAndSettle();
      app.notifier.emit(
        CatalogueState(
          catalogue: testCatalogue(
            moreHighlights: [
              ...more,
              hRow(order: '40', title: 'Chopin - Ballade', link: 'https://youtu.be/ccccccccccc'),
            ],
          ),
          fetchedAt: testNow,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.widget<VideoPreview>(find.byType(VideoPreview)).highlight.track, 'Song 29');
      // a mouse, then touch again
      final mouse = TestPointer(1, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(mouse.hover(const Offset(300, 500)));
      await tester.pumpAndSettle();
      expect(AppLayout.mouseOf(tester.element(find.byType(VideoPreview))), isTrue);
      await tester.tapAt(const Offset(1400, 880));
      await tester.pumpAndSettle();
      expect(AppLayout.mouseOf(tester.element(find.byType(VideoPreview))), isFalse);
      tester.view.physicalSize = const Size(1200, 800);
      await tester.pumpAndSettle();

      expect(video.disposed, isFalse);
      expect(video.mounts, 1, reason: 'never loaded again');
      expect(videos.videos, hasLength(1));
      expect(player(), findsOneWidget);
    });
  });

  group('mini player', () {
    /// I Will Survive playing in the mini player of an expanded window, Song of Storms in the pane.
    Future<FakeVideo> inMiniPlayer(WidgetTester tester, FakeVideoEmbedder videos) async {
      await choose(tester, 'I Will Survive');
      final video = await play(tester, videos);
      await choose(tester, 'Song of Storms');
      expectInMiniPlayer(tester, video, videos);
      return video;
    }

    testWidgets('another video replaces it: never two sounds', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      final first = await inMiniPlayer(tester, videos);
      final second = await play(tester, videos);
      expect(first.disposed, isTrue);
      expectInPlace(tester, second, videos);
    });

    testWidgets('its close button stops the video; the fiche then shows its preview', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      final video = await inMiniPlayer(tester, videos);
      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      expect(miniPlayer(), findsNothing);
      expect(player(), findsNothing);
      await choose(tester, 'I Will Survive');
      expect(playBadge(), findsOneWidget);
      expect(videos.videos, hasLength(1));
    });

    testWidgets('a failure closes it; a refusal is remembered', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      var video = await inMiniPlayer(tester, videos);
      video.playerState = EmbeddedVideoState.failed;
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      expect(miniPlayer(), findsNothing);
      // nothing said in the fiche, which did not see it: it may play another time
      await choose(tester, 'I Will Survive');
      expect(find.text(refusedText), findsNothing);
      expect(playBadge(), findsOneWidget);

      // loading in the mini player (a spinner over black), then refused
      await tapPreview(tester);
      video = videos.videos.last;
      // (the spinner turns: no settling)
      await tester.tap(highlightRow('Song of Storms').first);
      await tester.pump();
      await tester.pump();
      expect(find.descendant(of: miniPlayer(), matching: find.byType(CircularProgressIndicator)), findsOneWidget);
      video.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      expect(miniPlayer(), findsNothing);
      await choose(tester, 'I Will Survive');
      expect(find.text(refusedText), findsOneWidget);
    });

    testWidgets('anything opening YouTube stops it', (tester) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, videos: videos, pointer: PointerKind.mouse);
      final video = await inMiniPlayer(tester, videos);
      await tester.tap(inPane(find.widgetWithText(FilledButton, 'Watch on YouTube')));
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=aaaaaaaaaaa');
      expect(video.disposed, isTrue);
      expect(miniPlayer(), findsNothing);
    });

    testWidgets('Show details: the fiche again, the video back in place (pane, sheet)', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      final video = await inMiniPlayer(tester, videos);
      await tester.tap(find.byTooltip('Show details'));
      await tester.pumpAndSettle();
      expectInPlace(tester, video, videos);
      expect(tester.widget<VideoPreview>(find.byType(VideoPreview)).highlight.track, 'I Will Survive');

      // a phone: the sheet comes again, in place of another one
      tester.view.physicalSize = const Size(412, 892);
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, video, videos);
      await tester.tap(detailsButtons().at(0));
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, video, videos);
      await tester.tap(find.byTooltip('Show details'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expectInPlace(tester, video, videos);
      expect(tester.widget<VideoPreview>(find.byType(VideoPreview)).highlight.track, 'I Will Survive');
    });

    testWidgets('moved by its title, resized by its corner: inside the window, the video in 16:9, remembered', (
      tester,
    ) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, videos: videos, pointer: PointerKind.mouse);
      final video = await inMiniPlayer(tester, videos);
      final start = tester.getRect(miniPlayer());
      final title = find.descendant(of: miniPlayer(), matching: find.text('I Will Survive'));

      // the player lets the pointer through while it moves
      final gesture = await tester.startGesture(tester.getCenter(title), kind: PointerDeviceKind.mouse);
      await gesture.moveBy(const Offset(-300, 0));
      await gesture.moveBy(const Offset(-200, -300));
      await tester.pump();
      expect(video.pointerThrough, isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(video.pointerThrough, isFalse);
      expect(tester.getRect(miniPlayer()), start.shift(const Offset(-500, -300)));
      expect(app.prefs.getString('miniPlayer'), '516.0,316.0,320.0');

      // no further than the edges
      await tester.drag(title, const Offset(-5000, -5000));
      await tester.pumpAndSettle();
      expect(tester.getRect(miniPlayer()).topLeft, const Offset(8, 8));

      // its corner: wider and higher at once, the bottom right corner where it was
      final grip = find.descendant(of: miniPlayer(), matching: find.byIcon(Icons.open_in_full));
      await tester.drag(title, const Offset(600, 400));
      await tester.pumpAndSettle();
      final before = tester.getRect(miniPlayer());
      await tester.drag(grip, const Offset(-160, -90));
      await tester.pumpAndSettle();
      var after = tester.getRect(miniPlayer());
      expect(after.bottomRight, before.bottomRight);
      expect(after.width, closeTo(before.width + 160, 1));
      var shown = tester.getRect(player());
      expect(shown.width / shown.height, closeTo(16 / 9, 0.001));
      // no narrower than 200, no larger than the window
      await tester.drag(grip, const Offset(2000, 2000));
      await tester.pumpAndSettle();
      expect(tester.getRect(miniPlayer()).width, 200);
      await tester.drag(grip, const Offset(-5000, -5000));
      await tester.pumpAndSettle();
      after = tester.getRect(miniPlayer());
      expect(const Rect.fromLTRB(8, 8, 1440 - 8, 900 - 8).intersect(after), after);
      expect(after.width, 1440 - 16, reason: 'as wide as the window lets it');
      shown = tester.getRect(player());
      expect(shown.width / shown.height, closeTo(16 / 9, 0.001));

      // a smaller window, then a turned phone: it comes back inside, 16:9
      for (final size in [const Size(1000, 700), const Size(892, 412)]) {
        tester.view.physicalSize = size;
        await tester.pumpAndSettle();
        expect(miniPlayer(), findsOneWidget);
        final rect = tester.getRect(miniPlayer());
        expect(Rect.fromLTRB(8, 8, size.width - 8, size.height - 8).intersect(rect), rect, reason: '$size');
        shown = tester.getRect(player());
        expect(shown.width / shown.height, closeTo(16 / 9, 0.001), reason: '$size');
      }
      expect(video.disposed, isFalse);
      expect(video.mounts, 2, reason: 'shown in the mini player once, from the preview');
    });

    testWidgets('where it was left, at the next visit', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos, prefs: {'miniPlayer': '100.0,50.0,400.0'});
      await inMiniPlayer(tester, videos);
      expect(tester.getRect(miniPlayer()), const Rect.fromLTRB(1440 - 100 - 400, 900 - 50 - 40 - 225, 1440 - 100, 850));
    });

    testWidgets('its buttons: reached with the Tab key, named for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await inMiniPlayer(tester, videos);
      for (final name in ['Show details', 'Close']) {
        expect(
          tester.getSemantics(find.byTooltip(name)),
          isSemantics(tooltip: name, isButton: true, hasTapAction: true, isFocusable: true),
        );
      }
      // after the last button of the page
      bool hasFocus(String name) =>
          FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Tooltip>()?.message == name;
      var reached = false;
      for (var i = 0; i < 80 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reached = hasFocus('Show details');
      }
      expect(reached, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pump();
      expect(hasFocus('Close'), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(videos.alive, isEmpty);
      handle.dispose();
    });

    testWidgets('over a sheet of another fiche, and over a dialog', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, videos: videos);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final video = await play(tester, videos);
      await tester.tap(find.text('Played 2 times live'));
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
      expectInMiniPlayer(tester, video, videos);
      // the pointer reaches it, not the scrim of the sheet; so does the Tab key, from the sheet
      expect(find.byTooltip('Close').hitTestable(), findsOneWidget);
      var reached = false;
      for (var i = 0; i < 40 && !reached; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        reached =
            FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<Tooltip>()?.message == 'Close';
      }
      expect(reached, isTrue);
      expect(find.byType(BottomSheet), findsOneWidget);
    });
  });

  group('never two sounds', () {
    testWidgets('anything opening YouTube stops it first', (tester) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, videos: videos, pointer: PointerKind.mouse);
      await choose(tester, 'I Will Survive');
      // the button of the fiche
      var video = await play(tester, videos);
      await tester.tap(inPane(find.widgetWithText(FilledButton, 'Watch on YouTube')));
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      expect(app.effects.opened, hasLength(1));
      // the thumbnail of a row, with a mouse
      video = await play(tester, videos);
      await tester.tap(
        find.descendant(of: highlightRow('Song of Storms'), matching: find.byType(Thumbnail)),
        kind: PointerDeviceKind.mouse,
      );
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      expect(app.effects.opened, hasLength(2));
      // a video of the song fiche
      await play(tester, videos);
      expect(videos.alive, hasLength(1));
    });

    testWidgets('one player at a time', (tester) async {
      final videos = FakeVideoEmbedder();
      final catalogue = testCatalogue();
      Highlight withVideo(String id) => catalogue.highlights.firstWhere((h) => h.youtubeId == id);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            videoEmbedderProvider.overrideWithValue(videos),
            thumbnailImageProvider.overrideWithValue((url) => MemoryImage(transparentPng)),
          ],
          child: MaterialApp(
            theme: buildTheme(Brightness.light),
            home: Column(
              children: [
                SizedBox(width: 320, child: VideoPreview(highlight: withVideo('aaaaaaaaaaa'))),
                SizedBox(width: 320, child: VideoPreview(highlight: withVideo('bbbbbbbbbbb'))),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byType(VideoPreview).first);
      await tester.pump();
      await tester.tap(find.byType(VideoPreview).last);
      await tester.pump();
      expect(videos.videos.map((v) => (v.youtubeId, v.disposed)), [('aaaaaaaaaaa', true), ('bbbbbbbbbbb', false)]);
      // the first preview is back
      expect(playBadge(), findsOneWidget);
      expect(spinner(), findsOneWidget);
    });
  });

  group('Enter', () {
    testWidgets('plays the selected highlight in place', (tester) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, videos: videos);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(videos.only.youtubeId, 'bbbbbbbbbbb');
      expect(app.effects.opened, isEmpty);
      expect(spinner(), findsOneWidget);
      // once more: the same video goes on
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(videos.videos, hasLength(1));
      videos.only.playerState = EmbeddedVideoState.playing;
      await tester.pumpAndSettle();
      // the next row: it goes on in the mini player
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expectInMiniPlayer(tester, videos.only, videos);
    });

    testWidgets('opens YouTube when the fiche is under another one, or the video was refused', (tester) async {
      final videos = FakeVideoEmbedder();
      final app = await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.effects.opened.single.toString(), 'https://www.youtube.com/watch?v=bbbbbbbbbbb');
      expect(videos.videos, isEmpty);

      await tester.tap(inPane(find.byTooltip('Back')));
      await tester.pumpAndSettle();
      await tapPreview(tester);
      videos.only.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(app.effects.opened, hasLength(2));
      expect(videos.videos, hasLength(1));
    });
  });

  group('screen readers', () {
    testWidgets('the preview is a button of its own; the player then speaks for itself', (tester) async {
      final handle = tester.ensureSemantics();
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final button = find.bySemanticsLabel('Play the video here');
      expect(button, findsOneWidget);
      expect(tester.getSemantics(button), isSemantics(isButton: true, hasTapAction: true));
      // the action plays it
      tester.semantics.tap(find.semantics.byLabel('Play the video here'));
      await tester.pump();
      expect(videos.alive, hasLength(1));
      expect(find.bySemanticsLabel('Loading the video'), findsOneWidget);
      expect(find.bySemanticsLabel('Play the video here'), findsNothing);
      videos.only.playerState = EmbeddedVideoState.playing;
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel('Loading the video'), findsNothing);
      expect(find.bySemanticsLabel('Play the video here'), findsNothing);
      videos.only.playerState = EmbeddedVideoState.refused;
      await tester.pumpAndSettle();
      expect(find.bySemanticsLabel(refusedText), findsOneWidget);
      expect(find.bySemanticsLabel('Watch on YouTube'), findsNWidgets(2));
      handle.dispose();
    });
  });
}
