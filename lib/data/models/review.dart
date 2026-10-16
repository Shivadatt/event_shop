import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/om_doc.dart';

enum ReviewStatus {
  pending('pending'),
  published('published'),
  hidden('hidden'),
  rejected('rejected');

  const ReviewStatus(this.code);
  final String code;
}

ReviewStatus reviewStatusFromCode(String code) => ReviewStatus.values
    .firstWhere((s) => s.code == code, orElse: () => ReviewStatus.pending);

final class Review {
  const Review({
    required this.id,
    required this.productId,
    required this.uid,
    required this.rating,
    this.title = '',
    this.body = '',
    this.authorName = '',
    this.status = ReviewStatus.pending,
    this.isVerifiedPurchase = false,
    this.orderId = '',
    this.images = const <MediaRef>[],
    this.reportCount = 0,
    this.moderatorNote = '',
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String productId;
  final String uid;

  /// 1..5 only. Rules clamp it, the form clamps it again, and the aggregate is recomputed
  /// server-side so a burst of writes cannot skew the average.
  final int rating;
  final String title;
  final String body;
  final String authorName;
  final ReviewStatus status;

  /// Derived from an actual delivered order containing this product — never self-declared.
  final bool isVerifiedPurchase;
  final String orderId;
  final List<MediaRef> images;
  final int reportCount;
  final String moderatorNote;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  static const int maxBodyLength = 2000;
  static const int reportedThreshold = 3;

  bool get isPubliclyVisible => status == ReviewStatus.published;
  bool get isFlagged => reportCount >= reportedThreshold;

  factory Review.fromMap(Map<String, dynamic> m, {String? id}) => Review(
        id: id ?? readStringOrEmpty(m, 'id'),
        productId: readStringOrEmpty(m, 'productId'),
        uid: readStringOrEmpty(m, 'uid'),
        rating: (readInt(m, 'rating') ?? 0).clamp(1, 5),
        title: readStringOrEmpty(m, 'title'),
        body: readStringOrEmpty(m, 'body'),
        authorName: readStringOrEmpty(m, 'authorName'),
        status: reviewStatusFromCode(readStringOrEmpty(m, 'status')),
        isVerifiedPurchase: readBool(m, 'isVerifiedPurchase'),
        orderId: readStringOrEmpty(m, 'orderId'),
        images: readMapList(m, 'images').map(MediaRef.fromMap).toList(growable: false),
        reportCount: readIntOrZero(m, 'reportCount'),
        moderatorNote: readStringOrEmpty(m, 'moderatorNote'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'productId': productId,
        'uid': uid,
        'rating': rating,
        'title': title,
        'body': body,
        'authorName': authorName,
        'status': status.code,
        'isVerifiedPurchase': isVerifiedPurchase,
        'orderId': orderId,
        'images': images.map((i) => i.toMap()).toList(),
        'moderatorNote': moderatorNote,
      });
}

/// Rating histogram for the summary widget: index 1..5 -> count.
final class RatingBreakdown {
  const RatingBreakdown({
    required this.total,
    required this.average,
    required this.byStar,
  });

  final int total;
  final double average;
  final Map<int, int> byStar;

  int countFor(int star) => byStar[star] ?? 0;

  double fractionFor(int star) => total == 0 ? 0 : countFor(star) / total;

  factory RatingBreakdown.from(List<Review> reviews) {
    final visible = reviews.where((r) => r.isPubliclyVisible).toList(growable: false);
    final byStar = <int, int>{for (var star = 1; star <= 5; star++) star: 0};
    var sum = 0;
    for (final review in visible) {
      final star = review.rating.clamp(1, 5);
      byStar[star] = (byStar[star] ?? 0) + 1;
      sum += star;
    }
    final total = visible.length;
    return RatingBreakdown(
      total: total,
      average: total == 0 ? 0 : sum / total,
      byStar: byStar,
    );
  }
}
