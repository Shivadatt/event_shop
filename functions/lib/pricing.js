'use strict';

// Trusted mirror of lib/data/pricing/pricing_engine.dart. The Dart engine is the specification;
// this file is kept byte-for-byte semantically identical and is validated against the same
// test/data/slab_fixtures.json (see functions/scripts/check_pricing_fixtures.js). If the two
// diverge, every cart total in the store is suspect.

function contains(slab, qty) {
  return qty >= slab.minQty && (slab.maxQty == null || qty <= slab.maxQty);
}

// saleFrom / saleTo arrive as Firestore Timestamps, Dates, epoch millis, or null. Accept every
// shape so a snapshot written by another path cannot crash a price computation.
function toMillis(value) {
  if (value == null) return null;
  if (typeof value === 'number') return value;
  if (value instanceof Date) return value.getTime();
  if (typeof value.toMillis === 'function') return value.toMillis();
  if (typeof value._seconds === 'number') return value._seconds * 1000;
  return null;
}

// Mirrors Product.isSaleLive + Product.basePricePaise: the shelf price a line discounts from.
// Date-less sales are deterministic so the shared fixture carries no wall-clock dependency.
function basePricePaise(product) {
  const price = product.salePricePaise;
  const retail = product.retailPricePaise || 0;
  if (price != null && price > 0 && price < retail) {
    const now = Date.now();
    const from = toMillis(product.saleFrom);
    const to = toMillis(product.saleTo);
    if ((from == null || now >= from) && (to == null || now <= to)) {
      return price;
    }
  }
  return retail;
}

function effectiveSlabs(product, variant) {
  if (variant && Array.isArray(variant.slabs) && variant.slabs.length > 0) {
    return variant.slabs;
  }
  return Array.isArray(product.slabs) ? product.slabs : [];
}

function sortedSlabs(slabs) {
  return [...slabs].sort((a, b) => a.minQty - b.minQty);
}

class AmbiguousSlabError extends Error {
  constructor(message) {
    super(message);
    this.name = 'AmbiguousSlabError';
    this.field = 'slabs';
    this.code = 'validation';
  }
}

function emptyResolution(qty) {
  return {
    qty,
    unitPricePaise: 0,
    lineTotalPaise: 0,
    baseUnitPricePaise: 0,
    savedPaise: 0,
    slab: null,
    nextSlab: null,
    unitsToNextSlab: 0,
    hasSlabDiscount: false,
  };
}

function priceFor({ product, qty, variant = null, customerOverrideUnitPricePaise = null }) {
  if (qty <= 0) return emptyResolution(qty);

  const base =
    variant != null && (variant.retailPricePaise || 0) > 0
      ? variant.retailPricePaise
      : basePricePaise(product);

  // A negotiated contract price wins over public slabs and is applied unit-for-unit.
  if (customerOverrideUnitPricePaise != null && customerOverrideUnitPricePaise > 0) {
    const override = customerOverrideUnitPricePaise;
    return {
      qty,
      unitPricePaise: override,
      lineTotalPaise: override * qty,
      baseUnitPricePaise: base,
      savedPaise: base > override ? (base - override) * qty : 0,
      slab: null,
      nextSlab: null,
      unitsToNextSlab: 0,
      hasSlabDiscount: base > override,
    };
  }

  const slabs = effectiveSlabs(product, variant);
  if (slabs.length === 0) {
    return {
      qty,
      unitPricePaise: base,
      lineTotalPaise: base * qty,
      baseUnitPricePaise: base,
      savedPaise: 0,
      slab: null,
      nextSlab: null,
      unitsToNextSlab: 0,
      hasSlabDiscount: false,
    };
  }

  const sorted = sortedSlabs(slabs);
  const matches = sorted.filter((s) => contains(s, qty));
  if (matches.length > 1) {
    // Two bands claim this quantity. Guessing would quietly change what a buyer pays.
    throw new AmbiguousSlabError(
      `Quantity ${qty} matches ${matches.length} price slabs for ${product.name}.`,
    );
  }

  const applicable = matches.length === 0 ? null : matches[0];

  // Below the first band the buyer still pays the shelf price, never a discount nobody earned.
  const unitPrice = applicable ? applicable.unitPricePaise : base;
  const saved = unitPrice < base ? (base - unitPrice) * qty : 0;

  let next = null;
  let unitsToNext = 0;
  for (const candidate of sorted) {
    if (candidate.minQty > qty && candidate.unitPricePaise < unitPrice) {
      next = candidate;
      unitsToNext = candidate.minQty - qty;
      break;
    }
  }

  return {
    qty,
    unitPricePaise: unitPrice,
    lineTotalPaise: unitPrice * qty,
    baseUnitPricePaise: base,
    savedPaise: saved,
    slab: applicable,
    nextSlab: next,
    unitsToNextSlab: unitsToNext,
    hasSlabDiscount: saved > 0,
  };
}

// Mirrors PricingEngine.mergeQty: same product+variant lines aggregate before slab lookup.
function mergeQty(quantities) {
  return quantities.reduce((sum, qty) => sum + qty, 0);
}

function keyFor(productId, variantId) {
  return `${productId}::${variantId ?? ''}`;
}

// Mirrors CartTotals.from. Tax is BASIS POINTS (18% = 1800); money is integer paise throughout.
// Dart `.round()` is half-away-from-zero; for these non-negative figures `Math.round` agrees.
function cartTotals(lines, { couponDiscountPaise = 0, shippingPaise = 0, taxRateBps = 0, taxInclusive = false } = {}) {
  let subtotal = 0;
  let savings = 0;
  let units = 0;
  for (const line of lines) {
    subtotal += line.lineTotalPaise;
    savings += line.savedPaise;
    units += line.qty;
  }
  const cappedCoupon = Math.min(Math.max(couponDiscountPaise, 0), subtotal);
  const taxable = taxInclusive ? 0 : subtotal - cappedCoupon;
  const tax = taxInclusive ? 0 : Math.round((taxable * taxRateBps) / 10000);
  const grandTotal = subtotal - cappedCoupon + shippingPaise + tax;
  return {
    subtotalPaise: subtotal,
    slabSavingsPaise: savings,
    couponDiscountPaise: cappedCoupon,
    shippingPaise,
    taxPaise: tax,
    grandTotalPaise: grandTotal,
    lineCount: lines.length,
    unitCount: units,
    payableRoundedPaise: Math.floor((grandTotal + 99) / 100) * 100,
  };
}

// Mirrors the Dart validateSlabGrid guard: reject min<1, non-positive price, inverted range,
// overlap, and an open-ended band that is not the last.
function validateSlabGrid(slabs) {
  if (!slabs || slabs.length === 0) return;
  const sorted = sortedSlabs(slabs);
  let previous = null;
  for (const slab of sorted) {
    if (slab.minQty < 1) {
      throw new AmbiguousSlabError('Slab minimum quantity must be at least 1.');
    }
    if (slab.unitPricePaise <= 0) {
      throw new AmbiguousSlabError('Slab price must be above zero.');
    }
    if (slab.maxQty != null && slab.maxQty < slab.minQty) {
      throw new AmbiguousSlabError('Slab maximum cannot be below its minimum.');
    }
    if (previous != null) {
      const previousCeiling = previous.maxQty;
      if (previousCeiling != null && slab.minQty <= previousCeiling) {
        throw new AmbiguousSlabError(`Quantity ${slab.minQty} matches two price slabs.`);
      }
      if (previous.maxQty == null) {
        throw new AmbiguousSlabError('Only the last price slab may be open-ended.');
      }
    }
    previous = slab;
  }
}

module.exports = {
  priceFor,
  cartTotals,
  mergeQty,
  keyFor,
  validateSlabGrid,
  basePricePaise,
  contains,
  AmbiguousSlabError,
};
