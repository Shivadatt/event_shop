import 'package:get/get.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/routes/guards.dart';
import 'package:om_events/features/storefront/account/account_binding.dart';
import 'package:om_events/features/storefront/account/views/account_home_view.dart';
import 'package:om_events/features/storefront/account/views/addresses_view.dart';
import 'package:om_events/features/storefront/account/views/notifications_view.dart';
import 'package:om_events/features/storefront/account/views/order_detail_view.dart';
import 'package:om_events/features/storefront/account/views/order_success_view.dart';
import 'package:om_events/features/storefront/account/views/orders_view.dart';
import 'package:om_events/features/storefront/account/views/profile_view.dart';
import 'package:om_events/features/storefront/account/views/settings_view.dart';
import 'package:om_events/features/storefront/account/views/support_view.dart';
import 'package:om_events/features/storefront/account/views/wishlist_view.dart';
import 'package:om_events/features/storefront/auth/auth_binding.dart';
import 'package:om_events/features/storefront/auth/views/forgot_password_view.dart';
import 'package:om_events/features/storefront/auth/views/login_view.dart';
import 'package:om_events/features/storefront/auth/views/register_view.dart';
import 'package:om_events/features/storefront/auth/views/reset_password_view.dart';
import 'package:om_events/features/storefront/cart/cart_binding.dart';
import 'package:om_events/features/storefront/cart/views/cart_view.dart';
import 'package:om_events/features/storefront/catalog/catalog_binding.dart';
import 'package:om_events/features/storefront/catalog/views/category_view.dart';
import 'package:om_events/features/storefront/checkout/checkout_binding.dart';
import 'package:om_events/features/storefront/checkout/checkout_guard.dart';
import 'package:om_events/features/storefront/checkout/views/checkout_view.dart';
import 'package:om_events/features/storefront/common/storefront_binding.dart';
import 'package:om_events/features/storefront/common/storefront_route_names.dart';
import 'package:om_events/features/storefront/home/home_binding.dart';
import 'package:om_events/features/storefront/home/views/home_view.dart';
import 'package:om_events/features/storefront/product_details/product_details_binding.dart';
import 'package:om_events/features/storefront/product_details/views/product_details_view.dart';
import 'package:om_events/features/storefront/reviews/review_binding.dart';
import 'package:om_events/features/storefront/reviews/views/review_compose_view.dart';
import 'package:om_events/features/storefront/search/search_binding.dart';
import 'package:om_events/features/storefront/search/views/search_view.dart';
import 'package:om_events/features/storefront/static/views/about_view.dart';
import 'package:om_events/features/storefront/static/views/contact_view.dart';
import 'package:om_events/features/storefront/static/views/faq_view.dart';
import 'package:om_events/features/storefront/static/views/policy_view.dart';
import 'package:om_events/features/storefront/wholesale/views/apply_view.dart';
import 'package:om_events/features/storefront/wholesale/views/bulk_order_view.dart';
import 'package:om_events/features/storefront/wholesale/views/quotation_view.dart';
import 'package:om_events/features/storefront/wholesale/wholesale_binding.dart';

/// The customer storefront's route table.
///
/// `OmRoutes.notFound` is deliberately absent: `app_pages.unknownPage` owns that name and a second
/// registration trips the duplicate assertion in `app_pages.dart`.
///
/// Guards are UX and defence-in-depth only — Firestore rules and Cloud Functions re-check the
/// buyer, the wholesale status and every amount on each call.
List<GetPage<dynamic>> get storefrontRoutes => <GetPage<dynamic>>[
      // Browsing.
      GetPage<dynamic>(
        name: OmRoutes.home,
        page: () => const HomeView(),
        bindings: <Bindings>[StorefrontBinding(), HomeBinding()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.category,
        page: () => const CategoryView(),
        bindings: <Bindings>[StorefrontBinding(), CatalogBinding()],
      ),
      GetPage<dynamic>(
        name: '${OmRoutes.category}/:slug',
        page: () => const CategoryView(),
        bindings: <Bindings>[StorefrontBinding(), CatalogBinding()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.product,
        page: () => const ProductDetailsView(),
        bindings: <Bindings>[StorefrontBinding(), ProductDetailsBinding()],
      ),
      GetPage<dynamic>(
        name: '${OmRoutes.product}/:idOrSlug',
        page: () => const ProductDetailsView(),
        bindings: <Bindings>[StorefrontBinding(), ProductDetailsBinding()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.search,
        page: () => const SearchView(),
        bindings: <Bindings>[StorefrontBinding(), SearchBinding()],
      ),

      // Buying. The cart stays open to visitors. `/checkout` does not take the blanket `AuthGuard`:
      // guest checkout is a store setting (`StoreSettings.allowGuestCheckout`), and a guard that
      // bounced every visitor to login made it unreachable. `CheckoutGuard` keeps that exact
      // bounce when the setting says "off" (or the session is blocked) and otherwise lets the
      // flow's own `guestAllowed`/`guestGate` checks decide — see the note on the route below.
      GetPage<dynamic>(
        name: OmRoutes.cart,
        page: () => const CartView(),
        bindings: <Bindings>[StorefrontBinding(), CartBinding()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.checkout,
        page: () => const CheckoutView(),
        bindings: <Bindings>[StorefrontBinding(), CheckoutBinding()],
        middlewares: <GetMiddleware>[CheckoutGuard()],
      ),
      GetPage<dynamic>(
        name: '${OmRoutes.orderSuccess}/:orderId',
        page: () => const OrderSuccessView(),
        bindings: <Bindings>[StorefrontBinding(), OrderSuccessBinding()],
      ),

      // Auth. `return` and `from=admin` query args are emitted by the guards and read by the
      // controllers; a signed-in buyer is bounced off these two screens.
      GetPage<dynamic>(
        name: OmRoutes.login,
        page: () => const LoginView(),
        bindings: <Bindings>[StorefrontBinding(), LoginBinding()],
        middlewares: <GetMiddleware>[SignedOutOnlyGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.register,
        page: () => const RegisterView(),
        bindings: <Bindings>[StorefrontBinding(), RegisterBinding()],
        middlewares: <GetMiddleware>[SignedOutOnlyGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.forgotPassword,
        page: () => const ForgotPasswordView(),
        bindings: <Bindings>[StorefrontBinding(), ForgotPasswordBinding()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.resetPassword,
        page: () => const ResetPasswordView(),
        bindings: <Bindings>[StorefrontBinding(), ResetPasswordBinding()],
      ),

      // My account.
      GetPage<dynamic>(
        name: OmRoutes.account,
        page: () => const AccountHomeView(),
        bindings: <Bindings>[StorefrontBinding(), AccountHomeBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: StorefrontRouteNames.accountProfile,
        page: () => const ProfileView(),
        bindings: <Bindings>[StorefrontBinding(), ProfileBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.accountOrders,
        page: () => const OrdersView(),
        bindings: <Bindings>[StorefrontBinding(), OrderListBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: '${OmRoutes.accountOrder}/:orderId',
        page: () => const AccountOrderView(),
        bindings: <Bindings>[StorefrontBinding(), AccountOrderBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.accountAddresses,
        page: () => const AddressesView(),
        bindings: <Bindings>[StorefrontBinding(), AddressBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.accountWishlist,
        page: () => const WishlistView(),
        bindings: <Bindings>[StorefrontBinding(), WishlistBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.accountNotifications,
        page: () => const NotificationsView(),
        bindings: <Bindings>[StorefrontBinding(), NotificationBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.accountSupport,
        page: () => const SupportView(),
        bindings: <Bindings>[StorefrontBinding(), SupportBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.accountSettings,
        page: () => const AccountSettingsView(),
        bindings: <Bindings>[StorefrontBinding(), AccountSettingsBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),

      // Reviews. Only the buyer's own review for one product; the verified-purchase flag is the
      // Cloud Function's answer, never this page's claim.
      GetPage<dynamic>(
        name: '${OmRoutes.reviewCompose}/:productId',
        page: () => const ReviewComposeView(),
        bindings: <Bindings>[StorefrontBinding(), ReviewComposeBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),

      // Wholesale. `wholesaleApply` takes `AuthGuard`, not `WholesaleGuard`: that guard sends every
      // non-approved account to this exact page, so guarding it would redirect it onto itself.
      GetPage<dynamic>(
        name: OmRoutes.wholesaleApply,
        page: () => const WholesaleApplyView(),
        bindings: <Bindings>[StorefrontBinding(), WholesaleApplyBinding()],
        middlewares: <GetMiddleware>[AuthGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.wholesaleBulkOrder,
        page: () => const BulkOrderView(),
        bindings: <Bindings>[StorefrontBinding(), BulkOrderBinding()],
        middlewares: <GetMiddleware>[WholesaleGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.wholesaleQuotation,
        page: () => const WholesaleQuotationView(),
        bindings: <Bindings>[StorefrontBinding(), WholesaleQuotationBinding()],
        middlewares: <GetMiddleware>[WholesaleGuard()],
      ),

      // Editorial pages. No page controller: the copy comes from `SettingsStore`, which reports an
      // honest failure while the settings repository is unbound.
      GetPage<dynamic>(
        name: OmRoutes.about,
        page: () => const AboutView(),
        bindings: <Bindings>[StorefrontBinding()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.contact,
        page: () => const ContactView(),
        bindings: <Bindings>[StorefrontBinding()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.faq,
        page: () => const FaqView(),
        bindings: <Bindings>[StorefrontBinding()],
      ),
      GetPage<dynamic>(
        name: '${OmRoutes.policy}/:kind',
        page: () => const PolicyView(),
        bindings: <Bindings>[StorefrontBinding()],
      ),
    ];
