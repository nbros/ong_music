import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ong_music/src/data/schedule.dart';
import 'package:ong_music/src/data/twitch.dart';

import 'schedule_test.dart' show twitchFeed;

/// A response that tells its final URL, as the browser client does after
/// following redirects.
class _ResponseWithUrl extends http.StreamedResponse implements http.BaseResponseWithUrl {
  _ResponseWithUrl(Uint8List body, int statusCode, {required this.url, super.headers})
    : super(Stream.value(body), statusCode, contentLength: body.length);

  @override
  final Uri url;
}

/// A client answering every request with [respond].
class _Client extends http.BaseClient {
  _Client(this.respond);

  final Future<http.StreamedResponse> Function(http.BaseRequest request) respond;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    requests.add(request);
    return respond(request);
  }
}

Uint8List bytes(int n) => Uint8List(n);

void main() {
  group('isLiveByPreview', () {
    Future<bool> check(http.Client client) => isLiveByPreview(client, timeout: const Duration(milliseconds: 200));

    test('200 with a large JPEG: live; redirects are not followed', () async {
      final client = _Client(
        (r) async => http.StreamedResponse(Stream.value(bytes(24000)), 200, headers: {'content-type': 'image/jpeg'}),
      );
      expect(await check(client), isTrue);
      final request = client.requests.single;
      expect(request.url, TwitchUrls.preview);
      expect(request.followRedirects, isFalse);
      expect(request.method, 'GET');
    });

    test('the offline placeholder (a redirect followed by the browser): not live', () async {
      final placeholder = Uri.parse('https://static-cdn.jtvnw.net/ttv-static/404_preview-440x248.jpg');
      expect(
        await check(
          _Client(
            (r) async => _ResponseWithUrl(
              bytes(offlinePreviewBytes),
              200,
              url: placeholder,
              headers: {'content-type': 'image/jpeg'},
            ),
          ),
        ),
        isFalse,
      );
      // even a large image, when it is not at the requested address
      expect(
        await check(
          _Client(
            (r) async => _ResponseWithUrl(bytes(30000), 200, url: placeholder, headers: {'content-type': 'image/jpeg'}),
          ),
        ),
        isFalse,
      );
      // the placeholder served directly
      expect(
        await check(
          MockClient(
            (r) async => http.Response.bytes(bytes(offlinePreviewBytes), 200, headers: {'content-type': 'image/jpeg'}),
          ),
        ),
        isFalse,
      );
    });

    test('the final URL is the requested one: live', () async {
      expect(
        await check(
          _Client(
            (r) async =>
                _ResponseWithUrl(bytes(30000), 200, url: TwitchUrls.preview, headers: {'content-type': 'image/jpeg'}),
          ),
        ),
        isTrue,
      );
    });

    test('a redirect not followed: not live', () async {
      expect(
        await check(
          MockClient(
            (r) async => http.Response(
              '',
              302,
              headers: {'location': 'https://static-cdn.jtvnw.net/ttv-static/404_preview-440x248.jpg'},
            ),
          ),
        ),
        isFalse,
      );
    });

    test('an error status: not live', () async {
      for (final status in [404, 500, 503]) {
        expect(
          await check(
            MockClient((r) async => http.Response.bytes(bytes(30000), status, headers: {'content-type': 'image/jpeg'})),
          ),
          isFalse,
          reason: '$status',
        );
      }
    });

    test('a network error or a timeout: not live, no exception', () async {
      expect(await check(MockClient((r) async => throw http.ClientException('offline'))), isFalse);
      final never = Completer<http.StreamedResponse>();
      expect(await check(_Client((r) => never.future)), isFalse);
      // a body that never ends
      final body = StreamController<List<int>>();
      addTearDown(body.close);
      expect(
        await check(
          _Client((r) async => http.StreamedResponse(body.stream, 200, headers: {'content-type': 'image/jpeg'})),
        ),
        isFalse,
      );
    });

    test('a 200 that is not an image: not live', () async {
      expect(
        await check(
          MockClient(
            (r) async => http.Response('<html>${'x' * 30000}</html>', 200, headers: {'content-type': 'text/html'}),
          ),
        ),
        isFalse,
      );
      expect(await check(MockClient((r) async => http.Response.bytes(bytes(30000), 200))), isFalse);
    });
  });

  group('fetchScheduleText', () {
    test('downloads the feed, without any header', () async {
      final client = _Client((r) async => http.StreamedResponse(Stream.value(twitchFeed.join('\r\n').codeUnits), 200));
      final text = await fetchScheduleText(client);
      expect(text, startsWith('BEGIN:VCALENDAR'));
      expect(client.requests.single.url, TwitchUrls.schedule);
      expect(client.requests.single.headers, isEmpty);
    });

    test('throws on an error status and on a timeout', () async {
      await expectLater(
        fetchScheduleText(MockClient((r) async => http.Response('', 429))),
        throwsA(isA<TwitchHttpException>().having((e) => e.statusCode, 'statusCode', 429)),
      );
      final never = Completer<http.StreamedResponse>();
      await expectLater(
        fetchScheduleText(_Client((r) => never.future), timeout: const Duration(milliseconds: 50)),
        throwsA(isA<TimeoutException>()),
      );
    });
  });

  test('HttpTwitchApi parses the schedule', () async {
    final api = HttpTwitchApi(client: MockClient((r) async => http.Response(twitchFeed.join('\r\n'), 200)));
    final schedule = await api.fetchSchedule();
    expect(schedule.eventCount, 3);
    await expectLater(
      HttpTwitchApi(client: MockClient((r) async => http.Response('<html></html>', 200))).fetchSchedule(),
      throwsA(isA<ScheduleFormatException>()),
    );
  });
}
