import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../logger.dart';
import 'thumbnail_cache.dart';

/// IO platforms: thumbnails kept in `<application cache directory>/thumbnails`.
ThumbnailImages createPlatformThumbnailImages() {
  final client = http.Client();
  final cache = ThumbnailCache(
    directory: () async => Directory(p.join((await getApplicationCacheDirectory()).path, 'thumbnails')),
    client: client,
  );
  return (image: (url) => CachedThumbnail(url, cache), dispose: client.close);
}

/// The answer of [ThumbnailCache.load] to a request whose turn came when
/// nobody wanted it any more (its rows have gone): nothing was read or
/// downloaded. Ask again once someone wants it.
final class ThumbnailNotWanted implements Exception {
  /// Creates the exception.
  const ThumbnailNotWanted();

  @override
  String toString() => 'ThumbnailNotWanted';
}

/// The bytes of a thumbnail, as [ThumbnailCache.load] gives them.
final class ThumbnailData {
  ThumbnailData._(this.bytes, {required this.fromDisk, Future<void> Function()? keep, Future<void> Function()? discard})
    : _keep = keep,
      _discard = discard;

  /// The encoded image (JPEG for YouTube).
  final Uint8List bytes;

  /// Read from the disk (else downloaded just now).
  final bool fromDisk;

  Future<void> Function()? _keep, _discard;

  /// Writes downloaded bytes to the disk, once they are known to decode: an
  /// image that does not decode is never kept. Does nothing for bytes read
  /// from the disk, after the first call, or when there is no disk.
  void keep() {
    final keep = _keep;
    _keep = null;
    if (keep != null) unawaited(keep());
  }

  /// Deletes the file these bytes were read from, because they do not decode.
  /// Does nothing for downloaded bytes or after the first call.
  void discard() {
    final discard = _discard;
    _discard = null;
    if (discard != null) unawaited(discard());
  }
}

/// The thumbnails kept in a directory: read from it without any request (also
/// offline), else downloaded, then written to it by [ThumbnailData.keep].
///
/// - **Freshness**: a file older than [maxAge] is still given at once, and
///   downloaded again in the background for the next time, at most once per
///   run for a URL; a failure leaves the old file.
/// - **Size**: beyond [maxBytes], the least recently shown files are deleted
///   down to [trimmedBytes], in a background isolate. The directory is
///   measured there at the first write of a run (a run without downloads
///   never lists it), then the size is counted in memory.
/// - **Recently shown**: the files' access time, set by the cache when it
///   reads a file whose access time is older than [touchInterval]: at most
///   one metadata write per file per day, on an IO thread; nothing is
///   written for thumbnails the memory image cache still holds, since those
///   never reach this class.
/// - **Concurrency**: one load per URL at a time (requests of the same URL
///   share it); at most [fileOperations] file operations and [downloads]
///   downloads run at once, and one refresh beside them; the others wait,
///   the newest first (the rows on screen), and one whose turn comes when
///   nobody wants it any more is dropped ([ThumbnailNotWanted]).
/// - **Failures**: never thrown for the disk, which reads as absent (the
///   directory may vanish at any moment or never be created); a failed
///   download or an HTTP status other than 200 is thrown and nothing is kept.
///   Writes go through a temporary file and a rename, so a file under its
///   final name is always complete.
final class ThumbnailCache {
  /// A cache in the directory given by [directory] (created when needed; when
  /// it throws, nothing is kept and everything is downloaded), downloading
  /// with [client].
  ThumbnailCache({
    required Future<Directory> Function() directory,
    required http.Client client,
    this.clock = DateTime.now,
    this.maxAge = const Duration(days: 30),
    this.maxBytes = 50 * 1024 * 1024,
    this.trimmedBytes = 40 * 1024 * 1024,
    this.touchInterval = const Duration(days: 1),
    this.timeout = const Duration(seconds: 30),
    int fileOperations = 4,
    int downloads = 6,
  }) : _directoryOf = directory,
       _client = client,
       _files = _Slots(fileOperations),
       _downloads = _Slots(downloads),
       _refreshes = _Slots(1);

  final Future<Directory> Function() _directoryOf;
  final http.Client _client;

  /// Refreshes have a slot of their own, one at a time: after 30 days away
  /// every file shown is old, and its refresh must not hold back the rows
  /// that wait for a download.
  final _Slots _files, _downloads, _refreshes;

  /// The time of the files: when they were downloaded (modification time) and
  /// last shown (access time).
  final DateTime Function() clock;

  /// Files older than this are downloaded again in the background.
  final Duration maxAge;

  /// The size beyond which the directory is trimmed…
  final int maxBytes;

  /// … down to this size, so that it is not trimmed at every write.
  final int trimmedBytes;

  /// The access time of a file shown is set again when it is older than this.
  final Duration touchInterval;

  /// The longest wait for a download, which holds one of the [downloads] slots.
  final Duration timeout;

  /// The file name of [url], or null when [url] is not a YouTube thumbnail
  /// (then it is only downloaded).
  ///
  /// Video ids tell upper from lower case and the file systems of Windows do
  /// not: each upper-case letter becomes `!` and its lower-case form.
  @visibleForTesting
  static String? fileName(String url) {
    final match = _thumbnailUrl.firstMatch(url);
    if (match == null) return null;
    final id = match[1]!.replaceAllMapped(_upperCase, (m) => '!${m[0]!.toLowerCase()}');
    return '$id.${match[2]}.jpg';
  }

  static final _thumbnailUrl = RegExp(r'^https://i\.ytimg\.com/vi/([A-Za-z0-9_-]{1,64})/([a-z0-9_]{1,32})\.jpg$');
  static final _upperCase = RegExp('[A-Z]');

  Future<Directory?>? _directory;

  Future<Directory?> _resolveDirectory() => _directory ??= () async {
    try {
      return await _directoryOf();
    } catch (e) {
      _warnOnce('No directory for the thumbnails: $e');
      return null;
    }
  }();

  bool _warned = false;

  /// Logs the first failure of the disk only: a full or read-only disk fails
  /// for every thumbnail.
  void _warnOnce(String message) {
    if (_warned) return;
    _warned = true;
    logger.w(message);
  }

  final _loads = <(String, bool), _Load>{};

  /// The URLs downloaded again in this run because their file was old.
  final _refreshed = <String>{};

  /// The thumbnail at [url]: from its file when there is one (unless
  /// [skipDisk]), else downloaded. Requests of the same URL made while one is
  /// running share it.
  ///
  /// [wanted] is asked when a request that had to wait gets its turn: when
  /// it and every request sharing the load say no, it throws
  /// [ThumbnailNotWanted] without any request. Throws the error of a failed
  /// download.
  Future<ThumbnailData> load(String url, {bool Function()? wanted, bool skipDisk = false}) {
    final key = (url, skipDisk);
    final running = _loads[key];
    if (running != null) {
      running.wanted.add(wanted);
      return running.result;
    }
    final load = _Load(wanted);
    _loads[key] = load;
    return load.result = _load(url, skipDisk, load.isWanted).whenComplete(() {
      if (identical(_loads[key], load)) _loads.remove(key);
    });
  }

  Future<ThumbnailData> _load(String url, bool skipDisk, bool Function() wanted) async {
    final file = await _fileOf(url);
    if (file != null && !skipDisk) {
      final found = await _files.run(() => _read(file), wanted: wanted);
      if (found != null) {
        final (bytes, stat) = found;
        _shown(url, file, stat);
        return ThumbnailData._(bytes, fromDisk: true, discard: () => _delete(file));
      }
    }
    final bytes = await _downloads.run(() => _download(url), wanted: wanted);
    return ThumbnailData._(bytes, fromDisk: false, keep: file == null ? null : () => _store(file, bytes));
  }

  Future<File?> _fileOf(String url) async {
    final name = fileName(url);
    if (name == null) return null;
    final directory = await _resolveDirectory();
    return directory == null ? null : File(p.join(directory.path, name));
  }

  /// The content and the times of [file], or null when it cannot be read.
  static Future<(Uint8List, FileStat)?> _read(File file) async {
    try {
      final stat = await file.stat();
      if (stat.type != FileSystemEntityType.file || stat.size == 0) return null;
      final bytes = await file.readAsBytes();
      return bytes.isEmpty ? null : (bytes, stat);
    } catch (_) {
      return null; // gone between the two, or unreadable: download it
    }
  }

  /// Records that [file] was shown, and downloads it again when it is old.
  void _shown(String url, File file, FileStat stat) {
    final now = clock();
    if (now.difference(stat.accessed) > touchInterval) {
      _background(
        _files.run(() async {
          try {
            await file.setLastAccessed(now);
          } catch (_) {
            // gone: nothing to record
          }
        }),
      );
    }
    if (now.difference(stat.modified) > maxAge && _refreshed.add(url)) {
      _background(() async {
        try {
          final bytes = await _refreshes.run(() => _download(url, imageOnly: true));
          await _store(file, bytes);
        } catch (_) {
          // offline, or the video is gone: keep the old file
        }
      }());
    }
  }

  /// Downloads [url] as [NetworkImage] does (only a status 200 with a body
  /// counts). [imageOnly] also asks for an image content type, for the
  /// downloads that nobody decodes before they are kept (a captive portal
  /// answers 200 with a page of its own).
  Future<Uint8List> _download(String url, {bool imageOnly = false}) async {
    final uri = Uri.parse(url);
    // Past [timeout] the request is aborted, so that it does not go on in the
    // background once its slot is given to another.
    final abort = Completer<void>();
    final response =
        await () async {
          final request = http.AbortableRequest('GET', uri, abortTrigger: abort.future);
          return http.Response.fromStream(await _client.send(request));
        }().timeout(
          timeout,
          onTimeout: () {
            abort.complete();
            throw TimeoutException('The thumbnail took too long: $url', timeout);
          },
        );
    if (response.statusCode != HttpStatus.ok) {
      throw NetworkImageLoadException(statusCode: response.statusCode, uri: uri);
    }
    if (response.bodyBytes.isEmpty) throw Exception('The thumbnail is an empty file: $url');
    if (imageOnly && !(response.headers['content-type'] ?? '').startsWith('image/')) {
      throw Exception('The thumbnail is not an image: $url');
    }
    return response.bodyBytes;
  }

  /// Makes the temporary file names unique within the process.
  static int _temporaryFiles = 0;

  /// Writes [bytes] to [file] through a temporary file of this write only and
  /// a rename, so that an interrupted write never leaves a partial file under
  /// the final name, and two writes never write into the same file. Sets both
  /// times to [clock]: downloaded and shown now.
  Future<void> _store(File file, Uint8List bytes) => _background(
    _files.run(() async {
      final temporary = File('${file.path}.$pid-${_temporaryFiles++}.tmp');
      try {
        await file.parent.create(recursive: true);
        await temporary.writeAsBytes(bytes, flush: true);
        final now = clock();
        await temporary.setLastModified(now);
        await temporary.setLastAccessed(now);
        await temporary.rename(file.path);
      } catch (e) {
        _warnOnce('Cannot keep a thumbnail: $e');
        try {
          await temporary.delete();
        } catch (_) {
          // never created
        }
        return;
      }
      _wrote(bytes.length);
    }),
  );

  Future<void> _delete(File file) => _background(
    _files.run(() async {
      try {
        await file.delete();
      } catch (_) {
        // already gone
      }
    }),
  );

  /// The size of the directory as last measured, plus what was written since;
  /// null before the first measure of the run.
  int? _bytes;

  /// The trim running, if any.
  Future<void>? _trimming;

  /// What was written while [_trimming] ran.
  int _writtenWhileTrimming = 0;

  void _wrote(int length) {
    if (_trimming != null) {
      _writtenWhileTrimming += length;
      return;
    }
    final bytes = _bytes;
    if (bytes != null) {
      _bytes = bytes + length;
      if (_bytes! <= maxBytes) return;
    }
    _trim();
  }

  /// Measures the directory, and trims it when it is beyond [maxBytes], in a
  /// background isolate: the listing and the deletions never run on the
  /// isolate of the UI.
  void _trim() {
    _writtenWhileTrimming = 0;
    final trimming = () async {
      final directory = await _resolveDirectory();
      if (directory == null) return;
      try {
        _bytes = await _trimInIsolate(directory.path, maxBytes, trimmedBytes, clock());
      } catch (_) {
        _bytes = 0; // no isolate: measure again after maxBytes more
      }
    }();
    _trimming = trimming;
    _background(
      trimming.whenComplete(() {
        _trimming = null;
        final written = _writtenWhileTrimming;
        _bytes = (_bytes ?? 0) + written;
        if (written > 0 && _bytes! > maxBytes) _trim();
      }),
    );
  }

  /// Static, so that the closure sent to the isolate holds its arguments only.
  static Future<int> _trimInIsolate(String path, int maxBytes, int trimmedBytes, DateTime now) =>
      Isolate.run(() => trimThumbnailDirectory(path, maxBytes: maxBytes, trimmedBytes: trimmedBytes, now: now));

  final _pending = <Future<void>>{};

  Future<void> _background(Future<void> work) {
    _pending.add(work);
    return work.whenComplete(() => _pending.remove(work));
  }

  /// Completes when the writes, deletions, refreshes and trims started so far
  /// (and those they start) are done.
  @visibleForTesting
  Future<void> get settled async {
    while (_pending.isNotEmpty) {
      await Future.wait(_pending.toList(), eagerError: false).catchError((_) => <void>[]);
    }
  }
}

/// A temporary file older than this belongs to no write still running.
const Duration _temporaryFileMaxAge = Duration(minutes: 10);

/// Measures the directory at [path] and, when it holds more than [maxBytes],
/// deletes the files shown least recently (access time, then modification
/// time) until it holds [trimmedBytes] at most; also deletes the temporary
/// files of writes that never finished (the app was killed in the middle).
/// Returns the size left. Synchronous: it runs in a background isolate.
@visibleForTesting
int trimThumbnailDirectory(String path, {required int maxBytes, required int trimmedBytes, required DateTime now}) {
  final files = <(File, FileStat)>[];
  var total = 0;
  try {
    for (final entry in Directory(path).listSync(followLinks: false)) {
      if (entry is! File) continue;
      try {
        final stat = entry.statSync();
        if (entry.path.endsWith('.tmp')) {
          if (now.difference(stat.modified) > _temporaryFileMaxAge) entry.deleteSync();
          continue;
        }
        files.add((entry, stat));
        total += stat.size;
      } catch (_) {
        // gone in the meantime
      }
    }
  } catch (_) {
    return total; // no directory: nothing to trim
  }
  if (total <= maxBytes) return total;
  files.sort((a, b) {
    final accessed = a.$2.accessed.compareTo(b.$2.accessed);
    return accessed != 0 ? accessed : a.$2.modified.compareTo(b.$2.modified);
  });
  for (final (file, stat) in files) {
    if (total <= trimmedBytes) break;
    try {
      file.deleteSync();
      total -= stat.size;
    } catch (_) {
      // gone already, or held open (Windows): try the next one
    }
  }
  return total;
}

/// The requests sharing one load.
final class _Load {
  _Load(bool Function()? wanted) : wanted = [wanted];

  /// The answers of each request; null for one that is always wanted.
  final List<bool Function()?> wanted;

  late Future<ThumbnailData> result;

  bool isWanted() => wanted.any((wanted) => wanted == null || wanted());
}

/// At most [size] tasks at once; the others wait, the newest first.
final class _Slots {
  _Slots(this.size) : assert(size > 0);

  final int size;
  int _running = 0;
  final _waiting = <(Completer<void>, bool Function()?)>[];

  /// Runs [task] when a slot is free. A task that had to wait and is not
  /// [wanted] any more when its turn comes is not run: [ThumbnailNotWanted].
  Future<T> run<T>(Future<T> Function() task, {bool Function()? wanted}) async {
    if (_running < size) {
      _running++;
    } else {
      final turn = Completer<void>();
      _waiting.add((turn, wanted));
      await turn.future; // the slot is handed over by _release
    }
    try {
      return await task();
    } finally {
      _release();
    }
  }

  void _release() {
    while (_waiting.isNotEmpty) {
      final (turn, wanted) = _waiting.removeLast();
      if (wanted == null || wanted()) {
        turn.complete();
        return;
      }
      turn.completeError(const ThumbnailNotWanted());
    }
    _running--;
  }
}

/// A thumbnail kept by [cache]: the same pixels as a [NetworkImage] of [url]
/// (decoded by the decoder it is given, [ResizeImage]'s at the display size),
/// read from the disk when it is there.
///
/// Two of them are equal for the same [url] and [cache], so that Flutter's
/// image cache keeps one decoded image per URL and size, as for
/// [NetworkImage].
@immutable
final class CachedThumbnail extends ImageProvider<CachedThumbnail> {
  /// The thumbnail at [url], kept by [cache].
  const CachedThumbnail(this.url, this.cache);

  /// The address of the image.
  final String url;

  /// Where it is kept.
  final ThumbnailCache cache;

  @override
  Future<CachedThumbnail> obtainKey(ImageConfiguration configuration) => SynchronousFuture<CachedThumbnail>(this);

  @override
  ImageStreamCompleter loadImage(CachedThumbnail key, ImageDecoderCallback decode) {
    final codec = Completer<ui.Codec>();
    final completer = _ThumbnailCompleter(
      codec: codec.future,
      scale: 1,
      debugLabel: url,
      informationCollector: () => <DiagnosticsNode>[
        DiagnosticsProperty<ImageProvider>('Image provider', this),
        DiagnosticsProperty<CachedThumbnail>('Image key', key),
      ],
    );
    codec.complete(_load(completer, decode));
    return completer;
  }

  Future<ui.Codec> _load(_ThumbnailCompleter completer, ImageDecoderCallback decode) async {
    // A file that does not decode is downloaded again, once: the download
    // replaces it, and it is deleted only when that fails too (never both: a
    // deletion still waiting could run after the write and delete the new file).
    ThumbnailData? corrupt;
    try {
      while (true) {
        final data = await _fetch(completer, skipDisk: corrupt != null);
        try {
          final codec = await _decode(data.bytes, decode);
          data.keep();
          return codec;
        } catch (_) {
          if (!data.fromDisk) rethrow;
          corrupt = data;
        }
      }
    } catch (_) {
      corrupt?.discard();
      rethrow;
    }
  }

  /// Loads the bytes; when the request is dropped because nobody shows the
  /// image any more, waits until someone does and asks again.
  Future<ThumbnailData> _fetch(_ThumbnailCompleter completer, {required bool skipDisk}) async {
    while (true) {
      try {
        return await cache.load(url, wanted: () => completer.wanted, skipDisk: skipDisk);
      } on ThumbnailNotWanted {
        if (!completer.wanted) await completer.nextListener;
      }
    }
  }

  /// Decodes [bytes] and their first frame, so that a file that is not an
  /// image fails here, where it can be deleted and downloaded again, rather
  /// than in the completer.
  static Future<ui.Codec> _decode(Uint8List bytes, ImageDecoderCallback decode) async {
    final codec = await decode(await ui.ImmutableBuffer.fromUint8List(bytes));
    try {
      return _FirstFrameDecoded(codec, await codec.getNextFrame());
    } catch (_) {
      codec.dispose();
      rethrow;
    }
  }

  @override
  bool operator ==(Object other) => other is CachedThumbnail && other.url == url && identical(other.cache, cache);

  @override
  int get hashCode => Object.hash(url, identityHashCode(cache));

  @override
  String toString() => '${objectRuntimeType(this, 'CachedThumbnail')}("$url")';
}

/// A codec whose first frame is already decoded.
final class _FirstFrameDecoded implements ui.Codec {
  _FirstFrameDecoded(this._codec, ui.FrameInfo first) : _first = first;

  final ui.Codec _codec;
  ui.FrameInfo? _first;

  @override
  int get frameCount => _codec.frameCount;

  @override
  int get repetitionCount => _codec.repetitionCount;

  @override
  Future<ui.FrameInfo> getNextFrame() {
    final first = _first;
    _first = null;
    return first != null ? Future.value(first) : _codec.getNextFrame();
  }

  @override
  void dispose() {
    _first?.image.dispose();
    _first = null;
    _codec.dispose();
  }
}

/// The completer of a [CachedThumbnail], which tells whether anyone but
/// Flutter's image cache listens to it: whether a row still shows it.
///
/// The image cache adds a listener of its own to a completer it has just
/// created ([ImageCache.putIfAbsent], before it returns it to the image
/// stream) and keeps it until the image is loaded: that first listener is
/// not counted. The tests check this order through real rows.
final class _ThumbnailCompleter extends MultiFrameImageStreamCompleter {
  _ThumbnailCompleter({required super.codec, required super.scale, super.debugLabel, super.informationCollector});

  bool _cacheListenerExpected = true;
  ImageStreamListener? _cacheListener;
  final _others = <ImageStreamListener>[];
  Completer<void>? _listened;

  /// Someone but the image cache listens.
  bool get wanted => _others.isNotEmpty;

  /// Completes when someone but the image cache starts listening.
  Future<void> get nextListener => (_listened ??= Completer<void>()).future;

  @override
  void addListener(ImageStreamListener listener) {
    if (_cacheListenerExpected) {
      _cacheListenerExpected = false;
      _cacheListener = listener;
    } else {
      _others.add(listener);
      final listened = _listened;
      _listened = null;
      listened?.complete();
    }
    super.addListener(listener);
  }

  @override
  void removeListener(ImageStreamListener listener) {
    if (identical(listener, _cacheListener)) {
      _cacheListener = null;
    } else {
      _others.remove(listener);
    }
    super.removeListener(listener);
  }
}
