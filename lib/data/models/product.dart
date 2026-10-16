import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/om_doc.dart';

/// One quantity band. Its `unitPricePaise` applies to **every** unit in the line, not only the
/// units inside the band — progressive marginal pricing is deliberately not implemented.
final class PriceSlab {
  const PriceSlab({
    required this.minQty,
    required this.unitPricePaise,
    this.maxQty,
    this.label,
  });

  final int minQty;

  /// Null means "and above".
  final int? maxQty;
  final int unitPricePaise;
  final String? label;

  bool contains(int qty) => qty >= minQty && (maxQty == null || qty <= maxQty!);

  bool get isOpenEnded => maxQty == null;

  factory PriceSlab.fromMap(Map<String, dynamic> m) => PriceSlab(
        minQty: readIntOrZero(m, 'minQty'),
        maxQty: readInt(m, 'maxQty'),
        unitPricePaise: readIntOrZero(m, 'unitPricePaise'),
        label: readString(m, 'label'),
      );

  Map<String, Object?> toMap() => compact(<String, Object?>{
        'minQty': minQty,
        'maxQty': maxQty,
        'unitPricePaise': unitPricePaise,
        'label': label,
      });
}

enum ProductStatus {
  draft('draft'),
  active('active'),
  archived('archived');

  const ProductStatus(this.code);
  final String code;
}

ProductStatus productStatusFromCode(String code) => ProductStatus.values
    .firstWhere((s) => s.code == code, orElse: () => ProductStatus.draft);

final class Product {
  const Product({
    required this.id,
    required this.name,
    this.slug = '',
    this.sku = '',
    this.description = '',
    this.categoryId = '',
    this.categorySlug = '',
    this.brand = '',
    this.packSize = '',
    this.unit = 'pack',
    this.retailPricePaise = 0,
    this.slabs = const <PriceSlab>[],
    this.variants = const <String>[],
    this.images = const <MediaRef>[],
    this.minOrderQty = 1,
    this.orderMultiple = 1,
    this.stockQty = 0,
    this.lowStockThreshold = 5,
    this.salePricePaise,
    this.saleFrom,
    this.saleTo,
    this.status = ProductStatus.draft,
    this.isWholesaleOnly = false,
    this.isFeatured = false,
    this.isBestSeller = false,
    this.isNewArrival = false,
    this.tags = const <String>[],
    this.keywords = const <String>[],
    this.seoTitle = '',
    this.seoDescription = '',
    this.ratingAvg = 0,
    this.ratingCount = 0,
    this.soldCount = 0,
    this.weightGrams,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;

  /// SEO path segment; falls back to the id when a document predates slugs.
  final String slug;
  final String sku;
  final String description;
  final String categoryId;
  final String categorySlug;
  final String brand;

  /// e.g. "50 pcs per pack" — shown on cards so bulk buyers can compare.
  final String packSize;
  final String unit;
  final int retailPricePaise;
  final List<PriceSlab> slabs;
  final List<String> variants;
  final List<MediaRef> images;
  final int minOrderQty;

  /// Bulk buyers order in multiples (a carton of 24 cannot be split into 20).
  final int orderMultiple;

  /// Denormalised mirror of `inventory` truth; the backend recomputes it, the client only reads.
  final int stockQty;
  final int lowStockThreshold;
  final int? salePricePaise;
  final DateTime? saleFrom;
  final DateTime? saleTo;
  final ProductStatus status;
  final bool isWholesaleOnly;
  final bool isFeatured;
  final bool isBestSeller;
  final bool isNewArrival;
  final List<String> tags;
  final List<String> keywords;
  final String seoTitle;
  final String seoDescription;

  /// Written by Cloud Functions when reviews change; listing pages read it without a subquery.
  final double ratingAvg;
  final int ratingCount;
  final int soldCount;
  final int? weightGrams;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get pathSlug => slug.isNotEmpty ? slug : id;

  MediaRef? get primaryImage {
    if (images.isEmpty) return null;
    for (final image in images) {
      if (image.isPrimary) return image;
    }
    return images.first;
  }

  bool get isInStock => stockQty > 0;
  bool get isLowStock => stockQty > 0 && stockQty <= lowStockThreshold;
  bool get isSoldOut => !isInStock;

  bool get hasQuantitySlabs => slabs.length > 1;

  bool get isSaleLive {
    final price = salePricePaise;
    if (price == null || price <= 0) return false;
    final now = DateTime.now();
    final from = saleFrom;
    final to = saleTo;
    if (from != null && now.isBefore(from)) return false;
    if (to != null && now.isAfter(to)) return false;
    return price < retailPricePaise;
  }

  /// The shelf price before slab discounts: active sale price, else retail.
  int get basePricePaise => isSaleLive ? salePricePaise! : retailPricePaise;

  /// Slabs are trusted at read time. An admin form can still save an impossible grid, so the
  /// UI refuses to guess: overlapping bands throw instead of picking one silently.
  factory Product.fromMap(Map<String, dynamic> m, {String? id}) {
    final slabs = readMapList(m, 'slabs').map(PriceSlab.fromMap).toList(growable: false);
    return Product(
      id: id ?? readStringOrEmpty(m, 'id'),
      name: readStringOrEmpty(m, 'name'),
      slug: readStringOrEmpty(m, 'slug'),
      sku: readStringOrEmpty(m, 'sku'),
      description: readStringOrEmpty(m, 'description'),
      categoryId: readStringOrEmpty(m, 'categoryId'),
      categorySlug: readStringOrEmpty(m, 'categorySlug'),
      brand: readStringOrEmpty(m, 'brand'),
      packSize: readStringOrEmpty(m, 'packSize'),
      unit: readStringOrEmpty(m, 'unit').isEmpty ? 'pack' : readStringOrEmpty(m, 'unit'),
      retailPricePaise: readIntOrZero(m, 'retailPricePaise'),
      slabs: slabs,
      variants: readStringList(m, 'variants'),
      images: readMapList(m, 'images').map(MediaRef.fromMap).toList(growable: false),
      minOrderQty: readInt(m, 'minOrderQty') ?? 1,
      orderMultiple: readInt(m, 'orderMultiple') ?? 1,
      stockQty: readIntOrZero(m, 'stockQty'),
      lowStockThreshold: readInt(m, 'lowStockThreshold') ?? 5,
      salePricePaise: readInt(m, 'salePricePaise'),
      saleFrom: readDate(m, 'saleFrom'),
      saleTo: readDate(m, 'saleTo'),
      status: productStatusFromCode(readStringOrEmpty(m, 'status')),
      isWholesaleOnly: readBool(m, 'isWholesaleOnly'),
      isFeatured: readBool(m, 'isFeatured'),
      isBestSeller: readBool(m, 'isBestSeller'),
      isNewArrival: readBool(m, 'isNewArrival'),
      tags: readStringList(m, 'tags'),
      keywords: readStringList(m, 'keywords'),
      seoTitle: readStringOrEmpty(m, 'seoTitle'),
      seoDescription: readStringOrEmpty(m, 'seoDescription'),
      ratingAvg: (m['ratingAvg'] as num?)?.toDouble() ?? 0,
      ratingCount: readIntOrZero(m, 'ratingCount'),
      soldCount: readIntOrZero(m, 'soldCount'),
      weightGrams: readInt(m, 'weightGrams'),
      createdAt: readDate(m, 'createdAt'),
      updatedAt: readDate(m, 'updatedAt'),
    );
  }

  /// Writable subset. Rating/sold counters and `stockQty` are owned by Cloud Functions, so a
  /// product save from the admin panel must not clobber them.
  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'name': name,
        'slug': slug,
        'sku': sku,
        'description': description,
        'categoryId': categoryId,
        'categorySlug': categorySlug,
        'brand': brand,
        'packSize': packSize,
        'unit': unit,
        'retailPricePaise': retailPricePaise,
        'slabs': slabs.map((s) => s.toMap()).toList(),
        'variants': variants,
        'images': images.map((i) => i.toMap()).toList(),
        'minOrderQty': minOrderQty,
        'orderMultiple': orderMultiple,
        'lowStockThreshold': lowStockThreshold,
        'salePricePaise': salePricePaise,
        'saleFrom': saleFrom,
        'saleTo': saleTo,
        'status': status.code,
        'isWholesaleOnly': isWholesaleOnly,
        'isFeatured': isFeatured,
        'isBestSeller': isBestSeller,
        'isNewArrival': isNewArrival,
        'tags': tags,
        'keywords': keywords,
        'seoTitle': seoTitle,
        'seoDescription': seoDescription,
        'weightGrams': weightGrams,
      });

  Product copyWith({
    String? name,
    String? slug,
    String? sku,
    String? description,
    String? categoryId,
    int? retailPricePaise,
    List<PriceSlab>? slabs,
    List<MediaRef>? images,
    int? minOrderQty,
    int? orderMultiple,
    int? stockQty,
    int? lowStockThreshold,
    int? salePricePaise,
    ProductStatus? status,
    bool? isFeatured,
    bool? isBestSeller,
    bool? isNewArrival,
    bool? isWholesaleOnly,
    List<String>? tags,
    List<String>? keywords,
    String? seoTitle,
    String? seoDescription,
    double? ratingAvg,
    int? ratingCount,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      Product(
        id: id,
        name: name ?? this.name,
        slug: slug ?? this.slug,
        sku: sku ?? this.sku,
        description: description ?? this.description,
        categoryId: categoryId ?? this.categoryId,
        categorySlug: categorySlug,
        brand: brand,
        packSize: packSize,
        unit: unit,
        retailPricePaise: retailPricePaise ?? this.retailPricePaise,
        slabs: slabs ?? this.slabs,
        variants: variants,
        images: images ?? this.images,
        minOrderQty: minOrderQty ?? this.minOrderQty,
        orderMultiple: orderMultiple ?? this.orderMultiple,
        stockQty: stockQty ?? this.stockQty,
        lowStockThreshold: lowStockThreshold ?? this.lowStockThreshold,
        salePricePaise: salePricePaise ?? this.salePricePaise,
        saleFrom: saleFrom,
        saleTo: saleTo,
        status: status ?? this.status,
        isWholesaleOnly: isWholesaleOnly ?? this.isWholesaleOnly,
        isFeatured: isFeatured ?? this.isFeatured,
        isBestSeller: isBestSeller ?? this.isBestSeller,
        isNewArrival: isNewArrival ?? this.isNewArrival,
        tags: tags ?? this.tags,
        keywords: keywords ?? this.keywords,
        seoTitle: seoTitle ?? this.seoTitle,
        seoDescription: seoDescription ?? this.seoDescription,
        ratingAvg: ratingAvg ?? this.ratingAvg,
        ratingCount: ratingCount ?? this.ratingCount,
        soldCount: soldCount,
        weightGrams: weightGrams,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}

/// Server-side guard reused by the admin form so an ambiguous grid is rejected before it is
/// ever written.
void validateSlabGrid(List<PriceSlab> slabs) {
  if (slabs.isEmpty) return;
  final sorted = [...slabs]..sort((a, b) => a.minQty.compareTo(b.minQty));
  PriceSlab? previous;
  for (final slab in sorted) {
    if (slab.minQty < 1) {
      throw const ValidationFailure(
        'Slab minimum quantity must be at least 1.',
        field: 'slabs',
      );
    }
    if (slab.unitPricePaise <= 0) {
      throw const ValidationFailure('Slab price must be above zero.', field: 'slabs');
    }
    if (slab.maxQty != null && slab.maxQty! < slab.minQty) {
      throw const ValidationFailure(
        'Slab maximum cannot be below its minimum.',
        field: 'slabs',
      );
    }
    if (previous != null) {
      final previousCeiling = previous.maxQty;
      if (previousCeiling != null && slab.minQty <= previousCeiling) {
        throw ValidationFailure(
          'Quantity ${slab.minQty} matches two price slabs.',
          field: 'slabs',
        );
      }
      if (previous.isOpenEnded) {
        throw const ValidationFailure(
          'Only the last price slab may be open-ended.',
          field: 'slabs',
        );
      }
    }
    previous = slab;
  }
}
