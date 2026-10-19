import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/firebase/firebase_backend.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/data/providers/firestore_converters.dart';
import 'package:om_events/data/repositories/auth_repository.dart';

/// Firebase Auth + the `users/{uid}` profile document. The session user is the Firestore profile,
/// not the Auth account: role and wholesale approval are data on the doc, re-verified by rules and
/// functions. Profile documents are minted server-side via the `accountEnsure` callable so a client
/// can never write its own role.
final class FirestoreAuthRepository implements AuthRepository {
  FirestoreAuthRepository(this._session) {
    _authSub = FirebaseBackend.auth.authStateChanges().listen(_onAuthChanged);
  }

  final SessionStore _session;
  final StreamController<UserProfile?> _controller = StreamController<UserProfile?>.broadcast();
  final StreamController<UserRole> _roleController = StreamController<UserRole>.broadcast();
  StreamSubscription<User?>? _authSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _profileSub;
  UserProfile? _cached;

  @override
  UserProfile? get cachedProfile => _cached;

  @override
  Stream<UserProfile?> get profileChanges => _controller.stream;

  @override
  Stream<UserRole> get roleChanges => _roleController.stream;

  Future<void> _onAuthChanged(User? user) async {
    await _profileSub?.cancel();
    if (user == null) {
      _emit(null);
      return;
    }
    _profileSub = Collections.user(user.uid).snapshots().listen(
      (snap) {
        if (!snap.exists) {
          _emit(_provisional(user));
          return;
        }
        _emit(FirestoreConverters.user(snap));
      },
      onError: _emitError,
    );
  }

  UserProfile _provisional(User user) => UserProfile(
        uid: user.uid,
        email: user.email ?? '',
        displayName: user.displayName ?? '',
        phone: user.phoneNumber ?? '',
      );

  void _emit(UserProfile? profile) {
    _cached = profile;
    _session.set(profile);
    if (!_controller.isClosed) _controller.add(profile);
    if (!_roleController.isClosed) _roleController.add(profile?.role ?? UserRole.guest);
  }

  void _emitError(Object error, StackTrace stack) {
    if (!_controller.isClosed) _controller.addError(error, stack);
  }

  Future<UserProfile> _ensure(User user) async {
    try {
      final data = await FirebaseBackend.call(
        'accountEnsure',
        <String, Object?>{'displayName': user.displayName ?? ''},
      );
      final profile = UserProfile.fromMap(data, uid: user.uid);
      _emit(profile);
      return profile;
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<UserProfile> signIn({required String email, required String password}) async {
    try {
      final cred = await FirebaseBackend.auth
          .signInWithEmailAndPassword(email: email.trim(), password: password);
      return _ensure(cred.user!);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String displayName,
    String? phone,
  }) async {
    try {
      final cred = await FirebaseBackend.auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = cred.user!;
      await user.updateDisplayName(displayName.trim());
      await Collections.user(user.uid).set(<String, Object?>{
        'uid': user.uid,
        'email': user.email,
        'phone': phone ?? '',
        'displayName': displayName.trim(),
      }, SetOptions(merge: true));
      return _ensure(user);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await FirebaseBackend.auth.signOut();
      _emit(null);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await FirebaseBackend.auth.sendPasswordResetEmail(email: email.trim());
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    }
  }

  /// Backed by `FirebaseAuth.confirmPasswordReset({required String code, required String newPassword})`
  /// (firebase_auth 7.0.0, `lib/src/firebase_auth.dart:203`; implemented on web by
  /// firebase_auth_web 6.3.1, so this is not a native-only call). Our parameter is named `oobCode`
  /// to match the deep-link key the storefront reads; it maps to the SDK's `code:` here.
  ///
  /// Possession of the emailed link is the authorisation for this operation — see the contract note
  /// on [AuthRepository.confirmPasswordReset]. Nothing is decided locally: the new password goes to
  /// Firebase, and role authority stays on `users/{uid}`.
  @override
  Future<void> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  }) async {
    final code = oobCode.trim();
    if (code.isEmpty) {
      throw const ValidationFailure(
        'That reset link is incomplete — open the link from the email, or send yourself a new one.',
        field: 'oobCode',
      );
    }
    if (newPassword.isEmpty) {
      throw const ValidationFailure(
        'Enter the new password you would like to use.',
        field: 'password',
      );
    }
    try {
      await FirebaseBackend.auth.confirmPasswordReset(code: code, newPassword: newPassword);
    } on FirebaseAuthException catch (error) {
      throw _mapResetError(error);
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<UserProfile> ensureProfile() async {
    final user = FirebaseBackend.auth.currentUser;
    if (user == null) throw const AuthFailure('Please sign in to continue.');
    return _ensure(user);
  }

  @override
  Future<void> updateProfile({
    String? displayName,
    String? phone,
    String? gstNumber,
    String? companyName,
    bool? notifyEmail,
    bool? notifyWhatsapp,
    bool? notifySms,
  }) async {
    final user = FirebaseBackend.auth.currentUser;
    if (user == null) throw const AuthFailure();
    final uid = user.uid;
    try {
      if (displayName != null) await user.updateDisplayName(displayName.trim());
      final fields = <String, Object?>{};
      if (displayName != null) fields['displayName'] = displayName.trim();
      if (phone != null) fields['phone'] = phone.trim();
      if (gstNumber != null) fields['gstNumber'] = gstNumber.trim();
      if (companyName != null) fields['companyName'] = companyName.trim();
      if (notifyEmail != null) fields['notifyEmail'] = notifyEmail;
      if (notifyWhatsapp != null) fields['notifyWhatsapp'] = notifyWhatsapp;
      if (notifySms != null) fields['notifySms'] = notifySms;
      if (fields.isEmpty) return;
      await Collections.user(uid).update(fields);
    } on FirebaseAuthException catch (error) {
      throw _mapAuthError(error);
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<void> applyForWholesale({
    required String companyName,
    required String contactName,
    required String phone,
    String? gstNumber,
    String? address,
    String? reason,
    String? expectedMonthlyVolume,
  }) async {
    final user = FirebaseBackend.auth.currentUser;
    if (user == null) throw const AuthFailure('Sign in to apply for wholesale pricing.');
    if (_cached?.isBlocked ?? false) throw const PermissionFailure('This account is suspended.');
    // The one intentional public write: create an application with status forced to 'pending'. The
    // onWholesaleApplicationCreated trigger flips the profile wholesaleStatus server-side; a client
    // can never set it itself.
    final doc = Collections.wholesaleApplications_.doc();
    final payload = <String, Object?>{
      'uid': user.uid,
      'companyName': companyName.trim(),
      'contactName': contactName.trim(),
      'phone': phone.trim(),
      'email': user.email ?? '',
      'gstNumber': gstNumber?.trim() ?? '',
      'address': address?.trim() ?? '',
      'reason': reason?.trim() ?? '',
      'expectedMonthlyVolume': expectedMonthlyVolume?.trim() ?? '',
      'status': WholesaleStatus.pending.code,
    };
    try {
      await doc.set(touchCreate(payload), SetOptions(merge: false));
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  @override
  Future<void> toggleWishlist(String productId, {required bool add}) async {
    final user = FirebaseBackend.auth.currentUser;
    if (user == null) throw const AuthFailure();
    if (_cached?.isBlocked ?? false) throw const PermissionFailure('This account is suspended.');
    final op = add
        ? FieldValue.arrayUnion(<String>[productId])
        : FieldValue.arrayRemove(<String>[productId]);
    try {
      await Collections.user(user.uid).update(<String, Object?>{
        'wishlistProductIds': op,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }

  Future<void> dispose() async {
    await _authSub?.cancel();
    await _profileSub?.cancel();
    await _controller.close();
    await _roleController.close();
  }

  /// Reset-link errors, mapped separately from [_mapAuthError] because that switch is written for
  /// credentials ("incorrect email or password") and would be a lie here: an expired link is not a
  /// wrong password, and sending someone back to the sign-in form does not help them.
  ///
  /// firebase_auth_web strips the `auth/` prefix before the code reaches us
  /// (`firebase_auth_web-6.3.1/lib/src/utils/web_utils.dart:89`), so these keys are bare. Firebase's
  /// docs for `confirmPasswordReset` name `expired-action-code` / `invalid-action-code`; current JS
  /// SDK builds answer the same failure as `code-expired` / `invalid-code`. Both spellings are
  /// handled rather than betting on one.
  static OmFailure _mapResetError(FirebaseAuthException error) => switch (error.code) {
        'expired-action-code' || 'code-expired' =>
          const ValidationFailure(
            'That reset link has expired. Request a new password email and open the fresh link.',
            field: 'oobCode',
          ),
        'invalid-action-code' || 'invalid-code' || 'invalid-oob-code' || 'malformed-oob-code' ||
        'argument-error' =>
          const ValidationFailure(
            'That reset link is not valid — it has either already been used or was damaged in '
            'transit. Send yourself a new one and open it in this browser.',
            field: 'oobCode',
          ),
        'user-not-found' =>
          const NotFoundFailure(
            'That reset link no longer belongs to an account on this store.',
          ),
        'user-disabled' =>
          const PermissionFailure(
            'This account has been suspended, so its password cannot be reset. Contact support.',
          ),
        'weak-password' =>
          const ValidationFailure('Choose a stronger password.', field: 'password'),
        'too-many-requests' =>
          const ServerFailure('Too many attempts. Please wait a few minutes and try again.'),
        'network-request-failed' => const NetworkFailure(),
        'requires-recent-login' || 'user-not-signed-in' =>
          // Not a session problem: completing a reset link needs no signed-in user at all.
          const ValidationFailure(
            'Open the link from the password-reset email to finish resetting the password.',
            field: 'oobCode',
          ),
        'operation-not-allowed' =>
          const PermissionFailure('Password reset is not enabled for this store.'),
        _ => ValidationFailure(
            error.message ?? 'The reset could not be completed. Send a new reset email.',
            field: 'oobCode',
          ),
      };

  static OmFailure _mapAuthError(FirebaseAuthException error) => switch (error.code) {
        'invalid-email' || 'user-disabled' || 'user-not-found' || 'wrong-password' ||
        'invalid-credential' || 'invalid-login-credentials' =>
          const AuthFailure('Incorrect email or password.'),
        'email-already-in-use' =>
          const ValidationFailure('That email is already registered.', field: 'email'),
        'weak-password' =>
          const ValidationFailure('Choose a stronger password.', field: 'password'),
        'too-many-requests' =>
          const ServerFailure('Too many attempts. Please wait and try again.'),
        'network-request-failed' => const NetworkFailure(),
        'requires-recent-login' => const AuthFailure(),
        'user-not-signed-in' => const AuthFailure(),
        'operation-not-allowed' =>
          const PermissionFailure('Email/password sign-in is not enabled for this store.'),
        _ => AuthFailure(error.message ?? 'Sign-in failed.'),
      };
}
