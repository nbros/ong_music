import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ong_music/src/data/schedule.dart';
import 'package:ong_music/src/ui/about_page.dart';
import 'package:ong_music/src/ui/theme.dart';

import 'ui_harness.dart';

/// Thursday 12 November 2026, noon on the calendar of the machine: the tests
/// give their times in the local zone, so they do not depend on it.
final localNoon = DateTime(2026, 11, 12, 12).toUtc();

String _ics(DateTime t) {
  final u = t.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year}${two(u.month)}${two(u.day)}T${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
}

/// A schedule of one-off streams, given in local time.
StreamSchedule scheduleOf(List<(DateTime, DateTime)> streams) => parseSchedule(
  [
    'BEGIN:VCALENDAR',
    for (final (i, (start, end)) in streams.indexed) ...[
      'BEGIN:VEVENT',
      'UID:s$i',
      'DTSTART:${_ics(start)}',
      'DTEND:${_ics(end)}',
      'SUMMARY:Symphonic Loops',
      'END:VEVENT',
    ],
    'END:VCALENDAR',
  ].join('\r\n'),
);

/// 11:00 – 15:00 today, local time.
final inProgress = (DateTime(2026, 11, 12, 11), DateTime(2026, 11, 12, 15));

/// Pumps the app at [localNoon] with [twitch] and opens the About tab.
Future<TestApp> pumpAbout(
  WidgetTester tester,
  FakeTwitchApi twitch, {
  bool h24 = false,
  double textScale = 1,
  Map<String, Object> prefs = const {},
}) async {
  // a new app each time (a ProviderScope rebuilt in place would keep its state)
  await tester.pumpWidget(const SizedBox());
  final app = await pumpApp(
    tester,
    twitch: twitch,
    clock: () => localNoon,
    alwaysUse24HourFormat: h24,
    textScale: textScale,
    prefs: prefs,
  );
  await goToTab(tester, 'About');
  return app;
}

/// The rich text reading [text] (the live dot is a placeholder, not text).
Finder line(String text) =>
    find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText(includePlaceholders: false) == text);

Finder liveDot() => find.byKey(const ValueKey('live-dot'));

void main() {
  setUpAll(loadTimeZones);

  testWidgets('nothing is asked before the About tab is shown', (tester) async {
    final app = await pumpApp(tester, clock: () => localNoon);
    await goToTab(tester, 'Ong Log');
    expect((app.twitch.scheduleCalls, app.twitch.liveCalls), (0, 0));
    await goToTab(tester, 'About');
    expect((app.twitch.scheduleCalls, app.twitch.liveCalls), (1, 1));
    // back and forth within 2 minutes: throttled
    await goToTab(tester, 'Highlights');
    await goToTab(tester, 'About');
    expect((app.twitch.scheduleCalls, app.twitch.liveCalls), (1, 1));
  });

  testWidgets('the line keeps its place: nothing below moves when the answer arrives', (tester) async {
    final twitch = FakeTwitchApi(schedule: scheduleOf([inProgress]), live: true)..gate = Completer<void>();
    await pumpAbout(tester, twitch);
    expect(find.textContaining('Live now', findRichText: true), findsNothing);
    final before = tester.getRect(find.text('YouTube'));
    twitch.gate!.complete();
    await tester.pumpAndSettle();
    expect(line('Live now · since 11:00 AM'), findsOneWidget);
    expect(tester.getRect(find.text('YouTube')), before);
  });

  testWidgets('in the background nothing is asked; coming back checks at once', (tester) async {
    var now = localNoon;
    final twitch = FakeTwitchApi(schedule: scheduleOf([inProgress]), live: true);
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, twitch: twitch, clock: () => now);
    await goToTab(tester, 'About');
    expect((twitch.scheduleCalls, twitch.liveCalls), (1, 1));
    expect(line('Live now · since 11:00 AM'), findsOneWidget);

    for (final state in [AppLifecycleState.inactive, AppLifecycleState.hidden, AppLifecycleState.paused]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    now = now.add(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    expect((twitch.scheduleCalls, twitch.liveCalls), (1, 1), reason: 'no polling while paused');

    twitch.live = false;
    for (final state in [AppLifecycleState.hidden, AppLifecycleState.inactive, AppLifecycleState.resumed]) {
      tester.binding.handleAppLifecycleStateChanged(state);
    }
    await tester.pump();
    await tester.pump();
    expect((twitch.scheduleCalls, twitch.liveCalls), (1, 2), reason: 'the schedule is recent, the live check is not');
    // the half-hour-old "live" is not shown again, and the new answer says offline
    expect(find.textContaining('Live now', findRichText: true), findsNothing);
    expect(line('Scheduled now: 11:00 AM – 3:00 PM'), findsOneWidget);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });

  testWidgets('nothing known: the button alone', (tester) async {
    await pumpAbout(tester, FakeTwitchApi(schedule: null));
    expect(find.text('Watch on Twitch'), findsOneWidget);
    expect(find.textContaining('Next stream'), findsNothing);
    expect(find.textContaining('Live now'), findsNothing);
    expect(find.textContaining('Scheduled now'), findsNothing);
    expect(liveDot(), findsNothing);
  });

  for (final h24 in [false, true]) {
    String t(String h12, String h24text) => h24 ? h24text : h12;
    final mode = h24 ? '24-hour' : '12-hour';

    testWidgets('live, during a scheduled stream ($mode)', (tester) async {
      await pumpAbout(tester, FakeTwitchApi(schedule: scheduleOf([inProgress]), live: true), h24: h24);
      expect(find.text('Watch live on Twitch'), findsOneWidget);
      expect(find.text('Watch on Twitch'), findsNothing);
      expect(line('Live now · since ${t('11:00 AM', '11:00')}'), findsOneWidget);
      expect(liveDot(), findsOneWidget);
    });

    testWidgets('live without schedule ($mode)', (tester) async {
      await pumpAbout(tester, FakeTwitchApi(live: true), h24: h24);
      expect(find.text('Watch live on Twitch'), findsOneWidget);
      expect(line('Live now'), findsOneWidget);
      expect(liveDot(), findsOneWidget);
    });

    testWidgets('scheduled now, not known to be live ($mode)', (tester) async {
      await pumpAbout(tester, FakeTwitchApi(schedule: scheduleOf([inProgress])), h24: h24);
      expect(find.text('Watch on Twitch'), findsOneWidget);
      expect(
        find.text('Scheduled now: ${t('11:00 AM – 3:00 PM', '11:00 – 15:00')}', findRichText: true),
        findsOneWidget,
      );
      expect(find.textContaining('Live now'), findsNothing);
      expect(liveDot(), findsNothing);
    });

    testWidgets('next stream: today, tomorrow, a date, another year ($mode)', (tester) async {
      final cases = {
        (DateTime(2026, 11, 12, 20), DateTime(2026, 11, 13, 3)): 'today at ${t('8:00 PM', '20:00')}',
        (DateTime(2026, 11, 13, 9, 30), DateTime(2026, 11, 13, 12)): 'tomorrow at ${t('9:30 AM', '09:30')}',
        (DateTime(2026, 11, 20, 13, 30), DateTime(2026, 11, 20, 21)): 'Fri 20 Nov at ${t('1:30 PM', '13:30')}',
        (DateTime(2027, 1, 8, 0, 5), DateTime(2027, 1, 8, 2)): 'Fri 8 Jan 2027 at ${t('12:05 AM', '00:05')}',
      };
      for (final MapEntry(key: stream, value: text) in cases.entries) {
        // a past stream, to be ignored
        final past = (DateTime(2026, 11, 11, 20), DateTime(2026, 11, 11, 22));
        await pumpAbout(tester, FakeTwitchApi(schedule: scheduleOf([past, stream])), h24: h24);
        expect(find.text('Next stream: $text', findRichText: true), findsOneWidget, reason: text);
        expect(find.text('Watch on Twitch'), findsOneWidget);
        expect(liveDot(), findsNothing);
      }
    });
  }

  testWidgets('screen reader labels; the dot is not read', (tester) async {
    final semantics = tester.ensureSemantics();
    await pumpAbout(tester, FakeTwitchApi(schedule: scheduleOf([inProgress]), live: true), h24: true);
    expect(find.bySemanticsLabel('Live now, since 11:00'), findsOneWidget);
    await pumpAbout(tester, FakeTwitchApi(schedule: scheduleOf([inProgress])), h24: true);
    expect(find.bySemanticsLabel('Scheduled now, from 11:00 to 15:00'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('tapping the status line does nothing; the button opens Twitch', (tester) async {
    final app = await pumpAbout(tester, FakeTwitchApi(schedule: scheduleOf([inProgress]), live: true));
    await tester.tap(find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('Live now')));
    await tester.pumpAndSettle();
    expect(app.effects.opened, isEmpty);
    await tester.tap(find.text('Watch live on Twitch'));
    await tester.pumpAndSettle();
    expect(app.effects.opened.single.toString(), twitchUrl);
  });

  testWidgets('the text follows the time: a stream starting, then ending', (tester) async {
    final soon = (DateTime(2026, 11, 12, 12, 0, 30), DateTime(2026, 11, 12, 14));
    var now = localNoon;
    await pumpApp(
      tester,
      twitch: FakeTwitchApi(schedule: scheduleOf([soon])),
      clock: () => now,
      alwaysUse24HourFormat: true,
    );
    await goToTab(tester, 'About');
    expect(find.text('Next stream: today at 12:00', findRichText: true), findsOneWidget);
    now = now.add(const Duration(seconds: 30));
    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Scheduled now: 12:00 – 14:00', findRichText: true), findsOneWidget);
    now = DateTime(2026, 11, 12, 14).toUtc();
    await tester.pump(DateTime(2026, 11, 12, 14).difference(DateTime(2026, 11, 12, 12, 0, 30)));
    expect(find.textContaining('Scheduled now', findRichText: true), findsNothing);
    expect(find.textContaining('Next stream', findRichText: true), findsNothing);
  });

  for (final dark in [false, true]) {
    testWidgets('text scale 2 on a 412-dp phone: wraps, no overflow (${dark ? 'dark' : 'light'})', (tester) async {
      await pumpAbout(
        tester,
        FakeTwitchApi(schedule: scheduleOf([inProgress]), live: true),
        textScale: 2,
        prefs: {'themeMode': dark ? 'dark' : 'light'},
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Watch live on Twitch'), findsOneWidget);
      final line = find.byWidgetPredicate((w) => w is RichText && w.text.toPlainText().contains('Live now'));
      expect(tester.getSize(line).width, lessThanOrEqualTo(412 - 48));
      await pumpAbout(tester, FakeTwitchApi(schedule: scheduleOf([inProgress])), textScale: 2, h24: false);
      expect(tester.takeException(), isNull);
      await pumpAbout(
        tester,
        FakeTwitchApi(schedule: scheduleOf([(DateTime(2026, 11, 20, 13, 30), DateTime(2026, 11, 20, 21))])),
        textScale: 2,
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('the live dot stands out from the surfaces of both themes (3:1 at least)', () {
    double contrast(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
    }

    for (final (scheme, ong) in [(lightScheme, OngColors.light), (darkScheme, OngColors.dark)]) {
      for (final surface in [scheme.surface, scheme.surfaceContainerLowest, scheme.surfaceContainer]) {
        expect(contrast(ong.live, surface), greaterThanOrEqualTo(3), reason: '${scheme.brightness} $surface');
      }
    }
  });
}
