/// State of the UI shell: the selected tab and the filters of the two lists.
///
/// Kept in providers (not in the page widgets) because other places change
/// them: the "N in the Ong Log →" link and a requester tap in a sheet.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';

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
  HighlightFilter build() => const HighlightFilter();

  void setQuery(String query) => state = HighlightFilter(query: query, genre: state.genre);

  /// Selects [genre], or all genres when it is null or already selected.
  void toggleGenre(Genre? genre) =>
      state = HighlightFilter(query: state.query, genre: genre == state.genre ? null : genre);
}

/// Filters of the Ong Log list.
final playFilterProvider = NotifierProvider<PlayFilterNotifier, PlayFilter>(PlayFilterNotifier.new);

/// Holds the [PlayFilter] of the Ong Log tab.
class PlayFilterNotifier extends Notifier<PlayFilter> {
  @override
  PlayFilter build() => const PlayFilter();

  void setQuery(String query) =>
      state = PlayFilter(query: query, type: state.type, genre: state.genre, withVideo: state.withVideo);

  /// Removes every chip filter, keeps the query ("All").
  void clearChips() => state = PlayFilter(query: state.query);

  /// Selects [type], or none when it is already selected.
  void toggleType(PlayType type) => state = PlayFilter(
    query: state.query,
    type: type == state.type ? null : type,
    genre: state.genre,
    withVideo: state.withVideo,
  );

  /// Selects [genre], or none when it is already selected.
  void toggleGenre(Genre genre) => state = PlayFilter(
    query: state.query,
    type: state.type,
    genre: genre == state.genre ? null : genre,
    withVideo: state.withVideo,
  );

  void toggleWithVideo() =>
      state = PlayFilter(query: state.query, type: state.type, genre: state.genre, withVideo: !state.withVideo);

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
