import 'dart:math';

/// Short, URL-safe, collision-resistant identifiers for storage objects and `media_objects` rows.
///
/// `Random.secure()` rather than `Random()`: these ids are part of a public object key, and a
/// predictable pseudo-random sequence would let someone enumerate another store's not-yet-published
/// product photos. The alphabet drops visually ambiguous characters because admins read these paths
/// in support tickets.
abstract final class MediaId {
  static const String _alphabet =
      '0123456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ';

  static final Random _random = Random.secure();

  static String generate({int length = 16}) {
    final safe = length < 8 ? 8 : length;
    final buffer = StringBuffer();
    for (var i = 0; i < safe; i++) {
      buffer.write(_alphabet[_random.nextInt(_alphabet.length)]);
    }
    return buffer.toString();
  }

  /// First 8 characters, for cache-busting query values and human-facing labels.
  static String short() => generate(length: 8);

  static bool isValid(String value) =>
      value.length >= 8 && value.length <= 32 && RegExp(r'^[0-9A-Za-z]+$').hasMatch(value);
}
