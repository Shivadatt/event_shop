import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/features/storefront/account/account_data_controller.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/common/store_product_card.dart';

/// `/account/wishlist`. Resolves saved ids into live products through the repository, so an
/// archived item disappears rather than rendering a dead card.
final class WishlistView extends GetView<WishlistController> {
  const WishlistView({super.key});

  @override
  Widget build(BuildContext context) {
    return AccountPage(
      title: 'Wishlist',
      subtitle: 'Saved items keep their current price — a heart never locks in a rate.',
      currentRoute: OmRoutes.accountWishlist,
      body: Obx(() {
        if (controller.loading.value && controller.items.isEmpty) {
          return const OmLoading(message: 'Loading saved items…');
        }
        final failure = controller.failure.value;
        if (failure != null && controller.items.isEmpty) {
          return OmErrorState(failure: failure, onRetry: controller.load);
        }
        if (controller.items.isEmpty) return OmEmptyState.emptyWishlist();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmProductGrid(
              itemCount: controller.items.length,
              itemBuilder: (context, index) {
                final product = controller.items[index];
                return StoreProductCard(
                  product: product,
                  inWishlist: true,
                  onWishlistToggle: () => controller.remove(product),
                );
              },
            ),
            const SizedBox(height: OmSpacing.lg),
            OmButton(
              label: 'Keep browsing',
              variant: OmButtonVariant.ghost,
              size: OmButtonSize.small,
              onPressed: () => Get.offAllNamed<dynamic>(OmRoutes.home),
            ),
          ],
        );
      }),
    );
  }
}
