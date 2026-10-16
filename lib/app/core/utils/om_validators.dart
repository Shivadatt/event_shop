import 'package:om_events/app/core/utils/money.dart';

/// Form validators shared by storefront and admin. Each returns an error string or null.
final class OmValidators {
  const OmValidators._();

  static String? required(String? value, {String label = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$label is required';
    return null;
  }

  static String? email(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Email is required';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(v)) return 'Enter a valid email';
    return null;
  }

  static String? phone(String? value) {
    final v = (value ?? '').trim().replaceAll(RegExp(r'[\s-]'), '');
    if (v.isEmpty) return 'Mobile number is required';
    if (!RegExp(r'^\+?91?[6-9]\d{9}$').hasMatch(v)) return 'Enter a valid Indian mobile number';
    return null;
  }

  static String? pincode(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Pincode is required';
    if (!RegExp(r'^[1-9]\d{5}$').hasMatch(v)) return 'Enter a valid 6-digit pincode';
    return null;
  }

  static String? password(String? value) {
    final v = value ?? '';
    if (v.length < 8) return 'Use at least 8 characters';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'\d').hasMatch(v)) {
      return 'Include at least one letter and one number';
    }
    return null;
  }

  static String? sku(String? value) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'SKU is required';
    if (!RegExp(r'^[A-Za-z0-9][A-Za-z0-9_-]{1,31}$').hasMatch(v)) {
      return 'SKU: 2-32 letters, digits, hyphen or underscore';
    }
    return null;
  }

  static String? wholeQuantity(String? value, {int minimum = 1, int? maximum}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Quantity is required';
    final qty = int.tryParse(v);
    if (qty == null) return 'Quantity must be a whole number';
    if (qty < minimum) return 'Minimum quantity is $minimum';
    if (maximum != null && qty > maximum) return 'Maximum quantity is $maximum';
    return null;
  }

  /// Rejects a slab grid where a quantity could match two slabs, or where a slab is inverted.
  static String? slabRange(int min, int? max) {
    if (min < 1) return 'Minimum quantity must be at least 1';
    if (max != null && max < min) return 'Maximum cannot be below minimum';
    return null;
  }

  static String? price(String? value, {int minimumPaise = 1}) {
    final v = (value ?? '').trim();
    if (v.isEmpty) return 'Price is required';
    final paise = OmMoney.parseRupeeString(v);
    if (paise < minimumPaise) return 'Enter a price above zero';
    if (paise > 99999999) return 'That price looks too large';
    return null;
  }
}
