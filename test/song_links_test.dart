// song_links.tsv: a line per title of the Songs sheet with the YouTube video of its most recent row with a link; one
// link per song, that of its last line; only videos, never an address of the sheet; read tolerantly.
import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/slices.dart';
import 'package:ong_music/src/data/song_links.dart';
import 'package:ong_music/src/data/text.dart';

/// A file of [lines] (`link`, `title`) under its header.
String _file(List<String> lines) => 'link\ttitle\n${lines.join('\n')}\n';

SongLinks _parse(List<String> lines) => SongLinks.parse(_file(lines));

String? _urlOf(SongLinks links, String title) => links.of(songKey(title))?.url;

void main() {
  group('a link', () {
    test('a video id: the address the app makes, opened and copied; its short form', () {
      final link = SongLink.tryParse('dQw4w9WgXcQ')!;
      expect(link.youtubeId, 'dQw4w9WgXcQ');
      expect(link.startSeconds, isNull);
      expect(link.url, 'https://youtu.be/dQw4w9WgXcQ');
      expect(link.shortText, 'youtu.be/dQw4w9WgXcQ');
    });

    test('a start time: in the address, not in its short form', () {
      final link = SongLink.tryParse(' dQw4w9WgXcQ?t=90 ')!;
      expect(link.startSeconds, 90);
      expect(link.url, 'https://youtu.be/dQw4w9WgXcQ?t=90');
      expect(link.shortText, 'youtu.be/dQw4w9WgXcQ');
      expect(SongLink.tryParse('dQw4w9WgXcQ?t=0'), SongLink.tryParse('dQw4w9WgXcQ'), reason: 't=0 is the start');
      expect(SongLink.tryParse('dQw4w9WgXcQ?t=90'), isNot(SongLink.tryParse('dQw4w9WgXcQ')));
    });

    test('anything else: no link, an address among them (the app never opens an address of the sheet)', () {
      for (final cell in [
        '',
        'Moana',
        'dQw4w9WgXc',
        'dQw4w9WgXcQQ',
        'dQw4w9WgXc!',
        'dQw4w9WgXcQ?t=',
        'dQw4w9WgXcQ?t=1m30s',
        'dQw4w9WgXcQ&t=90',
        'https://youtu.be/dQw4w9WgXcQ',
        'https://www.youtube.com/watch?v=dQw4w9WgXcQ',
        'https://soundcloud.com/artist/track',
        'javascript:alert(1)',
      ]) {
        expect(SongLink.tryParse(cell), isNull, reason: cell);
      }
    });
  });

  group('the file', () {
    test('without its header: no file, nothing read', () {
      expect(SongLinks.isFile('<html>Sign in</html>'), isFalse);
      expect(SongLinks.isFile(''), isFalse);
      expect(SongLinks.isFile('dQw4w9WgXcQ\tSong'), isFalse);
      expect(SongLinks.parse('dQw4w9WgXcQ\tSong').isEmpty, isTrue);
      expect(SongLinks.parse('<html>\ndQw4w9WgXcQ\tSong\n').isEmpty, isTrue);
      expect(SongLinks.isFile('﻿# a comment\n\nLink\tTitle\n'), isTrue);
      expect(SongLinks.parse(_file([])).isEmpty, isTrue, reason: 'the header alone: a file without any link');
    });

    test('a line that does not read is left out, not the file', () {
      final links = _parse([
        'dQw4w9WgXcQ\tSong A',
        'not a link\tSong B',
        'https://youtu.be/ccccccccccc\tSong C',
        'ddddddddddd',
        'eeeeeeeeeee\t!!!',
        '# a comment',
        '',
        'fffffffffff?t=12\tSong F\r',
        'ggggggggggg\tSong\twith a tab',
      ]);
      expect(links.length, 3);
      expect(_urlOf(links, 'Song A'), 'https://youtu.be/dQw4w9WgXcQ');
      expect(_urlOf(links, 'Song C'), isNull);
      expect(_urlOf(links, 'Song F'), 'https://youtu.be/fffffffffff?t=12', reason: 'a line ending with CR');
      expect(_urlOf(links, 'Song with a tab'), 'https://youtu.be/ggggggggggg');
      expect(links.of(''), isNull);
    });
  });

  group('one link per song', () {
    test('the titles of one song (its key: case, accents, punctuation, spaces): the last line wins', () {
      final links = _parse([
        'aaaaaaaaaaa\tPokémon - Route 1',
        'bbbbbbbbbbb\tSomething else',
        'ccccccccccc\tpokemon  route 1!',
      ]);
      expect(links.length, 2);
      expect(_urlOf(links, 'POKEMON: Route 1'), 'https://youtu.be/ccccccccccc');
      expect(
        _urlOf(_parse(['ccccccccccc\tpokemon route 1', 'aaaaaaaaaaa\tPokémon - Route 1']), 'Pokemon Route 1'),
        'https://youtu.be/aaaaaaaaaaa',
      );
    });

    test('a later line that does not read leaves the link of the one before', () {
      expect(_urlOf(_parse(['aaaaaaaaaaa\tSong', 'Moana\tsong']), 'Song'), 'https://youtu.be/aaaaaaaaaaa');
    });

    test('another song, another link; a song without any: none', () {
      final links = _parse(['aaaaaaaaaaa\tSong A', 'bbbbbbbbbbb?t=30\tSong B']);
      expect(_urlOf(links, 'Song A'), 'https://youtu.be/aaaaaaaaaaa');
      expect(_urlOf(links, 'Song B'), 'https://youtu.be/bbbbbbbbbbb?t=30');
      expect(_urlOf(links, 'Song C'), isNull);
    });
  });

  test('read in steps of rowsPerPause lines: the same links as at once', () {
    final lines = [for (var i = 0; i < 1000; i++) '${'v$i'.padRight(11, 'x')}\tSong ${i % 300}'];
    final load = SongLinksLoad(_file(lines));
    var steps = 0;
    while (load.step()) {
      steps++;
    }
    expect(steps, 1 + (lines.length + 2) ~/ rowsPerPause, reason: 'the split, then $rowsPerPause lines a step');
    final atOnce = _parse(lines);
    expect(load.links.length, 300);
    for (var i = 0; i < 300; i++) {
      expect(load.links.of(songKey('Song $i')), atOnce.of(songKey('Song $i')));
      final last = i + 900 < 1000 ? i + 900 : i + 600;
      expect(load.links.of(songKey('Song $i'))!.youtubeId, 'v$last'.padRight(11, 'x'), reason: 'the last line');
    }
  });
}
