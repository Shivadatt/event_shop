import 'package:get/get.dart';
import 'package:om_events/features/storefront/search/search_controller.dart';

/// One controller instance for `/search`. `SearchController` extends `CatalogController`, so the
/// shared `CatalogResults` widget is handed the instance directly rather than resolved under a
/// second DI key — registering the same object twice would run `onInit` (and therefore the first
/// page fetch) twice.
final class SearchBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<SearchController>(SearchController.new, fenix: true);
  }
}
