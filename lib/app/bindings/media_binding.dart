import 'package:get/get.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/services/media/media_object_ledger.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/media_repository.dart';
import 'package:om_events/data/repositories/supabase/supabase_media_repository.dart';

/// Agent 4's binding: the Supabase Storage implementation behind [MediaRepository].
///
/// Screens and admin forms depend on the interface only, so nothing above this file imports
/// `supabase_flutter`. The important property is *which* implementation is bound when the build is
/// not configured: an explicit failing one, never a silent no-op that lets an upload "succeed"
/// while no bytes were stored.
final class MediaBinding extends Bindings {
  @override
  void dependencies() {
    if (Get.isRegistered<MediaRepository>()) return;
    if (MediaConfig.isConfigured) {
      Get.lazyPut<MediaRepository>(SupabaseMediaRepository.new, fenix: true);
    } else {
      Get.lazyPut<MediaRepository>(UnconfiguredMediaRepository.new, fenix: true);
    }
  }
}

/// Explicit "not wired up" implementation, used when `SUPABASE_URL` / `SUPABASE_ANON_KEY` are absent
/// or `Supabase.initialize()` refused them.
///
/// `isConfigured` is false — which is what the admin media screen renders as "media storage not
/// configured" alongside the exact missing key names — and every method throws [MediaFailure] with
/// that same explanation. Deliberately does *not* implement `MediaUploadPipeline`: a form that asks
/// for an upload queue gets `null` behaviour and shows the notice instead of a picker that cannot
/// finish.
final class UnconfiguredMediaRepository implements MediaRepository {
  @override
  bool get isConfigured => false;

  /// Presentable reason, straight from the same source the service layer uses so the two can never
  /// disagree about what is missing.
  String get statusMessage => MediaConfig.statusMessage;

  Never _unavailable(String action) => MediaConfig.unavailable(action: action);

  @override
  Future<MediaRef> upload({
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    required MediaKind kind,
    required String ownerId,
    String altText = '',
    int order = 0,
    void Function(double fraction)? onProgress,
  }) async =>
      _unavailable('upload $fileName');

  @override
  Future<MediaRef> replace({
    required MediaRef existing,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    void Function(double fraction)? onProgress,
  }) async =>
      _unavailable('replace ${existing.storagePath}');

  @override
  Future<void> delete(MediaRef ref) async => _unavailable('delete ${ref.storagePath}');

  @override
  Future<void> deleteMany(List<MediaRef> refs) async =>
      _unavailable('delete ${refs.length} media object(s)');

  @override
  Future<OrphanScan> scanOrphans() async => _unavailable('scan the media bucket');

  /// No ledger rows can be read here, so this reports the same explanation as every other method
  /// rather than an empty page that would look like "the media library is empty".
  @override
  Future<PagedResult<MediaObjectRecord>> listMedia({
    String? kind,
    MediaObjectState? state,
    bool missingAltOnly = false,
    int pageSize = 24,
    String? cursor,
  }) async =>
      _unavailable('list the media library');

  @override
  Future<String> signedUrl(
    String storagePath, {
    Duration ttl = const Duration(minutes: 15),
  }) async =>
      _unavailable('sign a URL for $storagePath');

  @override
  MediaValidation validate({
    required int byteLength,
    required String mimeType,
    required List<int> leadingBytes,
  }) =>
      MediaValidation(isValid: false, error: MediaConfig.unavailableMessage('accept an upload'));

  @override
  Future<Product> commitProductImages({
    required Product product,
    required List<MediaRef> nextImages,
  }) async =>
      _unavailable('save images for ${product.id}');
}

/// Convenience for the one caller that must know the difference between "not configured" and
/// "configured but Firebase bookkeeping is missing": the admin panel's health card.
abstract final class MediaBindingStatus {
  static bool get supabaseConfigured => MediaConfig.isConfigured;
  static bool get firestoreConfigured => Env.hasFirebase;
  static String get summary => MediaConfig.statusMessage;

  /// Both backends have their keys *and* this bundle carries no privileged Supabase credential.
  /// The health card's single answer to "is this build even shippable" — the service-role half of
  /// it is enforced at boot by `AppBootstrap.assertNoPrivilegedKeyInBundle`, so a false here means
  /// the app never rendered in the first place.
  static bool get isFullyConfigured => Env.isFullyConfigured;

  /// True when the bound repository can actually transfer bytes.
  static bool get canUpload {
    if (!Get.isRegistered<MediaRepository>()) return false;
    return Get.find<MediaRepository>().isConfigured;
  }

  /// Thrown by [MediaBinding] consumers that need the pipeline rather than the notice.
  static Never unavailable({String? action}) => MediaConfig.unavailable(action: action);
}
