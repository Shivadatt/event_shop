import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/features/admin/customers/customers_controller.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// One customer account, with the two privileged writes that change who they are: role and block.
///
/// Lifetime value comes from the server aggregate. The order table is explicitly one page of the
/// account's orders, and the screen says so instead of letting an operator read a partial list as
/// the whole history.
final class CustomerDetailView extends StatelessWidget {
  const CustomerDetailView({super.key});

  CustomerDetailController get controller => Get.find<CustomerDetailController>();

  @override
  Widget build(BuildContext context) => AdminScaffold(
        child: Obx(() => OmAdminPanel<UserProfile>(
              isLoading: controller.isLoading.value,
              hasLoaded: controller.hasLoaded.value,
              failure: controller.failure.value,
              isEmpty: controller.profile.value == null,
              onRetry: controller.load,
              empty: OmEmptyState(
                icon: Icons.person_off_outlined,
                title: 'Account not loaded',
                message: 'No profile came back for this uid. It may have been merged or removed.',
                actionLabel: 'Retry',
                onAction: controller.load,
              ),
              builder: (context) {
                final profile = controller.profile.value!;
                return OmAdminPage(
                  title: profile.displayName.isEmpty
                      ? (profile.email.isEmpty ? profile.uid : profile.email)
                      : profile.displayName,
                  eyebrow: 'Customer',
                  subtitle: 'Joined ${AdminFormat.date(profile.createdAt)} · uid ${profile.uid}',
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
                                roleBadge(profile.role),
                                wholesaleBadge(profile.wholesaleStatus),
                                profile.isBlocked
                                    ? const OmBadge(
                                        label: 'Blocked', tone: OmTone.danger, dense: true)
                                    : const OmBadge(
                                        label: 'Not blocked', tone: OmTone.success, dense: true),
                                if (profile.hasWholesalePricing)
                                  const OmBadge(
                                    label: 'Wholesale pricing live', tone: OmTone.gold, dense: true),
                              ],
                            ),
                            const SizedBox(height: OmSpacing.md),
                            OmAdminMetaRow(
                              entries: <OmAdminMeta>[
                                OmAdminMeta(
                                  label: 'Email',
                                  value: AdminFormat.missing(profile.email),
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Phone',
                                  value: AdminFormat.missing(profile.phone),
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Company',
                                  value: AdminFormat.missing(profile.companyName),
                                ),
                                OmAdminMeta(
                                  label: 'GST number',
                                  value: AdminFormat.missing(profile.gstNumber),
                                  selectable: true,
                                ),
                                OmAdminMeta(
                                  label: 'Last order',
                                  value: AdminFormat.date(profile.lastOrderAt),
                                ),
                                OmAdminMeta(
                                  label: 'Wishlist items',
                                  value: '${profile.wishlistProductIds.length}',
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      _ValueCard(controller: controller),
                      _OrdersCard(controller: controller),
                      _PrivilegedCard(controller: controller, profile: profile),
                    ],
                  ),
                );
              },
            )),
      );
}

class _ValueCard extends StatelessWidget {
  const _ValueCard({required this.controller});

  final CustomerDetailController controller;

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Lifetime value',
        subtitle: 'Counted by the server from the orders collection.',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Obx(() {
                final row = controller.value.value;
                if (row == null) {
                  return const OmAdminNotice(
                    tone: OmTone.warning,
                    icon: Icons.help_outline,
                    title: 'Aggregate not returned',
                    message: 'The customer-value function has not answered, so no figure is '
                        'printed. This panel deliberately does not add up the visible order page '
                        'as a substitute.',
                  );
                }
                return OmAdminMetaRow(
                  entries: <OmAdminMeta>[
                    OmAdminMeta(label: 'Orders', value: '${row.orderCount}', emphasise: true),
                    OmAdminMeta(
                      label: 'Paid',
                      value: _rupees(row.revenuePaise),
                      emphasise: true,
                    ),
                    OmAdminMeta(label: 'Refunded', value: _rupees(row.refundedPaise)),
                    OmAdminMeta(
                      label: 'Net',
                      value: _rupees(row.revenuePaise - row.refundedPaise),
                    ),
                  ],
                );
              }),
              const SizedBox(height: OmSpacing.md),
              const OmText(
                'Net is the paid aggregate minus the refunded aggregate — both server numbers. '
                'Order-line pricing on each of those orders is the snapshot stored with the order.',
                variant: OmTextVariant.caption,
              ),
            ],
          ),
        ),
      );

  static String _rupees(int paise) => OmMoney.format(paise);
}

class _OrdersCard extends StatelessWidget {
  const _OrdersCard({required this.controller});

  final CustomerDetailController controller;

  @override
  Widget build(BuildContext context) => OmAdminSection(
        title: 'Orders',
        subtitle: 'The page of this account\'s orders the server returned, most recent first.',
        child: OmCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Obx(() {
                final orders = controller.orders;
                if (orders.isEmpty) {
                  return const OmText(
                    'No orders returned for this account on the loaded page.',
                    variant: OmTextVariant.caption,
                  );
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (final order in orders)
                      Padding(
                        padding: const EdgeInsets.only(bottom: OmSpacing.sm),
                        child: OmAdminRowCard(
                          title: order.orderNumber.isEmpty ? order.id : order.orderNumber,
                          badges: <Widget>[
                            orderBadge(order.status),
                            paymentBadge(order.paymentStatus),
                            deliveryBadge(order.deliveryMode),
                          ],
                          lines: <String>[
                            AdminFormat.dateTime(order.createdAt),
                            '${order.totalQty} unit(s) · stored total '
                                '${OmMoney.format(order.totals.grandTotalPaise)}',
                          ],
                          onTap: () => Get.toNamed<dynamic>(OmRoutes.forAdminOrder(order.id)),
                        ),
                      ),
                  ],
                );
              }),
              const SizedBox(height: OmSpacing.sm),
              Obx(
                () => OmText(
                  controller.ordersCountText,
                  variant: OmTextVariant.caption,
                ),
              ),
            ],
          ),
        ),
      );
}

/// Role change and block/unblock. Both require a reason and both are visibly labelled privileged,
/// because a silent hide teaches an operator nothing about what the server will refuse.
class _PrivilegedCard extends StatefulWidget {
  const _PrivilegedCard({required this.controller, required this.profile});

  final CustomerDetailController controller;
  final UserProfile profile;

  @override
  State<_PrivilegedCard> createState() => _PrivilegedCardState();
}

class _PrivilegedCardState extends State<_PrivilegedCard> {
  UserRole? _role;
  final TextEditingController _reason = TextEditingController();

  @override
  void initState() {
    super.initState();
    _role = widget.profile.role;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _changeRole() async {
    final target = _role;
    final profile = widget.profile;
    if (target == null || target == profile.role) return;
    final reason = await omPromptForReason(
      context: context,
      label: 'Why is the role changing from ${profile.role.code} to ${target.code}?',
      title: 'Reason for the role change',
    );
    if (reason == null) return;
    // The reason prompt is an async gap: on web the operator can navigate away while it is open, so
    // the confirmation dialog must not be built against a defunct element. Inside a `State`,
    // `mounted` is the guard the analyzer understands for `this.context` (a `context.mounted` check
    // on the inherited getter is not tracked), and it implies the same thing: this element is still
    // in the tree.
    if (!mounted) return;
    final confirmed = await omConfirmAdminAction(
      context: context,
      title: 'Change role to ${target.code}?',
      message: target.canManageStore
          ? 'This grants store-management access. The write is refused unless the acting account '
              'is admin or owner, and it is logged with your reason.'
          : 'This account loses or narrows its access on the next read. Nothing about its orders '
              'changes.',
      confirmLabel: 'Change role',
      destructive: !target.canManageStore,
    );
    if (!confirmed) return;
    if (await widget.controller.changeRole(target, reason) && mounted) setState(() {});
  }

  Future<void> _toggleBlock(bool blocked) async {
    final reason = await omPromptForReason(
      context: context,
      label: blocked ? 'Why is this account being blocked?' : 'Why is the block being lifted?',
      title: blocked ? 'Block account' : 'Unblock account',
    );
    if (reason == null) return;
    // Same async gap as the role change — see the note there for why `mounted` is the guard.
    if (!mounted) return;
    final confirmed = await omConfirmAdminAction(
      context: context,
      title: blocked ? 'Block this customer?' : 'Unblock this customer?',
      message: blocked
          ? 'They keep their order history but cannot sign in or check out. Their existing carts '
              'and any saved addresses stay untouched. The reason is written to the audit log.'
          : 'The account can sign in again immediately. Check that the reason for the original '
              'block has actually been resolved.',
      confirmLabel: blocked ? 'Block account' : 'Unblock account',
      destructive: blocked,
    );
    if (!confirmed) return;
    if (await widget.controller.setBlocked(blocked: blocked, reason: reason) && mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = widget.profile;
    return OmAdminSection(
      title: 'Privileged account actions',
      subtitle: 'Both writes are re-authorized by the server before they land.',
      child: OmCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!widget.controller.canManageRoles)
              OmAdminNotice.requiresRole('admin or owner')
            else ...<Widget>[
              OmAdminFormGrid(
                children: <Widget>[
                  OmDropdown<UserRole>(
                    label: 'Role',
                    value: _role,
                    items: const <UserRole>[
                      UserRole.customer,
                      UserRole.wholesale,
                      UserRole.staff,
                      UserRole.admin,
                      UserRole.owner,
                    ],
                    itemLabel: (role) => role.code,
                    onChanged: (value) => setState(() => _role = value),
                  ),
                  OmTextField(
                    label: 'Reason for the change',
                    controller: _reason,
                    maxLines: 2,
                    maxLength: omAdminReasonMaxLength,
                    helper: 'Stored with the audit row. Required.',
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.md),
              Wrap(
                spacing: OmSpacing.sm,
                runSpacing: OmSpacing.sm,
                children: <Widget>[
                  Obx(
                    () => OmButton(
                      label: 'Save role change',
                      icon: Icons.manage_accounts_outlined,
                      loading: widget.controller.isSubmitting.value,
                      onPressed: widget.controller.isSubmitting.value || _role == profile.role
                          ? null
                          : _changeRole,
                    ),
                  ),
                  OmButton(
                    label: profile.isBlocked ? 'Unblock account' : 'Block account',
                    icon: profile.isBlocked ? Icons.lock_open : Icons.block,
                    variant: profile.isBlocked
                        ? OmButtonVariant.secondary
                        : OmButtonVariant.danger,
                    onPressed: widget.controller.isSubmitting.value
                        ? null
                        : () => _toggleBlock(!profile.isBlocked),
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.md),
              const OmAdminNotice(
                message: 'A customer cannot be given wholesale pricing from this card. Approval '
                    'happens on the wholesale queue, which is the only path to wholesale prices — '
                    'setting the role here is for staff access, not for repricing an account.',
                icon: Icons.info_outline,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
