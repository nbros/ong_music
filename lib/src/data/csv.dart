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
  final rows = <List<String>>[];
  if (text.isEmpty) return rows;
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

  var row = <String>[];
  // The current field is head + text[anchor, fieldEnd), fieldEnd being i until a closing quote sets it. head holds
  // the text before an escaped quote, and is null when there is none (one substring per field otherwise).
  String? head;
  var anchor = start, fieldEnd = -1;

  String field(int i) {
    final value = text.substring(anchor, fieldEnd < 0 ? i : fieldEnd);
    return head == null ? value : '$head$value';
  }

  void endRow() {
    for (final cell in row) {
      if (cell.isNotEmpty) {
        rows.add(row);
        break;
      }
    }
    row = <String>[];
  }

  var i = start;
  while (i < end) {
    final unit = text.codeUnitAt(i);
    if (unit == _quote && i == anchor && fieldEnd < 0 && (head == null || head.isEmpty)) {
      // quoted field: only quotes matter until it ends
      anchor = ++i;
      while (true) {
        final q = text.indexOf('"', i);
        if (q < 0 || q >= end) {
          i = end;
          break;
        }
        final next = q + 1 < end ? text.codeUnitAt(q + 1) : -1;
        if (next == _quote) {
          head = '${head ?? ''}${text.substring(anchor, q)}"';
          anchor = i = q + 2;
        } else if (next == -1 || next == _comma || next == _lf || next == _cr) {
          fieldEnd = q;
          i = q + 1;
          break;
        } else {
          i = q + 1;
        }
      }
      continue;
    }
    if (unit == _comma || unit == _lf || unit == _cr) {
      row.add(field(i));
      head = null;
      fieldEnd = -1;
      if (unit != _comma) {
        endRow();
        if (unit == _cr && i + 1 < end && text.codeUnitAt(i + 1) == _lf) i++;
      }
      anchor = i + 1;
    }
    i++;
  }
  final last = anchor < end ? field(end) : (head ?? '');
  if (row.isNotEmpty || last.isNotEmpty) {
    row.add(last);
    endRow();
  }
  return rows;
}
