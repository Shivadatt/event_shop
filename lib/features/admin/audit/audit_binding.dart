import 'package:get/get.dart';
import 'package:om_events/features/admin/audit/audit_controller.dart';

/// Audit log screen.
final class AuditBinding extends Bindings {
  @override
  void dependencies() {
    Get.lazyPut<AuditController>(AuditController.new, fenix: true);
  }
}
