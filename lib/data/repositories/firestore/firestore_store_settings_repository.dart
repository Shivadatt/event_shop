import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/firebase/firebase_backend.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';

/// Public read of the singleton `store_settings/store` document.
///
/// `firestore.rules` already opens this document to every visitor (`allow read: if true`) and
/// forbids every client write, so the storefront can show shop identity, tax mode, delivery zones
/// and payment methods without a sign-in — the trusted copy still comes from `adminSettingsSave`.
///
/// A document that does not exist is a loud [NotFoundFailure] rather than
/// [StoreSettings.fallback]: a store that has never saved its settings has no tax rate, no zone
/// covering any pincode and no payment method, and pretending otherwise would let checkout display
/// prices the order server rejects. A document that does exist is mapped field by field through
/// `StoreSettings.fromMap`, so a sparse or wrongly-shaped field degrades to that field's model
/// default instead of failing the whole read.
final class FirestoreStoreSettingsRepository implements StoreSettingsRepository {
  const FirestoreStoreSettingsRepository();

  @override
  Future<StoreSettings> load() async {
    try {
      final snapshot = await Collections.settings().get();
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        throw const NotFoundFailure(
          'This store has not published its settings yet, so its tax rate, delivery zones and '
          'payment methods are unavailable.',
        );
      }
      return StoreSettings.fromMap(data);
    } on FirebaseException catch (error) {
      throw FirebaseBackend.mapFirebaseError(error);
    }
  }
}
