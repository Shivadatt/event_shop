import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// How the stock table is being sourced. Both branches are server reads; the difference is only
/// which privileged query the repository runs.
enum StockScope {
  /// Every product, server-paginated.
  all,

  /// The server's low-stock report, including sold-out rows. A bounded read, not a page.
  low,

  /// Products with stock above zero, server-paginated.
  inStock,
}

/// Stock table.
///
/// `Product.stockQty` is a read-only mirror of the ledger, so this screen never sends a balance:
/// stock changes go through [StockAdjustController], which writes an append-only movement and lets
/// the function recompute the mirror.
final class InventoryController extends AdminController with PagedAdminList<Product> {
  InventoryController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final RxString search = ''.obs;
  final RxnString categoryIdFilter = RxnString();
  final Rx<StockScope> scope = StockScope.all.obs;
  final RxList<Product> lowReport = <Product>[].obs;
  final RxBool lowReportFailed = false.obs;

  /// The row the adjustment form and the ledger panel are pointed at.
  final RxnString selectedProductId = RxnString();

  Product? get selected {
    final id = selectedProductId.value;
    if (id == null) return null;
    for (final product in rows) {
      if (product.id == id) return product;
    }
    return null;
  }

  bool get isReportMode => scope.value == StockScope.low;

  @override
  void onInit() {
    super.onInit();
    loadFirstPage();
  }

  bool get hasFilters =>
      search.value.isNotEmpty || categoryIdFilter.value != null || scope.value != StockScope.all;

  @override
  Future<PagedResult<Product>> fetch({String? cursor}) => _admin.listProducts(
        query: CatalogQuery(
          search: search.value,
          categoryId: categoryIdFilter.value,
          includeSubCategories: false,
          inStockOnly: scope.value == StockScope.inStock,
          pageSize: pageSize,
          cursor: cursor,
        ),
        status: ProductStatus.active,
        pageSize: pageSize,
        cursor: cursor,
      );

  /// Low-stock uses the report the dashboard already computes server-side, so the threshold logic
  /// lives in one place instead of being re-derived from whatever page happens to be loaded.
  Future<void> loadLowReport() async {
    lowReportFailed.value = false;
    final report = await guard<List<Product>>(_admin.lowStockReport);
    if (report != null) lowReport.assignAll(report);
  }

  void applyScope(StockScope value) {
    scope.value = value;
    if (value == StockScope.low) {
      clearRows();
      loadLowReport();
      return;
    }
    loadFirstPage();
  }

  void applySearch(String value) {
    search.value = value.trim();
    if (isReportMode) {
      loadLowReport();
      return;
    }
    loadFirstPage();
  }

  void applyCategory(String? value) {
    categoryIdFilter.value = value;
    if (isReportMode) {
      announce('The low-stock report cannot be narrowed by category; switch to All stock first.');
      return;
    }
    loadFirstPage();
  }

  void clearFilters() {
    search.value = '';
    categoryIdFilter.value = null;
    scope.value = StockScope.all;
    loadFirstPage();
  }

  void select(String productId) {
    selectedProductId.value = selectedProductId.value == productId ? null : productId;
  }

  /// The displayed list is either the server page or the server report — never a client filter of
  /// a larger set.
  List<Product> get visibleRows => isReportMode ? lowReport.toList(growable: false) : rows;

  /// Low-stock thresholds are a product field, not a ledger entry, so this write goes through the
  /// privileged product save. `stockQty` is absent from `Product.toWriteMap`, so a threshold edit
  /// cannot move a balance even by accident.
  Future<bool> setThreshold(Product product, int threshold) async {
    if (threshold < 0) {
      announce('A low-stock threshold cannot be negative.', error: true);
      return false;
    }
    if (threshold == product.lowStockThreshold) return false;
    final updated = await mutate<Product>(
      () => _admin.saveProduct(product.copyWith(lowStockThreshold: threshold)),
    );
    if (updated != null) {
      if (isReportMode) {
        await loadLowReport();
      } else {
        await loadFirstPage();
      }
      announce(
        'Threshold for ${updated.name} is now ${updated.lowStockThreshold}. The re-check of your '
        'role and the audit row were done by the write, not by this dialog.',
      );
      return true;
    }
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
    return false;
  }

  String exportLoaded() {
    final source = visibleRows;
    return OmCsv.build(
      headers: const <String>[
        'name',
        'sku',
        'stockQty',
        'lowStockThreshold',
        'state',
        'unitCostVisible',
        'productId',
      ],
      rows: <List<Object?>>[
        for (final product in source)
          <Object?>[
            product.name,
            product.sku,
            product.stockQty,
            product.lowStockThreshold,
            product.isSoldOut
                ? 'out'
                : product.isLowStock
                    ? 'low'
                    : 'ok',
            session.canSeeCostPrice ? 'yes' : 'no',
            product.id,
          ],
      ],
    );
  }
}

/// The append-only stock movement form.
///
/// There is deliberately no "set stock to N" field for an existing balance: a balance is derived,
/// so an operator states a quantity plus a movement kind plus a reason and the function applies the
/// signed delta. Opening stock is the one exception, because a product with no ledger needs an
/// `opening` row to start from.
final class StockAdjustController extends AdminController {
  StockAdjustController();

  final AdminRepository _admin = Get.find<AdminRepository>();
  final InventoryController _list = Get.find<InventoryController>();

  final RxnString productId = RxnString();
  final Rxn<StockMovementKind> kind = Rxn<StockMovementKind>();
  final RxInt quantity = 0.obs;
  final RxString reason = ''.obs;
  final RxString reference = ''.obs;
  final RxnString unitCostText = RxnString();
  final RxnString variantId = RxnString();

  bool get canSeeCost => session.canSeeCostPrice;

  /// Movements an operator may write by hand. `saleOut` and `cancelRestore` are order-driven and are
  /// not offered here — writing one by hand would corrupt the ledger that checkout relies on.
  static const List<StockMovementKind> writableKinds = <StockMovementKind>[
    StockMovementKind.purchaseIn,
    StockMovementKind.manualAdjust,
    StockMovementKind.damaged,
    StockMovementKind.transferOut,
    StockMovementKind.returnIn,
    StockMovementKind.opening,
  ];

  int get signedDelta {
    final value = kind.value;
    if (value == null) return 0;
    final qty = quantity.value.abs();
    if (value == StockMovementKind.opening) return qty;
    return qty * value.sign;
  }

  List<String> blockingIssues() {
    final found = <String>[];
    if (productId.value == null || productId.value!.isEmpty) {
      found.add('Pick the product this movement belongs to.');
    }
    final selectedKind = kind.value;
    if (selectedKind == null) found.add('Pick a movement kind.');
    if (quantity.value <= 0) found.add('Quantity must be above zero.');
    if (reason.value.trim().isEmpty) {
      found.add('A reason is required — it is written to the audit log and the ledger row.');
    }
    if (selectedKind != StockMovementKind.opening &&
        selectedKind != null &&
        selectedKind.sign < 0) {
      final product = _productById(productId.value);
      if (product != null && quantity.value > product.stockQty) {
        found.add(
          'This would take ${product.name} below zero on the current mirror '
          '(${product.stockQty} shown). Outbound movements above the available quantity are '
          'refused by the function.',
        );
      }
    }
    if (unitCostText.value != null && unitCostText.value!.trim().isNotEmpty) {
      if (AdminFormat.paiseFromRupeeText(unitCostText.value!) <= 0) {
        found.add('Unit cost, if given, must be above zero.');
      }
    }
    return found;
  }

  Product? _productById(String? id) {
    if (id == null) return _list.selected;
    for (final product in _list.visibleRows) {
      if (product.id == id) return product;
    }
    return id == _list.selected?.id ? _list.selected : null;
  }

  Product? get target => _productById(productId.value);

  void setProduct(String? id) {
    productId.value = id;
    if (id != null) _list.select(id);
  }

  void setKind(StockMovementKind? value) => kind.value = value;

  void setQuantity(String text) => quantity.value = int.tryParse(text.trim()) ?? 0;

  void setReason(String value) => reason.value = value;

  void setReference(String value) => reference.value = value;

  void setVariant(String? value) => variantId.value = value;

  void setUnitCost(String? value) => unitCostText.value = value;

  Future<bool> submit() async {
    final found = blockingIssues();
    if (found.isNotEmpty) {
      announce(found.first, error: true);
      return false;
    }
    final selectedKind = kind.value!;
    final product = _productById(productId.value)!;
    final cost = unitCostText.value;
    final costPaise = (cost == null || cost.trim().isEmpty)
        ? null
        : AdminFormat.paiseFromRupeeText(cost);

    final ok = selectedKind == StockMovementKind.opening
        ? await mutateVoid(
            () => _admin.setOpeningStock(
              productId: product.id,
              quantity: quantity.value,
              variantId: variantId.value,
              reason: reason.value.trim(),
            ),
          )
        : await mutateVoid(
            () => _admin.adjustStock(
              productId: product.id,
              deltaQty: signedDelta,
              kind: selectedKind,
              reason: reason.value.trim(),
              variantId: variantId.value,
              unitCostPaise: canSeeCost ? costPaise : null,
            ),
          );

    if (!ok) {
      final error = failure.value;
      announce(error?.message ?? 'The movement was refused.', error: true);
      return false;
    }
    announce(
      'Ledger row written: ${stockMovementLabel(selectedKind)} of ${quantity.value}. The new '
      'balance is recomputed by the server from the ledger, not from this form.',
    );
    clearForm();
    if (_list.isReportMode) {
      await _list.loadLowReport();
    } else {
      await _list.loadFirstPage();
    }
    return true;
  }

  void clearForm() {
    kind.value = null;
    quantity.value = 0;
    reason.value = '';
    reference.value = '';
    unitCostText.value = null;
    variantId.value = null;
  }
}

/// The movement ledger.
///
/// Two reads, both server-side: one product's rows through `movementsFor`, which exists today, and
/// a cross-product filtered view that needs the repository method noted below.
final class StockLedgerController extends AdminController {
  StockLedgerController();

  final AdminRepository _admin = Get.find<AdminRepository>();
  final InventoryController _list = Get.find<InventoryController>();

  final RxList<InventoryMovement> movements = <InventoryMovement>[].obs;
  final RxInt limit = 50.obs;
  final Rxn<DateTime> since = Rxn<DateTime>();
  final Rxn<StockMovementKind> kindFilter = Rxn<StockMovementKind>();

  /// The store-wide ledger needs a repository query that does not exist yet.
  ///
  /// NEEDS OWNER(AdminRepository):
  ///
  /// ```dart
  /// Future<PagedResult<InventoryMovement>> movements({
  ///   String? productId, StockMovementKind? kind,
  ///   DateTime? from, DateTime? to, int pageSize, String? cursor})
  /// ```
  ///
  /// `movementsFor` is per-product only; filtering a returned page client-side would hide rows the
  /// operator needs, so until that method lands the cross-product view is honestly unavailable
  /// rather than silently partial.
  final RxBool crossProductUnavailable = false.obs;

  bool get isProductScoped => _list.selectedProductId.value != null;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final product = _list.selectedProductId.value;
    if (product == null) {
      movements.clear();
      crossProductUnavailable.value = true;
      hasLoaded.value = true;
      return;
    }
    crossProductUnavailable.value = false;
    final rows = await guard<List<InventoryMovement>>(
      () => _admin.movementsFor(
        product,
        limit: limit.value,
        since: sinceBound,
      ),
    );
    if (rows != null) movements.assignAll(rows);
  }

  DateTime? get sinceBound {
    final value = since.value;
    if (value == null) return null;
    return DateTime(value.year, value.month, value.day);
  }

  void setLimit(int value) {
    limit.value = value.clamp(10, 200);
    load();
  }

  void setSince(DateTime? value) {
    since.value = value;
    load();
  }

  void setKind(StockMovementKind? value) {
    kindFilter.value = value;
    load();
  }

  void focusProduct(String? productId) {
    _list.select(productId ?? '');
    load();
  }

  String exportCsv() => OmCsv.build(
        headers: const <String>[
          'at',
          'product',
          'kind',
          'quantity',
          'signed',
          'balanceAfter',
          'reason',
          'reference',
          'order',
          'actor',
        ],
        rows: <List<Object?>>[
          for (final movement in movements)
            <Object?>[
              AdminFormat.dateTime(movement.createdAt),
              movement.productId,
              movement.kind.code,
              movement.quantity,
              movement.signedQuantity,
              movement.balanceAfter,
              movement.reason,
              movement.reference,
              movement.orderId,
              movement.actorUid,
            ],
        ],
      );

  /// Sum of the loaded rows is a *display* total over a bounded read. It is never written anywhere
  /// and the ledger's own `balanceAfter` is the authoritative figure for each row.
  String loadedSummary(OmFailure? error) {
    if (error != null) return 'Ledger read failed: ${error.message}';
    return '${movements.length} movement row(s) loaded';
  }
}
