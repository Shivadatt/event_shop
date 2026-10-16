import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';

/// Result of running the shared slab-grid validator over a draft grid.
///
/// The validator itself lives in `lib/data/pricing/pricing_engine.dart` and is the same code the
/// cart and the Cloud Function use; this wrapper only turns its thrown `ValidationFailure` into a
/// value a widget can highlight a row from. The admin panel never has a second copy of the rules.
final class SlabGridCheck {
  const SlabGridCheck._({required this.isValid, this.message, this.rowIndex});

  const SlabGridCheck.valid()
      : isValid = true,
        message = null,
        rowIndex = null;

  final bool isValid;
  final String? message;

  /// Index into the list that was checked — the same order the editor displays — or null when the
  /// message does not name a row. Null is honest: it means "the grid is wrong, but not because of
  /// one particular row".
  final int? rowIndex;

  String get displayMessage => message ?? 'The price slab grid is invalid.';
}

final class SlabPreviewRow {
  const SlabPreviewRow({
    required this.qty,
    required this.unitPricePaise,
    required this.lineTotalPaise,
    required this.band,
    this.hasBand = false,
  });

  final int qty;
  final int unitPricePaise;
  final int lineTotalPaise;
  final String band;

  /// False when the quantity sits below the lowest band, where the shelf price applies. The
  /// preview labels that explicitly so an operator does not read it as a broken row.
  final bool hasBand;
}

/// Sorted copy, which is the order both the table and the engine reason about.
List<PriceSlab> sortedSlabs(List<PriceSlab> slabs) =>
    [...slabs]..sort((a, b) => a.minQty.compareTo(b.minQty));

SlabGridCheck checkSlabGrid(List<PriceSlab> slabs) {
  try {
    validateSlabGrid(slabs);
    return const SlabGridCheck.valid();
  } on ValidationFailure catch (error) {
    return SlabGridCheck._(
      isValid: false,
      message: error.message,
      rowIndex: _rowForMessage(slabs, error.message, field: error.field),
    );
  } on OmFailure catch (error) {
    return SlabGridCheck._(isValid: false, message: error.message);
  }
}

/// Maps the validator's message onto the row that caused it.
///
/// `validateSlabGrid` reports by quantity ("Quantity 10 is inside two bands"), which is more
/// useful to a buyer-facing bug report than a row number; turning it back into a row here keeps
/// the operator from hunting through a 12-band grid.
int? _rowForMessage(List<PriceSlab> slabs, String message, {String? field}) {
  if (slabs.isEmpty) return null;
  final qtyMatch = RegExp(r'[Qq]uantity (\d+)').firstMatch(message);
  final qty = qtyMatch == null ? null : int.tryParse(qtyMatch.group(1) ?? '');
  if (qty != null) {
    for (var i = 0; i < slabs.length; i++) {
      final max = slabs[i].maxQty;
      if (slabs[i].minQty == qty || (max != null && max == qty)) return i;
    }
  }
  if (message.contains('open-ended')) {
    for (var i = 0; i < slabs.length; i++) {
      if (slabs[i].isOpenEnded && slabs[i].minQty != _topMinimum(slabs)) return i;
    }
  }
  if (message.contains('below its minimum') || message.contains('higher than')) {
    for (var i = 0; i < slabs.length; i++) {
      final max = slabs[i].maxQty;
      if (max != null && max < slabs[i].minQty) return i;
    }
  }
  if (field == 'unitPricePaise') {
    for (var i = 0; i < slabs.length; i++) {
      if (slabs[i].unitPricePaise <= 0) return i;
    }
  }
  return null;
}

int _topMinimum(List<PriceSlab> slabs) =>
    slabs.fold(0, (best, s) => s.minQty > best ? s.minQty : best);

/// A blank band that continues the grid: its minimum is one past the highest quantity already
/// covered, and it starts at the shelf price so an unfinished row cannot silently discount the
/// product.
PriceSlab nextSlabRow(List<PriceSlab> slabs, {required int basePricePaise}) {
  var top = 0;
  for (final slab in slabs) {
    final covered = slab.maxQty ?? slab.minQty;
    if (covered > top) top = covered;
  }
  return PriceSlab(
    minQty: top == 0 ? 2 : top + 1,
    unitPricePaise: basePricePaise,
  );
}

/// What the grid means at a handful of quantities, produced by the one pricing implementation.
///
/// Requires the draft product (not just the slabs) because band membership, the sale price and a
/// variant override all interact inside `PricingEngine`; re-deriving it here would be a second
/// source of truth and the preview would drift from the cart.
List<SlabPreviewRow> previewSlabGrid({
  required Product product,
  required List<PriceSlab> slabs,
  ProductVariant? variant,
  List<int> quantities = const <int>[1, 9, 10, 21, 50],
}) {
  final draft = product.copyWith(
    slabs: slabs,
    retailPricePaise: variant?.retailPricePaise ?? product.retailPricePaise,
  );
  return quantities.map((qty) {
    try {
      final resolution = PricingEngine.priceFor(product: draft, qty: qty, variant: variant);
      return SlabPreviewRow(
        qty: qty,
        unitPricePaise: resolution.unitPricePaise,
        lineTotalPaise: resolution.lineTotalPaise,
        band: resolution.slab == null ? 'shelf price (below the first band)' : resolution.slabDescription,
        hasBand: resolution.slab != null,
      );
    } on ValidationFailure catch (error) {
      return SlabPreviewRow(
        qty: qty,
        unitPricePaise: 0,
        lineTotalPaise: 0,
        band: error.message,
      );
    }
  }).toList(growable: false);
}

/// A band's label as the table shows it, matching `OmSlabTable`'s wording so the admin panel and
/// the product page describe the same band with the same characters.
String slabRangeLabel(PriceSlab slab) => slab.maxQty == null
    ? '${slab.minQty}+'
    : slab.minQty == slab.maxQty
        ? '${slab.minQty}'
        : '${slab.minQty}-${slab.maxQty}';
