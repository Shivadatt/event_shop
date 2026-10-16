import 'package:intl/intl.dart';

/// Money is integer paise end to end. Doubles appear nowhere in totals, snapshots, or Firestore
/// documents — a rupee amount read as `double` is a defect, not a style choice.
final class OmMoney {
  const OmMoney._();

  static final NumberFormat _grouped = NumberFormat('#,##0');

  static int parseRupeeString(String input) {
    final cleaned = input.replaceAll(RegExp(r'[^0-9.]'), '');
    if (cleaned.isEmpty) return 0;
    final parts = cleaned.split('.');
    final rupees = int.tryParse(parts.first) ?? 0;
    final paise = parts.length > 1
        ? (int.tryParse(parts[1].padRight(2, '0').substring(0, 2)) ?? 0)
        : 0;
    return rupees * 100 + paise;
  }

  /// `₹1,234` / `₹1,234.50` — trailing paise omitted only when exactly zero.
  static String format(int paise) {
    final negative = paise < 0;
    final abs = paise.abs();
    final rupees = _grouped.format(abs ~/ 100);
    final remainder = abs % 100;
    final body = remainder == 0 ? rupees : '$rupees.${remainder.toString().padLeft(2, '0')}';
    return negative ? '-₹$body' : '₹$body';
  }

  static String formatRupees(int paise) => '₹${_grouped.format(paise ~/ 100)}';

  /// Percentage off a reference price, rounded for display only. Returns 0 when there is no
  /// discount or the base is zero.
  static int discountPercent(int basePaise, int sellingPaise) {
    if (basePaise <= 0 || sellingPaise >= basePaise) return 0;
    return (((basePaise - sellingPaise) * 100) / basePaise).round();
  }
}
