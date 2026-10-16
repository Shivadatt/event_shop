// Each failure carries its own presentable default message and its own stable `code`, which a
// `super.message` parameter cannot express (it would also lose the code). The explicit super
// calls are deliberate, so this one file opts out of the lint rather than duplicating `code`.
// ignore_for_file: use_super_parameters

/// Centralised failure taxonomy. Repositories throw these; controllers catch these; widgets
/// render these. No widget may string-match a Firebase error message.
sealed class OmFailure implements Exception {
  const OmFailure(this.message, {this.code});

  /// Safe, user-presentable text. Never includes credentials or raw server traces.
  final String message;
  final String? code;

  bool get isRetryable => false;
  bool get isAuthFailure => false;
  bool get isPermissionFailure => false;

  @override
  String toString() => '$runtimeType($code): $message';
}

class NetworkFailure extends OmFailure {
  const NetworkFailure([
    String message = 'You appear to be offline. Check your connection.',
  ]) : super(message, code: 'network');

  @override
  bool get isRetryable => true;
}

class ServerFailure extends OmFailure {
  const ServerFailure([
    String message = 'Something went wrong on our side. Please try again.',
  ]) : super(message, code: 'server');

  @override
  bool get isRetryable => true;
}

class NotFoundFailure extends OmFailure {
  const NotFoundFailure([
    String message = 'We could not find what you were looking for.',
  ]) : super(message, code: 'not-found');
}

/// Rules denied the read/write. Distinct from [ServerFailure] because the correct UI response
/// is "sign in as the right person", not "retry".
class PermissionFailure extends OmFailure {
  const PermissionFailure([
    String message = 'You do not have access to this data.',
  ]) : super(message, code: 'permission-denied');

  @override
  bool get isPermissionFailure => true;
}

class AuthFailure extends OmFailure {
  const AuthFailure([
    String message = 'Your session expired. Please sign in again.',
  ]) : super(message, code: 'auth');

  @override
  bool get isAuthFailure => true;
}

/// Pricing, stock or coupon state changed between browsing and confirming.
class ConflictFailure extends OmFailure {
  const ConflictFailure({
    String message =
        'Prices or availability changed. Review the updated order before paying.',
    String? code = 'conflict',
    this.details = const <String, Object?>{},
  }) : super(message, code: code);

  final Map<String, Object?> details;
}

class ValidationFailure extends OmFailure {
  const ValidationFailure(
    String message, {
    this.field,
  }) : super(message, code: 'validation');

  final String? field;
}

/// Supabase Storage rejected an upload/delete, or the media pipeline is unconfigured.
class MediaFailure extends OmFailure {
  const MediaFailure([
    String message = 'The image could not be transferred. Please try again.',
  ]) : super(message, code: 'media');

  @override
  bool get isRetryable => true;
}

class NotImplementedFailure extends OmFailure {
  const NotImplementedFailure([
    String message = 'This feature is not available yet.',
  ]) : super(message, code: 'not-implemented');
}
