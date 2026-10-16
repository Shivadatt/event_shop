import 'package:flutter/material.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_responsive.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';

/// Loading / empty / error / content, from one widget, with retry wired.
///
/// `OmStateView` has no retry hook; every admin surface needs one because these reads cross the
/// network, so this composes the same primitives instead of inventing new ones. A request that
/// neither succeeded nor failed is reported as a loading state, never as "no results", which is
/// how a dead backend would otherwise masquerade as an empty store.
final class OmAdminPanel<T> extends StatelessWidget {
  const OmAdminPanel({
    super.key,
    required this.isLoading,
    required this.hasLoaded,
    required this.failure,
    required this.isEmpty,
    required this.builder,
    required this.empty,
    this.onRetry,
    this.loadingMessage,
    this.skeleton,
  });

  final bool isLoading;
  final bool hasLoaded;
  final OmFailure? failure;
  final bool isEmpty;
  final Widget Function(BuildContext context) builder;
  final Widget empty;
  final VoidCallback? onRetry;
  final String? loadingMessage;
  final Widget? skeleton;

  @override
  Widget build(BuildContext context) {
    final error = failure;
    if (error != null) return OmErrorState(failure: error, onRetry: onRetry);
    if (!hasLoaded || isLoading) {
      return skeleton ?? OmLoading(message: loadingMessage ?? 'Loading…');
    }
    if (isEmpty) return empty;
    return builder(context);
  }
}

/// One column of a dense admin table.
///
/// The cell closure receives the row index only: screens close over their own page of rows, which
/// keeps this widget free of a second copy of the data.
final class OmAdminColumn {
  const OmAdminColumn({
    required this.heading,
    required this.cell,
    this.numeric = false,
  });

  final String heading;
  final Widget Function(BuildContext context, int index) cell;
  final bool numeric;
}

/// Table on wide screens, card list under [minTableWidth].
///
/// The wide branch scrolls its own body sideways when a table is wider than the column it sits in,
/// so the *page* never moves horizontally; the compact branch is mandatory (not optional) because
/// a five-column table is unreadable on a phone.
final class OmAdminResponsiveList extends StatelessWidget {
  const OmAdminResponsiveList({
    super.key,
    required this.itemCount,
    required this.columns,
    required this.cardBuilder,
    this.onTapRow,
    this.minTableWidth = OmBreakpoints.laptop,
    this.footer,
  });

  final int itemCount;
  final List<OmAdminColumn> columns;
  final Widget Function(BuildContext context, int index) cardBuilder;
  final void Function(int index)? onTapRow;
  final double minTableWidth;
  final Widget? footer;

  @override
  Widget build(BuildContext context) => OmResponsiveTable(
        minTableWidth: minTableWidth,
        table: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _AdminTable(
              itemCount: itemCount,
              columns: columns,
              onTapRow: onTapRow,
            ),
            if (footer != null) footer!,
          ],
        ),
        asCards: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < itemCount; index++)
              Padding(
                padding: const EdgeInsets.only(bottom: OmSpacing.sm),
                child: cardBuilder(context, index),
              ),
            if (footer != null) footer!,
          ],
        ),
      );
}

class _AdminTable extends StatelessWidget {
  const _AdminTable({
    required this.itemCount,
    required this.columns,
    required this.onTapRow,
  });

  final int itemCount;
  final List<OmAdminColumn> columns;
  final void Function(int index)? onTapRow;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final headingStyle = styles.label.copyWith(
      color: styles.muted.color,
      fontWeight: FontWeight.w700,
    );
    return OmCard(
      padding: const EdgeInsets.symmetric(
        horizontal: OmSpacing.xs,
        vertical: OmSpacing.xs,
      ),
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            // Bounded so a long description cannot push the table to an unmeasurable width, and
            // at least the viewport so the card fills the column.
            constraints: const BoxConstraints(minWidth: 720),
            child: DataTable(
              headingRowHeight: 40,
              dataRowMinHeight: 48,
              dataRowMaxHeight: 88,
              horizontalMargin: OmSpacing.md,
              columnSpacing: OmSpacing.lg,
              dividerThickness: 0.6,
              headingTextStyle: headingStyle,
              dataTextStyle: styles.body,
              columns: columns
                  .map(
                    (c) => DataColumn(
                      numeric: c.numeric,
                      label: SizedBox(
                        width: c.numeric ? 120 : 200,
                        child: Text(
                          c.heading,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 2,
                          style: headingStyle,
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
              rows: List<DataRow>.generate(
                itemCount,
                (index) => DataRow(
                  onSelectChanged:
                      onTapRow == null ? null : (_) => onTapRow!(index),
                  cells: columns
                      .map(
                        (c) => DataCell(
                          SizedBox(
                            width: c.numeric ? 120 : 200,
                            child: c.cell(context, index),
                          ),
                        ),
                      )
                      .toList(growable: false),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact rendering of one table row. Every field is labelled with text, so state is never
/// carried by colour alone.
final class OmAdminRowCard extends StatelessWidget {
  const OmAdminRowCard({
    super.key,
    required this.title,
    this.lines = const <String>[],
    this.trailing,
    this.badges = const <Widget>[],
    this.onTap,
    this.actions = const <Widget>[],
  });

  final String title;
  final List<String> lines;
  final Widget? trailing;
  final List<Widget> badges;
  final VoidCallback? onTap;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => OmCard(
        onTap: onTap,
        padding: const EdgeInsets.all(OmSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: OmText(title, variant: OmTextVariant.bodyStrong),
                ),
                if (trailing != null) ...<Widget>[
                  const SizedBox(width: OmSpacing.sm),
                  trailing!,
                ],
              ],
            ),
            if (badges.isNotEmpty) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              Wrap(spacing: OmSpacing.xs, runSpacing: OmSpacing.xs, children: badges),
            ],
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(top: OmSpacing.xs),
                child: OmText(line, variant: OmTextVariant.caption, maxLines: 4),
              ),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: OmSpacing.md),
              Wrap(spacing: OmSpacing.sm, runSpacing: OmSpacing.sm, children: actions),
            ],
          ],
        ),
      );
}

/// Paging footer. It only ever asks the controller for the next cursor the *server* issued; there
/// is no client-side windowing in this panel.
final class OmAdminPager extends StatelessWidget {
  const OmAdminPager({
    super.key,
    required this.loadedCount,
    required this.hasMore,
    required this.isLoading,
    required this.onLoadMore,
    this.onRefresh,
    this.totalEstimate,
  });

  final int loadedCount;
  final bool hasMore;
  final bool isLoading;
  final VoidCallback onLoadMore;
  final VoidCallback? onRefresh;
  final int? totalEstimate;

  @override
  Widget build(BuildContext context) {
    final total = totalEstimate;
    return Padding(
      padding: const EdgeInsets.only(top: OmSpacing.md),
      child: Row(
        children: <Widget>[
          Expanded(
            child: OmText(
              total == null
                  ? '$loadedCount rows loaded'
                  : '$loadedCount of about $total rows loaded',
              variant: OmTextVariant.caption,
            ),
          ),
          if (onRefresh != null) ...<Widget>[
            OmButton(
              label: 'Refresh',
              variant: OmButtonVariant.ghost,
              size: OmButtonSize.small,
              onPressed: isLoading ? null : onRefresh,
            ),
            const SizedBox(width: OmSpacing.sm),
          ],
          if (hasMore)
            OmButton(
              label: 'Load more',
              variant: OmButtonVariant.secondary,
              size: OmButtonSize.small,
              loading: isLoading,
              onPressed: isLoading ? null : onLoadMore,
            )
          else if (loadedCount > 0)
            const OmText('End of results', variant: OmTextVariant.caption),
        ],
      ),
    );
  }
}

/// Search + filter strip. Stacks into a column under the laptop breakpoint so filters cannot push
/// the page sideways.
final class OmAdminFilterBar extends StatelessWidget {
  const OmAdminFilterBar({
    super.key,
    this.searchController,
    this.searchHint = 'Search',
    this.onSearch,
    this.children = const <Widget>[],
    this.trailing,
  });

  final TextEditingController? searchController;
  final String searchHint;
  final ValueChanged<String>? onSearch;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final compact = context.screenWidth < OmBreakpoints.laptop;
    final search = searchController == null
        ? null
        : OmTextField(
            label: searchHint,
            controller: searchController,
            hint: searchHint,
            prefixIcon: Icons.search,
            onChanged: onSearch,
            onSubmitted: onSearch,
          );

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          if (search != null) ...<Widget>[search, const SizedBox(height: OmSpacing.sm)],
          for (final child in children)
            Padding(
              padding: const EdgeInsets.only(bottom: OmSpacing.sm),
              child: child,
            ),
          if (trailing != null)
            Align(alignment: Alignment.centerLeft, child: trailing!),
        ],
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(width: 300, child: search ?? const SizedBox.shrink()),
        const SizedBox(width: OmSpacing.md),
        Expanded(
          child: Wrap(
            spacing: OmSpacing.md,
            runSpacing: OmSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: children,
          ),
        ),
        const SizedBox(width: OmSpacing.md),
        if (trailing != null) trailing!,
      ],
    );
  }
}

/// Explains *why* a control is restricted, in the same voice on every screen.
///
/// The text is the point: a silently hidden button teaches an operator nothing, while a labelled
/// one names the role and states that the server — not this page — decides.
final class OmAdminNotice extends StatelessWidget {
  const OmAdminNotice({
    super.key,
    required this.message,
    this.tone = OmTone.info,
    this.icon,
    this.title,
  });

  factory OmAdminNotice.requiresRole(String needed, {Key? key, String? title}) =>
      OmAdminNotice(
        key: key,
        title: title ?? 'Restricted action',
        tone: OmTone.warning,
        icon: Icons.lock_outline,
        message: 'This needs the $needed role. The server re-checks it on every write, so this '
            'page hiding or showing the control is a convenience, not the permission.',
      );

  final String message;
  final OmTone tone;
  final IconData? icon;
  final String? title;

  Color get _accent => switch (tone) {
        OmTone.danger => OmColors.danger,
        OmTone.warning => OmColors.warning,
        OmTone.success => OmColors.success,
        OmTone.gold => OmColors.gold,
        OmTone.info => OmColors.info,
        OmTone.neutral => OmColors.textMuted,
      };

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(OmSpacing.md),
        decoration: BoxDecoration(
          color: _accent.withValues(alpha: 0.07),
          borderRadius: OmRadius.smAll,
          border: Border.all(color: _accent.withValues(alpha: 0.45)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(icon ?? Icons.info_outline, size: 18, color: _accent),
            const SizedBox(width: OmSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (title != null) ...<Widget>[
                    OmText(title!, variant: OmTextVariant.label, color: _accent),
                    const SizedBox(height: OmSpacing.xs),
                  ],
                  OmText(message, variant: OmTextVariant.caption, maxLines: null),
                ],
              ),
            ),
          ],
        ),
      );
}

/// Page chrome for every admin screen: heading, one row of actions, body capped by the content
/// width token so a 27-inch monitor shows a centred column.
final class OmAdminPage extends StatelessWidget {
  const OmAdminPage({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.actions = const <Widget>[],
    this.eyebrow,
  });

  final String title;
  final Widget child;
  final String? subtitle;
  final List<Widget> actions;
  final String? eyebrow;

  @override
  Widget build(BuildContext context) => OmContentWidth(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmSectionHeader(
              title: title,
              eyebrow: eyebrow ?? 'Admin',
              subtitle: subtitle,
            ),
            if (actions.isNotEmpty) ...<Widget>[
              const SizedBox(height: OmSpacing.md),
              Wrap(
                spacing: OmSpacing.sm,
                runSpacing: OmSpacing.sm,
                children: actions,
              ),
            ],
            const SizedBox(height: OmSpacing.lg),
            child,
            const SizedBox(height: OmSpacing.xxl),
          ],
        ),
      );
}

/// Two columns of fields on a wide screen, one column below it.
///
/// A grid with a fixed aspect ratio was the obvious choice and is wrong here: form fields have
/// different heights (a helper line, an error line, a multi-line note) and a fixed ratio clips
/// them. Pairing with `Expanded` keeps every field full-height-of-its-own.
final class OmAdminFormGrid extends StatelessWidget {
  const OmAdminFormGrid({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final twoColumns = context.screenWidth >= OmBreakpoints.laptop;
    if (!twoColumns) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          for (final child in children)
            Padding(padding: const EdgeInsets.only(bottom: OmSpacing.md), child: child),
        ],
      );
    }
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i += 2) {
      final left = children[i];
      final right = i + 1 < children.length ? children[i + 1] : const SizedBox.shrink();
      rows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: OmSpacing.md),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(child: left),
                const SizedBox(width: OmSpacing.md),
                Expanded(child: right),
              ],
            ),
          ),
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Labelled key/value block for detail headers.
final class OmAdminMeta extends StatelessWidget {
  const OmAdminMeta({
    super.key,
    required this.label,
    required this.value,
    this.selectable = false,
    this.emphasise = false,
  });

  final String label;
  final String value;
  final bool selectable;
  final bool emphasise;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          OmText(label.toUpperCase(), variant: OmTextVariant.label),
          const SizedBox(height: OmSpacing.xs),
          OmText(
            value,
            variant: emphasise ? OmTextVariant.bodyStrong : OmTextVariant.body,
            selectable: selectable,
            maxLines: 6,
          ),
        ],
      );
}

/// Wrap of [OmAdminMeta] blocks sized by the available width, not the screen width, so it behaves
/// inside a drawer or a split column.
final class OmAdminMetaRow extends StatelessWidget {
  const OmAdminMetaRow({super.key, required this.entries});

  final List<OmAdminMeta> entries;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final perRow = width >= 1100
              ? 4
              : width >= 760
                  ? 3
                  : width >= 460
                      ? 2
                      : 1;
          final itemWidth =
              ((width - OmSpacing.lg * (perRow - 1)) / perRow).clamp(140.0, 340.0);
          return Wrap(
            spacing: OmSpacing.lg,
            runSpacing: OmSpacing.md,
            children: entries
                .map((e) => SizedBox(width: itemWidth, child: e))
                .toList(growable: false),
          );
        },
      );
}

/// Heading + body block inside a page.
final class OmAdminSection extends StatelessWidget {
  const OmAdminSection({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.action,
    this.onActionTap,
    this.spaceAbove = OmSpacing.lg,
  });

  final String title;
  final Widget child;
  final String? subtitle;
  final String? action;
  final VoidCallback? onActionTap;
  final double spaceAbove;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: spaceAbove),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmSectionHeader(
              title: title,
              subtitle: subtitle,
              action: action,
              onActionTap: onActionTap,
            ),
            const SizedBox(height: OmSpacing.md),
            child,
          ],
        ),
      );
}

/// Confirm-before-write. Privileged mutations pass through here because the audit row and the
/// Cloud Function both need an explicit human intent.
Future<bool> omConfirmAdminAction({
  required BuildContext context,
  required String title,
  required String message,
  String confirmLabel = 'Confirm',
  bool destructive = false,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (dialogContext.screenWidth - 96).clamp(240.0, 460.0),
        ),
        child: Text(message, style: dialogContext.omText.body),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: const Text('Cancel'),
        ),
        OmButton(
          label: confirmLabel,
          variant: destructive ? OmButtonVariant.danger : OmButtonVariant.primary,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
  return result ?? false;
}

/// Asks for the reason a privileged action needs, and refuses to continue without one.
///
/// [omAdminReasonMaxLength] is the local cap on the note; the server may store less. A blank
/// reason would make the audit log unreviewable, so it is a validation error rather than an
/// optional field.
const int omAdminReasonMaxLength = 400;
Future<String?> omPromptForReason({
  required BuildContext context,
  required String label,
  String title = 'Reason',
  bool required = true,
}) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  bool accepted = false;
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: (dialogContext.screenWidth - 96).clamp(240.0, 460.0),
        ),
        child: Form(
          key: formKey,
          child: OmTextField(
            label: label,
            controller: controller,
            maxLines: 3,
            required: required,
            maxLength: omAdminReasonMaxLength,
            validator: (value) =>
                required && (value == null || value.trim().isEmpty)
                    ? 'A reason is required — it is written to the audit log'
                    : null,
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Cancel'),
        ),
        OmButton(
          label: 'Continue',
          onPressed: () {
            if (formKey.currentState?.validate() ?? false) {
              accepted = true;
              Navigator.of(dialogContext).pop();
            }
          },
        ),
      ],
    ),
  );
  final text = controller.text.trim();
  controller.dispose();
  if (!accepted) return null;
  return text;
}

/// Read-only date field that opens the platform picker.
///
/// Admin filters and sale windows need calendar dates, and a free-typed `2/3/2026` parses
/// differently depending on who typed it. A null value means "not set", which the list screens
/// send to the repository as null rather than as a fabricated bound.
final class OmAdminDateField extends StatelessWidget {
  const OmAdminDateField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.helper,
    this.initialDate,
  });

  final String label;
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final String? helper;
  final DateTime? initialDate;

  Future<void> _pick(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: value ?? initialDate ?? now,
      firstDate: now.subtract(const Duration(days: 365 * 4)),
      lastDate: now.add(const Duration(days: 365 * 3)),
      helpText: label,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) => OmTextField(
        label: label,
        readOnly: true,
        initialValue: value == null
            ? ''
            : '${value!.day.toString().padLeft(2, '0')}/'
                '${value!.month.toString().padLeft(2, '0')}/${value!.year}',
        hint: 'Not set',
        helper: helper,
        suffix: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (value != null)
              OmIconButton(
                icon: Icons.clear,
                tooltip: 'Clear $label',
                size: 32,
                onPressed: () => onChanged(null),
              ),
            OmIconButton(
              icon: Icons.event_outlined,
              tooltip: 'Pick a date',
              size: 32,
              onPressed: () => _pick(context),
            ),
          ],
        ),
      );
}

/// Shows a generated CSV before it leaves the panel.
///
/// The text is selectable and on screen *with* the copy button, so an export is verifiable rather
/// than "it probably worked". Clipboard failure is reported, never swallowed: on Flutter Web a
/// blocked permission prompt is a real outcome the operator needs to see.
Future<void> omShowAdminCsv(
  BuildContext context, {
  required String title,
  required String csv,
  required int totalRows,
}) async {
  final exported = OmCsv.countRows(csv);
  await showDialog<void>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: SizedBox(
        width: (dialogContext.screenWidth - 96).clamp(260.0, 720.0),
        height: 380,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            OmText(
              exported >= totalRows
                  ? '$exported rows. Copy the text below, or save it from the sheet.'
                  : OmCsv.truncatedMessage(totalRows, exported),
              variant: OmTextVariant.caption,
              maxLines: 4,
            ),
            const SizedBox(height: OmSpacing.sm),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(OmSpacing.sm),
                decoration: BoxDecoration(
                  color: OmColors.cream,
                  borderRadius: OmRadius.smAll,
                  border: Border.all(color: OmColors.line),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(
                    csv,
                    style: dialogContext.omText.caption,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(),
          child: const Text('Close'),
        ),
        OmButton(
          label: 'Copy CSV',
          icon: Icons.copy_all_outlined,
          onPressed: () async {
            final ok = await adminCopyCsv(csv);
            if (!ok && dialogContext.mounted) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(
                  content: Text('The browser refused clipboard access. Select and copy manually.'),
                ),
              );
            }
          },
        ),
      ],
    ),
  );
}
