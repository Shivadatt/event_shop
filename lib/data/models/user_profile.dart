import 'package:om_events/data/om_doc.dart';

/// Roles are mirrored from Firestore for UI only. `isAdmin` decisions in rules and Cloud
/// Functions read the persisted document, never a value the bundle supplied.
enum UserRole {
  guest('guest'),
  customer('customer'),
  wholesale('wholesale'),
  staff('staff'),
  admin('admin'),
  owner('owner');

  const UserRole(this.code);
  final String code;

  bool get canManageStore => this == staff || this == admin || this == owner;
  bool get canEditPricing => this == admin || this == owner;
  bool get canSeeCostPrice => this == admin || this == owner;
  bool get isPrivileged => canManageStore;
}

UserRole userRoleFromCode(String code) =>
    UserRole.values.firstWhere((r) => r.code == code, orElse: () => UserRole.customer);

enum WholesaleStatus {
  none('none'),
  pending('pending'),
  approved('approved'),
  rejected('rejected');

  const WholesaleStatus(this.code);
  final String code;
}

WholesaleStatus wholesaleStatusFromCode(String code) => WholesaleStatus.values
    .firstWhere((s) => s.code == code, orElse: () => WholesaleStatus.none);

final class UserProfile {
  const UserProfile({
    required this.uid,
    this.email = '',
    this.phone = '',
    this.displayName = '',
    this.role = UserRole.customer,
    this.wholesaleStatus = WholesaleStatus.none,
    this.gstNumber = '',
    this.companyName = '',
    this.isBlocked = false,
    this.notifyEmail = true,
    this.notifyWhatsapp = false,
    this.notifySms = false,
    this.wishlistProductIds = const <String>[],
    this.createdAt,
    this.updatedAt,
    this.lastOrderAt,
  });

  final String uid;
  final String email;
  final String phone;
  final String displayName;
  final UserRole role;
  final WholesaleStatus wholesaleStatus;

  /// Wholesale buyers need this on invoices; kept on the profile so checkout can prefill.
  final String gstNumber;
  final String companyName;
  final bool isBlocked;
  final bool notifyEmail;
  final bool notifyWhatsapp;
  final bool notifySms;

  /// Bounded list: the wishlist is capped at [maxWishlistItems] so the document cannot grow
  /// without limit.
  final List<String> wishlistProductIds;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? lastOrderAt;

  static const int maxWishlistItems = 500;

  bool get isAdminAreaAllowed => role.canManageStore;

  /// Wholesale pricing unlocks only after an admin approves the application — a self-declared
  /// role in the client never counts.
  bool get hasWholesalePricing =>
      role == UserRole.wholesale ||
      (role.canManageStore) ||
      wholesaleStatus == WholesaleStatus.approved;

  factory UserProfile.fromMap(Map<String, dynamic> m, {String? uid}) => UserProfile(
        uid: uid ?? readStringOrEmpty(m, 'uid'),
        email: readStringOrEmpty(m, 'email'),
        phone: readStringOrEmpty(m, 'phone'),
        displayName: readStringOrEmpty(m, 'displayName'),
        role: userRoleFromCode(readStringOrEmpty(m, 'role')),
        wholesaleStatus: wholesaleStatusFromCode(readStringOrEmpty(m, 'wholesaleStatus')),
        gstNumber: readStringOrEmpty(m, 'gstNumber'),
        companyName: readStringOrEmpty(m, 'companyName'),
        isBlocked: readBool(m, 'isBlocked'),
        notifyEmail: readBool(m, 'notifyEmail', fallback: true),
        notifyWhatsapp: readBool(m, 'notifyWhatsapp'),
        notifySms: readBool(m, 'notifySms'),
        wishlistProductIds: readStringList(m, 'wishlistProductIds'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
        lastOrderAt: readDate(m, 'lastOrderAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'email': email,
        'phone': phone,
        'displayName': displayName,
        'role': role.code,
        'wholesaleStatus': wholesaleStatus.code,
        'gstNumber': gstNumber,
        'companyName': companyName,
        'notifyEmail': notifyEmail,
        'notifyWhatsapp': notifyWhatsapp,
        'notifySms': notifySms,
        'wishlistProductIds': wishlistProductIds.take(maxWishlistItems).toList(),
      });

  UserProfile copyWith({
    String? email,
    String? phone,
    String? displayName,
    UserRole? role,
    WholesaleStatus? wholesaleStatus,
    String? gstNumber,
    String? companyName,
    bool? isBlocked,
    bool? notifyEmail,
    bool? notifyWhatsapp,
    bool? notifySms,
    List<String>? wishlistProductIds,
    DateTime? lastOrderAt,
  }) =>
      UserProfile(
        uid: uid,
        email: email ?? this.email,
        phone: phone ?? this.phone,
        displayName: displayName ?? this.displayName,
        role: role ?? this.role,
        wholesaleStatus: wholesaleStatus ?? this.wholesaleStatus,
        gstNumber: gstNumber ?? this.gstNumber,
        companyName: companyName ?? this.companyName,
        isBlocked: isBlocked ?? this.isBlocked,
        notifyEmail: notifyEmail ?? this.notifyEmail,
        notifyWhatsapp: notifyWhatsapp ?? this.notifyWhatsapp,
        notifySms: notifySms ?? this.notifySms,
        wishlistProductIds: wishlistProductIds ?? this.wishlistProductIds,
        createdAt: createdAt,
        updatedAt: updatedAt,
        lastOrderAt: lastOrderAt ?? this.lastOrderAt,
      );
}
