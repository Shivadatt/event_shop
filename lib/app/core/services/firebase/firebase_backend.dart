import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';

/// The only place in the app that touches Firebase. Everything else — repositories, providers,
/// controllers, UI — depends on these accessors and the failure mapping, so a `FirebaseException`
/// or a `FirebaseFunctionsException` can never reach the widget layer un-translated.
///
/// Instances are assumed already initialised by [AppBootstrap.run]; this class only hands them out
/// and normalises errors. When Firebase is not configured the binding never wires these repos, so
/// callers hit the unconfigured implementations instead — but every accessor asserts anyway.
abstract final class FirebaseBackend {
  const FirebaseBackend._();

  static FirebaseAuth get auth {
    _assertConfigured();
    return FirebaseAuth.instance;
  }

  static FirebaseFirestore get firestore {
    _assertConfigured();
    return FirebaseFirestore.instance;
  }

  static FirebaseFunctions get functions {
    _assertConfigured();
    return FirebaseFunctions.instanceFor(region: Env.functionsRegion);
  }

  static void _assertConfigured() {
    if (!Env.hasFirebase) {
      throw ServerFailure(
        'Firebase is not configured (${Env.missingKeys().join(', ')}).',
      );
    }
  }

  /// Invoke a callable and return its decoded map payload. The single funnel through which every
  /// repository reaches Cloud Functions, so error mapping is written exactly once.
  static Future<Map<String, dynamic>> call(
    String name, [
    Map<String, Object?> argument = const <String, Object?>{},
  ]) async {
    try {
      // `Object?`, never the default: an un-parameterised `call()` infers `dynamic`, and a
      // silently-dynamic payload is exactly how a client-trusting bug (read a price, trust a role)
      // gets reintroduced one field access later. The defensive checks below are the contract.
      final result = await functions.httpsCallable(name).call<Object?>(argument);
      final data = result.data;
      if (data is Map) return data.cast<String, dynamic>();
      return <String, dynamic>{'result': data};
    } on FirebaseFunctionsException catch (error) {
      throw mapFunctionsError(error);
    } on FirebaseException catch (error) {
      throw mapFirebaseError(error);
    }
  }

  static OmFailure mapFirebaseError(FirebaseException error) {
    final message = error.message ?? 'Firestore request failed.';
    return switch (error.code) {
      'permission-denied' => PermissionFailure(message),
      'unauthenticated' => const AuthFailure(),
      'not-found' => const NotFoundFailure(),
      'cancelled' => const NetworkFailure(),
      'unavailable' || 'network-request-failed' => const NetworkFailure(),
      'resource-exhausted' => const ServerFailure(),
      _ => ServerFailure(message),
    };
  }

  static OmFailure mapFunctionsError(FirebaseFunctionsException error) {
    final message = error.message ?? 'The request could not be completed.';
    final details = error.details is Map
        ? (error.details as Map).cast<String, Object?>()
        : const <String, Object?>{};
    return switch (error.code) {
      'permission-denied' => PermissionFailure(message),
      'unauthenticated' => const AuthFailure(),
      'not-found' => NotFoundFailure(message),
      'invalid-argument' => ValidationFailure(message),
      'failed-precondition' => ConflictFailure(
          message: message,
          code: details['code'] as String? ?? 'conflict',
          details: details,
        ),
      'out-of-range' || 'already-exists' => ConflictFailure(message: message),
      'unavailable' || 'deadline-exceeded' => const NetworkFailure(),
      'resource-exhausted' => const ServerFailure(),
      _ => ServerFailure(message),
    };
  }
}

/// Shared Firestore -> model converters. Reading happens through the defensive `fromMap` readers;
/// writing goes through `toWriteMap` so counters and cost price are never clobbered by the client.
final class ModelConverters {
  const ModelConverters._();

  static T fromDoc<T>(DocumentSnapshot<Object?> doc, T Function(Map<String, dynamic>, String) build) {
    final data = doc.data();
    return build(data is Map<String, dynamic> ? data : <String, dynamic>{}, doc.id);
  }

  static Timestamp ts(DateTime value) => Timestamp.fromDate(value);
  static Timestamp now() => Timestamp.now();
}
