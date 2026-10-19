import 'package:get/get.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/models/wholesale.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';

/// Wholesale applications queue.
///
/// `decideWholesale` is the only way an account reaches wholesale pricing: this screen never flips
/// a user's role or status directly, so the UI cannot become the permission. The function re-checks
/// the staff role and writes both the user profile and the audit row.
final class WholesaleController extends AdminController {
  WholesaleController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final RxList<WholesaleApplication> applications = <WholesaleApplication>[].obs;
  final RxBool openOnly = true.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final rows = await guard<List<WholesaleApplication>>(
      () => _admin.wholesaleApplications(openOnly: openOnly.value),
    );
    if (rows != null) applications.assignAll(rows);
  }

  void applyOpenOnly(bool value) {
    openOnly.value = value;
    load();
  }

  Future<void> decide(
    WholesaleApplication application,
    bool approve,
    String note,
  ) async {
    final ok = await mutateVoid(
      () => _admin.decideWholesale(
        applicationId: application.id,
        decision: approve ? WholesaleStatus.approved : WholesaleStatus.rejected,
        note: note,
      ),
    );
    if (!ok) {
      announce(failure.value?.message ?? 'The decision was refused.', error: true);
      return;
    }
    announce(
      approve
          ? '${application.companyName} approved. Wholesale pricing is now live for that account — '
              'granted by the write, not by this screen.'
          : '${application.companyName} rejected. The note is stored with the application.',
    );
    await load();
  }
}
