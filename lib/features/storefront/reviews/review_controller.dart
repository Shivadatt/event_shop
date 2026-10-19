import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/data/repositories/order_repository.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';

/// `/review/:productId` — compose or edit the buyer's own review for one product.
///
/// Verified purchase is not asserted here: the submission carries an `orderId` guess from the
/// buyer's own delivered orders and `ReviewRepository.submit` (the Cloud Function) is what decides
/// `Review.isVerifiedPurchase`. The badge shown after submitting is the server's answer.
final class ReviewComposeController extends GetxController {
  final Rxn<Product> product = Rxn<Product>();
  final Rxn<Review> existing = Rxn<Review>();
  final RxInt rating = 0.obs;
  final Rxn<MediaRef> photo = Rxn<MediaRef>();
  final RxList<Order> deliveredOrders = <Order>[].obs;
  final Rxn<String> linkedOrderId = Rxn<String>();
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxBool done = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();

  final TextEditingController title = TextEditingController();
  final TextEditingController body = TextEditingController();

  String get productId => Get.parameters['productId'] ?? '';

  UserProfile? get profile => Get.find<SessionStore>().profile;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  @override
  void onClose() {
    title.dispose();
    body.dispose();
    super.onClose();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    if (productId.isEmpty) {
      loading.value = false;
      failure.value = const NotFoundFailure('No product id in this link.');
      return;
    }
    final loaded = await safeCall<Product>(
      () => Get.find<ProductRepository>().byId(productId),
      onFailure: (f) => failure.value = f,
    );
    if (loaded != null) product.value = loaded;

    // `mineFor` is nullable by contract: "no review yet" is a valid answer, not a failure, so the
    // generic stays `Review?` and `safeCall` returns `Review?`.
    final mine = await safeCall<Review?>(
      () => Get.find<ReviewRepository>().mineFor(productId),
      onFailure: (f) => failure.value = f,
    );
    if (mine != null) {
      existing.value = mine;
      rating.value = mine.rating;
      title.text = mine.title;
      body.text = mine.body;
      if (mine.images.isNotEmpty) photo.value = mine.images.first;
    }

    await _findDeliveredOrders();
    loading.value = false;
  }

  Future<void> _findDeliveredOrders() async {
    final page = await safeCall<PagedResult<Order>>(
      () => Get.find<OrderRepository>().listMine(),
    );
    if (page == null) return;
    final matching = page.items
        .where(
          (order) =>
              order.status == OrderStatus.delivered &&
              order.items.any((item) => item.productId == productId),
        )
        .toList(growable: false);
    deliveredOrders.assignAll(matching);
    if (existing.value?.orderId.isNotEmpty == true) {
      linkedOrderId.value = existing.value!.orderId;
    } else if (matching.length == 1) {
      linkedOrderId.value = matching.first.id;
    }
  }

  void setRating(int value) => rating.value = value.clamp(1, 5);

  void setPhoto(MediaRef? ref) {
    if (ref != null && ref.id.isNotEmpty) photo.value = ref;
    if (ref == null) photo.value = null;
  }

  void pickOrder(String? id) => linkedOrderId.value = id;

  bool get canSubmit => rating.value >= 1 && !busy.value;

  Future<void> submit() async {
    if (!canSubmit) {
      failure.value = const ValidationFailure('Choose a star rating first');
      return;
    }
    if (!(formKey.currentState?.validate() ?? false)) return;
    busy.value = true;
    failure.value = null;
    final images = photo.value == null
        ? const <MediaRef>[]
        : <MediaRef>[photo.value!];
    final saved = await safeCall<Review>(
      () => Get.find<ReviewRepository>().submit(
        productId: productId,
        rating: rating.value,
        title: title.text.trim(),
        body: body.text.trim(),
        orderId: linkedOrderId.value,
        images: images,
      ),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    if (saved == null) return;
    existing.value = saved;
    done.value = true;
  }

  String? validateBody(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty && existing.value == null) {
      return 'Tell other buyers what you received';
    }
    if (text.length > Review.maxBodyLength) {
      return 'Keep it under ${Review.maxBodyLength} characters';
    }
    return null;
  }
}
