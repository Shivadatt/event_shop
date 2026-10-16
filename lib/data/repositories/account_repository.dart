import 'package:om_events/data/models/address.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/review.dart';
import 'package:om_events/data/models/support.dart';

abstract interface class AddressRepository {
  Future<List<AddressBookEntry>> forCurrentUser();

  Future<AddressBookEntry> save(AddressBookEntry entry);

  Future<void> delete(String addressId);

  Future<void> setDefault(String addressId, {bool billing = false});
}

abstract interface class WishlistRepository {
  Future<List<String>> ids();

  /// Resolves the ids into live products so a deleted or archived item drops out instead of
  /// rendering a broken card.
  Future<List<Product>> items();

  Future<bool> toggle(String productId, {required bool add});
}

/// Locally persisted "recently viewed" trail — personal data, not store data, so it is not a
/// Firestore collection.
abstract interface class RecentlyViewedRepository {
  Future<List<String>> ids();

  Future<void> push(String productId, {int limit = 24});

  Future<void> clear();
}

abstract interface class ReviewRepository {
  Future<List<Review>> forProduct(String productId, {bool publishedOnly = true});

  Future<RatingBreakdown> breakdownFor(String productId);

  /// Submission writes a pending review through the function, which verifies purchase and
  /// enforces one-review-per-buyer-per-product.
  Future<Review> submit({
    required String productId,
    required int rating,
    String title = '',
    String body = '',
    String? orderId,
    List<MediaRef> images = const <MediaRef>[],
  });

  Future<void> report(String reviewId, {required String reason});

  Future<Review?> mineFor(String productId);
}

abstract interface class AccountRepository {
  Stream<List<AppNotification>> notifications({int limit = 30});

  Future<void> markNotificationRead(String id);

  Future<void> markAllNotificationsRead();

  Future<SupportRequest> openSupportTicket({
    required String subject,
    required SupportTopic topic,
    required String message,
    String? orderId,
    String? productId,
  });

  Future<List<SupportRequest>> mySupportTickets();

  Future<void> replyToTicket(String ticketId, {required String message});
}
