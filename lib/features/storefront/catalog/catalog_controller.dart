import 'dart:async';

import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/features/storefront/common/categories_store.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/common/wishlist_actions.dart';

/// One controller driving every product-result surface: category pages and search results.
/// All filtering is expressed through `CatalogQuery`; the repository decides how it is executed,
/// and this class only accumulates pages for display.
class CatalogController extends GetxController with WishlistToggleMixin {
  @override
  void onInit() {
    super.onInit();
    _query = initialQuery();
    bootstrap();
  }

  late CatalogQuery _query;
  CatalogQuery get query => _query;

  final RxList<Product> items = <Product>[].obs;
  final Rxn<Category> category = Rxn<Category>();
  final Rxn<String> nextCursor = Rxn<String>();
  final Rxn<int> totalEstimate = Rxn<int>();
  final RxBool loadingFirst = false.obs;
  final RxBool loadingMore = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxSet<String> activeTags = <String>{}.obs;

  bool get hasMore => nextCursor.value != null;
  bool get isEmpty => items.isEmpty;

  /// Facet chips are derived from what the current page set actually carries; the repo has no
  /// facet-count endpoint, so chips never promise a count the server did not report.
  List<String> get facetTags {
    final counts = <String, int>{};
    for (final product in items) {
      for (final tag in product.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return entries.take(12).map((e) => e.key).toList(growable: false);
  }

  /// Overridable so the search page can start from a query term instead of a category slug.
  /// It is a public instance method on purpose: a private name cannot be overridden from another
  /// library, which would leave the dedicated search page with no way to seed its query.
  CatalogQuery initialQuery() {
    final slug = Get.parameters['slug'];
    if (slug != null && slug.isNotEmpty) {
      return CatalogQuery(
        categorySlug: slug,
        sort: SortMode.relevance,
        wholesaleOnly: null,
      );
    }
    return const CatalogQuery(sort: SortMode.relevance);
  }

  Future<void> bootstrap() async {
    final slug = _query.categorySlug;
    if (slug != null && slug.isNotEmpty) {
      final resolved = await safeCall<Category>(
        () => Get.find<CategoryRepository>().bySlug(slug),
      );
      category.value = resolved;
    } else {
      Get.find<CategoriesStore>().ensureLoaded();
    }
    await refresh();
  }

  /// Re-runs the current query from page one.
  Future<void> refresh() async {
    loadingFirst.value = true;
    failure.value = null;
    final page = await safeCall<PagedResult<Product>>(
      () => Get.find<ProductRepository>().search(_query),
      onFailure: (f) => failure.value = f,
    );
    if (page != null) {
      items.assignAll(page.items);
      nextCursor.value = page.nextCursor;
      totalEstimate.value = page.totalEstimate;
    }
    loadingFirst.value = false;
  }

  Future<void> loadMore() async {
    final cursor = nextCursor.value;
    if (cursor == null || loadingMore.value) return;
    loadingMore.value = true;
    final page = await safeCall<PagedResult<Product>>(
      () => Get.find<ProductRepository>().search(_query.copyWith(cursor: cursor)),
      onFailure: (f) => failure.value = f,
    );
    if (page != null) {
      items.addAll(page.items);
      nextCursor.value = page.nextCursor;
      totalEstimate.value = page.totalEstimate;
    }
    loadingMore.value = false;
  }

  void setSort(SortMode mode) {
    _query = _query.copyWith(sort: mode);
    refresh();
  }

  void toggleTag(String tag) {
    final tags = activeTags.toSet();
    if (!tags.remove(tag)) tags.add(tag);
    activeTags.assignAll(tags);
    _query = _query.copyWith(tags: tags.toList(growable: false));
    refresh();
  }

  /// Whole-rupee band converted to paise; a negative or empty bound clears that side.
  void setPriceBand({int? minRupees, int? maxRupees}) {
    _query = CatalogQuery(
      search: _query.search,
      categoryId: _query.categoryId,
      categorySlug: _query.categorySlug,
      tags: _query.tags,
      inStockOnly: _query.inStockOnly,
      featuredOnly: _query.featuredOnly,
      wholesaleOnly: _query.wholesaleOnly,
      sort: _query.sort,
      pageSize: _query.pageSize,
      minPricePaise: minRupees == null ? null : minRupees * 100,
      maxPricePaise: maxRupees == null ? null : maxRupees * 100,
    );
    refresh();
  }

  void setInStockOnly(bool on) {
    _query = CatalogQuery(
      search: _query.search,
      categoryId: _query.categoryId,
      categorySlug: _query.categorySlug,
      tags: _query.tags,
      minPricePaise: _query.minPricePaise,
      maxPricePaise: _query.maxPricePaise,
      inStockOnly: on,
      featuredOnly: _query.featuredOnly,
      wholesaleOnly: _query.wholesaleOnly,
      sort: _query.sort,
      pageSize: _query.pageSize,
    );
    refresh();
  }

  void clearFilters() {
    activeTags.clear();
    _query = initialQuery();
    refresh();
  }

  /// Replaces the whole active query. `CatalogQuery.copyWith` cannot clear a nullable bound back
  /// to null, so a filter sheet that must be able to *remove* a price band rebuilds the query and
  /// hands it over here — one repository round-trip per user action.
  void applyQuery(CatalogQuery next, {bool reload = true}) {
    _query = next;
    activeTags.assignAll(next.tags);
    if (reload) refresh();
  }

  void openProduct(Product product) =>
      Get.toNamed<dynamic>(OmRoutes.forProduct(product.pathSlug));

  List<Category> suggestionCategories() {
    if (!Get.isRegistered<CategoriesStore>()) return const <Category>[];
    return Get.find<CategoriesStore>().topLevel.take(6).toList(growable: false);
  }
}
