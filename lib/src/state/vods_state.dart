/// Riverpod state of the data files of the branch `data`: where they come from, and the VODs and their offsets taken
/// last.
///
/// `CatalogueNotifier` reads, downloads and keeps the files (see `DataFile`), and gives the VODs to
/// [vodFileProvider], their offsets to [vodOffsetsProvider]; the rows and the fiches ask [vodLinksFor] for the links
/// of their catalogue.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/catalogue.dart';
import '../data/data_files.dart';
import '../data/vod_offsets.dart';
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

/// The content of `offsets.tsv` taken last (kept or downloaded), null until one is, or while the file does not
/// exist: then the plays are at their uptime in the VODs.
final vodOffsetsProvider = NotifierProvider<VodOffsetsNotifier, OffsetFile?>(VodOffsetsNotifier.new);

/// Holds the content of `offsets.tsv` taken last.
class VodOffsetsNotifier extends Notifier<OffsetFile?> {
  @override
  OffsetFile? build() => null;

  /// Takes [file] (only `CatalogueNotifier` and tests do).
  void take(OffsetFile file) => state = file;
}

final _links = Expando<VodLinks>('VOD links');

/// The VODs [file] gives the streams of [catalogue] with the offsets of [offsets] (see [VodLinks]), made once per
/// catalogue and files; null without [file], or without the Songs sheet. Without [offsets], the plays are at their
/// uptime.
VodLinks? vodLinksFor(Catalogue catalogue, VodFile? file, OffsetFile? offsets) {
  if (file == null || file.isEmpty || !catalogue.hasSongs) return null;
  final made = _links[catalogue];
  final wanted = offsets ?? OffsetFile.empty;
  if (made != null && identical(made.file, file) && identical(made.offsets, wanted)) return made;
  return _links[catalogue] = VodLinks(catalogue, file, wanted);
}
