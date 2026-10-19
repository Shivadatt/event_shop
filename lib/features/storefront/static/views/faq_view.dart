import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/routes/app_routes.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/store_settings.dart';
import 'package:om_events/features/storefront/static/widgets/static_page.dart';

/// `/faq` — the store's own `faq` entries from `store_settings`, in the order the store set.
final class FaqView extends StatelessWidget {
  const FaqView({super.key});

  @override
  Widget build(BuildContext context) {
    return StaticPage(
      title: 'Frequently asked questions',
      subtitle: 'Answers the store wrote for the questions its trade buyers actually ask.',
      currentRoute: OmRoutes.faq,
      content: (context, settings) {
        if (settings == null) {
          return const OmLoading(message: 'Loading the store’s answers…');
        }
        return _FaqList(entries: settings.faq);
      },
    );
  }
}

class _FaqList extends StatelessWidget {
  const _FaqList({required this.entries});

  final List<FaqEntry> entries;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return OmEmptyState(
        compact: true,
        title: 'No questions published yet',
        message: 'The store has not written its FAQ list. Ask anything through the support desk and '
            'the answer goes in your thread.',
        icon: Icons.help_outline,
        actionLabel: 'Ask the support desk',
        onAction: () => Get.toNamed<dynamic>(OmRoutes.accountSupport),
      );
    }
    final sorted = [...entries]..sort((a, b) => a.order.compareTo(b.order));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        for (final entry in sorted)
          Padding(
            padding: const EdgeInsets.only(bottom: OmSpacing.sm),
            child: _FaqTile(entry: entry),
          ),
        const SizedBox(height: OmSpacing.sm),
        const OmText(
          'Nothing answered it? The support desk keeps a written thread on your account, which is '
          'also what the team uses to turn a common question into a new entry here.',
          variant: OmTextVariant.caption,
          overflow: TextOverflow.visible,
        ),
      ],
    );
  }
}

class _FaqTile extends StatelessWidget {
  const _FaqTile({required this.entry});

  final FaqEntry entry;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    return OmCard(
      padding: EdgeInsets.zero,
      child: Theme(
        // The tile inherits the page theme; without this the divider under each answer is the
        // theme default, which is invisible on the card's paper surface.
        data: Theme.of(context).copyWith(dividerColor: OmColors.line),
        child: ExpansionTile(
          tilePadding: const EdgeInsets.symmetric(horizontal: OmSpacing.md),
          childrenPadding: const EdgeInsets.fromLTRB(OmSpacing.md, 0, OmSpacing.md, OmSpacing.md),
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(entry.question, style: styles.bodyStrong),
          children: <Widget>[
            Text(entry.answer, style: styles.body),
          ],
        ),
      ),
    );
  }
}
