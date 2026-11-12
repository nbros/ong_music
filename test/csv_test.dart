import 'package:flutter_test/flutter_test.dart';
import 'package:ong_music/src/data/csv.dart';

void main() {
  test('splits fields and rows', () {
    expect(decodeCsv('a,b,c\nd,e,f'), [
      ['a', 'b', 'c'],
      ['d', 'e', 'f'],
    ]);
    expect(decodeCsv(''), isEmpty);
  });

  test('quoted fields keep separators, line breaks and escaped quotes', () {
    expect(decodeCsv('"a,b","line 1\nline 2","say ""hi""",""\n"x"'), [
      ['a,b', 'line 1\nline 2', 'say "hi"', ''],
      ['x'],
    ]);
    expect(decodeCsv('"crlf\r\ninside"'), [
      ['crlf\r\ninside'],
    ]);
  });

  test('a quote not opening a field, or not followed by a separator, is text', () {
    expect(decodeCsv('a"b,c'), [
      ['a"b', 'c'],
    ]);
    expect(decodeCsv('"a"b",c'), [
      ['a"b', 'c'],
    ]);
  });

  test('accepts CRLF, LF and CR row ends', () {
    expect(decodeCsv('a\r\nb\nc\rd\r\n'), [
      ['a'],
      ['b'],
      ['c'],
      ['d'],
    ]);
  });

  test('skips one leading BOM', () {
    expect(decodeCsv('﻿"a",b'), [
      ['a', 'b'],
    ]);
    expect(decodeCsv('﻿﻿a'), [
      ['﻿a'],
    ]);
  });

  test('leaves out rows whose cells are all empty, keeps short rows', () {
    expect(decodeCsv('a,b,c\n\n,,\n"",""\nd\n\n\n'), [
      ['a', 'b', 'c'],
      ['d'],
    ]);
    expect(decodeCsv(',x'), [
      ['', 'x'],
    ]);
  });

  test('a text ending inside a quoted field ends that field', () {
    expect(decodeCsv('a,"b\nc'), [
      ['a', 'b\nc'],
    ]);
    expect(decodeCsv('a,"'), [
      ['a', ''],
    ]);
  });

  test('keeps the quirks of package:csv 8.0.0 at the end of the text', () {
    // an odd number of trailing quotes loses the last one, else a trailing CR is dropped
    expect(decodeCsv('a,b"'), [
      ['a', 'b'],
    ]);
    expect(decodeCsv('"a"""'), [
      ['a"'],
    ]);
    expect(decodeCsv('"ab\r'), [
      ['ab'],
    ]);
    expect(decodeCsv('"'), isEmpty);
  });
}
