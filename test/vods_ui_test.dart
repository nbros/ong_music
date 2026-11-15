// The actions of the VODs: "Watch in the VOD" in the menu of a play and as the button of a row without video,
// "Watch the VOD" in the head of the fiche of a stream; nothing of them without the file, and nothing moves when it
// comes.
import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/vod_offsets.dart';
import 'package:ong_music/src/data/vods.dart';
import 'package:ong_music/src/state/vods_state.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'keyboard_test.dart' show enterList, focusUnder, focusedIndex, narrow, press;
import 'fixtures.dart';
import 'ui_harness.dart';

// The streams of the test catalogue have no time on their "Stream Start" rows: their keys are their dates.
// 2024-03-02 (newest first in the Ong Log): I Will Survive at 2:03:00 (no video), Song of Storms at 0:20:00 (video);
// 2024-03-01: Lost Woods at 1:05:00 (no video), I Will Survive at 0:10:00 (video).
const _first = 'vod1aaaaaaa', _second = 'vod2aaaaaaa', _secondPart2 = 'vod2bbbbbbb';

/// The VOD of 1 March in one part, that of 2 March in two (part 1 of one hour).
final _file = VodFile.parse(
  'date\tpart\tid\tseconds\n'
  '2024-03-01\t1\t$_first\t21600\n'
  '2024-03-02\t1\t$_second\t3600\n'
  '2024-03-02\t2\t$_secondPart2\t',
);

/// The file of the VODs comes.
Future<void> _arrive(WidgetTester tester, [VodFile? file]) async {
  ProviderScope.containerOf(
    tester.element(find.byType(OngMusicApp)),
  ).read(vodFileProvider.notifier).take(file ?? _file);
  await tester.pumpAndSettle();
}

Finder _playRow(String date, String track) => find.byWidgetPredicate(
  (w) => w is PlayRow && w.play.track == track && w.catalogue.streamOf(w.play).date.toIso() == date,
);

Finder _historyRow(String date) =>
    find.byWidgetPredicate((w) => w is HistoryRow && w.catalogue.streamOf(w.play).date.toIso() == date);

/// The items of the open menu.
List<String> _items(WidgetTester tester) => [
  for (final item in tester.widgetList<PopupMenuItem<void>>(find.byType(PopupMenuItem<void>)))
    tester
        .widgetList<Text>(find.descendant(of: find.byWidget(item), matching: find.byType(Text)))
        .map((t) => t.data!)
        .join(),
];

Future<void> _menu(WidgetTester tester, Finder row) async {
  await tester.longPress(row);
  await tester.pumpAndSettle();
}

/// The boxes of the rows of the Ong Log and of what they show, widths included, by a description: each row, header
/// and type icon, the column of the title and the line under it (`row i column`), each text in that column
/// (`row i column text j`) and outside it (`row i text j`, the time). The texts inside a span of a widget have no box
/// of their own.
Map<String, Rect> _places(WidgetTester tester) {
  final places = <String, Rect>{};
  for (final (i, e) in find.byType(PlayRow).evaluate().indexed) {
    final row = find.byWidget(e.widget);
    final column = find.descendant(of: row, matching: find.byType(Expanded)).first;
    places['row $i'] = tester.getRect(row);
    places['row $i column'] = tester.getRect(column);
    final inColumn = find.descendant(of: column, matching: find.byType(Text)).evaluate().toSet();
    for (final (j, t) in find.descendant(of: row, matching: find.byType(Text)).evaluate().indexed) {
      final r = tester.getRect(find.byWidget(t.widget));
      if (r.isFinite) places[inColumn.contains(t) ? 'row $i column text $j' : 'row $i text $j'] = r;
    }
    places['row $i type'] = tester.getRect(find.descendant(of: row, matching: find.byType(PlayTypeIcon)));
  }
  for (final (i, e) in find.byType(StreamHeader).evaluate().indexed) {
    places['header $i'] = tester.getRect(find.byWidget(e.widget));
  }
  return places;
}

void main() {
  group('without the file (the branch missing, no network)', () {
    testWidgets('the menus, the rows and the fiches as before', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      expect(find.byType(VodButton), findsNothing);
      await _menu(tester, _playRow('2024-03-01', 'Lost Woods'));
      expect(_items(tester), ['Copy title']);
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(StreamHeader).first);
      await tester.pumpAndSettle();
      expect(find.byType(StreamSheet), findsOneWidget);
      expect(find.textContaining('Watch the VOD'), findsNothing);
    });
  });

  group('the menu of a play', () {
    testWidgets('"Watch in the VOD" opens its moment on YouTube; with a video, after "Watch on YouTube"', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await _menu(tester, _playRow('2024-03-01', 'Lost Woods'));
      expect(_items(tester), ['Copy title', 'Watch in the VOD']);
      await tester.tap(find.text('Watch in the VOD'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/$_first?t=3900']);

      await _menu(tester, _playRow('2024-03-01', 'I Will Survive'));
      expect(_items(tester), ['Copy title', 'Watch on YouTube', 'Watch in the VOD', 'Copy link', 'Share']);
      await tester.tap(find.text('Watch in the VOD'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.last.toString(), 'https://youtu.be/$_first?t=600');

      // in part 2, an hour (part 1) earlier
      await _menu(tester, _playRow('2024-03-02', 'I Will Survive'));
      await tester.tap(find.text('Watch in the VOD'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.last.toString(), 'https://youtu.be/$_secondPart2?t=3780');
    });

    testWidgets('none for a play the VOD does not reach', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      // part 1 of 2 March of unknown length: none of its plays can be placed
      await _arrive(tester, VodFile.parse('date\tpart\tid\n2024-03-02\t1\t$_second\n2024-03-02\t2\t$_secondPart2'));
      await _menu(tester, _playRow('2024-03-02', 'I Will Survive'));
      expect(_items(tester), ['Copy title']);
      expect(find.byType(VodButton), findsNothing);
    });
  });

  group('the button of a row', () {
    testWidgets('a play without video gets it in the column of the video button; those with a video keep theirs', (
      tester,
    ) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      for (final (date, track, vod) in [
        ('2024-03-02', 'I Will Survive', true),
        ('2024-03-02', 'Song of Storms', false),
        ('2024-03-01', 'Lost Woods', true),
        ('2024-03-01', 'I Will Survive', false),
      ]) {
        final row = _playRow(date, track);
        expect(find.descendant(of: row, matching: find.byType(VodButton)), vod ? findsOneWidget : findsNothing);
        expect(find.descendant(of: row, matching: find.byType(VideoPill)), vod ? findsNothing : findsOneWidget);
      }
      // where the pill of a row with a video is
      final pill = tester.getRect(
        find.descendant(of: _playRow('2024-03-02', 'Song of Storms'), matching: find.byType(VideoPill)),
      );
      final button = tester.getRect(
        find.descendant(of: _playRow('2024-03-02', 'I Will Survive'), matching: find.byType(VodButton)),
      );
      expect((button.left, button.width, button.height), (pill.left, pill.width, pill.height));
      expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Watch in the VOD'), findsNWidgets(2));
      await tester.tap(find.descendant(of: _playRow('2024-03-01', 'Lost Woods'), matching: find.byType(VodButton)));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/$_first?t=3900']);
      expect(find.byType(StreamSheet), findsNothing, reason: 'the button, not the row');
    });

    testWidgets('the offsets: when their file comes, the button and the menu open the moved moment; a play they put '
        'before the start of the recording loses both', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      final lostWoods = _playRow('2024-03-01', 'Lost Woods');
      final survive = _playRow('2024-03-02', 'I Will Survive');
      expect(find.descendant(of: survive, matching: find.byType(VodButton)), findsOneWidget);
      ProviderScope.containerOf(tester.element(find.byType(OngMusicApp)))
          .read(vodOffsetsProvider.notifier)
          .take(OffsetFile.parse('date\tuptime\toffset\tnote\n2024-03-01\t\t-600\n2024-03-02\t2:00:00+\t-7400\n'));
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: lostWoods, matching: find.byType(VodButton)));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/$_first?t=3300']);
      await _menu(tester, lostWoods);
      await tester.tap(find.text('Watch in the VOD'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u').last, 'https://youtu.be/$_first?t=3300');
      // 2:03:00 - 7400 s: 20 s before the start of the recording
      expect(find.descendant(of: survive, matching: find.byType(VodButton)), findsNothing);
      await _menu(tester, survive);
      expect(_items(tester), ['Copy title']);
    });

    testWidgets('screen readers: a button of its own, named, with its action', (tester) async {
      final semantics = tester.ensureSemantics();
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      expect(
        tester.getSemantics(
          find.descendant(of: _playRow('2024-03-01', 'Lost Woods'), matching: find.byType(VodButton)),
        ),
        isSemantics(label: 'Watch in the VOD', isButton: true, hasTapAction: true),
      );
      semantics.dispose();
    });

    testWidgets('the keyboard: → to it, as to a video button', (tester) async {
      await pumpApp(tester, size: narrow, desktop: true);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await enterList(tester);
      // the first play (I Will Survive, 2 March) has no video, but a VOD
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusUnder<VodButton>(), isTrue);
      expect(focusedIndex(), 1);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusUnder<VodButton>(), isFalse);
    });

    testWidgets('nothing moves when the file comes, after the list is on the screen', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      final before = _places(tester);
      expect(before, isNotEmpty);
      await _arrive(tester);
      expect(find.byType(VodButton), findsNWidgets(2));
      final after = _places(tester);
      expect(after.keys, before.keys);
      // the rows that gain the button
      final gained = {
        for (final (i, e) in find.byType(PlayRow).evaluate().indexed)
          if (find.descendant(of: find.byWidget(e.widget), matching: find.byType(VodButton)).evaluate().isNotEmpty) i,
      };
      expect(gained, hasLength(2));
      bool ofGained(String key) => gained.any((i) => key.startsWith('row $i column'));
      // everything else keeps its box, widths included: rows, headers, times, type icons, the rows without the button
      for (final key in before.keys.where((k) => !ofGained(k))) {
        expect(after[key], before[key], reason: key);
      }
      // what changes, in a row that gains the button: the column of the title and the line under it narrows by 42 px
      // (the button's 48 against the 6 of the space it takes the place of), from its right edge; its texts keep their
      // place and height, their width cut to the column's (a long title is cut 42 px earlier)
      for (final i in gained) {
        final column = before['row $i column']!, narrower = after['row $i column']!;
        expect(narrower, Rect.fromLTWH(column.left, column.top, column.width - 42, column.height));
        for (final key in before.keys.where((k) => k.startsWith('row $i column text'))) {
          final text = before[key]!;
          expect(after[key], Rect.fromLTWH(text.left, text.top, math.min(text.width, narrower.width), text.height));
        }
      }
      // (the line under the title fills its column: it is one of the texts cut)
      expect(
        gained.any(
          (i) => before.keys.any((k) => k.startsWith('row $i column text') && after[k]!.width < before[k]!.width),
        ),
        isTrue,
      );
    });
  });

  group('the fiche of a stream', () {
    testWidgets('one part: "Watch the VOD", from the start', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await tester.tap(find.widgetWithText(StreamHeader, 'Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      expect(find.text('Watch the VOD'), findsOneWidget);
      expect(find.textContaining('part'), findsNothing);
      await tester.tap(find.text('Watch the VOD'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/$_first']);
    });

    testWidgets('two parts: a button each', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await tester.tap(find.widgetWithText(StreamHeader, 'Sat 2 Mar 2024'));
      await tester.pumpAndSettle();
      expect(find.text('Watch the VOD'), findsNothing);
      await tester.tap(find.text('VOD 2'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('VOD 1'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/$_secondPart2', 'https://youtu.be/$_second']);
      // its setlist has the buttons of the rows too
      expect(find.descendant(of: find.byType(StreamSheet), matching: find.byType(VodButton)), findsOneWidget);
    });

    testWidgets('open when another file comes: its buttons open the new links, none added or moved', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await tester.tap(find.widgetWithText(StreamHeader, 'Sat 2 Mar 2024'));
      await tester.pumpAndSettle();
      final head = [
        for (final label in ['VOD 1', 'VOD 2']) tester.getRect(find.text(label)),
      ];
      // part 1 re-uploaded, part 2 gone
      await _arrive(tester, VodFile.parse('date\tpart\tid\n2024-03-02\t1\tvod3ccccccc'));
      expect([
        for (final label in ['VOD 1', 'VOD 2']) tester.getRect(find.text(label)),
      ], head);
      await tester.tap(find.text('VOD 1'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/vod3ccccccc']);
      // the part the file no longer has: disabled, in its place
      await tester.tap(find.text('VOD 2'));
      await tester.pumpAndSettle();
      expect(app.effects.opened, hasLength(1));
      // the plays of its setlist: the new file too (one part of unknown length: I Will Survive at 2:03:00)
      await tester.tap(find.descendant(of: find.byType(StreamSheet), matching: find.byType(VodButton)));
      await tester.pumpAndSettle();
      expect(app.effects.opened.last.toString(), 'https://youtu.be/vod3ccccccc?t=7380');
    });

    testWidgets('open in the pane through a refresh of the sheets: as many buttons as when it opened', (tester) async {
      final app = await pumpApp(tester, size: const Size(1280, 800));
      await goToTab(tester, 'Ong Log');
      // one part when the fiche opens
      await _arrive(tester, VodFile.parse('date\tpart\tid\n2024-03-02\t1\tvod3ccccccc'));
      await tester.tap(find.widgetWithText(StreamHeader, 'Sat 2 Mar 2024'));
      await tester.pumpAndSettle();
      final button = tester.getRect(find.text('Watch the VOD'));
      // two parts in the next file, then the sheets again: another object for the same stream
      await _arrive(tester);
      app.notifier.emit(
        loadedState(
          testCatalogue(
            moreSongs: [sRow(date: '2024-03-02 23:30:00', title: 'One more song')],
          ),
          testNow,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.descendant(of: find.byType(StreamSheet), matching: find.text('One more song')), findsOneWidget);
      expect(tester.getRect(find.text('Watch the VOD')), button);
      expect(find.text('VOD 2'), findsNothing);
      await tester.tap(find.text('Watch the VOD'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.last.toString(), 'https://youtu.be/$_second');
    });

    testWidgets('open when the file comes: its head stays as it is, nothing pushed down', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await tester.tap(find.widgetWithText(StreamHeader, 'Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      final rows = find.descendant(of: find.byType(StreamSheet), matching: find.byType(PlayRow));
      final before = [for (final e in rows.evaluate()) tester.getRect(find.byWidget(e.widget))];
      await _arrive(tester);
      expect(find.text('Watch the VOD'), findsNothing, reason: 'the next time it opens');
      expect([for (final e in rows.evaluate()) tester.getRect(find.byWidget(e.widget))], before);
    });
  });

  group('the fiche of a song', () {
    testWidgets('its plays without video get the button; the play with a video keeps its own', (tester) async {
      final app = await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await tester.tap(_playRow('2024-03-01', 'I Will Survive'));
      await tester.pumpAndSettle();
      expect(find.byType(SongSheet), findsOneWidget);
      expect(find.descendant(of: _historyRow('2024-03-02'), matching: find.byType(VodButton)), findsOneWidget);
      expect(find.descendant(of: _historyRow('2024-03-01'), matching: find.byType(VodButton)), findsNothing);
      expect(find.descendant(of: _historyRow('2024-03-01'), matching: find.byType(VideoPill)), findsOneWidget);
      await tester.tap(find.descendant(of: _historyRow('2024-03-02'), matching: find.byType(VodButton)));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/$_secondPart2?t=3780']);
    });
  });
}
