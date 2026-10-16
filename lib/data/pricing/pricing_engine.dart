import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';

/// The single answer to "what does this line cost".
final class PriceResolution {
  const PriceResolution({
    required this.qty,
    required this.unitPricePaise,
    required this.lineTotalPaise,
    required this.baseUnitPricePaise,
    required this.savedPaise,
    this.slab,
    this.nextSlab,
    this.unitsToNextSlab = 0,
  });

  final int qty;

  /// Price applied to **every** unit in the line.
  final int unitPricePaise;
  final int lineTotalPaise;

  /// Single-unit shelf price, so "you save" has a fixed reference.
  final int baseUnitPricePaise;
  final int savedPaise;
  final PriceSlab? slab;

  /// The band the buyer is closest to unlocking, plus how many more units it takes.
  final PriceSlab? nextSlab;
  final int unitsToNextSlab;

  bool get hasSlabDiscount => savedPaise > 0;

  String get slabDescription {
    final current = slab;
    if (current == null) return 'Standard retail price';
    final upper = current.maxQty;
    final range = upper == null
        ? '${current.minQty}+'
        : current.minQty == upper
            ? '${current.minQty}'
            : '${current.minQty}-$upper';
    return current.label ?? 'Quantity $range';
  }

  static const PriceResolution empty =
      PriceResolution(qty: 0, unitPricePaise: 0, lineTotalPaise: 0, baseUnitPricePaise: 0, savedPaise: 0);
}

/// Quantity nudging honouring a product's ordering granularity.
final class OrderGranularity {
  const OrderGranularity({this.minQty = 1, this.multiple = 1});

  final int minQty;
  final int multiple;

  /// Below the minimum, the answer is the minimum — not zero, and not a silent rounding down.
  int clampQty(int requested) {
    if (requested <= 0) return 0;
    if (requested < minQty) return minQty;
    final step = multiple < 1 ? 1 : multiple;
    if (step == 1) return requested;
    final steps = (requested / step).ceil();
    return steps * step;
  }

  bool accepts(int qty) => qty >= minQty && qty % (multiple < 1 ? 1 : multiple) == 0;

  String? violationFor(int qty) {
    if (qty < minQty) return 'Minimum order quantity is $minQty.';
    if (!accepts(qty)) return 'Order in multiples of $multiple.';
    return null;
  }
}

/// THE pricing implementation. Storefront carts, product pages, the admin preview and the
/// checkout summary all call this; nothing else may compute a unit price. The trusted mirror of
/// these rules lives in `functions/lib/pricing.js` and is checked against the same fixtures.
final class PricingEngine {
  const PricingEngine._();

  static PriceResolution priceFor({
    required Product product,
    required int qty,
    ProductVariant? variant,
    int? customerOverrideUnitPricePaise,
  }) {
    if (qty <= 0) return PriceResolution.empty;

    final base = variant != null && variant.retailPricePaise > 0
        ? variant.retailPricePaise
        : product.basePricePaise;

    // A negotiated price for this specific customer wins over public slabs, and is applied
    // unit-for-unit because it is a contract price, not a volume tier.
    final override = customerOverrideUnitPricePaise;
    if (override != null && override > 0) {
      return PriceResolution(
        qty: qty,
        unitPricePaise: override,
        lineTotalPaise: override * qty,
        baseUnitPricePaise: base,
        savedPaise: base > override ? (base - override) * qty : 0,
      );
    }

    final slabs = _effectiveSlabs(product: product, variant: variant);
    if (slabs.isEmpty) {
      return PriceResolution(
        qty: qty,
        unitPricePaise: base,
        lineTotalPaise: base * qty,
        baseUnitPricePaise: base,
        savedPaise: 0,
      );
    }

    final sorted = _sortedSlabs(slabs);
    final matches = sorted.where((s) => s.contains(qty)).toList(growable: false);
    if (matches.length > 1) {
      // Two bands claim this quantity. Guessing would quietly change what a buyer pays.
      throw ValidationFailure(
        'Quantity $qty matches ${matches.length} price slabs for ${product.name}.',
        field: 'slabs',
      );
    }

    final applicable = matches.isEmpty ? null : matches.first;

    // Below the first band the buyer still pays the shelf price — never the nearest band's
    // price, which would hand out a discount nobody qualified for.
    final unitPrice = applicable?.unitPricePaise ?? base;
    final saved = unitPrice < base ? (base - unitPrice) * qty : 0;

    PriceSlab? next;
    var unitsToNext = 0;
    for (final candidate in sorted) {
      if (candidate.minQty > qty && candidate.unitPricePaise < unitPrice) {
        next = candidate;
        unitsToNext = candidate.minQty - qty;
        break;
      }
    }

    return PriceResolution(
      qty: qty,
      unitPricePaise: unitPrice,
      lineTotalPaise: unitPrice * qty,
      baseUnitPricePaise: base,
      savedPaise: saved,
      slab: applicable,
      nextSlab: next,
      unitsToNextSlab: unitsToNext,
    );
  }

  /// Cart lines and product pages need the same ordering; the engine sorts rather than trusting
  /// document array order, which admin forms and CSV imports rewrite constantly.
  static List<PriceSlab> sortedSlabsFor({
    required Product product,
    ProductVariant? variant,
  }) =>
      _sortedSlabs(_effectiveSlabs(product: product, variant: variant));

  static List<PriceSlab> _effectiveSlabs({
    required Product product,
    ProductVariant? variant,
  }) {
    if (variant != null && variant.slabs.isNotEmpty) return variant.slabs;
    return product.slabs;
  }

  static List<PriceSlab> _sortedSlabs(List<PriceSlab> slabs) {
    final copy = [...slabs]..sort((a, b) => a.minQty.compareTo(b.minQty));
    return copy;
  }

  /// Rows sharing a product line aggregate into one slab lookup: 6 packs + 5 packs of the same
  /// product must reach the 10-unit band, not price as two separate retail lines.
  static int mergeQty(Iterable<int> quantities) =>
      quantities.fold(0, (sum, qty) => sum + qty);
}

/// Totals for a set of already-priced lines. The grand total is still only authoritative once
/// `orders.createOrder` recomputes it server-side.
final class CartTotals {
  const CartTotals({
    required this.subtotalPaise,
    required this.slabSavingsPaise,
    required this.couponDiscountPaise,
    required this.shippingPaise,
    required this.taxPaise,
    this.lineCount = 0,
    this.unitCount = 0,
  });

  final int subtotalPaise;
  final int slabSavingsPaise;
  final int couponDiscountPaise;
  final int shippingPaise;
  final int taxPaise;
  final int lineCount;
  final int unitCount;

  int get totalDiscountPaise => slabSavingsPaise + couponDiscountPaise;
  int get grandTotalPaise => subtotalPaise - couponDiscountPaise + shippingPaise + taxPaise;
  int get payableRoundedPaise => ((grandTotalPaise + 99) ~/ 100) * 100;

  static const CartTotals empty = CartTotals(
    subtotalPaise: 0,
    slabSavingsPaise: 0,
    couponDiscountPaise: 0,
    shippingPaise: 0,
    taxPaise: 0,
  );

  factory CartTotals.from(
    List<PriceResolution> lines, {
    int couponDiscountPaise = 0,
    int shippingPaise = 0,
    int taxRateBps = 0,
    bool taxInclusive = false,
  }) {
    var subtotal = 0;
    var savings = 0;
    var units = 0;
    for (final line in lines) {
      subtotal += line.lineTotalPaise;
      savings += line.savedPaise;
      units += line.qty;
    }
    final cappedCoupon = couponDiscountPaise.clamp(0, subtotal);
    final taxable = taxInclusive ? 0 : subtotal - cappedCoupon;
    final tax = taxInclusive ? 0 : (taxable * taxRateBps / 10000).round();
    return CartTotals(
      subtotalPaise: subtotal,
      slabSavingsPaise: savings,
      couponDiscountPaise: cappedCoupon,
      shippingPaise: shippingPaise,
      taxPaise: tax,
      lineCount: lines.length,
      unitCount: units,
    );
  }
}
