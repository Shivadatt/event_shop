import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/utils/om_validators.dart';
import 'package:om_events/data/models/address.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/support.dart';
import 'package:om_events/data/repositories/account_repository.dart';
import 'package:om_events/features/storefront/common/safe_call.dart';
import 'package:om_events/features/storefront/common/wishlist_actions.dart';

/// `/account/addresses`. CRUD over `AddressRepository`; the server keeps exactly one default
/// shipping (and optionally billing) row, which is why "make default" is a call and not a local
/// flag flip.
final class AddressController extends GetxController {
  final RxList<AddressBookEntry> entries = <AddressBookEntry>[].obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  AddressRepository get _repository => Get.find<AddressRepository>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    final list = await safeCall<List<AddressBookEntry>>(
      _repository.forCurrentUser,
      onFailure: (f) => failure.value = f,
    );
    loading.value = false;
    if (list != null) entries.assignAll(list);
  }

  AddressBookEntry? get defaultShipping {
    for (final entry in entries) {
      if (entry.isDefaultShipping) return entry;
    }
    return entries.isEmpty ? null : entries.first;
  }

  Future<bool> save(AddressBookEntry entry) async {
    if (busy.value) return false;
    busy.value = true;
    failure.value = null;
    final savedEntry = await safeCall<AddressBookEntry>(
      () => _repository.save(entry),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    if (savedEntry == null) return false;
    final index = entries.indexWhere((e) => e.id == savedEntry.id);
    if (index >= 0) {
      entries[index] = savedEntry;
    } else {
      entries.add(savedEntry);
    }
    entries.refresh();
    return true;
  }

  Future<void> remove(AddressBookEntry entry) async {
    busy.value = true;
    failure.value = null;
    final ok = await tryCall(() => _repository.delete(entry.id),
        onFailure: (f) => failure.value = f);
    busy.value = false;
    if (ok) entries.removeWhere((e) => e.id == entry.id);
  }

  Future<void> makeDefault(AddressBookEntry entry, {bool billing = false}) async {
    busy.value = true;
    failure.value = null;
    final ok = await tryCall(
      () => _repository.setDefault(entry.id, billing: billing),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    if (ok) await load();
  }
}

/// `/account/wishlist`. Resolves saved ids into live products, so an archived item drops out
/// instead of rendering a broken card.
final class WishlistController extends GetxController with WishlistToggleMixin {
  final RxList<Product> items = <Product>[].obs;
  final RxBool loading = true.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    final list = await safeCall<List<Product>>(
      () => Get.find<WishlistRepository>().items(),
      onFailure: (f) => failure.value = f,
    );
    loading.value = false;
    if (list == null) return;
    items.assignAll(list);
    // The session profile is the source of truth for the heart state; a removed item that the
    // server already dropped must not stay ticked.
    final session = Get.find<SessionStore>();
    final ids = list.map((p) => p.id).toSet();
    final kept = session.profile?.wishlistProductIds
            .where(ids.contains)
            .toList(growable: false) ??
        const <String>[];
    if (kept.length != (session.profile?.wishlistProductIds.length ?? 0)) {
      session.set(session.profile?.copyWith(wishlistProductIds: kept));
    }
  }

  Future<void> remove(Product product) async {
    await toggleWishlist(product);
    items.removeWhere((item) => item.id == product.id);
  }
}

/// `/account/notifications`. Streams from `AccountRepository`; a read marker is a server write.
final class NotificationController extends GetxController {
  final RxList<AppNotification> items = <AppNotification>[].obs;
  final RxBool loading = true.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();

  StreamSubscription<List<AppNotification>>? _subscription;

  @override
  void onInit() {
    super.onInit();
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    loading.value = true;
    failure.value = null;
    try {
      _subscription = Get.find<AccountRepository>()
          .notifications()
          .listen(
            (list) {
              items.assignAll(list);
              loading.value = false;
              failure.value = null;
            },
            onError: (Object error) {
              loading.value = false;
              failure.value = error is OmFailure
                  ? error
                  : const ServerFailure('Notifications are unavailable right now.');
            },
          );
    } on OmFailure catch (error) {
      loading.value = false;
      failure.value = error;
    } catch (_) {
      loading.value = false;
      failure.value = const ServerFailure('Notifications are unavailable right now.');
    }
  }

  void retry() => _subscribe();

  int get unreadCount => items.where((item) => !item.isRead).length;

  Future<void> markRead(AppNotification item) async {
    if (item.isRead) return;
    await safeCall<void>(() => Get.find<AccountRepository>().markNotificationRead(item.id));
  }

  Future<void> markAllRead() async {
    await safeCall<void>(() => Get.find<AccountRepository>().markAllNotificationsRead());
  }

  Future<void> open(AppNotification item) async {
    await markRead(item);
    final route = item.route;
    if (route.startsWith('/') && !route.startsWith('//')) {
      await Get.toNamed<dynamic>(route);
    }
  }

  @override
  void onClose() {
    _subscription?.cancel();
    super.onClose();
  }
}

/// `/account/support`. Opens tickets through `AccountRepository` and keeps the thread readable.
final class SupportController extends GetxController {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController subject = TextEditingController();
  final TextEditingController message = TextEditingController();
  final Rx<SupportTopic> topic = SupportTopic.orderIssue.obs;
  final Rxn<String> orderId = Rxn<String>();
  final Rxn<String> productId = Rxn<String>();
  final RxList<SupportRequest> tickets = <SupportRequest>[].obs;
  final RxBool loading = true.obs;
  final RxBool busy = false.obs;
  final RxBool opened = false.obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final Rxn<OmFailure> replyFailure = Rxn<OmFailure>();
  final TextEditingController reply = TextEditingController();

  @override
  void onInit() {
    super.onInit();
    // Support can be entered from an order card, which passes the ids in the query string.
    orderId.value = Get.parameters['orderId'];
    productId.value = Get.parameters['productId'];
    loadTickets();
  }

  @override
  void onClose() {
    subject.dispose();
    message.dispose();
    reply.dispose();
    super.onClose();
  }

  AccountRepository get _repository => Get.find<AccountRepository>();

  Future<void> loadTickets() async {
    loading.value = true;
    final list = await safeCall<List<SupportRequest>>(
      _repository.mySupportTickets,
      onFailure: (f) => failure.value = f,
    );
    loading.value = false;
    if (list != null) tickets.assignAll(list);
  }

  Future<void> submit() async {
    if (busy.value) return;
    if (!(formKey.currentState?.validate() ?? false)) return;
    busy.value = true;
    failure.value = null;
    final request = await safeCall<SupportRequest>(
      () => _repository.openSupportTicket(
        subject: subject.text.trim(),
        topic: topic.value,
        message: message.text.trim(),
        orderId: orderId.value,
        productId: productId.value,
      ),
      onFailure: (f) => failure.value = f,
    );
    busy.value = false;
    if (request == null) return;
    tickets.insert(0, request);
    opened.value = true;
    subject.clear();
    message.clear();
  }

  Future<void> replyTo(SupportRequest ticket) async {
    if (reply.text.trim().isEmpty) {
      replyFailure.value = const ValidationFailure('Write a reply first');
      return;
    }
    replyFailure.value = null;
    busy.value = true;
    final ok = await tryCall(
      () => _repository.replyToTicket(ticket.id, message: reply.text.trim()),
      onFailure: (f) => replyFailure.value = f,
    );
    busy.value = false;
    if (ok) {
      reply.clear();
      await loadTickets();
    }
  }

  String? validateSubject(String? value) =>
      OmValidators.required(value, label: 'Subject');

  String? validateMessage(String? value) {
    final error = OmValidators.required(value, label: 'Message');
    if (error != null) return error;
    if ((value ?? '').trim().length < 12) {
      return 'Give the team at least a sentence to work with';
    }
    return null;
  }
}
