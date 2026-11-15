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
/// of the first version with this) nothing is new: the highlights of that
/// visit become the known ones.
///
/// "Out of sight" is the app lifecycle (hidden or paused) on Android and
/// Windows, the visibility of the page in a browser: [KnownHighlightsNotifier.sync]
/// is told by the Highlights page.
///
/// What is stored, so that all this survives the end of the process:
/// - [KnownHighlightsNotifier.key]: the keys known at the end of the previous
///   visits, only ever added to (a download briefly lacking a highlight does
///   not make it new again). Absent until a first visit ended.
/// - [KnownHighlightsNotifier.visitKey]: the visit under way, once the list
///   was shown in it: when the app was last known in sight, then the keys it
///   has shown that are not known yet. Absent between visits.
///
/// Each is one value, written whole: a write cut short leaves the previous
/// value. The end of a visit adds its keys to the known ones, then removes
/// the visit; the process ending between the two only leaves the visit to end
/// again at the next start, which adds nothing more. The process ending while
/// the app is in sight (a crash) counts the time from the last moment
/// recorded: the start of the visit, or the last time the app came back in
/// sight.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/catalogue.dart';
import '../logger.dart';
import 'catalogue_state.dart';
import 'settings_state.dart';

/// How long the app must stay out of sight, after the Highlights list was
/// shown, for the visit to end: its highlights are then no longer new.
const Duration highlightVisitGap = Duration(hours: 1);

/// The keys of the highlights the app knew at the end of the previous visit;
/// null until a first visit has ended (nothing is new then). It does not
/// change during a visit: the marks stay.
final knownHighlightsProvider = NotifierProvider<KnownHighlightsNotifier, Set<String>?>(KnownHighlightsNotifier.new);

/// The visit under way, once the Highlights list was shown in it.
final class _Visit {
  _Visit(this.seenAt, this.keys);

  /// When the app was last known in sight.
  DateTime seenAt;

  /// The keys of the highlights of the visit that are not known yet.
  final Set<String> keys;
}

/// Holds [knownHighlightsProvider] and the visit under way, and stores both.
class KnownHighlightsNotifier extends Notifier<Set<String>?> {
  /// Preference key of the known keys, a list of `Highlight.key`.
  static const key = 'knownHighlights';

  /// Preference key of the visit under way: the time the app was last known in sight (milliseconds since the
  /// epoch), then the keys of the visit that are not known yet.
  static const visitKey = 'highlightVisit';

  _Visit? _visit;

  /// Whether the app is in sight; false at the start, until [sync] says otherwise.
  bool _inSight = false;

  /// Since when the app is out of sight, when known.
  DateTime? _hiddenSince;

  bool _listOnScreen = false;

  /// The writes still to do, one after the other.
  Future<void> _writes = Future.value();

  @override
  Set<String>? build() {
    final prefs = ref.watch(sharedPreferencesProvider);
    var known = _storedKnown(prefs);
    final visit = _storedVisit(prefs);
    _visit = null;
    if (visit != null && _ended(visit.seenAt)) {
      // the app was closed, or the process ended, more than the gap ago
      known = _adopt(known, visit.keys);
    } else if (visit != null) {
      // the same visit goes on: out of sight since its last record
      _visit = visit;
      _hiddenSince = visit.seenAt;
    }
    // a refresh during the visit: its new highlights join the visit
    ref.listen(currentCatalogueProvider, (_, catalogue) {
      final visit = _visit;
      if (visit == null) return _startIfShown();
      if (catalogue == null) return;
      final before = visit.keys.length;
      visit.keys.addAll(_unknownKeys(catalogue, state));
      if (visit.keys.length > before) _writeVisit();
    });
    return known;
  }

  DateTime _now() => ref.read(clockProvider)();

  bool _ended(DateTime since) => _now().difference(since) >= highlightVisitGap;

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

  static _Visit? _storedVisit(SharedPreferences prefs) {
    try {
      final values = prefs.getStringList(visitKey);
      final millis = values == null || values.isEmpty ? null : int.tryParse(values.first);
      if (millis == null) return null;
      return _Visit(DateTime.fromMillisecondsSinceEpoch(millis, isUtc: true), values!.skip(1).toSet());
    } catch (e, st) {
      // unreadable: no visit under way
      logger.w('Unreadable highlight visit', error: e, stackTrace: st);
      return null;
    }
  }

  /// [known] with the keys of a visit that ended, stored; then the visit removed.
  Set<String>? _adopt(Set<String>? known, Set<String> keys) {
    // a first visit with no highlight adopts nothing: every highlight would be new after it
    if (known == null && keys.isEmpty) {
      _write((prefs) => prefs.remove(visitKey));
      return null;
    }
    final adopted = Set<String>.unmodifiable({...?known, ...keys});
    _write((prefs) async {
      if (!await prefs.setStringList(key, adopted.toList())) logger.w('The known highlights were not stored');
      await prefs.remove(visitKey);
    });
    return adopted;
  }

  void _writeVisit() {
    final visit = _visit;
    if (visit == null) return;
    final values = ['${visit.seenAt.millisecondsSinceEpoch}', ...visit.keys];
    _write((prefs) async {
      if (!await prefs.setStringList(visitKey, values)) logger.w('The highlight visit was not stored');
    });
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
    if (_visit != null || !_inSight || !_listOnScreen) return;
    final catalogue = ref.read(currentCatalogueProvider);
    if (catalogue == null) return;
    _visit = _Visit(_now(), _unknownKeys(catalogue, state).toSet());
    _writeVisit();
  }

  /// Tells whether the app is [inSight], and whether the Highlights tab is the
  /// one selected ([listOnScreen], in sight or not).
  ///
  /// Coming back in sight after [highlightVisitGap] or more ends the visit
  /// under way: its highlights are no longer new.
  void sync({required bool inSight, required bool listOnScreen}) {
    if (inSight != _inSight) {
      _inSight = inSight;
      final visit = _visit;
      final now = _now();
      if (!inSight) {
        _hiddenSince = now;
        visit?.seenAt = now;
        _writeVisit();
      } else {
        final hiddenSince = _hiddenSince;
        _hiddenSince = null;
        if (visit != null && hiddenSince != null && _ended(hiddenSince)) {
          _visit = null;
          state = _adopt(state, visit.keys);
        } else if (visit != null) {
          visit.seenAt = now;
          _writeVisit();
        }
      }
    }
    _listOnScreen = listOnScreen;
    _startIfShown();
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
