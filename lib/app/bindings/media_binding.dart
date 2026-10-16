import 'package:get/get.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/repositories/media_repository.dart';

/// Agent 4 owns this file. Binds the Supabase Storage implementation behind [MediaRepository] so
/// screens and admin forms can render and manage media without importing Supabase themselves.
///
/// When `SUPABASE_URL` / `SUPABASE_ANON_KEY` are absent, bind an implementation whose
/// `isConfigured` is false and whose methods throw [MediaFailure] — never a silent no-op that
/// lets an upload "succeed" while nothing was stored.
final class MediaBinding extends Bindings {
  @override
  void dependencies() {
    if (!Get.isRegistered<MediaRepository>()) {
      Get.lazyPut<MediaRepository>(UnconfiguredMediaRepository.new, fenix: true);
    }
  }
}

/// Explicit "not wired up" implementation. Every method fails loudly and `isConfigured` is false,
/// which is what the admin media screen shows as the reason the upload control is disabled.
final class UnconfiguredMediaRepository implements MediaRepository {
  @override
  bool get isConfigured => false;

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
  }) =>
      throw MediaFailure(
        'Supabase Storage is not configured '
        '(${Env.supabaseUrl.isEmpty ? 'SUPABASE_URL' : 'SUPABASE_ANON_KEY'} missing).',
      );

  @override
  Future<MediaRef> replace({
    required MediaRef existing,
    required List<int> bytes,
    required String fileName,
    required String mimeType,
    void Function(double fraction)? onProgress,
  }) =>
      throw const MediaFailure('Supabase Storage is not configured.');

  @override
  Future<void> delete(MediaRef ref) async =>
      throw const MediaFailure('Supabase Storage is not configured.');

  @override
  Future<void> deleteMany(List<MediaRef> refs) async =>
      throw const MediaFailure('Supabase Storage is not configured.');

  @override
  Future<OrphanScan> scanOrphans() async =>
      throw const MediaFailure('Supabase Storage is not configured.');

  @override
  Future<String> signedUrl(String storagePath,
          {Duration ttl = const Duration(minutes: 15)}) async =>
      throw const MediaFailure('Supabase Storage is not configured.');

  @override
  MediaValidation validate({
    required int byteLength,
    required String mimeType,
    required List<int> leadingBytes,
  }) =>
      const MediaValidation(
        isValid: false,
        error: 'Media storage is not configured, so uploads are disabled.',
      );

  @override
  Future<Product> commitProductImages({
    required Product product,
    required List<MediaRef> nextImages,
  }) async =>
      throw const MediaFailure('Supabase Storage is not configured.');
}
