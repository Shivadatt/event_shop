import 'package:get/get.dart';
import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';

/// Append-only audit log reader.
///
/// The log is read-only by design: nothing on this screen can edit or delete an entry. `entityType`
/// and `action` are real server-side filters; an actor or date-range filter needs a repository
/// method that does not exist yet (see [AuditController.filtersActorAndDate]).
final class AuditController extends AdminController with PagedAdminList<AuditLog> {
  AuditController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  static const List<String> knownActions = <String>[
    'product.update',
    'product.archive',
    'pricing.slab_write',
    'pricing.customer_override',
    'stock.adjust',
    'stock.threshold',
    'order.status_change',
    'order.payment_mark',
    'refund.issue',
    'role.change',
    'coupon.save',
    'settings.save',
    'wholesale.decide',
    'review.decide',
    'media.delete',
  ];

  static const List<String> knownEntities = <String>[
    'product',
    'order',
    'pricing',
    'stock',
    'user',
    'role',
    'coupon',
    'settings',
    'wholesale',
    'review',
    'media',
  ];

  final RxnString entityFilter = RxnString();
  final RxnString actionFilter = RxnString();

  /// Documents the filter gap. The Cloud Function only accepts entity + action; actor and a date
  /// window would require paging the whole log client-side, which this panel must not do.
  bool get filtersActorAndDate => false;

  @override
  void onInit() {
    super.onInit();
    loadFirstPage();
  }

  @override
  Future<PagedResult<AuditLog>> fetch({String? cursor}) => _admin.auditLogs(
        entityType: entityFilter.value,
        action: actionFilter.value,
        pageSize: pageSize,
        cursor: cursor,
        // NEEDS OWNER(AdminRepository.auditLogs): add `String? actorUid` and `DateTime? from/to`
        // so actor and date filters run on the server. Until then the UI offers only the entity
        // and action filters that `auditLogs` actually honours.
      );

  void applyEntity(String? value) {
    entityFilter.value = (value == null || value.isEmpty) ? null : value;
    loadFirstPage();
  }

  void applyAction(String? value) {
    actionFilter.value = (value == null || value.isEmpty) ? null : value;
    loadFirstPage();
  }

  void clearFilters() {
    entityFilter.value = null;
    actionFilter.value = null;
    loadFirstPage();
  }

  bool get hasFilters => entityFilter.value != null || actionFilter.value != null;

  String exportLoaded() => OmCsv.build(
        headers: const <String>[
          'createdAt',
          'actorRole',
          'actorUid',
          'action',
          'entityType',
          'entityId',
          'summary',
        ],
        rows: <List<Object?>>[
          for (final entry in rows)
            <Object?>[
              AdminFormat.dateTime(entry.createdAt),
              entry.actorRole,
              entry.actorUid,
              entry.action,
              entry.entityType,
              entry.entityId,
              entry.summary,
            ],
        ],
      );
}
