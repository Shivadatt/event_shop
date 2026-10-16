import 'package:get/get.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';

/// Review moderation queue.
///
/// `moderationQueue` is a bounded server read for one status at a time, so the screen filters by
/// status rather than slicing a client list. Approve/reject call `decideReview`, whose Cloud
/// Function re-checks the staff role and writes the audit row.
final class ReviewsController extends AdminController {
  ReviewsController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  final RxList<Review> queue = <Review>[].obs;
  final Rx<ReviewStatus> statusFilter = ReviewStatus.pending.obs;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    final rows = await guard<List<Review>>(
      () => _admin.moderationQueue(status: statusFilter.value),
    );
    if (rows != null) queue.assignAll(rows);
  }

  void applyStatus(ReviewStatus value) {
    statusFilter.value = value;
    load();
  }

  /// Publish or reject, with the moderator note stored alongside the decision.
  Future<void> decide(Review review, ReviewStatus decision, String note) async {
    final ok = await mutateVoid(
      () => _admin.decideReview(
        reviewId: review.id,
        decision: decision,
        note: note,
      ),
    );
    if (!ok) {
      announce(failure.value?.message ?? 'The decision was refused.', error: true);
      return;
    }
    announce(
      '${review.isVerifiedPurchase ? 'Verified' : 'Review'} '
      '${decision == ReviewStatus.published ? 'approved' : 'decided'}. The re-check of your role '
      'and the aggregate recompute are done by the write, not this screen.',
    );
    await load();
  }
}
