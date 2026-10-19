import 'package:om_events/data/models/user_profile.dart';

/// Everything the app knows about "who is using it". Implementations live in
/// `lib/app/core/services/firebase/` (Agent 3).
abstract interface class AuthRepository {
  /// Emits null on sign-out. The session user is the Firestore profile document, not the
  /// Firebase Auth account, because role and wholesale approval are data, not token claims.
  Stream<UserProfile?> get profileChanges;

  UserProfile? get cachedProfile;

  Future<UserProfile> signIn({required String email, required String password});

  Future<UserProfile> signUp({
    required String email,
    required String password,
    required String displayName,
    String? phone,
  });

  Future<void> signOut();

  Future<void> sendPasswordReset(String email);

  /// Completes the reset email: swaps the OOB code from the deep link for a new password.
  ///
  /// `oobCode` is the value the storefront extracts as `Get.parameters['oobCode']` (the `oobCode`
  /// query parameter of the Firebase action link); `newPassword` is the user's chosen password.
  /// The names are part of the contract — the caller must not have to guess them.
  ///
  /// Security posture: this is safe to call from the client because the code *is* the proof. Only
  /// whoever received the reset email holds it, Firebase expires and single-uses it server-side, and
  /// the operation can only ever change the password of the account the email was sent to. It grants
  /// no privilege by itself: a role, a wholesale tier or a suspension is decided exclusively by the
  /// `users/{uid}` Firestore document, re-read via `requireRole` in the callables — never by this
  /// call and never by a token claim. An attacker with a valid code gains a password, not an admin.
  ///
  /// Implementations translate Firebase's error codes into [OmFailure]s; an expired or already-used
  /// code must read differently from a malformed one, and a blank code must be rejected locally
  /// rather than burned against the network.
  Future<void> confirmPasswordReset({
    required String oobCode,
    required String newPassword,
  });

  /// Guest checkout: no account is created, and `orders.createOrder` links the order to the
  /// supplied contact instead.
  Future<UserProfile> ensureProfile();

  Future<void> updateProfile({
    String? displayName,
    String? phone,
    String? gstNumber,
    String? companyName,
    bool? notifyEmail,
    bool? notifyWhatsapp,
    bool? notifySms,
  });

  /// Wholesale status changes go through the function, never a direct document write: a client
  /// must not be able to promote itself to wholesale pricing.
  Future<void> applyForWholesale({
    required String companyName,
    required String contactName,
    required String phone,
    String? gstNumber,
    String? address,
    String? reason,
    String? expectedMonthlyVolume,
  });

  Future<void> toggleWishlist(String productId, {required bool add});

  Stream<UserRole> get roleChanges;
}
