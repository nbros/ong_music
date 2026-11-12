/// Twitch, without API key: the channel's public schedule and whether it is
/// live right now.
library;

import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../logger.dart';
import 'schedule.dart';

/// The Twitch addresses used by the app.
abstract final class TwitchUrls {
  /// The public iCalendar feed of the schedule of `jonathanong` (broadcaster
  /// id 156801396). Needs no Client-Id; answers with CORS headers.
  static final schedule = Uri.parse('https://api.twitch.tv/helix/schedule/icalendar?broadcaster_id=156801396');

  /// The preview image of the live stream of `jonathanong`.
  static final preview = Uri.parse('https://static-cdn.jtvnw.net/previews-ttv/live_user_jonathanong-440x248.jpg');
}

/// Maximum time of each Twitch request.
const Duration twitchTimeout = Duration(seconds: 10);

/// A non-200 answer of Twitch.
class TwitchHttpException implements Exception {
  /// Creates the exception.
  const TwitchHttpException(this.uri, this.statusCode);

  final Uri uri;
  final int statusCode;

  @override
  String toString() => 'HTTP $statusCode for $uri';
}

/// What the app asks Twitch.
abstract interface class TwitchApi {
  /// Downloads and parses the schedule; throws on any network, HTTP or
  /// format error.
  Future<StreamSchedule> fetchSchedule();

  /// True only when the channel is known to be live; false on any doubt or
  /// error. Never throws.
  Future<bool> isLive();
}

/// [TwitchApi] over HTTP: a new client per request unless one is given, each
/// request bounded by [timeout].
final class HttpTwitchApi implements TwitchApi {
  /// Uses [client] (a new one per request when null) and [timeout].
  HttpTwitchApi({http.Client? client, this.timeout = twitchTimeout}) : _client = client;

  final http.Client? _client;

  /// Maximum time of each request, body included.
  final Duration timeout;

  Future<T> _with<T>(Future<T> Function(http.Client client) request) async {
    final client = _client ?? http.Client();
    try {
      return await request(client);
    } finally {
      if (_client == null) client.close();
    }
  }

  @override
  Future<StreamSchedule> fetchSchedule() async {
    final text = await _with((client) => fetchScheduleText(client, timeout: timeout));
    await loadTimeZones();
    return parseSchedule(text);
  }

  @override
  Future<bool> isLive() => _with((client) => isLiveByPreview(client, timeout: timeout));
}

/// Downloads the iCalendar text at [uri]; throws on any network or HTTP error
/// and after [timeout].
Future<String> fetchScheduleText(http.Client client, {Uri? uri, Duration timeout = twitchTimeout}) async {
  final target = uri ?? TwitchUrls.schedule;
  final response = await client.get(target).timeout(timeout);
  if (response.statusCode != 200) throw TwitchHttpException(target, response.statusCode);
  return utf8.decode(response.bodyBytes, allowMalformed: true);
}

const bool _inBrowser = bool.fromEnvironment('dart.library.js_interop');

/// Size of the image Twitch serves instead of the preview of an offline
/// channel (`ttv-static/404_preview-440x248.jpg`).
const int offlinePreviewBytes = 4031;

/// A live preview must be at least this large: twice the offline placeholder
/// (live previews weigh 20–30 KB).
const int minLivePreviewBytes = 2 * offlinePreviewBytes;

/// Whether the channel is live, from its preview image at [uri].
///
/// **Relies on undocumented behaviour of Twitch's image CDN**, observed in
/// November 2026: for a live channel the address answers 200 with a JPEG of
/// 20–30 KB (`cache-control: max-age=300`); for an offline one it redirects
/// (302) to the 4,031-byte placeholder `404_preview-440x248.jpg`
/// (`max-age=900`). The preview lags: it can take about 15 minutes to appear
/// after a stream starts and 5 minutes to go after it ends.
///
/// True only on positive evidence: status 200 without redirect, an image
/// content type, and a body of at least [minLivePreviewBytes]. Any doubt,
/// error or [timeout] gives false. Never throws.
///
/// Redirects are not followed, except on web: a browser can only follow a
/// redirect or fail the whole request (an error in its console at every check
/// of an offline channel). There the final URL, when exposed, must be the
/// requested one, and the size tells the placeholder apart anyway.
Future<bool> isLiveByPreview(http.Client client, {Uri? uri, Duration timeout = twitchTimeout}) async {
  final target = uri ?? TwitchUrls.preview;
  try {
    return await () async {
      final request = http.Request('GET', target)..followRedirects = _inBrowser;
      final streamed = await client.send(request);
      if (streamed.statusCode != 200) return false;
      if (streamed case http.BaseResponseWithUrl(:final url) when url.toString() != target.toString()) return false;
      final type = streamed.headers['content-type']?.toLowerCase() ?? '';
      if (!type.startsWith('image/')) return false;
      final response = await http.Response.fromStream(streamed);
      return response.bodyBytes.length >= minLivePreviewBytes;
    }().timeout(timeout);
  } catch (e) {
    logger.w('Live check failed: $e');
    return false;
  }
}
