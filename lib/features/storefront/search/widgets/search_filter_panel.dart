import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/utils/money.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/features/storefront/search/search_controller.dart';

/// Filter + sort controls for the search page. Rendered as a sidebar on laptop-and-wider and as a
/// scroll-controlled bottom sheet on mobile/tablet, so neither layout needs a sideways page
/// scroll to reach a control.
///
/// The controller's query is the only state; each control calls the one setter it changes, so
/// applying a chip can never drop a price band the buyer had already typed.
class SearchFilterPanel extends StatefulWidget {
  const SearchFilterPanel({super.key, required this.controller, this.onApplied});

  final SearchController controller;

  /// Called after an apply so the bottom-sheet wrapper can close itself.
  final VoidCallback? onApplied;

  @override
  State<SearchFilterPanel> createState() => _SearchFilterPanelState();
}

class _SearchFilterPanelState extends State<SearchFilterPanel> {
  late final TextEditingController _min = TextEditingController(
    text: _rupeesOf(widget.controller.query.minPricePaise),
  );
  late final TextEditingController _max = TextEditingController(
    text: _rupeesOf(widget.controller.query.maxPricePaise),
  );

  static String _rupeesOf(int? paise) => paise == null ? '' : '${paise ~/ 100}';

  @override
  void dispose() {
    _min.dispose();
    _max.dispose();
    super.dispose();
  }

  /// Whole rupees typed by the buyer become integer paise; blank means "no bound".
  static int? _paiseFrom(TextEditingController field) {
    final digits = field.text.trim().replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return null;
    final rupees = int.tryParse(digits);
    if (rupees == null || rupees < 1) return null;
    return rupees * 100;
  }

  void _commitPriceBand() {
    widget.controller.setPriceBand(
      minPaise: _paiseFrom(_min),
      maxPaise: _paiseFrom(_max),
    );
    widget.onApplied?.call();
  }

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return Obx(() {
      final controller = widget.controller;
      final query = controller.query;
      final tags = controller.facetTags;

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          OmText('Refine results', variant: OmTextVariant.h3),
          const SizedBox(height: OmSpacing.md),
          OmDropdown<SortMode>(
            label: 'Sort by',
            value: query.sort,
            items: SortMode.values,
            itemLabel: (mode) => mode.label,
            onChanged: (mode) {
              if (mode != null) controller.setSort(mode);
            },
          ),
          const SizedBox(height: OmSpacing.lg),
          Text('Category', style: styles.bodyStrong),
          const SizedBox(height: OmSpacing.sm),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              OmFilterChip(
                label: 'All categories',
                selected: query.categorySlug == null,
                onTap: () => controller.setCategory(null),
              ),
              for (final category in controller.categoryChoices)
                OmFilterChip(
                  label: category.name,
                  selected: query.categorySlug == category.pathSlug,
                  onTap: () => controller.setCategory(category),
                ),
            ],
          ),
          const SizedBox(height: OmSpacing.lg),
          Text('Price range (₹)', style: styles.bodyStrong),
          const SizedBox(height: OmSpacing.sm),
          Row(
            children: <Widget>[
              Expanded(
                child: OmNumberField(
                  label: 'Minimum',
                  controller: _min,
                  hint: '0',
                ),
              ),
              const SizedBox(width: OmSpacing.sm),
              Expanded(
                child: OmNumberField(
                  label: 'Maximum',
                  controller: _max,
                  hint: 'Any',
                ),
              ),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          if (query.minPricePaise != null || query.maxPricePaise != null)
            OmText('Applied: ${_rangeLabel(query)}', variant: OmTextVariant.caption)
          else
            OmText(
              'Leave both blank to search every price.',
              variant: OmTextVariant.caption,
            ),
          const SizedBox(height: OmSpacing.sm),
          OmButton(
            label: 'Apply price range',
            icon: Icons.check,
            variant: OmButtonVariant.secondary,
            size: OmButtonSize.small,
            onPressed: _commitPriceBand,
          ),
          const SizedBox(height: OmSpacing.lg),
          OmSwitchRow(
            label: 'In stock only',
            value: query.inStockOnly,
            onChanged: controller.setInStockOnly,
          ),
          OmSwitchRow(
            label: 'Featured only',
            value: query.featuredOnly,
            onChanged: controller.setFeaturedOnly,
          ),
          OmSwitchRow(
            label: 'Wholesale-only items',
            value: query.wholesaleOnly ?? false,
            description: 'Shows only products the store lists as wholesale-only.',
            onChanged: (on) => controller.setWholesaleOnly(on ? true : null),
          ),
          if (tags.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.lg),
            Text('Tags in these results', style: styles.bodyStrong),
            const SizedBox(height: OmSpacing.sm),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                for (final tag in tags)
                  OmFilterChip(
                    label: tag,
                    selected: controller.activeTags.contains(tag),
                    onTap: () => controller.toggleTagFromSheet(tag),
                  ),
              ],
            ),
          ],
          const SizedBox(height: OmSpacing.lg),
          OmButton(
            label: 'Clear all filters',
            icon: Icons.filter_alt_off_outlined,
            variant: OmButtonVariant.ghost,
            onPressed: () {
              _min.clear();
              _max.clear();
              controller.resetFilters();
              widget.onApplied?.call();
            },
          ),
        ],
      );
    });
  }

  String _rangeLabel(CatalogQuery query) {
    final min = query.minPricePaise;
    final max = query.maxPricePaise;
    if (min != null && max != null) {
      return '${OmMoney.formatRupees(min)} – ${OmMoney.formatRupees(max)}';
    }
    if (min != null) return '${OmMoney.formatRupees(min)} and above';
    if (max != null) return 'Up to ${OmMoney.formatRupees(max)}';
    return 'Any price';
  }
}

/// Compact-layout entry point for the panel. `isScrollControlled` plus the keyboard inset keeps a
/// long filter list reachable without the page itself scrolling sideways.
Future<void> showSearchFilterSheet(BuildContext context, SearchController controller) {
  controller.openSheet();
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        left: OmSpacing.md,
        right: OmSpacing.md,
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + OmSpacing.md,
      ),
      child: SafeArea(
        child: SingleChildScrollView(
          child: SearchFilterPanel(
            controller: controller,
            onApplied: () => Navigator.of(sheetContext).pop(),
          ),
        ),
      ),
    ),
  ).whenComplete(controller.closeSheet);
}
