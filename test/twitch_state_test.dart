import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/schedule.dart';
import 'package:ong_music/src/state/catalogue_state.dart';
import 'package:ong_music/src/state/twitch_state.dart';

import 'schedule_test.dart' show twitchFeed;
import 'ui_harness.dart' show FakeTwitchApi;

void main() {
  final start = DateTime.utc(2026, 11, 12, 12);
  late DateTime clock;
  late FakeTwitchApi api;
  late ProviderContainer container;
  late List<TwitchState> states;
  late StreamSchedule schedule;

  setUpAll(() async {
    await loadTimeZones();
    schedule = parseSchedule(twitchFeed.join('\r\n'));
  });

  setUp(() {
    clock = start;
    api = FakeTwitchApi(schedule: schedule, live: true);
    container = ProviderContainer.test(
      overrides: [twitchApiProvider.overrideWithValue(api), clockProvider.overrideWithValue(() => clock)],
    );
    states = [];
    container.listen(twitchProvider, (_, next) => states.add(next), fireImmediately: true);
  });

  TwitchNotifier notifier() => container.read(twitchProvider.notifier);
  TwitchState state() => container.read(twitchProvider);
  (int, int) calls() => (api.scheduleCalls, api.liveCalls);

  test('nothing is requested until watched', () async {
    expect(state().schedule, isNull);
    await notifier().idle;
    await pumpEventQueue();
    expect(calls(), (0, 0));
    notifier().setWatching(true);
    await notifier().idle;
    expect(calls(), (1, 1));
    expect(state().schedule, same(schedule));
    expect(state().scheduleFetchedAt, start);
    expect(state().isLiveAt(start), isTrue);
  });

  test('throttling: the schedule every 6 hours, the live check every 2 minutes', () async {
    notifier().setWatching(true);
    await notifier().idle;
    await notifier().refresh();
    expect(calls(), (1, 1));
    // hidden and shown again a minute later: nothing due
    notifier().setWatching(false);
    clock = start.add(const Duration(minutes: 1));
    notifier().setWatching(true);
    await notifier().idle;
    expect(calls(), (1, 1));
    clock = start.add(const Duration(minutes: 2));
    await notifier().refresh();
    expect(calls(), (1, 2));
    clock = start.add(const Duration(hours: 5, minutes: 59));
    await notifier().refresh();
    expect(calls(), (1, 3));
    // a minute later: the schedule is due, the live check is not
    clock = start.add(const Duration(hours: 6));
    await notifier().refresh();
    expect(calls(), (2, 3));
  });

  test('a refresh running is joined', () async {
    api.gate = Completer();
    notifier().setWatching(true);
    final second = notifier().refresh();
    api.gate!.complete();
    await second;
    expect(calls(), (1, 1));
  });

  test('a failed schedule download keeps the previous schedule, retried after 5 minutes', () async {
    notifier().setWatching(true);
    await notifier().idle;
    clock = start.add(const Duration(hours: 7));
    api.scheduleError = Exception('offline');
    await notifier().refresh();
    expect(calls(), (2, 2));
    expect(state().schedule, same(schedule));
    expect(state().scheduleFetchedAt, start);
    clock = clock.add(const Duration(minutes: 4));
    await notifier().refresh();
    expect(api.scheduleCalls, 2);
    clock = clock.add(const Duration(minutes: 1));
    api.scheduleError = null;
    await notifier().refresh();
    expect(api.scheduleCalls, 3);
    expect(state().scheduleFetchedAt, clock);
  });

  test('a failed first download: still nothing known', () async {
    api.scheduleError = Exception('offline');
    api.live = false;
    notifier().setWatching(true);
    await notifier().idle;
    expect(state().schedule, isNull);
    expect(state().isLiveAt(start), isFalse);
  });

  test('a positive live check expires after 10 minutes, a negative one replaces it', () async {
    notifier().setWatching(true);
    await notifier().idle;
    expect(state().isLiveAt(start.add(const Duration(minutes: 9))), isTrue);
    expect(state().isLiveAt(start.add(const Duration(minutes: 10))), isFalse);
    api.live = false;
    clock = start.add(const Duration(minutes: 3));
    await notifier().refresh();
    expect(state().isLiveAt(clock), isFalse);
  });

  test('results arriving after dispose are dropped', () async {
    api.gate = Completer();
    notifier().setWatching(true);
    final count = states.length;
    container.dispose();
    api.gate!.complete();
    await pumpEventQueue();
    expect(states.length, count);
  });

  test('results of a build gone (invalidate) are dropped', () async {
    api.gate = Completer();
    notifier().setWatching(true);
    // no longer watched: the new build asks nothing, only the old answers could arrive
    notifier().setWatching(false);
    container.invalidate(twitchProvider);
    expect(state().schedule, isNull);
    api.gate!.complete();
    await pumpEventQueue();
    expect(state().schedule, isNull);
    expect(state().liveCheckedAt, isNull);
  });

  testWidgets('invalidated while watched: asks again at once, and keeps polling', (tester) async {
    final fake = FakeTwitchApi(schedule: schedule);
    var now = start;
    final c = ProviderContainer.test(
      overrides: [twitchApiProvider.overrideWithValue(fake), clockProvider.overrideWithValue(() => now)],
    );
    c.read(twitchProvider.notifier).setWatching(true);
    await tester.pump();
    expect((fake.scheduleCalls, fake.liveCalls), (1, 1));
    c.invalidate(twitchProvider);
    expect(c.read(twitchProvider).schedule, isNull);
    await tester.pump();
    expect((fake.scheduleCalls, fake.liveCalls), (2, 2));
    expect(c.read(twitchProvider).schedule, same(schedule));
    now = now.add(const Duration(minutes: 5));
    await tester.pump(const Duration(minutes: 5));
    expect(fake.liveCalls, 3);
    c.dispose();
  });

  testWidgets('every 5 minutes while watched, not when hidden', (tester) async {
    // fake time: a container of its own, created inside the fake zone
    final fake = FakeTwitchApi(schedule: schedule);
    var now = start;
    final c = ProviderContainer.test(
      overrides: [twitchApiProvider.overrideWithValue(fake), clockProvider.overrideWithValue(() => now)],
    );
    c.read(twitchProvider.notifier).setWatching(true);
    await tester.pump();
    expect((fake.scheduleCalls, fake.liveCalls), (1, 1));
    for (var i = 1; i <= 3; i++) {
      now = start.add(Duration(minutes: 5 * i));
      await tester.pump(const Duration(minutes: 5));
      expect(fake.liveCalls, 1 + i);
    }
    expect(fake.scheduleCalls, 1);
    c.read(twitchProvider.notifier).setWatching(false);
    now = now.add(const Duration(minutes: 30));
    await tester.pump(const Duration(minutes: 30));
    expect(fake.liveCalls, 4);
    // shown again: at once
    c.read(twitchProvider.notifier).setWatching(true);
    await tester.pump();
    expect(fake.liveCalls, 5);
    c.dispose();
  });
}
