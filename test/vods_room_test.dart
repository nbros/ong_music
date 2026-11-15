// The room of the VOD buttons: a list shows the buttons of the VODs in its rows only when, with the button, the column
// of the title keeps room for a title of normal length (vodButtonTitleRoom, scaled with the text). The same answer for
// every row of a list, in the Ong Log, the stream fiche and the song fiche, phone and wide layouts, the detail pane;
// never changed by the arrival of the file. And the short buttons of a VOD in several parts.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/vods.dart';
import 'package:ong_music/src/state/vods_state.dart';
import 'package:ong_music/src/ui/app.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';
import 'package:ong_music/src/ui/widgets.dart';

import 'ui_harness.dart';

// The streams of the test catalogue have no time on their "Stream Start" rows: their keys are their dates.
// 2024-03-02 (newest first in the Ong Log): I Will Survive at 2:03:00 (no video), Song of Storms at 0:20:00 (video);
// 2024-03-01: Lost Woods at 1:05:00 (no video), I Will Survive at 0:10:00 (video).
const _first = 'vod1aaaaaaa', _second = 'vod2aaaaaaa', _secondPart2 = 'vod2bbbbbbb';

final _file = VodFile.parse(
  'date\tpart\tid\tseconds\n'
  '2024-03-01\t1\t$_first\t21600\n'
  '2024-03-02\t1\t$_second\t3600\n'
  '2024-03-02\t2\t$_secondPart2\t',
);

Future<void> _arrive(WidgetTester tester, [VodFile? file]) async {
  ProviderScope.containerOf(
    tester.element(find.byType(OngMusicApp)),
  ).read(vodFileProvider.notifier).take(file ?? _file);
  await tester.pumpAndSettle();
}

/// The boxes of the rows of [type] under [scope] and of everything in them, widths included.
List<Rect> _boxes(WidgetTester tester, Type type, [Finder? scope]) {
  final rows = scope == null ? find.byType(type) : find.descendant(of: scope, matching: find.byType(type));
  return [
    for (final e in rows.evaluate())
      for (final w in [
        e,
        ...find.descendant(of: find.byWidget(e.widget), matching: find.byType(Text)).evaluate(),
        ...find.descendant(of: find.byWidget(e.widget), matching: find.byType(Expanded)).evaluate(),
      ])
        if (tester.getRect(find.byWidget(w.widget)) case final r when r.isFinite) r,
  ];
}

/// The width of the column of the title of the first row of [type] under [scope] without a video (whose column no
/// pill narrows), as it is now: without a button.
double _column(WidgetTester tester, Type type, [Finder? scope]) {
  bool plain(Widget w) => switch (w) {
    PlayRow(:final catalogue, :final play) => catalogue.highlightOf(play)?.youtubeId == null,
    HistoryRow(:final catalogue, :final play) => catalogue.highlightOf(play)?.youtubeId == null,
    _ => false,
  };
  final rows = find.byWidgetPredicate((w) => w.runtimeType == type && plain(w));
  final row = scope == null ? rows.first : find.descendant(of: scope, matching: rows).first;
  return tester.getSize(find.descendant(of: row, matching: find.byType(Expanded)).first).width;
}

int _buttons(Type type, [Finder? scope]) => find
    .descendant(
      of: scope == null ? find.byType(type) : find.descendant(of: scope, matching: find.byType(type)),
      matching: find.byType(VodButton),
    )
    .evaluate()
    .length;

/// What a list's rows lose to the button: 48 px against the 6 px space of a play row, 48 against nothing in the
/// history of a song.
const _taken = {PlayRow: 42.0, HistoryRow: 48.0};

/// The figures of the configurations measured, for the report.
final _figures = <String>[];

/// Checks one list of rows of [type] under [scope] (the whole screen when null), [eligible] of them with a VOD and
/// without video: without the file, its column of the title ([_column]); with the file, the buttons in all of those
/// rows when the column keeps [vodButtonTitleRoom] scaled with the text beside the button, in none otherwise; and the
/// rows exactly as before when none shows. Returns whether the buttons show.
Future<bool> _check(
  WidgetTester tester,
  String name,
  Type type,
  int eligible,
  double scale,
  Future<void> Function() open, [
  Finder? scope,
]) async {
  await open();
  final column = _column(tester, type, scope);
  final before = _boxes(tester, type, scope);
  await _arrive(tester);
  final room = column - _taken[type]!;
  final shown = room >= vodButtonTitleRoom * scale;
  expect(_buttons(type, scope), shown ? eligible : 0, reason: name);
  if (!shown) expect(_boxes(tester, type, scope), before, reason: '$name: the rows as without the file');
  _figures.add(
    '$name: column ${column.toStringAsFixed(0)} px, ${room.toStringAsFixed(0)} with the button, '
    'threshold ${(vodButtonTitleRoom * scale).toStringAsFixed(0)}: ${shown ? 'shown' : 'hidden'}',
  );
  return shown;
}

void main() {
  // the figures of the report: flutter test --dart-define=VOD_ROOM_FIGURES=true test/vods_room_test.dart
  tearDownAll(() {
    if (!const bool.fromEnvironment('VOD_ROOM_FIGURES')) return;
    for (final f in _figures) {
      debugPrint(f);
    }
  });

  group('the room of the row buttons', () {
    for (final (width, scale, expected) in [
      (412.0, 1.0, true),
      (360.0, 1.0, true),
      (320.0, 1.0, false),
      (412.0, 1.3, true),
      (360.0, 1.3, false),
      (320.0, 1.3, false),
      (412.0, 2.0, false),
      (360.0, 2.0, false),
      (320.0, 2.0, false),
    ]) {
      final name = '${width.toInt()} dp, text ×$scale';
      testWidgets('$name: the Ong Log ${expected ? 'shows' : 'hides'} them, all its rows alike', (tester) async {
        await pumpApp(tester, size: Size(width, 892), textScale: scale);
        final shown = await _check(tester, '$name, Ong Log', PlayRow, 2, scale, () => goToTab(tester, 'Ong Log'));
        expect(shown, expected);
        // the menu has the item either way
        await tester.longPress(find.byWidgetPredicate((w) => w is PlayRow && w.play.track == 'Lost Woods'));
        await tester.pumpAndSettle();
        expect(find.text('Watch in the VOD'), findsOneWidget);
      });

      testWidgets('$name: the fiches of a stream and of a song, as their lists', (tester) async {
        await pumpApp(tester, size: Size(width, 892), textScale: scale);
        await goToTab(tester, 'Ong Log');
        final setlist = find.byType(StreamSheet);
        await _check(tester, '$name, stream fiche', PlayRow, 1, scale, () async {
          await tester.tap(find.widgetWithText(StreamHeader, 'Sat 2 Mar 2024'));
          await tester.pumpAndSettle();
        }, setlist);
        Navigator.of(tester.element(setlist)).pop();
        await tester.pumpAndSettle();
        ProviderScope.containerOf(tester.element(find.byType(OngMusicApp))).invalidate(vodFileProvider);
        await tester.pumpAndSettle();
        await _check(tester, '$name, song fiche', HistoryRow, 1, scale, () async {
          await tester.tap(
            find.byWidgetPredicate(
              (w) => w is PlayRow && w.play.track == 'I Will Survive' && w.catalogue.streamOf(w.play).date.day == 1,
            ),
          );
          await tester.pumpAndSettle();
        }, find.byType(SongSheet));
      });
    }

    testWidgets('a wide window: the list and the detail pane, each by its own room', (tester) async {
      await pumpApp(tester, size: const Size(1440, 900), desktop: true);
      await goToTab(tester, 'Ong Log');
      final pane = find.byType(StreamSheet);
      await tester.tap(find.widgetWithText(StreamHeader, 'Sat 2 Mar 2024'));
      await tester.pumpAndSettle();
      expect(pane, findsOneWidget);
      final listColumn = _column(tester, PlayRow);
      final paneColumn = _column(tester, PlayRow, pane);
      await _arrive(tester);
      expect(_buttons(PlayRow, pane), 1);
      expect(find.byType(VodButton), findsNWidgets(3), reason: 'two in the list, one in the pane');
      _figures.add(
        'wide 1440 dp: list column ${listColumn.toStringAsFixed(0)} px (${(listColumn - 42).toStringAsFixed(0)} with '
        'the button), detail pane ${paneColumn.toStringAsFixed(0)} px (${(paneColumn - 42).toStringAsFixed(0)}): shown',
      );
    });

    testWidgets('a resize across the threshold is what changes it; the file never does', (tester) async {
      await pumpApp(tester, size: const Size(412, 892), textScale: 1.3);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      expect(find.byType(VodButton), findsNWidgets(2));
      tester.view.physicalSize = const Size(360, 892);
      await tester.pumpAndSettle();
      expect(find.byType(VodButton), findsNothing, reason: 'narrower: the column would keep less than 229 px');
      tester.view.physicalSize = const Size(412, 892);
      await tester.pumpAndSettle();
      expect(find.byType(VodButton), findsNWidgets(2));
    });
  });

  group('the buttons of a VOD in several parts', () {
    Future<void> openSecond(WidgetTester tester, {VodFile? file}) async {
      await goToTab(tester, 'Ong Log');
      await _arrive(tester, file);
      await tester.tap(find.widgetWithText(StreamHeader, 'Sat 2 Mar 2024'));
      await tester.pumpAndSettle();
    }

    testWidgets('"VOD 1", "VOD 2" side by side on one line, with the icon; the head one line of buttons high', (
      tester,
    ) async {
      await pumpApp(tester);
      await openSecond(tester);
      final one = tester.getRect(find.ancestor(of: find.text('VOD 1'), matching: find.byType(FilledButton)).first);
      final two = tester.getRect(find.ancestor(of: find.text('VOD 2'), matching: find.byType(FilledButton)).first);
      expect(one.top, two.top, reason: 'one line');
      expect(two.left, greaterThan(one.right));
      final wrap = tester.getRect(find.descendant(of: find.byType(StreamSheet), matching: find.byType(Wrap)));
      expect(wrap.height, one.height, reason: 'one line of buttons');
      for (final label in ['VOD 1', 'VOD 2']) {
        expect(
          find.descendant(
            of: find.ancestor(of: find.text(label), matching: find.byType(FilledButton)).first,
            matching: find.byIcon(vodIcon),
          ),
          findsOneWidget,
        );
      }
      expect(find.text('Watch the VOD, part 1'), findsNothing);
      // its full name as its tooltip
      expect(find.byWidgetPredicate((w) => w is Tooltip && w.message == 'Watch the VOD, part 2'), findsOneWidget);
    });

    testWidgets('screen readers hear the full name, as a button with its action', (tester) async {
      final semantics = tester.ensureSemantics();
      final app = await pumpApp(tester);
      await openSecond(tester);
      final node = tester.getSemantics(find.ancestor(of: find.text('VOD 1'), matching: find.byType(Tooltip)).first);
      expect(node, isSemantics(label: 'Watch the VOD, part 1', isButton: true, hasTapAction: true, isEnabled: true));
      tester.semantics.tap(find.semantics.byLabel('Watch the VOD, part 2'));
      await tester.pumpAndSettle();
      expect(app.effects.opened.map((u) => '$u'), ['https://youtu.be/$_secondPart2']);
      semantics.dispose();
    });

    testWidgets('one part keeps "Watch the VOD"', (tester) async {
      await pumpApp(tester);
      await goToTab(tester, 'Ong Log');
      await _arrive(tester);
      await tester.tap(find.widgetWithText(StreamHeader, 'Fri 1 Mar 2024'));
      await tester.pumpAndSettle();
      expect(find.text('Watch the VOD'), findsOneWidget);
      expect(find.text('VOD 1'), findsNothing);
    });

    testWidgets('many parts and large text: a second line, nothing over the edge', (tester) async {
      await pumpApp(tester, size: const Size(320, 892), textScale: 2);
      final file = VodFile.parse(
        'date\tpart\tid\tseconds\n${[for (var i = 1; i <= 6; i++) '2024-03-02\t$i\tvodpart${i}aaa\t3600'].join('\n')}',
      );
      await openSecond(tester, file: file);
      expect(tester.takeException(), isNull, reason: 'no overflow');
      final tops = {
        for (var i = 1; i <= 6; i++)
          tester.getRect(find.ancestor(of: find.text('VOD $i'), matching: find.byType(FilledButton)).first).top,
      };
      expect(tops.length, greaterThan(1), reason: 'wrapped');
      for (var i = 1; i <= 6; i++) {
        final box = tester.getRect(find.ancestor(of: find.text('VOD $i'), matching: find.byType(FilledButton)).first);
        expect(box.right, lessThanOrEqualTo(320), reason: 'VOD $i within the screen');
      }
    });
  });
}
