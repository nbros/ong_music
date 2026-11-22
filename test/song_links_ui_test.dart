// The original of a song (song_links.tsv): "Listen to the original" and "Copy original link" in the menus of the rows,
// a line of the fiche of the song (under its stats boxes) and of a highlight (after "Played N times live"); nothing of
// them without a link, and nothing moves when the file comes.
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/song_links.dart';
import 'package:ong_music/src/data/vods.dart';
import 'package:ong_music/src/state/song_links_state.dart';
import 'package:ong_music/src/state/vods_state.dart';
import 'package:ong_music/src/ui/actions.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/detail_pane.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/video_preview.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:ong_music/src/web/embedded_video.dart';

import 'ui_harness.dart';

const _listen = 'Listen to the original';
const _copyOriginal = 'Copy original link';

/// I Will Survive (played twice, two videos) under two spellings, the last one winning; Song of Storms (played once)
/// from 42 s; nothing for Lost Woods.
final _links = SongLinks.parse(
  'link\ttitle\n'
  'deadsurviv0\tGloria Gaynor - I Will Survive\n'
  'stormsorig1?t=42\tZelda - Song of Storms\n'
  'origsurviv1\tgloria gaynor: i will survive\n',
);

/// The file of the links comes.
Future<void> _arrive(WidgetTester tester) async {
  ProviderScope.containerOf(tester.element(find.byType(OngMusicApp))).read(songLinksProvider.notifier).take(_links);
  await tester.pumpAndSettle();
}

Finder _highlightRow(String track) => find.ancestor(of: find.text(track), matching: find.byType(HighlightRow)).first;

Finder _playRow(String date, String track) => find.byWidgetPredicate(
  (w) => w is PlayRow && w.play.track == track && w.catalogue.streamOf(w.play).date.toIso() == date,
);

Finder _tooltip(String tooltip) => find.byWidgetPredicate((w) => w is IconButton && w.tooltip == tooltip);

/// The copy button of the line of the original, whatever its state.
Finder _copyButton() => find.byWidgetPredicate(
  (w) => w is IconButton && (w.tooltip == _copyOriginal || w.tooltip == 'Copied') && w.icon is AnimatedSwitcher,
);

List<String> _items(WidgetTester tester) => [
  for (final item in tester.widgetList<PopupMenuItem<void>>(find.byType(PopupMenuItem<void>)))
    tester
        .widgetList<Text>(find.descendant(of: find.byWidget(item), matching: find.byType(Text)))
        .map((t) => t.data!)
        .join(),
];

List<IconData?> _icons(WidgetTester tester) => [
  for (final item in tester.widgetList<PopupMenuItem<void>>(find.byType(PopupMenuItem<void>)))
    tester.widget<Icon>(find.descendant(of: find.byWidget(item), matching: find.byType(Icon))).icon,
];

Future<void> _longPress(WidgetTester tester, Finder row) async {
  await tester.longPress(row);
  await tester.pumpAndSettle();
}

Future<void> _choose(WidgetTester tester, String item) async {
  await tester.tap(find.descendant(of: find.byType(PopupMenuItem<void>), matching: find.text(item)));
  await tester.pumpAndSettle();
}

Future<void> _openSong(WidgetTester tester, String date, String track) async {
  await goToTab(tester, 'Ong Log');
  await tester.tap(_playRow(date, track));
  await tester.pumpAndSettle();
  expect(find.byType(SongSheet), findsOneWidget);
}

Future<void> _openHighlight(WidgetTester tester, String track) async {
  await tester.tap(find.descendant(of: _highlightRow(track), matching: detailsButtons()));
  await tester.pumpAndSettle();
  expect(find.byType(HighlightSheet), findsOneWidget);
}

Finder _inSong(Finder matching) => find.descendant(of: find.byType(SongSheet), matching: matching);

Finder _inHighlight(Finder matching) => find.descendant(of: find.byType(HighlightSheet), matching: matching);

void main() {
  test('the labels, approved by the user', () {
    expect(listenToTheOriginalText, _listen);
    expect(copyOriginalLinkText, _copyOriginal);
    expect(copyVideoLinkText, 'Copy video link');
  });

  group('the fiche of a song', () {
    testWidgets('a line under the stats boxes: its short link, which it opens; the copy button copies it, in place', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await _arrive(tester);
      await _openSong(tester, '2024-03-01', 'I Will Survive');
      final line = _inSong(find.text(_listen));
      expect(line, findsOneWidget);
      expect(_inSong(find.text('youtu.be/origsurviv1')), findsOneWidget);
      expect(_inSong(find.byIcon(Icons.music_note)), findsOneWidget);
      expect(_inSong(find.byIcon(Icons.chevron_right)), findsNothing, reason: 'it leads outside the app');
      // under the boxes, over the videos
      final boxes = tester.getRect(_inSong(find.text('first played')));
      final videos = tester.getRect(_inSong(find.text('Every time it was played')));
      expect(tester.getRect(line).top, greaterThan(boxes.bottom));
      expect(tester.getRect(line).bottom, lessThan(videos.top));
      expect(tester.getRect(line).bottom, lessThan(tester.getRect(_inSong(find.byType(Thumbnail)).first).top));
      // the copy icon in the column of the copy button of the title
      final titleCopy = _tooltip('Copy title');
      expect(tester.getRect(_copyButton()).center.dx, tester.getRect(titleCopy).center.dx);
      expect(tester.getSize(_copyButton()), tester.getSize(titleCopy));

      await tester.tap(line);
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/origsurviv1']);
      expect(find.byType(SongSheet), findsOneWidget, reason: 'the fiche stays');

      final parts = [
        line,
        _inSong(find.text('youtu.be/origsurviv1')),
        _copyButton(),
        _inSong(find.byType(Thumbnail)).first,
      ];
      List<Rect> rects() => [for (final p in parts) tester.getRect(p)];
      final before = rects();
      tester.takeAnnouncements();
      await tester.tap(_copyButton());
      await tester.pump();
      expect(app.effects.clipboard, 'https://youtu.be/origsurviv1');
      expect(tester.takeAnnouncements().map((a) => a.message), ['Copied']);
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(_copyButton()).tooltip, 'Copied');
      expect(find.descendant(of: _copyButton(), matching: find.byIcon(Icons.check)), findsOneWidget);
      expect(find.text('Copied'), findsNothing, reason: 'no message');
      expect(rects(), before);
      expect(app.effects.opened, hasLength(1), reason: 'the copy opens nothing');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
      expect(tester.widget<IconButton>(_copyButton()).tooltip, _copyOriginal);
      expect(rects(), before);
    });

    testWidgets('a song without a link, or no file: no line', (tester) async {
      await pumpApp(tester);
      await _openSong(tester, '2024-03-01', 'I Will Survive');
      expect(find.text(_listen), findsNothing);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await _arrive(tester);
      await _openSong(tester, '2024-03-01', 'Lost Woods');
      expect(find.text(_listen), findsNothing);
      expect(_copyButton(), findsNothing);
    });

    testWidgets('the file comes while the fiche is open: nothing moves; the next fiche has the line', (tester) async {
      await pumpApp(tester);
      await _openSong(tester, '2024-03-01', 'I Will Survive');
      final parts = [
        _inSong(find.text('first played')),
        _inSong(find.byType(Thumbnail)).first,
        _inSong(find.text('Every time it was played')),
        find.byType(SongSheet),
      ];
      List<Rect> rects() => [for (final p in parts) tester.getRect(p)];
      final before = rects();
      await _arrive(tester);
      expect(find.text(_listen), findsNothing);
      expect(rects(), before);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await _openSong(tester, '2024-03-01', 'I Will Survive');
      expect(_inSong(find.text(_listen)), findsOneWidget);
    });

    testWidgets('in the pane, another song in the same place: its own link', (tester) async {
      await pumpApp(tester, size: const Size(1280, 800), desktop: true);
      await _arrive(tester);
      await goToTab(tester, 'Ong Log');
      await tester.tap(_playRow('2024-03-01', 'I Will Survive'));
      await tester.pumpAndSettle();
      expect(_inSong(find.text('youtu.be/origsurviv1')), findsOneWidget);
      await tester.tap(_playRow('2024-03-02', 'Song of Storms'));
      await tester.pumpAndSettle();
      expect(find.byType(DetailPane), findsWidgets);
      expect(_inSong(find.text('youtu.be/origsurviv1')), findsNothing);
      expect(_inSong(find.text('youtu.be/stormsorig1')), findsOneWidget);
      await tester.tap(_playRow('2024-03-01', 'Lost Woods'));
      await tester.pumpAndSettle();
      expect(_inSong(find.text(_listen)), findsNothing);
    });

    testWidgets('screen readers: the line is one button, the copy button another, named', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      await _arrive(tester);
      await _openSong(tester, '2024-03-01', 'I Will Survive');
      expect(
        tester.getSemantics(_inSong(find.text(_listen))),
        matchesSemantics(
          label: '$_listen\nyoutu.be/origsurviv1',
          isButton: true,
          hasTapAction: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      final copy = tester.getSemantics(_copyButton()).getSemanticsData();
      expect((copy.tooltip, copy.flagsCollection.isButton), (_copyOriginal, true));
      semantics.dispose();
    });
  });

  group('the fiche of a highlight', () {
    testWidgets('a line after "Played N times live", before the vocals; the copy button in the column of the star', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await _arrive(tester);
      await _openHighlight(tester, 'I Will Survive');
      final line = _inHighlight(find.text(_listen));
      expect(line, findsOneWidget);
      expect(
        tester.getRect(line).top,
        greaterThan(tester.getRect(_inHighlight(find.text('Played 2 times live'))).bottom),
      );
      expect(tester.getRect(line).bottom, lessThan(tester.getRect(_inHighlight(find.text('With vocals'))).top));
      expect(tester.getRect(_copyButton()).center.dx, tester.getRect(_tooltip('Add to favourites')).center.dx);
      await tester.tap(_copyButton());
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, 'https://youtu.be/origsurviv1');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('a song played once has it too; a start time: in the address opened, not shown', (tester) async {
      final app = await pumpApp(tester);
      await _arrive(tester);
      await _openHighlight(tester, 'Song of Storms');
      expect(_inHighlight(find.textContaining('times live')), findsNothing);
      expect(_inHighlight(find.text('youtu.be/stormsorig1')), findsOneWidget);
      await tester.tap(_inHighlight(find.text(_listen)));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/stormsorig1?t=42']);
      await tester.tap(_copyButton());
      await tester.pumpAndSettle();
      expect(app.effects.clipboard, 'https://youtu.be/stormsorig1?t=42');
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('without a link: no line', (tester) async {
      await pumpApp(tester);
      await _arrive(tester);
      await _openHighlight(tester, "How Far I'll Go");
      expect(find.text(_listen), findsNothing);
    });
  });

  group('the menus of the rows', () {
    testWidgets('a play: after the VOD, Listen to the original; Copy original link after Copy video link', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      ProviderScope.containerOf(tester.element(find.byType(OngMusicApp)))
          .read(vodFileProvider.notifier)
          .take(VodFile.parse('date\tpart\tid\tseconds\n2024-03-01\t1\tvod1aaaaaaa\t21600\n'));
      await _arrive(tester);
      final row = _playRow('2024-03-01', 'I Will Survive');
      await _longPress(tester, row);
      expect(_items(tester), [
        'Copy title',
        'Watch on YouTube',
        'Watch in the VOD',
        _listen,
        'Copy video link',
        _copyOriginal,
        'Share',
      ]);
      expect(_icons(tester), [
        Icons.copy,
        Icons.play_arrow,
        vodIcon,
        Icons.music_note,
        Icons.link,
        Icons.link,
        Icons.share,
      ]);
      await _choose(tester, _listen);
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/origsurviv1']);
      await _longPress(tester, row);
      await _choose(tester, _copyOriginal);
      expect(app.effects.clipboard, 'https://youtu.be/origsurviv1');
      await waitForMessage(tester);
      await _longPress(tester, row);
      await _choose(tester, 'Copy video link');
      expect(app.effects.clipboard, 'https://youtu.be/bbbbbbbbbbb');
      await waitForMessage(tester);
    });

    testWidgets('a play without video: its original all the same; without a link, none', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await _longPress(tester, _playRow('2024-03-02', 'I Will Survive'));
      expect(_items(tester), ['Copy title', _listen, _copyOriginal]);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await _longPress(tester, _playRow('2024-03-01', 'Lost Woods'));
      expect(_items(tester), ['Copy title']);
    });

    testWidgets('a highlight: Listen to the original second, Copy original link after Copy video link', (tester) async {
      final app = await pumpApp(tester);
      await _arrive(tester);
      await _longPress(tester, _highlightRow('I Will Survive'));
      expect(_items(tester), ['Copy title', _listen, 'Copy video link', _copyOriginal, 'Share', 'Add to favourites']);
      await _choose(tester, _copyOriginal);
      expect(app.effects.clipboard, 'https://youtu.be/origsurviv1');
      await waitForMessage(tester);
      await _longPress(tester, _highlightRow('Song of Storms'));
      await _choose(tester, _listen);
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/stormsorig1?t=42']);
      await _longPress(tester, _highlightRow("How Far I'll Go"));
      expect(_items(tester), ['Copy title', 'Add to favourites']);
    });

    testWidgets('no file: the menus as before', (tester) async {
      await pumpApp(tester);
      await _longPress(tester, _highlightRow('I Will Survive'));
      expect(_items(tester), ['Copy title', 'Copy video link', 'Share', 'Add to favourites']);
    });
  });

  testWidgets('the web app: the video playing in the app stops when the original opens, never two sounds', (
    tester,
  ) async {
    final videos = FakeVideoEmbedder();
    final app = await pumpApp(tester, size: const Size(1280, 800), videos: videos, pointer: PointerKind.mouse);
    await _arrive(tester);
    await tester.tap(_highlightRow('I Will Survive'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(VideoPreview).hitTestable());
    await tester.pump();
    final video = videos.videos.last..playerState = EmbeddedVideoState.playing;
    await tester.pumpAndSettle();
    expect(video.disposed, isFalse);
    await tester.tap(_inHighlight(find.text(_listen)), kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/origsurviv1']);
    expect(video.disposed, isTrue);
  });
}
