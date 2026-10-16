import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/routes/app_routes.dart';

/// Placeholder route list. Agent 1 replaces the body of `storefrontRoutes` with the real
/// customer pages; the exported name and the `List<GetPage<dynamic>>` return type are part of the
/// integration contract and must not change.
List<GetPage<dynamic>> get storefrontRoutes => <GetPage<dynamic>>[
      GetPage<dynamic>(
        name: OmRoutes.notFound,
        page: () => const Scaffold(
          body: Center(child: Text('Storefront routes pending')),
        ),
      ),
    ];
