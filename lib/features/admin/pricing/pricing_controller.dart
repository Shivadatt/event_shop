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

  /// True while the negotiated-price list could not be read back. The screen then says so instead
  /// of showing an empty list that would look like "no overrides exist".
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
        query: const CatalogQuery(),
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

  Future<void> loadOverrides({String? uid, String? productId}) async {
    // AGREED with the backend owner (r2 convergence list):
    // `Future<List<CustomerPriceOverride>> listCustomerPrices({String? productId, String? uid})`.
    // The read is scoped server-side; nothing here fetches every override and filters it in the
    // browser, because negotiated prices for other customers must not reach this tab at all.
    _listScopeUid = uid;
    _listScopeProductId = productId;
    final rows = await guard<List<CustomerPriceOverride>>(
      () => _admin.listCustomerPrices(uid: uid, productId: productId),
    );
    if (rows == null) {
      overrides.clear();
      overridesListUnavailable.value = true;
      return;
    }
    overridesListUnavailable.value = false;
    overrides.assignAll(rows);
  }

  /// The scope the last list read used, so a reload after a write shows the same rows it showed
  /// before rather than silently widening to every customer's negotiated prices.
  String? _listScopeUid;
  String? _listScopeProductId;

  /// Re-reads the list at the scope it was last shown at. This is how the screen learns the
  /// server-minted id of a row it just saved.
  Future<void> reloadOverrides() =>
      loadOverrides(uid: _listScopeUid, productId: _listScopeProductId);

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
    // An empty id means "the server mints the document key". `adminCustomerPriceSave` does
    // `data.id ? String(data.id) : newId()`, and an id supplied here is treated as an *update* —
    // the function now rejects an id belonging to a different customer/product pair. So the client
    // must never build a key: a fabricated `${uid}__${productId}` would either create a second row
    // for the same pair at another price, or aim at a row that does not exist.
    final override = CustomerPriceOverride(
      id: '',
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
    // The saved row's real key is only ever known to the server, and `saveCustomerPrice` is typed
    // `Future<void>` so the callable's `{ id, ...doc }` response is dropped at the repository.
    // Therefore the list read IS the identity source: every later edit and delete on this screen is
    // driven from the id `listCustomerPrices` returned.
    await reloadOverrides();
    if (overridesListUnavailable.value) {
      // The write landed but the read did not, so this screen cannot know the key. Keeping a local
      // row with a blank id would be a trap — it could never be deleted — so the rows stay hidden
      // and the operator is told to reload.
      announce(
        'Override saved, but the stored list could not be read back, so this screen cannot show '
        'its server id. Use "Reload override list" to pick the row up before editing or deleting '
        'it.',
        error: true,
      );
      return true;
    }
    announce(
      'Override recorded. Only the backend applies it at checkout, after re-checking your role — '
      'a value entered here does not itself change any live price.',
    );
    return true;
  }

  /// Deletes by the id the server returned from `listCustomerPrices`, never a locally built key.
  Future<bool> deleteOverride(String overrideId) async {
    final id = overrideId.trim();
    if (id.isEmpty) {
      announce(
        'This row has no server id, so it cannot be deleted. Reload the override list first.',
        error: true,
      );
      return false;
    }
    final ok = await mutateVoid(() => _admin.deleteCustomerPrice(id));
    if (!ok) {
      // `adminCustomerPriceDelete` now throws `not-found` instead of silently succeeding on a
      // missing row, so a message here always means the price may still be applying.
      final error = failure.value;
      announce(
        error?.message ?? 'The override could not be removed — the backend did not confirm it.',
        error: true,
      );
      return false;
    }
    // Re-read rather than dropping the row locally: the list is the only place the ids come from,
    // and a row the server refused to delete must not disappear from the screen.
    await reloadOverrides();
    announce('Override removed.');
    return true;
  }
}
