import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/order.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/orders/orders_controller.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';
import 'package:om_events/features/storefront/common/external_links.dart';

/// One order, in full.
///
/// Two rules shape this page. Line prices are the stored snapshot — never re-priced from the
/// current catalogue — and every status move is offered only from `OrderStatus.nextSteps`, so the
/// UI cannot present a backwards transition that the Cloud Function would refuse anyway.
final class OrderDetailView extends StatelessWidget {
  const OrderDetailView({super.key});

  OrderDetailController get controller => Get.find<OrderDetailController>();

  @override
  Widget build(BuildContext context) => AdminScaffold(
        child: Obx(() => OmAdminPanel<Order>(
              isLoading: controller.isLoading.value,
              hasLoaded: controller.hasLoaded.value,
              failure: controller.failure.value,
              isEmpty: controller.order.value == null,
              onRetry: controller.load,
              empty: OmEmptyState(
                icon: Icons.receipt_long_outlined,
                title: 'Order not loaded',
                message: 'The order document did not come back. Retry, or open it from the orders '
                    'list again.',
                actionLabel: 'Retry',
                onAction: controller.load,
              ),
              builder: (context) {
                final order = controller.order.value!;
                return OmAdminPage(
                  title: order.orderNumber.isEmpty ? order.id : order.orderNumber,
                  eyebrow: 'Order',
                  subtitle: 'Placed ${AdminFormat.dateTime(order.createdAt)} · '
                      'source ${order.source}',
                  actions: <Widget>[
                    OmButton(
                      label: 'Reload',
                      variant: OmButtonVariant.ghost,
                      icon: Icons.refresh,
                      onPressed: controller.load,
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      OmCard(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            Wrap(
                              spacing: OmSpacing.sm,
                              runSpacing: OmSpacing.sm,
                              children: <Widget>[
                                orderBadge(order.status),
                                paymentBadge(order.paymentStatus),
                                deliveryBadge(order.deliveryMode),
                                if (order.isGuest)
                                  const OmBadge(label: 'Guest order', dense: true),
                                if (order.invoiceNumber.isNotEmpty)
                                  OmBadge(
                                    label: 'Invoice ${order.invoiceNumber}',
                                    tone: OmTone.info,
                                    dense: true,
                                  ),
                              ],
                            ),
                            const SizedBox(height: OmSpacing.md),
                            OmAdminMetaRow(
                              entries: <OmAdminMeta>[
                                OmAdminMeta(
                                  label: 'Customer',
                                  value: order.isGuest
                                      ? 'Guest'
                                      : (order.userId.isEmpty ? 'Unknown' : order.userId),
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Contact phone',
                                  value: AdminFormat.missing(order.contactPhone),
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Contact email',
                                  value: AdminFormat.missing(order.contactEmail),
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Coupon used',
                                  value: AdminFormat.missing(order.couponCode),
                                ),
                                OmAdminMeta(
                                  label: 'Payment method',
                                  value: AdminFormat.missing(order.paymentMethod),
                                ),
                                OmAdminMeta(
                                  label: 'Gateway reference',
                                  value: AdminFormat.missing(order.transactionReference),
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Order id',
                                  value: order.id,
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Updated',
                                  value: AdminFormat.dateTime(order.updatedAt),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: OmSpacing.md),
                      const OmAdminNotice(
                        tone: OmTone.gold,
                        icon: Icons.lock_clock,
                        title: 'Prices are snapshotted at purchase',
                        message: 'Every unit price and line total below is the value stored when '
                            'this order was created. Editing the product, its slab grid or a '
                            'customer price afterwards cannot rewrite these figures.',
                      ),
                      _LinesCard(controller: controller, order: order),
                      _TotalsCard(order: order),
                      _DeliveryCard(order: order),
                      _NotesCard(order: order),
                      _TransitionCard(controller: controller, order: order),
                      _PaymentCard(controller: controller, order: order),
                      _RefundCard(controller: controller, order: order),
                      _InvoiceCard(controller: controller),
                    ],
                  ),
                );
              },
            )),
      );
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({required this.controller, required this.order});

  final OrderDetailController controller;
  final Order order;

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Line items (${order.items.length})',
        subtitle: 'Quantity × the banded unit price that was charged at purchase.',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              for (var index = 0; index < order.items.length; index++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: index == order.items.length - 1 ? 0 : OmSpacing.md,
                  ),
                  child: _LineRow(item: order.items[index], controller: controller),
                ),
            ],
          ),
        ),
      );
}

class _LineRow extends StatelessWidget {
  const _LineRow({required this.item, required this.controller});

  final OrderItem item;
  final OrderDetailController controller;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Container(
      padding: const EdgeInsets.all(OmSpacing.md),
      decoration: BoxDecoration(
        color: OmColors.cream,
        borderRadius: OmRadius.smAll,
        border: Border.all(color: OmColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    OmText(
                      item.name.isEmpty ? '(item name was not snapshotted)' : item.name,
                      variant: OmTextVariant.bodyStrong,
                      maxLines: 3,
                    ),
                    const SizedBox(height: OmSpacing.xs),
                    OmText(
                      AdminFormat.missing(
                        item.sku.isEmpty ? item.productId : 'SKU ${item.sku}',
                      ),
                      variant: OmTextVariant.caption,
                      selectable: true,
                    ),
                    OmText(
                      controller.priceSnapshotNote(item),
                      variant: OmTextVariant.caption,
                    ),
                    if (item.variantId != null && item.variantId!.isNotEmpty)
                      OmText('Variant ${item.variantId}', variant: OmTextVariant.caption),
                    if (!item.isStockDeducted)
                      const OmText(
                        'Stock was not deducted for this line (recorded by the server).',
                        variant: OmTextVariant.caption,
                      ),
                  ],
                ),
              ),
              const SizedBox(width: OmSpacing.md),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(OmMoney.format(item.lineTotalPaise), style: styles.price),
                  OmText(
                    '${item.qty} × ${OmMoney.format(item.unitPricePaise)}',
                    variant: OmTextVariant.caption,
                  ),
                  if (item.savedPaise > 0)
                    OmText(
                      'saved ${OmMoney.format(item.savedPaise)}',
                      variant: OmTextVariant.caption,
                      color: OmColors.success,
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Totals are printed from the stored document. This widget adds nothing up; the only arithmetic
/// on screen is the label showing that the rounding field exists.
class _TotalsCard extends StatelessWidget {
  const _TotalsCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Stored totals',
        subtitle: 'Server-computed at checkout, in integer paise.',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              _TotalRow(label: 'Subtotal', value: order.totals.subtotalPaise),
              _TotalRow(
                label: 'Volume (slab) discount',
                value: -order.totals.slabDiscountPaise,
              ),
              _TotalRow(
                label: 'Coupon discount',
                value: -order.totals.couponDiscountPaise,
              ),
              _TotalRow(label: 'Shipping', value: order.totals.shippingPaise),
              _TotalRow(label: 'Tax / GST', value: order.totals.taxPaise),
              _TotalRow(label: 'Rounding', value: order.totals.roundingPaise),
              const OmDivider(space: OmSpacing.sm, indent: 0),
              _TotalRow(
                label: 'Grand total',
                value: order.totals.grandTotalPaise,
                emphasise: true,
              ),
              _TotalRow(label: 'Recorded as paid', value: order.totals.paidPaise),
              if (order.totals.refundedPaise > 0)
                _TotalRow(label: 'Refunded so far', value: -order.totals.refundedPaise),
            ],
          ),
        ),
      );
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
    required this.label,
    required this.value,
    this.emphasise = false,
  });

  final String label;
  final int value;
  final bool emphasise;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: OmSpacing.xs),
        child: Row(
          children: <Widget>[
            Expanded(
              child: OmText(
                label,
                variant: emphasise ? OmTextVariant.bodyStrong : OmTextVariant.body,
              ),
            ),
            Text(
              OmMoney.format(value),
              style: emphasise ? context.omText.price : context.omText.body,
            ),
          ],
        ),
      );
}

class _DeliveryCard extends StatelessWidget {
  const _DeliveryCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) {
    final pickup = order.deliveryMode == DeliveryMode.pickup;
    final shipping = order.shipping;
    return OmAdminSection(
      title: pickup ? 'Store pickup details' : 'Courier details',
      subtitle: pickup
          ? 'The buyer collects from the store; there is no shipping address to print.'
          : 'Address frozen into the order at purchase.',
      child: OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (pickup)
              OmAdminMetaRow(
                entries: <OmAdminMeta>[
                  const OmAdminMeta(
                    label: 'Mode',
                    value: 'Store pickup — customer collects',
                  ),
                  OmAdminMeta(
                    label: 'Contact phone',
                    value: AdminFormat.missing(order.contactPhone),
                    selectable: true,
                  ),
                  OmAdminMeta(
                    label: 'Collecting name',
                    value: AdminFormat.missing(shipping?.name),
                  ),
                  const OmAdminMeta(
                    label: 'Pickup window',
                    value: 'Set by the store; confirm by phone or WhatsApp',
                  ),
                ],
              )
            else
              OmAdminMetaRow(
                entries: <OmAdminMeta>[
                  OmAdminMeta(
                    label: 'Consignee',
                    value: AdminFormat.missing(shipping?.name),
                  ),
                  OmAdminMeta(
                    label: 'Phone',
                    value: AdminFormat.missing(shipping?.phone),
                    selectable: true,
                  ),
                  OmAdminMeta(
                    label: 'Address',
                    value: shipping == null ? '—' : shipping.singleLine,
                  ),
                  OmAdminMeta(
                    label: 'Pincode',
                    value: AdminFormat.missing(shipping?.pincode),
                  ),
                  OmAdminMeta(
                    label: 'GST on invoice',
                    value: AdminFormat.missing(shipping?.gstNumber),
                  ),
                  OmAdminMeta(
                    label: 'Carrier',
                    value: AdminFormat.missing(order.carrier),
                  ),
                  OmAdminMeta(
                    label: 'Tracking link',
                    value: AdminFormat.missing(order.trackingUrl),
                    selectable: true,
                  ),
                ],
              ),
            if (order.cancelledReason.isNotEmpty) ...<Widget>[
              const SizedBox(height: OmSpacing.md),
              OmAdminNotice(
                tone: OmTone.warning,
                icon: Icons.cancel_outlined,
                title: 'Cancellation reason',
                message: order.cancelledReason,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _NotesCard extends StatelessWidget {
  const _NotesCard({required this.order});

  final Order order;

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Notes',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OmAdminMeta(
                label: 'Customer note',
                value: AdminFormat.missing(order.customerNote, placeholder: 'None'),
              ),
              const SizedBox(height: OmSpacing.md),
              OmAdminMeta(
                label: 'Internal note stored on the order',
                value: AdminFormat.missing(order.internalNote, placeholder: 'None'),
              ),
              const SizedBox(height: OmSpacing.md),
              const OmText(
                'This screen has no free-form note editor: `AdminRepository` exposes no note write, '
                'so adding one here would mean inventing a repository method. Use the transition '
                'note below — it is what lands in the audit log.',
                variant: OmTextVariant.caption,
                maxLines: null,
              ),
            ],
          ),
        ),
      );
}

/// Forward-only transitions. The offered list is `OrderStatus.nextSteps`; a cancellation asks for a
/// reason and a dispatch asks for a carrier and tracking link before the write is sent.
class _TransitionCard extends StatefulWidget {
  const _TransitionCard({required this.controller, required this.order});

  final OrderDetailController controller;
  final Order order;

  @override
  State<_TransitionCard> createState() => _TransitionCardState();
}

class _TransitionCardState extends State<_TransitionCard> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  OrderStatus? _target;
  final TextEditingController _note = TextEditingController();
  final TextEditingController _carrier = TextEditingController();
  final TextEditingController _tracking = TextEditingController();
  final TextEditingController _cancelReason = TextEditingController();

  @override
  void dispose() {
    _note.dispose();
    _carrier.dispose();
    _tracking.dispose();
    _cancelReason.dispose();
    super.dispose();
  }

  bool get _needsTracking {
    final target = _target;
    return target == OrderStatus.shipped || target == OrderStatus.outForDelivery;
  }

  bool get _isCancel => _target == OrderStatus.cancelled;

  Future<void> _submit() async {
    final target = _target;
    // The button is disabled until a step is chosen, so this is only a guard against a stale
    // closure; no user-facing message is needed and the controller's announce() is protected.
    if (target == null) return;
    if (!(_form.currentState?.validate() ?? false)) return;
    final ok = await widget.controller.transitionTo(
      target,
      note: _note.text.trim(),
      cancelledReason: _isCancel ? _cancelReason.text.trim() : null,
      carrier: _needsTracking ? _carrier.text.trim() : null,
      trackingUrl: _needsTracking ? _tracking.text.trim() : null,
    );
    if (ok && mounted) {
      setState(() {
        _target = null;
        _note.clear();
        _carrier.clear();
        _tracking.clear();
        _cancelReason.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Move this order forward',
        subtitle: 'Only the steps the workflow allows are listed. The Cloud Function re-checks the '
            'same table, restores stock on a cancel and writes the audit row.',
        child: Obx(() {
          final steps = widget.controller.availableSteps;
          return OmCard(
            child: Form(
              key: _form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (steps.isEmpty)
                    const OmAdminNotice(
                      tone: OmTone.neutral,
                      icon: Icons.done_all,
                      title: 'Nothing to transition',
                      message: 'This status is terminal — the workflow has no forward step from it. '
                          'A refund request below stays available.',
                    )
                  else ...<Widget>[
                    Wrap(
                      spacing: OmSpacing.sm,
                      runSpacing: OmSpacing.sm,
                      children: <Widget>[
                        for (final step in steps)
                          OmFilterChip(
                            label: orderStatusLabel(step),
                            selected: _target == step,
                            onTap: () => setState(() => _target = step),
                          ),
                      ],
                    ),
                    const SizedBox(height: OmSpacing.md),
                    if (_target != null)
                      OmAdminFormGrid(
                        children: <Widget>[
                          if (_isCancel)
                            OmTextField(
                              label: 'Cancellation reason',
                              required: true,
                              controller: _cancelReason,
                              hint: 'Out of stock, customer asked, duplicate order…',
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? 'A cancellation needs a reason for the audit log'
                                  : null,
                            ),
                          if (_needsTracking) ...<Widget>[
                            OmTextField(
                              label: 'Carrier',
                              required: true,
                              controller: _carrier,
                              hint: 'Blue Dart, Delhivery, local courier',
                              validator: (value) => (value ?? '').trim().isEmpty
                                  ? 'Name the carrier before dispatching'
                                  : null,
                            ),
                            OmTextField(
                              label: 'Tracking URL or AWB',
                              controller: _tracking,
                              hint: 'https://…',
                            ),
                          ],
                          OmTextField(
                            label: 'Transition note (optional)',
                            controller: _note,
                            maxLines: 2,
                            helper: 'Stored on the audit row beside the status change.',
                          ),
                        ],
                      ),
                    if (_target != null) const SizedBox(height: OmSpacing.md),
                    Row(
                      children: <Widget>[
                        OmButton(
                          label: _target == null
                              ? 'Choose a step'
                              : 'Mark as ${orderStatusLabel(_target!).toLowerCase()}',
                          icon: Icons.arrow_forward,
                          loading: widget.controller.isSubmitting.value,
                          onPressed: _target == null || widget.controller.isSubmitting.value
                              ? null
                              : _submit,
                        ),
                        const SizedBox(width: OmSpacing.md),
                        const Expanded(
                          child: OmText(
                            'Privileged write: the server re-checks the role and the transition '
                            'table, so this card hiding a step is never the permission.',
                            variant: OmTextVariant.caption,
                            maxLines: 3,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        }),
      );
}

class _PaymentCard extends StatefulWidget {
  const _PaymentCard({required this.controller, required this.order});

  final OrderDetailController controller;
  final Order order;

  @override
  State<_PaymentCard> createState() => _PaymentCardState();
}

class _PaymentCardState extends State<_PaymentCard> {
  static const List<String> _methods = <String>[
    'upi',
    'card',
    'netbanking',
    'wallet',
    'cash',
    'bank_transfer',
  ];

  String _method = _methods.first;
  bool _isCod = false;
  final TextEditingController _reference = TextEditingController();

  @override
  void initState() {
    super.initState();
    final stored = widget.order.paymentMethod;
    if (_methods.contains(stored)) _method = stored;
    if (widget.order.paymentStatus == PaymentStatus.codPending) _isCod = true;
  }

  @override
  void dispose() {
    _reference.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ok = await widget.controller.markPayment(
      method: _isCod ? 'cod' : _method,
      transactionReference: _reference.text.trim().isEmpty ? null : _reference.text.trim(),
      isCod: _isCod,
    );
    if (ok && mounted) setState(() => _reference.clear());
  }

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Payment',
        subtitle: 'Recording a payment here marks an externally settled order; it never moves money.',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              OmAdminNotice(
                message: 'Current state: ${paymentStatusLabel(widget.order.paymentStatus)}. '
                    'Recorded paid: ${OmMoney.format(widget.order.totals.paidPaise)}. The stored '
                    'amount is set by the server, not by this form.',
                tone: OmTone.info,
              ),
              const SizedBox(height: OmSpacing.md),
              if (!widget.controller.canMarkPayment)
                OmAdminNotice.requiresRole('staff, admin or owner')
              else
                OmAdminFormGrid(
                  children: <Widget>[
                    OmDropdown<String>(
                      label: 'Method settled',
                      value: _method,
                      items: _methods,
                      itemLabel: (code) => switch (code) {
                        'upi' => 'UPI',
                        'card' => 'Card',
                        'netbanking' => 'Net banking',
                        'wallet' => 'Wallet',
                        'cash' => 'Cash at counter',
                        _ => 'Bank transfer',
                      },
                      onChanged: (value) => setState(() => _method = value ?? _method),
                      enabled: !_isCod,
                    ),
                    OmTextField(
                      label: 'Gateway reference / UTR',
                      controller: _reference,
                      hint: 'Optional, but strongly worth recording',
                      enabled: !_isCod,
                    ),
                  ],
                ),
              if (widget.controller.canMarkPayment) ...<Widget>[
                const SizedBox(height: OmSpacing.sm),
                OmSwitchRow(
                  label: 'Cash on delivery (settles when collected, not now)',
                  value: _isCod,
                  onChanged: (value) => setState(() => _isCod = value),
                ),
                const SizedBox(height: OmSpacing.md),
                Obx(
                  () => OmButton(
                    label: 'Record payment',
                    icon: Icons.verified_outlined,
                    loading: widget.controller.isSubmitting.value,
                    onPressed: widget.controller.isSubmitting.value ? null : _submit,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _RefundCard extends StatefulWidget {
  const _RefundCard({required this.controller, required this.order});

  final OrderDetailController controller;
  final Order order;

  @override
  State<_RefundCard> createState() => _RefundCardState();
}

class _RefundCardState extends State<_RefundCard> {
  final GlobalKey<FormState> _form = GlobalKey<FormState>();
  final TextEditingController _amount = TextEditingController();
  final TextEditingController _reason = TextEditingController();

  int get _paidPaise => widget.order.totals.grandTotalPaise - widget.order.totals.refundedPaise;

  @override
  void dispose() {
    _amount.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final ok = await widget.controller.requestRefund(
      amountPaise: AdminFormat.paiseFromRupeeText(_amount.text),
      reason: _reason.text,
    );
    if (ok && mounted) {
      setState(() {
        _amount.clear();
        _reason.clear();
      });
    }
  }

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Refund request',
        subtitle: 'Refunds are an admin/owner action. The gateway call and the ledger entry are '
            'made by the server; this form only asks.',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              if (!widget.controller.canIssueRefund)
                OmAdminNotice.requiresRole('admin or owner')
              else ...<Widget>[
                OmAdminNotice(
                  tone: OmTone.warning,
                  icon: Icons.savings_outlined,
                  title: 'Suggested ceiling',
                  message: 'The stored grand total less what has already been refunded is '
                      '${OmMoney.format(_paidPaise)}. That figure is a display hint only — the '
                      'function recomputes the refundable amount and refuses more.',
                ),
                const SizedBox(height: OmSpacing.md),
                Form(
                  key: _form,
                  child: OmAdminFormGrid(
                    children: <Widget>[
                      OmTextField(
                        label: 'Amount to refund (₹)',
                        required: true,
                        controller: _amount,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        hint: '1500 or 1500.50',
                        validator: (value) {
                          final paise = AdminFormat.paiseFromRupeeText(value ?? '');
                          if (paise <= 0) return 'Enter an amount above zero';
                          return null;
                        },
                      ),
                      OmTextField(
                        label: 'Reason',
                        required: true,
                        controller: _reason,
                        maxLines: 3,
                        maxLength: omAdminReasonMaxLength,
                        helper: 'Written to the audit log beside the refund.',
                        validator: (value) => (value ?? '').trim().isEmpty
                            ? 'A refund needs a reason'
                            : null,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: OmSpacing.md),
                Obx(
                  () => OmButton(
                    label: 'Request refund',
                    icon: Icons.undo_outlined,
                    variant: OmButtonVariant.danger,
                    loading: widget.controller.isSubmitting.value,
                    onPressed: widget.controller.isSubmitting.value ? null : _submit,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}

class _InvoiceCard extends StatelessWidget {
  const _InvoiceCard({required this.controller});

  final OrderDetailController controller;

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Invoice',
        subtitle: 'The URL is re-read every time, so a signed link is never cached here.',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Obx(() {
                final url = controller.invoiceUrl.value;
                if (url == null) {
                  return const OmText(
                    'No invoice link fetched yet.',
                    variant: OmTextVariant.caption,
                  );
                }
                return OmAdminMeta(label: 'Invoice link', value: url, selectable: true);
              }),
              const SizedBox(height: OmSpacing.md),
              Row(
                children: <Widget>[
                  Obx(
                    () => OmButton(
                      label: 'Fetch and open invoice',
                      icon: Icons.picture_as_pdf_outlined,
                      variant: OmButtonVariant.secondary,
                      loading: controller.isLoading.value,
                      onPressed: () async {
                        final url = await controller.loadInvoiceUrl();
                        if (url != null && url.isNotEmpty) {
                          if (!context.mounted) return;
                          await OmExternalLink.open(context, url, label: 'invoice');
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: OmSpacing.md),
                  const Expanded(
                    child: OmText(
                      'If the invoice has not been generated yet, the server returns nothing and '
                      'this screen says so rather than showing a stale PDF.',
                      variant: OmTextVariant.caption,
                      maxLines: 3,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
}
