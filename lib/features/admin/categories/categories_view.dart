import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/features/admin/categories/categories_controller.dart';
import 'package:om_events/features/admin/categories/category_edit_view.dart';
import 'package:om_events/features/admin/dashboard/admin_scaffold.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Category tree with an inline editor.
///
/// There is no `/admin/categories/:id` constant in `OmRoutes`, so the editor is a panel above the
/// tree rather than a route, and it is keyed by the selected id so switching rows cannot leak the
/// previous draft into these fields. The tree itself comes from one bounded read
/// (`CategoryRepository.tree()`), which is the same read the storefront navigation uses.
final class CategoriesView extends StatefulWidget {
  const CategoriesView({super.key});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> {
  CategoriesController get list => Get.find<CategoriesController>();
  CategoryEditController get editor => Get.find<CategoryEditController>();

  /// Held by the screen: it is a text buffer, not state another widget needs.
  late final TextEditingController _search =
      TextEditingController(text: list.query.value);
  Worker? _selectionSync;

  @override
  void initState() {
    super.initState();
    // One direction only: the view mirrors the selection into the editor's draft. The editor never
    // writes back into `selectedId` except through `CategoriesController.select`.
    _selectionSync = ever<String?>(list.selectedId, (id) {
      editor.open(id == null || id == 'new' ? null : list.byId(id));
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _selectionSync?.dispose();
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AdminScaffold(
        child: Obx(() => OmAdminPanel<Category>(
              isLoading: list.isLoading.value,
              hasLoaded: list.hasLoaded.value,
              failure: list.failure.value,
              isEmpty: list.all.isEmpty,
              onRetry: list.load,
              empty: OmEmptyState(
                icon: Icons.category_outlined,
                title: 'No categories yet',
                message: 'Products need a category before they can appear in shop navigation. '
                    'Create the first one.',
                actionLabel: 'New category',
                onAction: list.startNew,
              ),
              builder: (context) {
                final rows = list.visibleTree;
                return OmAdminPage(
                  title: 'Categories',
                  eyebrow: 'Catalogue',
                  subtitle: '${list.all.length} categories in the store, ${rows.length} shown',
                  actions: <Widget>[
                    OmButton(
                      label: 'New category',
                      icon: Icons.add,
                      onPressed: list.startNew,
                    ),
                    OmButton(
                      label: 'Reload',
                      variant: OmButtonVariant.ghost,
                      icon: Icons.refresh,
                      onPressed: list.load,
                    ),
                  ],
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      if (list.editorOpen)
                        Padding(
                          padding: const EdgeInsets.only(bottom: OmSpacing.lg),
                          child: CategoryEditPanel(
                            key: ValueKey<String>(list.selectedId.value ?? 'none'),
                            list: list,
                            editor: editor,
                          ),
                        ),
                      _Filters(list: list, search: _search),
                      const SizedBox(height: OmSpacing.lg),
                      if (rows.isEmpty)
                        OmEmptyState(
                          icon: Icons.filter_alt_off_outlined,
                          title: 'Nothing matches',
                          message: 'No category matches the current search or active filter.',
                          actionLabel: 'Clear filters',
                          onAction: () {
                            _search.clear();
                            list.clearFilters();
                          },
                        )
                      else
                        OmAdminResponsiveList(
                          itemCount: rows.length,
                          onTapRow: (index) => list.select(rows[index]),
                          columns: <OmAdminColumn>[
                            OmAdminColumn(
                              heading: 'Category',
                              cell: (context, index) => _NameCell(
                                category: rows[index],
                                depth: list.query.trim().isEmpty
                                    ? list.depthOf(rows[index].id)
                                    : 0,
                              ),
                            ),
                            OmAdminColumn(
                              heading: 'Slug',
                              cell: (context, index) => OmText(
                                '/c/${rows[index].slug}',
                                variant: OmTextVariant.caption,
                                maxLines: 2,
                              ),
                            ),
                            OmAdminColumn(
                              heading: 'Parent',
                              cell: (context, index) => OmText(
                                list.labelFor(rows[index].parentId),
                                variant: OmTextVariant.caption,
                              ),
                            ),
                            OmAdminColumn(
                              heading: 'Products',
                              numeric: true,
                              cell: (context, index) => OmText(
                                '${rows[index].productCount}',
                                variant: OmTextVariant.bodyStrong,
                              ),
                            ),
                            OmAdminColumn(
                              heading: 'Order',
                              numeric: true,
                              cell: (context, index) => OmText('${rows[index].order}'),
                            ),
                            OmAdminColumn(
                              heading: 'Status',
                              cell: (context, index) => categoryBadges(rows[index]),
                            ),
                            OmAdminColumn(
                              heading: 'Actions',
                              cell: (context, index) => Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  OmIconButton(
                                    icon: Icons.edit_outlined,
                                    tooltip: 'Edit ${rows[index].name}',
                                    size: 34,
                                    onPressed: () => list.select(rows[index]),
                                  ),
                                  OmIconButton(
                                    icon: Icons.add_outlined,
                                    tooltip: 'New subcategory of ${rows[index].name}',
                                    size: 34,
                                    onPressed: () => list.startNew(),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          cardBuilder: (context, index) {
                            final category = rows[index];
                            return OmAdminRowCard(
                              title: category.name.isEmpty
                                  ? '(untitled)'
                                  : category.name,
                              badges: <Widget>[categoryBadges(category)],
                              lines: <String>[
                                '/c/${category.slug}',
                                'Parent: ${list.labelFor(category.parentId)} · '
                                    'order ${category.order}',
                                '${category.productCount} product(s) assigned',
                              ],
                              onTap: () => list.select(category),
                              actions: <Widget>[
                                OmButton(
                                  label: 'Edit',
                                  size: OmButtonSize.small,
                                  onPressed: () => list.select(category),
                                ),
                              ],
                            );
                          },
                          footer: Padding(
                            padding: const EdgeInsets.only(top: OmSpacing.md),
                            child: Row(
                              children: <Widget>[
                                const Expanded(
                                  child: OmText(
                                    'The whole tree is loaded at once — a partial tree would make '
                                    'the parent chooser wrong.',
                                    variant: OmTextVariant.caption,
                                  ),
                                ),
                                OmButton(
                                  label: 'Refresh',
                                  variant: OmButtonVariant.ghost,
                                  size: OmButtonSize.small,
                                  loading: list.isLoading.value,
                                  onPressed: list.isLoading.value ? null : list.load,
                                ),
                              ],
                            ),
                          ),
                        ),
                      const SizedBox(height: OmSpacing.lg),
                      const OmAdminNotice(
                        message: 'Product counts are maintained by the server, never typed here. '
                            'Deleting a category is refused while a product still references it — '
                            'that check runs on the write, not in this page.',
                      ),
                    ],
                  ),
                );
              },
            )),
      );
}

class _Filters extends StatelessWidget {
  const _Filters({required this.list, required this.search});

  final CategoriesController list;
  final TextEditingController search;

  @override
  Widget build(BuildContext context) => Obx(() {
        final showInactive = list.showInactive.value;
        return OmAdminFilterBar(
          searchController: search,
          searchHint: 'Search name or slug',
          onSearch: list.applyQuery,
          children: <Widget>[
            OmFilterChip(
              label: 'Show inactive',
              selected: showInactive,
              onTap: () => list.toggleShowInactive(!showInactive),
            ),
            if (list.hasFilters)
              OmButton(
                label: 'Clear',
                variant: OmButtonVariant.ghost,
                size: OmButtonSize.small,
                onPressed: () {
                  search.clear();
                  list.clearFilters();
                },
              ),
            const OmText(
              'Subcategories stay listed under their parent.',
              variant: OmTextVariant.caption,
            ),
          ],
        );
      });
}

class _NameCell extends StatelessWidget {
  const _NameCell({required this.category, required this.depth});

  final Category category;
  final int depth;

  @override
  Widget build(BuildContext context) => Row(
        children: <Widget>[
          for (var level = 0; level < depth; level++)
            const Padding(
              padding: EdgeInsets.only(right: OmSpacing.sm),
              child: OmText('↳', variant: OmTextVariant.caption),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                OmText(
                  category.name.isEmpty ? '(untitled)' : category.name,
                  variant: OmTextVariant.bodyStrong,
                  maxLines: 2,
                ),
                if (category.description.isNotEmpty)
                  OmText(
                    category.description,
                    variant: OmTextVariant.caption,
                    maxLines: 1,
                  ),
              ],
            ),
          ),
        ],
      );
}

/// State is carried by the badge words, not by colour alone, so a colourblind operator reading the
/// table sees the same information.
Widget categoryBadges(Category category) => Wrap(
      spacing: OmSpacing.xs,
      runSpacing: OmSpacing.xs,
      children: <Widget>[
        OmBadge(
          label: category.isActive ? 'Active' : 'Hidden',
          tone: category.isActive ? OmTone.success : OmTone.neutral,
          dense: true,
        ),
        if (category.isFeatured)
          const OmBadge(label: 'Featured', tone: OmTone.gold, dense: true),
        if (category.images.isEmpty)
          const OmBadge(label: 'No image', tone: OmTone.warning, dense: true),
      ],
    );
