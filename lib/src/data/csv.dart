/// A CSV decoder for the sheet exports.
///
/// Pure Dart: usable from isolates, `dart run` scripts and unit tests.
library;

const int _quote = 0x22, _comma = 0x2C, _cr = 0x0D, _lf = 0x0A;

/// Splits CSV text into rows of cells.
///
/// Fields are separated by `,`, rows by CRLF, LF or CR. A field that starts
/// with `"` is quoted: it may contain separators and line breaks, `""` stands
/// for one quote, and it ends at a quote followed by `,`, a line break or the
/// end of the text (any other quote is kept as text). A quote elsewhere is
/// text. A leading BOM is skipped, rows whose cells are all empty are left out,
/// and a text ending inside a quoted field ends that field.
///
/// Gives the same rows as `package:csv` 8.0.0 (`Csv(autoDetect: false,
/// skipEmptyLines: true).decode`), which this replaces, down to its quirks: a
/// text ending with an odd number of quotes loses the last one, else a text
/// ending with CR loses it. Several times faster on the quoted cells of the
/// exports: it jumps from quote to quote.
List<List<String>> decodeCsv(String text) {
  final reader = CsvReader(text);
  while (reader.read(_allRows)) {}
  return reader.rows;
}

/// More row ends than any text holds: [decodeCsv] reads its text in one call.
const int _allRows = 1 << 30;

/// [decodeCsv] in steps: each call of [read] goes on where the last one stopped, so that a long text can be decoded
/// a few hundred rows at a time, between which the thread does something else (the web, see `runInSlices`). The rows
/// are those of [decodeCsv], however the text is cut.
final class CsvReader {
  /// A reader of [text], nothing read yet.
  CsvReader(this._text) {
    if (_text.isEmpty) {
      _done = true;
      return;
    }
    final text = _text;
    final start = text.codeUnitAt(0) == 0xFEFF ? 1 : 0;
    var end = text.length;
    var trailingQuotes = 0;
    while (end - 1 - trailingQuotes >= start && text.codeUnitAt(end - 1 - trailingQuotes) == _quote) {
      trailingQuotes++;
    }
    if (trailingQuotes.isOdd) {
      end--;
    } else if (end > start && text.codeUnitAt(end - 1) == _cr) {
      end--;
    }
    _end = end;
    _i = _anchor = start;
  }

  final String _text;
  int _end = 0;
  bool _done = false;

  /// The rows read so far, empty rows left out.
  final List<List<String>> rows = [];

  // The current field is _head + text[_anchor, _fieldEnd), _fieldEnd being i until a closing quote sets it. _head
  // holds the text before an escaped quote, and is null when there is none (one substring per field otherwise). _i is
  // where the next [read] goes on.
  List<String> _row = <String>[];
  StringBuffer? _head;
  int _i = 0, _anchor = 0, _fieldEnd = -1;

  String _field(int i) {
    final value = _text.substring(_anchor, _fieldEnd < 0 ? i : _fieldEnd);
    final before = _head;
    return before == null ? value : (before..write(value)).toString();
  }

  void _endRow() {
    for (final cell in _row) {
      if (cell.isNotEmpty) {
        rows.add(_row);
        break;
      }
    }
    _row = <String>[];
  }

  /// Reads on until [rowEnds] more row ends are passed (empty rows count) or the text is over. Returns whether there
  /// is more to read; [rows] holds every row once it returns false.
  bool read(int rowEnds) {
    if (_done) return false;
    final text = _text, end = _end;
    var i = _i, ends = 0;
    while (i < end) {
      final unit = text.codeUnitAt(i);
      if (unit == _quote && i == _anchor && _fieldEnd < 0 && (_head?.isEmpty ?? true)) {
        // quoted field: only quotes matter until it ends
        _anchor = ++i;
        while (true) {
          final q = text.indexOf('"', i);
          if (q < 0 || q >= end) {
            i = end;
            break;
          }
          final next = q + 1 < end ? text.codeUnitAt(q + 1) : -1;
          if (next == _quote) {
            _head = (_head ?? StringBuffer())
              ..write(text.substring(_anchor, q))
              ..write('"');
            _anchor = i = q + 2;
          } else if (next == -1 || next == _comma || next == _lf || next == _cr) {
            _fieldEnd = q;
            i = q + 1;
            break;
          } else {
            i = q + 1;
          }
        }
        continue;
      }
      if (unit == _comma || unit == _lf || unit == _cr) {
        _row.add(_field(i));
        _head = null;
        _fieldEnd = -1;
        if (unit != _comma) {
          _endRow();
          if (unit == _cr && i + 1 < end && text.codeUnitAt(i + 1) == _lf) i++;
        }
        _anchor = i + 1;
        if (unit != _comma && ++ends >= rowEnds) {
          _i = i + 1;
          return true;
        }
      }
      i++;
    }
    final last = _anchor < end ? _field(end) : (_head?.toString() ?? '');
    if (_row.isNotEmpty || last.isNotEmpty) {
      _row.add(last);
      _endRow();
    }
    _done = true;
    return false;
  }
}
