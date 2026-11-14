import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ong_music/src/data/font_kits.dart';
import 'package:ong_music/src/web/font_network.dart';

/// The text of the kit named [name] in [kits], or null.
String? textOf(List<FontKit> kits, String name) => kits.where((k) => k.name == name).firstOrNull?.text;

/// A CSS of the API describing one cut-down font at [url].
String cssOf(String url) =>
    "@font-face {\n  font-family: 'Noto Sans JP';\n  font-style: normal;\n  font-weight: 400;\n"
    "  src: url($url) format('woff2');\n  unicode-range: U+3042;\n}\n";

void main() {
  group('the kits', () {
    test(
      'a later plan: the characters the kits planned already hold are left out, the next kits numbered after them',
      () {
        final first = planFontKits('あ한'.runes);
        expect([for (final k in first) '${k.name}: ${k.text}'], ['Ong JP 1: あ', 'Ong KR 1: 한']);
        final more = planFontKits('あい한봄東'.runes, planned: first);
        expect([for (final k in more) '${k.name}: ${k.text}'], ['Ong JP 2: い東', 'Ong KR 2: 봄', 'Ong SC 1: 東']);
        expect(planFontKits('あ한'.runes, planned: first), isEmpty, reason: 'nothing new');
        // never more than kitsPerGroup kits of a family: what does not fit is left to the engine
        final many = [for (var i = 0; i < kitLength * kitsPerGroup; i++) 0x4E00 + i];
        final full = planFontKits(many);
        expect(planFontKits([...many, 0x9FA0], planned: full).where((k) => k.family == 'Noto Sans SC'), isEmpty);
      },
    );

    // Japanese, Korean, Chinese only, Arabic, signs the CJK fonts share (radical, bopomofo, enclosed, compatibility,
    // vertical forms), symbols the colour emoji does not draw, symbols it draws though text by default (▶ ♥ ✔ ❤ ㊗),
    // emoji and the variation selector, Latin letters Roboto lacks
    final kits = planFontKits('東あア「한铁ا⺀ㄅ㈱㎡︐︵♪☆→▶♥✔❤㊗✨🌈\uFE0Fǐʻ'.runes);

    test('kana, CJK punctuation, Han and the shared CJK signs go to Noto Sans JP; Han and the shared signs to Noto '
        'Sans SC too (for those JP lacks)', () {
      expect(textOf(kits, 'Ong JP 1'), '⺀「あアㄅ㈱㎡東铁︐︵');
      expect(textOf(kits, 'Ong SC 1'), '⺀ㄅ㈱㎡東铁︐︵');
    });

    test('Hangul and the shared CJK signs to Noto Sans KR, Arabic to Noto Sans Arabic', () {
      expect(textOf(kits, 'Ong KR 1'), '⺀ㄅ㈱㎡한︐︵');
      expect(textOf(kits, 'Ong Arabic 1'), 'ا');
    });

    test('what the colour emoji draws to it alone, as the engine gives it (▶ ♥ ✔ ❤ ㊗ too, text by default); the '
        'other symbols to the symbol fonts and Noto Sans', () {
      expect(textOf(kits, 'Ong Emoji 1'), '▶♥✔✨❤㊗\uFE0F🌈');
      for (final name in ['Ong Symbols 2 1', 'Ong Symbols 1', 'Ong Math 1']) {
        expect(textOf(kits, name), '→☆♪', reason: name);
      }
    });

    test(
      'anything else (Latin letters Roboto lacks, modifier letters, joiners) to Noto Sans, with the text symbols',
      () {
        expect(textOf(kits, 'Ong Sans 1'), 'ǐʻ→☆♪\uFE0F');
      },
    );

    test('characters a text asks to draw as emoji (the digit of a keycap) to the colour emoji', () {
      final asked = planFontKits('\uFE0F\u20E3'.runes, emojiBases: {0x31, 0x23});
      expect(textOf(asked, 'Ong Emoji 1'), '#1\u20E3\uFE0F');
    });

    test('no kit for a family with nothing to draw; characters in ascending order, each once', () {
      expect(planFontKits(const []), isEmpty);
      final korean = planFontKits('한국한'.runes);
      expect(korean, [(name: 'Ong KR 1', family: 'Noto Sans KR', text: '국한')]);
    });

    test('at most $kitLength characters a kit, at most $kitsPerGroup kits a family', () {
      final hangul = [for (var i = 0; i < kitLength * kitsPerGroup + 10; i++) 0xAC00 + i];
      final split = planFontKits(hangul);
      expect([for (final k in split) k.name], ['Ong KR 1', 'Ong KR 2', 'Ong KR 3']);
      expect([for (final k in split) k.text.runes.length], [kitLength, kitLength, kitLength]);
      expect(split[1].text.runes.first, 0xAC00 + kitLength);
    });

    test('the family names, in the order of the families; those of some kits, in that order', () {
      expect(fontKitFamilies.take(4), ['Ong Emoji 1', 'Ong Emoji 2', 'Ong Emoji 3', 'Ong JP 1']);
      expect(fontKitFamilies, hasLength(kitGroups.length * kitsPerGroup));
      final all = planFontKits([for (var i = 0; i < 3000; i++) 0x4E00 + i, 0xAC00, 0x0627, 0x2192, 0x01D0]);
      expect(fontKitFamilies, containsAll([for (final k in all) k.name]));
      expect(kitFamiliesOf(all.reversed), [
        for (final name in fontKitFamilies)
          if (all.any((k) => k.name == name)) name,
      ]);
      expect(kitFamiliesOf(planFontKits('한ا'.runes)), ['Ong KR 1', 'Ong Arabic 1']);
    });

    test('what the colour emoji draws: the Unicode property Emoji, not a block', () {
      for (final c in '⌚✨❌⭐🌈💙🎶▶♥✔❤☀✌↔㊗'.runes) {
        expect(isEmoji(c), isTrue, reason: String.fromCharCode(c));
      }
      for (final c in '☆♪→△★㈱東한'.runes) {
        expect(isEmoji(c), isFalse, reason: String.fromCharCode(c));
      }
    });
  });

  group('the CSS', () {
    test('the address asks for the family and the text', () {
      final uri = kitCssUri((name: 'Ong JP 1', family: 'Noto Sans JP', text: 'あ東'));
      expect(uri.host, 'fonts.googleapis.com');
      expect(uri.path, '/css2');
      expect(uri.queryParameters, {'family': 'Noto Sans JP', 'text': 'あ東'});
    });

    test('one cut-down font: its address', () {
      expect(
        kitFontUri(cssOf('https://fonts.gstatic.com/l/font?kit=abc&skey=1&v=v57')),
        Uri.parse('https://fonts.gstatic.com/l/font?kit=abc&skey=1&v=v57'),
      );
    });

    test('none, the family\'s slices (the font was not cut down), or several: none', () {
      expect(kitFontUri(''), isNull);
      expect(kitFontUri(cssOf('https://fonts.gstatic.com/s/notosansjp/v57/x.0.woff2')), isNull);
      expect(
        kitFontUri(cssOf('https://fonts.gstatic.com/l/font?kit=a') + cssOf('https://fonts.gstatic.com/l/font?kit=b')),
        isNull,
      );
    });
  });

  group('the download', () {
    const kit = (name: 'Ong JP 1', family: 'Noto Sans JP', text: 'あ');

    /// A client answering the CSS with [css] and the font with [font].
    MockClient answering(http.Response css, http.Response font) =>
        MockClient((request) async => request.url.host == 'fonts.googleapis.com' ? css : font);

    final cutDown = http.Response(cssOf('https://fonts.gstatic.com/l/font?kit=k'), 200);

    test('the CSS, then the font it names', () async {
      final asked = <Uri>[];
      final client = MockClient((request) async {
        asked.add(request.url);
        return request.url.host == 'fonts.googleapis.com' ? cutDown : http.Response.bytes([1, 2, 3], 200);
      });
      expect(await FontKitDownloader(client).download(kit), [1, 2, 3]);
      expect(asked, [kitCssUri(kit), Uri.parse('https://fonts.gstatic.com/l/font?kit=k')]);
    });

    test('fails for now (worth another attempt) on an HTTP error or an empty font', () async {
      Future<void> failsForNow(MockClient client) => expectLater(
        FontKitDownloader(client).download(kit),
        throwsA(isA<FontKitException>().having((e) => e, 'error', isNot(isA<FontKitUnavailable>()))),
      );
      await failsForNow(
        answering(http.Response(cssOf('https://fonts.gstatic.com/l/font?kit=k'), 500), http.Response('x', 200)),
      );
      await failsForNow(answering(cutDown, http.Response('', 404)));
      await failsForNow(answering(cutDown, http.Response.bytes([], 200)));
    });

    test(
      'unavailable for good when the API does not cut the font down for this browser: its slices, or no font',
      () async {
        for (final css in [
          cssOf('https://fonts.gstatic.com/s/notocoloremoji/v50/x.0.woff2') +
              cssOf('https://fonts.gstatic.com/s/notocoloremoji/v50/x.1.woff2'),
          '/* nothing */',
        ]) {
          await expectLater(
            FontKitDownloader(answering(http.Response(css, 200), http.Response('x', 200))).download(kit),
            throwsA(isA<FontKitUnavailable>()),
          );
        }
      },
    );

    test('unavailable for good when the font is larger than a cut-down one: abandoned as soon as it shows', () async {
      // announced larger: not read at all
      var read = false;
      final announced = MockClient.streaming((request, _) async {
        if (request.url.host == 'fonts.googleapis.com') {
          return http.StreamedResponse(Stream.value(cutDown.bodyBytes), 200);
        }
        return http.StreamedResponse(
          Stream.fromFuture(
            Future(() {
              read = true;
              return [0];
            }),
          ),
          200,
          contentLength: maxKitBytes + 1,
        );
      });
      await expectLater(FontKitDownloader(announced).download(kit), throwsA(isA<FontKitUnavailable>()));
      expect(read, isFalse);
      // not announced: read until it is too large, then the rest is not
      var chunks = 0;
      final unannounced = MockClient.streaming((request, _) async {
        if (request.url.host == 'fonts.googleapis.com') {
          return http.StreamedResponse(Stream.value(cutDown.bodyBytes), 200);
        }
        Iterable<List<int>> body() sync* {
          for (var i = 0; i < 100; i++) {
            chunks++;
            yield List.filled(64 * 1024, 0);
          }
        }

        return http.StreamedResponse(Stream.fromIterable(body()), 200);
      });
      await expectLater(FontKitDownloader(unannounced).download(kit), throwsA(isA<FontKitUnavailable>()));
      expect(chunks, lessThan(100));
      // a cut-down font of the largest size passes
      final largest = answering(cutDown, http.Response.bytes(List.filled(maxKitBytes, 1), 200));
      expect(await FontKitDownloader(largest).download(kit), hasLength(maxKitBytes));
    });
  });

  test('the fonts the engine fetches for itself, not the kits', () {
    expect(isEngineFont('https://fonts.gstatic.com/s/notosanskr/v39/x.woff2'), isTrue);
    expect(isEngineFont('https://fonts.gstatic.com/s/notocoloremoji/v50/x.7.woff2'), isTrue);
    expect(isEngineFont('https://fonts.gstatic.com/s/roboto/v32/KFOmCnqEu92Fr1Me4GZLCzYlKw.woff2'), isFalse);
    expect(isEngineFont('https://fonts.gstatic.com/l/font?kit=abc&skey=1&v=v57'), isFalse);
    expect(isEngineFont('https://fonts.googleapis.com/css2?family=Noto+Sans+JP'), isFalse);
  });
}
