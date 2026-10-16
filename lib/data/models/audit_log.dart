import 'package:om_events/data/om_doc.dart';

/// Every sensitive mutation lands here: price, stock, role, order status, refund. The log is
/// append-only and admin reads are the only consumer, so it is separate from public documents.
final class AuditLog {
  const AuditLog({
    required this.id,
    required this.action,
    required this.entityType,
    required this.entityId,
    this.actorUid = '',
    this.actorRole = '',
    this.summary = '',
    this.before = const <String, Object?>{},
    this.after = const <String, Object?>{},
    this.createdAt,
  });

  final String id;

  /// Stable verb strings: `product.update`, `pricing.slab_write`, `stock.adjust`,
  /// `order.status_change`, `role.change`, `refund.issue`.
  final String action;
  final String entityType;
  final String entityId;
  final String actorUid;
  final String actorRole;
  final String summary;
  final Map<String, Object?> before;
  final Map<String, Object?> after;
  final DateTime? createdAt;

  factory AuditLog.fromMap(Map<String, dynamic> m, {String? id}) => AuditLog(
        id: id ?? readStringOrEmpty(m, 'id'),
        action: readStringOrEmpty(m, 'action'),
        entityType: readStringOrEmpty(m, 'entityType'),
        entityId: readStringOrEmpty(m, 'entityId'),
        actorUid: readStringOrEmpty(m, 'actorUid'),
        actorRole: readStringOrEmpty(m, 'actorRole'),
        summary: readStringOrEmpty(m, 'summary'),
        before: readMap(m, 'before'),
        after: readMap(m, 'after'),
        createdAt: readDate(m, 'createdAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'action': action,
        'entityType': entityType,
        'entityId': entityId,
        'actorUid': actorUid,
        'actorRole': actorRole,
        'summary': summary,
        'before': before,
        'after': after,
      });
}
