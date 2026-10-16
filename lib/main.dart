import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/bindings/global_binding.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/app/routes/app_pages.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_theme.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final report = await AppBootstrap.run();
  runApp(OmEventsApp(report: report));
}

class OmEventsApp extends StatelessWidget {
  const OmEventsApp({super.key, required this.report});

  final BootstrapReport report;

  static const String appName =
      'OM Events And Decorators – Wholesale & Party Supplies';

  @override
  Widget build(BuildContext context) {
    if (!report.firebaseReady) {
      return MaterialApp(
        title: appName,
        debugShowCheckedModeBanner: false,
        theme: OmTheme.light,
        home: SetupRequiredPage(report: report),
      );
    }

    return GetMaterialApp(
      title: appName,
      debugShowCheckedModeBanner: false,
      theme: OmTheme.light,
      darkTheme: OmTheme.dark,
      // Brand-first: the storefront is black and gold. Data-dense admin surfaces opt into
      // `OmTheme.light` by wrapping their own scaffold, which keeps forms and tables legible
      // without washing the storefront into grey.
      themeMode: ThemeMode.dark,
      initialRoute: OmRoutes.home,
      getPages: appPages,
      unknownRoute: unknownPage,
      defaultTransition: Transition.fadeIn,
      initialBinding: AppRootBinding(),
      builder: (context, child) => MediaQuery.withClampedTextScaling(
        minScaleFactor: 0.9,
        maxScaleFactor: 1.6,
        child: child ?? const SizedBox.shrink(),
      ),
      scrollBehavior: const OmScrollBehavior(),
    );
  }
}

/// Honest state, not a demo: an unconfigured build says exactly which values are missing and how
/// to supply them, instead of rendering placeholder merchandise that looks like a working store.
class SetupRequiredPage extends StatelessWidget {
  const SetupRequiredPage({super.key, required this.report});

  final BootstrapReport report;

  @override
  Widget build(BuildContext context) {
    final text = OmTextStyles.forBrightness(Brightness.light);
    final missing = report.missing.isEmpty ? Env.missingKeys() : report.missing;

    return Scaffold(
      backgroundColor: OmColors.cream,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(OmSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text('OM Events And Decorators', style: text.h1),
                const SizedBox(height: OmSpacing.xs),
                Text('Wholesale & Party Supplies', style: text.label),
                const SizedBox(height: OmSpacing.xl),
                Text('Backend not configured', style: text.h3),
                const SizedBox(height: OmSpacing.md),
                Text(
                  'The store will not start with sample data, because a catalogue that looks '
                  'real but cannot be ordered from is worse than an empty one. Supply the '
                  'values below and rebuild.',
                  style: text.body,
                ),
                const SizedBox(height: OmSpacing.lg),
                _CodeBlock(
                  text: <String>[
                    'fvm flutter run -d chrome \\',
                    ...missing.map((key) => '  --dart-define=$key=<value>'),
                  ].join('\n'),
                  style: text.caption,
                ),
                if (report.failure != null) ...<Widget>[
                  const SizedBox(height: OmSpacing.lg),
                  Text('Last error', style: text.bodyStrong),
                  const SizedBox(height: OmSpacing.sm),
                  _CodeBlock(text: report.failure!, style: text.caption),
                ],
                const SizedBox(height: OmSpacing.lg),
                Text(
                  'Public values only. Never pass SUPABASE_SERVICE_ROLE_KEY or a Firebase '
                  'service account into the client build.',
                  style: text.caption.copyWith(color: OmColors.danger),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CodeBlock extends StatelessWidget {
  const _CodeBlock({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(OmSpacing.md),
        decoration: BoxDecoration(
          color: OmColors.black,
          borderRadius: OmRadius.mdAll,
        ),
        child: SelectableText(
          text,
          style: style.copyWith(color: OmColors.goldSoft, fontFamily: 'monospace'),
        ),
      );
}

/// Keeps a mouse and trackpad able to drag-scroll a desktop page — Flutter's default drag devices
/// are touch-only, so a desktop build otherwise loses wheel-free scrolling inside nested lists.
class OmScrollBehavior extends MaterialScrollBehavior {
  const OmScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const <PointerDeviceKind>{
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
      };
}
