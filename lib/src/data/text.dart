/// Text folding, song keys, query tokens and match ranges.
///
/// Pure Dart: usable from isolates, `dart run` scripts and unit tests.
library;

import 'dart:typed_data';

import 'fold_table.g.dart';

Uint16List? _table;

Uint16List _foldTable() {
  final existing = _table;
  if (existing != null) return existing;
  final table = Uint16List(0x10000);
  for (var i = 0; i < table.length; i++) {
    table[i] = i;
  }
  for (var i = 0; i < foldFrom.length; i++) {
    table[foldFrom[i]] = foldTo[i];
  }
  return _table = table;
}

/// Folds case and diacritics, one UTF-16 code unit at a time.
///
/// The result always has the same length as [text], so an offset found in the
/// folded string is valid in the original one (see [matchRanges]).
/// `Élan` → `elan`, `ÇA` → `ca`, `Ø` → `o`; characters that would need more than
/// one unit (`ß`, `æ`, Hangul syllables, characters outside the BMP) are only
/// lowercased or kept as they are.
String fold(String text) {
  final table = _foldTable();
  final units = Uint16List(text.length);
  var changed = false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    final folded = table[unit];
    units[i] = folded;
    if (folded != unit) changed = true;
  }
  return changed ? String.fromCharCodes(units) : text;
}

Map<int, int>? _compositions;

Map<int, int> _compositionTable() =>
    _compositions ??= {for (var i = 0; i < composeFrom.length; i++) composeFrom[i]: composeTo[i]};

bool _isDiacriticalMark(int unit) => unit >= 0x0300 && unit <= 0x036F;

/// Composes "letter + combining diacritical mark" pairs into the precomposed
/// character: `e` followed by U+0301 becomes `é`.
///
/// Some sheet cells are typed with decomposed accents. Left as they are, they
/// would not match a search ([fold] keeps the mark, to preserve the length) and
/// a highlighted hit would end between the letter and its accent. Applied to
/// the sheets when they are parsed and to queries in [tokenize]. A mark with no
/// precomposed form is kept. Text without such marks is returned unchanged.
String composeMarks(String text) {
  var first = -1;
  for (var i = 1; i < text.length; i++) {
    if (_isDiacriticalMark(text.codeUnitAt(i))) {
      first = i;
      break;
    }
  }
  if (first < 0) return text;
  final table = _compositionTable();
  final units = Uint16List(text.length);
  var n = first;
  for (var i = 0; i < first; i++) {
    units[i] = text.codeUnitAt(i);
  }
  for (var i = first; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (n > 0 && _isDiacriticalMark(unit)) {
      final composed = table[units[n - 1] * 0x10000 + unit];
      if (composed != null) {
        units[n - 1] = composed;
        continue;
      }
    }
    units[n++] = unit;
  }
  return String.fromCharCodes(units, 0, n);
}

final _diacriticalMarks = RegExp('[\u0300-\u036F]+');
final _notLetterOrDigit = RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true);
final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _whitespace = RegExp(r'\s+');

/// The key under which plays and highlights of the same song are grouped.
///
/// Case and Latin diacritics are folded ([fold]), loose combining diacritics
/// (U+0300–U+036F) dropped, and every run of characters that are not Unicode
/// letters or digits (or marks attached to them, as in Indic scripts) becomes
/// one space: `"Pokémon - Route 1!"` → `pokemon route 1`. Titles in non-Latin
/// scripts keep their letters. An empty key means "not a song".
String songKey(String title) {
  final key = fold(title).replaceAll(_diacriticalMarks, '').replaceAll(_notLetterOrDigit, ' ').trim();
  return _letterOrDigit.hasMatch(key) ? key : '';
}

/// Collapses runs of whitespace into one space and trims.
String collapseSpaces(String text) => text.replaceAll(_whitespace, ' ').trim();

/// At most this many tokens of a query are used (a pasted paragraph must not
/// cost a full scan per word on every keystroke).
const int maxQueryTokens = 12;

/// Splits a search query into folded tokens (on whitespace, empty ones dropped).
///
/// A row matches a query when every token is a substring of at least one of its
/// searchable fields. Tokens that add no constraint are dropped: duplicates, and
/// tokens contained in another one (a field containing `zelda` contains `zel`).
/// Only the first [maxQueryTokens] remaining tokens are kept.
List<String> tokenize(String query) {
  final all = fold(composeMarks(query)).split(_whitespace).where((token) => token.isNotEmpty).toList(growable: false);
  if (all.length <= 1) return all;
  final kept = <String>[];
  for (var i = 0; i < all.length && kept.length < maxQueryTokens; i++) {
    final token = all[i];
    var redundant = false;
    for (var j = 0; j < all.length && !redundant; j++) {
      if (j == i) continue;
      final other = all[j];
      // equal tokens: keep the first one only
      redundant = other == token ? j < i : other.contains(token);
    }
    if (!redundant) kept.add(token);
  }
  return List.unmodifiable(kept);
}

/// A half-open range `[start, end)` of UTF-16 offsets in a displayed string.
typedef TextRange = ({int start, int end});

/// The ranges of [text] to highlight for the query [tokens] (from [tokenize]).
///
/// Every occurrence of every token is marked; overlapping or adjacent hits are
/// merged, and the result is sorted. Empty when nothing matches.
List<TextRange> matchRanges(String text, List<String> tokens) {
  if (tokens.isEmpty || text.isEmpty) return const [];
  final folded = fold(text);
  final hit = Uint8List(text.length);
  var any = false;
  for (final token in tokens) {
    if (token.isEmpty) continue;
    for (var i = folded.indexOf(token); i >= 0; i = folded.indexOf(token, i + token.length)) {
      hit.fillRange(i, i + token.length, 1);
      any = true;
    }
  }
  if (!any) return const [];
  final ranges = <TextRange>[];
  var start = -1;
  for (var i = 0; i <= hit.length; i++) {
    final on = i < hit.length && hit[i] == 1;
    if (on && start < 0) {
      start = i;
    } else if (!on && start >= 0) {
      ranges.add((start: start, end: i));
      start = -1;
    }
  }
  return ranges;
}

/// A title split on its first `" - "`: `"Zelda - Song of Storms"` gives artist
/// (or work) `Zelda` and track `Song of Storms`. Without separator the artist is
/// empty and the whole title is the track.
typedef SplitTitle = ({String artist, String track});

/// See [SplitTitle].
SplitTitle splitTitle(String title) {
  final i = title.indexOf(' - ');
  return i < 0 ? (artist: '', track: title) : (artist: title.substring(0, i), track: title.substring(i + 3));
}
