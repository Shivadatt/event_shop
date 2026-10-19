import 'package:om_events/data/om_doc.dart';

enum OrderStatus {
  placed('placed'),
  confirmed('confirmed'),
  processing('processing'),
  packed('packed'),
  shipped('shipped'),
  outForDelivery('outForDelivery'),
  delivered('delivered'),
  cancelled('cancelled'),
  returned('returned'),
  refunded('refunded');

  const OrderStatus(this.code);
  final String code;

  bool get isTerminal => this == delivered || this == cancelled || this == refunded;
  bool get isCancellable =>
      this == placed || this == confirmed || this == processing;

  /// Forward-only workflow. Admin UI offers only these moves so a dispatched parcel cannot be
  /// silently dragged back to "placed".
  List<OrderStatus> get nextSteps {
    switch (this) {
      case OrderStatus.placed:
        return const <OrderStatus>[OrderStatus.confirmed, OrderStatus.cancelled];
      case OrderStatus.confirmed:
        return const <OrderStatus>[OrderStatus.processing, OrderStatus.cancelled];
      case OrderStatus.processing:
        return const <OrderStatus>[OrderStatus.packed, OrderStatus.cancelled];
      case OrderStatus.packed:
        return const <OrderStatus>[OrderStatus.shipped];
      case OrderStatus.shipped:
        return const <OrderStatus>[OrderStatus.outForDelivery];
      case OrderStatus.outForDelivery:
        return const <OrderStatus>[OrderStatus.delivered];
      case OrderStatus.delivered:
        return const <OrderStatus>[OrderStatus.returned];
      case OrderStatus.returned:
        return const <OrderStatus>[OrderStatus.refunded];
      case OrderStatus.cancelled:
      case OrderStatus.refunded:
        return const <OrderStatus>[];
    }
  }
}

OrderStatus orderStatusFromCode(String code) => OrderStatus.values
    .firstWhere((s) => s.code == code, orElse: () => OrderStatus.placed);

enum PaymentStatus {
  notRequired('notRequired'),
  pending('pending'),
  codPending('codPending'),
  paid('paid'),
  failed('failed'),
  refunded('refunded'),
  partiallyRefunded('partiallyRefunded');

  const PaymentStatus(this.code);
  final String code;

  bool get isSettled => this == paid || this == codPending || this == notRequired;
}

PaymentStatus paymentStatusFromCode(String code) => PaymentStatus.values
    .firstWhere((s) => s.code == code, orElse: () => PaymentStatus.pending);

enum DeliveryMode {
  courier('courier'),
  pickup('pickup');

  const DeliveryMode(this.code);
  final String code;
}

DeliveryMode deliveryModeFromCode(String code) => DeliveryMode.values
    .firstWhere((m) => m.code == code, orElse: () => DeliveryMode.courier);

/// Immutable copy of what the buyer actually bought, at the price they actually paid. Later
/// edits to the product must never rewrite history — that is the whole point of this class.
final class OrderItem {
  const OrderItem({
    required this.productId,
    required this.name,
    required this.qty,
    required this.unitPricePaise,
    required this.lineTotalPaise,
    this.variantId,
    this.sku = '',
    this.unit = 'pack',
    this.slug = '',
    this.imageUrl = '',
    this.slabLabel,
    this.slabMinQty,
    this.slabMaxQty,
    this.basePricePaise,
    this.discountPaise = 0,
    this.isStockDeducted = false,
  });

  final String productId;
  final String name;
  final int qty;

  /// Per-unit price that was applied to every unit in this line (slab price, not marginal).
  final int unitPricePaise;
  final int lineTotalPaise;
  final String? variantId;
  final String sku;
  final String unit;
  final String slug;
  final String imageUrl;
  final String? slabLabel;
  final int? slabMinQty;
  final int? slabMaxQty;

  /// The price the line would have cost at quantity 1 — used for "you saved" display.
  final int? basePricePaise;
  final int discountPaise;
  final bool isStockDeducted;

  int get savedPaise => (basePricePaise ?? unitPricePaise) * qty - lineTotalPaise;

  factory OrderItem.fromMap(Map<String, dynamic> m) => OrderItem(
        productId: readStringOrEmpty(m, 'productId'),
        name: readStringOrEmpty(m, 'name'),
        qty: readIntOrZero(m, 'qty'),
        unitPricePaise: readIntOrZero(m, 'unitPricePaise'),
        lineTotalPaise: readIntOrZero(m, 'lineTotalPaise'),
        variantId: readString(m, 'variantId'),
        sku: readStringOrEmpty(m, 'sku'),
        unit: readStringOrEmpty(m, 'unit').isEmpty ? 'pack' : readStringOrEmpty(m, 'unit'),
        slug: readStringOrEmpty(m, 'slug'),
        imageUrl: readStringOrEmpty(m, 'imageUrl'),
        slabLabel: readString(m, 'slabLabel'),
        slabMinQty: readInt(m, 'slabMinQty'),
        slabMaxQty: readInt(m, 'slabMaxQty'),
        basePricePaise: readInt(m, 'basePricePaise'),
        discountPaise: readIntOrZero(m, 'discountPaise'),
        isStockDeducted: readBool(m, 'isStockDeducted'),
      );

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'productId': productId,
        'name': name,
        'qty': qty,
        'unitPricePaise': unitPricePaise,
        'lineTotalPaise': lineTotalPaise,
        'variantId': variantId,
        'sku': sku,
        'unit': unit,
        'slug': slug,
        'imageUrl': imageUrl,
        'slabLabel': slabLabel,
        'slabMinQty': slabMinQty,
        'slabMaxQty': slabMaxQty,
        'basePricePaise': basePricePaise,
        'discountPaise': discountPaise,
        'isStockDeducted': isStockDeducted,
      });

  /// Reorder path: keeps identity and quantity, drops every snapshot field so current pricing
  /// and stock apply.
  Map<String, Object?> asReorderLine() => <String, Object?>{
        'productId': productId,
        'variantId': variantId,
        'qty': qty,
      };
}

final class OrderTotals {
  const OrderTotals({
    this.subtotalPaise = 0,
    this.slabDiscountPaise = 0,
    this.couponDiscountPaise = 0,
    this.shippingPaise = 0,
    this.taxPaise = 0,
    this.roundingPaise = 0,
    this.grandTotalPaise = 0,
    this.paidPaise = 0,
    this.refundedPaise = 0,
  });

  final int subtotalPaise;

  /// Volume savings are reported separately from promo codes so reports can attribute them.
  final int slabDiscountPaise;
  final int couponDiscountPaise;
  final int shippingPaise;
  final int taxPaise;
  final int roundingPaise;
  final int grandTotalPaise;
  final int paidPaise;
  final int refundedPaise;

  int get totalDiscountPaise => slabDiscountPaise + couponDiscountPaise;

  factory OrderTotals.fromMap(Map<String, dynamic> m) => OrderTotals(
        subtotalPaise: readIntOrZero(m, 'subtotalPaise'),
        slabDiscountPaise: readIntOrZero(m, 'slabDiscountPaise'),
        couponDiscountPaise: readIntOrZero(m, 'couponDiscountPaise'),
        shippingPaise: readIntOrZero(m, 'shippingPaise'),
        taxPaise: readIntOrZero(m, 'taxPaise'),
        roundingPaise: readIntOrZero(m, 'roundingPaise'),
        grandTotalPaise: readIntOrZero(m, 'grandTotalPaise'),
        paidPaise: readIntOrZero(m, 'paidPaise'),
        refundedPaise: readIntOrZero(m, 'refundedPaise'),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'subtotalPaise': subtotalPaise,
        'slabDiscountPaise': slabDiscountPaise,
        'couponDiscountPaise': couponDiscountPaise,
        'shippingPaise': shippingPaise,
        'taxPaise': taxPaise,
        'roundingPaise': roundingPaise,
        'grandTotalPaise': grandTotalPaise,
        'paidPaise': paidPaise,
        'refundedPaise': refundedPaise,
      };
}

/// Address frozen into the order. Customers editing their saved address afterwards must not
/// change where an already-placed parcel goes.
final class ShippingSnapshot {
  const ShippingSnapshot({
    this.name = '',
    this.phone = '',
    this.line1 = '',
    this.line2 = '',
    this.city = '',
    this.state = '',
    this.pincode = '',
    this.gstNumber = '',
    this.addressId,
  });

  final String name;
  final String phone;
  final String line1;
  final String line2;
  final String city;
  final String state;
  final String pincode;
  final String gstNumber;
  final String? addressId;

  String get singleLine => <String>[
        name,
        line1,
        line2,
        '$city, $state $pincode',
      ].where((s) => s.trim().isNotEmpty).join(' · ');

  factory ShippingSnapshot.fromMap(Map<String, dynamic> m) => ShippingSnapshot(
        name: readStringOrEmpty(m, 'name'),
        phone: readStringOrEmpty(m, 'phone'),
        line1: readStringOrEmpty(m, 'line1'),
        line2: readStringOrEmpty(m, 'line2'),
        city: readStringOrEmpty(m, 'city'),
        state: readStringOrEmpty(m, 'state'),
        pincode: readStringOrEmpty(m, 'pincode'),
        gstNumber: readStringOrEmpty(m, 'gstNumber'),
        addressId: readString(m, 'addressId'),
      );

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'name': name,
        'phone': phone,
        'line1': line1,
        'line2': line2,
        'city': city,
        'state': state,
        'pincode': pincode,
        'gstNumber': gstNumber,
        'addressId': addressId,
      });
}

final class OrderEvent {
  const OrderEvent({
    required this.at,
    required this.status,
    this.note = '',
    this.actorRole = '',
    this.actorUid = '',
  });

  final DateTime at;
  final OrderStatus status;
  final String note;
  final String actorRole;
  final String actorUid;

  factory OrderEvent.fromMap(Map<String, dynamic> m) => OrderEvent(
        at: readDate(m, 'at') ?? DateTime.now(),
        status: orderStatusFromCode(readStringOrEmpty(m, 'status')),
        note: readStringOrEmpty(m, 'note'),
        actorRole: readStringOrEmpty(m, 'actorRole'),
        actorUid: readStringOrEmpty(m, 'actorUid'),
      );

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'at': at,
        'status': status.code,
        'note': note,
        'actorRole': actorRole,
        'actorUid': actorUid,
      });
}

final class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.items,
    required this.totals,
    this.userId = '',
    this.isGuest = false,
    this.contactEmail = '',
    this.contactPhone = '',
    this.status = OrderStatus.placed,
    this.paymentStatus = PaymentStatus.pending,
    this.paymentMethod = '',
    this.transactionReference = '',
    this.couponCode = '',
    this.deliveryMode = DeliveryMode.courier,
    this.shipping,
    this.internalNote = '',
    this.customerNote = '',
    this.trackingUrl = '',
    this.carrier = '',
    this.cancelledReason = '',
    this.idempotencyKey = '',
    this.invoiceNumber = '',
    this.source = 'web',
    this.createdAt,
    this.updatedAt,
  });

  final String id;

  /// Human-facing number (OME-2026-000123). Generated by Cloud Functions, never by the browser.
  final String orderNumber;
  final String userId;
  final bool isGuest;
  final String contactEmail;
  final String contactPhone;
  final OrderStatus status;
  final PaymentStatus paymentStatus;
  final String paymentMethod;
  final String transactionReference;
  final String couponCode;
  final DeliveryMode deliveryMode;
  final ShippingSnapshot? shipping;
  final String internalNote;
  final String customerNote;
  final String trackingUrl;
  final String carrier;
  final String cancelledReason;

  /// Retried submits reuse this key; the function returns the already-created order instead of
  /// a second charge.
  final String idempotencyKey;
  final String invoiceNumber;

  /// web | counter | whatsapp — shop-counter and WhatsApp orders share this pipeline.
  final String source;
  final List<OrderItem> items;
  final OrderTotals totals;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  int get totalQty => items.fold(0, (sum, item) => sum + item.qty);
  bool get canCancel => status.isCancellable;
  bool get canReorder =>
      status == OrderStatus.delivered || status == OrderStatus.cancelled;
  bool get isPaid => paymentStatus == PaymentStatus.paid;

  factory Order.fromMap(Map<String, dynamic> m, {String? id}) {
    final shippingMap = readMap(m, 'shipping');
    // Totals live in a nested `totals` map — that is what `toWriteMap()` and the Cloud Function
    // both write. The top-level fallback only exists for rows written before that shape settled.
    final totalsMap = readMap(m, 'totals');
    final totalsSource = totalsMap.isEmpty ? m : totalsMap;
    return Order(
      id: id ?? readStringOrEmpty(m, 'id'),
      orderNumber: readStringOrEmpty(m, 'orderNumber'),
      userId: readStringOrEmpty(m, 'userId'),
      isGuest: readBool(m, 'isGuest'),
      contactEmail: readStringOrEmpty(m, 'contactEmail'),
      contactPhone: readStringOrEmpty(m, 'contactPhone'),
      status: orderStatusFromCode(readStringOrEmpty(m, 'status')),
      paymentStatus: paymentStatusFromCode(readStringOrEmpty(m, 'paymentStatus')),
      paymentMethod: readStringOrEmpty(m, 'paymentMethod'),
      transactionReference: readStringOrEmpty(m, 'transactionReference'),
      couponCode: readStringOrEmpty(m, 'couponCode'),
      deliveryMode: deliveryModeFromCode(readStringOrEmpty(m, 'deliveryMode')),
      shipping: shippingMap.isEmpty ? null : ShippingSnapshot.fromMap(shippingMap),
      internalNote: readStringOrEmpty(m, 'internalNote'),
      customerNote: readStringOrEmpty(m, 'customerNote'),
      trackingUrl: readStringOrEmpty(m, 'trackingUrl'),
      carrier: readStringOrEmpty(m, 'carrier'),
      cancelledReason: readStringOrEmpty(m, 'cancelledReason'),
      idempotencyKey: readStringOrEmpty(m, 'idempotencyKey'),
      invoiceNumber: readStringOrEmpty(m, 'invoiceNumber'),
      source: readStringOrEmpty(m, 'source').isEmpty ? 'web' : readStringOrEmpty(m, 'source'),
      items: readMapList(m, 'items').map(OrderItem.fromMap).toList(growable: false),
      totals: OrderTotals.fromMap(totalsSource),
      createdAt: readDate(m, 'createdAt'),
      updatedAt: readDate(m, 'updatedAt'),
    );
  }

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'orderNumber': orderNumber,
        'userId': userId,
        'isGuest': isGuest,
        'contactEmail': contactEmail,
        'contactPhone': contactPhone,
        'status': status.code,
        'paymentStatus': paymentStatus.code,
        'paymentMethod': paymentMethod,
        'couponCode': couponCode,
        'deliveryMode': deliveryMode.code,
        'shipping': shipping?.toMap(),
        'customerNote': customerNote,
        'idempotencyKey': idempotencyKey,
        'source': source,
        'items': items.map((i) => i.toMap()).toList(),
        'totals': totals.toMap(),
      });

  Order copyWith({
    OrderStatus? status,
    PaymentStatus? paymentStatus,
    String? paymentMethod,
    String? transactionReference,
    String? internalNote,
    String? trackingUrl,
    String? carrier,
    String? cancelledReason,
    String? invoiceNumber,
    OrderTotals? totals,
    DateTime? updatedAt,
  }) =>
      Order(
        id: id,
        orderNumber: orderNumber,
        userId: userId,
        isGuest: isGuest,
        contactEmail: contactEmail,
        contactPhone: contactPhone,
        status: status ?? this.status,
        paymentStatus: paymentStatus ?? this.paymentStatus,
        paymentMethod: paymentMethod ?? this.paymentMethod,
        transactionReference: transactionReference ?? this.transactionReference,
        couponCode: couponCode,
        deliveryMode: deliveryMode,
        shipping: shipping,
        internalNote: internalNote ?? this.internalNote,
        customerNote: customerNote,
        trackingUrl: trackingUrl ?? this.trackingUrl,
        carrier: carrier ?? this.carrier,
        cancelledReason: cancelledReason ?? this.cancelledReason,
        idempotencyKey: idempotencyKey,
        invoiceNumber: invoiceNumber ?? this.invoiceNumber,
        source: source,
        items: items,
        totals: totals ?? this.totals,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
