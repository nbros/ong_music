/// What the tool of the offsets (a panel of the browser extension, on the YouTube page of a VOD) asks of the app's
/// code, plain strings in and out: the JS module `ongVods` (`tool/ong_vods_js.dart`, built by
/// `tool/build_vods_js.sh`) is this class compiled to JavaScript, so that the tool shows exactly what the app does.
///
/// Pure Dart: the parser of the sheets, the keys of the streams ([streamKeys]), `vods.tsv` ([VodFile]),
/// `offsets.tsv` ([OffsetFile]) and the positions in the VODs ([VodLinks]), those of the app.
library;

import 'dart:convert';

import 'catalogue.dart';
import 'model.dart';
import 'parser.dart';
import 'vod_offsets.dart';
import 'vods.dart';

/// The functions of the JS module `ongVods`, over one catalogue ([load]).
final class VodsTool {
  Catalogue? _catalogue;

  /// The texts of `vods.tsv` and `offsets.tsv` read last, and the links made of them: the tool calls [stream] again
  /// and again with the same files, or with a candidate text of `offsets.tsv` beside the saved one.
  final _vodFiles = _Recent<String, VodFile>(2);
  final _offsetFiles = _Recent<String, OffsetFile>(4);
  final _links = _Recent<(VodFile, OffsetFile), VodLinks>(4);

  /// Parses the two sheets as the app does (the app's table of names), and keeps the catalogue; returns the number of
  /// its streams. Throws a [CatalogueFormatException] when a sheet does not read (the catalogue kept before stays).
  int load(String songsCsv, String highlightsCsv) {
    final catalogue = parseCatalogue(highlightsCsv, songsCsv);
    _catalogue = catalogue;
    return catalogue.streamCount;
  }

  /// The catalogue of [load]: a [StateError] before.
  Catalogue get catalogue => _catalogue ?? (throw StateError('ongVods.load has not been called'));

  /// The links of [vodsTsv] and [offsetsTsv] (`""`: no file) in the catalogue.
  VodLinks links(String vodsTsv, String offsetsTsv) {
    final catalogue = this.catalogue;
    final vods = _vodFiles.get(vodsTsv, () => VodFile.parse(vodsTsv));
    final offsets = _offsetFiles.get(offsetsTsv, () => OffsetFile.parse(offsetsTsv));
    final made = _links.get((vods, offsets), () => VodLinks(catalogue, vods, offsets));
    // a [load] since: made again
    if (identical(made.catalogue, catalogue)) return made;
    return _links.put((vods, offsets), VodLinks(catalogue, vods, offsets));
  }

  /// JSON: every stream that has a VOD, in the order of the sheet: `key`, `startUtc`, `lengthSeconds`, `parts`
  /// (`part`, `id`, `seconds`), `vodSeconds` (their sum, null when a length is unknown), and the counts `plays`,
  /// `playsWithLink`, `offsets` (its lines that count), `checked` (it has at least one).
  String overview(String vodsTsv, String offsetsTsv) {
    final links = this.links(vodsTsv, offsetsTsv);
    final catalogue = links.catalogue;
    final out = <Object?>[];
    for (final s in catalogue.streams) {
      final vod = links.vodOf(s);
      if (vod == null) continue;
      var withLink = 0;
      for (final p in catalogue.playsOf(s)) {
        if (links.positionOf(p) != null) withLink++;
      }
      final offsets = links.offsetsOf(s)?.lines.length ?? 0;
      out.add({
        'key': links.keys[s.id].toString(),
        'startUtc': _startUtc(s),
        'lengthSeconds': s.durationSeconds,
        'parts': [
          for (final l in vod) {'part': l.part, 'id': l.id, 'seconds': l.seconds},
        ],
        'vodSeconds': vod.any((l) => l.seconds == null) ? null : vod.fold<int>(0, (sum, l) => sum + l.seconds!),
        'plays': s.playCount,
        'playsWithLink': withLink,
        'offsets': offsets,
        'checked': offsets > 0,
      });
    }
    return jsonEncode(out);
  }

  /// JSON: the stream whose VOD holds the video [videoId], or `null`: `key`, `startUtc`, `lengthSeconds`, `parts`
  /// (`part`, `id`, `seconds`, `title`), `offsets` (its lines that count, in order of uptime: `kind`, `uptime`,
  /// `seconds`, `note`), `plays` (`uptime`, null without one; `title`, one line as the Ong Log has it; `requester`;
  /// `offset`, the seconds added, 0 when no line applies and null without uptime; `offsetKind`, the kind of the line
  /// that applies, null when none; `position`, `part` and `seconds`, or null when it gets no link).
  String stream(String vodsTsv, String offsetsTsv, String videoId) {
    final links = this.links(vodsTsv, offsetsTsv);
    final catalogue = links.catalogue;
    for (final s in catalogue.streams) {
      final vod = links.vodOf(s);
      if (vod == null || !vod.any((l) => l.id == videoId)) continue;
      return jsonEncode({
        'key': links.keys[s.id].toString(),
        'startUtc': _startUtc(s),
        'lengthSeconds': s.durationSeconds,
        'parts': [
          for (final l in vod) {'part': l.part, 'id': l.id, 'seconds': l.seconds, 'title': l.title},
        ],
        'offsets': [for (final o in links.offsetsOf(s)?.lines ?? const <VodOffset>[]) offsetJson(o)],
        'plays': [
          for (final p in catalogue.playsOf(s))
            () {
              final uptime = catalogue.uptimeOf(p);
              final offset = links.offsetOf(p);
              final position = links.positionOf(p);
              final hasUptime = uptime != null && uptime > 0;
              return {
                'uptime': hasUptime ? uptime : null,
                'title': p.title,
                'requester': catalogue.requester(p.requesterId)?.name ?? '',
                'offset': hasUptime ? offset?.seconds ?? 0 : null,
                'offsetKind': offset?.kind.name,
                'position': position == null ? null : {'part': position.part, 'seconds': position.seconds},
              };
            }(),
        ],
      });
    }
    return 'null';
  }

  /// The text of `offsets.tsv` [offsetsTsv] with the lines of the stream [key] (as the `date` cell of `vods.tsv`)
  /// replaced by the set [offsetsJson], a JSON array as [stream] gives its `offsets` ([OffsetFile.replace]). Throws a
  /// [FormatException] on a key, a set or a file that does not read. Needs no [load].
  static String replaceOffsets(String offsetsTsv, String key, String offsetsJson) {
    final stream = StreamKey.tryParse(key);
    if (stream == null || key.trim() != key) {
      throw FormatException('The key does not read (YYYY-MM-DD, or YYYY-MM-DD#2)', key);
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(offsetsJson);
    } on FormatException {
      // (not the message of the parser: the JavaScript one says something else)
      throw FormatException('The offsets are not JSON', offsetsJson);
    }
    if (decoded is! List) throw FormatException('The offsets are not a JSON array', offsetsJson);
    return OffsetFile.replace(offsetsTsv, stream, [for (final (i, o) in decoded.indexed) offsetFromJson(o, i)]);
  }

  /// [o] as the tool gives it: `kind`, `uptime`, `seconds`, `note`.
  static Map<String, Object?> offsetJson(VodOffset o) => {
    'kind': o.kind.name,
    'uptime': o.uptime,
    'seconds': o.seconds,
    'note': o.note,
  };

  /// The offset of [json], the [index]th of a set ([offsetJson]); a [FormatException] when it does not read: a
  /// `kind` that is not `stream`, `from` or `play`, an `uptime` that is not null (or absent) for the whole stream
  /// and only then, nor a whole number of seconds from 0 ([maxVodOffsetUptime]), `seconds` not a whole number at most
  /// a day either way ([maxVodOffsetSeconds]), a `note` neither a string nor null (or absent).
  static VodOffset offsetFromJson(Object? json, int index) {
    Never fail(String what) => throw FormatException('Offset $index: $what', jsonEncode(json));
    if (json is! Map) fail('not an object');
    final kind = VodOffsetKind.values.where((k) => k.name == json['kind']).firstOrNull;
    if (kind == null) fail('kind is not "stream", "from" or "play"');
    final uptime = json['uptime'], seconds = json['seconds'], note = json['note'];
    if (kind == VodOffsetKind.stream ? uptime != null : !_wholeIn(uptime, 0, maxVodOffsetUptime)) {
      fail(kind == VodOffsetKind.stream ? 'uptime is not null' : 'uptime is not a whole number of seconds');
    }
    if (!_wholeIn(seconds, -maxVodOffsetSeconds, maxVodOffsetSeconds)) {
      fail('seconds is not a whole number at most $maxVodOffsetSeconds either way');
    }
    if (note != null && note is! String) fail('note is not a string');
    return VodOffset(
      kind: kind,
      uptime: (uptime as num?)?.toInt(),
      seconds: (seconds as num).toInt(),
      note: note ?? '',
    );
  }

  static bool _wholeIn(Object? value, int min, int max) =>
      value is num && value.isFinite && value == value.roundToDouble() && value >= min && value <= max;

  /// The instant of the "Stream Start" row of [s], `2021-07-30T04:12:00Z`, or null when the row has no time.
  static String? _startUtc(LiveStream s) {
    final minute = s.startMinute;
    if (minute == null) return null;
    final at = DateTime.fromMillisecondsSinceEpoch(minute * Duration.millisecondsPerMinute, isUtc: true);
    return '${at.toIso8601String().substring(0, 19)}Z';
  }
}

/// The message of the error [e] of a call of the JS module: what its JS `Error` says.
String vodsToolErrorMessage(Object e) => switch (e) {
  FormatException(:final message, :final source) => source == null ? message : '$message: ${_short(source)}',
  StateError(:final message) => message,
  ArgumentError(:final message) => '$message',
  _ => '$e',
};

String _short(Object? source) {
  final text = '$source';
  return text.length <= 200 ? text : '${text.substring(0, 200)}...';
}

/// The last [size] values made, by key.
final class _Recent<K, V> {
  _Recent(this.size);

  final int size;
  final _values = <K, V>{};

  V get(K key, V Function() make) {
    final value = _values.remove(key);
    return put(key, value ?? make());
  }

  V put(K key, V value) {
    _values
      ..remove(key)
      ..[key] = value;
    if (_values.length > size) _values.remove(_values.keys.first);
    return value;
  }
}
