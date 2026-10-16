import 'package:flutter/services.dart';
import 'package:om_events/app/core/utils/money.dart';

/// CSV construction for admin exports.
///
/// The exporter is deliberately not a `join(',')`: a product description containing a comma or a
/// newline would otherwise shift every later column, and an operator would import a report that
/// silently disagrees with the screen it came from.
abstract final class OmCsv {
  /// Columns beyond this are not exported. The caller must show [truncatedMessage] rather than
  /// letting a 200k-row ledger export run until the tab dies.
  static const int maxRows = 5000;

  static String? _needsQuotes(String value) {
    if (value.isEmpty) return null;
    final hasStructural = value.contains(',') ||
        value.contains('"') ||
        value.contains('\n') ||
        value.contains('\r');
    final hasEdgeSpace = value != value.trim();
    // A cell starting with = + - @ or a tab is evaluated by Excel/Sheets when the file is opened.
    // An admin export lands in a spreadsheet, so the formula is neutralised, not exported raw.
    final looksLikeFormula = value.startsWith('=') ||
        value.startsWith('+') ||
        value.startsWith('-') ||
        value.startsWith('@') ||
        value.startsWith('\t');
    if (!hasStructural && !hasEdgeSpace && !looksLikeFormula) return null;
    return value;
  }

  static String cell(Object? value) {
    if (value == null) return '';
    final raw = value is int ? '$value' : value.toString();
    final guarded = _needsQuotes(raw);
    if (guarded == null) return raw;
    final escaped = guarded.startsWith('=') ||
            guarded.startsWith('+') ||
            guarded.startsWith('-') ||
            guarded.startsWith('@') ||
            guarded.startsWith('\t')
        ? "'$guarded"
        : guarded;
    return '"${escaped.replaceAll('"', '""')}"';
  }

  static List<String> row(List<Object?> cells) =>
      cells.map(cell).toList(growable: false);

  static String build({
    required List<String> headers,
    required Iterable<List<Object?>> rows,
  }) {
    final buffer = StringBuffer(row(headers).join(','));
    buffer.write('\r\n');
    for (final r in rows) {
      buffer.write(row(r).join(','));
      buffer.write('\r\n');
    }
    return buffer.toString();
  }

  static int capRows(List<List<Object?>> rows) =>
      rows.length > maxRows ? maxRows : rows.length;

  /// Data rows in generated text: every line except the header. Quoted cells may contain newlines,
  /// so this counts *lines* of the built document, which is what a spreadsheet imports.
  static int countRows(String csv) {
    if (csv.trim().isEmpty) return 0;
    final lines = csv
        .replaceAll('\r\n', '\n')
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .toList(growable: false);
    return lines.isEmpty ? 0 : lines.length - 1;
  }

  static String truncatedMessage(int totalRows, int exported) =>
      'This export is capped at $maxRows rows. $totalRows rows matched, so only the first '
      '$exported were written. Narrow the date range or filters to export the rest.';

  /// Reverses the write path for an import preview: splits one logical row, honouring quoted
  /// fields with doubled inner quotes.
  static List<String> parseLine(String line) {
    final out = <String>[];
    final current = StringBuffer();
    var inQuotes = false;
    for (var i = 0; i < line.length; i++) {
      final ch = line[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < line.length && line[i + 1] == '"') {
            current.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          current.write(ch);
        }
      } else if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        out.add(current.toString());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    out.add(current.toString());
    return out;
  }

  static List<List<String>> parse(String csvText) {
    final normalised = csvText.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalised
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .map(parseLine)
        .toList(growable: false);
  }

  static int headerIndexOf(List<String> headerRow, List<String> aliases) {
    for (var i = 0; i < headerRow.length; i++) {
      final key = headerRow[i].trim().toLowerCase();
      if (aliases.contains(key)) return i;
    }
    return -1;
  }
}

/// Display-only helpers shared by admin tables. Nothing here computes money: `paise` values are
/// formatted with [OmMoney] and totals always come from the server.
abstract final class AdminFormat {
  static const int shortDateCap = 10;

  static String date(DateTime? value) {
    if (value == null) return '—';
    final y = value.year.toString().padLeft(4, '0');
    final m = value.month.toString().padLeft(2, '0');
    final d = value.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  static String dateTime(DateTime? value) {
    if (value == null) return '—';
    final hh = value.hour.toString().padLeft(2, '0');
    final mm = value.minute.toString().padLeft(2, '0');
    return '${date(value)} $hh:$mm';
  }

  /// Rupees entered by a human, stored as integer paise. The parse is [OmMoney]'s so the admin
  /// form and the storefront cannot disagree about what "12.5" means.
  static int paiseFromRupeeText(String text) => OmMoney.parseRupeeString(text);

  static String rupeeText(int paise) {
    final rupees = paise ~/ 100;
    final remainder = paise % 100;
    return remainder == 0 ? '$rupees' : '$rupees.${remainder.toString().padLeft(2, '0')}';
  }

  static String missing(Object? value, {String placeholder = '—'}) =>
      (value == null || '$value'.trim().isEmpty) ? placeholder : '$value';

  /// Basis points as readable text. Never a percent-as-double round trip.
  static String bps(int basisPoints) {
    final whole = basisPoints ~/ 100;
    final fraction = basisPoints % 100;
    return fraction == 0 ? '$whole%' : '$whole.${fraction.toString().padLeft(2, '0')}%';
  }

  static int bpsFromPercentText(String text) {
    final cleaned = text.replaceAll('%', '').trim();
    final asPercent = double.tryParse(cleaned);
    if (asPercent == null) return 0;
    return (asPercent * 100).round();
  }

  static String bytes(int? sizeBytes) {
    if (sizeBytes == null) return '—';
    if (sizeBytes < 1024) return '$sizeBytes B';
    if (sizeBytes < 1024 * 1024) return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
    return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

/// Places a prepared CSV on the clipboard so an operator can paste it into a sheet.
///
/// A browser download would need an extra declared dependency (`file_picker.saveFile` or
/// `url_launcher` as a direct dep); until the owner adds one, copy-to-clipboard is the honest,
/// working export path. The raw text is also shown on screen, so an export is never a
/// "it probably worked" action.
Future<bool> adminCopyCsv(String csv) async {
  try {
    await Clipboard.setData(ClipboardData(text: csv));
    return true;
  } catch (_) {
    return false;
  }
}
