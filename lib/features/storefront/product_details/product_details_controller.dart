import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/features/storefront/common/cart_store.dart';
import 'package:om_events/features/storefront/common/external_links.dart';
import 'package:om_events/features/storefront/common/line_price.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/common/settings_store.dart';
import 'package:om_events/features/storefront/common/wishlist_actions.dart';

/// Product detail page. Resolves the route's `:idOrSlug` (slug first, id fallback), loads variants,
/// related products and reviews, and turns the buyer's quantity intent into a cart line.
///
/// Authority boundaries (contract):
///  * the payable amount is NEVER decided here — only `PricingEngine` display math runs, and the
///    server recomputes everything at `OrderRepository.createOrder`;
///  * stock shown is advisory (from `ProductRepository.availableStock`), the server is the arbiter;
///  * this controller touches no Firestore/Supabase directly — everything goes through
///    `Get.find<XxxRepository>()`.
final class ProductDetailsController extends GetxController with WishlistToggleMixin {
  final Rxn<Product> product = Rxn<Product>();
  final Rxn<Category> category = Rxn<Category>();
  final RxList<ProductVariant> variants = <ProductVariant>[].obs;
  final Rxn<ProductVariant> selectedVariant = Rxn<ProductVariant>();
  final RxInt quantity = 1.obs;
  final RxList<Product> related = <Product>[].obs;
  final RxList<Review> reviews = <Review>[].obs;
  final Rxn<RatingBreakdown> breakdown = Rxn<RatingBreakdown>();
  final Rxn<int> availableStock = Rxn<int>();
  final RxBool loading = true.obs;
  final RxBool loadingExtras = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  OrderGranularity? _granularity;
  OrderGranularity get granularity => _granularity ?? const OrderGranularity();

  bool get hasProduct => product.value != null;
  String get routeIdOrSlug => Get.parameters['idOrSlug'] ?? '';

  ProductVariant? get variant => selectedVariant.value;

  /// True only when the advisory stock read explicitly reports zero; a failed/unknown read keeps
  /// the buy button live so the server (not a missing read) is the one that rejects.
  bool get isSoldOut {
    final p = product.value;
    if (p == null) return false;
    final v = variant;
    if (v != null) return v.stockQty <= 0;
    final stock = availableStock.value;
    if (stock != null) return stock <= 0;
    return p.isSoldOut;
  }

  int get currentStock {
    final v = variant;
    if (v != null) return v.stockQty;
    return availableStock.value ?? product.value?.stockQty ?? 0;
  }

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final idOrSlug = routeIdOrSlug;
    if (idOrSlug.isEmpty) {
      loading.value = false;
      failure.value = const NotFoundFailure('No product was requested.');
      return;
    }
    loading.value = true;
    failure.value = null;
    final loaded = await safeCall<Product>(
      () async {
        final repo = Get.find<ProductRepository>();
        try {
          return await repo.bySlug(idOrSlug);
        } on NotFoundFailure {
          return await repo.byId(idOrSlug);
        }
      },
      onFailure: (f) => failure.value = f,
    );
    product.value = loaded;
    loading.value = false;
    if (loaded == null) return;

    _granularity = OrderGranularity(minQty: loaded.minOrderQty, multiple: loaded.orderMultiple);
    quantity.value = _granularity!.clampQty(loaded.minOrderQty);
    _reprice();
    _loadExtras(loaded);
  }

  Future<void> _loadExtras(Product loaded) async {
    loadingExtras.value = true;
    Get.find<SessionStore>();
    if (loaded.categorySlug.isNotEmpty) {
      safeCall<Category>(() => Get.find<CategoryRepository>().bySlug(loaded.categorySlug))
          .then((c) => category.value = c);
    }
    safeCall<List<Product>>(() => Get.find<ProductRepository>().relatedTo(loaded, limit: 12))
        .then((r) => related.assignAll(r ?? const <Product>[]));
    safeCall<List<Review>>(() => Get.find<ReviewRepository>().forProduct(loaded.id))
        .then((l) => reviews.assignAll(l ?? const <Review>[]));
    safeCall<RatingBreakdown>(() => Get.find<ReviewRepository>().breakdownFor(loaded.id))
        .then((b) => breakdown.value = b);
    safeCall<List<ProductVariant>>(() => Get.find<VariantRepository>().forProduct(loaded.id))
        .then((v) {
      final list = v ?? const <ProductVariant>[];
      variants.assignAll(list);
      if (list.isNotEmpty) {
        selectedVariant.value = list.first;
        _applyVariantGranularity(list.first);
      }
    });
    safeCall<int>(
      () => Get.find<ProductRepository>().availableStock(
        loaded.id,
        variantId: variant?.id,
      ),
    ).then((s) => availableStock.value = s);
    loadingExtras.value = false;
  }

  void _applyVariantGranularity(ProductVariant v) {
    final p = product.value;
    _granularity = OrderGranularity(
      minQty: v.minOrderQty > 0 ? v.minOrderQty : (p?.minOrderQty ?? 1),
      multiple: p?.orderMultiple ?? 1,
    );
    quantity.value = _granularity!.clampQty(quantity.value);
    _reprice();
  }

  void selectVariant(ProductVariant? v) {
    selectedVariant.value = v;
    final p = product.value;
    if (p == null) return;
    if (v == null) {
      _granularity = OrderGranularity(minQty: p.minOrderQty, multiple: p.orderMultiple);
    } else {
      _applyVariantGranularity(v);
    }
    quantity.value = _granularity!.clampQty(quantity.value);
    // advisory stock is variant-specific; refresh without blocking the UI.
    safeCall<int>(
      () => Get.find<ProductRepository>().availableStock(p.id, variantId: v?.id),
    ).then((s) => availableStock.value = s);
    _reprice();
  }

  void setQuantity(int requested) {
    quantity.value = granularity.clampQty(requested);
    _reprice();
  }

  void increment() => setQuantity(quantity.value + granularity.multiple);
  void decrement() => setQuantity(quantity.value - granularity.multiple);

  LinePrice _line = LinePrice.unavailable();
  LinePrice get linePrice => _line;
  PriceResolution get resolution => _line.resolution;

  /// Slabs in the display order, for the slab table. Uses the engine's sort so a variant's slab
  /// grid replaces the product's exactly the way the price lookup does.
  List<PriceSlab> get displaySlabs {
    final p = product.value;
    if (p == null) return const <PriceSlab>[];
    try {
      return PricingEngine.sortedSlabsFor(product: p, variant: variant);
    } on OmFailure {
      return const <PriceSlab>[];
    }
  }

  void _reprice() {
    final p = product.value;
    if (p == null) {
      _line = LinePrice.unavailable();
      return;
    }
    _line = priceLine(product: p, qty: quantity.value, variant: variant);
  }

  /// Adds one cart line carrying the buyer's intent only (product, variant, quantity). Prices are
  /// re-derived when the cart renders, and the server re-derives again at checkout.
  void addToCart() {
    final p = product.value;
    if (p == null) return;
    final violation = granularity.violationFor(quantity.value);
    if (violation != null) {
      Get.snackbar('Adjust quantity', violation, snackDuration: const Duration(seconds: 3));
      return;
    }
    Get.find<CartStore>().add(
      CartLine(productId: p.id, variantId: variant?.id, qty: quantity.value),
    );
    Get.snackbar(
      'Added to cart',
      '${p.name} — ${quantity.value} × unit. Review the cart to continue.',
      snackDuration: const Duration(seconds: 2),
    );
  }

  void openCart() => Get.toNamed<dynamic>(OmRoutes.cart);

  void openCategory(Category c) =>
      Get.toNamed<dynamic>(OmRoutes.forCategory(c.pathSlug));

  void openProduct(Product other) =>
      Get.toNamed<dynamic>(OmRoutes.forProduct(other.pathSlug));

  void writeReview() {
    final p = product.value;
    if (p == null) return;
    final session = Get.find<SessionStore>();
    if (!session.isSignedIn) {
      Get.toNamed<dynamic>(
        OmRoutes.login,
        parameters: <String, String>{
          OmRouteArgs.returnUrl: Uri.encodeComponent(Get.currentRoute),
        },
      );
      return;
    }
    Get.toNamed<dynamic>(OmRoutes.forReview(p.id));
  }

  /// WhatsApp enquiry prefilled with the product name and SKU, straight from `StoreSettings`.
  Future<void> enquiryOnWhatsApp() async {
    final p = product.value;
    if (p == null) return;
    final settings = Get.find<SettingsStore>().value;
    final link = settings.whatsappLink;
    if (link.isEmpty) {
      Get.snackbar('Unavailable', 'The store has not published a WhatsApp number yet.',
          snackDuration: const Duration(seconds: 3));
      return;
    }
    final message = 'Hello, I would like to enquire about "${p.name}"'
        '${p.sku.isNotEmpty ? ' (SKU ${p.sku})' : ''}.';
    await OmExternalLink.open(
      Get.context!,
      OmExternalLink.whatsappChat(link, message: message),
      label: 'WhatsApp enquiry',
    );
  }

  Future<void> openMap() async {
    final settings = Get.find<SettingsStore>().value;
    if (settings.googleMapsUrl.isEmpty) {
      Get.snackbar('Unavailable', 'The store has not published a map link yet.',
          snackDuration: const Duration(seconds: 3));
      return;
    }
    await OmExternalLink.open(Get.context!, settings.googleMapsUrl, label: 'Store map');
  }

  Future<void> copyShareLink() =>
      OmExternalLink.copy(Get.location, note: 'Product link copied — paste it to share.');

  void retry() => load();
}
