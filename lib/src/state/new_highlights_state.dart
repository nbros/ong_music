/// Which highlights are new since the user's last visit: the `New` marks of
/// the Highlights list, its `New` chip and the count on its navigation
/// destination.
///
/// A highlight is new when its key (`Highlight.key`) was not among the
/// highlights the app knew at the end of the previous visit. A visit ends when
/// the app stays out of sight for [highlightVisitGap] or more after the
/// Highlights list was shown in it: a trip to YouTube or to another app, even
/// one during which the system ends the process, comes back to the same
/// visit, with the same marks. A visit that never showed the list ends
/// nothing. Until a first visit has ended (the first run, also the first run
/// of the first version with this) nothing is new: every highlight of that
/// visit becomes known, seen or not.
///
/// A visit makes known only what it could show: the highlights of the list
/// when it is on screen, in sight. Those a refresh brings while the app is out
/// of sight, or on another tab, join the visit when the list is next on
/// screen; if the visit ends first, they are new in the next one.
///
/// "Out of sight" is the app lifecycle (hidden or paused) on Android and
/// Windows, the visibility of the page in a browser: [KnownHighlightsNotifier.sync]
/// is told by the Highlights page.
///
/// What is stored, so that all this survives the end of the process:
/// - [KnownHighlightsNotifier.key]: the keys known at the end of the previous
///   visits, only ever added to (a download briefly lacking a highlight does
///   not make it new again), and merged with the stored ones when written
///   (another tab of the browser, another window). Absent until a first visit
///   ended.
/// - [KnownHighlightsNotifier.visitKey]: the visit under way, once the list
///   was shown in it: a time the app was in sight, then the keys it has shown
///   that are not known yet. Absent between visits.
/// - [KnownHighlightsNotifier.seenKey]: the last time the app was known in
///   sight during the visit, written every [highlightVisitBeat] while in sight
///   and at each change of tab or of sight, without writing the keys again.
///
/// Each is one value, written whole: a write cut short leaves the previous
/// value. The visit is in sight until the later of its two times, so a write
/// of one without the other loses nothing. The end of a visit adds its keys to
/// the known ones, then removes the visit, then its time; the process ending
/// between them only leaves the visit to end again at the next start, which
/// adds nothing more, or a time without visit, which is not read. The process
/// ending while the app is in sight (a crash, a window closed without a last
/// event) counts the time away from the last beat: at most [highlightVisitBeat]
/// too early.
library;

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalogue.dart';
import '../logger.dart';
import 'catalogue_state.dart';
import 'settings_state.dart';

/// How long the app must stay out of sight, after the Highlights list was
/// shown, for the visit to end: its highlights are then no longer new.
const Duration highlightVisitGap = Duration(hours: 1);

/// How often the time the app is in sight is stored during a visit.
const Duration highlightVisitBeat = Duration(minutes: 5);

/// The keys of the highlights the app knew at the end of the previous visit;
/// null until a first visit has ended (nothing is new then). It does not
/// change during a visit: the marks stay.
final knownHighlightsProvider = NotifierProvider<KnownHighlightsNotifier, Set<String>?>(KnownHighlightsNotifier.new);

/// Holds [knownHighlightsProvider] and the visit under way, and stores both.
class KnownHighlightsNotifier extends Notifier<Set<String>?> {
  /// Preference key of the known keys, a list of `Highlight.key`.
  static const key = 'knownHighlights';

  /// Preference key of the visit under way: a time the app was in sight (milliseconds since the epoch), then the
  /// keys of the visit that are not known yet.
  static const visitKey = 'highlightVisit';

  /// Preference key of the last time the app was known in sight during the visit (milliseconds since the epoch).
  static const seenKey = 'highlightVisitSeen';

  /// The keys of the visit under way that are not known yet; null without visit.
  Set<String>? _visit;

  /// The last time the app was known in sight.
  DateTime _seenAt = DateTime.utc(0);

  /// Whether the app is in sight; false at the start, until [sync] says otherwise.
  bool _inSight = false;

  /// Since when the app is out of sight, when known.
  DateTime? _hiddenSince;

  bool _listOnScreen = false;

  /// Stores the time in sight while a visit is under way in sight.
  Timer? _beat;

  /// The writes still to do, one after the other.
  Future<void> _writes = Future.value();

  @override
  Set<String>? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    ref.onDispose(() => _beat?.cancel());
    var known = _storedKnown(prefs);
    final visit = _storedVisit(prefs);
    _visit = null;
    if (visit != null) {
      // the later of the two times: either may be the one written last
      final seen = _storedSeen(prefs);
      final seenAt = seen != null && seen.isAfter(visit.seenAt) ? seen : visit.seenAt;
      if (_ended(seenAt)) {
        // the app was closed, or the process ended, more than the gap ago
        known = _adopt(known, visit.keys);
      } else {
        // the same visit goes on: out of sight since its last record
        _visit = visit.keys;
        _seenAt = seenAt;
        _hiddenSince = seenAt;
      }
    }
    // a refresh: its new highlights join the visit when the list shows them (on the first visit, whatever they are)
    ref.listen(currentCatalogueProvider, (_, catalogue) {
      if (_visit == null) return _startIfShown();
      if (state == null || _shown) _record(catalogue);
    });
    return known;
  }

  DateTime _now() => ref.read(clockProvider)();

  bool _ended(DateTime since) => _now().difference(since) >= highlightVisitGap;

  /// The list is on screen, in sight.
  bool get _shown => _inSight && _listOnScreen;

  static Set<String>? _storedKnown(SharedPreferences prefs) {
    try {
      final keys = prefs.getStringList(key);
      return keys == null ? null : Set.unmodifiable(keys);
    } catch (e, st) {
      // something else than a list of strings under the key: as on a first run
      logger.w('Unreadable known highlights', error: e, stackTrace: st);
      return null;
    }
  }

  static ({DateTime seenAt, Set<String> keys})? _storedVisit(SharedPreferences prefs) {
    try {
      final values = prefs.getStringList(visitKey);
      final millis = values == null || values.isEmpty ? null : int.tryParse(values.first);
      if (millis == null) return null;
      return (seenAt: DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true), keys: values!.skip(1).toSet());
    } catch (e, st) {
      // unreadable: no visit under way
      logger.w('Unreadable highlight visit', error: e, stackTrace: st);
      return null;
    }
  }

  static DateTime? _storedSeen(SharedPreferences prefs) {
    try {
      final millis = prefs.getInt(seenKey);
      return millis == null ? null : DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true);
    } catch (e, st) {
      // unreadable: the time of the visit alone
      logger.w('Unreadable highlight visit time', error: e, stackTrace: st);
      return null;
    }
  }

  /// [known] with the keys of a visit that ended; stored with the keys stored meanwhile (another tab, another
  /// window), then the visit removed, then its time.
  Set<String>? _adopt(Set<String>? known, Set<String> keys) {
    // a first visit with no highlight adopts nothing: every highlight would be new after it
    final adopted = known == null && keys.isEmpty ? null : Set<String>.unmodifiable({...?known, ...keys});
    _write((prefs) async {
      if (adopted != null) {
        await prefs.reload();
        final merged = {...?_storedKnown(prefs), ...adopted};
        if (!await prefs.setStringList(key, merged.toList())) logger.w('The known highlights were not stored');
      }
      await prefs.remove(visitKey);
      await prefs.remove(seenKey);
    });
    return adopted;
  }

  /// Stores the visit: its keys, with the last time in sight.
  void _writeVisit() {
    final visit = _visit;
    if (visit == null) return;
    final values = ['${_seenAt.millisecondsSinceEpoch}', ...visit];
    _write((prefs) async {
      if (!await prefs.setStringList(visitKey, values)) logger.w('The highlight visit was not stored');
    });
  }

  /// Stores the last time in sight alone.
  void _writeSeen() {
    if (_visit == null) return;
    final millis = _seenAt.millisecondsSinceEpoch;
    _write((prefs) => prefs.setInt(seenKey, millis));
  }

  void _write(Future<void> Function(SharedPreferences prefs) write) {
    final prefs = ref.read(sharedPreferencesProvider);
    _writes = _writes.then((_) async {
      try {
        await write(prefs);
      } catch (e, st) {
        // kept in memory for this session
        logger.w('Cannot store the highlight visit', error: e, stackTrace: st);
      }
    });
  }

  /// Starts the visit when the Highlights list is on screen, with a catalogue, in sight.
  void _startIfShown() {
    if (_visit != null || !_shown) return;
    final catalogue = ref.read(currentCatalogueProvider);
    if (catalogue == null) return;
    _visit = _unknownKeys(catalogue, state).toSet();
    _seenAt = _now();
    _writeVisit();
    _writeSeen();
    _syncBeat();
  }

  /// The keys of [catalogue] not known yet join the visit.
  void _record(Catalogue? catalogue) {
    final visit = _visit;
    if (visit == null || catalogue == null) return;
    final before = visit.length;
    visit.addAll(_unknownKeys(catalogue, state));
    if (visit.length > before) _writeVisit();
  }

  /// The beat runs while a visit is under way in sight.
  void _syncBeat() {
    if (_visit != null && _inSight) {
      _beat ??= Timer.periodic(highlightVisitBeat, (_) => _stillInSight());
    } else {
      _beat?.cancel();
      _beat = null;
    }
  }

  void _stillInSight() {
    _seenAt = _now();
    _writeSeen();
  }

  /// Tells whether the app is [inSight], and whether the Highlights tab is the
  /// one selected ([listOnScreen], in sight or not).
  ///
  /// Coming back in sight after [highlightVisitGap] or more ends the visit
  /// under way: its highlights are no longer new.
  void sync({required bool inSight, required bool listOnScreen}) {
    final now = _now();
    if (inSight != _inSight) {
      _inSight = inSight;
      if (!inSight) {
        _hiddenSince = now;
        _seenAt = now;
        _writeSeen();
      } else {
        final hiddenSince = _hiddenSince;
        _hiddenSince = null;
        final visit = _visit;
        if (visit != null && hiddenSince != null && _ended(hiddenSince)) {
          _visit = null;
          state = _adopt(state, visit);
        }
      }
    }
    _listOnScreen = listOnScreen;
    if (_visit == null) {
      _startIfShown();
    } else if (inSight) {
      // in sight now (a change of tab, of sight): the time, and what the list shows if it is on screen
      _seenAt = now;
      _writeSeen();
      if (_listOnScreen) _record(ref.read(currentCatalogueProvider));
    }
    _syncBeat();
  }
}

/// The keys of the highlights of the current catalogue that are new: not
/// among [knownHighlightsProvider]. Empty without catalogue, and until a
/// first visit has ended.
final newHighlightKeysProvider = Provider<Set<String>>((ref) {
  final known = ref.watch(knownHighlightsProvider);
  final catalogue = ref.watch(currentCatalogueProvider);
  if (known == null || catalogue == null) return const {};
  return Set.unmodifiable(_unknownKeys(catalogue, known));
});

/// The keys of the highlights of [catalogue] that are not in [known] (all of them when it is null).
Iterable<String> _unknownKeys(Catalogue catalogue, Set<String>? known) => [
  for (final h in catalogue.highlights)
    if (known == null || !known.contains(h.key)) h.key,
];

/// How many highlights of the current catalogue are new: the count on the
/// Highlights destination of the navigation, and of the `New` chip, which
/// only show when it is not 0.
final newHighlightCountProvider = Provider<int>(
  (ref) => ref.watch(currentCatalogueProvider)?.highlightCountWithKeys(ref.watch(newHighlightKeysProvider)) ?? 0,
);
