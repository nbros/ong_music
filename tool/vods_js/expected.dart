// The calls of the test of the JS module `ongVods` (tool/vods_js_test.sh), with what the app's code gives for each
// on the Dart VM: `VodsTool`, the code the module is compiled from. test.cjs makes the same calls on the built file
// and compares.
//
//   dart run tool/vods_js/expected.dart <fixtures directory> [<songs.csv> <highlights.csv> <vods.tsv> [<offsets.tsv>]]
//
// Prints a JSON array of `{fn, args, fresh?, result}` or `{fn, args, fresh?, error}`: `fn` a function of the module,
// `args` its arguments, each a string or `{"file": <path>}` (the text of that file); `fresh`: called in a module
// just loaded (before any `load`); `error`: the message of the JS Error it throws. With the real sheets and files,
// their cases come after those of the fixtures: `load`, `overview`, and `stream` for the first part of each VOD.
//
// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:ong_music/src/data/sheets.dart' show SheetUrls;
import 'package:ong_music/src/data/vod_offsets.dart';
import 'package:ong_music/src/data/vods.dart';
import 'package:ong_music/src/data/vods_tool.dart';

void main(List<String> argv) {
  if (argv.isEmpty || argv.length == 2 || argv.length == 3 || argv.length > 5) {
    stderr.writeln(
      'usage: dart run tool/vods_js/expected.dart <fixtures> [<songs.csv> <highlights.csv> <vods.tsv> [<offsets.tsv>]]',
    );
    exit(64);
  }
  final dir = Directory(argv[0]).absolute.path;
  final cases = <Map<String, Object?>>[];
  var tool = VodsTool();

  Map<String, String> file(String name) => {'file': name.startsWith('/') ? name : '$dir/$name'};
  String text(Object arg) => arg is String ? arg : File((arg as Map)['file'] as String).readAsStringSync();

  void call(String fn, List<Object> args, {bool fresh = false}) {
    final strings = [for (final a in args) text(a)];
    final used = fresh ? VodsTool() : tool;
    final entry = <String, Object?>{'fn': fn, 'args': args, if (fresh) 'fresh': true};
    try {
      entry['result'] = switch (fn) {
        'load' => used.load(strings[0], strings[1]),
        'overview' => used.overview(strings[0], strings[1]),
        'stream' => used.stream(strings[0], strings[1], strings[2]),
        'replaceOffsets' => VodsTool.replaceOffsets(strings[0], strings[1], strings[2]),
        _ => throw ArgumentError(fn),
      };
    } on ArgumentError catch (e) {
      if (e.message == fn) rethrow;
      entry['error'] = vodsToolErrorMessage(e);
    } catch (e) {
      entry['error'] = vodsToolErrorMessage(e);
    }
    cases.add(entry);
  }

  // the constants
  cases.add({
    'fn': 'constants',
    'args': <Object>[],
    'result': {
      'sheets': {'songs': SheetUrls.songs.toString(), 'highlights': SheetUrls.highlights.toString()},
      'offsetsHeader': OffsetFile.header,
    },
  });

  final songs = file('songs.csv'), highlights = file('highlights.csv');
  final vods = file('vods.tsv'), offsets = file('offsets.tsv');

  // before load, and sheets that do not read
  call('overview', [vods, ''], fresh: true);
  call('stream', [vods, offsets, 'aaaaaaaaaa1'], fresh: true);
  call('load', ['', highlights], fresh: true);
  call('load', ['<html><body>sign in</body></html>', highlights], fresh: true);
  call('load', [songs, '"Nothing"\n"at all"\n'], fresh: true);

  call('load', [songs, highlights]);
  // a load that fails keeps the catalogue
  call('load', ['', highlights]);
  for (final o in ['', offsets, '<html>no file</html>']) {
    call('overview', [vods, o]);
  }
  for (final id in ['aaaaaaaaaa1', 'aaaaaaaaaa2', 'bbbbbbbbbb1', 'ccccccccccc', 'ddddddddddd', 'zzzzzzzzzzz']) {
    call('stream', [vods, offsets, id]);
  }
  call('stream', [vods, '', 'aaaaaaaaaa1']);
  call('stream', ['', '', 'aaaaaaaaaa1']);

  // replaceOffsets
  String set(List<Map<String, Object?>> offsets) => jsonEncode(offsets);
  final whole = set([
    {'kind': 'stream', 'uptime': null, 'seconds': -1140, 'note': ''},
  ]);
  call('replaceOffsets', ['', '2021-07-30', '[]']);
  call('replaceOffsets', ['', '2021-07-30', whole]);
  call('replaceOffsets', ['   \n', '2021-07-30', whole]);
  call('replaceOffsets', [
    offsets,
    '2024-01-02',
    set([
      {'kind': 'play', 'uptime': 1800, 'seconds': 1, 'note': 'exact'},
      {'kind': 'from', 'uptime': 3600, 'seconds': -12},
      {'kind': 'stream', 'uptime': null, 'seconds': -25, 'note': 'tab\there, line\nbreak'},
      // the same cell again: the later wins; from 0 is the whole stream
      {'kind': 'from', 'uptime': 0, 'seconds': -26, 'note': null},
      {'kind': 'play', 'uptime': 1800, 'seconds': 2, 'note': 'exact again'},
    ]),
  ]);
  call('replaceOffsets', [offsets, '2024-01-02', '[]']);
  call('replaceOffsets', [offsets, '2024-01-02#1', '[]']);
  call('replaceOffsets', [offsets, '2024-01-02#2', whole]);
  // the line that does not read stays where it is; the new one at the end
  call('replaceOffsets', [offsets, '2024-01-05', whole]);
  call('replaceOffsets', [offsets, '2024-03-01', whole]);
  call('replaceOffsets', ['date\tuptime\toffset\tnote\r\n2024-01-02\t\t5\r\n# end', '2024-03-01', whole]);
  call('replaceOffsets', ['date\tuptime\toffset\tnote\r\n2024-01-02\t\t5\r\n# end', '2024-01-02', whole]);
  // what does not read
  for (final (key, json) in [
    ('x', whole),
    (' 2024-01-02', whole),
    ('2024-01-02', '{'),
    ('2024-01-02', '{}'),
    ('2024-01-02', '[1]'),
    ('2024-01-02', '[{"kind":"part","uptime":null,"seconds":1}]'),
    ('2024-01-02', '[{"kind":"stream","uptime":5,"seconds":1}]'),
    ('2024-01-02', '[{"kind":"from","seconds":1}]'),
    ('2024-01-02', '[{"kind":"play","uptime":-1,"seconds":1}]'),
    ('2024-01-02', '[{"kind":"play","uptime":1.5,"seconds":1}]'),
    ('2024-01-02', '[{"kind":"stream","seconds":86401}]'),
    ('2024-01-02', '[{"kind":"stream","seconds":"5"}]'),
    ('2024-01-02', '[{"kind":"stream","seconds":5,"note":3}]'),
  ]) {
    call('replaceOffsets', [offsets, key, json]);
  }
  call('replaceOffsets', ['[{"kind":"stream","seconds":86400}]', '2024-01-02', '[{"kind":"stream","seconds":-86400}]']);
  call('replaceOffsets', [
    offsets,
    '2024-01-02',
    '[{"kind":"stream","seconds":86400},{"kind":"play","uptime":360000,"seconds":-86400}]',
  ]);

  // the real sheets and files
  if (argv.length > 1) {
    final realSongs = file(argv[1]), realHighlights = file(argv[2]), realVods = file(argv[3]);
    final realOffsets = argv.length > 4 ? file(argv[4]) : '';
    tool = VodsTool();
    call('load', [realSongs, realHighlights]);
    call('overview', [realVods, realOffsets]);
    final vodFile = VodFile.parse(text(realVods));
    for (final key in vodFile.keys) {
      call('stream', [realVods, realOffsets, vodFile.vodOf(key)!.first.id]);
    }
  }
  print(jsonEncode(cases));
}
