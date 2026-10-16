import 'package:get/get.dart';
import 'package:om_events/features/admin/categories/categories_controller.dart';

/// Category tree + the inline editor. Both controllers belong to this route; the editor is a
/// second controller on purpose so the tree list never accumulates draft state.
final class CategoriesBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<CategoriesController>(CategoriesController.new, fenix: true);
    Get.lazyPut<CategoryEditController>(CategoryEditController.new, fenix: true);
  }
}
