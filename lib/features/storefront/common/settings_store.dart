import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/store_settings.dart';

/// Public read of the singleton `store_settings/{store}` document.
///
/// `AdminRepository.settings()` is staff-gated, but the storefront needs shop identity,
/// policies, zones and payment methods for every visitor. Agent 3 binds the real implementation
/// in `BackendBinding`; until something is registered, `SettingsStore` shows this honest failure
/// instead of inventing a store.
abstract interface class StoreSettingsRepository {
  Future<StoreSettings> load();
}

/// Placeholder bound by the storefront's own binding only when no real repository exists.
/// It fails visibly, mirroring `UnconfiguredMediaRepository`.
final class UnboundStoreSettingsRepository implements StoreSettingsRepository {
  const UnboundStoreSettingsRepository();

  @override
  Future<StoreSettings> load() async {
    throw const ServerFailure(
      'Store settings are not connected to a backend yet. '
      'A StoreSettingsRepository implementation must be bound.',
    );
  }
}

/// App-wide cached copy of the public settings. UI never awaits the repository directly; it
/// reads this store and gets a retry handle when the load failed.
final class SettingsStore extends GetxService {
  SettingsStore({StoreSettingsRepository? repository}) : _injected = repository;

  final StoreSettingsRepository? _injected;

  final Rxn<StoreSettings> settings = Rxn<StoreSettings>();
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxBool loading = false.obs;

  StoreSettingsRepository get _repository =>
      _injected ?? Get.find<StoreSettingsRepository>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    try {
      settings.value = await _repository.load();
    } on OmFailure catch (error) {
      failure.value = error;
    } catch (_) {
      failure.value = const ServerFailure();
    } finally {
      loading.value = false;
    }
  }

  /// Convenience for widgets that only need identity fields and can live with the tokenised
  /// defaults (`shopName`, `tagline` carry brand defaults in the model itself).
  StoreSettings get value => settings.value ?? StoreSettings.fallback;
  bool get isLive => settings.value != null;
}
