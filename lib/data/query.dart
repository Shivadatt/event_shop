import 'package:om_events/data/models/product.dart';

enum SortMode {
  relevance('relevance', 'Popular'),
  newest('newest', 'Newest'),
  priceLowHigh('priceLowHigh', 'Price: low to high'),
  priceHighLow('priceHighLow', 'Price: high to low'),
  bestSelling('bestSelling', 'Best selling'),
  rating('rating', 'Top rated');

  const SortMode(this.code, this.label);
  final String code;
  final String label;
}

SortMode sortModeFromCode(String code) =>
    SortMode.values.firstWhere((m) => m.code == code, orElse: () => SortMode.relevance);

/// Immutable catalogue query. Repositories translate it into Firestore constraints; widgets
/// never build `Query` objects themselves.
final class CatalogQuery {
  const CatalogQuery({
    this.search = '',
    this.categoryId,
    this.categorySlug,
    this.includeSubCategories = true,
    this.tags = const <String>[],
    this.colors = const <String>[],
    this.sizes = const <String>[],
    this.minPricePaise,
    this.maxPricePaise,
    this.inStockOnly = false,
    this.wholesaleOnly,
    this.featuredOnly = false,
    this.status = ProductStatus.active,
    this.sort = SortMode.relevance,
    this.pageSize = 24,
    this.cursor,
  });

  final String search;
  final String? categoryId;
  final String? categorySlug;

  /// Category pages show their children's products too; the flag exists because the admin
  /// product picker must not.
  final bool includeSubCategories;
  final List<String> tags;
  final List<String> colors;
  final List<String> sizes;
  final int? minPricePaise;
  final int? maxPricePaise;
  final bool inStockOnly;
  final bool? wholesaleOnly;
  final bool featuredOnly;
  final ProductStatus status;
  final SortMode sort;
  final int pageSize;

  /// Opaque page token; the repository owns how it is produced.
  final String? cursor;

  bool get hasFilters =>
      search.isNotEmpty ||
      categoryId != null ||
      categorySlug != null ||
      tags.isNotEmpty ||
      colors.isNotEmpty ||
      sizes.isNotEmpty ||
      minPricePaise != null ||
      maxPricePaise != null ||
      inStockOnly ||
      wholesaleOnly != null ||
      featuredOnly;

  int get filterCount => [
        search.isNotEmpty,
        categoryId != null || categorySlug != null,
        tags.isNotEmpty,
        colors.isNotEmpty,
        sizes.isNotEmpty,
        minPricePaise != null || maxPricePaise != null,
        inStockOnly,
        wholesaleOnly != null,
        featuredOnly,
      ].where((on) => on).length;

  CatalogQuery copyWith({
    String? search,
    String? categoryId,
    String? categorySlug,
    List<String>? tags,
    List<String>? colors,
    List<String>? sizes,
    int? minPricePaise,
    int? maxPricePaise,
    bool? inStockOnly,
    bool? wholesaleOnly,
    bool? featuredOnly,
    SortMode? sort,
    String? cursor,
    int? pageSize,
  }) =>
      CatalogQuery(
        search: search ?? this.search,
        categoryId: categoryId ?? this.categoryId,
        categorySlug: categorySlug ?? this.categorySlug,
        includeSubCategories: includeSubCategories,
        tags: tags ?? this.tags,
        colors: colors ?? this.colors,
        sizes: sizes ?? this.sizes,
        minPricePaise: minPricePaise ?? this.minPricePaise,
        maxPricePaise: maxPricePaise ?? this.maxPricePaise,
        inStockOnly: inStockOnly ?? this.inStockOnly,
        wholesaleOnly: wholesaleOnly ?? this.wholesaleOnly,
        featuredOnly: featuredOnly ?? this.featuredOnly,
        status: status,
        sort: sort ?? this.sort,
        pageSize: pageSize ?? this.pageSize,
        cursor: cursor ?? this.cursor,
      );

  CatalogQuery cleared() => CatalogQuery(sort: sort, pageSize: pageSize);

  /// A stable key so controllers can cache and skip refetches while filters are being typed.
  String get cacheKey => <Object>[
        search,
        categoryId ?? '',
        categorySlug ?? '',
        tags.join(','),
        colors.join(','),
        sizes.join(','),
        minPricePaise ?? -1,
        maxPricePaise ?? -1,
        inStockOnly,
        wholesaleOnly ?? 'any',
        featuredOnly,
        sort.code,
        cursor ?? '',
      ].join('|');
}

final class PagedResult<T> {
  const PagedResult({
    required this.items,
    this.nextCursor,
    this.totalEstimate,
  });

  final List<T> items;
  final String? nextCursor;
  final int? totalEstimate;

  bool get hasMore => nextCursor != null;
  bool get isEmpty => items.isEmpty;

  static PagedResult<T> emptyPage<T>() => PagedResult<T>(items: const <Never>[]);
}
