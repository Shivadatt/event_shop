import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/features/admin/admin_routes.dart';
import 'package:om_events/features/storefront/storefront_routes.dart';

/// The merged route table. `storefrontRoutes` and `adminRoutes` are contributed by their owning
/// agents; this file only joins them and pins the app-wide fallbacks, so a duplicate `name` shows
/// up as a single obvious merge point rather than a silent shadow.
List<GetPage<dynamic>> get appPages {
  final pages = <GetPage<dynamic>>[
    ...storefrontRoutes,
    ...adminRoutes,
  ];

  final seen = <String>{};
  final duplicates = <String>[];
  for (final page in pages) {
    if (!seen.add(page.name)) duplicates.add(page.name);
  }
  assert(
    duplicates.isEmpty,
    'Duplicate route names registered: ${duplicates.toSet().join(', ')}',
  );
  return pages;
}

/// Unknown deep links land here. Redirecting them to home would hide a broken or mistyped URL
/// from the buyer and from a crawler alike.
GetPage<dynamic> get unknownPage => GetPage<dynamic>(
      name: OmRoutes.notFound,
      page: () => const OmNotFoundPage(),
    );

class OmNotFoundPage extends StatelessWidget {
  const OmNotFoundPage({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: OmEmptyState(
            icon: Icons.storefront_outlined,
            title: 'Page not found',
            message: 'The link you followed is not part of this store. Older catalogue URLs are '
                'usually one slug away from a live product.',
            actionLabel: 'Back to shop',
            onAction: () => Get.offAllNamed<dynamic>(OmRoutes.home),
          ),
        ),
      );
}
