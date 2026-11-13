/// State of the UI shell: the selected tab, the filters of the two lists and
/// what their detail panes show in an expanded window.
///
/// Kept in providers (not in the page widgets) because other places change
/// them: the "N in the Ong Log →" link, a requester tap in a sheet, the
/// links of a fiche, the keyboard.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

import '../data/catalogue.dart';
import '../data/model.dart';
import '../state/catalogue_state.dart';

/// The three destinations of the navigation bar.
enum AppTab { highlights, ongLog, about }

/// The selected tab.
final selectedTabProvider = NotifierProvider<SelectedTabNotifier, AppTab>(SelectedTabNotifier.new);

/// Holds [AppTab].
class SelectedTabNotifier extends Notifier<AppTab> {
  @override
  AppTab build() => AppTab.highlights;

  /// Shows [tab].
  void select(AppTab tab) => state = tab;
}

/// The focus node of the search field of [AppTab.highlights] or
/// [AppTab.ongLog], for the keyboard shortcut that reaches it.
final searchFocusProvider = Provider.family<FocusNode, AppTab>((ref, tab) {
  final node = FocusNode(debugLabel: 'search ${tab.name}');
  ref.onDispose(node.dispose);
  return node;
});

/// Filters of the Highlights list.
final highlightFilterProvider = NotifierProvider<HighlightFilterNotifier, HighlightFilter>(HighlightFilterNotifier.new);

/// Holds the [HighlightFilter] of the Highlights tab.
class HighlightFilterNotifier extends Notifier<HighlightFilter> {
  @override
  HighlightFilter build() {
    // the "You" chip is gone (Twitch name changed, refresh): its filter goes with it, and does not come back with it
    ref.listen(myHighlightCountProvider, (_, count) {
      if (count == 0 && state.mine) {
        state = HighlightFilter(query: state.query, genre: state.genre, favourites: state.favourites);
      }
    });
    // the star chip is gone (last star removed, refresh): the same
    ref.listen(favouriteCountProvider, (_, count) {
      if (count == 0 && state.favourites) {
        state = HighlightFilter(query: state.query, genre: state.genre, mine: state.mine);
      }
    });
    return const HighlightFilter();
  }

  void setQuery(String query) =>
      state = HighlightFilter(query: query, genre: state.genre, mine: state.mine, favourites: state.favourites);

  /// Removes every chip filter, keeps the query ("All").
  void clearChips() => state = HighlightFilter(query: state.query);

  /// Selects [genre], or all genres when it is null or already selected.
  void toggleGenre(Genre? genre) => state = HighlightFilter(
    query: state.query,
    genre: genre == state.genre ? null : genre,
    mine: state.mine,
    favourites: state.favourites,
  );

  /// Shows only the user's own requests, or all of them again ("You").
  void toggleMine() =>
      state = HighlightFilter(query: state.query, genre: state.genre, mine: !state.mine, favourites: state.favourites);

  /// Shows only the favourites, or all highlights again (the star chip).
  void toggleFavourites() =>
      state = HighlightFilter(query: state.query, genre: state.genre, mine: state.mine, favourites: !state.favourites);
}

/// Filters of the Ong Log list.
final playFilterProvider = NotifierProvider<PlayFilterNotifier, PlayFilter>(PlayFilterNotifier.new);

/// Holds the [PlayFilter] of the Ong Log tab.
class PlayFilterNotifier extends Notifier<PlayFilter> {
  @override
  PlayFilter build() {
    // the "You" chip is gone (Twitch name changed, refresh): its filter goes with it, and does not come back with it
    ref.listen(myPlayCountProvider, (_, count) {
      if (count == 0 && state.mine) {
        state = PlayFilter(query: state.query, type: state.type, genre: state.genre, withVideo: state.withVideo);
      }
    });
    return const PlayFilter();
  }

  void setQuery(String query) => state = PlayFilter(
    query: query,
    type: state.type,
    genre: state.genre,
    withVideo: state.withVideo,
    mine: state.mine,
  );

  /// Removes every chip filter, keeps the query ("All").
  void clearChips() => state = PlayFilter(query: state.query);

  /// Selects [type], or none when it is already selected.
  void toggleType(PlayType type) => state = PlayFilter(
    query: state.query,
    type: type == state.type ? null : type,
    genre: state.genre,
    withVideo: state.withVideo,
    mine: state.mine,
  );

  /// Selects [genre], or none when it is already selected.
  void toggleGenre(Genre genre) => state = PlayFilter(
    query: state.query,
    type: state.type,
    genre: genre == state.genre ? null : genre,
    withVideo: state.withVideo,
    mine: state.mine,
  );

  void toggleWithVideo() => state = PlayFilter(
    query: state.query,
    type: state.type,
    genre: state.genre,
    withVideo: !state.withVideo,
    mine: state.mine,
  );

  /// Shows only the user's own requests, or all of them again ("You").
  void toggleMine() => state = PlayFilter(
    query: state.query,
    type: state.type,
    genre: state.genre,
    withVideo: state.withVideo,
    mine: !state.mine,
  );

  /// Shows every play matching [query], without chip filter.
  void searchOnly(String query) => state = PlayFilter(query: query);
}

/// Opens the Ong Log on [query], without chip filter: the link shows the number
/// of plays matching the query alone (cross-link of the Highlights search).
void showOngLogFor(WidgetRef ref, String query) {
  ref.read(playFilterProvider.notifier).searchOnly(query);
  ref.read(selectedTabProvider.notifier).select(AppTab.ongLog);
  FocusManager.instance.primaryFocus?.unfocus();
}

/// Opens the Ong Log on the requests of [name], without chip filter.
void showRequesterInOngLog(WidgetRef ref, String name) {
  ref.read(playFilterProvider.notifier).searchOnly(name);
  ref.read(selectedTabProvider.notifier).select(AppTab.ongLog);
  FocusManager.instance.primaryFocus?.unfocus();
}

// ------------------------------------------------------------------ fiches and the detail pane

/// What a detail sheet, or the detail pane of an expanded window, shows: a
/// highlight, a song (every time it was played) or a stream setlist, with the
/// [catalogue] its items come from (ids are only valid with their catalogue).
@immutable
sealed class Fiche {
  const Fiche(this.catalogue);

  final Catalogue catalogue;

  /// The same fiche with the items of [next] (a refresh), or null when its
  /// item is no longer there.
  Fiche? translate(Catalogue next);

  /// What the fiche shows, whatever the catalogue: equal for the same fiche
  /// before and after a refresh.
  Object get identity;
}

/// The fiche of a highlight.
final class HighlightFiche extends Fiche {
  const HighlightFiche(super.catalogue, this.highlight);

  final Highlight highlight;

  @override
  HighlightFiche? translate(Catalogue next) {
    if (identical(next, catalogue)) return this;
    final h = _sameHighlight(highlight, next);
    return h == null ? null : HighlightFiche(next, h);
  }

  @override
  Object get identity => ('highlight', highlight.key);
}

/// The fiche of a song: every time it was played.
final class SongFiche extends Fiche {
  const SongFiche(super.catalogue, this.song, {this.play});

  final Song song;

  /// The row of the Ong Log it was chosen from: marked as selected there.
  final Play? play;

  @override
  SongFiche? translate(Catalogue next) {
    if (identical(next, catalogue)) return this;
    final s = next.song(song.key);
    if (s == null) return null;
    final p = play;
    // the row may have gone while the song stays: the fiche stays, unmarked in the list
    return SongFiche(next, s, play: p == null ? null : _samePlay(catalogue, p, next));
  }

  @override
  Object get identity => ('song', song.key, play == null ? null : _playIdentity(catalogue, play!));
}

/// The setlist of a stream.
final class StreamFiche extends Fiche {
  const StreamFiche(super.catalogue, this.stream, {this.play});

  final LiveStream stream;

  /// The play the setlist was opened from: tinted and scrolled into view.
  final Play? play;

  @override
  StreamFiche? translate(Catalogue next) {
    if (identical(next, catalogue)) return this;
    final s = _sameStream(catalogue, stream, next);
    if (s == null) return null;
    final p = play;
    if (p == null) return StreamFiche(next, s);
    final q = _samePlay(catalogue, p, next);
    return q == null ? null : StreamFiche(next, s, play: q);
  }

  @override
  Object get identity =>
      ('stream', _streamIdentity(catalogue, stream), play == null ? null : play!.id - stream.firstPlayId);
}

/// [highlight] in [next]: the highlight with the same key, at the same index
/// when nothing moved.
Highlight? _sameHighlight(Highlight highlight, Catalogue next) {
  final key = highlight.key;
  final highlights = next.highlights;
  if (highlight.id < highlights.length && highlights[highlight.id].key == key) return highlights[highlight.id];
  for (final h in highlights) {
    if (h.key == key) return h;
  }
  return null;
}

/// A stream whatever the catalogue: its day, and its rank among the streams
/// of that day.
(int, int) _streamIdentity(Catalogue catalogue, LiveStream stream) {
  final day = stream.date.epochDay;
  var rank = 0;
  for (var i = stream.id - 1; i >= 0 && catalogue.streams[i].date.epochDay == day; i--) {
    rank++;
  }
  return (day, rank);
}

/// [stream] of [from] in [next].
LiveStream? _sameStream(Catalogue from, LiveStream stream, Catalogue next) {
  final (day, rank) = _streamIdentity(from, stream);
  final streams = next.streams;
  if (stream.id < streams.length && _streamIdentity(next, streams[stream.id]) == (day, rank)) return streams[stream.id];
  for (var i = 0; i < streams.length; i++) {
    if (streams[i].date.epochDay == day) {
      final j = i + rank;
      return j < streams.length && streams[j].date.epochDay == day ? streams[j] : null;
    }
  }
  return null;
}

/// A play whatever the catalogue: its stream and its place in it.
(int, int, int) _playIdentity(Catalogue catalogue, Play play) {
  final stream = catalogue.streamOf(play);
  final (day, rank) = _streamIdentity(catalogue, stream);
  return (day, rank, play.id - stream.firstPlayId);
}

/// [play] of [from] in [next]: the play at the same place of the same stream,
/// if it has the same title.
Play? _samePlay(Catalogue from, Play play, Catalogue next) {
  final stream = from.streamOf(play);
  final same = _sameStream(from, stream, next);
  if (same == null) return null;
  final index = play.id - stream.firstPlayId;
  if (index >= same.playCount) return null;
  final p = next.plays[same.firstPlayId + index];
  return p.title == play.title ? p : null;
}

/// What the detail pane of [AppTab.highlights] or [AppTab.ongLog] shows, in an
/// expanded window: a stack of fiches, the one on screen last. The first one
/// is the row chosen in the list (marked as selected there); the links of a
/// fiche stack the next ones over it.
///
/// Kept per tab, whatever the window mode: leaving and re-entering expanded
/// mode finds the pane as it was.
final detailPaneProvider = NotifierProvider.family<DetailPaneNotifier, List<Fiche>, AppTab>(DetailPaneNotifier.new);

/// Holds the stack of [detailPaneProvider], always on the current catalogue.
class DetailPaneNotifier extends Notifier<List<Fiche>> {
  DetailPaneNotifier(this.tab) : assert(tab != AppTab.about);

  final AppTab tab;

  @override
  List<Fiche> build() {
    final catalogue = ref.watch(currentCatalogueProvider);
    final previous = stateOrNull ?? const <Fiche>[];
    // no catalogue (cleared): kept for when it comes back
    if (catalogue == null) return previous;
    if (previous.isNotEmpty) {
      // a refresh: each fiche on the new catalogue, up to the first one whose item is gone (no fiche ever shows
      // the items of two catalogues, nor a link to an item that is not there)
      final kept = <Fiche>[];
      for (final fiche in previous) {
        final same = fiche.translate(catalogue);
        if (same == null) break;
        kept.add(same);
      }
      if (kept.isNotEmpty) return kept;
    }
    // never empty once the catalogue is there: the first row of the list, or the newest item
    final first = _firstFiche(catalogue);
    return first == null ? const [] : [first];
  }

  Fiche? _firstFiche(Catalogue catalogue) {
    switch (tab) {
      case AppTab.highlights:
        for (final filter in [ref.read(highlightFilterProvider), const HighlightFilter()]) {
          final results = ref.read(highlightResultsProvider(filter));
          if (results != null && !results.isEmpty) {
            return HighlightFiche(catalogue, catalogue.highlights[results.ids[0]]);
          }
        }
      case AppTab.ongLog:
        for (final filter in [ref.read(playFilterProvider), const PlayFilter()]) {
          final results = ref.read(playResultsProvider(filter));
          if (results != null && !results.isEmpty) {
            final play = results[0];
            final song = catalogue.songOfPlay(play);
            return song == null
                ? StreamFiche(catalogue, catalogue.streamOf(play), play: play)
                : SongFiche(catalogue, song, play: play);
          }
        }
      case AppTab.about:
    }
    return null;
  }

  /// [fiche] on the current catalogue (it may come from a sheet opened before a refresh).
  Fiche? _current(Fiche fiche) {
    final catalogue = ref.read(currentCatalogueProvider);
    return catalogue == null ? null : fiche.translate(catalogue);
  }

  /// Shows [fiche] alone: a row chosen in the list.
  void choose(Fiche fiche) {
    final current = _current(fiche);
    if (current != null) state = [current];
  }

  /// Shows [fiche] over the current one: a link of the fiche on screen.
  void push(Fiche fiche) {
    final current = _current(fiche);
    if (current != null) state = [...state, current];
  }

  /// Goes back to the fiche under the one on screen; false when there is none.
  bool pop() {
    if (state.length < 2) return false;
    state = state.sublist(0, state.length - 1);
    return true;
  }
}

/// The highlight whose row is selected in the list (the first fiche of the
/// pane), or null.
int? selectedHighlightId(List<Fiche> stack) => switch (stack.firstOrNull) {
  HighlightFiche(:final highlight) => highlight.id,
  _ => null,
};

/// The play whose row is selected in the Ong Log, or null.
int? selectedPlayId(List<Fiche> stack) => switch (stack.firstOrNull) {
  SongFiche(:final play?) => play.id,
  _ => null,
};

/// The stream whose header is selected in the Ong Log, or null.
int? selectedStreamId(List<Fiche> stack) => switch (stack.firstOrNull) {
  StreamFiche(:final stream) => stream.id,
  _ => null,
};
