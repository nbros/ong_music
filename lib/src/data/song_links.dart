/// The link of each song to its original: the YouTube video the moderators link its title to in the Songs sheet (the
/// Ong Log).
///
/// Pure Dart. The CSV export of the sheet drops the links of its cells; the daily snapshot job reads them from the
/// xlsx export (`tool/song_links.py`) and publishes `song_links.tsv` on the branch `sheets-snapshot`, downloaded and
/// kept as the data files are (`DataFile.songLinks`). A line of it is one title as written with the video of its most
/// recent row with a link (the moderators replace dead links), in the order of those rows. Here the lines are grouped
/// by song ([songKey]), the last line of a song winning: its most recent link, which its plays without a link have
/// too. Only videos: the app makes their address itself ([SongLink.url]), it never opens an address of the sheet.
library;

import 'slices.dart';
import 'text.dart';

/// The original of a song: a YouTube video, from its start or from [startSeconds].
final class SongLink {
  /// The link to video [youtubeId] (11 characters) from [startSeconds] (from the start when null).
  const SongLink(this.youtubeId, [this.startSeconds]);

  /// The link a cell `link` of `song_links.tsv` gives: `<id>`, or `<id>?t=<seconds>`. Null for anything else (an
  /// address among them: the app never opens an address of the sheet).
  static SongLink? tryParse(String cell) {
    final m = _cell.firstMatch(cell.trim());
    if (m == null) return null;
    final start = m[2] == null ? null : int.tryParse(m[2]!);
    return SongLink(m[1]!, start == 0 ? null : start);
  }

  final String youtubeId;
  final int? startSeconds;

  /// `https://youtu.be/<id>`, with `?t=<seconds>` when it starts later: what opens it and what is copied.
  String get url => 'https://youtu.be/$youtubeId${startSeconds == null ? '' : '?t=$startSeconds'}';

  /// The address as the fiche shows it, short: `youtu.be/<id>`.
  String get shortText => 'youtu.be/$youtubeId';

  @override
  bool operator ==(Object other) =>
      other is SongLink && other.youtubeId == youtubeId && other.startSeconds == startSeconds;

  @override
  int get hashCode => Object.hash(youtubeId, startSeconds);

  @override
  String toString() => 'SongLink($url)';
}

final _cell = RegExp(r'^([A-Za-z0-9_-]{11})(?:\?t=(\d{1,6}))?$');

/// The content of `song_links.tsv`: the link of each song.
///
/// Read tolerantly, as `vods.tsv` is: a line that does not read is left out, never an error for the whole file. The
/// file: UTF-8, tab-separated, a header line, then one line per title: `link`, `title`. Lines beginning with `#` and
/// blank lines are ignored.
final class SongLinks {
  SongLinks._(this._bySong);

  /// No link.
  static final empty = SongLinks._(const {});

  /// Whether [text] is a `song_links.tsv` at all: its first line that is neither blank nor a comment is the header,
  /// which begins with the cells `link`, `title` (trimmed, any case). Anything else (a page of an error answered with
  /// status 200) is no file: a download of it counts as failed.
  static bool isFile(String text) {
    for (var line in text.split('\n')) {
      if (line.startsWith('﻿')) line = line.substring(1);
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      final cells = line.split('\t');
      return cells.length >= 2 && cells[0].trim().toLowerCase() == 'link' && cells[1].trim().toLowerCase() == 'title';
    }
    return false;
  }

  /// Reads [text] at once ([SongLinksLoad] does it in steps; see [isFile]: without its header, nothing is read).
  factory SongLinks.parse(String text) {
    final load = SongLinksLoad(text);
    while (load.step()) {}
    return load.links;
  }

  final Map<String, SongLink> _bySong;

  /// The link of the song of key [key] (`Play.songKey`, `Highlight.songKey`, `Song.key`), or null.
  SongLink? of(String key) => key.isEmpty ? null : _bySong[key];

  /// Number of songs with a link.
  int get length => _bySong.length;

  bool get isEmpty => _bySong.isEmpty;
}

/// Reads a `song_links.tsv` in steps of [rowsPerPause] lines ([step]), so that the thread can draw frames between two
/// of them: some 10,000 lines, a few dozen milliseconds in one go, too long for a frame of the page on the web (see
/// `runWhenIdle`). Each song gets the link of its last line ([songKey] of the titles).
final class SongLinksLoad {
  /// A load of [text], nothing read yet.
  SongLinksLoad(this._text);

  final String _text;
  List<String>? _lines;
  int _next = 0;
  bool _header = false;
  final _bySong = <String, SongLink>{};

  /// Reads the next lines; false once the whole text is read ([links] is then complete).
  bool step() {
    final lines = _lines;
    if (lines == null) {
      _lines = _text.split('\n');
      return true;
    }
    final end = _next + rowsPerPause < lines.length ? _next + rowsPerPause : lines.length;
    for (; _next < end; _next++) {
      _read(lines[_next]);
    }
    return _next < lines.length;
  }

  void _read(String line) {
    if (line.startsWith('﻿')) line = line.substring(1);
    if (line.endsWith('\r')) line = line.substring(0, line.length - 1);
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) return;
    if (!_header) {
      if (!SongLinks.isFile(line)) {
        // no file: nothing more is read
        _next = _lines!.length;
        return;
      }
      _header = true;
      return;
    }
    final tab = line.indexOf('\t');
    if (tab < 0) return;
    final link = SongLink.tryParse(line.substring(0, tab));
    final key = songKey(line.substring(tab + 1));
    if (link == null || key.isEmpty) return;
    _bySong[key] = link;
  }

  /// The links read so far: all of them once [step] returned false.
  SongLinks get links => _bySong.isEmpty ? SongLinks.empty : SongLinks._(_bySong);
}
