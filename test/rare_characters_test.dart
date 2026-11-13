import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/rare_characters.dart';

import 'fixtures.dart';

/// [codePoints] as a text, in ascending order.
String charactersText(Iterable<int> codePoints) => String.fromCharCodes(codePoints.toList()..sort());

/// The rare characters of [text], as a text in ascending order.
String rareOf(String text) {
  final set = <int>{};
  addRareCharacters(text, set);
  return charactersText(set);
}

void main() {
  group('the fonts of the web app', () {
    test('draw Latin, Greek and Cyrillic text, its punctuation and currency signs', () {
      for (final c in 'Aaz09 éèçàœŒßÆøŁřőžİı ΑΩαωάΐ АЯаяЁёЖж ‘’“”–—…•€£¥'.runes) {
        expect(bundledFontsDraw(c), isTrue, reason: String.fromCharCode(c));
      }
    });

    test('lack Japanese, Chinese, Korean, Arabic, the symbols of the sheets, emoji, and a few Latin letters', () {
      for (final c in 'あア中한ا♪☆♡→✨🌈🎶ǐǒʻ'.runes) {
        expect(bundledFontsDraw(c), isFalse, reason: String.fromCharCode(c));
      }
    });

    test('ranges: the first and last code point of a range are in it, those around it are not', () {
      // 0x0020–0x007E and 0x00A0–0x017F are ranges of the table (see font_coverage.g.dart)
      expect([0x1F, 0x20, 0x7E, 0x7F, 0x9F, 0xA0, 0x17F, 0x180].map(bundledFontsDraw), [
        false,
        true,
        true,
        false,
        false,
        true,
        true,
        false,
      ]);
      expect(bundledFontsDraw(0x10FFFF), isFalse);
      expect(bundledFontsDraw(-1), isFalse);
    });
  });

  group('rare characters', () {
    test('Japanese, Chinese, Korean, Arabic, symbols and emoji are collected, once each', () {
      expect(rareOf('東方 - 月に叫ぶ (ピアノ) 한국 العربية ♪☆♡→ 🌈🎶 東方'), charactersText('東方月に叫ぶピアノ한국العربية♪☆♡→🌈🎶'.runes));
    });

    test('nothing of Latin, Greek or Cyrillic text that the fonts draw', () {
      expect(rareOf('Zelda - Song of Storms, Ça déménage! Ωμέγα Жизнь “quoted” – 5 € …'), isEmpty);
    });

    test('a surrogate pair is one character; a surrogate alone is none', () {
      final set = <int>{};
      addRareCharacters('a🎶b\uD83Cc\uDF08d', set);
      expect(set, {0x1F3B6});
      addRareCharacters('\uD83C', set);
      addRareCharacters('\uDF08', set);
      expect(set, {0x1F3B6});
    });

    test('combining marks: those the fonts draw are not collected, the others are', () {
      // e + U+0301 (acute, drawn by Roboto); か + U+3099 (Japanese voicing mark); क + U+094D (Devanagari virama)
      expect(rareOf('é'), isEmpty);
      expect(rareOf('が'), charactersText([0x304B, 0x3099]));
      expect(rareOf('क्'), charactersText([0x0915, 0x094D]));
    });

    test('the characters a text asks to draw as emoji: before U+FE0F or a keycap mark, ASCII digits included', () {
      final set = <int>{}, bases = <int>{};
      addRareCharacters('I \u2764\uFE0F it, 1\uFE0F\u20E3 and #\u20E3, ❤ plain', set, bases);
      expect(bases, {0x2764, 0x31, 0x23});
      expect(set, containsAll([0x2764, 0xFE0F, 0x20E3]));
      expect(set, isNot(contains(0x31)), reason: 'a digit is no rare character');
      final none = <int>{};
      addRareCharacters('\uFE0F first, then plain ❤', <int>{}, none);
      expect(none, isEmpty);
    });

    test('control characters are not collected (no font draws them), nor characters beyond Unicode', () {
      expect(rareOf('a\nb\tc\u0085d\u007F'), isEmpty);
      expect(isRareCharacter(0x110000), isFalse);
      expect(isRareCharacter(0x1F3B6), isTrue);
    });

    test('of a catalogue: titles of plays and highlights, notes of highlights, names of requesters', () {
      final catalogue = catalogueOf(
        highlights: [
          hRow(title: 'Video 東', requester: '한', notes: 'Played ♪ ♪ \u2764\uFE0F'),
          // not shown: the link, the dates, the genre
          hRow(order: '2', title: 'Plain', link: 'https://example.com/月', stream: '2024-01-01'),
        ],
        songs: [
          start('2024-01-01'),
          sRow(date: '2024-01-01 20:00:00', title: 'Song 🎶', requester: 'ا'),
          // not shown as written: the notes of a play (its flag), its type
          sRow(date: '2024-01-01 20:10:00', title: 'Other', notes: '☆', type: '→'),
        ],
      );
      final set = <int>{}, bases = <int>{};
      addCatalogueCharacters(catalogue, set, emojiBases: bases).forEach((_) {});
      expect(bases, {0x2764});
      expect(charactersText(set), charactersText('東한♪🎶ا\u2764\uFE0F'.runes));
    });

    test('of a catalogue, in steps: a pause point every so many titles, highlights or requesters', () {
      final catalogue = catalogueOf(
        highlights: [for (var i = 1; i <= 5; i++) hRow(order: '$i', title: 'Video $i 東', requester: 'r$i')],
        songs: [
          start('2024-01-01'),
          for (var i = 0; i < 7; i++) sRow(date: '2024-01-01 20:0$i:00', title: 'Song $i', requester: 'r$i'),
        ],
      );
      // 7 titles, 5 highlights, 7 requesters: pauses after the 2nd, 4th and 6th of each loop
      final set = <int>{};
      expect(addCatalogueCharacters(catalogue, set, pauseEvery: 2).length, 3 + 2 + 3);
      expect(set, {0x6771});
      expect(addCatalogueCharacters(catalogue, <int>{}).length, 0);
      expect(() => addCatalogueCharacters(catalogue, set, pauseEvery: 0).length, throwsArgumentError);
    });
  });
}
