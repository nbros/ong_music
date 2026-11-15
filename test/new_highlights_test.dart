// The highlights new since the last visit: what makes a visit and ends it, what survives the end of the process,
// and the marks (the row mark, the "New" chip, the count on the navigation).
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/new_highlights_state.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/new_highlights.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

const _known = KnownHighlightsNotifier.key;
const _visit = KnownHighlightsNotifier.visitKey;

/// The keys of the highlights of [testCatalogue].
final List<String> _testKeys = [for (final h in testCatalogue().highlights) h.key];

/// Two highlights after those of [testCatalogue], the newest last.
final _nocturne = hRow(
  order: '4',
  title: 'Chopin - Nocturne Op. 9 No. 2',
  genre: 'CLASSICAL',
  link: 'https://youtu.be/ccccccccccc',
  upload: '2024-03-08',
);
final _merryGoRound = hRow(
  order: '5',
  title: 'Joe Hisaishi - Merry-Go-Round of Life',
  genre: 'ANIME',
  link: 'https://youtu.be/ddddddddddd',
  upload: '2024-03-09',
);

/// [testCatalogue] with [more] highlights, both sheets downloaded an hour before [at].
CatalogueState _state(List<List<String>> more, DateTime at) =>
    loadedState(testCatalogue(moreHighlights: more), at.subtract(const Duration(hours: 1)));

/// What the app stored, to start it again with.
Map<String, Object> _stored(SharedPreferences prefs) => {for (final k in prefs.getKeys()) k: prefs.get(k)!};

/// The app goes out of sight (another app, the home screen; a hidden page in a browser).
Future<void> _hide(WidgetTester tester) async {
  for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
  await tester.pumpAndSettle();
}

/// The app comes back in sight.
Future<void> _show(WidgetTester tester) async {
  _resume(tester.binding);
  await tester.pumpAndSettle();
}

/// The lifecycle back to resumed, through the states between.
void _resume(WidgetsBinding binding) {
  const order = [AppLifecycleState.paused, AppLifecycleState.hidden, AppLifecycleState.inactive];
  final from = order.indexOf(binding.lifecycleState ?? AppLifecycleState.resumed);
  if (from < 0) return;
  for (final state in [...order.skip(from + 1), AppLifecycleState.resumed]) {
    binding.handleAppLifecycleStateChanged(state);
  }
}

/// The process ends: the app starts again from what it stored.
Future<TestApp> _restart(
  WidgetTester tester,
  TestApp app, {
  required DateTime Function() clock,
  required CatalogueState state,
  FakeBrowser? browser,
}) async {
  // what was stored while out of sight: the process ends there
  final prefs = _stored(app.prefs);
  // frames again, for the test to take the app down
  _resume(tester.binding);
  await tester.pumpWidget(const SizedBox());
  return pumpApp(tester, prefs: prefs, clock: clock, state: state, browser: browser);
}

/// The tracks of the rows with the `New` mark, top to bottom.
List<String> _marked(WidgetTester tester) => [
  for (final row in tester.widgetList<HighlightRow>(find.byType(HighlightRow)))
    if (row.isNew) row.highlight.track,
];

/// The count on the Highlights destination of the navigation, null when there is none.
String? _badge(WidgetTester tester) {
  final badges = find.descendant(
    of: navigation(),
    matching: find.byWidgetPredicate((w) => w is Badge && w.isLabelVisible),
  );
  if (badges.evaluate().isEmpty) return null;
  final texts = find.descendant(of: badges, matching: find.byType(Text));
  return tester.widget<Text>(texts.last).data;
}

void main() {
  tearDown(() => _resume(TestWidgetsFlutterBinding.instance));

  testWidgets('the first run marks nothing, not even what a refresh brings; its highlights become the known ones', (
    tester,
  ) async {
    var now = testNow;
    final app = await pumpApp(tester, clock: () => now, state: _state([], now));
    expect(_marked(tester), isEmpty);
    // a refresh during the first visit
    app.notifier.emit(_state([_nocturne], now));
    await tester.pumpAndSettle();
    expect(_marked(tester), isEmpty);
    expect(_badge(tester), isNull);
    expect(chip(newLabel), findsNothing);
    expect(app.prefs.getStringList(_known), isNull, reason: 'known only once the first visit ends');

    await _hide(tester);
    now = now.add(const Duration(hours: 2));
    final next = await _restart(tester, app, clock: () => now, state: _state([_nocturne, _merryGoRound], now));
    expect(next.prefs.getStringList(_known), unorderedEquals([..._testKeys, 'ccccccccccc']));
    // only what came since the first visit
    expect(_marked(tester), ['Merry-Go-Round of Life']);
  });

  testWidgets('a highlight not known at the end of the last visit is marked, in the row, the chip and the navigation', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, prefs: {_known: _testKeys}, state: _state([_nocturne, _merryGoRound], testNow));
    expect(_marked(tester), ['Merry-Go-Round of Life', 'Nocturne Op. 9 No. 2']);
    expect(chipTextOf(tester, newLabel), 'New  2');
    expect(_badge(tester), '2');
    // said with the row, and with the destination
    final row = find.ancestor(of: find.text('Nocturne Op. 9 No. 2'), matching: find.byType(HighlightRow));
    expect(tester.getSemantics(row).getSemanticsData().label, contains(newLabel));
    expect(find.semantics.byLabel(RegExp('2 new highlights')), findsOneWidget);
    // nothing in the Ong Log
    await goToTab(tester, 'Ong Log');
    expect(find.text(newLabel).hitTestable(), findsNothing);
    handle.dispose();
  });

  testWidgets('the count is said in the singular for one', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpApp(tester, prefs: {_known: _testKeys}, state: _state([_nocturne], testNow));
    expect(find.semantics.byLabel(RegExp(r'\b1 new highlight\b(?!s)')), findsOneWidget);
    expect(newHighlightsLabel(1), '1 new highlight');
    expect(newHighlightsLabel(12), '12 new highlights');
    handle.dispose();
  });

  testWidgets('a trip out of the app shorter than the gap keeps the marks, even when the process ends meanwhile', (
    tester,
  ) async {
    var now = testNow;
    final state = _state([_nocturne], now);
    final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: state);
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);

    // to YouTube and back, the process alive
    await _hide(tester);
    now = now.add(highlightVisitGap - const Duration(minutes: 1));
    await _show(tester);
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);

    // two hours on screen, then again, the process ended by the system: the app starts cold
    now = now.add(const Duration(hours: 2));
    await _hide(tester);
    now = now.add(highlightVisitGap - const Duration(minutes: 1));
    final next = await _restart(tester, app, clock: () => now, state: state);
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
    expect(_badge(tester), '1');
    expect(next.prefs.getStringList(_known), unorderedEquals(_testKeys), reason: 'the visit goes on');
  });

  testWidgets('out of sight for the gap or more ends the visit: the marks go, what comes after is new at once', (
    tester,
  ) async {
    var now = testNow;
    final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([_nocturne], now));
    await tapVisible(tester, chip(newLabel));
    expect(find.byType(HighlightRow), findsOneWidget);

    await _hide(tester);
    now = now.add(highlightVisitGap);
    await _show(tester);
    expect(_marked(tester), isEmpty);
    expect(_badge(tester), isNull);
    // the chip went, and its filter with it
    expect(chip(newLabel), findsNothing);
    expect(find.byType(HighlightRow), findsNWidgets(4));
    expect(app.prefs.getStringList(_known), unorderedEquals([..._testKeys, 'ccccccccccc']));

    // a refresh of the new visit
    app.notifier.emit(_state([_nocturne, _merryGoRound], now));
    await tester.pumpAndSettle();
    expect(_marked(tester), ['Merry-Go-Round of Life']);
    // the chip is back, its filter is not
    expect(chip(newLabel), findsOneWidget);
    expect(find.byType(HighlightRow), findsNWidgets(5));
  });

  testWidgets('the next day, after the process ended, only what came since the last visit is marked', (tester) async {
    var now = testNow;
    final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([_nocturne], now));
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
    await _hide(tester);

    now = now.add(const Duration(days: 1));
    // the kept sheet first, as the app starts
    final next = await _restart(tester, app, clock: () => now, state: _state([_nocturne], now));
    expect(_marked(tester), isEmpty);
    next.notifier.emit(_state([_nocturne, _merryGoRound], now));
    await tester.pumpAndSettle();
    expect(_marked(tester), ['Merry-Go-Round of Life']);
  });

  testWidgets('a visit that never showed the list clears nothing: opened on the Ong Log', (tester) async {
    var now = testNow;
    final app = await pumpApp(
      tester,
      prefs: {_known: _testKeys},
      clock: () => now,
      state: _state([_nocturne], now),
      browser: FakeBrowser('/log'),
    );
    expect(app.prefs.getStringList(_visit), isNull, reason: 'no visit without the list');
    await _hide(tester);
    now = now.add(const Duration(hours: 3));
    await _show(tester);
    await tester.pumpWidget(const SizedBox());

    final next = await pumpApp(tester, prefs: _stored(app.prefs), clock: () => now, state: _state([_nocturne], now));
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
    expect(next.prefs.getStringList(_known), unorderedEquals(_testKeys));
  });

  testWidgets('a visit that never showed the list clears nothing: closed before the highlights came', (tester) async {
    var now = testNow;
    final app = await pumpApp(
      tester,
      prefs: {_known: _testKeys},
      clock: () => now,
      state: const CatalogueState(isRefreshing: true),
      // the spinner turns
      settle: false,
    );
    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    // the download ends in the background
    app.notifier.emit(_state([_nocturne], now));
    await tester.pumpAndSettle();
    expect(app.prefs.getStringList(_visit), isNull);
    now = now.add(const Duration(hours: 3));
    await _restart(tester, app, clock: () => now, state: _state([_nocturne], now));
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
  });

  testWidgets('the list shown on another tab of the visit still makes it a visit', (tester) async {
    var now = testNow;
    final app = await pumpApp(
      tester,
      prefs: {_known: _testKeys},
      clock: () => now,
      state: _state([_nocturne], now),
      browser: FakeBrowser('/log'),
    );
    await goToTab(tester, 'Highlights');
    await goToTab(tester, 'About');
    await _hide(tester);
    now = now.add(const Duration(hours: 3));
    await _restart(tester, app, clock: () => now, state: _state([_nocturne], now));
    expect(_marked(tester), isEmpty);
  });

  testWidgets('a highlight once known is not new again when a download briefly lacked it', (tester) async {
    var now = testNow;
    // the last visit knew the nocturne; this one's first download lacks it
    var app = await pumpApp(
      tester,
      prefs: {
        _known: [..._testKeys, 'ccccccccccc'],
      },
      clock: () => now,
      state: _state([], now),
    );
    await _hide(tester);
    now = now.add(const Duration(hours: 2));
    app = await _restart(tester, app, clock: () => now, state: _state([], now));
    expect(app.prefs.getStringList(_known), contains('ccccccccccc'));
    // it is back
    app.notifier.emit(_state([_nocturne], now));
    await tester.pumpAndSettle();
    expect(_marked(tester), isEmpty);
  });

  testWidgets('what a visit stored survives the process ending at any moment', (tester) async {
    final now = testNow;
    // ended between the two writes of the end of a visit: the known keys already have its keys
    await pumpApp(
      tester,
      prefs: {
        _known: [..._testKeys, 'ccccccccccc'],
        _visit: ['${now.subtract(const Duration(hours: 5)).millisecondsSinceEpoch}', 'ccccccccccc'],
      },
      clock: () => now,
      state: _state([_nocturne, _merryGoRound], now),
    );
    expect(_marked(tester), ['Merry-Go-Round of Life']);
    await tester.pumpWidget(const SizedBox());

    // something else than a visit under its key: no visit
    await pumpApp(
      tester,
      prefs: {
        _known: _testKeys,
        _visit: ['not a time', 'ccccccccccc'],
      },
      clock: () => now,
      state: _state([_nocturne], now),
    );
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
    await tester.pumpWidget(const SizedBox());

    // something else than a list of keys: as on a first run
    await pumpApp(tester, prefs: {_known: 'oops'}, clock: () => now, state: _state([_nocturne], now));
    expect(_marked(tester), isEmpty);
  });

  testWidgets('the New chip combines with the others and the search, and All clears it', (tester) async {
    await pumpApp(tester, prefs: {_known: _testKeys}, state: _state([_nocturne, _merryGoRound], testNow));
    await tapVisible(tester, chip(newLabel));
    expect(find.byType(HighlightRow), findsNWidgets(2));
    // the genre chips count the new ones of their genre
    expect(chipTextOf(tester, 'Classical'), 'Classical  1');
    await tapVisible(tester, chip('Classical'));
    expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
    expect(chipTextOf(tester, newLabel), 'New  1');
    await tapVisible(tester, chip('Classical'));
    await tester.enterText(searchField(), 'merry');
    await tester.pumpAndSettle();
    expect(_marked(tester), ['Merry-Go-Round of Life']);
    expect(find.byType(HighlightRow), findsOneWidget);
    await tester.enterText(searchField(), '');
    await tapVisible(tester, chip('All'));
    expect(find.byType(HighlightRow), findsNWidgets(5));
    expect(tester.getSemantics(chip(newLabel)), isSemantics(isSelected: false, isButton: true));
  });

  group('the marks move nothing', () {
    /// The places of the texts of the row of [track], from its top left corner, and its size.
    (Size, List<Rect>) layoutOf(WidgetTester tester, String track) {
      final row = find.ancestor(of: find.text(track), matching: find.byType(HighlightRow));
      final origin = tester.getTopLeft(row);
      return (
        tester.getSize(row),
        [
          for (final e in find.descendant(of: row, matching: find.byType(RichText)).evaluate())
            if ((e.widget as RichText).text.toPlainText() != newLabel)
              tester.getRect(find.byWidget(e.widget)).shift(-origin),
        ],
      );
    }

    /// The place of each label of the navigation.
    List<Rect> labels(WidgetTester tester) => [
      for (final label in ['Highlights', 'Ong Log', 'About'])
        tester.getRect(find.descendant(of: navigation(), matching: find.text(label))),
    ];

    for (final (name, size, desktop) in [
      ('compact', const Size(412, 892), false),
      ('medium', const Size(700, 1000), false),
      ('expanded', const Size(1280, 800), false),
      ('desktop look', const Size(1280, 800), true),
    ]) {
      testWidgets('$name: the row, its texts, the navigation', (tester) async {
        await pumpApp(tester, size: size, desktop: desktop, state: _state([_nocturne], testNow));
        final plain = layoutOf(tester, 'Nocturne Op. 9 No. 2');
        final plainLabels = labels(tester);
        await tester.pumpWidget(const SizedBox());

        await pumpApp(
          tester,
          size: size,
          desktop: desktop,
          prefs: {_known: _testKeys},
          state: _state([_nocturne], testNow),
        );
        expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
        expect(_badge(tester), '1');
        final marked = layoutOf(tester, 'Nocturne Op. 9 No. 2');
        expect(marked.$1, plain.$1);
        expect(marked.$2, plain.$2);
        expect(labels(tester), plainLabels);
        // the mark over the thumbnail, inside it
        final mark = tester.getRect(find.byType(NewMark));
        final thumbnail = tester.getRect(
          find
              .descendant(
                of: find.ancestor(of: find.text('Nocturne Op. 9 No. 2'), matching: find.byType(HighlightRow)),
                matching: find.byType(ClipRRect),
              )
              .first,
        );
        expect(thumbnail.contains(mark.topLeft) && thumbnail.contains(mark.bottomRight), isTrue, reason: '$mark');
      });
    }
  });

  test('the search counts the new highlights, and keeps only them when asked', () {
    final catalogue = testCatalogue(moreHighlights: [_nocturne, _merryGoRound]);
    final fresh = {'ccccccccccc', 'ddddddddddd'};
    final all = catalogue.searchHighlights(newKeys: fresh, onlyNew: false);
    expect((all.length, all.counts.newKeys), (5, 2));
    final only = catalogue.searchHighlights(newKeys: fresh);
    expect(
      [for (final id in only.ids) catalogue.highlights[id].track],
      ['Merry-Go-Round of Life', 'Nocturne Op. 9 No. 2'],
    );
    expect(only.counts.genre(Genre.classical), 1);
    // with the favourites: each one counts what the other keeps
    final both = catalogue.searchHighlights(keys: {'ccccccccccc', 'aaaaaaaaaaa'}, newKeys: fresh, onlyKeys: false);
    expect((both.length, both.counts.keys, both.counts.newKeys), (2, 1, 2));
  });

  testWidgets('the page tells the visit when the list is on screen', (tester) async {
    await pumpApp(tester, prefs: {_known: _testKeys}, state: _state([_nocturne], testNow));
    expect(find.byType(HighlightsPage), findsOneWidget);
    // the visit is stored at once: the process may end any moment
    final stored = (await SharedPreferences.getInstance()).getStringList(_visit);
    expect(stored, ['${testNow.millisecondsSinceEpoch}', 'ccccccccccc']);
  });
}
