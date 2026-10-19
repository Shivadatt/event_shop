/// Live smoke test against the Firebase Local Emulator Suite.
///
/// This is the only check in the suite that proves the app can talk to a real Firestore, a real
/// Auth and a real rules-shaped document set — everything else runs against fakes. It therefore
/// skips unless it is *both* compiled for the web and built with the emulator flag:
///
///   npx firebase-tools@13.35.1 emulators:start --config firebase.local.json \
///       --project demo-om-events --only auth,firestore
///   node scripts/local/seed_local_store.mjs
///   CHROME_EXECUTABLE="C:\\Program Files\\Google\\Chrome\\Application\\chrome.exe" \
///   flutter test --platform chrome --dart-define=OM_USE_EMULATORS=true test/integration/
///
/// Under any other invocation the file contributes nothing: a unit run must not depend on a
/// developer's emulator being up, and a VM run cannot load the web Firestore SDK at all.
library;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/firestore/firestore_admin_repository.dart';
import 'package:om_events/data/repositories/firestore/firestore_auth_repository.dart';
import 'package:om_events/data/repositories/firestore/firestore_catalog_repository.dart';
import 'package:om_events/main.dart' show OmEventsApp;

const bool _live = kIsWeb && Env.useEmulators;
const String _skipReason =
    'needs `--platform chrome --dart-define=OM_USE_EMULATORS=true` plus a running, seeded emulator suite';

/// Everything below is asserted against the documents written by scripts/local/seed_local_store.mjs.
/// Changing the seed means changing these numbers; they are deliberately literals so a silent
/// drift in the seed shows up as a red test rather than a green one that proves nothing.
const String _seededBestSeller = 'Heavy Duty Dinner Plate — Gold Rim (100 pack)';
const int _liveCategoryCount = 4;
const int _activeProductCount = 9;

void main() {
  group('emulator smoke', () {
    test('Firebase initialises against the emulator', () async {
      final report = await AppBootstrap.run();
      expect(report.firebaseReady, isTrue,
          reason: 'bootstrap reported: ${report.failure ?? 'no failure'}');
      expect(AppBootstrap.report.isPartial, isTrue,
          reason: 'Supabase stays down on purpose: media is not part of a local demo');
    });

    test('the seeded catalogue is readable and archived rows stay hidden', () async {
      await AppBootstrap.run();
      final page = await FirestoreProductRepository()
          .search(const CatalogQuery(pageSize: 50));
      expect(page.items, hasLength(_activeProductCount),
          reason: 'the seed writes 9 active products plus 1 draft; got '
              '${page.items.map((p) => p.sku).toList()}');
      expect(page.items.map((p) => p.name), contains(_seededBestSeller));
      expect(page.items.map((p) => p.name), isNot(contains('Retired Paper Lantern (archived)')));
    });

    test('quantity slabs survive the Firestore round trip', () async {
      await AppBootstrap.run();
      final product = await FirestoreProductRepository().bySku('BAL-LTX-11-AS');
      expect(product.retailPricePaise, 45000);
      expect(product.slabs, hasLength(2));
      expect(product.slabs.first.minQty, 5);
      expect(product.slabs.first.unitPricePaise, 42000);
      expect(product.slabs.last.unitPricePaise, 39000);
    });

    test('only live categories reach the storefront rail', () async {
      await AppBootstrap.run();
      final tree = await FirestoreCategoryRepository().tree();
      expect(tree, hasLength(_liveCategoryCount));
      expect(tree.map((c) => c.name), isNot(contains('Archived Range')));
      expect(tree.map((c) => c.slug), containsAll(<String>['balloons', 'tableware']));
    });

    test('store settings load rather than silently falling back', () async {
      await AppBootstrap.run();
      final settings = await FirestoreAdminRepository().settings();
      expect(settings.shopName, 'OM Events And Decorators');
      expect(settings.allowGuestCheckout, isTrue);
      expect(settings.minOrderValuePaise, 50000);
    });

    test('the seeded logins resolve to their documented roles', () async {
      await AppBootstrap.run();
      final auth = FirestoreAuthRepository(SessionStore());
      addTearDown(auth.dispose);

      final buyer = await auth.signIn(email: 'buyer@om-events.test', password: 'emulator-demo');
      expect(buyer.role, UserRole.customer);
      expect(buyer.role.canManageStore, isFalse,
          reason: 'a buyer must not be able to reach the admin area');

      final admin = await auth.signIn(email: 'admin@om-events.test', password: 'emulator-demo');
      expect(admin.role, UserRole.admin);
      expect(admin.role.canEditPricing, isTrue);
    });

    testWidgets('the storefront home renders the seeded catalogue', (tester) async {
      final report = await AppBootstrap.run();
      Get.reset();
      addTearDown(Get.reset);

      await tester.runAsync(() async {
        await tester.pumpWidget(OmEventsApp(report: report));
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        while (find.text(_seededBestSeller).evaluate().isEmpty &&
            DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 200));
          await tester.pump();
        }
      });

      expect(find.text(_seededBestSeller), findsWidgets,
          reason: 'the home shelf never showed a seeded product — the browser could not reach '
              'the emulator, or the shelf query is wrong');
      expect(find.text('Shop by category'), findsWidgets);
    });
  }, skip: _live ? null : _skipReason);
}
