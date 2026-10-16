import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/catalog/widgets/catalog_results.dart';
import 'package:om_events/features/storefront/catalog/catalog_controller.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';

/// Category listing page (`/category/:slug`). The controller resolves the slug into a
/// `Category` header and a `CatalogQuery`; the shared results grid handles the rest.
final class CategoryView extends GetView<CatalogController> {
  const CategoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Shop',
      body: Obx(() {
        final category = controller.category.value;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const SizedBox(height: OmSpacing.md),
            if (category != null)
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.lg),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OmText(category.name, variant: OmTextVariant.h2),
                    if (category.description.isNotEmpty) ...<Widget>[
                      const SizedBox(height: OmSpacing.sm),
                      OmText(
                        category.description,
                        variant: OmTextVariant.muted,
                        maxLines: 3,
                        overflow: TextOverflow.visible,
                      ),
                    ],
                  ],
                ),
              )
            else
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.lg),
                child: OmText('Shop all products', variant: OmTextVariant.h2),
              ),
            CatalogResults(controller: controller),
            const SizedBox(height: OmSpacing.xl),
          ],
        );
      }),
    );
  }
}
