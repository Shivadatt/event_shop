import 'package:cloud_firestore/cloud_firestore.dart';

/// Defensive Firestore -> Dart readers. Documents written by different agents (and by Cloud
/// Functions in Node) are not guaranteed to agree on number width or null shape, so every read
/// goes through here rather than a bare cast.
String? readString(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is String) return v.isEmpty ? null : v;
  return null;
}

String readStringOrEmpty(Map<String, dynamic> m, String key) => readString(m, key) ?? '';

int? readInt(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is int) return v;
  if (v is double) return v.round();
  if (v is String) return int.tryParse(v);
  return null;
}

int readIntOrZero(Map<String, dynamic> m, String key) => readInt(m, key) ?? 0;

bool readBool(Map<String, dynamic> m, String key, {bool fallback = false}) {
  final v = m[key];
  if (v is bool) return v;
  if (v is num) return v != 0;
  return fallback;
}

List<String> readStringList(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is List) {
    return v.whereType<String>().where((e) => e.isNotEmpty).toList(growable: false);
  }
  return const <String>[];
}

Map<String, dynamic> readMap(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is Map) {
    return v.cast<Object?, Object?>().map((k, value) => MapEntry('$k', value));
  }
  return <String, dynamic>{};
}

List<Map<String, dynamic>> readMapList(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v is List) {
    return v
        .whereType<Map<Object?, Object?>>()
        .map((e) => e.map((k, value) => MapEntry('$k', value)))
        .toList(growable: false);
  }
  return const <Map<String, dynamic>>[];
}

/// Accepts `Timestamp`, epoch millis, or ISO-8601 — functions and the client disagree on all
/// three, and a lost date is cheaper than a crash.
DateTime? readDate(Map<String, dynamic> m, String key) {
  final v = m[key];
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
  if (v is double) return DateTime.fromMillisecondsSinceEpoch(v.round());
  if (v is String) return DateTime.tryParse(v)?.toLocal();
  return null;
}

/// Firestore cannot store `undefined`; every writer must null-out absent values.
Map<String, Object?> compact(Map<String, Object?> input) =>
    Map<String, Object?>.fromEntries(input.entries.where((e) => e.value != null));
