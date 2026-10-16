import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/features/storefront/common/categories_store.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/common/wishlist_actions.dart';

/// Home is presentation-only: shelf products and the category rail. There is no pricing or
/// stock decision here; cards ask the engine per line.
final class HomeController extends GetxController with WishlistToggleMixin {
  static const int _shelfLimit = 12;

  final RxList<Product> bestSellers = <Product>[].obs;
  final RxList<Product> newArrivals = <Product>[].obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxBool loading = true.obs;

  CategoriesStore get _categories => Get.find<CategoriesStore>();
  List<Category> get railCategories => _categories.topLevel;

  @override
  void onInit() {
    super.onInit();
    _categories.ensureLoaded();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    final shelf = await safeCall<List<Product>>(
      () => Get.find<ProductRepository>().homeShelf(
            featuredLimit: _shelfLimit,
            bestSellerLimit: _shelfLimit,
            newArrivalLimit: _shelfLimit,
          ),
      onFailure: (f) => failure.value = f,
    );
    if (shelf != null) {
      bestSellers.assignAll(shelf.where((p) => p.isBestSeller || p.isFeatured));
      newArrivals.assignAll(shelf.where((p) => p.isNewArrival));
    }
    loading.value = false;
  }

  void retry() => load();
}
