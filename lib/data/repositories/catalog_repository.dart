import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/data/models/inventory.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';

abstract interface class ProductRepository {
  Future<Product> byId(String id);

  /// SEO URLs use the slug; the repository resolves slug -> document and throws
  /// [NotFoundFailure] when nothing matches.
  Future<Product> bySlug(String slug);

  Future<Product> bySku(String sku);

  Future<List<Product>> byIds(List<String> ids);

  Future<PagedResult<Product>> search(CatalogQuery query);

  Stream<PagedResult<Product>> watchSearch(CatalogQuery query);

  Future<List<Product>> homeShelf({
    required int featuredLimit,
    required int bestSellerLimit,
    required int newArrivalLimit,
  });

  Future<List<Product>> relatedTo(Product product, {int limit = 8});

  /// Search-as-you-type suggestions: names and SKUs only, capped, no full document reads.
  Future<List<String>> suggestions(String term, {int limit = 8});

  /// Server-side validation used by checkout before the trusted create call, so the buyer sees
  /// "only 12 left" rather than a rejected order.
  Future<int> availableStock(String productId, {String? variantId});
}

abstract interface class CategoryRepository {
  Future<List<Category>> tree();

  Future<Category> byId(String id);

  Future<Category> bySlug(String slug);

  Future<List<Category>> childrenOf(String? parentId);
}

abstract interface class VariantRepository {
  Future<List<ProductVariant>> forProduct(String productId);

  Future<ProductVariant> byId(String variantId);
}

abstract interface class CouponRepository {
  /// Returns the coupon with the discount already computed against the *server's* view of the
  /// cart. A client that trusts its own arithmetic is what makes this call exist.
  Future<CouponQuote> quote({
    required String code,
    required List<QuoteLine> lines,
    String? uid,
  });
}

final class QuoteLine {
  const QuoteLine({
    required this.productId,
    required this.qty,
    required this.lineTotalPaise,
    this.categoryId = '',
    this.variantId,
  });

  final String productId;
  final String? variantId;
  final String categoryId;
  final int qty;
  final int lineTotalPaise;

  Map<String, Object?> toMap() => <String, Object?>{
        'productId': productId,
        'variantId': variantId,
        'categoryId': categoryId,
        'qty': qty,
        'lineTotalPaise': lineTotalPaise,
      };
}

final class CouponQuote {
  const CouponQuote({
    required this.coupon,
    required this.discountPaise,
    required this.freeShipping,
    this.reason = '',
  });

  final Coupon coupon;
  final int discountPaise;
  final bool freeShipping;

  /// Populated when the code is valid but not applicable to this cart.
  final String reason;
}
