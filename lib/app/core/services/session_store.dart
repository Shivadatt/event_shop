import 'package:get/get.dart';
import 'package:om_events/data/models/user_profile.dart';

/// The one place that answers "who is on this device right now".
///
/// Route guards must decide synchronously, and repositories answer asynchronously, so the
/// session is mirrored here as soon as the auth source emits. Only the Firebase implementation
/// writes to it — UI reads it.
final class SessionStore extends GetxService {
  SessionStore({UserProfile? initial}) : _profile = Rxn<UserProfile>(initial);

  final Rxn<UserProfile> _profile;

  UserProfile? get profile => _profile.value;
  String? get uid => _profile.value?.uid;
  bool get isSignedIn => _profile.value != null;

  /// Never derive this from a query parameter, a hidden menu, or a value in localStorage.
  UserRole get role => _profile.value?.role ?? UserRole.guest;

  bool get isAdmin => role.canManageStore;
  bool get canEditPricing => role.canEditPricing;
  bool get canSeeCostPrice => role.canSeeCostPrice;
  bool get hasWholesalePricing => _profile.value?.hasWholesalePricing ?? false;

  Rxn<UserProfile> get changes => _profile;

  bool get isBlocked => _profile.value?.isBlocked ?? false;

  /// Blocked accounts lose admin rights at the rules layer, not here: this mirror only reports
  /// what the profile document says, and every privileged call re-checks server-side.
  void set(UserProfile? value) => _profile.value = value;

  void clear() => _profile.value = null;
}
