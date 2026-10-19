import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/services/session_store.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/features/storefront/account/widgets/account_page.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/wholesale/wholesale_controller.dart';

/// `/wholesale/apply`. The form records an application; approval is the store's decision and is
/// only ever read back from the session profile.
final class WholesaleApplyView extends GetView<WholesaleApplyController> {
  const WholesaleApplyView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Wholesale account',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const OmSectionHeader(
              title: 'Open a trade account',
              subtitle:
                  'Verified trade buyers get carton (slab) pricing, the bulk-order grid and '
                  'quotation requests. Send your business details and the store team reviews them.',
            ),
            const SizedBox(height: OmSpacing.lg),
            const _StatusPanel(),
            const SizedBox(height: OmSpacing.lg),
            Obx(() {
              if (controller.done.value) return const _AppliedCard();
              return _ApplyForm(controller: controller);
            }),
            const SizedBox(height: OmSpacing.xl),
          ],
        ),
      ),
    );
  }
}

/// Reads the session mirror, never a form field, so the page cannot paint itself approved.
class _StatusPanel extends StatelessWidget {
  const _StatusPanel();

  @override
  Widget build(BuildContext context) => Obx(() {
        final profile = Get.find<SessionStore>().changes.value;
        if (profile == null) {
          return OmCard(
            borderColor: OmColors.info,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const OmText(
                  'You are not signed in, so this form cannot be attached to an account yet.',
                  variant: OmTextVariant.caption,
                  overflow: TextOverflow.visible,
                ),
                const SizedBox(height: OmSpacing.md),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  children: <Widget>[
                    OmButton(
                      label: 'Sign in',
                      size: OmButtonSize.small,
                      onPressed: () => Get.toNamed<dynamic>(OmRoutes.login),
                    ),
                    OmButton(
                      label: 'Create an account',
                      variant: OmButtonVariant.secondary,
                      size: OmButtonSize.small,
                      onPressed: () => Get.toNamed<dynamic>(OmRoutes.register),
                    ),
                  ],
                ),
              ],
            ),
          );
        }

        final status = profile.wholesaleStatus;
        return OmCard(
          borderColor: switch (status) {
            WholesaleStatus.approved => OmColors.success,
            WholesaleStatus.rejected => OmColors.danger,
            WholesaleStatus.pending => OmColors.warning,
            WholesaleStatus.none => null,
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(child: WholesaleStatusBadge(status: status)),
                  OmText(
                    profile.companyName.isEmpty ? profile.email : profile.companyName,
                    variant: OmTextVariant.caption,
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.md),
              OmText(
                switch (status) {
                  WholesaleStatus.approved =>
                    'Approved. Carton pricing now shows on every product page and the trade tools '
                        'below are unlocked.',
                  WholesaleStatus.pending =>
                    'Your application is with the store team. You will be notified here and by '
                        'email when it is decided; nothing is chargeable until then.',
                  WholesaleStatus.rejected =>
                    'The store team declined this application. Update the details below and '
                        'resubmit, or use the support desk to ask what is missing.',
                  WholesaleStatus.none =>
                    'No application on file yet. Fill the form below to open a trade account.',
                },
                variant: OmTextVariant.muted,
                overflow: TextOverflow.visible,
              ),
              if (status == WholesaleStatus.approved) ...<Widget>[
                const SizedBox(height: OmSpacing.md),
                Wrap(
                  spacing: OmSpacing.sm,
                  runSpacing: OmSpacing.sm,
                  children: <Widget>[
                    OmButton(
                      label: 'Bulk order',
                      icon: Icons.grid_on_rounded,
                      size: OmButtonSize.small,
                      onPressed: () => Get.toNamed<dynamic>(OmRoutes.wholesaleBulkOrder),
                    ),
                    OmButton(
                      label: 'Request a quotation',
                      variant: OmButtonVariant.secondary,
                      size: OmButtonSize.small,
                      onPressed: () => Get.toNamed<dynamic>(OmRoutes.wholesaleQuotation),
                    ),
                  ],
                ),
              ],
              if (status == WholesaleStatus.rejected) ...<Widget>[
                const SizedBox(height: OmSpacing.md),
                OmButton(
                  label: 'Ask the support desk',
                  variant: OmButtonVariant.secondary,
                  size: OmButtonSize.small,
                  onPressed: () => Get.toNamed<dynamic>(OmRoutes.accountSupport),
                ),
              ],
            ],
          ),
        );
      });
}

class _ApplyForm extends StatelessWidget {
  const _ApplyForm({required this.controller});

  final WholesaleApplyController controller;

  @override
  Widget build(BuildContext context) => Obx(() {
    final profile = Get.find<SessionStore>().changes.value;
    final failure = controller.failure.value;
    final busy = controller.busy.value;
    final isFirstApplication =
        (profile?.wholesaleStatus ?? WholesaleStatus.none) == WholesaleStatus.none;
    return OmCard(
      elevated: true,
      child: Form(
        key: controller.formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const OmSectionHeader(
              title: 'Business details',
              subtitle: 'Only what the store needs to verify you and issue a trade invoice.',
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'Company / firm name',
              controller: controller.companyName,
              required: true,
              validator: controller.validateCompany,
              autofillHints: const <String>[AutofillHints.organizationName],
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'Contact person',
              controller: controller.contactName,
              required: true,
              validator: controller.validateContact,
              autofillHints: const <String>[AutofillHints.name],
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'Phone',
              controller: controller.phone,
              required: true,
              keyboardType: TextInputType.phone,
              validator: controller.validatePhone,
              helper: 'The store calls this number to verify the business.',
              autofillHints: const <String>[AutofillHints.telephoneNumber],
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'GSTIN (optional)',
              controller: controller.gstNumber,
              hint: '07ABCDE1234F1Z5',
              helper: 'Needed for tax invoices; leave blank if you do not have one yet.',
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'Business address (optional)',
              controller: controller.address,
              maxLines: 3,
              minLines: 2,
              keyboardType: TextInputType.streetAddress,
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'Expected monthly volume (optional)',
              controller: controller.expectedMonthlyVolume,
              hint: 'e.g. 20 cartons of balloons, 5 backdrops',
            ),
            const SizedBox(height: OmSpacing.md),
            OmTextField(
              label: 'What do you stock? (optional)',
              controller: controller.reason,
              maxLines: 4,
              minLines: 2,
              counterText: '',
            ),
            const SizedBox(height: OmSpacing.lg),
            OmButton(
              label: isFirstApplication ? 'Submit application' : 'Update and resubmit',
              icon: Icons.verified_user_outlined,
              loading: busy,
              busyLabel: 'Sending…',
              expanded: context.isCompactLayout,
              onPressed: controller.submit,
            ),
            if (failure != null) ...<Widget>[
              const SizedBox(height: OmSpacing.md),
              OmCard(
                borderColor: OmColors.danger,
                padding: const EdgeInsets.all(OmSpacing.sm),
                child: OmText(failure.message,
                    variant: OmTextVariant.caption, overflow: TextOverflow.visible),
              ),
            ],
            const SizedBox(height: OmSpacing.md),
            const OmText(
              'Submitting an application does not reserve stock or fix a price. Trade pricing, '
              'availability and the payable total are confirmed by the store and by the server '
              'when an order is placed.',
              variant: OmTextVariant.caption,
              overflow: TextOverflow.visible,
            ),
          ],
        ),
      ),
    );
      });
}

class _AppliedCard extends StatelessWidget {
  const _AppliedCard();

  @override
  Widget build(BuildContext context) => OmCard(
        elevated: true,
        borderColor: OmColors.success,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const OmSectionHeader(
              title: 'Application received',
              subtitle: 'It is queued for the store team. Watch the account overview and your '
                  'notifications for the decision.',
            ),
            const SizedBox(height: OmSpacing.md),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                OmButton(
                  label: 'Account overview',
                  size: OmButtonSize.small,
                  onPressed: () => Get.offNamed<dynamic>(OmRoutes.account),
                ),
                OmButton(
                  label: 'Edit the application',
                  variant: OmButtonVariant.secondary,
                  size: OmButtonSize.small,
                  onPressed: () => Get.back<dynamic>(),
                ),
              ],
            ),
          ],
        ),
      );
}
