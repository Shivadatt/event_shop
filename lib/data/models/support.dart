import 'package:om_events/data/om_doc.dart';

enum SupportStatus {
  open('open'),
  inProgress('inProgress'),
  awaitingCustomer('awaitingCustomer'),
  resolved('resolved'),
  closed('closed');

  const SupportStatus(this.code);
  final String code;
}

SupportStatus supportStatusFromCode(String code) => SupportStatus.values
    .firstWhere((s) => s.code == code, orElse: () => SupportStatus.open);

enum SupportTopic {
  orderIssue('orderIssue'),
  returnRequest('returnRequest'),
  wholesaleQuery('wholesaleQuery'),
  pricingQuery('pricingQuery'),
  productQuestion('productQuestion'),
  other('other');

  const SupportTopic(this.code);
  final String code;
}

SupportTopic supportTopicFromCode(String code) => SupportTopic.values
    .firstWhere((t) => t.code == code, orElse: () => SupportTopic.other);

final class SupportMessage {
  const SupportMessage({
    required this.from,
    required this.body,
    required this.at,
    this.isStaff = false,
  });

  final String from;
  final String body;
  final DateTime at;
  final bool isStaff;

  factory SupportMessage.fromMap(Map<String, dynamic> m) => SupportMessage(
        from: readStringOrEmpty(m, 'from'),
        body: readStringOrEmpty(m, 'body'),
        at: readDate(m, 'at') ?? DateTime.now(),
        isStaff: readBool(m, 'isStaff'),
      );

  Map<String, Object?> toMap() => <String, Object?>{
        'from': from,
        'body': body,
        'at': at,
        'isStaff': isStaff,
      };
}

final class SupportRequest {
  const SupportRequest({
    required this.id,
    required this.uid,
    required this.subject,
    this.orderId = '',
    this.productId = '',
    this.topic = SupportTopic.other,
    this.status = SupportStatus.open,
    this.messages = const <SupportMessage>[],
    this.createdAt,
    this.updatedAt,
    this.resolvedAt,
  });

  final String id;
  final String uid;
  final String subject;
  final String orderId;
  final String productId;
  final SupportTopic topic;
  final SupportStatus status;

  /// Bounded thread: the writer caps replies and older turns move to `messages/{range}` if the
  /// conversation ever outgrows one document.
  final List<SupportMessage> messages;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final DateTime? resolvedAt;

  static const int maxMessagesPerThread = 100;

  bool get isOpen => status == SupportStatus.open || status == SupportStatus.inProgress;

  factory SupportRequest.fromMap(Map<String, dynamic> m, {String? id}) => SupportRequest(
        id: id ?? readStringOrEmpty(m, 'id'),
        uid: readStringOrEmpty(m, 'uid'),
        subject: readStringOrEmpty(m, 'subject'),
        orderId: readStringOrEmpty(m, 'orderId'),
        productId: readStringOrEmpty(m, 'productId'),
        topic: supportTopicFromCode(readStringOrEmpty(m, 'topic')),
        status: supportStatusFromCode(readStringOrEmpty(m, 'status')),
        messages:
            readMapList(m, 'messages').map(SupportMessage.fromMap).toList(growable: false),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
        resolvedAt: readDate(m, 'resolvedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'uid': uid,
        'subject': subject,
        'orderId': orderId,
        'productId': productId,
        'topic': topic.code,
        'status': status.code,
        'messages': messages.map((m) => m.toMap()).toList(),
      });
}

/// In-app notification feed. Delivery/email/WhatsApp fan-out happens in Cloud Functions; this
/// row is what the customer sees when they return.
final class AppNotification {
  const AppNotification({
    required this.id,
    required this.uid,
    required this.title,
    required this.body,
    this.kind = NotificationKind.orderUpdate,
    this.entityId = '',
    this.route = '',
    this.isRead = false,
    this.createdAt,
  });

  final String id;
  final String uid;
  final String title;
  final String body;
  final NotificationKind kind;

  /// Order / product / application id the notification points at.
  final String entityId;

  /// Named route the tap handler pushes, e.g. `/account/order/abc`.
  final String route;
  final bool isRead;
  final DateTime? createdAt;

  factory AppNotification.fromMap(Map<String, dynamic> m, {String? id}) => AppNotification(
        id: id ?? readStringOrEmpty(m, 'id'),
        uid: readStringOrEmpty(m, 'uid'),
        title: readStringOrEmpty(m, 'title'),
        body: readStringOrEmpty(m, 'body'),
        kind: notificationKindFromCode(readStringOrEmpty(m, 'kind')),
        entityId: readStringOrEmpty(m, 'entityId'),
        route: readStringOrEmpty(m, 'route'),
        isRead: readBool(m, 'isRead'),
        createdAt: readDate(m, 'createdAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'uid': uid,
        'title': title,
        'body': body,
        'kind': kind.code,
        'entityId': entityId,
        'route': route,
        'isRead': isRead,
      });
}

enum NotificationKind {
  orderPlaced('orderPlaced'),
  orderUpdate('orderUpdate'),
  paymentUpdate('paymentUpdate'),
  backInStock('backInStock'),
  wholesaleDecision('wholesaleDecision'),
  reviewResponse('reviewResponse'),
  promo('promo');

  const NotificationKind(this.code);
  final String code;
}

NotificationKind notificationKindFromCode(String code) => NotificationKind.values
    .firstWhere((k) => k.code == code, orElse: () => NotificationKind.orderUpdate);
