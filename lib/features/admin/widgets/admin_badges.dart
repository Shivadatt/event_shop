import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/user_profile.dart';

/// Status pills for the admin panel.
///
/// Every tone is paired with the state's own word, because a colour-only signal is invisible to a
/// colourblind operator and to a screen reader — the contract forbids colour-only state.

OmBadge productBadge(ProductStatus status) => OmBadge(
      label: switch (status) {
        ProductStatus.active => 'Active',
        ProductStatus.draft => 'Draft',
        ProductStatus.archived => 'Archived',
      },
      tone: switch (status) {
        ProductStatus.active => OmTone.success,
        ProductStatus.draft => OmTone.neutral,
        ProductStatus.archived => OmTone.warning,
      },
      dense: true,
    );

OmBadge stockBadge({required int stockQty, required int lowStockThreshold}) {
  if (stockQty <= 0) {
    return const OmBadge(label: 'Out of stock', tone: OmTone.danger, dense: true);
  }
  if (stockQty <= lowStockThreshold) {
    return const OmBadge(label: 'Low stock', tone: OmTone.warning, dense: true);
  }
  return const OmBadge(label: 'In stock', tone: OmTone.success, dense: true);
}

OmBadge orderBadge(OrderStatus status) => OmBadge(
      label: orderStatusLabel(status),
      tone: switch (status) {
        OrderStatus.placed => OmTone.info,
        OrderStatus.confirmed => OmTone.info,
        OrderStatus.processing => OmTone.gold,
        OrderStatus.packed => OmTone.gold,
        OrderStatus.shipped => OmTone.gold,
        OrderStatus.outForDelivery => OmTone.gold,
        OrderStatus.delivered => OmTone.success,
        OrderStatus.cancelled => OmTone.neutral,
        OrderStatus.returned => OmTone.warning,
        OrderStatus.refunded => OmTone.danger,
      },
      dense: true,
    );

String orderStatusLabel(OrderStatus status) => switch (status) {
      OrderStatus.placed => 'Placed',
      OrderStatus.confirmed => 'Confirmed',
      OrderStatus.processing => 'Processing',
      OrderStatus.packed => 'Packed',
      OrderStatus.shipped => 'Shipped',
      OrderStatus.outForDelivery => 'Out for delivery',
      OrderStatus.delivered => 'Delivered',
      OrderStatus.cancelled => 'Cancelled',
      OrderStatus.returned => 'Returned',
      OrderStatus.refunded => 'Refunded',
    };

OmBadge paymentBadge(PaymentStatus status) => OmBadge(
      label: switch (status) {
        PaymentStatus.notRequired => 'No payment needed',
        PaymentStatus.pending => 'Payment pending',
        PaymentStatus.codPending => 'COD pending',
        PaymentStatus.paid => 'Paid',
        PaymentStatus.failed => 'Payment failed',
        PaymentStatus.refunded => 'Refunded',
        PaymentStatus.partiallyRefunded => 'Partly refunded',
      },
      tone: switch (status) {
        PaymentStatus.paid => OmTone.success,
        PaymentStatus.notRequired => OmTone.neutral,
        PaymentStatus.codPending => OmTone.gold,
        PaymentStatus.failed => OmTone.danger,
        PaymentStatus.refunded => OmTone.danger,
        PaymentStatus.partiallyRefunded => OmTone.warning,
        PaymentStatus.pending => OmTone.info,
      },
      dense: true,
    );

String paymentStatusLabel(PaymentStatus status) => switch (status) {
      PaymentStatus.notRequired => 'Not required',
      PaymentStatus.pending => 'Pending',
      PaymentStatus.codPending => 'COD pending',
      PaymentStatus.paid => 'Paid',
      PaymentStatus.failed => 'Failed',
      PaymentStatus.refunded => 'Refunded',
      PaymentStatus.partiallyRefunded => 'Partly refunded',
    };

OmBadge deliveryBadge(DeliveryMode mode) => OmBadge(
      label: mode == DeliveryMode.pickup ? 'Store pickup' : 'Courier',
      tone: mode == DeliveryMode.pickup ? OmTone.info : OmTone.neutral,
      dense: true,
    );

OmBadge reviewBadge(ReviewStatus status) => OmBadge(
      label: switch (status) {
        ReviewStatus.pending => 'Awaiting moderation',
        ReviewStatus.published => 'Published',
        ReviewStatus.hidden => 'Hidden',
        ReviewStatus.rejected => 'Rejected',
      },
      tone: switch (status) {
        ReviewStatus.pending => OmTone.warning,
        ReviewStatus.published => OmTone.success,
        ReviewStatus.hidden => OmTone.neutral,
        ReviewStatus.rejected => OmTone.danger,
      },
      dense: true,
    );

String reviewStatusLabel(ReviewStatus status) => switch (status) {
      ReviewStatus.pending => 'Pending',
      ReviewStatus.published => 'Published',
      ReviewStatus.hidden => 'Hidden',
      ReviewStatus.rejected => 'Rejected',
    };

OmBadge wholesaleBadge(WholesaleStatus status) => OmBadge(
      label: switch (status) {
        WholesaleStatus.none => 'Not applied',
        WholesaleStatus.pending => 'Pending',
        WholesaleStatus.approved => 'Approved',
        WholesaleStatus.rejected => 'Rejected',
      },
      tone: switch (status) {
        WholesaleStatus.none => OmTone.neutral,
        WholesaleStatus.pending => OmTone.warning,
        WholesaleStatus.approved => OmTone.success,
        WholesaleStatus.rejected => OmTone.danger,
      },
      dense: true,
    );

OmBadge roleBadge(UserRole role) => OmBadge(
      label: switch (role) {
        UserRole.guest => 'Guest',
        UserRole.customer => 'Customer',
        UserRole.wholesale => 'Wholesale',
        UserRole.staff => 'Staff',
        UserRole.admin => 'Admin',
        UserRole.owner => 'Owner',
      },
      tone: switch (role) {
        UserRole.owner => OmTone.gold,
        UserRole.admin => OmTone.info,
        UserRole.staff => OmTone.neutral,
        UserRole.wholesale => OmTone.success,
        UserRole.customer => OmTone.neutral,
        UserRole.guest => OmTone.neutral,
      },
      dense: true,
    );

OmBadge movementBadge(StockMovementKind kind) => OmBadge(
      label: stockMovementLabel(kind),
      tone: kind.sign > 0 ? OmTone.success : OmTone.warning,
      dense: true,
    );

String stockMovementLabel(StockMovementKind kind) => switch (kind) {
      StockMovementKind.opening => 'Opening balance',
      StockMovementKind.purchaseIn => 'Purchase in',
      StockMovementKind.saleOut => 'Sale out',
      StockMovementKind.manualAdjust => 'Manual adjustment',
      StockMovementKind.cancelRestore => 'Cancel restore',
      StockMovementKind.returnIn => 'Return in',
      StockMovementKind.damaged => 'Damaged / write-off',
      StockMovementKind.transferOut => 'Transfer out',
    };

/// Live / scheduled / expired / exhausted, derived from the model's own predicates so the column
/// can never disagree with what the code will actually honour.
OmBadge couponBadge(Coupon coupon) {
  if (!coupon.isActive) {
    return const OmBadge(label: 'Disabled', dense: true);
  }
  if (coupon.isExhausted) {
    return const OmBadge(label: 'Exhausted', tone: OmTone.warning, dense: true);
  }
  if (coupon.startsAt != null && !coupon.isWithinWindow()) {
    return const OmBadge(label: 'Scheduled', tone: OmTone.info, dense: true);
  }
  if (!coupon.isWithinWindow()) {
    return const OmBadge(label: 'Expired', tone: OmTone.danger, dense: true);
  }
  return const OmBadge(label: 'Live', tone: OmTone.success, dense: true);
}

String couponKindLabel(CouponKind kind) => switch (kind) {
      CouponKind.percentage => 'Percent off',
      CouponKind.flatPaise => 'Flat amount',
      CouponKind.freeShipping => 'Free shipping',
    };
