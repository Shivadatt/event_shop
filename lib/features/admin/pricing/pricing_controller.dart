import 'package:get/get.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_slabs.dart';

/// Pricing administration: quantity-band grids shared across products and negotiated per-customer
/// prices.
///
/// A slab grid is always validated with the shared `validateSlabGrid` (via [checkSlabGrid]) before
/// it is submitted, and `saveProduct` writes the grid + audit row on the server — this screen never
/// stores a price the pricing engine would disagree with. Customer overrides apply only on the
/// backend, so this UI records intent and the write re-checks the role.
final class PricingController extends AdminController {
  PricingController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final RxList<Product> products = <Product>[].obs;
  final Rxn<Product> selected = Rxn<Product>();
  final RxList<PriceSlab> workingSlabs = <PriceSlab>[].obs;
  final RxnString slabError = RxnString();
  final RxnInt slabErrorRow = RxnInt();

  final RxList<CustomerPriceOverride> overrides = <CustomerPriceOverride>[].obs;

  /// The repository has no customer-override listing method, so existing overrides cannot be read
  /// back; the panel can only record new ones and delete by a known id. See the NEEDS OWNER note on
  /// [loadOverrides].
  final RxBool overridesListUnavailable = true.obs;

  bool get hasSelection => selected.value != null;

  @override
  void onInit() {
    super.onInit();
    loadProducts();
    loadOverrides();
  }

  Future<void> loadProducts() async {
    final page = await guard<PagedResult<Product>>(
      () => _admin.listProducts(
        query: const CatalogQuery(status: ProductStatus.active),
        pageSize: 100,
      ),
    );
    products.assignAll(page?.items ?? const <Product>[]);
  }

  void selectProduct(Product? product) {
    selected.value = product;
    slabError.value = null;
    slabErrorRow.value = null;
    workingSlabs.assignAll(product == null ? <PriceSlab>[] : [...product.slabs]);
  }

  /// The editor hands back the whole grid; we store it and validate live so an operator sees the
  /// exact message the shared engine would throw before pressing save.
  void onSlabsChanged(List<PriceSlab> next) {
    workingSlabs.assignAll(next);
    final check = checkSlabGrid(workingSlabs.toList(growable: false));
    slabError.value = check.isValid ? null : check.displayMessage;
    slabErrorRow.value = check.rowIndex;
  }

  Future<bool> saveSlabs() async {
    final product = selected.value;
    if (product == null) return false;
    if (!validate()) {
      announce(slabError.value ?? 'Fix the price grid before saving.', error: true);
      return false;
    }
    final grid = sortedSlabs(workingSlabs.toList(growable: false));
    final saved = await mutate<Product>(() => _admin.saveProduct(product, slabs: grid));
    if (saved == null) {
      final error = failure.value;
      announce(error?.message ?? 'The price grid could not be saved.', error: true);
      return false;
    }
    selected.value = saved;
    announce(
      'Price bands saved. The write ran validateSlabGrid again on the server, wrote the audit row '
      'and is the same code the cart prices with.',
    );
    await loadProducts();
    return true;
  }

  bool validate() {
    final check = checkSlabGrid(workingSlabs.toList(growable: false));
    slabError.value = check.isValid ? null : check.displayMessage;
    slabErrorRow.value = check.rowIndex;
    return check.isValid;
  }

  // ----------------------------------------------------------- customer overrides

  Future<void> loadOverrides() async {
    // NEEDS OWNER(AdminRepository): Future<List<CustomerPriceOverride>> listCustomerPrices(
    //   {String? uid, String? productId, bool includeExpired}).
    // Without it this screen cannot show the negotiated prices that already exist; it can only add
    // new ones and delete by id, so it says so instead of pretending the list is complete.
    overrides.clear();
    overridesListUnavailable.value = true;
  }

  Future<bool> addOverride({
    required String uid,
    required String productId,
    required int unitPricePaise,
    String? variantId,
    String note = '',
    DateTime? expiresAt,
  }) async {
    final cleanUid = uid.trim();
    final cleanProduct = productId.trim();
    if (cleanUid.isEmpty || cleanProduct.isEmpty) {
      announce('A customer override needs both a customer id and a product id.', error: true);
      return false;
    }
    if (unitPricePaise <= 0) {
      announce('The override unit price must be above zero paise.', error: true);
      return false;
    }
    final override = CustomerPriceOverride(
      id: _overrideId(cleanUid, cleanProduct, variantId),
      uid: cleanUid,
      productId: cleanProduct,
      variantId: (variantId == null || variantId.trim().isEmpty) ? null : variantId.trim(),
      unitPricePaise: unitPricePaise,
      note: note.trim(),
      expiresAt: expiresAt,
    );
    final ok = await mutateVoid(() => _admin.saveCustomerPrice(override));
    if (!ok) {
      final error = failure.value;
      announce(error?.message ?? 'The override could not be saved.', error: true);
      return false;
    }
    overrides.add(override);
    announce(
      'Override recorded. Only the backend applies it at checkout, after re-checking your role — '
      'a value entered here does not itself change any live price.',
    );
    return true;
  }

  Future<bool> deleteOverride(String overrideId) async {
    if (overrideId.trim().isEmpty) return false;
    final ok = await mutateVoid(() => _admin.deleteCustomerPrice(overrideId.trim()));
    if (!ok) {
      final error = failure.value;
      announce(error?.message ?? 'The override could not be removed.', error: true);
      return false;
    }
    overrides.removeWhere((o) => o.id == overrideId.trim());
    announce('Override removed.', error: false);
    return true;
  }

  /// Document-id convention is server-owned; this mirrors the `${uid}__${product}` shape the write
  /// path expects. NEEDS OWNER confirms the exact key so an override saved here can be read back.
  String _overrideId(String uid, String productId, String? variantId) =>
      variantId == null || variantId.trim().isEmpty
          ? '${uid}__${productId}'
          : '${uid}__${productId}__${variantId.trim()}';
}
