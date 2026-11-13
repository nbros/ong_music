/// The characters of the catalogue that the fonts of the web app lack: Japanese, Chinese, Korean, Arabic, symbols
/// such as ♪ ☆ →, emoji, and the few Latin letters Roboto does not draw (ǐ). The web engine draws them with fonts it
/// downloads when it first meets them (`ui/font_warm_up.dart` makes that happen at a moment of its choosing).
///
/// Pure Dart: usable from `dart run` scripts and unit tests.
library;

import 'catalogue.dart';
import 'font_coverage.g.dart';
import 'slices.dart';

/// Whether the fonts of the web app (Roboto Regular and Medium, see `tool/gen_font_coverage.py`) draw [codePoint].
bool bundledFontsDraw(int codePoint) {
  // the last range starting at or before the code point
  var low = 0, high = bundledFontRanges.length ~/ 2 - 1, found = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (bundledFontRanges[2 * middle] <= codePoint) {
      found = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return found >= 0 && codePoint <= bundledFontRanges[2 * found + 1];
}

/// Whether [codePoint] is a character the fonts of the web app lack: neither a control character (C0, DEL, C1),
/// which no font draws, nor a surrogate, which is half of a character; within Unicode.
bool isRareCharacter(int codePoint) =>
    codePoint >= 0x20 &&
    !(codePoint >= 0x7F && codePoint <= 0x9F) &&
    !(codePoint >= 0xD800 && codePoint <= 0xDFFF) &&
    codePoint <= 0x10FFFF &&
    !bundledFontsDraw(codePoint);

/// Every code unit below it is a control character or one the fonts draw: what most text is made of (ASCII, the
/// accented letters of Latin-1 and Latin Extended-A) costs one comparison.
final int _firstRare = () {
  var codePoint = 0;
  while (!isRareCharacter(codePoint)) {
    codePoint++;
  }
  return codePoint;
}();

/// Adds the rare characters of [text] (see [isRareCharacter]) to [into]. A surrogate pair is one character; a
/// surrogate alone (a broken text) is none.
///
/// Adds to [emojiBases] the characters [text] asks to be drawn as emoji: those followed by the emoji variation
/// selector (U+FE0F) or the keycap mark (U+20E3), the digits of `1️⃣` included, which are no rare characters.
void addRareCharacters(String text, Set<int> into, [Set<int>? emojiBases]) {
  var previous = -1;
  for (var i = 0; i < text.length; i++) {
    final unit = text.codeUnitAt(i);
    if (unit < _firstRare) {
      previous = unit;
      continue;
    }
    var codePoint = unit;
    if (unit >= 0xD800 && unit <= 0xDBFF && i + 1 < text.length) {
      final next = text.codeUnitAt(i + 1);
      if (next >= 0xDC00 && next <= 0xDFFF) {
        codePoint = 0x10000 + ((unit - 0xD800) << 10) + (next - 0xDC00);
        i++;
      }
    }
    if (isRareCharacter(codePoint)) into.add(codePoint);
    if ((codePoint == 0xFE0F || codePoint == 0x20E3) && previous >= 0 && previous != 0xFE0F) {
      emojiBases?.add(previous);
    }
    previous = codePoint;
  }
}

/// Adds to [into] the rare characters of every text of [catalogue] the app can show: the titles of the plays (a song
/// shows the title of one of its plays or highlights), the titles and notes of the highlights, the names of the
/// requesters; and to [emojiBases] the characters asked to be drawn as emoji (see [addRareCharacters]). In steps (see
/// `runInSlices`): a pause point every [pauseEvery] titles, highlights or requesters.
Iterable<void> addCatalogueCharacters(
  Catalogue catalogue,
  Set<int> into, {
  Set<int>? emojiBases,
  int pauseEvery = rowsPerPause,
}) sync* {
  if (pauseEvery < 1) throw ArgumentError.value(pauseEvery, 'pauseEvery', 'must be at least 1');
  final titles = catalogue.titles;
  for (var i = 0; i < titles.length; i++) {
    addRareCharacters(titles[i], into, emojiBases);
    if (i % pauseEvery == pauseEvery - 1) yield null;
  }
  final highlights = catalogue.highlights;
  for (var i = 0; i < highlights.length; i++) {
    addRareCharacters(highlights[i].title, into, emojiBases);
    addRareCharacters(highlights[i].notes, into, emojiBases);
    if (i % pauseEvery == pauseEvery - 1) yield null;
  }
  final requesters = catalogue.requesters;
  for (var i = 0; i < requesters.length; i++) {
    addRareCharacters(requesters[i].name, into, emojiBases);
    if (i % pauseEvery == pauseEvery - 1) yield null;
  }
}
