import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/coupon.dart';
import 'package:om_events/features/admin/coupons/coupons_controller.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// Coupons: list with usage counters, and a create/edit form.
final class CouponsView extends StatelessWidget {
  const CouponsView({super.key});

  @override
  Widget build(BuildContext context) => AdminScaffold(
        title: 'Coupons',
        child: OmAdminPage(
          title: 'Discount codes',
          eyebrow: 'Marketing',
          subtitle: 'A code is only honoured by the order function — this page edits the coupon '
              'document, it cannot mint a discount the backend will not apply.',
          actions: <Widget>[
            OmButton(
              label: 'New coupon',
              icon: Icons.add,
              size: OmButtonSize.small,
              onPressed: () => Get.find<CouponsController>().openEditor(),
            ),
            OmButton(
              label: 'Reload',
              variant: OmButtonVariant.ghost,
              size: OmButtonSize.small,
              icon: Icons.refresh,
              onPressed: () => Get.find<CouponsController>().load(),
            ),
          ],
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: const <Widget>[
              _Editor(),
              _List(),
            ],
          ),
        ),
      );
}

class _List extends StatelessWidget {
  const _List();

  @override
  Widget build(BuildContext context) {
    final controller = Get.find<CouponsController>();
    return Obx(() => OmAdminPanel<Coupon>(
          isLoading: controller.isLoading.value,
          hasLoaded: controller.hasLoaded.value,
          failure: controller.failure.value,
          isEmpty: controller.coupons.isEmpty,
          onRetry: controller.load,
          empty: const OmEmptyState(
            icon: Icons.confirmation_number_outlined,
            title: 'No coupons yet',
            message: 'Create a code to run a promotion.',
          ),
          builder: (context) => Padding(
            padding: const EdgeInsets.only(top: OmSpacing.lg),
            child: OmAdminResponsiveList(
              itemCount: controller.coupons.length,
              onTapRow: (index) => controller.openEditor(controller.coupons[index]),
              columns: <OmAdminColumn>[
                OmAdminColumn(
                  heading: 'Code',
                  cell: (context, index) => OmText(
                    controller.coupons[index].code,
                    variant: OmTextVariant.bodyStrong,
                  ),
                ),
                OmAdminColumn(
                  heading: 'Discount',
                  cell: (context, index) => OmText(_discountLabel(controller.coupons[index])),
                ),
                OmAdminColumn(
                  heading: 'Usage',
                  numeric: true,
                  cell: (context, index) {
                    final c = controller.coupons[index];
                    return OmText(
                      '${c.usedCount}${c.usageLimit == null ? '' : '/${c.usageLimit}'}',
                      variant: OmTextVariant.body,
                    );
                  },
                ),
                OmAdminColumn(
                  heading: 'Per customer',
                  numeric: true,
                  cell: (context, index) => OmText('${controller.coupons[index].perUserLimit}'),
                ),
                OmAdminColumn(
                  heading: 'Window',
                  cell: (context, index) => OmText(
                    <String>[
                      if (controller.coupons[index].startsAt != null)
                        'from ${AdminFormat.date(controller.coupons[index].startsAt)}',
                      if (controller.coupons[index].endsAt != null)
                        'to ${AdminFormat.date(controller.coupons[index].endsAt)}',
                    ].join(' · ').isEmpty
                        ? 'Always'
                        : <String>[
                            if (controller.coupons[index].startsAt != null)
                              'from ${AdminFormat.date(controller.coupons[index].startsAt)}',
                            if (controller.coupons[index].endsAt != null)
                              'to ${AdminFormat.date(controller.coupons[index].endsAt)}',
                          ].join(' · '),
                    variant: OmTextVariant.caption,
                  ),
                ),
                OmAdminColumn(
                  heading: 'Status',
                  cell: (context, index) => couponBadge(controller.coupons[index]),
                ),
                OmAdminColumn(
                  heading: 'Actions',
                  cell: (context, index) => Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      OmIconButton(
                        icon: Icons.edit_outlined,
                        tooltip: 'Edit ${controller.coupons[index].code}',
                        size: 34,
                        onPressed: () => controller.openEditor(controller.coupons[index]),
                      ),
                      OmIconButton(
                        icon: Icons.delete_outline,
                        tooltip: 'Delete ${controller.coupons[index].code}',
                        size: 34,
                        onPressed: () async {
                          final ok = await omConfirmAdminAction(
                            context: context,
                            title: 'Delete ${controller.coupons[index].code}?',
                            message: 'The code stops working for new carts. Orders that already '
                                'used it keep their recorded discount.',
                            confirmLabel: 'Delete',
                            destructive: true,
                          );
                          if (ok) await controller.delete(controller.coupons[index]);
                        },
                      ),
                    ],
                  ),
                ),
              ],
              cardBuilder: (context, index) {
                final c = controller.coupons[index];
                return OmAdminRowCard(
                  title: c.code,
                  badges: <Widget>[couponBadge(c)],
                  lines: <String>[
                    _discountLabel(c),
                    'Used ${c.usedCount}${c.usageLimit == null ? '' : '/${c.usageLimit}'} · '
                        '${c.perUserLimit} per customer',
                  ],
                  onTap: () => controller.openEditor(c),
                  actions: <Widget>[
                    OmButton(
                      label: 'Edit',
                      size: OmButtonSize.small,
                      onPressed: () => controller.openEditor(c),
                    ),
                  ],
                );
              },
            ),
          ),
        ));
  }
}

/// The editor renders only while open, and is keyed on the coupon being edited so a reopen seeds
/// fresh `initialValue`s instead of showing the previous row's text.
class _Editor extends StatelessWidget {
  const _Editor();

  @override
  Widget build(BuildContext context) {
    final editor = Get.find<CouponEditController>();
    return Obx(() {
      if (!editor.isOpen) return const SizedBox.shrink();
      final draft = editor.draft.value;
      return Padding(
        padding: const EdgeInsets.only(bottom: OmSpacing.lg),
        child: OmCard(
          borderColor: OmColors.gold,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Expanded(
                    child: OmText(
                      editor.isNew ? 'New coupon' : 'Editing ${draft.code}',
                      variant: OmTextVariant.h3,
                    ),
                  ),
                  OmIconButton(
                    icon: Icons.close,
                    tooltip: 'Close editor',
                    size: 36,
                    onPressed: editor.close,
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.md),
              OmAdminNotice(
                tone: OmTone.info,
                message: 'Values are stored as integer paise and an integer percent. The '
                    'percentage cap and window are re-checked by the server on save.',
              ),
              const SizedBox(height: OmSpacing.md),
              // Keyed on the coupon identity so opening a different row rebuilds the fields with
              // fresh `initialValue`s; `OmTextField` only reads `initialValue` at first build.
              KeyedSubtree(
                key: ValueKey<String>('${draft.id}|${draft.code}'),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    OmAdminFormGrid(
                      children: <Widget>[
                        OmTextField(
                          label: 'Code',
                          required: true,
                          initialValue: draft.code,
                          hint: 'FESTIVE10',
                          helper: 'Uppercase letters, digits, hyphen or underscore.',
                          onChanged: editor.setCode,
                        ),
                        OmDropdown<CouponKind>(
                          label: 'Type',
                          value: draft.kind,
                          items: CouponKind.values,
                          itemLabel: couponKindLabel,
                          onChanged: (v) => v == null ? null : editor.setKind(v),
                        ),
                        if (draft.kind == CouponKind.percentage)
                          OmTextField(
                            label: 'Percent off',
                            initialValue: '${draft.percentOff}',
                            keyboardType: TextInputType.number,
                            helper: '1-99.',
                            onChanged: editor.setPercent,
                          )
                        else if (draft.kind == CouponKind.flatPaise)
                          OmTextField(
                            label: 'Flat amount (rupees)',
                            initialValue: _rupees(draft.valuePaise),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: editor.setValueRupees,
                          )
                        else
                          const OmText(
                            'Free shipping waives the shipping charge; no amount needed.',
                            variant: OmTextVariant.caption,
                          ),
                        if (draft.kind != CouponKind.freeShipping)
                          OmTextField(
                            label: 'Max discount (rupees, optional)',
                            initialValue: draft.maxDiscountPaise == null
                                ? ''
                                : _rupees(draft.maxDiscountPaise!),
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            onChanged: editor.setMaxDiscountRupees,
                          ),
                        OmTextField(
                          label: 'Minimum order value (rupees)',
                          initialValue: _rupees(draft.minCartValuePaise),
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          onChanged: editor.setMinOrderRupees,
                        ),
                        OmTextField(
                          label: 'Per-customer cap',
                          initialValue: '${draft.perUserLimit}',
                          keyboardType: TextInputType.number,
                          helper: 'How many times one customer may use this code.',
                          onChanged: editor.setPerUserLimit,
                        ),
                        OmTextField(
                          label: 'Total usage limit (optional)',
                          initialValue: draft.usageLimit == null ? '' : '${draft.usageLimit}',
                          keyboardType: TextInputType.number,
                          onChanged: editor.setUsageLimit,
                        ),
                        OmAdminDateField(
                          label: 'Starts',
                          value: draft.startsAt,
                          onChanged: editor.setStartsAt,
                        ),
                        OmAdminDateField(
                          label: 'Expires',
                          value: draft.endsAt,
                          onChanged: editor.setEndsAt,
                        ),
                      ],
                    ),
                    const SizedBox(height: OmSpacing.sm),
                    OmTextField(
                      label: 'Description',
                      initialValue: draft.description,
                      maxLines: 2,
                      onChanged: editor.setDescription,
                    ),
                    const SizedBox(height: OmSpacing.sm),
                    OmSwitchRow(
                      label: 'Active',
                      value: draft.isActive,
                      onChanged: editor.setActive,
                    ),
                    OmSwitchRow(
                      label: 'Exclude wholesale orders',
                      value: draft.excludesWholesale,
                      onChanged: editor.setExcludesWholesale,
                    ),
                    const SizedBox(height: OmSpacing.md),
                    Row(
                      children: <Widget>[
                        OmText(
                          'Used ${draft.usedCount} times so far (server counter).',
                          variant: OmTextVariant.caption,
                        ),
                        const Spacer(),
                        OmButton(
                          label: 'Cancel',
                          variant: OmButtonVariant.ghost,
                          onPressed: editor.close,
                        ),
                        const SizedBox(width: OmSpacing.sm),
                        OmButton(
                          label: 'Save coupon',
                          loading: editor.isSubmitting.value,
                          onPressed: editor.isSubmitting.value ? null : editor.save,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    });
  }
}

String _discountLabel(Coupon c) => switch (c.kind) {
      CouponKind.percentage => '${c.percentOff}% off'
          '${c.maxDiscountPaise == null ? '' : ' (max ${OmMoney.format(c.maxDiscountPaise!)})'}',
      CouponKind.flatPaise => '${OmMoney.format(c.valuePaise)} off',
      CouponKind.freeShipping => 'Free shipping',
    };

String _rupees(int paise) => (paise / 100).toStringAsFixed(paise % 100 == 0 ? 0 : 2);
