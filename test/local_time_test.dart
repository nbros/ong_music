// The time of each song in the zone of the device; every date as written in the sheet. The sheet writes both in
// US Eastern time; the viewers below are fixed offsets from UTC, never the zone of the machine running the tests.
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:ong_music/src/ui/sheets.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

/// A viewer at the fixed offset [hours] from UTC.
DateTime Function(DateTime) utcPlus(int hours) =>
    (instant) => instant.toUtc().add(Duration(hours: hours));

const _lgtm = 'LGTM Looks Good to Me - Claude Opus 5.5';

/// The stream of 12 November 2026 as the sheet writes it (US Eastern): started at 21:34, "Some Game - Opening" at
/// 21:52, "LGTM…" at 01:39 the day after, a row without time; the video of LGTM, its "Stream Source" the 12th.
CatalogueState _state() => CatalogueState(
  catalogue: catalogueOf(
    highlights: [
      hRow(
        title: _lgtm,
        genre: 'ONGRIGINAL',
        link: 'https://youtu.be/eeeeeeeeeee',
        stream: '2026/11/12',
        upload: '2026-11-14',
        notes: 'Played live on stream on 2026-11-12.',
      ),
    ],
    songs: [
      start('2026/11/12 21:34'),
      sRow(date: '2026/11/12 21:52', uptime: '0:18:00', title: 'Some Game - Opening'),
      sRow(date: '2026/11/13 01:39', uptime: '4:05:00', title: _lgtm),
      sRow(date: '', title: 'Some Band - No Time'),
    ],
  ),
  fetchedAt: testNow,
);

Finder _playRow(String title) => find.byWidgetPredicate((w) => w is PlayRow && w.play.title == title);
Finder _highlightRow(String title) => find.byWidgetPredicate((w) => w is HighlightRow && w.highlight.title == title);

/// The time column of the play row of [title], in [scope] when given.
String _timeOf(WidgetTester tester, String title, {Finder? scope}) {
  final row = scope == null ? _playRow(title) : find.descendant(of: scope, matching: _playRow(title));
  return tester.widgetList<Text>(find.descendant(of: row, matching: find.byType(Text))).first.data!;
}

/// The genre · date line of the highlight row of [title].
String _metaOf(WidgetTester tester, String title) {
  final texts = tester.widgetList<Text>(find.descendant(of: _highlightRow(title), matching: find.byType(Text)));
  return texts.map((t) => t.data ?? t.textSpan!.toPlainText()).last.replaceAll('￼', '').trim();
}

Future<void> _close(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

/// The times of the songs in the Ong Log list, its search results and the setlist, then back to the list.
Future<void> _expectTimes(WidgetTester tester, {required String opening, required String lgtm}) async {
  await goToTab(tester, 'Ong Log');
  expect(_timeOf(tester, 'Some Game - Opening'), opening);
  expect(_timeOf(tester, _lgtm), lgtm);
  expect(_timeOf(tester, 'Some Band - No Time'), '–');

  await tester.enterText(searchField(), 'lgtm');
  await tester.pumpAndSettle();
  expect(find.byType(PlayRow), findsOneWidget);
  expect(_timeOf(tester, _lgtm), lgtm, reason: 'search results');
  await tester.enterText(searchField(), '');
  await tester.pumpAndSettle();

  await tester.tap(find.text('Thu 12 Nov 2026'));
  await tester.pumpAndSettle();
  final setlist = find.byType(StreamSheet);
  expect(_timeOf(tester, _lgtm, scope: setlist), lgtm, reason: 'setlist');
  expect(_timeOf(tester, 'Some Game - Opening', scope: setlist), opening, reason: 'setlist');
  await _close(tester);
}

/// Every date as the sheet writes it: the header of the stream, the setlist title, the history row of the song,
/// the date of its video, the highlight row, "Played live on" and "Uploaded". A date converted to the viewer's zone
/// moves to the day after for a viewer east of New York (the stream starts in the evening) and to the day before for
/// one west of it, from the sheet's midnight.
Future<void> _expectSheetDates(WidgetTester tester) async {
  await goToTab(tester, 'Ong Log');
  expect(find.text('Thu 12 Nov 2026'), findsOneWidget, reason: 'stream header');

  await tester.tap(find.text('Thu 12 Nov 2026'));
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: find.byType(StreamSheet), matching: find.text('Thu 12 Nov 2026')),
    findsOneWidget,
    reason: 'setlist title',
  );
  await _close(tester);

  await tester.tap(_playRow(_lgtm));
  await tester.pumpAndSettle();
  expect(
    find.descendant(of: find.byType(HistoryRow), matching: find.text('Thu 12 Nov 2026')),
    findsOneWidget,
    reason: 'history row',
  );
  expect(
    find.descendant(of: find.byType(SongSheet), matching: find.text('12 Nov')),
    findsOneWidget,
    reason: 'the date under the video of the song',
  );
  expect(find.bySemanticsLabel('Video of 12 Nov'), findsOneWidget, reason: 'and what a screen reader says of it');
  await _close(tester);

  await goToTab(tester, 'Highlights');
  expect(_metaOf(tester, _lgtm), 'Ongriginal · 12 Nov', reason: 'highlight row');
  await tester.tap(find.descendant(of: _highlightRow(_lgtm), matching: find.byTooltip('Details')));
  await tester.pumpAndSettle();
  expect(find.text('Played live on Thu 12 Nov 2026'), findsOneWidget);
  expect(find.text('Uploaded 14 Nov'), findsOneWidget);
  expect(find.text('Played live on stream on 2026-11-12.'), findsOneWidget, reason: 'the note, which agrees');
  await _close(tester);
}

void main() {
  testWidgets('a viewer at UTC+1 (Paris in winter): the times move, the dates do not', (tester) async {
    await pumpApp(tester, state: _state(), wallTime: utcPlus(1));
    await _expectTimes(tester, opening: '03:52', lgtm: '07:39');
    await _expectSheetDates(tester);
  });

  testWidgets('a viewer at UTC+11 (Sydney in summer): the times of the afternoon, the dates of the sheet', (
    tester,
  ) async {
    await pumpApp(tester, state: _state(), wallTime: utcPlus(11));
    await _expectTimes(tester, opening: '13:52', lgtm: '17:39');
    await _expectSheetDates(tester);
  });

  testWidgets('a viewer at UTC−8: three hours earlier than New York, the dates of the sheet', (tester) async {
    await pumpApp(tester, state: _state(), wallTime: utcPlus(-8));
    await _expectTimes(tester, opening: '18:52', lgtm: '22:39');
    await _expectSheetDates(tester);
  });

  testWidgets('a viewer in New York sees the sheet as written', (tester) async {
    await pumpApp(tester, state: _state());
    await _expectTimes(tester, opening: '21:52', lgtm: '01:39');
    await _expectSheetDates(tester);
  });

  testWidgets('the zone is asked for each instant: the viewer\'s own daylight saving shows', (tester) async {
    // a viewer whose clock moves forward at 2026-03-29 01:00 UTC (Paris)
    DateTime paris(DateTime t) => t.toUtc().add(Duration(hours: t.isBefore(DateTime.utc(2026, 3, 29, 1)) ? 1 : 2));
    final state = CatalogueState(
      catalogue: catalogueOf(
        songs: [
          start('2026/03/28 20:00'),
          sRow(date: '2026/03/28 20:30', title: 'Before - The Change'),
          sRow(date: '2026/03/28 21:30', title: 'After - The Change'),
        ],
      ),
      fetchedAt: testNow,
    );
    await pumpApp(tester, state: state, wallTime: paris);
    await goToTab(tester, 'Ong Log');
    expect(find.text('Sat 28 Mar 2026'), findsOneWidget);
    expect(_timeOf(tester, 'Before - The Change'), '01:30');
    expect(_timeOf(tester, 'After - The Change'), '03:30');
  });

  testWidgets('a stream on New Year\'s Eve: "first in" and "first played" keep the year of the sheet', (tester) async {
    // 21:30 on 31 December in New York is already 2026 at UTC+1
    final state = CatalogueState(
      catalogue: catalogueOf(
        highlights: [
          hRow(
            title: 'Some Game - Opening',
            link: 'https://youtu.be/fffffffffff',
            stream: '2025/12/31',
            upload: '2026-01-05',
          ),
        ],
        songs: [
          start('2025/12/31 21:30'),
          sRow(date: '2025/12/31 21:45', title: 'Some Game - Opening'),
          start('2026/11/12 21:34'),
          sRow(date: '2026/11/12 21:52', title: 'Some Game - Opening'),
        ],
      ),
      fetchedAt: testNow,
    );
    await pumpApp(tester, state: state, wallTime: utcPlus(1));
    await tester.tap(find.byTooltip('Details'));
    await tester.pumpAndSettle();
    expect(find.text('first in 2025'), findsOneWidget);
    await tester.tap(find.text('Played 2 times live'));
    await tester.pumpAndSettle();
    expect(find.descendant(of: find.byType(SongSheet), matching: find.text('2025')), findsOneWidget);
    expect(find.text('first played'), findsOneWidget);
  });

  test('outside the tests, the zone is the device\'s', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final instant = DateTime.utc(2026, 11, 13, 6, 39);
    final wall = container.read(wallTimeProvider)(instant);
    final local = instant.toLocal();
    // a local DateTime, whatever the zone of the machine (in UTC too)
    expect(wall.isUtc, isFalse);
    expect(
      (wall.year, wall.month, wall.day, wall.hour, wall.minute),
      (local.year, local.month, local.day, local.hour, local.minute),
    );
    expect(wall.millisecondsSinceEpoch, instant.millisecondsSinceEpoch);
  });
}
