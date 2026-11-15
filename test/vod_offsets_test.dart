// offsets.tsv: how it reads, which line applies to a play, where the play then is in the VOD, and how the tool of the
// extension rewrites the lines of one stream.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/vod_offsets.dart';
import 'package:ong_music/src/data/vods.dart';
import 'package:ong_music/src/data/vods_tool.dart';

import 'fixtures.dart';

const _header = 'date\tuptime\toffset\tnote';
const _vodsHeader = 'date\tpart\tid\tseconds\tposted\ttitle';

/// A file of [lines] after its header.
OffsetFile _offsets(List<String> lines) => OffsetFile.parse([_header, ...lines].join('\n'));

final _key = StreamKey.tryParse('2024-01-02')!;

/// The offsets of `2024-01-02` in [lines].
StreamOffsets _of(List<String> lines) => _offsets(lines).of(_key)!;

/// A stream started 2024-01-01 20:00 in the zone of the sheet (2024-01-02 in Sydney), its plays at [uptimes].
Catalogue _stream(List<String> uptimes) => catalogueOf(
  songs: [
    start('2024-01-01 20:00:00'),
    for (final (i, u) in uptimes.indexed)
      sRow(date: '2024-01-01 21:00:00', uptime: u, order: '${i + 1}', title: 'Song $i'),
  ],
);

/// A VOD of `2024-01-02` in parts of [seconds] (null: unknown).
VodFile _vod(List<int?> seconds) => VodFile.parse(
  [
    _vodsHeader,
    for (final (i, s) in seconds.indexed) '2024-01-02\t${i + 1}\tvid_______${i + 1}\t${s ?? ''}',
  ].join('\n'),
);

/// The position of each play of [catalogue] as `part@seconds`, null for none.
List<String?> _positions(Catalogue catalogue, VodFile vod, OffsetFile offsets) {
  final links = VodLinks(catalogue, vod, offsets);
  return [
    for (final p in catalogue.plays)
      () {
        final at = links.positionOf(p);
        return at == null ? null : '${at.part}@${at.seconds}';
      }(),
  ];
}

void main() {
  group('reading', () {
    test('the three kinds of lines, a note, columns beyond the fourth, a signed offset', () {
      final file = _offsets([
        '2024-01-02\t\t-1140\tlocal recording',
        '2024-01-02\t1:00:00+\t+12',
        '2024-01-02\t2:03:23\t5\tthe song\textra\tcolumns',
        '2022-05-08#2\t0:10:00\t0',
      ]);
      expect(file.ignored, isEmpty);
      expect(
        [for (final l in file.lines) (l.key.toString(), l.offset.kind, l.offset.uptime, l.offset.seconds)],
        [
          ('2024-01-02', VodOffsetKind.stream, null, -1140),
          ('2024-01-02', VodOffsetKind.from, 3600, 12),
          ('2024-01-02', VodOffsetKind.play, 7403, 5),
          ('2022-05-08#2', VodOffsetKind.play, 600, 0),
        ],
      );
      expect(file.lines.first.offset.note, 'local recording');
      expect(file.lines[2].offset.note, 'the song');
      expect([for (final l in file.lines) l.lineNumber], [2, 3, 4, 5]);
      expect(file.keys.map((k) => '$k'), ['2024-01-02', '2022-05-08#2']);
    });

    test('comments, blank lines, a byte order mark and CRLF line ends', () {
      final file = OffsetFile.parse('﻿# offsets\r\n\r\n$_header\r\n  # indented comment\r\n2024-01-02\t\t-5\r\n\n');
      expect(file.ignored, isEmpty);
      expect(file.lines.single.offset.seconds, -5);
      expect(file.lines.single.lineNumber, 5);
    });

    test('a line that does not read is left out, with why; never the whole file', () {
      final file = _offsets([
        '2024-01-02\t\t1',
        '2024-01-02\t1:00:00',
        '\t\t5',
        '2024/01/02\t\t5',
        '2024-01-02#0\t\t5',
        '2024-01-02\t1:60:00\t5',
        '2024-01-02\t1:00\t5',
        '2024-01-02\t1:00:00++\t5',
        '2024-01-02\t+1:00:00\t5',
        '2024-01-02\t-1:00:00\t5',
        '2024-01-02\t\t86401',
        '2024-01-02\t\t-86401',
        '2024-01-02\t\t1.5',
        '2024-01-02\t\t',
        '2024-01-02\t\t5 s',
        '2024-01-02\t\t--5',
      ]);
      expect(file.lines.single.offset.seconds, 1);
      expect(
        [for (final n in file.ignored) n.reason],
        [
          'fewer than three columns',
          'no date',
          'the date does not read (YYYY-MM-DD, or YYYY-MM-DD#2)',
          'the date does not read (YYYY-MM-DD, or YYYY-MM-DD#2)',
          for (var i = 0; i < 5; i++) 'the uptime does not read (empty, h:mm:ss+ or h:mm:ss)',
          for (var i = 0; i < 6; i++) 'the offset does not read (whole seconds, at most a day either way)',
        ],
      );
      expect(file.ignored.first.lineNumber, 3);
      expect(file.ignored.first.text, '2024-01-02\t1:00:00');
    });

    test('at most a day either way: 86400 reads, both ways', () {
      final file = _offsets(['2024-01-02\t\t86400', '2024-01-03\t\t-86400']);
      expect([for (final l in file.lines) l.offset.seconds], [86400, -86400]);
    });

    test('whether a text is the file: its first line neither blank nor a comment is the header', () {
      expect(OffsetFile.isFile(_header), isTrue);
      expect(OffsetFile.isFile('# offsets\n\n  DATE \t Uptime\tOFFSET\n'), isTrue);
      expect(OffsetFile.isFile('﻿date\tuptime\toffset'), isTrue);
      expect(OffsetFile.isFile(''), isFalse);
      expect(OffsetFile.isFile('# only a comment\n'), isFalse);
      expect(OffsetFile.isFile('upstream connect error'), isFalse);
      expect(OffsetFile.isFile('<html><body>404</body></html>'), isFalse);
      expect(OffsetFile.isFile('$_vodsHeader\n'), isFalse, reason: 'a vods.tsv');
      expect(OffsetFile.isFile('2024-01-02\t\t5\n$_header'), isFalse, reason: 'the header must come first');
      expect(OffsetFile.parse('$_header\n').isEmpty, isTrue);
    });

    test('the later line of a same stream and uptime cell wins; 0:00:00+ is the whole stream', () {
      final file = _offsets([
        '2024-01-02\t\t-100\tfirst',
        '2024-01-02\t1:00:00+\t1',
        '2024-01-02\t1:00:00\t2',
        '2024-01-02\t0:00:00+\t-200\tsecond',
        '2024-01-02\t1:00:00+\t3',
        '2024-01-02#1\t\t-300\tthird',
        '2024-01-02#2\t\t-400',
      ]);
      expect([for (final (a, b) in file.replaced) (a.lineNumber, b.lineNumber)], [(2, 5), (3, 6), (5, 7)]);
      final lines = file.of(_key)!.lines;
      expect(
        [for (final o in lines) (o.kind, o.uptime, o.seconds, o.note)],
        [
          (VodOffsetKind.stream, null, -300, 'third'),
          (VodOffsetKind.from, 3600, 3, ''),
          (VodOffsetKind.play, 3600, 2, ''),
        ],
      );
      expect(file.of(StreamKey.tryParse('2024-01-02#2')!)!.lines.single.seconds, -400);
    });
  });

  group('the offset of a play', () {
    test('1. the line of exactly its uptime', () {
      final o = _of(['2024-01-02\t\t-10', '2024-01-02\t1:00:00+\t-20', '2024-01-02\t1:30:00\t-30']);
      expect(o.at(5400)!.seconds, -30);
      expect(o.at(5401)!.seconds, -20, reason: 'only that uptime');
      expect(o.at(5399)!.seconds, -20);
    });

    test('2. else the "from" line of the largest uptime at most its own, the whole stream from 0', () {
      final o = _of(['2024-01-02\t2:00:00+\t-2', '2024-01-02\t\t-10', '2024-01-02\t1:00:00+\t-1']);
      expect(o.at(1)!.seconds, -10);
      expect(o.at(3599)!.seconds, -10);
      expect(o.at(3600)!.seconds, -1, reason: 'from that uptime on, itself included');
      expect(o.at(7199)!.seconds, -1);
      expect(o.at(7200)!.seconds, -2);
      expect(o.at(99999)!.seconds, -2);
      expect(o.lines.map((l) => l.uptime), [null, 3600, 7200], reason: 'in order of uptime');
    });

    test('3. else none (0)', () {
      final o = _of(['2024-01-02\t1:00:00+\t-1', '2024-01-02\t0:30:00\t-3']);
      expect(o.at(10), isNull);
      expect(o.at(3599), isNull);
      expect(o.at(1800)!.seconds, -3);
      expect(_offsets(['2024-01-03\t\t5']).of(_key), isNull, reason: 'another stream');
    });

    test('a "from" line and the line of exactly the same uptime: the exact one', () {
      final o = _of(['2024-01-02\t1:00:00\t7', '2024-01-02\t1:00:00+\t-1']);
      expect(o.at(3600)!.kind, VodOffsetKind.play);
      expect(o.at(3601)!.kind, VodOffsetKind.from);
      expect(o.lines.map((l) => l.kind), [VodOffsetKind.from, VodOffsetKind.play]);
    });
  });

  group('the position in the VOD', () {
    test('the uptime plus the offset, in a VOD of one part', () {
      final c = _stream(['0:30:00', '1:00:00', '2:00:00', '2:00:01']);
      final offsets = _offsets(['2024-01-02\t\t-1140', '2024-01-02\t2:00:00+\t-1200', '2024-01-02\t2:00:01\t+5']);
      expect(_positions(c, _vod([12628]), offsets), ['1@660', '1@2460', '1@6000', '1@7206']);
      expect(_positions(c, _vod([12628]), OffsetFile.empty), ['1@1800', '1@3600', '1@7200', '1@7201']);
      final links = VodLinks(c, _vod([12628]), offsets);
      expect(links.linkOf(c.plays.first).toString(), 'https://youtu.be/vid_______1?t=660');
      expect(links.offsetOf(c.plays.first)!.kind, VodOffsetKind.stream);
      expect(links.offsetOf(c.plays.last)!.kind, VodOffsetKind.play);
      expect(VodLinks(c, _vod([12628])).positionOf(c.plays.first)!.seconds, 1800, reason: 'no offsets');
    });

    test('a position before the start of the recording: no link; at its very start, the link without t', () {
      final c = _stream(['0:10:00', '0:19:59', '0:20:00', '0:20:01']);
      final offsets = _offsets(['2024-01-02\t\t-1200']);
      expect(_positions(c, _vod([5000]), offsets), [null, null, '1@0', '1@1']);
      expect(VodLinks(c, _vod([5000]), offsets).linkOf(c.plays[2]).toString(), 'https://youtu.be/vid_______1');
    });

    test('no uptime, or 0:00:00: no link and no offset, whatever the lines', () {
      final c = _stream(['', '0:00:00', '0:00:01']);
      final offsets = _offsets(['2024-01-02\t\t600', '2024-01-02\t0:00:00\t600']);
      expect(_positions(c, _vod([5000]), offsets), [null, null, '1@601']);
      final links = VodLinks(c, _vod([5000]), offsets);
      expect(links.offsetOf(c.plays[0]), isNull);
      expect(links.offsetOf(c.plays[1]), isNull);
    });

    test('several parts: the position, not the uptime, decides the part', () {
      final c = _stream(['0:59:50', '1:00:10', '2:30:00', '3:30:00']);
      final vod = _vod([3600, 7200]);
      expect(_positions(c, vod, OffsetFile.empty), ['1@3590', '2@10', '2@5400', null]);
      // 20 s late: the play just after the end of part 1 falls back into it
      expect(_positions(c, vod, _offsets(['2024-01-02\t\t-20'])), ['1@3570', '1@3590', '2@5380', null]);
      // 30 s early: the play just before the end of part 1 goes into part 2
      expect(_positions(c, vod, _offsets(['2024-01-02\t\t+30'])), ['2@20', '2@40', '2@5430', null]);
      // an hour and a second late: the first before the start, the others a part earlier or nearer its start
      expect(_positions(c, vod, _offsets(['2024-01-02\t\t-3601'])), [null, '1@9', '2@1799', '2@5399']);
    });

    test('a "from" line at the boundary of two parts', () {
      final c = _stream(['0:59:59', '1:00:00', '1:00:10', '1:00:11']);
      final vod = _vod([3600, 7200]);
      final offsets = _offsets(['2024-01-02\t1:00:00+\t-10']);
      expect(_positions(c, vod, offsets), ['1@3599', '1@3590', '2@0', '2@1']);
    });

    test('a part of unknown length: a position after it has no link, one before it has', () {
      final c = _stream(['0:30:00', '1:30:00']);
      final vod = _vod([null, 7200]);
      expect(_positions(c, vod, _offsets(['2024-01-02\t\t-600'])), [null, null]);
      expect(_positions(c, _vod([3600, null]), _offsets(['2024-01-02\t\t-600'])), ['1@1200', '2@1200']);
      expect(_positions(c, _vod([null]), _offsets(['2024-01-02\t\t+80000'])), ['1@81800', '1@85400']);
    });

    test('placeInVod: the parts end to end', () {
      final vod = _vod([100, 200, null]).vodOf(_key)!;
      String? at(int s) {
        final p = placeInVod(vod, s);
        return p == null ? null : '${p.part}@${p.seconds}';
      }

      expect(
        [
          for (final s in [-1, 0, 99, 100, 299, 300, 100000]) at(s),
        ],
        [null, '1@0', '1@99', '2@0', '2@199', '3@0', '3@99700'],
      );
    });
  });

  group('replace (the tool writes one stream)', () {
    const file =
        '# offsets of the VODs\n'
        '$_header\n'
        '2023-05-01\t\t-5\tanother stream\n'
        '\n'
        '2024-01-02\t\t-1140\tfirst\n'
        '# a comment between\n'
        '2024-01-02\t1:00:60\t5\tdoes not read: stays\n'
        '2024-01-02\t1:00:00+\t-1200\n'
        '2024-01-02#2\t\t10\n'
        '2024-01-03\t\t+7  \tspaces kept\n';

    test('its lines replaced where the first was; every other line byte for byte', () {
      final out = OffsetFile.replace(file, _key, [
        VodOffset(kind: VodOffsetKind.play, uptime: 7403, seconds: 5, note: 'Hot Potato'),
        VodOffset(kind: VodOffsetKind.stream, seconds: -1100),
      ]);
      expect(
        out,
        '# offsets of the VODs\n'
        '$_header\n'
        '2023-05-01\t\t-5\tanother stream\n'
        '\n'
        '2024-01-02\t\t-1100\t\n'
        '2024-01-02\t2:03:23\t5\tHot Potato\n'
        '# a comment between\n'
        '2024-01-02\t1:00:60\t5\tdoes not read: stays\n'
        '2024-01-02#2\t\t10\n'
        '2024-01-03\t\t+7  \tspaces kept\n',
      );
      final read = OffsetFile.parse(out);
      expect(read.of(_key)!.lines.map((o) => o.seconds), [-1100, 5]);
      expect(read.ignored.single.text, '2024-01-02\t1:00:60\t5\tdoes not read: stays');
    });

    test('replaced by an empty set: its lines removed, nothing else', () {
      final out = OffsetFile.replace(file, _key, const []);
      expect(
        out,
        file.replaceFirst('2024-01-02\t\t-1140\tfirst\n', '').replaceFirst('2024-01-02\t1:00:00+\t-1200\n', ''),
      );
      expect(OffsetFile.parse(out).of(_key), isNull);
    });

    test('a stream without lines: at the end, after a last line with or without its line end', () {
      final key = StreamKey.tryParse('2024-02-01#2')!;
      final set = [VodOffset(kind: VodOffsetKind.stream, seconds: 0, note: 'checked')];
      expect(OffsetFile.replace(file, key, set), '${file}2024-02-01#2\t\t0\tchecked\n');
      final without = file.substring(0, file.length - 1);
      expect(OffsetFile.replace(without, key, set), '$without\n2024-02-01#2\t\t0\tchecked\n');
      expect(OffsetFile.replace(file, key, const []), file, reason: 'nothing to write');
    });

    test('the key as the date cell reads it: 2024-01-02#1 is 2024-01-02', () {
      final out = OffsetFile.replace(file.replaceAll('2024-01-02\t', '2024-01-02#1\t'), _key, const []);
      expect(OffsetFile.parse(out).of(_key), isNull);
    });

    test('no file yet (empty): its header and the new lines', () {
      expect(OffsetFile.replace('', _key, const []), '$_header\n');
      expect(
        OffsetFile.replace(' \n', _key, [VodOffset(kind: VodOffsetKind.stream, seconds: -1140)]),
        '$_header\n2024-01-02\t\t-1140\t\n',
      );
      expect(OffsetFile.isFile(OffsetFile.replace('', _key, const [])), isTrue);
    });

    test('a text that is no file is not overwritten', () {
      expect(() => OffsetFile.replace('<html>rate limited</html>', _key, const []), throwsFormatException);
    });

    test('the set: one line per uptime cell (the later wins), in order of uptime, the note on one line', () {
      final out = OffsetFile.replace('', _key, [
        VodOffset(kind: VodOffsetKind.from, uptime: 7200, seconds: 1),
        VodOffset(kind: VodOffsetKind.stream, seconds: -1, note: 'a\ttab\nand a line'),
        VodOffset(kind: VodOffsetKind.play, uptime: 3600, seconds: 2),
        VodOffset(kind: VodOffsetKind.from, uptime: 3600, seconds: 3),
        VodOffset(kind: VodOffsetKind.from, uptime: 0, seconds: -4),
        VodOffset(kind: VodOffsetKind.from, uptime: 7200, seconds: 5),
      ]);
      expect(
        out,
        '$_header\n'
        '2024-01-02\t\t-4\t\n'
        '2024-01-02\t1:00:00+\t3\t\n'
        '2024-01-02\t1:00:00\t2\t\n'
        '2024-01-02\t2:00:00+\t5\t\n',
      );
      expect(
        OffsetFile.replace('', _key, [VodOffset(kind: VodOffsetKind.stream, seconds: 1, note: ' a\ttab\nand a line ')]),
        '$_header\n2024-01-02\t\t1\ta tab and a line\n',
      );
    });

    test('an offset that would not read again cannot be made', () {
      expect(() => VodOffset(kind: VodOffsetKind.stream, uptime: 5, seconds: 1), throwsArgumentError);
      expect(() => VodOffset(kind: VodOffsetKind.from, seconds: 1), throwsArgumentError);
      expect(() => VodOffset(kind: VodOffsetKind.play, uptime: -1, seconds: 1), throwsRangeError);
      expect(() => VodOffset(kind: VodOffsetKind.stream, seconds: 86401), throwsRangeError);
      final far = VodOffset(kind: VodOffsetKind.play, uptime: maxVodOffsetUptime, seconds: -86400);
      final read = OffsetFile.parse(OffsetFile.replace('', _key, [far])).lines.single.offset;
      expect(read, far);
    });
  });

  group('the tool (the JS module ongVods)', () {
    final songs = songsCsv([
      start('2024-01-01 20:00:00'),
      sRow(date: '2024-01-01 21:00:00', uptime: '0:10:00', requester: 'Amy', title: 'Some  Game - Theme'),
      sRow(date: '2024-01-01 21:10:00', uptime: '1:00:10', title: 'Other'),
      sRow(date: '2024-01-01 21:20:00', title: 'No uptime'),
    ]);
    final highlights = highlightsCsv([hRow(title: 'A video')]);
    final vods = '$_vodsHeader\n2024-01-02\t1\tvid_______1\t3600\t\tPart 1\n2024-01-02\t2\tvid_______2\t\t\tPart 2\n';
    const offsets = '$_header\n2024-01-02\t\t-700\n2024-01-02\t1:00:10\t+5\tnudged\n';

    test('before load: an error', () {
      expect(() => VodsTool().overview(vods, ''), throwsStateError);
      expect(() => VodsTool().stream(vods, '', 'vid_______1'), throwsStateError);
      expect(() => VodsTool().load('', highlights), throwsFormatException);
    });

    test('stream: the parts, the lines that count, each play with its offset and position', () {
      final tool = VodsTool();
      expect(tool.load(songs, highlights), 1);
      final json = jsonDecode(tool.stream(vods, offsets, 'vid_______2')) as Map<String, Object?>;
      expect(json['key'], '2024-01-02');
      expect(json['startUtc'], '2024-01-02T01:00:00Z');
      expect(json['lengthSeconds'], 3610);
      expect(json['parts'], [
        {'part': 1, 'id': 'vid_______1', 'seconds': 3600, 'title': 'Part 1'},
        {'part': 2, 'id': 'vid_______2', 'seconds': null, 'title': 'Part 2'},
      ]);
      expect(json['offsets'], [
        {'kind': 'stream', 'uptime': null, 'seconds': -700, 'note': ''},
        {'kind': 'play', 'uptime': 3610, 'seconds': 5, 'note': 'nudged'},
      ]);
      expect(json['plays'], [
        {
          'uptime': 600,
          'title': 'Some Game - Theme',
          'requester': 'Amy',
          'offset': -700,
          'offsetKind': 'stream',
          'position': null,
        },
        {
          'uptime': 3610,
          'title': 'Other',
          'requester': '',
          'offset': 5,
          'offsetKind': 'play',
          'position': {'part': 2, 'seconds': 15},
        },
        {'uptime': null, 'title': 'No uptime', 'requester': '', 'offset': null, 'offsetKind': null, 'position': null},
      ]);
      final none = (jsonDecode(tool.stream(vods, '', 'vid_______1')) as Map)['plays'] as List;
      expect(none.first, containsPair('offset', 0));
      expect(none.first, containsPair('offsetKind', null));
      expect(none.first, containsPair('position', {'part': 1, 'seconds': 600}));
      expect(tool.stream(vods, offsets, 'vid_______3'), 'null');
    });

    test('overview: the counts', () {
      final tool = VodsTool()..load(songs, highlights);
      expect(jsonDecode(tool.overview(vods, offsets)), [
        {
          'key': '2024-01-02',
          'startUtc': '2024-01-02T01:00:00Z',
          'lengthSeconds': 3610,
          'parts': [
            {'part': 1, 'id': 'vid_______1', 'seconds': 3600},
            {'part': 2, 'id': 'vid_______2', 'seconds': null},
          ],
          'vodSeconds': null,
          'plays': 3,
          'playsWithLink': 1,
          'offsets': 2,
          'checked': true,
        },
      ]);
      expect((jsonDecode(tool.overview(vods, '')) as List).single, containsPair('checked', false));
    });

    test('replaceOffsets: the JSON of stream().offsets back into the file', () {
      final tool = VodsTool()..load(songs, highlights);
      final lines = (jsonDecode(tool.stream(vods, offsets, 'vid_______1')) as Map)['offsets'];
      expect(
        VodsTool.replaceOffsets(offsets, '2024-01-02', jsonEncode(lines)),
        '$_header\n2024-01-02\t\t-700\t\n2024-01-02\t1:00:10\t5\tnudged\n',
      );
      expect(VodsTool.replaceOffsets('', '2024-01-02', '[]'), '$_header\n');
      for (final (key, json) in [
        ('2024-13-02', '[]'),
        ('2024-01-02', '[{"kind":"stream","seconds":1.5}]'),
        ('2024-01-02', '[{"kind":"play","seconds":1}]'),
        ('2024-01-02', 'not json'),
      ]) {
        expect(() => VodsTool.replaceOffsets(offsets, key, json), throwsFormatException, reason: '$key $json');
      }
      expect(vodsToolErrorMessage(StateError('x')), 'x');
    });
  });
}
