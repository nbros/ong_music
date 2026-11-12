/// Riverpod state of the Twitch status of the About tab: the channel's
/// schedule and whether it is live, and when to ask Twitch.
///
/// Read [twitchProvider] for a [TwitchState]; the About tab tells
/// `ref.read(twitchProvider.notifier)` ([TwitchNotifier]) when it is on screen.
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/schedule.dart';
import '../data/twitch.dart';
import '../logger.dart';
import 'catalogue_state.dart';

/// A schedule downloaded less than this long ago is not downloaded again
/// (the feed itself asks for `REFRESH-INTERVAL:PT6H`).
const Duration scheduleMaxAge = Duration(hours: 6);

/// After a failed schedule download, the next attempt waits this long.
const Duration scheduleRetryDelay = Duration(minutes: 5);

/// The live check runs at most once in this time.
const Duration liveCheckInterval = Duration(minutes: 2);

/// While the About tab stays on screen, Twitch is asked again this often
/// (within the limits above).
const Duration twitchRefreshPeriod = Duration(minutes: 5);

/// A positive live check older than this no longer counts (the app was in the
/// background, or the tab hidden, meanwhile).
const Duration liveResultMaxAge = Duration(minutes: 10);

// ------------------------------------------------------------ dependencies
// Overridden in tests.

/// Asks Twitch.
final twitchApiProvider = Provider<TwitchApi>((ref) => HttpTwitchApi());

// ------------------------------------------------------------ state

/// What is known about the channel.
@immutable
final class TwitchState {
  /// Creates a state; the default knows nothing.
  const TwitchState({this.schedule, this.scheduleFetchedAt, this.live = false, this.liveCheckedAt});

  /// The last schedule downloaded, null until one is.
  final StreamSchedule? schedule;

  /// When [schedule] was downloaded (UTC).
  final DateTime? scheduleFetchedAt;

  /// Result of the last live check (false on any doubt).
  final bool live;

  /// When the last live check ended (UTC).
  final DateTime? liveCheckedAt;

  /// The channel is known to be live at [now]: a recent positive check.
  bool isLiveAt(DateTime now) {
    final checkedAt = liveCheckedAt;
    return live && checkedAt != null && now.difference(checkedAt).abs() < liveResultMaxAge;
  }

  /// The occurrence in progress and the next one at [now].
  ScheduleStatus scheduleAt(DateTime now) => schedule?.statusAt(now) ?? (current: null, next: null);

  @override
  String toString() => 'TwitchState(schedule: $schedule at $scheduleFetchedAt, live: $live at $liveCheckedAt)';
}

/// The Twitch status and its refresh policy.
final twitchProvider = NotifierProvider<TwitchNotifier, TwitchState>(TwitchNotifier.new);

/// Refresh policy:
/// - nothing is requested until [setWatching] is called with true (the About
///   tab is on screen and the app in the foreground);
/// - then at once, and every [twitchRefreshPeriod] while it stays true; a new
///   true (tab shown again, app resumed) refreshes at once too;
/// - each refresh downloads the schedule when the last one is older than
///   [scheduleMaxAge] (or failed more than [scheduleRetryDelay] ago), and
///   checks the live status when the last check is older than
///   [liveCheckInterval]; both run in parallel, each bounded by
///   [twitchTimeout];
/// - a failed download keeps the schedule known (if any); a failed live check
///   means not live. Failures are logged.
class TwitchNotifier extends Notifier<TwitchState> {
  // As in CatalogueNotifier: the notifier object survives `ref.invalidate`, so
  // each build has a generation and work of an older one drops its result.
  int _generation = 0;
  bool _disposed = false;

  bool _watching = false;
  Timer? _timer;
  Future<void>? _refresh;
  DateTime? _scheduleAttemptAt;
  bool _scheduleFailed = false;
  DateTime? _liveAttemptAt;

  DateTime _now() => ref.read(clockProvider)();

  @override
  TwitchState build() {
    final generation = ++_generation;
    // Watching is the screen's business and survives `ref.invalidate`: the
    // status stays on screen, so the new build asks again at once and polls.
    final watching = _watching;
    _disposed = false;
    _watching = false;
    _timer?.cancel();
    _timer = null;
    _refresh = null;
    _scheduleAttemptAt = null;
    _scheduleFailed = false;
    _liveAttemptAt = null;
    ref.onDispose(() {
      if (_generation != generation) return;
      _generation++;
      _disposed = true;
      _timer?.cancel();
      _timer = null;
    });
    if (watching) Future.microtask(() => setWatching(true));
    return const TwitchState();
  }

  /// Whether the status is on screen. Becoming true refreshes at once, then
  /// every [twitchRefreshPeriod] until it is false again.
  void setWatching(bool watching) {
    if (_disposed || watching == _watching) return;
    _watching = watching;
    _timer?.cancel();
    _timer = null;
    if (!watching) return;
    _timer = Timer.periodic(twitchRefreshPeriod, (_) => unawaited(refresh()));
    unawaited(refresh());
  }

  /// Asks Twitch what is due (see the class comment). Returns when done;
  /// never throws. Joins a refresh already running.
  Future<void> refresh() {
    if (_disposed) return Future<void>.value();
    final running = _refresh;
    if (running != null) return running;
    late final Future<void> tracked;
    tracked = _run(_generation).whenComplete(() {
      if (identical(_refresh, tracked)) _refresh = null;
    });
    return _refresh = tracked;
  }

  bool _due(DateTime? last, Duration interval, DateTime now) => last == null || now.difference(last).abs() >= interval;

  Future<void> _run(int generation) async {
    final now = _now();
    final work = <Future<void>>[];
    if (_due(_scheduleAttemptAt, _scheduleFailed ? scheduleRetryDelay : scheduleMaxAge, now)) {
      _scheduleAttemptAt = now;
      work.add(_downloadSchedule(generation));
    }
    if (_due(_liveAttemptAt, liveCheckInterval, now)) {
      _liveAttemptAt = now;
      work.add(_checkLive(generation));
    }
    await Future.wait(work);
  }

  Future<void> _downloadSchedule(int generation) async {
    try {
      final schedule = await ref.read(twitchApiProvider).fetchSchedule();
      if (generation != _generation) return;
      _scheduleFailed = false;
      _scheduleFailure = null;
      logger.i('Twitch schedule downloaded: $schedule');
      state = TwitchState(
        schedule: schedule,
        scheduleFetchedAt: _now(),
        live: state.live,
        liveCheckedAt: state.liveCheckedAt,
      );
    } catch (e) {
      // Once per kind of failure, without its stack: with the About tab left open offline, the same lines every few
      // minutes would fill the log file.
      if ('$e' != _scheduleFailure) logger.w('Twitch schedule download failed: $e');
      _scheduleFailure = '$e';
      if (generation != _generation) return;
      _scheduleFailed = true;
    }
  }

  /// The last failure of the schedule download logged, null after a success.
  String? _scheduleFailure;

  Future<void> _checkLive(int generation) async {
    var live = false;
    try {
      live = await ref.read(twitchApiProvider).isLive();
    } catch (e) {
      // the API reports its own failures as "not live": only what it lets through comes here
      logger.w('Live check failed: $e');
    }
    if (generation != _generation) return;
    state = TwitchState(
      schedule: state.schedule,
      scheduleFetchedAt: state.scheduleFetchedAt,
      live: live,
      liveCheckedAt: _now(),
    );
  }

  /// Completes when the running refresh (if any) is over.
  Future<void> get idle async {
    while (_refresh != null) {
      await _refresh;
    }
  }
}
