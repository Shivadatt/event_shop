// Foundation tests: the invariants the five feature agents build on. If one of these breaks,
// every screen that depends on routing, guards or the unconfigured-app state is suspect.
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/routes/app_pages.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/routes/guards.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/main.dart';

SessionStore signIn(UserProfile profile) {
  Get.reset();
  final store = SessionStore(initial: profile);
  Get.put<SessionStore>(store);
  return store;
}

void main() {
  tearDown(Get.reset);

  group('route table', () {
    test('has no duplicate names, so no page silently shadows another', () {
      final names = appPages.map((page) => page.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('keeps the admin area namespaced under /admin', () {
      expect(OmRoutes.isAdmin(OmRoutes.admin), isTrue);
      expect(OmRoutes.isAdmin(OmRoutes.account), isFalse);
    });
  });

  group('route guards', () {
    test('an anonymous visitor is sent to login with the page they wanted', () {
      final redirect = AuthGuard().redirect(OmRoutes.cart);
      expect(redirect?.name, contains(OmRoutes.login));
      expect(Uri.parse(redirect!.name!).queryParameters[OmRouteArgs.returnUrl], OmRoutes.cart);
    });

    test('a signed-in customer reaches their own account page', () {
      signIn(const UserProfile(uid: 'u1'));
      expect(AuthGuard().redirect(OmRoutes.accountOrders), isNull);
    });

    test('a signed-in customer cannot open the admin panel', () {
      signIn(const UserProfile(uid: 'u1'));
      expect(AdminGuard().redirect(OmRoutes.admin)?.name, OmRoutes.notFound);
    });

    test('staff manages the store but cannot reprice it', () {
      signIn(const UserProfile(uid: 'u2', role: UserRole.staff));
      expect(AdminGuard().redirect(OmRoutes.admin), isNull);
      expect(PricingAdminGuard().redirect(OmRoutes.adminPricing)?.name, OmRoutes.notFound);
    });

    test('admin and owner pass the pricing guard', () {
      for (final role in const [UserRole.admin, UserRole.owner]) {
        signIn(UserProfile(uid: 'u3', role: role));
        expect(PricingAdminGuard().redirect(OmRoutes.adminPricing), isNull, reason: '$role');
      }
    });

    test('a blocked account loses admin rights even when its role says otherwise', () {
      signIn(const UserProfile(
        uid: 'u4',
        role: UserRole.admin,
        isBlocked: true,
      ));
      expect(AdminGuard().redirect(OmRoutes.admin)?.name, OmRoutes.home);
      expect(PricingAdminGuard().redirect(OmRoutes.adminPricing)?.name, OmRoutes.notFound);
    });

    test('wholesale tools stay locked until an admin approves the application', () {
      signIn(const UserProfile(uid: 'u5'));
      expect(
        WholesaleGuard().redirect(OmRoutes.wholesaleBulkOrder)?.name,
        OmRoutes.wholesaleApply,
      );

      signIn(const UserProfile(uid: 'u5', wholesaleStatus: WholesaleStatus.approved));
      expect(WholesaleGuard().redirect(OmRoutes.wholesaleBulkOrder), isNull);
    });

    test('a signed-in user is bounced out of the login screen', () {
      signIn(const UserProfile(uid: 'u6'));
      expect(SignedOutOnlyGuard().redirect(OmRoutes.login)?.name, OmRoutes.account);
    });

    test('guards fall back to a safe redirect when the session service is missing', () {
      expect(AuthGuard().redirect(OmRoutes.cart)?.name, contains(OmRoutes.login));
      expect(AdminGuard().redirect(OmRoutes.admin)?.name, contains(OmRoutes.login));
    });
  });

  group('unconfigured build', () {
    testWidgets('shows what is missing instead of a sample catalogue', (tester) async {
      await tester.pumpWidget(
        const OmEventsApp(report: BootstrapReport(firebaseReady: false, supabaseReady: false)),
      );

      expect(find.text('Backend not configured'), findsOneWidget);
      expect(find.textContaining('FIREBASE_API_KEY'), findsOneWidget);
      expect(find.byType(GetMaterialApp), findsNothing);
    });

    testWidgets('refuses to start when a privileged key reached the bundle', (tester) async {
      await tester.pumpWidget(
        const OmEventsApp(
          report: BootstrapReport(
            firebaseReady: false,
            supabaseReady: false,
            failure: 'SUPABASE_SERVICE_ROLE_KEY must not be compiled into the client',
          ),
        ),
      );

      expect(find.textContaining('SUPABASE_SERVICE_ROLE_KEY'), findsWidgets);
    });
  });
}
