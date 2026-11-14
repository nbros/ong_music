import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ong_music/src/data/thumbnail_cache_io.dart';
import 'package:ong_music/src/ui/theme.dart';
import 'package:ong_music/src/ui/widgets.dart';
import 'package:path/path.dart' as p;

import 'ui_harness.dart' show transparentPng;

/// YouTube, as the cache sees it: every request is logged; each URL answers
/// 200 with an image of its own unless [answers] says otherwise; [gates]
/// hold answers back; [offline] fails every request.
class FakeYouTube {
  final requests = <String>[];
  final answers = <String, http.Response Function()>{};
  final gates = <String, Completer<void>>{};
  bool offline = false;

  /// The version of the images served, to tell a download again from the first.
  int version = 1;

  static List<int> imageOf(String url, int version) => utf8.encode('image of $url, version $version');

  late final client = MockClient((request) async {
    final url = request.url.toString();
    requests.add(url);
    await gates[url]?.future;
    if (offline) throw http.ClientException('offline', request.url);
    final answer = answers[url];
    if (answer != null) return answer();
    return http.Response.bytes(imageOf(url, version), 200, headers: {'content-type': 'image/jpeg'});
  });
}

String urlOf(String id, [String variant = 'mqdefault']) => 'https://i.ytimg.com/vi/$id/$variant.jpg';

void main() {
  late Directory tmp;
  late Directory dir;
  late FakeYouTube youtube;
  late DateTime now;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('ong_thumbnails_test');
    dir = Directory(p.join(tmp.path, 'thumbnails'));
    youtube = FakeYouTube();
    now = DateTime(2026, 11, 14, 12);
  });
  tearDown(() {
    // a write of the test's last image may still be running: try again
    for (var i = 0; i < 5 && tmp.existsSync(); i++) {
      try {
        tmp.deleteSync(recursive: true);
      } on FileSystemException {
        sleep(const Duration(milliseconds: 20));
      }
    }
  });

  ThumbnailCache cacheOf({
    Future<Directory> Function()? directory,
    int maxBytes = 50 * 1024 * 1024,
    int trimmedBytes = 40 * 1024 * 1024,
    int downloads = 6,
    Duration timeout = const Duration(seconds: 30),
  }) => ThumbnailCache(
    directory: directory ?? () async => dir,
    client: youtube.client,
    clock: () => now,
    maxBytes: maxBytes,
    trimmedBytes: trimmedBytes,
    downloads: downloads,
    timeout: timeout,
  );

  File fileOf(String url) => File(p.join(dir.path, ThumbnailCache.fileName(url)!));

  /// A file on disk for [url], downloaded [age] ago and last shown [shown] ago.
  File seed(String url, List<int> bytes, {Duration age = Duration.zero, Duration? shown}) {
    final file = fileOf(url)..parent.createSync(recursive: true);
    file.writeAsBytesSync(bytes);
    file.setLastModifiedSync(now.subtract(age));
    file.setLastAccessedSync(now.subtract(shown ?? age));
    return file;
  }

  group('ThumbnailCache', () {
    test('file names tell upper from lower case without relying on the file system', () {
      expect(ThumbnailCache.fileName(urlOf('dQw4w9WgXcQ')), 'd!qw4w9!wg!xc!q.mqdefault.jpg');
      expect(ThumbnailCache.fileName(urlOf('abc-_9', 'hqdefault')), 'abc-_9.hqdefault.jpg');
      expect(ThumbnailCache.fileName(urlOf('ABC')), isNot(ThumbnailCache.fileName(urlOf('abc'))));
      // anything else is only downloaded
      expect(ThumbnailCache.fileName('https://example.com/vi/abc/mqdefault.jpg'), isNull);
      expect(ThumbnailCache.fileName(urlOf('../x')), isNull);
    });

    test('a miss is downloaded, kept once it decodes, then read from the disk', () async {
      final cache = cacheOf();
      final url = urlOf('miss');
      final first = await cache.load(url);
      expect(first.fromDisk, false);
      expect(first.bytes, FakeYouTube.imageOf(url, 1));
      await cache.settled;
      expect(fileOf(url).existsSync(), isFalse, reason: 'nothing is kept before it is known to decode');
      first.keep();
      await cache.settled;
      expect(fileOf(url).readAsBytesSync(), FakeYouTube.imageOf(url, 1));
      expect(fileOf(url).lastModifiedSync(), now);

      youtube.version = 2;
      final second = await cache.load(url);
      expect(second.fromDisk, true);
      expect(second.bytes, FakeYouTube.imageOf(url, 1));
      expect(youtube.requests, [url]);
    });

    test('a file on the disk is read without any request, also offline', () async {
      final url = urlOf('offline');
      seed(url, [1, 2, 3], age: const Duration(days: 3));
      youtube.offline = true;
      final data = await cacheOf().load(url);
      expect(data.fromDisk, true);
      expect(data.bytes, [1, 2, 3]);
      expect(youtube.requests, isEmpty);
    });

    test('an old file is given at once and downloaded again for the next time, once per run', () async {
      final cache = cacheOf();
      final url = urlOf('old');
      seed(url, [1], age: const Duration(days: 31));
      final data = await cache.load(url);
      expect(data.fromDisk, true);
      expect(data.bytes, [1]);
      await cache.settled;
      expect(youtube.requests, [url]);
      expect(fileOf(url).readAsBytesSync(), FakeYouTube.imageOf(url, 1));
      expect(fileOf(url).lastModifiedSync(), now);

      // old again (the clock moved on): not downloaded again in this run
      fileOf(url).setLastModifiedSync(now.subtract(const Duration(days: 40)));
      await cache.load(url);
      await cache.settled;
      expect(youtube.requests, [url]);

      // a file younger than 30 days is not downloaded again
      final young = urlOf('young');
      seed(young, [2], age: const Duration(days: 29));
      await cache.load(young);
      await cache.settled;
      expect(youtube.requests, [url]);
    });

    test('a failed refresh keeps the old file', () async {
      final cache = cacheOf();
      final gone = urlOf('gone'), offline = urlOf('offline'), portal = urlOf('portal');
      for (final url in [gone, offline, portal]) {
        seed(url, [7], age: const Duration(days: 60));
      }
      youtube.answers[gone] = () => http.Response('', 404);
      youtube.answers[portal] = () => http.Response('<html>log in</html>', 200, headers: {'content-type': 'text/html'});
      for (final url in [gone, portal]) {
        expect((await cache.load(url)).bytes, [7]);
      }
      await cache.settled;
      youtube.offline = true;
      expect((await cache.load(offline)).bytes, [7]);
      await cache.settled;
      expect(youtube.requests, unorderedEquals([gone, portal, offline]));
      for (final url in [gone, offline, portal]) {
        expect(fileOf(url).readAsBytesSync(), [7]);
      }
    });

    test('a file shown is recorded as shown, at most once a day', () async {
      final cache = cacheOf();
      final url = urlOf('shown');
      final file = seed(url, [1], age: const Duration(days: 3));
      await cache.load(url);
      await cache.settled;
      expect(file.lastAccessedSync(), now);
      expect(file.lastModifiedSync(), now.subtract(const Duration(days: 3)), reason: 'still as old');

      final recent = urlOf('recent');
      final shownAt = now.subtract(const Duration(hours: 20));
      final recentFile = seed(recent, [1], age: const Duration(days: 3), shown: const Duration(hours: 20));
      await cache.load(recent);
      await cache.settled;
      expect(recentFile.lastAccessedSync(), shownAt, reason: 'no write for a file shown less than a day ago');
    });

    test('beyond the limit, the least recently shown files go first, down to the margin', () async {
      final cache = cacheOf(maxBytes: 1000, trimmedBytes: 600);
      final a = urlOf('a'), b = urlOf('b'), c = urlOf('c'), d = urlOf('d'), e = urlOf('e');
      seed(a, List.filled(200, 0), age: const Duration(days: 9), shown: const Duration(days: 8));
      seed(b, List.filled(200, 0), age: const Duration(days: 9), shown: const Duration(days: 6));
      seed(c, List.filled(200, 0), age: const Duration(days: 9), shown: const Duration(days: 7));
      seed(d, List.filled(200, 0), age: const Duration(days: 9), shown: const Duration(days: 5));
      // c shown now: it becomes the most recently shown of the four
      await cache.load(c);
      await cache.settled;
      youtube.answers[e] = () => http.Response.bytes(List.filled(300, 1), 200);
      (await cache.load(e)).keep(); // 1100 bytes
      await cache.settled;
      final left = dir.listSync().map((f) => p.basename(f.path)).toSet();
      expect(left, {ThumbnailCache.fileName(c), ThumbnailCache.fileName(e)});
    });

    test('below the limit nothing is deleted, and the size is counted between writes', () async {
      final cache = cacheOf(maxBytes: 1000, trimmedBytes: 600);
      final old = urlOf('old');
      seed(old, List.filled(400, 0), age: const Duration(days: 9));
      for (final id in ['x', 'y']) {
        youtube.answers[urlOf(id)] = () => http.Response.bytes(List.filled(250, 1), 200);
        (await cache.load(urlOf(id))).keep();
        await cache.settled;
      }
      expect(dir.listSync(), hasLength(3), reason: '900 bytes');
      // the third write passes the limit without listing the directory again
      youtube.answers[urlOf('z')] = () => http.Response.bytes(List.filled(250, 1), 200);
      (await cache.load(urlOf('z'))).keep();
      await cache.settled;
      expect(fileOf(old).existsSync(), isFalse);
      expect(dir.listSync(), hasLength(2));
    });

    test('a download that takes too long fails, and gives its slot to the next one', () async {
      final cache = cacheOf(downloads: 1, timeout: const Duration(milliseconds: 50));
      final slow = urlOf('slow'), next = urlOf('next');
      youtube.gates[slow] = Completer<void>();
      final first = cache.load(slow);
      final second = cache.load(next);
      await expectLater(first, throwsA(isA<TimeoutException>()));
      expect((await second).bytes, FakeYouTube.imageOf(next, 1));
      youtube.gates[slow]!.complete();
      await cache.settled;
      expect(dir.existsSync() ? dir.listSync() : const <FileSystemEntity>[], isEmpty, reason: 'nothing kept');
    });

    test('an interrupted write is never read, and its temporary file goes later', () async {
      final cache = cacheOf();
      final url = urlOf('interrupted');
      dir.createSync(recursive: true);
      final stale = File('${fileOf(url).path}.123-0.tmp')..writeAsBytesSync([1, 2]);
      stale.setLastModifiedSync(now.subtract(const Duration(hours: 1)));
      final running = File('${fileOf(urlOf('other')).path}.456-0.tmp')..writeAsBytesSync([3]);
      running.setLastModifiedSync(now.subtract(const Duration(minutes: 1)));

      final data = await cache.load(url);
      expect(data.fromDisk, false);
      expect(data.bytes, FakeYouTube.imageOf(url, 1));
      data.keep();
      await cache.settled;
      expect(stale.existsSync(), isFalse);
      expect(running.existsSync(), isTrue, reason: 'may belong to a write still running');
      expect(fileOf(url).readAsBytesSync(), FakeYouTube.imageOf(url, 1));
    });

    test('a write that fails leaves no file and throws nowhere', () async {
      // the directory cannot be created: a file is in its way
      File(dir.path).writeAsStringSync('in the way');
      final cache = cacheOf();
      final url = urlOf('blocked');
      final data = await cache.load(url);
      data.keep();
      await cache.settled;
      expect(File(dir.path).readAsStringSync(), 'in the way');
      expect(tmp.listSync(), hasLength(1));
      await cache.load(url);
      expect(youtube.requests, [url, url]);
    });

    test('the directory may vanish at any moment', () async {
      final cache = cacheOf();
      final url = urlOf('vanish');
      (await cache.load(url)).keep();
      await cache.settled;
      dir.deleteSync(recursive: true);
      final data = await cache.load(url);
      expect(data.fromDisk, isFalse);
      data.keep();
      await cache.settled;
      expect(fileOf(url).existsSync(), isTrue, reason: 'made again');
      expect(youtube.requests, [url, url]);
    });

    test('without a directory, everything is downloaded', () async {
      final cache = cacheOf(directory: () async => throw const FileSystemException('no cache directory'));
      final url = urlOf('nowhere');
      for (var i = 0; i < 2; i++) {
        final data = await cache.load(url);
        expect(data.fromDisk, isFalse);
        data.keep();
        await cache.settled;
      }
      expect(youtube.requests, [url, url]);
      expect(tmp.listSync(), isEmpty);
    });

    test('two requests for one URL download it once', () async {
      final cache = cacheOf();
      final url = urlOf('twice');
      youtube.gates[url] = Completer<void>();
      final first = cache.load(url), second = cache.load(url);
      await pumpEventQueue();
      youtube.gates[url]!.complete();
      final both = await Future.wait([first, second]);
      expect(identical(both[0], both[1]), isTrue);
      expect(youtube.requests, [url]);
    });

    test('an HTTP error is thrown and nothing is kept', () async {
      final cache = cacheOf();
      final url = urlOf('deleted');
      youtube.answers[url] = () => http.Response('', 404);
      await expectLater(cache.load(url), throwsA(isA<NetworkImageLoadException>()));
      await cache.settled;
      expect(dir.existsSync() && dir.listSync().isNotEmpty, isFalse);
      await expectLater(cache.load(url), throwsA(isA<NetworkImageLoadException>()));
      expect(youtube.requests, [url, url], reason: 'asked again');
    });

    test('requests wait for a slot, the newest first; one nobody wants any more is dropped', () async {
      // no disk: the order of the requests is not left to the file system
      final cache = cacheOf(downloads: 1, directory: () async => throw const FileSystemException('none'));
      final first = urlOf('first'), gone = urlOf('gone'), older = urlOf('older'), newer = urlOf('newer');
      youtube.gates[first] = Completer<void>();
      final loads = [
        cache.load(first),
        cache.load(gone, wanted: () => false),
        cache.load(older, wanted: () => true),
        cache.load(newer),
      ];
      await pumpEventQueue();
      expect(youtube.requests, [first]);
      youtube.gates[first]!.complete();
      final results = await Future.wait([for (final load in loads) load.then((_) => 'ok', onError: (e) => '$e')]);
      expect(results, ['ok', 'ThumbnailNotWanted', 'ok', 'ok']);
      expect(youtube.requests, [first, newer, older]);
    });

    test('a refresh never holds back the download of a row', () async {
      final cache = cacheOf(downloads: 1);
      final old = urlOf('old'), miss = urlOf('miss');
      seed(old, [1], age: const Duration(days: 31));
      youtube.gates[old] = Completer<void>();
      await cache.load(old);
      await pumpEventQueue();
      expect(youtube.requests, [old]);
      expect((await cache.load(miss)).fromDisk, isFalse);
      expect(youtube.requests, [old, miss]);
      youtube.gates[old]!.complete();
      await cache.settled;
    });

    test('discard deletes the file', () async {
      final cache = cacheOf();
      final url = urlOf('corrupt');
      seed(url, [0xFF], age: const Duration(days: 1));
      final data = await cache.load(url);
      data.discard();
      await cache.settled;
      expect(fileOf(url).existsSync(), isFalse);
    });
  });

  group('trimThumbnailDirectory', () {
    test('without a directory, there is nothing to trim', () {
      expect(trimThumbnailDirectory(dir.path, maxBytes: 10, trimmedBytes: 5, now: now), 0);
    });
  });

  group('CachedThumbnail', () {
    Widget appOf(Widget child, ThumbnailCache cache) => ProviderScope(
      overrides: [thumbnailImageProvider.overrideWithValue((url) => CachedThumbnail(url, cache))],
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Center(child: child),
      ),
    );

    bool shownImage(WidgetTester tester, String id) {
      final image = find.descendant(of: find.byKey(ValueKey(id)), matching: find.byType(RawImage));
      return image.evaluate().isNotEmpty && tester.widget<RawImage>(image).image != null;
    }

    bool shownError(String id) =>
        find.descendant(of: find.byKey(ValueKey(id)), matching: find.byIcon(Icons.video_library)).evaluate().isNotEmpty;

    /// Lets the files, the fake network, the decoder and the isolates work.
    ///
    /// Their futures belong to the test's fake zone: they move on between the
    /// pumps, not inside [WidgetTester.runAsync].
    ///
    /// Stops early once [until] holds (it may take long on a busy machine).
    Future<void> settle(WidgetTester tester, {bool Function()? until}) async {
      for (var i = 0; i < (until == null ? 20 : 300); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump(const Duration(milliseconds: 50));
        if (i >= 5 && (until?.call() ?? false)) break;
      }
    }

    bool keeps(String url, List<int> bytes) =>
        fileOf(url).existsSync() && listEquals(fileOf(url).readAsBytesSync(), bytes);

    Widget thumbnail(String id) => Thumbnail(key: ValueKey(id), youtubeId: id, width: 160);

    testWidgets('equal for the same URL and cache, as Flutter\'s image cache needs', (tester) async {
      final cache = cacheOf(), other = cacheOf();
      expect(CachedThumbnail(urlOf('a'), cache), CachedThumbnail(urlOf('a'), cache));
      expect(CachedThumbnail(urlOf('a'), cache).hashCode, CachedThumbnail(urlOf('a'), cache).hashCode);
      expect(CachedThumbnail(urlOf('a'), cache), isNot(CachedThumbnail(urlOf('b'), cache)));
      expect(CachedThumbnail(urlOf('a'), cache), isNot(CachedThumbnail(urlOf('a'), other)));
    });

    testWidgets('a thumbnail on the disk is shown from it, with the fade, without any request', (tester) async {
      final cache = cacheOf();
      seed(urlOf('disk'), transparentPng, age: const Duration(days: 2));
      youtube.offline = true;
      await tester.pumpWidget(appOf(thumbnail('disk'), cache));
      expect(find.byType(AnimatedOpacity), findsOneWidget, reason: 'not loaded synchronously');
      await settle(tester, until: () => shownImage(tester, 'disk'));
      expect(shownImage(tester, 'disk'), isTrue);
      expect(youtube.requests, isEmpty);
    });

    testWidgets('a miss is downloaded, shown and kept', (tester) async {
      final cache = cacheOf();
      final url = urlOf('miss');
      youtube.answers[url] = () => http.Response.bytes(transparentPng, 200);
      await tester.pumpWidget(appOf(thumbnail('miss'), cache));
      await settle(tester, until: () => shownImage(tester, 'miss') && keeps(url, transparentPng));
      expect(shownImage(tester, 'miss'), isTrue);
      expect(fileOf(url).readAsBytesSync(), transparentPng);
    });

    testWidgets('a file that does not decode is deleted and downloaded again', (tester) async {
      final cache = cacheOf();
      final url = urlOf('corrupt');
      // a sound header: the codec is made, its frame fails
      final idat = 33 + 8;
      seed(url, Uint8List.fromList(transparentPng)..[idat] ^= 0xFF, age: const Duration(days: 2));
      youtube.answers[url] = () => http.Response.bytes(transparentPng, 200);
      await tester.pumpWidget(appOf(thumbnail('corrupt'), cache));
      await settle(tester, until: () => shownImage(tester, 'corrupt') && keeps(url, transparentPng));
      expect(shownImage(tester, 'corrupt'), isTrue);
      expect(youtube.requests, [url]);
      expect(fileOf(url).readAsBytesSync(), transparentPng);
    });

    testWidgets('bytes that never decode show the error icon and are not kept', (tester) async {
      final cache = cacheOf();
      final url = urlOf('garbage');
      seed(url, [1, 2, 3], age: const Duration(days: 2));
      await tester.pumpWidget(appOf(thumbnail('garbage'), cache));
      await settle(tester, until: () => shownError('garbage'));
      expect(shownError('garbage'), isTrue);
      expect(youtube.requests, [url], reason: 'downloaded again once, not more');
      expect(fileOf(url).existsSync(), isFalse);
    });

    testWidgets('a download that does not decode shows the error icon, once, and is not kept', (tester) async {
      final cache = cacheOf();
      final url = urlOf('broken');
      await tester.pumpWidget(appOf(thumbnail('broken'), cache));
      await settle(tester, until: () => shownError('broken'));
      expect(shownError('broken'), isTrue);
      expect(youtube.requests, [url]);
      expect(dir.existsSync() && dir.listSync().isNotEmpty, isFalse);
    });

    testWidgets('an HTTP error shows the error icon', (tester) async {
      final cache = cacheOf();
      youtube.answers[urlOf('deleted')] = () => http.Response('', 404);
      await tester.pumpWidget(appOf(thumbnail('deleted'), cache));
      await settle(tester, until: () => shownError('deleted'));
      expect(shownError('deleted'), isTrue);
      expect(dir.existsSync() && dir.listSync().isNotEmpty, isFalse);
    });

    testWidgets('a row gone before its turn downloads nothing until it is back', (tester) async {
      final cache = cacheOf(downloads: 1);
      final first = urlOf('first'), gone = urlOf('gone');
      for (final url in [first, gone]) {
        youtube.answers[url] = () => http.Response.bytes(transparentPng, 200);
      }
      youtube.gates[first] = Completer<void>();
      await tester.pumpWidget(appOf(Column(children: [thumbnail('first')]), cache));
      await settle(tester);
      expect(youtube.requests, [first]);
      await tester.pumpWidget(appOf(Column(children: [thumbnail('first'), thumbnail('gone')]), cache));
      await settle(tester);
      expect(youtube.requests, [first], reason: 'waits for the slot');
      // the row scrolls away while its download waits
      await tester.pumpWidget(appOf(Column(children: [thumbnail('first')]), cache));
      youtube.gates[first]!.complete();
      await settle(tester, until: () => shownImage(tester, 'first'));
      expect(shownImage(tester, 'first'), isTrue);
      expect(youtube.requests, [first], reason: 'nobody shows it any more');
      // and comes back
      await tester.pumpWidget(appOf(Column(children: [thumbnail('first'), thumbnail('gone')]), cache));
      await settle(tester, until: () => shownImage(tester, 'gone'));
      expect(shownImage(tester, 'gone'), isTrue);
      expect(youtube.requests, [first, gone]);
    });
  });

  testWidgets('the native app builds thumbnails kept on disk', (tester) async {
    late ImageProvider image;
    await tester.pumpWidget(
      ProviderScope(
        child: Consumer(
          builder: (context, ref, _) {
            image = ref.watch(thumbnailImageProvider)(urlOf('abc'));
            return const SizedBox();
          },
        ),
      ),
    );
    expect(image, isA<CachedThumbnail>().having((i) => i.url, 'url', urlOf('abc')));
  });
}
