/// Fonts cut down to the characters the app needs, from the Google Fonts CSS API.
///
/// `https://fonts.googleapis.com/css2?family=<family>&text=<characters>` answers a `@font-face` whose source is a font
/// (`fonts.gstatic.com/l/font?kit=…`) holding only those of the characters the family draws: the 375 rare characters
/// of the real sheets come in 9 such fonts, 107 KB together, where the web engine's own fallback downloads whole fonts
/// (2.9 MB: Noto Sans KR alone is 2 MB). Above some 800 characters the API answers the family's usual slices instead:
/// a request holds at most [kitLength] characters. For some browsers it never cuts some families down (Noto Color
/// Emoji for Safari and every iPhone browser: the 11 slices; an old Safari: the whole 4.7 MB font): such a kit is not
/// to be had ([FontKitUnavailable]), and the engine's own fallback draws its characters, as without kits.
///
/// Which family draws a character is decided here, by the families it is sent to and their order ([kitGroups]): a
/// Japanese (or Chinese) title gets the shapes of Noto Sans JP, a Han character Noto Sans JP lacks those of Noto Sans
/// SC; a character the colour emoji font draws gets it, as the engine's own fallback gives it (▶ ♥ ✔ ❤ ㊗ too, whose
/// default presentation is text: the engine tries that font right after Roboto); other symbols (★ ☆ ♪ →) the symbol
/// fonts.
///
/// Pure Dart (and `package:http`): usable from unit tests.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'emoji.g.dart';

/// A family of Google Fonts the rare characters of a kind are asked from: [takes] says whether a character goes to
/// it, given the characters the texts ask to be drawn as emoji.
typedef KitGroup = ({String name, String family, bool Function(int codePoint, Set<int> emojiBases) takes});

bool _within(int c, int first, int last) => c >= first && c <= last;

/// Hangul syllables and jamo.
bool isHangul(int c) =>
    _within(c, 0xAC00, 0xD7AF) ||
    _within(c, 0x1100, 0x11FF) ||
    _within(c, 0x3130, 0x318F) ||
    _within(c, 0xA960, 0xA97F) ||
    _within(c, 0xD7B0, 0xD7FF);

/// Han ideographs (unified, extensions, compatibility).
bool isHan(int c) =>
    _within(c, 0x3400, 0x4DBF) ||
    _within(c, 0x4E00, 0x9FFF) ||
    _within(c, 0xF900, 0xFAFF) ||
    _within(c, 0x20000, 0x3FFFF);

/// What the fonts of Japan, Korea and China all draw, each its own way: CJK radicals, enclosed letters and months
/// (㈱ ㊗), compatibility signs (㎡), bopomofo, vertical and compatibility forms.
bool isCjkShared(int c) =>
    _within(c, 0x2E80, 0x2FDF) ||
    _within(c, 0x3100, 0x312F) ||
    _within(c, 0x31A0, 0x31BF) ||
    _within(c, 0x3200, 0x33FF) ||
    _within(c, 0xFE10, 0xFE1F) ||
    _within(c, 0xFE30, 0xFE4F);

/// What a Japanese title is written with: kana, CJK punctuation, full- and half-width forms, Han, and the signs the
/// CJK fonts share.
bool isJapanese(int c) =>
    _within(c, 0x3000, 0x30FF) ||
    _within(c, 0x31F0, 0x31FF) ||
    _within(c, 0xFF00, 0xFFEF) ||
    isHan(c) ||
    isCjkShared(c);

/// The Arabic script.
bool isArabic(int c) =>
    _within(c, 0x0600, 0x06FF) ||
    _within(c, 0x0750, 0x077F) ||
    _within(c, 0x08A0, 0x08FF) ||
    _within(c, 0xFB50, 0xFDFF) ||
    _within(c, 0xFE70, 0xFEFF);

/// Whether [codePoint] beyond ASCII is one the colour emoji font draws (the Unicode property Emoji: ✨ 🌈, and ▶ ♥ ✔
/// ❤ ㊗ whose default presentation is text).
bool isEmoji(int codePoint) {
  var low = 0, high = emojiRanges.length ~/ 2 - 1, found = -1;
  while (low <= high) {
    final middle = (low + high) >> 1;
    if (emojiRanges[2 * middle] <= codePoint) {
      found = middle;
      low = middle + 1;
    } else {
      high = middle - 1;
    }
  }
  return found >= 0 && codePoint <= emojiRanges[2 * found + 1];
}

/// What makes an emoji sequence: the joiner, the variation selectors, the keycap mark, skin tones, tags. Sent with the
/// emoji (a sequence is drawn by one font) and to Noto Sans.
bool isEmojiPart(int c) =>
    c == 0x200D ||
    c == 0xFE0E ||
    c == 0xFE0F ||
    c == 0x20E3 ||
    _within(c, 0x1F3FB, 0x1F3FF) ||
    _within(c, 0xE0020, 0xE007F);

/// Arrows, mathematical and technical signs, shapes, symbols, dingbats, and the symbols beyond the BMP.
bool isSymbol(int c) => _within(c, 0x2190, 0x2BFF) || c >= 0x1F000 && c < 0x20000;

/// Symbols the colour emoji font does not draw (★ ☆ ♪ →): the symbol fonts.
bool _isTextSymbol(int c) => isSymbol(c) && !isEmoji(c);

bool _isOther(int c) => !isHangul(c) && !isJapanese(c) && !isArabic(c) && !isSymbol(c) && !isEmoji(c);

/// The families, in the order the app's text tries them (after Roboto): a character goes to every family whose test
/// takes it; the first of them that draws it draws it. A character of the colour emoji goes to it alone: where the API
/// gives no kit of it (Safari), the engine's own fallback draws it, in colour, as without kits.
///
/// Scripts with no family here (Hebrew, Thai, the scripts of India, Armenian, Georgian, Ethiopic, Khmer, Tibetan…) go
/// to Noto Sans, which does not draw them: the engine's own fallback draws them, as without kits.
final List<KitGroup> kitGroups = [
  (
    name: 'Ong Emoji',
    family: 'Noto Color Emoji',
    takes: (c, bases) => isEmoji(c) || isEmojiPart(c) || bases.contains(c),
  ),
  (name: 'Ong JP', family: 'Noto Sans JP', takes: (c, _) => isJapanese(c) && !isEmoji(c)),
  (name: 'Ong KR', family: 'Noto Sans KR', takes: (c, _) => (isHangul(c) || isCjkShared(c)) && !isEmoji(c)),
  (name: 'Ong SC', family: 'Noto Sans SC', takes: (c, _) => (isHan(c) || isCjkShared(c)) && !isEmoji(c)),
  (name: 'Ong Arabic', family: 'Noto Sans Arabic', takes: (c, _) => isArabic(c) && !isEmoji(c)),
  (name: 'Ong Sans', family: 'Noto Sans', takes: (c, _) => _isOther(c) || _isTextSymbol(c)),
  (name: 'Ong Symbols 2', family: 'Noto Sans Symbols 2', takes: (c, _) => _isTextSymbol(c)),
  (name: 'Ong Symbols', family: 'Noto Sans Symbols', takes: (c, _) => _isTextSymbol(c)),
  (name: 'Ong Math', family: 'Noto Sans Math', takes: (c, _) => _isTextSymbol(c)),
];

/// The most characters asked for in one request: the API cuts fonts down up to some 800.
const int kitLength = 500;

/// The most requests per family: [kitLength] times this many characters of a kind at most; more are left to the
/// engine's own fallback.
const int kitsPerGroup = 3;

/// The largest font a kit may be: a cut-down font of [kitLength] characters weighs some 100 KB (Noto Sans JP, 375
/// characters: 63 KB in WOFF2, 81 KB in WOFF); a larger one was not cut down (an old Safari gets the whole 4.7 MB of
/// Noto Color Emoji).
const int maxKitBytes = 512 * 1024;

/// A font to ask for: [text] of [family], registered as [name].
typedef FontKit = ({String name, String family, String text});

/// The family names of every kit there may be, in the order the text must try them.
final List<String> fontKitFamilies = [
  for (final group in kitGroups)
    for (var i = 1; i <= kitsPerGroup; i++) '${group.name} $i',
];

/// The kits that draw [codePoints] (rare characters, see `rare_characters.dart`) and [emojiBases] (characters the
/// texts ask to be drawn as emoji): for each family of [kitGroups], the characters it takes, in ascending order,
/// [kitLength] at a time, at most [kitsPerGroup] kits.
///
/// With [planned], the kits planned already (for an earlier catalogue: the highlights before the Songs sheet), only
/// the characters a family takes that its kits planned do not hold, in kits numbered after them, within the same
/// [kitsPerGroup].
List<FontKit> planFontKits(
  Iterable<int> codePoints, {
  Set<int> emojiBases = const {},
  List<FontKit> planned = const [],
}) {
  final sorted = {...codePoints, ...emojiBases}.toList()..sort();
  return [
    for (final group in kitGroups)
      ...() {
        final before = [
          for (final kit in planned)
            if (kit.family == group.family) kit,
        ];
        final held = {for (final kit in before) ...kit.text.runes};
        final taken = sorted.where((c) => group.takes(c, emojiBases) && !held.contains(c)).toList();
        return [
          for (var i = 0; i * kitLength < taken.length && before.length + i < kitsPerGroup; i++)
            (
              name: '${group.name} ${before.length + i + 1}',
              family: group.family,
              text: String.fromCharCodes(taken.skip(i * kitLength).take(kitLength)),
            ),
        ];
      }(),
  ];
}

/// The family names of [kits], in the order the text must try them ([fontKitFamilies]).
List<String> kitFamiliesOf(Iterable<FontKit> kits) {
  final names = {for (final kit in kits) kit.name};
  return [
    for (final name in fontKitFamilies)
      if (names.contains(name)) name,
  ];
}

/// The address of the CSS that describes [kit].
Uri kitCssUri(FontKit kit) => Uri.https('fonts.googleapis.com', '/css2', {'family': kit.family, 'text': kit.text});

final RegExp _source = RegExp(r"src:\s*url\((https://fonts\.gstatic\.com/l/font\?[^)\s]+)\)");

/// The address of the font a CSS of the API describes, or null when it describes none, or several (the family's
/// slices: the font was not cut down).
Uri? kitFontUri(String css) {
  final sources = _source.allMatches(css).toList();
  if (sources.length != 1 || '@font-face'.allMatches(css).length != 1) return null;
  return Uri.parse(sources.single.group(1)!);
}

/// Thrown when a kit cannot be had now (the network, the server): another attempt may get it.
class FontKitException implements Exception {
  const FontKitException(this.message);

  final String message;

  @override
  String toString() => '$runtimeType: $message';
}

/// Thrown when a kit cannot be had at all this way: the API gives this browser no cut-down font of the family (its
/// slices, or a font larger than [maxKitBytes]). Asking again gives the same answer.
final class FontKitUnavailable extends FontKitException {
  const FontKitUnavailable(super.message);
}

/// Downloads kits: the CSS, then the font it names.
final class FontKitDownloader {
  FontKitDownloader(this._client);

  final http.Client _client;

  /// The bytes of the font of [kit]. Throws [FontKitUnavailable] when the API has no cut-down font of it for this
  /// browser, [FontKitException] (or the client's own errors) when it cannot have it now. A font larger than
  /// [maxKitBytes] is abandoned as soon as it shows (its announced length, or the bytes read).
  Future<Uint8List> download(FontKit kit) async {
    final css = await _client.get(kitCssUri(kit));
    if (css.statusCode != 200) throw FontKitException('HTTP ${css.statusCode} for the CSS of ${kit.name}');
    final font = kitFontUri(css.body);
    if (font == null) throw FontKitUnavailable('No cut-down font of ${kit.family} for this browser');
    final abort = Completer<void>();
    final response = await _client.send(http.AbortableRequest('GET', font, abortTrigger: abort.future));
    final tooLarge = FontKitUnavailable('The font of ${kit.name} is larger than $maxKitBytes bytes: not cut down');
    try {
      if (response.statusCode != 200) throw FontKitException('HTTP ${response.statusCode} for the font of ${kit.name}');
      if ((response.contentLength ?? 0) > maxKitBytes) throw tooLarge;
      final bytes = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        bytes.add(chunk);
        if (bytes.length > maxKitBytes) throw tooLarge;
      }
      if (bytes.isEmpty) throw FontKitException('Empty font for ${kit.name}');
      return bytes.takeBytes();
    } on FontKitException {
      if (!abort.isCompleted) abort.complete();
      rethrow;
    }
  }
}
