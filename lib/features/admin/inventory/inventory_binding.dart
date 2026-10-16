import 'package:get/get.dart';
import 'package:om_events/features/admin/inventory/inventory_controller.dart';

/// Inventory screen. Three controllers, one per concern: the stock table, the movement form and the
/// ledger. No god-controller — each owns only its own read/write.
final class InventoryBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<InventoryController>(InventoryController.new, fenix: true);
    Get.lazyPut<StockAdjustController>(StockAdjustController.new, fenix: true);
    Get.lazyPut<StockLedgerController>(StockLedgerController.new, fenix: true);
  }
}
