import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/om_doc.dart';

enum StockMovementKind {
  opening('opening'),
  purchaseIn('purchaseIn'),
  saleOut('saleOut'),
  manualAdjust('manualAdjust'),
  cancelRestore('cancelRestore'),
  returnIn('returnIn'),
  damaged('damaged'),
  transferOut('transferOut');

  const StockMovementKind(this.code);
  final String code;

  /// Signed quantity contribution: inbound movements add, outbound subtract.
  int get sign => switch (this) {
        StockMovementKind.opening ||
        StockMovementKind.purchaseIn ||
        StockMovementKind.cancelRestore ||
        StockMovementKind.returnIn =>
          1,
        _ => -1,
      };
}

StockMovementKind stockKindFromCode(String code) => StockMovementKind.values
    .firstWhere((k) => k.code == code, orElse: () => StockMovementKind.manualAdjust);

/// Append-only ledger row. Stock is never edited in place by the client; an admin "set stock"
/// action writes a `manualAdjust` with a reason so the audit trail explains the delta.
final class InventoryMovement {
  const InventoryMovement({
    required this.id,
    required this.productId,
    required this.kind,
    required this.quantity,
    required this.balanceAfter,
    this.variantId,
    this.orderId = '',
    this.reason = '',
    this.reference = '',
    this.unitCostPaise,
    this.actorUid = '',
    this.createdAt,
  });

  final String id;
  final String productId;
  final String? variantId;
  final StockMovementKind kind;

  /// Always positive here; [InventoryMovement.signedQuantity] carries the direction.
  final int quantity;
  final int balanceAfter;
  final String orderId;
  final String reason;
  final String reference;
  final int? unitCostPaise;
  final String actorUid;
  final DateTime? createdAt;

  int get signedQuantity => quantity * kind.sign;

  bool get isInbound => kind.sign == 1;

  factory InventoryMovement.fromMap(Map<String, dynamic> m, {String? id}) => InventoryMovement(
        id: id ?? readStringOrEmpty(m, 'id'),
        productId: readStringOrEmpty(m, 'productId'),
        variantId: readString(m, 'variantId'),
        kind: stockKindFromCode(readStringOrEmpty(m, 'kind')),
        quantity: readIntOrZero(m, 'quantity'),
        balanceAfter: readIntOrZero(m, 'balanceAfter'),
        orderId: readStringOrEmpty(m, 'orderId'),
        reason: readStringOrEmpty(m, 'reason'),
        reference: readStringOrEmpty(m, 'reference'),
        unitCostPaise: readInt(m, 'unitCostPaise'),
        actorUid: readStringOrEmpty(m, 'actorUid'),
        createdAt: readDate(m, 'createdAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'productId': productId,
        'variantId': variantId,
        'kind': kind.code,
        'quantity': quantity,
        'balanceAfter': balanceAfter,
        'orderId': orderId,
        'reason': reason,
        'reference': reference,
        'unitCostPaise': unitCostPaise,
        'actorUid': actorUid,
      });
}

/// Variant-level price and stock. Optional: products with no variants never create these rows.
final class ProductVariant {
  const ProductVariant({
    required this.id,
    required this.productId,
    required this.name,
    this.sku = '',
    this.optionLabel = '',
    this.optionValue = '',
    this.retailPricePaise = 0,
    this.slabs = const <PriceSlab>[],
    this.stockQty = 0,
    this.costPricePaise,
    this.minOrderQty = 1,
    this.imageUrl = '',
    this.isActive = true,
    this.order = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String productId;
  final String name;
  final String sku;
  final String optionLabel;
  final String optionValue;
  final int retailPricePaise;

  /// Variant slabs reuse the same shape as product slabs; the pricing engine takes whichever
  /// list belongs to the ordered variant.
  final List<PriceSlab> slabs;
  final int stockQty;

  /// Cost price is admin-only; it lives on the variant so public product reads cannot leak it.
  final int? costPricePaise;
  final int minOrderQty;
  final String imageUrl;
  final bool isActive;
  final int order;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isInStock => stockQty > 0;

  factory ProductVariant.fromMap(Map<String, dynamic> m, {String? id}) => ProductVariant(
        id: id ?? readStringOrEmpty(m, 'id'),
        productId: readStringOrEmpty(m, 'productId'),
        name: readStringOrEmpty(m, 'name'),
        sku: readStringOrEmpty(m, 'sku'),
        optionLabel: readStringOrEmpty(m, 'optionLabel'),
        optionValue: readStringOrEmpty(m, 'optionValue'),
        retailPricePaise: readIntOrZero(m, 'retailPricePaise'),
        slabs: readMapList(m, 'slabs').map(PriceSlab.fromMap).toList(growable: false),
        stockQty: readIntOrZero(m, 'stockQty'),
        costPricePaise: readInt(m, 'costPricePaise'),
        minOrderQty: readInt(m, 'minOrderQty') ?? 1,
        imageUrl: readStringOrEmpty(m, 'imageUrl'),
        isActive: readBool(m, 'isActive', fallback: true),
        order: readIntOrZero(m, 'order'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
      );

  Map<String, Object?> toWriteMap({bool includeCost = false}) => compact(<String, Object?>{
        'productId': productId,
        'name': name,
        'sku': sku,
        'optionLabel': optionLabel,
        'optionValue': optionValue,
        'retailPricePaise': retailPricePaise,
        'stockQty': stockQty,
        'costPricePaise': includeCost ? costPricePaise : null,
        'minOrderQty': minOrderQty,
        'imageUrl': imageUrl,
        'isActive': isActive,
        'order': order,
      });
}
