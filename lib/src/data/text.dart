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
  // ASCII (most titles and names): the table only maps A-Z there, as toLowerCase does. Avoids building the string
  // from a code unit list, which is slow on the web.
  var upper = false;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit >= 0x80) return _foldTableLookup(text);
    if (unit >= 0x41 && unit <= 0x5A) upper = true;
  }
  return upper ? text.toLowerCase() : text;
}

String _foldTableLookup(String text) {
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
  // Copies the unchanged runs as substrings (building megabytes of text from a code unit list is slow on the web).
  // text[start, i) is still to be copied, unless [pending] holds the composed form of text[i - 1].
  final out = StringBuffer();
  var start = 0;
  var pending = -1;
  for (var i = first; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (_isDiacriticalMark(unit)) {
      final composed = table[(pending >= 0 ? pending : text.codeUnitAt(i - 1)) * 0x10000 + unit];
      if (composed != null) {
        if (pending < 0) out.write(text.substring(start, i - 1));
        pending = composed;
        continue;
      }
    }
    if (pending >= 0) {
      out.writeCharCode(pending);
      pending = -1;
      start = i;
    }
  }
  if (pending >= 0) {
    out.writeCharCode(pending);
  } else {
    out.write(text.substring(start));
  }
  return out.toString();
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
  final folded = fold(title);
  return _asciiSongKey(folded) ?? _unicodeSongKey(folded);
}

String _unicodeSongKey(String folded) {
  final key = folded.replaceAll(_diacriticalMarks, '').replaceAll(_notLetterOrDigit, ' ').trim();
  return _letterOrDigit.hasMatch(key) ? key : '';
}

bool _isAsciiLetterOrDigit(int unit) => (unit >= 0x61 && unit <= 0x7A) || (unit >= 0x30 && unit <= 0x39);

/// [songKey] of a folded ASCII string without regular expressions (slow on
/// native platforms), or null when [folded] is not ASCII. After [fold], the
/// only ASCII letters and digits are `a-z` and `0-9`.
String? _asciiSongKey(String folded) {
  var words = 0;
  var inWord = false;
  var clean = true; // words separated by single spaces, nothing else
  for (var i = 0; i < folded.length; i++) {
    final unit = folded.codeUnitAt(i);
    if (unit >= 0x80) return null;
    if (_isAsciiLetterOrDigit(unit)) {
      if (!inWord) words++;
      inWord = true;
    } else {
      if (unit != 0x20 || !inWord) clean = false;
      inWord = false;
    }
  }
  if (words == 0) return '';
  if (clean && inWord) return folded;
  final out = StringBuffer();
  var start = -1;
  for (var i = 0; i <= folded.length; i++) {
    if (i < folded.length && _isAsciiLetterOrDigit(folded.codeUnitAt(i))) {
      if (start < 0) start = i;
    } else if (start >= 0) {
      if (out.isNotEmpty) out.write(' ');
      out.write(folded.substring(start, i));
      start = -1;
    }
  }
  return out.toString();
}

/// Collapses runs of whitespace into one space and trims.
String collapseSpaces(String text) {
  // Most cells have nothing to collapse: check that without the regular expression (slow on native platforms).
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if ((unit <= 0x20 || unit >= 0x85) && _isSpace(unit)) {
      if (unit != 0x20 || i == 0 || i == text.length - 1 || text.codeUnitAt(i - 1) == 0x20) {
        return text.replaceAll(_whitespace, ' ').trim();
      }
    }
  }
  return text;
}

/// Whether [unit] is whitespace for [String.trim]: [isRegExpSpace] or U+0085.
bool _isSpace(int unit) => unit == 0x85 || isRegExpSpace(unit);

/// Whether the UTF-16 code unit [unit] matches `\s` in a [RegExp].
bool isRegExpSpace(int unit) =>
    (unit >= 0x09 && unit <= 0x0D) ||
    unit == 0x20 ||
    unit == 0xA0 ||
    unit == 0x1680 ||
    (unit >= 0x2000 && unit <= 0x200A) ||
    unit == 0x2028 ||
    unit == 0x2029 ||
    unit == 0x202F ||
    unit == 0x205F ||
    unit == 0x3000 ||
    unit == 0xFEFF;

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
