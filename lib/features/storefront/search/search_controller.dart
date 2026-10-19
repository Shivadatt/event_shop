import 'dart:async';

import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/features/storefront/catalog/catalog_controller.dart';
import 'package:om_events/features/storefront/common/categories_store.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';

/// Dedicated search page (`/search?q=…`).
///
/// It *is* a `CatalogController`: the term arrives through `initialQuery()` instead of a category
/// slug, so the shared results grid, paging, sort and failure handling stay in one place. Only the
/// search-box concerns (debounced suggestions and the filter panel) are added here.
///
/// Authority: filtering is expressed as a `CatalogQuery` and executed by `ProductRepository`; the
/// prices the grid shows come from `PricingEngine` per card, never from this controller.
final class SearchController extends CatalogController {
  static const Duration _debounce = Duration(milliseconds: 320);

  final RxString term = ''.obs;
  final RxList<String> suggestions = <String>[].obs;
  final RxBool suggestionsLoading = false.obs;
  final Rxn<OmFailure> suggestionFailure = Rxn<OmFailure>();
  final RxBool sheetOpen = false.obs;

  Timer? _debounceTimer;

  @override
  CatalogQuery initialQuery() {
    final incoming = (Get.parameters[OmRouteArgs.search] ?? '').trim();
    term.value = incoming;
    return CatalogQuery(
      search: incoming,
    );
  }

  @override
  void onClose() {
    _debounceTimer?.cancel();
    super.onClose();
  }

  /// Typed term. The grid only refetches on submit (Enter / Search button) so every keystroke is
  /// not a billable read, while suggestions do debounce.
  void onTermChanged(String value) {
    term.value = value;
    final trimmed = value.trim();
    _debounceTimer?.cancel();
    if (trimmed.length < 2) {
      clearSuggestions();
      return;
    }
    suggestionsLoading.value = true;
    _debounceTimer = Timer(_debounce, () => _fetchSuggestions(trimmed));
  }

  Future<void> _fetchSuggestions(String trimmed) async {
    final result = await safeCall<List<String>>(
      () => Get.find<ProductRepository>().suggestions(trimmed),
      onFailure: (f) {
        suggestionFailure.value = f;
        suggestionsLoading.value = false;
      },
    );
    if (result == null) return;
    suggestions.assignAll(result);
    suggestionFailure.value = null;
    suggestionsLoading.value = false;
  }

  void clearSuggestions() {
    _debounceTimer?.cancel();
    suggestions.clear();
    suggestionsLoading.value = false;
    suggestionFailure.value = null;
  }

  /// Runs the search the URL would produce for this term, so a submitted search stays shareable.
  void runSearch(String value) {
    final trimmed = value.trim();
    clearSuggestions();
    _apply(search: trimmed);
  }

  /// A tapped suggestion is a search, not a product link: the buyer still wants the result list.
  void useSuggestion(String value) => runSearch(value);

  /// The one write path. Every field is stated explicitly because `CatalogQuery.copyWith` cannot
  /// return a nullable bound to null — which is precisely what "clear this filter" has to do.
  /// Each public setter below passes the fields it is not changing from the live query, so no
  /// mutation can silently drop a filter the caller never mentioned.
  void _apply({
    String? search,
    Category? category,
    bool clearCategory = false,
    List<String>? tags,
    int? minPricePaise,
    int? maxPricePaise,
    bool clearMinPrice = false,
    bool clearMaxPrice = false,
    bool? inStockOnly,
    bool? featuredOnly,
    bool? wholesaleOnly,
    bool clearWholesaleOnly = false,
    SortMode? sort,
  }) {
    final current = query;
    final next = CatalogQuery(
      search: search ?? current.search,
      categoryId: clearCategory ? null : (category?.id ?? current.categoryId),
      categorySlug: clearCategory ? null : (category?.pathSlug ?? current.categorySlug),
      tags: tags ?? current.tags,
      minPricePaise: clearMinPrice ? null : (minPricePaise ?? current.minPricePaise),
      maxPricePaise: clearMaxPrice ? null : (maxPricePaise ?? current.maxPricePaise),
      inStockOnly: inStockOnly ?? current.inStockOnly,
      featuredOnly: featuredOnly ?? current.featuredOnly,
      wholesaleOnly: clearWholesaleOnly ? null : (wholesaleOnly ?? current.wholesaleOnly),
      sort: sort ?? current.sort,
      pageSize: current.pageSize,
    );
    term.value = next.search;
    applyQuery(next);
  }

  void setCategory(Category? category) {
    if (category == null) {
      _apply(clearCategory: true);
    } else {
      _apply(category: category);
    }
  }

  @override
  void setSort(SortMode mode) => _apply(sort: mode);

  void setTags(List<String> tags) => _apply(tags: tags);

  void toggleTagFromSheet(String tag) {
    final tags = activeTags.toSet();
    if (!tags.remove(tag)) tags.add(tag);
    _apply(tags: tags.toList(growable: false));
  }

  /// Price band in integer paise, the unit `CatalogQuery` stores.
  ///
  /// Named apart from `CatalogController.setPriceBand` on purpose: the base setter takes whole
  /// rupees and multiplies by 100, so a same-named override with paise parameters would be an
  /// invalid (and silently money-losing) override. The filter panel already converts the buyer's
  /// rupee input to paise and calls this.
  void setPriceBandPaise({int? minPaise, int? maxPaise}) => _apply(
        minPricePaise: minPaise,
        maxPricePaise: maxPaise,
        clearMinPrice: minPaise == null,
        clearMaxPrice: maxPaise == null,
      );

  @override
  void setInStockOnly(bool on) => _apply(inStockOnly: on);

  void setFeaturedOnly(bool on) => _apply(featuredOnly: on);

  /// Tri-state on purpose: `null` means "do not filter by wholesale", which is what a buyer who
  /// toggles the switch back off wants — `false` would mean "hide wholesale-only products".
  void setWholesaleOnly(bool? on) {
    if (on == null) {
      _apply(clearWholesaleOnly: true);
    } else {
      _apply(wholesaleOnly: on);
    }
  }

  /// Clears the filters but keeps the term — "start over" should not lose what was typed.
  @override
  void clearFilters() => resetFilters();

  void resetFilters() => _apply(
        clearCategory: true,
        tags: const <String>[],
        clearMinPrice: true,
        clearMaxPrice: true,
        inStockOnly: false,
        featuredOnly: false,
        clearWholesaleOnly: true,
      );

  void openSheet() => sheetOpen.value = true;
  void closeSheet() => sheetOpen.value = false;

  List<Category> get categoryChoices {
    if (!Get.isRegistered<CategoriesStore>()) return const <Category>[];
    return Get.find<CategoriesStore>().topLevel;
  }

  /// Resolved from the loaded tree, so the panel can highlight the active category without the
  /// route carrying a category object.
  Category? get activeCategory {
    final slug = query.categorySlug;
    if (slug == null || slug.isEmpty) return null;
    for (final category in categoryChoices) {
      if (category.pathSlug == slug) return category;
    }
    return null;
  }

  bool get hasActiveTerm => term.value.trim().isNotEmpty;

  int get activeFilterCount => query.filterCount;

  /// The URL this search would produce, offered as a copyable link.
  String get deepLink {
    final value = term.value.trim();
    return value.isEmpty
        ? OmRoutes.search
        : '${OmRoutes.search}?${OmRouteArgs.search}=${Uri.encodeComponent(value)}';
  }

  /// Absolute form of [deepLink], for sharing.
  String get absoluteDeepLink => Uri.base.resolve(deepLink).toString();
}
