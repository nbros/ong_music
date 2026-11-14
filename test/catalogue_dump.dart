import 'package:ong_music/src/data/catalogue.dart';
import 'package:ong_music/src/data/model.dart';

/// Everything a [Catalogue] holds, as lines of text: every field of every entity, in order, and the answers of the
/// queries that read its indexes (search, counts, lookups). Two catalogues with the same dump are the same catalogue.
List<String> dumpCatalogue(Catalogue c) {
  String ids(Iterable<int> ids) => ids.join(',');
  final out = <String>[
    'hasSongs ${c.hasSongs}',
    for (final h in c.highlights)
      'H ${h.id}|${h.seq}|${h.title}|${h.songKey}|${h.genre}|${h.link}|${h.youtubeId}|${h.requesterId}|'
          '${h.streamDate}|${h.uploadDate}|${h.vocals}|${h.notes}|${c.playOf(h)?.id}|${h.key}',
    for (final p in c.plays)
      'P ${p.id}|${p.loggedMinute}|${p.rowDate}|${p.titleId}|${p.title}|${p.songKey}|${p.genre}|${p.type}|'
          '${p.requesterId}|${p.flag}|${p.streamId}|${p.highlightId}',
    for (final s in c.streams)
      'S ${s.id}|${s.date}|${s.firstPlayId}|${s.playCount}|${s.durationMinutes}|${ids(s.highlightIds)}',
    for (final r in c.requesters)
      'R ${r.id}|${r.name}|${r.folded}|${r.requestCount}|${c.highlightRequestCount(r)}|'
          '${c.requesterNamed(r.name)?.id}|${c.isRequester(r.id, r.folded)}',
    for (final t in c.titles) 'T $t',
    for (final s in c.songs)
      'G ${s.key}|${s.title}|${s.genre}|${ids(s.playIds)}|${ids(s.highlightIds)}|${s.firstPlayed}|${s.lastPlayed}|'
          '${identical(c.song(s.key), s)}',
    'HG ${c.highlightGenreCounts}',
    'PG ${c.playGenreCounts}',
    'K ${c.highlightCountWithKeys({for (final h in c.highlights.take(50)) h.key})}',
  ];
  final requesterId = c.requesters.isEmpty ? null : c.requesters.first.id;
  for (final query in _queries(c)) {
    final h = c.searchHighlights(query: query, requesterId: requesterId, onlyRequester: false);
    out.add(
      'QH $query|${ids(h.ids)}|${h.counts.requester}|${h.counts.keys}|'
      '${[for (final g in Genre.values) h.counts.genre(g)]}',
    );
    final p = c.searchPlays(query: query);
    out.add('QP $query|${ids(p.ids)}|${p.streamCount}|${c.countPlays(query)}');
  }
  return out;
}

/// Queries that touch every searchable field: words of some titles, requester names, genre and type labels.
List<String> _queries(Catalogue c) => {
  '',
  'a',
  'e',
  'piano',
  'loop',
  'game',
  'é',
  for (final g in Genre.values) g.label,
  for (var i = 0; i < c.titles.length; i += 1 + c.titles.length ~/ 20) c.titles[i].split(' ').first,
  for (var i = 0; i < c.requesters.length; i += 1 + c.requesters.length ~/ 10) c.requesters[i].name,
}.toList();
