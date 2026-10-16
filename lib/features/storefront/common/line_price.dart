import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/pricing/pricing_engine.dart';

/// Everything a widget needs to show one cart/PDP line without ever touching money math: the
/// engine answers the price, this file only guards against a corrupt slab grid throwing during
/// build and exposes the product's ordering granularity.
final class LinePrice {
  const LinePrice({
    required this.resolution,
    required this.granularity,
    this.error,
  });

  final PriceResolution resolution;
  final OrderGranularity granularity;
  final OmFailure? error;

  bool get hasError => error != null;

  static LinePrice unavailable({OrderGranularity? granularity}) => LinePrice(
        resolution: PriceResolution.empty,
        granularity: granularity ?? const OrderGranularity(),
        error: const ServerFailure('This line could not be priced and will be re-checked at '
            'checkout.'),
      );
}

/// Display-only pricing. The engine is the sole calculator; wrapping a try/catch around it keeps
/// one malformed product from breaking an entire grid render.
LinePrice priceLine({
  required Product product,
  required int qty,
  ProductVariant? variant,
  int? customerOverrideUnitPricePaise,
}) {
  final granularity = OrderGranularity(
    minQty: variant?.minOrderQty ?? product.minOrderQty,
    multiple: product.orderMultiple,
  );
  try {
    return LinePrice(
      resolution: PricingEngine.priceFor(
        product: product,
        qty: qty,
        variant: variant,
        customerOverrideUnitPricePaise: customerOverrideUnitPricePaise,
      ),
      granularity: granularity,
    );
  } on OmFailure catch (failure) {
    return LinePrice(
      resolution: PriceResolution.empty,
      granularity: granularity,
      error: failure,
    );
  }
}
