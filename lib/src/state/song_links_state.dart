/// Riverpod state of the links of the songs to their originals (`song_links.tsv`, a data file: see `DataFile`).
///
/// `CatalogueNotifier` reads, downloads and keeps the file, and gives its content to [songLinksProvider]; the menus of
/// the rows and the fiches ask it for the link of a song (`SongLinks.of`, by its key).
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/song_links.dart';

/// The content of `song_links.tsv` taken last (kept or downloaded), null until one is: then no song has a link to its
/// original, and nothing shows of them.
final songLinksProvider = NotifierProvider<SongLinksNotifier, SongLinks?>(SongLinksNotifier.new);

/// Holds the content of `song_links.tsv` taken last.
class SongLinksNotifier extends Notifier<SongLinks?> {
  @override
  SongLinks? build() => null;

  /// Takes [links] (only `CatalogueNotifier` and tests do).
  void take(SongLinks links) => state = links;
}
