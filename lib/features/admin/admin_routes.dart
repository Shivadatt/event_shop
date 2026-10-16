import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/routes/app_routes.dart';

/// Placeholder route list. Agent 2 replaces the body of `adminRoutes` with the real admin pages;
/// the exported name and return type are part of the integration contract.
List<GetPage<dynamic>> get adminRoutes => <GetPage<dynamic>>[
      GetPage<dynamic>(
        name: OmRoutes.admin,
        page: () => const Scaffold(
          body: Center(child: Text('Admin routes pending')),
        ),
        middlewares: <GetMiddleware>[AdminAreaPlaceholderGuard()],
      ),
    ];

/// Stands in for Agent 2's real guard registration until the admin panel lands.
class AdminAreaPlaceholderGuard extends GetMiddleware {}
