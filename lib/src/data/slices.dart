/// Running long work in slices, so that the thread it runs on keeps doing its other work between two of them.
///
/// On the web, loading the catalogue runs on the page's only thread: in one go, the megabytes of the sheets would
/// freeze the page for a fifth of a second on a fast laptop, a second on a modest phone. Cut at pause points and run
/// in slices of [sliceBudget], it lets the browser draw a frame between two slices.
///
/// Pure Dart: what lets the browser run is given by the caller ([runInSlices]'s `pause`).
library;

import 'dart:math' as math;

/// The work a slice does before it lets the thread go: one frame of a 120 Hz display lasts 8.3 ms.
const Duration sliceBudget = Duration(milliseconds: 8);

/// The longest a slice may grow to when the work is what the user waits for ([runInSlices]'s `maxBudget`): on a slow
/// device, where a frame of the page costs 15 ms (a fast laptop slowed six times), slices of [sliceBudget] would leave
/// the work a third of the thread, and the catalogue would come a quarter to a third later. With a step more and a
/// collection of garbage, a task stays well under 100 ms there.
const Duration longestSlice = Duration(milliseconds: 50);

/// With a `maxBudget`, a slice lasts this many times the pause before it, so that the work keeps 4/5 of the thread
/// even when every pause holds a frame (a 120 Hz display): the 2–3 ms frame of a fast laptop gives slices of about
/// [sliceBudget].
const int _workPerPause = 4;

/// With a `maxBudget`, a slice lasts at most this much longer than the one before: a single long pause (a task of the
/// page that has nothing to do with frames) does not make a long slice.
const double _growth = 1.5;

/// The work between two pause points of a loop over rows, and a slice overruns its budget by at most one of them.
/// Measured on the real sheets in an optimised web build on a fast laptop (M1), 128 rows a step: 99 % of the steps
/// under 0.3 ms, the longest about 3–4 ms (a collection of garbage); with the CPU slowed six times, 99 % under 2.1 ms,
/// the longest 11–12 ms. With 256 rows, the same total, but 4–6.5 ms and 13–23 ms slowed.
const int rowsPerPause = 128;

/// The work between two pause points of a loop over the code units of a text: a fraction of a millisecond.
const int unitsPerPause = 1 << 16;

/// Thrown by [runInSlices] when the work is no longer wanted: what it was doing is left unfinished.
final class LoadAbandoned implements Exception {
  /// Creates the exception.
  const LoadAbandoned();

  @override
  String toString() => 'The load was abandoned';
}

/// Runs [step] until it returns false (the work is done), in slices of about [budget]: before each slice, [pause] lets
/// the thread do something else. [step] does the work up to its next pause point; a slice overruns [budget] by at most
/// one of them. A [budget] of zero pauses before every step.
///
/// With a [maxBudget] longer than [budget], a slice lasts four times the pause before it, within [budget] and
/// [maxBudget], and at most half as long again as the slice before: when the frames the browser draws during the
/// pauses are costly (a slow device), the work still gets 4/5 of the thread; a single long pause makes one slice half
/// as long again, no more. For work the user waits for, with nothing else on the screen; not while they scroll a
/// list, whose frames come first.
///
/// It starts with a pause too: what ran before it in the same task (the last slice of another run, the reading of a
/// download) does not lengthen its first slice.
///
/// [clock] is a monotonic time in microseconds (a [Stopwatch] when null). [isAbandoned] is asked after each pause:
/// when it says so, [runInSlices] throws [LoadAbandoned] and calls [step] no more. A failure of [step] is thrown as
/// it is.
Future<void> runInSlices(
  bool Function() step, {
  required Future<void> Function() pause,
  Duration budget = sliceBudget,
  int Function()? clock,
  Duration? maxBudget,
  bool Function()? isAbandoned,
}) async {
  final watch = clock == null ? (Stopwatch()..start()) : null;
  final now = clock ?? () => watch!.elapsedMicroseconds;
  final shortest = budget.inMicroseconds, longest = maxBudget?.inMicroseconds ?? shortest;
  var limit = shortest;
  while (true) {
    final pauseStart = now();
    await pause();
    if (isAbandoned?.call() ?? false) throw const LoadAbandoned();
    final sliceStart = now();
    if (longest > shortest) {
      final wanted = (_workPerPause * (sliceStart - pauseStart)).clamp(shortest, longest);
      limit = math.max(shortest, math.min(wanted, (limit * _growth).round()));
    }
    bool more;
    do {
      more = step();
    } while (more && now() - sliceStart < limit);
    if (!more) return;
  }
}

/// How long the thread may still give to background work before it is wanted again (the next frame), in
/// microseconds: what `requestIdleCallback` tells on the web.
typedef IdleDeadline = int Function();

/// What [runWhenIdle] leaves of an idle period, at least: a step is started only when this much is left, or the
/// length of the longest step lately if longer.
const int _idleMargin = 1000;

/// How long background work keeps to the idle time ([runWhenIdle]) before it goes on between frames as work the user
/// waits for does: while a list is scrolled without a pause, frames may leave it no idle time at all, and the Songs
/// sheet (2,265 steps) would come one step a second, if at all.
const Duration idlePatience = Duration(seconds: 5);

/// Runs [step] until it returns false (the work is done), in the idle time of the thread: [idle] waits for it and
/// tells how long it lasts (on the web, `requestIdleCallback`, see `waitForIdle`). A step is started only when the
/// idle period has room for it: a millisecond, or the longest step lately when longer; an idle period too short
/// waits for the next one. For background work the user does not wait for, while a list may be scrolled: the
/// browser gives it the time its frames leave, so that it never delays one (at 120 Hz, the 8.3 ms of a frame less
/// what drawing it took).
///
/// It goes on between frames as [runInSlices] does for work the user waits for ([pause], [longestSlice]) as soon as
/// [hurry] says so (the Ong Log waits for the Songs sheet), or once [patience] has passed since it started: frames
/// that leave no idle time would hold it back for ever. [clock] is a monotonic time in microseconds (a [Stopwatch]
/// when null). [isAbandoned] and the failures of [step] as for [runInSlices].
Future<void> runWhenIdle(
  bool Function() step, {
  required Future<IdleDeadline> Function() idle,
  required Future<void> Function() pause,
  bool Function()? isAbandoned,
  bool Function()? hurry,
  int Function()? clock,
  Duration patience = idlePatience,
}) async {
  final watch = clock == null ? (Stopwatch()..start()) : null;
  final now = clock ?? () => watch!.elapsedMicroseconds;
  final start = now();
  // the longest step lately, forgotten slowly: an outlier (a collection of garbage) does not hold back the rest
  var cost = 0;
  while (true) {
    if ((hurry?.call() ?? false) || now() - start >= patience.inMicroseconds) {
      return runInSlices(step, pause: pause, clock: clock, maxBudget: longestSlice, isAbandoned: isAbandoned);
    }
    final deadline = await idle();
    if (isAbandoned?.call() ?? false) throw const LoadAbandoned();
    while (deadline() >= math.max(_idleMargin, cost)) {
      final before = now();
      final more = step();
      final took = now() - before;
      cost = math.max(took, cost * 7 ~/ 8);
      if (!more) return;
    }
  }
}
