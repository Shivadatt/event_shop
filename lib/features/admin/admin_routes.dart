import 'package:get/get.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/routes/guards.dart';
import 'package:om_events/features/admin/audit/audit_binding.dart';
import 'package:om_events/features/admin/audit/views/audit_view.dart';
import 'package:om_events/features/admin/categories/categories_binding.dart';
import 'package:om_events/features/admin/categories/categories_view.dart';
import 'package:om_events/features/admin/coupons/coupons_binding.dart';
import 'package:om_events/features/admin/coupons/views/coupons_view.dart';
import 'package:om_events/features/admin/customers/customer_detail_view.dart';
import 'package:om_events/features/admin/customers/customers_binding.dart';
import 'package:om_events/features/admin/customers/customers_view.dart';
import 'package:om_events/features/admin/dashboard/dashboard_binding.dart';
import 'package:om_events/features/admin/dashboard/dashboard_view.dart';
import 'package:om_events/features/admin/inventory/inventory_binding.dart';
import 'package:om_events/features/admin/inventory/views/inventory_view.dart';
import 'package:om_events/features/admin/media/media_binding.dart';
import 'package:om_events/features/admin/media/views/media_view.dart';
import 'package:om_events/features/admin/orders/order_detail_view.dart';
import 'package:om_events/features/admin/orders/orders_binding.dart';
import 'package:om_events/features/admin/orders/orders_view.dart';
import 'package:om_events/features/admin/pricing/pricing_binding.dart';
import 'package:om_events/features/admin/pricing/views/pricing_view.dart';
import 'package:om_events/features/admin/products/product_edit_view.dart';
import 'package:om_events/features/admin/products/products_binding.dart';
import 'package:om_events/features/admin/products/products_view.dart';
import 'package:om_events/features/admin/reports/reports_binding.dart';
import 'package:om_events/features/admin/reports/views/reports_view.dart';
import 'package:om_events/features/admin/reviews/reviews_binding.dart';
import 'package:om_events/features/admin/reviews/views/reviews_view.dart';
import 'package:om_events/features/admin/settings/settings_binding.dart';
import 'package:om_events/features/admin/settings/views/settings_view.dart';
import 'package:om_events/features/admin/wholesale/views/wholesale_view.dart';
import 'package:om_events/features/admin/wholesale/wholesale_binding.dart';

/// The complete admin route table.
///
/// `AdminGuard` sits on every route (a UX convenience and defence-in-depth, never the permission —
/// the functions do that); `PricingAdminGuard` narrows pricing and store settings to the accounts
/// that may edit price/cost. `…/new` is registered before the `…/:id` pattern so a literal `new`
/// segment is never captured as a product id.
List<GetPage<dynamic>> get adminRoutes => <GetPage<dynamic>>[
      GetPage<dynamic>(
        name: OmRoutes.admin,
        page: () => const DashboardView(),
        binding: DashboardBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminProducts,
        page: () => const ProductsView(),
        binding: ProductsBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminProductNew,
        page: () => const ProductEditView(),
        binding: ProductEditBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminProductDetail,
        page: () => const ProductEditView(),
        binding: ProductEditBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminCategories,
        page: () => const CategoriesView(),
        binding: CategoriesBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminOrders,
        page: () => const OrdersView(),
        binding: OrdersBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminOrderDetail,
        page: () => const OrderDetailView(),
        binding: OrderDetailBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminCustomers,
        page: () => const CustomersView(),
        binding: CustomersBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminCustomerDetail,
        page: () => const CustomerDetailView(),
        binding: CustomerDetailBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminInventory,
        page: () => const InventoryView(),
        binding: InventoryBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminPricing,
        page: () => const PricingView(),
        binding: PricingBinding(),
        middlewares: <GetMiddleware>[AdminGuard(), PricingAdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminReviews,
        page: () => const ReviewsView(),
        binding: ReviewsBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminCoupons,
        page: () => const CouponsView(),
        binding: CouponsBinding(),
        // Coupon definitions are pricing-admin data: rules deny a staff read outright, and a bare
        // collection query would surface as a permission error rather than a clean role boundary.
        middlewares: <GetMiddleware>[AdminGuard(), PricingAdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminWholesale,
        page: () => const WholesaleView(),
        binding: WholesaleBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminSettings,
        page: () => const SettingsView(),
        binding: SettingsBinding(),
        // Settings carries the tax rate and payment toggles, so it shares the pricing role gate.
        middlewares: <GetMiddleware>[AdminGuard(), PricingAdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminReports,
        page: () => const ReportsView(),
        binding: ReportsBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminAudit,
        page: () => const AuditView(),
        binding: AuditBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
      GetPage<dynamic>(
        name: OmRoutes.adminMedia,
        page: () => const MediaView(),
        binding: MediaBinding(),
        middlewares: <GetMiddleware>[AdminGuard()],
      ),
    ];
