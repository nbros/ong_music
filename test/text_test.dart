import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/fold_table.g.dart';
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

  group('fast paths give the results of the general code', () {
    // Random strings mixing what the fast paths handle (ASCII words, single spaces) with everything that sends them
    // to the general code: whitespace of every kind (U+0085 is trimmed but is not \s), accents, combining marks,
    // letters outside Latin, surrogates.
    const pieces = [
      'a',
      'Z',
      'q',
      '7',
      ' ',
      ' ',
      '  ',
      '-',
      "'",
      '!',
      '\t',
      '\n',
      '\r',
      '\u0085',
      '\u00A0',
      '\u2028',
      '\u3000',
      '\uFEFF',
      'é',
      'É',
      'ß',
      'Ø',
      '\u0301',
      '\u0308',
      '千',
      'ツ',
      'न',
      '\u093F',
      '🎹',
      '=',
      '\u0338',
    ];
    final random = Random(7);
    final samples = [
      for (var i = 0; i < 20000; i++)
        [for (var n = random.nextInt(9); n > 0; n--) pieces[random.nextInt(pieces.length)]].join(),
    ];

    test('fold', () {
      for (final s in samples) {
        expect(fold(s), _foldReference(s), reason: s);
      }
    });

    test('songKey', () {
      for (final s in samples) {
        expect(songKey(s), _songKeyReference(s), reason: s);
      }
    });

    test('collapseSpaces', () {
      for (final s in samples) {
        expect(collapseSpaces(s), s.replaceAll(RegExp(r'\s+'), ' ').trim(), reason: s);
      }
    });

    test('composeMarks', () {
      for (final s in [...samples, 'e\u0301\u0302x', 'e\u0301\u0301', '=\u0338\u0338', 'ae\u0301e\u0301']) {
        expect(composeMarks(s), _composeMarksReference(s), reason: s);
      }
    });
  });

  test('splitTitle splits on the first " - "', () {
    expect(splitTitle('Zelda - Song of Storms - Remix'), (artist: 'Zelda', track: 'Song of Storms - Remix'));
    expect(splitTitle('Clair de Lune'), (artist: '', track: 'Clair de Lune'));
    expect(splitTitle('Spider-Man'), (artist: '', track: 'Spider-Man'));
  });
}

// The implementations before the fast paths, as the reference.

final _foldTable = () {
  final table = Uint16List(0x10000);
  for (var i = 0; i < table.length; i++) {
    table[i] = i;
  }
  for (var i = 0; i < foldFrom.length; i++) {
    table[foldFrom[i]] = foldTo[i];
  }
  return table;
}();

String _foldReference(String text) => String.fromCharCodes(text.codeUnits.map((unit) => _foldTable[unit]));

String _songKeyReference(String title) {
  final key = _foldReference(
    title,
  ).replaceAll(RegExp('[\u0300-\u036F]+'), '').replaceAll(RegExp(r'[^\p{L}\p{N}\p{M}]+', unicode: true), ' ').trim();
  return RegExp(r'[\p{L}\p{N}]', unicode: true).hasMatch(key) ? key : '';
}

final _compositions = {for (var i = 0; i < composeFrom.length; i++) composeFrom[i]: composeTo[i]};

String _composeMarksReference(String text) {
  final units = <int>[];
  for (final unit in text.codeUnits) {
    if (units.isNotEmpty && unit >= 0x0300 && unit <= 0x036F) {
      final composed = _compositions[units.last * 0x10000 + unit];
      if (composed != null) {
        units.last = composed;
        continue;
      }
    }
    units.add(unit);
  }
  return String.fromCharCodes(units);
}
