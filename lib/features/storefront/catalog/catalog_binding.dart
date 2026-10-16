import 'package:get/get.dart';
import 'package:om_events/features/storefront/catalog/catalog_controller.dart';

/// Binding for the category-listing page. Every storefront page pairs this with
/// `StorefrontBinding`, which owns the shared cart / settings / category stores.
/// The controller reads `:slug` from the route parameters in `onInit`.
final class CatalogBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CatalogController>(CatalogController.new, fenix: true);
  }
}
