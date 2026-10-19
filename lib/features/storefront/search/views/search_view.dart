// `SearchController` is also a Material widget state class (search_anchor.dart); this page uses
// the storefront's GetX controller, so the Material name is hidden.
import 'package:flutter/material.dart' hide SearchController;
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/storefront/catalog/widgets/catalog_results.dart';
import 'package:om_events/features/storefront/common/external_links.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';
import 'package:om_events/features/storefront/search/search_controller.dart';
import 'package:om_events/features/storefront/search/widgets/search_filter_panel.dart';

/// `/search` — a search box with server-backed suggestions, a filter panel that is a sidebar on
/// laptop-and-wider and a scrollable sheet on compact layouts, and the shared results grid.
final class SearchView extends GetView<SearchController> {
  const SearchView({super.key});

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: 'Search',
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const SizedBox(height: OmSpacing.md),
            _SearchField(controller: controller),
            const SizedBox(height: OmSpacing.md),
            if (context.isWideLayout)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 300,
                    child: SearchFilterPanel(controller: controller),
                  ),
                  const SizedBox(width: OmSpacing.lg),
                  Expanded(child: CatalogResults(controller: controller)),
                ],
              )
            else
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _CompactFilterButton(controller: controller),
                  const SizedBox(height: OmSpacing.sm),
                  CatalogResults(controller: controller),
                ],
              ),
            const SizedBox(height: OmSpacing.lg),
            _ShareSearch(controller: controller),
            const SizedBox(height: OmSpacing.xl),
          ],
        ),
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({required this.controller});

  final SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const OmText(
          'FIND IT',
          variant: OmTextVariant.label,
        ),
        const SizedBox(height: OmSpacing.xs),
        OmTextField(
          label: 'Search products',
          hint: 'Balloons, backdrops, tableware…',
          prefixIcon: Icons.search,
          initialValue: controller.term.value,
          textInputAction: TextInputAction.search,
          onChanged: controller.onTermChanged,
          onSubmitted: controller.runSearch,
        ),
        Obx(() {
          if (controller.suggestionsLoading.value && controller.suggestions.isEmpty) {
            return const Padding(
              padding: EdgeInsets.only(top: OmSpacing.sm),
              child: OmLoading(message: 'Searching names and SKUs…'),
            );
          }
          final failure = controller.suggestionFailure.value;
          if (failure != null && controller.suggestions.isEmpty) {
            return Padding(
              padding: const EdgeInsets.only(top: OmSpacing.sm),
              child: OmErrorState(failure: failure, compact: true),
            );
          }
          final items = controller.suggestions.toList(growable: false);
          if (items.isEmpty) return const SizedBox.shrink();
          return Padding(
            padding: const EdgeInsets.only(top: OmSpacing.sm),
            child: Semantics(
              container: true,
              label: 'Search suggestions',
              child: Wrap(
                spacing: OmSpacing.sm,
                runSpacing: OmSpacing.sm,
                children: <Widget>[
                  for (final suggestion in items)
                    OmFilterChip(
                      label: suggestion,
                      selected: false,
                      onTap: () => controller.useSuggestion(suggestion),
                    ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}

class _CompactFilterButton extends StatelessWidget {
  const _CompactFilterButton({required this.controller});

  final SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final count = controller.activeFilterCount;
      return OmButton(
        label: count == 0 ? 'Filters' : 'Filters ($count)',
        icon: Icons.tune,
        variant: OmButtonVariant.outline,
        onPressed: () => showSearchFilterSheet(context, controller),
      );
    });
  }
}

class _ShareSearch extends StatelessWidget {
  const _ShareSearch({required this.controller});

  final SearchController controller;

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      if (!controller.hasActiveTerm) return const SizedBox.shrink();
      // Touching `term.value` keeps this caption correct after a search is run.
      final term = controller.term.value.trim();
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: () => OmExternalLink.copy(
            controller.absoluteDeepLink,
            note: 'Search link copied — paste it to share this result.',
          ),
          icon: const Icon(Icons.link, size: 18),
          label: Text('Copy link to “$term”', style: context.omText.bodyStrong),
        ),
      );
    });
  }
}
