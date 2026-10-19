// Behaviour of FakeAdminRepository — the privileged admin surface used by admin widget tests.
//
// These tests exist because a fake that only satisfies an interface is worthless to the suite: if
// `saveCategory`/`deleteCategory` silently succeed or silently return empty lists, no admin test can
// tell "the screen refreshed the tree" from "the fake lied". So this file pins the store semantics
// (rows actually move), the refusal paths (`ConflictFailure` on a non-empty category,
// `NotFoundFailure` on an unknown id), the recorded calls, and the failure-injection flags.
import 'package:flutter_test/flutter_test.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/audit_log.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/models/wholesale.dart';
import '../support/om_fakes.dart';

Order _order(
  String id, {
  required String uid,
  required int paise,
  required DateTime at,
  int qty = 1,
  OrderStatus status = OrderStatus.delivered,
  DeliveryMode? deliveryMode,
}) =>
    Order(
      id: id,
      orderNumber: 'OME-$id',
      userId: uid,
      status: status,
      createdAt: at,
      items: <OrderItem>[
        OrderItem(
          productId: 'p-$id',
          name: 'Balloon pack',
          qty: qty,
          unitPricePaise: paise ~/ qty,
          lineTotalPaise: paise,
        ),
      ],
      totals: OrderTotals(subtotalPaise: paise, grandTotalPaise: paise),
      // `??` rather than an omitted argument: the courier default is only applied when the test
      // did not care about the delivery mode, so the filter assertions stay meaningful.
      deliveryMode: deliveryMode ?? DeliveryMode.courier,
    );

void main() {
  group('category write path', () {
    test('saving then deleting a category leaves the expected rows', () async {
      final repo = FakeAdminRepository(categories: const <Category>[
        Category(id: 'root', name: 'Balloons', slug: 'balloons'),
      ]);

      await repo.saveCategory(const Category(
        id: 'sub-1',
        name: 'Latex',
        slug: 'latex',
        parentId: 'root',
      ));
      expect(repo.categories.map((c) => c.id), containsAll(<String>['root', 'sub-1']));

      await repo.deleteCategory('sub-1');

      expect(repo.categories.map((c) => c.id), <String>['root']);
      expect(repo.deletedCategoryIds, <String>['sub-1']);
      expect(
        repo.calls,
        <String>['saveCategory:sub-1', 'deleteCategory:sub-1'],
        reason: 'the fake must record the privileged calls in the order the screen made them',
      );
    });

    test('a save with an existing id replaces that row instead of duplicating it', () async {
      final repo = FakeAdminRepository(categories: const <Category>[
        Category(id: 'root', name: 'Balloons', slug: 'balloons', order: 1),
      ]);

      await repo.saveCategory(const Category(
        id: 'root',
        name: 'Balloons & Arches',
        slug: 'balloons',
        order: 4,
      ));

      expect(repo.categories.length, 1);
      expect(repo.categories.single.name, 'Balloons & Arches');
      expect(repo.categories.single.order, 4);
      expect(repo.savedCategoryPayloads.single.order, 4);
    });

    test('delete is refused while a live product still references the category', () async {
      final repo = FakeAdminRepository(
        categories: const <Category>[Category(id: 'root', name: 'Balloons')],
        products: const <Product>[
          Product(id: 'p1', name: 'Latex pack', categoryId: 'root'),
          Product(id: 'p2', name: 'Retired arch', categoryId: 'root', status: ProductStatus.archived),
        ],
      );

      await expectLater(
        repo.deleteCategory('root'),
        throwsA(isA<ConflictFailure>()),
        reason: 'one live product is enough — the archived one must not count',
      );
      expect(repo.categories, hasLength(1), reason: 'a refused delete must not remove the row');
      expect(repo.deletedCategoryIds, <String>['root'], reason: 'the attempt is still recorded');
    });

    test('delete is refused while the category has children', () async {
      final repo = FakeAdminRepository(categories: const <Category>[
        Category(id: 'root', name: 'Balloons'),
        Category(id: 'child', name: 'Latex', parentId: 'root'),
      ]);

      await expectLater(repo.deleteCategory('root'), throwsA(isA<ConflictFailure>()));
      expect(repo.categories, hasLength(2));

      await repo.deleteCategory('child');
      await repo.deleteCategory('root');
      expect(repo.categories, isEmpty);
    });

    test('an unknown category id is a miss, not a silent success', () async {
      final repo = FakeAdminRepository();
      await expectLater(repo.deleteCategory('nope'), throwsA(isA<NotFoundFailure>()));
    });

    test('an empty name is rejected rather than written', () async {
      final repo = FakeAdminRepository();
      await expectLater(
        repo.saveCategory(const Category(id: 'blank', name: '   ')),
        throwsA(isA<ValidationFailure>()),
      );
      expect(repo.categories, isEmpty);
    });

    test('the write-failure flag makes the save throw and leaves the store untouched', () async {
      final repo = FakeAdminRepository(categories: const <Category>[
        Category(id: 'root', name: 'Balloons'),
      ])..failCategoryWrites = true;

      await expectLater(
        repo.saveCategory(const Category(id: 'sub', name: 'Latex', parentId: 'root')),
        throwsA(isA<ServerFailure>()),
      );
      expect(repo.categories.map((c) => c.id), <String>['root']);
      expect(repo.savedCategoryPayloads, hasLength(1), reason: 'the attempt is still recorded');

      repo.failCategoryWrites = false;
      repo.failCategoryDeletes = true;
      await expectLater(repo.deleteCategory('root'), throwsA(isA<ServerFailure>()));
      expect(repo.categories, hasLength(1));
    });

    test('a method this fake does not back fails loudly instead of returning empty data', () {
      final repo = FakeAdminRepository();
      expect(
        repo.dashboard,
        throwsA(isA<UnimplementedError>()),
        reason: 'noSuchMethod throws on the call, so an un-faked privileged read can never be '
            'mistaken for an empty one',
      );
    });
  });

  group('server-summed reports', () {
    final orders = <Order>[
      _order('a', uid: 'u1', paise: 50000, at: DateTime.utc(2026, 10, 1, 9), qty: 2),
      _order('b', uid: 'u1', paise: 25000, at: DateTime.utc(2026, 10, 1, 23)),
      _order('c', uid: 'u2', paise: 90000, at: DateTime.utc(2026, 10, 3, 12), qty: 3),
      _order(
        'd',
        uid: 'u2',
        paise: 10000,
        at: DateTime.utc(2026, 10, 3, 18),
        status: OrderStatus.cancelled,
      ),
    ];

    test('salesByDay sums per UTC day inside the window and skips cancelled orders', () async {
      final repo = FakeAdminRepository(orders: orders);
      final rows = await repo.salesByDay(
        from: DateTime.utc(2026, 10),
        to: DateTime.utc(2026, 10, 2, 23, 59),
      );

      expect(rows.map((r) => r.key), <String>['2026-10-01']);
      expect(rows.single.revenuePaise, 75000);
      expect(rows.single.units, 3);
      expect(rows.single.hasCostData, isFalse, reason: 'the fake has no cost ledger to invent');
      expect(repo.salesByDayRequests.single.from, DateTime.utc(2026, 10));
    });

    test('topCustomers ranks by lifetime revenue and honours the limit', () async {
      final repo = FakeAdminRepository(orders: orders);
      final all = await repo.topCustomers();
      expect(all.map((r) => r.key), <String>['u2', 'u1']);
      expect(all.first.revenuePaise, 90000, reason: 'the cancelled order must not count');

      final one = await repo.topCustomers(limit: 1);
      expect(one.map((r) => r.key), <String>['u2']);
      expect(repo.topCustomerLimits, <int>[20, 1]);
    });

    test('customerValue sums one customer and reports an unknown uid as a miss', () async {
      final repo = FakeAdminRepository(orders: orders);
      final row = await repo.customerValue('u1');
      expect(row.revenuePaise, 75000);
      expect(row.units, 3);
      expect(row.orderCount, 2, reason: 'orders and units are different claims; the customer '
          'panel prints both, and the server used to answer the count question with a paise field');
      expect(row.refundedPaise, 0, reason: 'nothing in this fixture was refunded');
      expect(repo.customerValueRequests, <String>['u1']);

      await expectLater(repo.customerValue('ghost'), throwsA(isA<NotFoundFailure>()));
    });

    test('the report-failure flag breaks all three report reads', () async {
      final repo = FakeAdminRepository(orders: orders)..failReportReads = true;
      final window = (from: DateTime.utc(2026, 10), to: DateTime.utc(2026, 10, 5));
      await expectLater(
        repo.salesByDay(from: window.from, to: window.to),
        throwsA(isA<ServerFailure>()),
      );
      await expectLater(repo.topCustomers(), throwsA(isA<ServerFailure>()));
      await expectLater(repo.customerValue('u1'), throwsA(isA<ServerFailure>()));
    });
  });

  group('listOrders filters', () {
    final orders = <Order>[
      _order('a', uid: 'u1', paise: 100, at: DateTime.utc(2026, 10)),
      _order(
        'b',
        uid: 'u1',
        paise: 200,
        at: DateTime.utc(2026, 10, 2),
        deliveryMode: DeliveryMode.pickup,
      ),
      _order(
        'c',
        uid: 'u2',
        paise: 300,
        at: DateTime.utc(2026, 10, 3),
        status: OrderStatus.placed,
      ),
    ];

    test('the round-2 deliveryMode and customerId filters narrow the page and are recorded',
        () async {
      final repo = FakeAdminRepository(orders: orders);

      final byMode = await repo.listOrders(deliveryMode: DeliveryMode.pickup);
      expect(byMode.items.map((o) => o.id), <String>['b']);
      final byCustomer = await repo.listOrders(customerId: 'u1');
      expect(byCustomer.items.map((o) => o.id), <String>['a', 'b']);
      final combined = await repo.listOrders(
        customerId: 'u1',
        status: OrderStatus.delivered,
        deliveryMode: DeliveryMode.courier,
      );
      expect(combined.items.map((o) => o.id), <String>['a']);

      expect(repo.listOrdersRequests.map((r) => r.deliveryMode), <DeliveryMode?>[
        DeliveryMode.pickup,
        null,
        DeliveryMode.courier,
      ]);
      expect(repo.listOrdersRequests.last.customerId, 'u1');
    });

    test('paging still hands back an opaque cursor over the filtered rows', () async {
      final repo = FakeAdminRepository(orders: orders);
      final first = await repo.listOrders(pageSize: 2);
      expect(first.items.map((o) => o.id), <String>['a', 'b']);
      expect(first.nextCursor, '2');
      final second = await repo.listOrders(pageSize: 2, cursor: first.nextCursor);
      expect(second.items.map((o) => o.id), <String>['c']);
      expect(second.nextCursor, isNull);
    });

    test('the order-list failure flag is injectable', () async {
      final repo = FakeAdminRepository(orders: orders)..failOrderList = true;
      await expectLater(repo.listOrders(), throwsA(isA<NetworkFailure>()));
    });
  });

  group('auditLogs filters', () {
    final logs = <AuditLog>[
      AuditLog(
        id: 'l1',
        action: 'category.delete',
        entityType: 'category',
        entityId: 'c1',
        actorUid: 'admin1',
        createdAt: DateTime.utc(2026, 10, 1, 8),
      ),
      AuditLog(
        id: 'l2',
        action: 'role.change',
        entityType: 'user',
        entityId: 'u1',
        actorUid: 'owner1',
        createdAt: DateTime.utc(2026, 10, 5, 8),
      ),
    ];

    test('actorUid, from and to all filter, and each request is recorded', () async {
      final repo = FakeAdminRepository(logs: logs);

      expect((await repo.auditLogs(actorUid: 'admin1')).items.map((l) => l.id), <String>['l1']);
      expect((await repo.auditLogs(entityType: 'user')).items.map((l) => l.id), <String>['l2']);
      expect(
        (await repo.auditLogs(
          from: DateTime.utc(2026, 10, 2),
          to: DateTime.utc(2026, 10, 6),
        ))
            .items
            .map((l) => l.id),
        <String>['l2'],
      );

      final last = repo.auditLogRequests.last;
      expect(last.from, DateTime.utc(2026, 10, 2));
      expect(last.to, DateTime.utc(2026, 10, 6));
      expect(repo.auditLogRequests.first.actorUid, 'admin1');
    });

    test('the audit-read failure flag is injectable', () async {
      final repo = FakeAdminRepository(logs: logs)..failAuditReads = true;
      await expectLater(repo.auditLogs(), throwsA(isA<PermissionFailure>()));
    });
  });

  group('contract-price reads', () {
    const overrides = <CustomerPriceOverride>[
      CustomerPriceOverride(id: 'o1', uid: 'u1', productId: 'p1', unitPricePaise: 9000),
      CustomerPriceOverride(id: 'o2', uid: 'u2', productId: 'p1', unitPricePaise: 8000),
      CustomerPriceOverride(id: 'o3', uid: 'u1', productId: 'p2', unitPricePaise: 7000),
    ];

    test('productId and uid filter the list and are recorded as asked', () async {
      final repo = FakeAdminRepository(overrides: overrides);

      expect((await repo.listCustomerPrices(productId: 'p1')).map((o) => o.id), <String>[
        'o1',
        'o2',
      ]);
      expect((await repo.listCustomerPrices(uid: 'u1')).map((o) => o.id), <String>['o1', 'o3']);
      expect((await repo.listCustomerPrices(productId: 'p2', uid: 'u1')).map((o) => o.id),
          <String>['o3']);
      expect((await repo.listCustomerPrices()).map((o) => o.id), <String>['o1', 'o2', 'o3']);

      expect(repo.customerPriceRequests.first.productId, 'p1');
      expect(repo.customerPriceRequests.last.productId, isNull);
      expect(repo.customerPriceRequests.last.uid, isNull);
    });

    test('the rules-forbidden read is injectable so the denied UI is testable', () async {
      final repo = FakeAdminRepository(overrides: overrides)..failCustomerPriceReads = true;
      await expectLater(repo.listCustomerPrices(), throwsA(isA<PermissionFailure>()));
    });
  });
}
