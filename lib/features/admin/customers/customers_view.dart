import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/user_profile.dart';
import 'package:om_events/features/admin/customers/customers_controller.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';
import 'package:om_events/features/admin/widgets/admin_badges.dart';

/// Customer accounts: search, role filter, wholesale state, block flag.
final class CustomersView extends StatefulWidget {
  const CustomersView({super.key});

  @override
  State<CustomersView> createState() => _CustomersViewState();
}

class _CustomersViewState extends State<CustomersView> {
  CustomersController get controller => Get.find<CustomersController>();
  late final TextEditingController _search =
      TextEditingController(text: controller.search.value);

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _export() async {
    await omShowAdminCsv(
      context,
      title: 'Customers export',
      csv: controller.exportLoaded(),
      totalRows: controller.rows.length,
    );
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
        child: Obx(() => OmAdminPanel<UserProfile>(
              isLoading: controller.isLoading.value,
              hasLoaded: controller.hasLoaded.value,
              failure: controller.failure.value,
              isEmpty: controller.rows.isEmpty,
              onRetry: controller.loadFirstPage,
              empty: OmEmptyState(
                icon: Icons.people_outline,
                title: controller.hasFilters ? 'No customers match' : 'No customer accounts yet',
                message: controller.hasFilters
                    ? 'Nothing matched the search or role filter.'
                    : 'Accounts appear here when someone registers or places a guest order.',
                actionLabel: controller.hasFilters ? 'Clear filters' : null,
                onAction: controller.hasFilters ? controller.clearFilters : null,
              ),
              builder: (context) => OmAdminPage(
                title: 'Customers',
                eyebrow: 'Accounts',
                subtitle: '${controller.rows.length} accounts on this page',
                actions: <Widget>[
                  OmButton(
                    label: 'Export loaded rows',
                    icon: Icons.file_download_outlined,
                    variant: OmButtonVariant.secondary,
                    onPressed: controller.rows.isEmpty ? null : _export,
                  ),
                  OmButton(
                    label: 'Reload',
                    variant: OmButtonVariant.ghost,
                    icon: Icons.refresh,
                    onPressed: controller.loadFirstPage,
                  ),
                ],
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    OmAdminFilterBar(
                      searchController: _search,
                      searchHint: 'Name, email or phone',
                      onSearch: controller.applySearch,
                      children: <Widget>[
                        SizedBox(
                          width: 210,
                          child: OmDropdown<UserRole>(
                            label: 'Role',
                            value: controller.roleFilter.value,
                            hint: 'Any role',
                            // Buyers, wholesale and staff only — guest is not an account.
                            items: const <UserRole>[
                              UserRole.customer,
                              UserRole.wholesale,
                              UserRole.staff,
                              UserRole.admin,
                              UserRole.owner,
                            ],
                            itemLabel: (role) => switch (role) {
                              UserRole.customer => 'Customer',
                              UserRole.wholesale => 'Wholesale',
                              UserRole.staff => 'Staff',
                              UserRole.admin => 'Admin',
                              UserRole.owner => 'Owner',
                              UserRole.guest => 'Guest',
                            },
                            onChanged: controller.applyRole,
                          ),
                        ),
                        if (controller.hasFilters)
                          OmButton(
                            label: 'Clear',
                            variant: OmButtonVariant.ghost,
                            size: OmButtonSize.small,
                            onPressed: () {
                              _search.clear();
                              controller.clearFilters();
                            },
                          ),
                      ],
                    ),
                    const SizedBox(height: OmSpacing.lg),
                    OmAdminResponsiveList(
                      itemCount: controller.rows.length,
                      onTapRow: (index) => controller.openDetail(controller.rows[index].uid),
                      columns: <OmAdminColumn>[
                        OmAdminColumn(
                          heading: 'Customer',
                          cell: (context, index) => _NameCell(profile: controller.rows[index]),
                        ),
                        OmAdminColumn(
                          heading: 'Contact',
                          cell: (context, index) {
                            final profile = controller.rows[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                OmText(
                                  AdminFormat.missing(profile.email),
                                  variant: OmTextVariant.caption,
                                  maxLines: 2,
                                ),
                                OmText(
                                  AdminFormat.missing(profile.phone),
                                  variant: OmTextVariant.caption,
                                ),
                              ],
                            );
                          },
                        ),
                        OmAdminColumn(
                          heading: 'Business',
                          cell: (context, index) {
                            final profile = controller.rows[index];
                            if (profile.companyName.isEmpty && profile.gstNumber.isEmpty) {
                              return const OmText('—', variant: OmTextVariant.caption);
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                OmText(
                                  AdminFormat.missing(profile.companyName),
                                  variant: OmTextVariant.bodyStrong,
                                  maxLines: 2,
                                ),
                                OmText(
                                  'GST ${AdminFormat.missing(profile.gstNumber)}',
                                  variant: OmTextVariant.caption,
                                ),
                              ],
                            );
                          },
                        ),
                        OmAdminColumn(
                          heading: 'Role',
                          cell: (context, index) => Wrap(
                            spacing: OmSpacing.xs,
                            runSpacing: OmSpacing.xs,
                            children: <Widget>[
                              roleBadge(controller.rows[index].role),
                              wholesaleBadge(controller.rows[index].wholesaleStatus),
                            ],
                          ),
                        ),
                        OmAdminColumn(
                          heading: 'Activity',
                          cell: (context, index) {
                            final profile = controller.rows[index];
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: <Widget>[
                                OmText(
                                  'Joined ${AdminFormat.date(profile.createdAt)}',
                                  variant: OmTextVariant.caption,
                                ),
                                OmText(
                                  'Last order ${AdminFormat.date(profile.lastOrderAt)}',
                                  variant: OmTextVariant.caption,
                                ),
                              ],
                            );
                          },
                        ),
                        OmAdminColumn(
                          heading: 'Access',
                          cell: (context, index) => controller.rows[index].isBlocked
                              ? const OmBadge(label: 'Blocked', tone: OmTone.danger, dense: true)
                              : const OmBadge(label: 'Active', tone: OmTone.success, dense: true),
                        ),
                      ],
                      cardBuilder: (context, index) {
                        final profile = controller.rows[index];
                        return OmAdminRowCard(
                          title: profile.displayName.isEmpty
                              ? (profile.email.isEmpty ? profile.uid : profile.email)
                              : profile.displayName,
                          badges: <Widget>[
                            roleBadge(profile.role),
                            wholesaleBadge(profile.wholesaleStatus),
                            if (profile.isBlocked)
                              const OmBadge(label: 'Blocked', tone: OmTone.danger, dense: true),
                          ],
                          lines: <String>[
                            '${AdminFormat.missing(profile.email)} · ${AdminFormat.missing(profile.phone)}',
                            if (profile.companyName.isNotEmpty)
                              '${profile.companyName} · GST ${AdminFormat.missing(profile.gstNumber)}',
                            'Joined ${AdminFormat.date(profile.createdAt)} · last order '
                                '${AdminFormat.date(profile.lastOrderAt)}',
                          ],
                          onTap: () => controller.openDetail(profile.uid),
                          actions: <Widget>[
                            OmButton(
                              label: 'Open',
                              size: OmButtonSize.small,
                              onPressed: () => controller.openDetail(profile.uid),
                            ),
                          ],
                        );
                      },
                      footer: OmAdminPager(
                        loadedCount: controller.rows.length,
                        hasMore: controller.hasMore,
                        isLoading: controller.isLoading.value,
                        onLoadMore: controller.loadMore,
                        onRefresh: controller.refresh,
                        totalEstimate: null,
                      ),
                    ),
                  ],
                ),
              ),
            )),
      );
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.profile});

  final UserProfile profile;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OmText(
                  profile.displayName.isEmpty ? '(no name)' : profile.displayName,
                  variant: OmTextVariant.bodyStrong,
                  maxLines: 2,
                ),
                OmText(profile.uid, variant: OmTextVariant.caption, maxLines: 1),
              ],
            ),
          ),
        ],
      );
}
