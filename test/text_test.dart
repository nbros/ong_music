import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/text.dart';

void main() {
  group('fold', () {
    test('folds case and diacritics', () {
      expect(fold('Élan ÇA va À Noël'), 'elan ca va a noel');
      expect(fold('Pokémon'), 'pokemon');
      expect(fold('Ångström Øre Łódź'), 'angstrom ore lodz');
      expect(fold('ΆΛΦΑ Привет'), 'αλφα привет');
      expect(fold('Tiếng Việt'), 'tieng viet');
    });

    test('keeps the length of the string', () {
      for (final s in ['Straße', 'ÆON', 'İstanbul', '한국어', 'emoji 🎹 piano', 'e\u0301', 'ﬁne']) {
        expect(fold(s).length, s.length, reason: s);
      }
      expect(fold('Straße'), 'straße');
      expect(fold('ÆON'), 'æon');
      expect(fold('İstanbul'), 'istanbul');
      expect(fold('한국어'), '한국어');
      expect(fold('でんでん'), 'でんでん');
    });

    test('returns ASCII lowercase unchanged', () {
      const s = 'already folded 123';
      expect(identical(fold(s), s), isTrue);
    });
  });

  group('songKey', () {
    test('folds and turns punctuation runs into one space', () {
      expect(songKey('The Legend of Zelda - Song of Storms!'), 'the legend of zelda song of storms');
      expect(songKey('  Pokémon:  Route 1 (Remix)  '), 'pokemon route 1 remix');
      expect(songKey("Ramin Karimloo - 'Til I Hear You Sing'"), 'ramin karimloo til i hear you sing');
    });

    test('keeps non-Latin letters', () {
      expect(songKey('千と千尋の神隠し - いつも何度でも'), '千と千尋の神隠し いつも何度でも');
      expect(songKey('Гоце Арнаудов - Дафино вино'), 'гоце арнаудов дафино вино');
      expect(songKey('ツ'), 'ツ');
      expect(songKey('で'), isNot(songKey('て')), reason: 'voicing marks make other syllables');
      expect(songKey('नमस्ते दुनिया'), 'नमस्ते दुनिया', reason: 'Indic vowel signs are part of words');
      expect(songKey('千と千尋'), isNot(songKey('となりのトトロ')));
    });

    test('drops combining marks of decomposed text', () {
      expect(songKey('Pokemo\u0301n'), 'pokemon');
    });

    test('is empty without letters or digits', () {
      expect(songKey('???'), '');
      expect(songKey(r' \ - '), '');
    });
  });

  test('tokenize folds and splits on whitespace', () {
    expect(tokenize('  Zélda   LOOP\talinsa '), ['zelda', 'loop', 'alinsa']);
    expect(tokenize('   '), isEmpty);
  });

  group('matchRanges', () {
    test('marks every occurrence of every token, merged and sorted', () {
      expect(matchRanges('Zelda - Zelda Theme', ['zelda']), [(start: 0, end: 5), (start: 8, end: 13)]);
      expect(matchRanges('abcdef', ['cd', 'bc', 'ef']), [(start: 1, end: 6)]);
      expect(matchRanges('abc', ['x']), isEmpty);
      expect(matchRanges('abc', []), isEmpty);
    });

    test('is accent-insensitive and maps offsets to the original text', () {
      const text = 'Pokémon Écarlate';
      final ranges = matchRanges(text, tokenize('pokemon ecarlate'));
      expect(ranges, [(start: 0, end: 7), (start: 8, end: 16)]);
      expect(text.substring(ranges[0].start, ranges[0].end), 'Pokémon');
    });

    test('offsets stay right after a character that would expand', () {
      const text = 'Straße Zelda';
      final ranges = matchRanges(text, ['zelda']);
      expect(text.substring(ranges.single.start, ranges.single.end), 'Zelda');
    });
  });

  group('composeMarks', () {
    test('composes a letter and its combining mark', () {
      expect(composeMarks('Poke\u0301mon'), 'Pokémon');
      expect(composeMarks('E\u0301cole, a\u0300 Noe\u0308l'), 'École, à Noël');
      expect(composeMarks('Vie\u0323\u0302t'), 'Việt', reason: 'two marks on one letter');
    });

    test('leaves the rest alone', () {
      const plain = 'Pokémon - Route 1';
      expect(identical(composeMarks(plain), plain), isTrue);
      expect(composeMarks(''), '');
      expect(composeMarks('\u0301a'), '\u0301a', reason: 'a mark with no letter before it');
      expect(composeMarks('q\u0301'), 'q\u0301', reason: 'no precomposed character');
      expect(composeMarks('で\u3099'), 'で\u3099', reason: 'not a Latin diacritical mark');
    });

    test('decomposed text then folds, keys and matches like precomposed text', () {
      final title = composeMarks('Poke\u0301mon XD');
      expect(fold(title), 'pokemon xd');
      expect(songKey(title), songKey('Pokémon XD'));
      expect(matchRanges(title, tokenize('pokemon')), [(start: 0, end: 7)]);
    });
  });

  group('tokenize', () {
    test('composes a decomposed query', () {
      expect(tokenize('poke\u0301mon'), ['pokemon']);
    });

    test('drops duplicates and tokens contained in another one', () {
      expect(tokenize('zelda Zelda'), ['zelda']);
      expect(tokenize('zel zelda song'), ['zelda', 'song']);
      expect(tokenize('song zelda da'), ['song', 'zelda']);
      expect(tokenize('a'), ['a']);
      expect(tokenize('   '), isEmpty);
    });

    test('keeps at most maxQueryTokens tokens', () {
      final words = [for (var i = 0; i < 40; i++) 'w${i}x'];
      expect(tokenize(words.join(' ')), words.take(maxQueryTokens));
    });
  });

  test('splitTitle splits on the first " - "', () {
    expect(splitTitle('Zelda - Song of Storms - Remix'), (artist: 'Zelda', track: 'Song of Storms - Remix'));
    expect(splitTitle('Clair de Lune'), (artist: '', track: 'Clair de Lune'));
    expect(splitTitle('Spider-Man'), (artist: '', track: 'Spider-Man'));
  });
}
