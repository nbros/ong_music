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
    testWidgets('stops when another row is chosen, with the pointer or the keyboard', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final first = await play(tester, videos);
      await choose(tester, 'Song of Storms');
      expect(first.disposed, isTrue);
      expect(player(), findsNothing);
      final second = await play(tester, videos);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(second.disposed, isTrue);
      expect(videos.alive, isEmpty);
    });

    testWidgets('stops on a link of the fiche, and Back does not start it again', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final video = await play(tester, videos);
      await tester.tap(inPane(find.text('Played 2 times live')));
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      await tester.tap(inPane(find.byTooltip('Back')));
      await tester.pumpAndSettle();
      expect(playBadge(), findsOneWidget);
      expect(videos.videos, hasLength(1));
    });

    testWidgets('stops on a tab change (both panes stay alive out of sight), and does not come back', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: desk, videos: videos);
      await choose(tester, 'I Will Survive');
      final video = await play(tester, videos);
      await goToTab(tester, 'Ong Log');
      expect(video.disposed, isTrue);
      await goToTab(tester, 'Highlights');
      expect(playBadge(), findsOneWidget);
      expect(videos.videos, hasLength(1));
      // "Requested by" switches tabs too
      await play(tester, videos);
      await tester.tap(inPane(find.textContaining('Requested by')));
      await tester.pumpAndSettle();
      expect(videos.alive, isEmpty);
    });

    testWidgets('stops when the sheet closes, at once, not at the end of its slide', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, videos: videos);
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
        await tester.tap(detailsButtons().at(1));
        await tester.pumpAndSettle();
        final video = await play(tester, videos);
        await close();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(video.disposed, isTrue, reason: how);
        await tester.pumpAndSettle();
        expect(find.byType(BottomSheet), findsNothing, reason: how);
      }
      // a link of the sheet replaces it
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      await play(tester, videos);
      await tester.tap(find.text('Played 2 times live'));
      await tester.pumpAndSettle();
      expect(videos.alive, isEmpty);
    });

    testWidgets('window modes: a sheet moving into the pane stops, and nothing starts by itself', (tester) async {
      final videos = FakeVideoEmbedder();
      await pumpApp(tester, size: medium, videos: videos);
      await tester.tap(detailsButtons().at(1));
      await tester.pumpAndSettle();
      final video = await play(tester, videos);
      // compact ↔ medium keeps the sheet, and its video
      tester.view.physicalSize = const Size(412, 892);
      await tester.pumpAndSettle();
      expect(video.disposed, isFalse);
      expect(video.mounts, 1);
      tester.view.physicalSize = desk;
      await tester.pumpAndSettle();
      expect(video.disposed, isTrue);
      expect(find.byType(BottomSheet), findsNothing);
      expect(playBadge(), findsOneWidget);
      expect(videos.videos, hasLength(1));
      // the pane goes when the window narrows
      final second = await play(tester, videos);
      tester.view.physicalSize = medium;
      await tester.pumpAndSettle();
      expect(second.disposed, isTrue);
      expect(videos.alive, isEmpty);
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
      // the next row: it stops
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(videos.alive, isEmpty);
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
