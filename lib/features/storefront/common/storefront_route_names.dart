import 'package:om_events/app/routes/app_routes.dart';

/// NEEDS OWNER: `OmRoutes` (app/routes/app_routes.dart) has no constant for the profile editor, and
/// screens must not carry literal paths. It is composed from `OmRoutes.account` here so the route
/// table and the link share one definition.
/// Promote to `static const String accountProfile = '/account/profile';` in `OmRoutes` and delete
/// this file.
abstract final class StorefrontRouteNames {
  static const String accountProfile = '${OmRoutes.account}/profile';
}
