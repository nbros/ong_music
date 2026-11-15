/// Riverpod state of the data files of the branch `data`: where they come from, and the VODs taken last.
///
/// `CatalogueNotifier` reads, downloads and keeps the files (see `DataFile`), and gives the VODs to
/// [vodFileProvider]; the rows and the fiches ask [vodLinksFor] for the links of their catalogue.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalogue.dart';
import '../data/data_files.dart';
import '../data/vods.dart';

// ------------------------------------------------------------ dependencies
// Overridden in tests.

/// Downloads the files of the branch `data`.
final dataFileFetcherProvider = Provider<DataFileFetcher>((ref) => HttpDataFileFetcher());

/// Keeps them (files on IO, Cache API on web).
final dataFileCacheProvider = Provider<DataFileCache>((ref) => createDataFileCache());

// ------------------------------------------------------------ state

/// The content of `vods.tsv` taken last (kept or downloaded), null until one is: then no play and no stream has a
/// VOD, and nothing shows of them.
final vodFileProvider = NotifierProvider<VodFileNotifier, VodFile?>(VodFileNotifier.new);

/// Holds the content of `vods.tsv` taken last.
class VodFileNotifier extends Notifier<VodFile?> {
  @override
  VodFile? build() => null;

  /// Takes [file] (only `CatalogueNotifier` and tests do).
  void take(VodFile file) => state = file;
}

final _links = Expando<VodLinks>('VOD links');

/// The VODs [file] gives the streams of [catalogue] (see [VodLinks]), made once per catalogue and file; null without
/// file, or without the Songs sheet.
VodLinks? vodLinksFor(Catalogue catalogue, VodFile? file) {
  if (file == null || file.isEmpty || !catalogue.hasSongs) return null;
  final made = _links[catalogue];
  if (made != null && identical(made.file, file)) return made;
  return _links[catalogue] = VodLinks(catalogue, file);
}
