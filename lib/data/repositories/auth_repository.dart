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
