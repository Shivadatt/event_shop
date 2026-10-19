import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/utils/om_slug.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/data/repositories/media_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_files.dart';
import 'package:om_events/features/admin/shared/admin_slabs.dart';

/// Products list. Filtering and paging are server-side: the table shows the page the repository
/// returned for the current filter, never a client-sliced copy of a larger set.
final class ProductsController extends AdminController with PagedAdminList<Product> {
  ProductsController();

  final AdminRepository _admin = Get.find<AdminRepository>();
  final CategoryRepository _categoryRepository = Get.find<CategoryRepository>();

  /// Loaded separately from the page of products, and only used to label the category filter and
  /// the table's category cell. A failure here must not blank the product table, so it reports into
  /// its own flag rather than the shared [failure] sink.
  final RxList<Category> categories = <Category>[].obs;
  final RxBool categoriesFailed = false.obs;

  /// Null means "any status", and it is sent as null rather than as a made-up filter value.
  final Rxn<ProductStatus> statusFilter = Rxn<ProductStatus>();
  final RxString search = ''.obs;
  final RxnString categoryIdFilter = RxnString();

  ProductStatus? get status => statusFilter.value;

  @override
  void onInit() {
    super.onInit();
    loadCategories();
    loadFirstPage();
  }

  Future<void> loadCategories() async {
    try {
      categories.assignAll(await _categoryRepository.tree());
      categoriesFailed.value = false;
    } on OmFailure {
      categoriesFailed.value = true;
    }
  }

  String categoryLabel(String categoryId) {
    for (final category in categories) {
      if (category.id == categoryId) return category.name;
    }
    return categoryId.isEmpty ? 'Uncategorised' : 'Unknown category';
  }

  bool get hasFilters =>
      search.value.isNotEmpty || statusFilter.value != null || categoryIdFilter.value != null;

  @override
  Future<PagedResult<Product>> fetch({String? cursor}) => _admin.listProducts(
        query: CatalogQuery(
          search: search.value,
          categoryId: categoryIdFilter.value,
          includeSubCategories: false,
          status: status ?? ProductStatus.active,
          pageSize: pageSize,
          cursor: cursor,
        ),
        status: status,
        pageSize: pageSize,
        cursor: cursor,
      );

  void applySearch(String value) {
    search.value = value.trim();
    loadFirstPage();
  }

  void applyStatus(ProductStatus? value) {
    statusFilter.value = value;
    loadFirstPage();
  }

  void applyCategory(String? value) {
    categoryIdFilter.value = value;
    loadFirstPage();
  }

  void clearFilters() {
    search.value = '';
    statusFilter.value = null;
    categoryIdFilter.value = null;
    loadFirstPage();
  }

  Future<void> setArchived(String productId, {required bool archived}) async {
    final ok = await mutateVoid(() => _admin.archiveProduct(productId, archived: archived));
    if (ok) {
      await loadFirstPage();
      announce(archived ? 'Product archived' : 'Product restored');
    } else {
      reportFailure();
    }
  }

  Future<Product?> duplicate(String productId) async {
    final copy = await mutate<Product>(() => _admin.duplicateProduct(productId));
    if (copy != null) {
      await loadFirstPage();
      announce('Copy created as ${copy.name}. Review its price and status before publishing.');
    } else {
      reportFailure();
    }
    return copy;
  }

  void openEditor(String productId) =>
      Get.toNamed<dynamic>(OmRoutes.forAdminProduct(productId));

  void openNew() => Get.toNamed<dynamic>(OmRoutes.adminProductNew);

  void reportFailure() {
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
  }
}

/// Create / edit form for one product: fields, images, variants and the price-slab grid.
///
/// Server-authority rules this class obeys:
/// * no payable total and no stock balance is ever sent — `stockQty`, `ratingAvg`, `ratingCount`
///   and `soldCount` are absent from `Product.toWriteMap()` and are owned by Cloud Functions;
/// * the slab grid is validated with the shared `validateSlabGrid` before submit, and the save
///   still goes through `AdminRepository.saveProduct`, whose Cloud Function re-validates it;
/// * cost price is only *collected* when the session may see it, and slug availability is only
///   *asked about* — the write remains the authority on both.
final class ProductEditController extends AdminController {
  ProductEditController({this.productId});

  /// Null means a new product.
  final String? productId;

  final AdminRepository _admin = Get.find<AdminRepository>();
  final ProductRepository _products = Get.find<ProductRepository>();
  final CategoryRepository _categories = Get.find<CategoryRepository>();
  final VariantRepository _variants = Get.find<VariantRepository>();
  final MediaRepository _media = Get.find<MediaRepository>();

  final Rxn<Product> product = Rxn<Product>();
  final RxList<Category> categories = <Category>[].obs;
  final RxList<ProductVariant> variantRows = <ProductVariant>[].obs;
  final RxList<PriceSlab> draftSlabs = <PriceSlab>[].obs;
  final RxList<String> issues = <String>[].obs;

  final RxnString slugAvailability = RxnString();
  final RxBool checkingSlug = false.obs;
  final RxBool uploading = false.obs;

  /// The last balance the server reported, as display text. Null means "not re-read this session",
  /// so the form shows the value the product document carried rather than implying a fresh read.
  final RxnString stockDisplay = RxnString();

  /// Set when `validateSlabGrid` rejects the grid; [slabErrorRowIndex] is the row it names, so the
  /// editor points at the offending band instead of showing a generic "invalid" banner.
  final Rxn<String> slabError = Rxn<String>();
  final Rxn<int> slabErrorRowIndex = Rxn<int>();

  bool get isNew => productId == null;
  bool get canSeeCost => session.canSeeCostPrice;
  bool get canEditPricing => session.canEditPricing;
  bool get mediaConfigured => _media.isConfigured;
  Product? get value => product.value;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    await guard<bool>(() async {
      categories.assignAll(await _categories.tree());
      if (isNew) {
        product.value = const Product(id: '', name: '');
      } else {
        final loaded = await _products.byId(productId!);
        product.value = loaded;
        draftSlabs.assignAll(loaded.slabs);
        variantRows.assignAll(await _variants.forProduct(loaded.id));
      }
      return true;
    });
  }

  // ------------------------------------------------------------------ fields

  void patch(Product Function(Product current) update) {
    final current = product.value;
    if (current == null) return;
    product.value = update(current);
  }

  /// `Product.copyWith` cannot reach `brand`, `packSize`, `unit`, `variants`, `saleFrom`, `saleTo`
  /// or `weightGrams`, so every edit rebuilds the document explicitly instead of quietly dropping
  /// the fields a copyWith would lose.
  Product _rebuild({
    String? name,
    String? slug,
    String? sku,
    String? description,
    String? categoryId,
    String? brand,
    String? packSize,
    String? unit,
    int? retailPricePaise,
    List<PriceSlab>? slabs,
    List<String>? variants,
    List<MediaRef>? images,
    int? minOrderQty,
    int? orderMultiple,
    int? lowStockThreshold,
    int? salePricePaise,
    bool clearSalePrice = false,
    DateTime? saleFrom,
    bool clearSaleFrom = false,
    DateTime? saleTo,
    bool clearSaleTo = false,
    ProductStatus? status,
    bool? isWholesaleOnly,
    bool? isFeatured,
    bool? isBestSeller,
    bool? isNewArrival,
    List<String>? tags,
    List<String>? keywords,
    String? seoTitle,
    String? seoDescription,
    int? weightGrams,
    bool clearWeight = false,
  }) {
    final p = product.value;
    if (p == null) throw const NotFoundFailure('Product not loaded');
    return Product(
      id: p.id,
      name: name ?? p.name,
      slug: slug ?? p.slug,
      sku: sku ?? p.sku,
      description: description ?? p.description,
      categoryId: categoryId ?? p.categoryId,
      brand: brand ?? p.brand,
      packSize: packSize ?? p.packSize,
      unit: unit ?? p.unit,
      retailPricePaise: retailPricePaise ?? p.retailPricePaise,
      slabs: slabs ?? p.slabs,
      variants: variants ?? p.variants,
      images: images ?? p.images,
      minOrderQty: minOrderQty ?? p.minOrderQty,
      orderMultiple: orderMultiple ?? p.orderMultiple,
      // Read-only mirror. The repository write path excludes it; keeping the loaded value here
      // means the on-screen balance is visible but never an input to the save.
      stockQty: p.stockQty,
      lowStockThreshold: lowStockThreshold ?? p.lowStockThreshold,
      salePricePaise: clearSalePrice ? null : (salePricePaise ?? p.salePricePaise),
      saleFrom: clearSaleFrom ? null : (saleFrom ?? p.saleFrom),
      saleTo: clearSaleTo ? null : (saleTo ?? p.saleTo),
      status: status ?? p.status,
      isWholesaleOnly: isWholesaleOnly ?? p.isWholesaleOnly,
      isFeatured: isFeatured ?? p.isFeatured,
      isBestSeller: isBestSeller ?? p.isBestSeller,
      isNewArrival: isNewArrival ?? p.isNewArrival,
      tags: tags ?? p.tags,
      keywords: keywords ?? p.keywords,
      seoTitle: seoTitle ?? p.seoTitle,
      seoDescription: seoDescription ?? p.seoDescription,
      ratingAvg: p.ratingAvg,
      ratingCount: p.ratingCount,
      soldCount: p.soldCount,
      weightGrams: clearWeight ? null : (weightGrams ?? p.weightGrams),
      createdAt: p.createdAt,
      updatedAt: p.updatedAt,
    );
  }

  void setName(String name) {
    final current = product.value;
    if (current == null) return;
    // The slug follows the name only while the operator has not typed one; after that it is
    // theirs, because a changed slug breaks an indexed URL.
    final shouldFollow = current.slug.isEmpty || current.slug == OmSlug.from(current.name);
    final next = shouldFollow ? OmSlug.from(name) : current.slug;
    patch((p) => _rebuild(name: name, slug: next));
    slugAvailability.value = null;
  }

  void setSlug(String raw) {
    final slug = OmSlug.from(raw);
    patch((p) => _rebuild(slug: slug));
    slugAvailability.value = null;
  }

  void setSku(String value) => patch((p) => _rebuild(sku: value.trim()));

  void setDescription(String value) => patch((p) => _rebuild(description: value));

  void setCategory(String? categoryId) => patch((p) => _rebuild(categoryId: categoryId ?? ''));

  void setBrand(String value) => patch((p) => _rebuild(brand: value));

  void setPackSize(String value) => patch((p) => _rebuild(packSize: value));

  void setUnit(String value) => patch((p) => _rebuild(unit: value));

  void setTags(List<String> tags) => patch((p) => _rebuild(tags: tags));

  void setKeywords(List<String> keywords) => patch((p) => _rebuild(keywords: keywords));

  void setRetailPrice(int paise) => patch((p) => _rebuild(retailPricePaise: paise));

  void setCostWeightGrams(int? grams) =>
      patch((p) => _rebuild(weightGrams: grams, clearWeight: grams == null));

  void setSalePrice(int? paise) =>
      patch((p) => _rebuild(salePricePaise: paise, clearSalePrice: paise == null));

  void setSaleFrom(DateTime? from) =>
      patch((p) => _rebuild(saleFrom: from, clearSaleFrom: from == null));

  void setSaleTo(DateTime? to) => patch((p) => _rebuild(saleTo: to, clearSaleTo: to == null));

  void setStatus(ProductStatus status) => patch((p) => _rebuild(status: status));

  void setMinOrderQty(int value) => patch((p) => _rebuild(minOrderQty: value));

  void setOrderMultiple(int value) => patch((p) => _rebuild(orderMultiple: value));

  void setLowStockThreshold(int value) => patch((p) => _rebuild(lowStockThreshold: value));

  void setSeo({String? title, String? description}) => patch(
        (p) => _rebuild(
          seoTitle: title ?? p.seoTitle,
          seoDescription: description ?? p.seoDescription,
        ),
      );

  void setFlags({bool? featured, bool? bestSeller, bool? newArrival, bool? wholesaleOnly}) => patch(
        (p) => _rebuild(
          isFeatured: featured ?? p.isFeatured,
          isBestSeller: bestSeller ?? p.isBestSeller,
          isNewArrival: newArrival ?? p.isNewArrival,
          isWholesaleOnly: wholesaleOnly ?? p.isWholesaleOnly,
        ),
      );

  /// `Product.copyWith` has no `variants` parameter, so the id list is maintained via `_rebuild`.
  void setVariantIds(List<String> ids) => patch((p) => _rebuild(variants: ids));

  // ------------------------------------------------------------------- slug

  /// Slug uniqueness is asked about, never asserted. `bySlug` is a server read, so the answer is
  /// the server's; a save that races another operator still fails server-side.
  Future<void> checkSlug(String raw) async {
    final candidate = OmSlug.from(raw);
    if (candidate.isEmpty || !OmSlug.isValid(candidate)) {
      checkingSlug.value = false;
      slugAvailability.value = candidate.isEmpty
          ? null
          : 'Not a valid slug: 2–96 lowercase letters, digits and single hyphens.';
      return;
    }
    checkingSlug.value = true;
    try {
      final existing = await _products.bySlug(candidate);
      final isSelf = !isNew && existing.id == productId;
      slugAvailability.value = isSelf
          ? 'This slug is already the one this product uses.'
          : 'Taken by ${existing.name}. Choose another.';
    } on NotFoundFailure {
      slugAvailability.value = 'Not used by any product.';
    } on OmFailure catch (error) {
      // A failed lookup is not an available slug. Saying "available" here would set the operator
      // up for a save error they cannot explain.
      slugAvailability.value = 'Could not check: ${error.message}';
    } finally {
      checkingSlug.value = false;
    }
  }

  // ------------------------------------------------------------------ slabs

  /// The rows are edited in the order they were entered — re-sorting while a field has focus would
  /// move the row under the cursor — so the error index below points at the displayed row.
  bool validateSlabs() {
    final check = checkSlabGrid(draftSlabs.toList(growable: false));
    slabError.value = check.isValid ? null : check.displayMessage;
    slabErrorRowIndex.value = check.rowIndex;
    return check.isValid;
  }

  void addSlabRow() {
    draftSlabs.add(
      nextSlabRow(
        draftSlabs.toList(growable: false),
        basePricePaise: product.value?.basePricePaise ?? 0,
      ),
    );
    validateSlabs();
  }

  void updateSlabRow(int index, PriceSlab slab) {
    if (index < 0 || index >= draftSlabs.length) return;
    draftSlabs[index] = slab;
    validateSlabs();
  }

  void removeSlabRow(int index) {
    if (index < 0 || index >= draftSlabs.length) return;
    draftSlabs.removeAt(index);
    validateSlabs();
  }

  /// Live preview of what the grid means at those quantities, produced by the one pricing
  /// implementation the cart uses. Below the first band the engine returns the shelf price, and the
  /// preview labels that rather than showing an empty cell.
  List<SlabPreviewRow> previewAt({
    List<int> quantities = const <int>[1, 9, 10, 21, 50],
    ProductVariant? variant,
  }) {
    final current = product.value;
    if (current == null) return const <SlabPreviewRow>[];
    return previewSlabGrid(
      product: current,
      slabs: draftSlabs.toList(growable: false),
      variant: variant,
      quantities: quantities,
    );
  }

  // ------------------------------------------------------------------ images

  /// Uploads bytes through the media repository. A reference that the repository did not return
  /// cannot appear in the form, so an unconfigured bucket produces a failure rather than a URL
  /// that 404s later.
  Future<void> uploadImages({
    required List<PickedImage> files,
    required String altText,
  }) async {
    final current = product.value;
    if (current == null || files.isEmpty) return;
    if (!_media.isConfigured) {
      announce(
        'Media storage is not configured, so uploads are disabled. Product text and prices can '
        'still be saved.',
        error: true,
      );
      return;
    }
    if (altText.trim().isEmpty) {
      announce('Alt text is required before an image can be added.', error: true);
      return;
    }
    uploading.value = true;
    final validation = _media.validate(
      byteLength: files.first.bytes.length,
      mimeType: files.first.mimeType,
      leadingBytes: files.first.bytes.take(16).toList(growable: false),
    );
    if (validation.isRejected) {
      uploading.value = false;
      announce(validation.error ?? 'That file is not an accepted image.', error: true);
      return;
    }
    final ownerId = current.id.isEmpty ? 'new' : current.id;
    final uploaded = await guard<List<MediaRef>>(
      () async {
        final refs = <MediaRef>[];
        var order = current.images.length;
        for (final file in files) {
          refs.add(
            await _media.upload(
              bytes: file.bytes,
              fileName: file.name,
              mimeType: file.mimeType,
              kind: MediaKind.product,
              ownerId: ownerId,
              altText: altText.trim(),
              order: order++,
            ),
          );
        }
        return refs;
      },
      asSubmitting: true,
    );
    uploading.value = false;
    if (uploaded == null) {
      announce(failure.value?.message ?? 'Upload failed.', error: true);
      return;
    }
    patch((p) => _rebuild(
          images: _renumber(<MediaRef>[...p.images, ...uploaded]),
        ));
    announce('${uploaded.length} image(s) uploaded to the media repository.');
  }

  Future<void> deleteImage(MediaRef ref) async {
    final current = product.value;
    if (current == null) return;
    final ok = await mutateVoid(() => _media.delete(ref));
    if (!ok) {
      announce(failure.value?.message ?? 'Could not delete the image.', error: true);
      return;
    }
    patch((p) => _rebuild(
          images: _renumber(p.images.where((i) => i.id != ref.id).toList(growable: false)),
        ));
  }

  void moveImage(int from, int to) {
    final current = product.value;
    if (current == null) return;
    if (from < 0 || to < 0 || from >= current.images.length || to >= current.images.length) {
      return;
    }
    // The reorder is applied to the closure's own product, not to the snapshot taken above, so a
    // concurrent edit in this session cannot be overwritten by a stale list.
    patch((p) {
      final next = [...p.images];
      if (from < 0 || to < 0 || from >= next.length || to >= next.length) return p;
      next.insert(to, next.removeAt(from));
      return _rebuild(images: _renumber(next));
    });
  }

  /// Exactly one primary: the flag is derived from position, so two documents cannot both claim
  /// the card image and `Product.primaryImage` stays predictable.
  void setPrimary(int index) {
    final current = product.value;
    if (current == null || index < 0 || index >= current.images.length) return;
    patch((p) {
      if (index < 0 || index >= p.images.length) return p;
      return _rebuild(images: _renumber([...p.images], primaryIndex: index));
    });
  }

  void setImageAlt(int index, String altText) {
    final current = product.value;
    if (current == null || index < 0 || index >= current.images.length) return;
    final next = [...current.images];
    next[index] = next[index].copyWith(altText: altText);
    patch((p) => _rebuild(images: next));
  }

  List<MediaRef> _renumber(List<MediaRef> images, {int primaryIndex = 0}) => <MediaRef>[
        for (var i = 0; i < images.length; i++)
          images[i].copyWith(order: i, isPrimary: i == primaryIndex),
      ];

  /// Writes the image list through the media repository, which also removes objects that are no
  /// longer referenced. Separate from [save] because a product write and an object delete are two
  /// different authorities.
  Future<void> commitImages() async {
    final current = product.value;
    if (current == null || current.id.isEmpty) {
      announce('Save the product before committing images.', error: true);
      return;
    }
    if (imagesMissingAlt(current.images)) {
      announce('Every image needs alt text before it can be committed.', error: true);
      return;
    }
    final ok = await mutateVoid(
      () => _media.commitProductImages(product: current, nextImages: current.images),
    );
    if (ok) {
      announce('Image list committed. Unreferenced objects were removed by the media service.');
    } else {
      announce(failure.value?.message ?? 'Could not commit images.', error: true);
    }
  }

  static bool imagesMissingAlt(List<MediaRef> images) =>
      images.any((image) => image.altText.trim().isEmpty);

  // ---------------------------------------------------------------- variants

  /// A variant write goes to the repository exactly as loaded. Cost price is deliberately NOT
  /// stripped here: `ProductVariant.toWriteMap({includeCost})` is the repository's decision, and a
  /// client that blanked the field for staff would silently delete a stored cost. `canSeeCostPrice`
  /// therefore only controls whether the number is shown or editable on screen.
  Future<void> saveVariant(ProductVariant variant) async {
    try {
      validateSlabGrid(variant.slabs);
    } on ValidationFailure catch (error) {
      slabError.value = 'Variant ${variant.name}: ${error.message}';
      announce(slabError.value!, error: true);
      return;
    }
    final ok = await mutateVoid(() => _admin.saveVariant(variant));
    if (!ok) {
      announce(failure.value?.message ?? 'Could not save the variant.', error: true);
      return;
    }
    slabError.value = null;
    final current = product.value;
    if (current != null) {
      variantRows.assignAll(await _variants.forProduct(current.id));
      setVariantIds(variantRows.map((v) => v.id).toList(growable: false));
    }
  }

  Future<void> deleteVariant(String variantId) async {
    final ok = await mutateVoid(() => _admin.deleteVariant(variantId));
    if (!ok) {
      announce(failure.value?.message ?? 'Could not delete the variant.', error: true);
      return;
    }
    variantRows.removeWhere((v) => v.id == variantId);
    setVariantIds(variantRows.map((v) => v.id).toList(growable: false));
  }

  // ------------------------------------------------------------------ submit

  /// Blocks locally for things the UI can know — a blank name, an image with no alt text, a sale
  /// window that ends before it starts. It is not the permission system and does not pretend to
  /// be: the price grid and the SKU uniqueness are still decided by the write.
  List<String> blockingIssues() {
    final current = product.value;
    if (current == null) return const <String>['Product not loaded.'];
    final found = <String>[];
    if (current.name.trim().isEmpty) found.add('Name is required.');
    if (!OmSlug.isValid(current.slug)) found.add('URL slug must be 2–96 lowercase characters.');
    if (current.sku.trim().isEmpty) found.add('SKU is required.');
    if (current.categoryId.isEmpty) found.add('Pick a category.');
    if (current.retailPricePaise <= 0) found.add('Retail price must be above zero.');
    if (imagesMissingAlt(current.images)) {
      for (var i = 0; i < current.images.length; i++) {
        if (current.images[i].altText.trim().isEmpty) {
          found.add('Image ${i + 1} has no alt text.');
        }
      }
    }
    if (current.orderMultiple < 1) found.add('Order multiple must be at least 1.');
    if (current.minOrderQty < 1) found.add('Minimum order quantity must be at least 1.');
    final multiple = current.orderMultiple < 1 ? 1 : current.orderMultiple;
    if (current.minOrderQty % multiple != 0) {
      found.add(
        'Minimum order quantity ${current.minOrderQty} is not a multiple of the order multiple '
        '$multiple, so the first legal order cannot be placed.',
      );
    }
    final from = current.saleFrom;
    final to = current.saleTo;
    if (from != null && to != null && !to.isAfter(from)) {
      found.add('The sale window must end after it starts.');
    }
    final sale = current.salePricePaise;
    if (sale != null && sale >= current.retailPricePaise) {
      found.add('A sale price must be below the retail price, or it is not a sale.');
    }
    if (!validateSlabs()) {
      found.add(slabError.value ?? 'The price slab grid is invalid.');
    }
    return found;
  }

  Future<Product?> save() async {
    final current = product.value;
    if (current == null) return null;
    final found = blockingIssues();
    issues.assignAll(found);
    if (found.isNotEmpty) {
      announce(found.first, error: true);
      return null;
    }
    final draft = _rebuild(slabs: draftSlabs.toList(growable: false));
    final saved = await mutate<Product>(
      () => _admin.saveProduct(
        draft,
        slabs: draftSlabs.toList(growable: false),
      ),
    );
    if (saved != null) {
      product.value = saved;
      draftSlabs.assignAll(saved.slabs);
      issues.clear();
      announce(
        'Saved. The slab grid was re-validated by the Cloud Function and the write is in the '
        'audit log.',
      );
      return saved;
    }
    final error = failure.value;
    if (error != null) {
      announce(error.message, error: true);
      if (error is ValidationFailure) slabError.value = error.message;
    }
    return null;
  }

  /// Server truth for the balance, re-read rather than inferred from what the form is showing.
  Future<int?> reloadStock() async {
    final current = product.value;
    if (current == null || current.id.isEmpty) return null;
    final qty = await mutate<int>(() => _admin.stockFor(current.id));
    if (qty != null) stockDisplay.value = '$qty units (read from the ledger)';
    return qty;
  }
}
