// The highlights new since the last visit: what makes a visit and ends it, what survives the end of the process,
// and the marks (the row mark, the "New" chip, the count on the navigation).
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/model.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/new_highlights_state.dart';
import 'package:ong_music/src/ui/highlights_page.dart';
import 'package:ong_music/src/ui/layout.dart';
import 'package:ong_music/src/ui/new_highlights.dart';
import 'package:ong_music/src/ui/rows.dart';
import 'package:shared_preferences/shared_preferences.dart';
// the storage under the plugin, to write to it as another tab of the browser would
// ignore: depend_on_referenced_packages
import 'package:shared_preferences_platform_interface/shared_preferences_platform_interface.dart';

import 'fixtures.dart';
import 'ui_harness.dart';

const _known = KnownHighlightsNotifier.key;
const _visit = KnownHighlightsNotifier.visitKey;
const _seen = KnownHighlightsNotifier.seenKey;

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

  group('what a visit can make known', () {
    testWidgets('a refresh landing out of sight is new in the next visit', (tester) async {
      var now = testNow;
      // the kept copy on screen, a refresh under way, and off to YouTube
      final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([], now));
      await _hide(tester);
      // the download ends in the background
      app.notifier.emit(_state([_nocturne], now));
      await tester.pumpAndSettle();
      expect(app.prefs.getStringList(_visit), isNot(contains('ccccccccccc')));
      now = now.add(const Duration(hours: 3));
      await _show(tester);
      expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
      expect(app.prefs.getStringList(_known), isNot(contains('ccccccccccc')));
    });

    testWidgets('a refresh landing on another tab is new in the next visit, unless the list showed it', (tester) async {
      var now = testNow;
      final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([], now));
      await goToTab(tester, 'Ong Log');
      app.notifier.emit(_state([_nocturne], now));
      await tester.pumpAndSettle();
      await _hide(tester);
      now = now.add(const Duration(hours: 3));
      await _show(tester);
      await goToTab(tester, 'Highlights');
      expect(_marked(tester), ['Nocturne Op. 9 No. 2']);

      // this time the list shows it before the visit ends
      await goToTab(tester, 'Ong Log');
      app.notifier.emit(_state([_nocturne, _merryGoRound], now));
      await tester.pumpAndSettle();
      await goToTab(tester, 'Highlights');
      expect(_marked(tester), ['Merry-Go-Round of Life', 'Nocturne Op. 9 No. 2']);
      await _hide(tester);
      now = now.add(const Duration(hours: 3));
      await _show(tester);
      expect(_marked(tester), isEmpty);
    });

    for (final (name, away) in [('out of sight', true), ('on another tab', false)]) {
      testWidgets('the first run makes known what its refresh brings $name, the list never shown again', (
        tester,
      ) async {
        var now = testNow;
        // the kept copy, then the network's a moment later
        final app = await pumpApp(tester, clock: () => now, state: _state([], now));
        if (away) {
          await _hide(tester);
        } else {
          await goToTab(tester, 'Ong Log');
        }
        app.notifier.emit(_state([_nocturne], now));
        await tester.pumpAndSettle();
        // nothing new on a first run
        expect(_badge(tester), isNull);
        if (!away) await _hide(tester);
        now = now.add(const Duration(hours: 3));
        await _restart(tester, app, clock: () => now, state: _state([_nocturne, _merryGoRound], now));
        expect(_marked(tester), ['Merry-Go-Round of Life']);
      });
    }
  });

  group('the time in sight', () {
    testWidgets('a crash after two hours on screen keeps the marks of a restart ten minutes later', (tester) async {
      var now = testNow;
      final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([_nocturne], now));
      final keys = app.prefs.getStringList(_visit);
      now = now.add(const Duration(hours: 2));
      await tester.pump(const Duration(hours: 2));
      // the time alone was written again, not the keys
      expect(app.prefs.getStringList(_visit), keys);
      expect(app.prefs.getInt(_seen), now.millisecondsSinceEpoch);
      // no event: the process ends on screen (or a window closed without "hidden")
      final stored = _stored(app.prefs);
      await tester.pumpWidget(const SizedBox());
      now = now.add(const Duration(minutes: 10));
      await pumpApp(tester, prefs: stored, clock: () => now, state: _state([_nocturne], now));
      expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
    });

    testWidgets('a change of tab stores the time in sight too', (tester) async {
      var now = testNow;
      final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([_nocturne], now));
      // before the first beat
      now = now.add(highlightVisitBeat - const Duration(minutes: 1));
      await goToTab(tester, 'Ong Log');
      final stored = _stored(app.prefs);
      await tester.pumpWidget(const SizedBox());
      now = now.add(highlightVisitGap - const Duration(minutes: 1));
      await pumpApp(tester, prefs: stored, clock: () => now, state: _state([_nocturne], now));
      expect(_marked(tester), ['Nocturne Op. 9 No. 2']);
    });

    testWidgets('the later of the two stored times counts, whichever was written last', (tester) async {
      final now = testNow;
      Future<List<String>> marksWith(Map<String, Object> prefs) async {
        await pumpApp(tester, prefs: prefs, clock: () => now, state: _state([_nocturne], now));
        final marked = _marked(tester);
        await tester.pumpWidget(const SizedBox());
        return marked;
      }

      int ago(int minutes) => now.subtract(Duration(minutes: minutes)).millisecondsSinceEpoch;
      // the time of the visit recent, its own time older (written by a visit before, not removed)
      expect(
        await marksWith({
          _known: _testKeys,
          _visit: ['${ago(30)}', 'ccccccccccc'],
          _seen: ago(300),
        }),
        ['Nocturne Op. 9 No. 2'],
      );
      // the other way round
      expect(
        await marksWith({
          _known: _testKeys,
          _visit: ['${ago(300)}', 'ccccccccccc'],
          _seen: ago(30),
        }),
        ['Nocturne Op. 9 No. 2'],
      );
      // both old
      expect(
        await marksWith({
          _known: _testKeys,
          _visit: ['${ago(300)}', 'ccccccccccc'],
          _seen: ago(200),
        }),
        isEmpty,
      );
    });
  });

  testWidgets('the end of a visit stores the keys another tab made known meanwhile, and its own', (tester) async {
    var now = testNow;
    final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([_nocturne], now));
    // another tab of the browser ended its visit, with a highlight this one never had
    await SharedPreferencesStorePlatform.instance.setValue('StringList', 'flutter.$_known', [
      ..._testKeys,
      'ddddddddddd',
    ]);
    await _hide(tester);
    now = now.add(const Duration(hours: 2));
    await _show(tester);
    expect(app.prefs.getStringList(_known), unorderedEquals([..._testKeys, 'ccccccccccc', 'ddddddddddd']));
  });

  testWidgets('a visit ended in sight, the next one starts and stays stored, the storage slow as it may be', (
    tester,
  ) async {
    var now = testNow;
    final app = await pumpApp(tester, prefs: {_known: _testKeys}, clock: () => now, state: _state([_nocturne], now));
    // from now on, each write ends a while after it was asked for
    SharedPreferencesStorePlatform.instance = _LateStore({
      for (final k in app.prefs.getKeys()) 'flutter.$k': app.prefs.get(k)!,
    });
    await _hide(tester);
    now = now.add(const Duration(hours: 2));
    // the end of the old visit is written before the start of the new one, not over it
    await _show(tester);
    await tester.pump(const Duration(seconds: 1));
    final stored = await SharedPreferencesStorePlatform.instance.getAll();
    expect(stored['flutter.$_visit'], ['${now.millisecondsSinceEpoch}']);
    expect(stored['flutter.$_seen'], now.millisecondsSinceEpoch);
    expect(stored['flutter.$_known'], unorderedEquals([..._testKeys, 'ccccccccccc']));
  });

  testWidgets('web: a page opened behind another one starts its visit when it is first shown', (tester) async {
    final visible = ValueNotifier(false);
    final app = await pumpApp(
      tester,
      prefs: {_known: _testKeys},
      state: _state([_nocturne], testNow),
      pageVisibility: visible,
    );
    // the engine says "resumed", the page is hidden
    expect(app.prefs.getStringList(_visit), isNull);
    // shown: no change of the lifecycle
    visible.value = true;
    await tester.pumpAndSettle();
    expect(app.prefs.getStringList(_visit), ['${testNow.millisecondsSinceEpoch}', 'ccccccccccc']);
  });

  testWidgets('with a mouse, the New mark lets the thumbnail open the video', (tester) async {
    final app = await pumpApp(
      tester,
      size: const Size(1280, 800),
      pointer: PointerKind.mouse,
      prefs: {_known: _testKeys},
      state: _state([_nocturne], testNow),
    );
    final mark = find.byType(NewMark);
    final mouse = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(tester.getCenter(mark)));
    await tester.pumpAndSettle();
    // the veil of the thumbnail
    expect(find.byIcon(Icons.open_in_new), findsOneWidget);
    await tester.tap(mark, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
    expect(app.effects.opened.single.toString(), contains('ccccccccccc'));
  });

  group('the count of the top bar never goes over the next label', () {
    for (final width in [320.0, 360.0, 400.0, 1280.0]) {
      for (final scale in [1.0, 2.0]) {
        testWidgets('$width px wide, text scale $scale', (tester) async {
          final many = [
            for (var i = 0; i < 120; i++)
              hRow(
                order: '${10 + i}',
                title: 'Artist $i - Track $i',
                genre: 'POPULAR MUSIC',
                link: 'https://youtu.be/q${i.toString().padLeft(10, '0')}',
                upload: '2024-04-01',
              ),
          ];
          for (final more in [many, many.sublist(0, 1)]) {
            await pumpApp(
              tester,
              size: Size(width, 800),
              desktop: true,
              textScale: scale,
              prefs: {_known: _testKeys},
              state: _state(more, testNow),
            );
            final count = more.length > 99 ? '99+' : '${more.length}';
            final badge = tester.getRect(
              find
                  .ancestor(
                    of: find.descendant(of: navigation(), matching: find.text(count)),
                    matching: find.byType(Container),
                  )
                  .first,
            );
            final next = tester.getRect(find.descendant(of: navigation(), matching: find.text('Ong Log')));
            final bar = tester.getRect(navigation());
            expect(badge.right, lessThanOrEqualTo(next.left - 4), reason: '$count at $badge, Ong Log at $next');
            expect(badge.top, greaterThanOrEqualTo(bar.top), reason: '$count at $badge');
            await tester.pumpWidget(const SizedBox());
          }
        });
      }
    }
  });
}

/// The storage under the plugin, each write of which ends 10 ms after it was asked for.
class _LateStore extends InMemorySharedPreferencesStore {
  _LateStore(super.data) : super.withData();

  static const _delay = Duration(milliseconds: 10);

  @override
  Future<bool> setValue(String valueType, String key, Object value) async {
    await Future<void>.delayed(_delay);
    return super.setValue(valueType, key, value);
  }

  @override
  Future<bool> remove(String key) async {
    await Future<void>.delayed(_delay);
    return super.remove(key);
  }
}
