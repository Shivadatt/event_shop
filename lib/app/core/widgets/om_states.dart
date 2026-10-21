import 'package:flutter/material.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

/// Shimmer-free block skeleton: a full shimmer layer per list is a repaint storm on low-end
/// laptops, and the shape alone communicates "content is coming".
final class OmSkeleton extends StatelessWidget {
  const OmSkeleton({
    super.key,
    this.height = 16,
    this.width = double.infinity,
    this.radius,
  });

  final double height;
  final double width;
  final BorderRadius? radius;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: isDark ? OmColors.surfaceElevated : OmColors.line,
        borderRadius: radius ?? OmRadius.smAll,
      ),
    );
  }
}

/// Card-shaped placeholder matching the real product card's proportions, so a grid does not
/// reflow when data arrives.
final class OmProductCardSkeleton extends StatelessWidget {
  const OmProductCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) => OmCard(
        padding: EdgeInsets.zero,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            AspectRatio(
              aspectRatio: 1,
              child: OmSkeleton(radius: OmRadius.mdAll),
            ),
            const Padding(
              padding: EdgeInsets.all(OmSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  OmSkeleton(height: 14, width: 140),
                  SizedBox(height: OmSpacing.sm),
                  OmSkeleton(height: 12, width: 90),
                  SizedBox(height: OmSpacing.md),
                  OmSkeleton(height: 18, width: 70),
                ],
              ),
            ),
          ],
        ),
      );
}

final class OmLoading extends StatelessWidget {
  const OmLoading({super.key, this.message});

  final String? message;

  @override
  Widget build(BuildContext context) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const SizedBox(
              height: 26,
              width: 26,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            if (message != null) ...<Widget>[
              const SizedBox(height: OmSpacing.md),
              Text(message!, style: context.omText.caption),
            ],
          ],
        ),
      );
}

final class OmEmptyState extends StatelessWidget {
  const OmEmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.actionLabel,
    this.onAction,
    this.compact = false,
  });

  final String title;
  final String? message;
  final IconData icon;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool compact;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: EdgeInsets.all(compact ? OmSpacing.md : OmSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: compact ? 30 : 44, color: context.omText.muted.color),
              const SizedBox(height: OmSpacing.md),
              Text(
                title,
                textAlign: TextAlign.center,
                style: compact ? context.omText.bodyStrong : context.omText.h3,
              ),
              if (message != null) ...<Widget>[
                const SizedBox(height: OmSpacing.sm),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: context.omText.muted,
                  ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...<Widget>[
                const SizedBox(height: OmSpacing.lg),
                OmButton(
                  label: actionLabel!,
                  variant: OmButtonVariant.outline,
                  onPressed: onAction,
                ),
              ],
            ],
          ),
        ),
      );

  /// The three empties the storefront hits most, so wording stays identical everywhere.
  static OmEmptyState noProducts({VoidCallback? onReset}) => OmEmptyState(
        title: 'No products match these filters',
        message: 'Try widening the price range or clearing a category.',
        icon: Icons.search_off,
        actionLabel: onReset == null ? null : 'Clear filters',
        onAction: onReset,
      );

  static OmEmptyState emptyCart({VoidCallback? onBrowse}) => OmEmptyState(
        title: 'Your cart is empty',
        message: 'Add packs, balloons or decor and quantity discounts apply automatically.',
        icon: Icons.shopping_bag_outlined,
        actionLabel: onBrowse == null ? null : 'Browse catalogue',
        onAction: onBrowse,
      );

  static OmEmptyState emptyWishlist() => const OmEmptyState(
        title: 'Nothing saved yet',
        message: 'Tap the heart on any product to keep it here.',
        icon: Icons.favorite_border,
      );

  static OmEmptyState noOrders({VoidCallback? onBrowse}) => OmEmptyState(
        title: 'No orders yet',
        message: 'Your placed orders and their live status will appear here.',
        icon: Icons.receipt_long_outlined,
        actionLabel: onBrowse == null ? null : 'Start shopping',
        onAction: onBrowse,
      );
}

final class OmErrorState extends StatelessWidget {
  const OmErrorState({
    super.key,
    required this.failure,
    this.onRetry,
    this.compact = false,
  });

  final OmFailure failure;
  final VoidCallback? onRetry;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final icon = switch (failure) {
      NetworkFailure() => Icons.wifi_off_rounded,
      PermissionFailure() => Icons.lock_outline,
      AuthFailure() => Icons.person_off_outlined,
      NotFoundFailure() => Icons.search_off,
      ConflictFailure() => Icons.update,
      ValidationFailure() => Icons.error_outline,
      MediaFailure() => Icons.broken_image_outlined,
      _ => Icons.report_problem_outlined,
    };
    final retryable = onRetry != null && failure.isRetryable;

    return OmEmptyState(
      compact: compact,
      icon: icon,
      title: failure.message,
      message: failure.code == null
          ? null
          : 'Reference: ${failure.code}${failure is ConflictFailure ? ' — review the updated totals before paying.' : ''}',
      actionLabel: retryable ? 'Try again' : null,
      onAction: retryable ? onRetry : null,
    );
  }
}

/// One place to decide "loading, error, empty, or content". Screens that hand-roll four
/// if-branches drift; this one does not.
///
/// [hasLoaded] is what separates "the backend has not answered yet" from "the backend answered with
/// nothing", and it is why `OmEmptyState` never appears as a first frame: a request that neither
/// succeeded nor failed would otherwise masquerade as an empty store. Content outranks the failure
/// and the spinner, so a background refresh that keeps the rows already on screen does not wipe
/// them.
final class OmStateView<T> extends StatelessWidget {
  const OmStateView({
    super.key,
    required this.hasLoaded,
    required this.value,
    required this.builder,
    this.loading = false,
    this.isEmpty = false,
    this.failure,
    this.onRetry,
    this.empty,
    this.skeleton,
    this.compact = false,
  });

  final bool hasLoaded;
  final bool loading;
  final T? value;
  final bool isEmpty;
  final OmFailure? failure;
  final VoidCallback? onRetry;
  final Widget Function(BuildContext context, T value) builder;
  final Widget? empty;
  final Widget? skeleton;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final data = value;
    if (data != null && !isEmpty) return builder(context, data);
    final error = failure;
    if (error != null) {
      return OmErrorState(failure: error, onRetry: onRetry, compact: compact);
    }
    if (loading || !hasLoaded) return skeleton ?? const OmLoading();
    return empty ?? OmEmptyState(title: 'Nothing here yet', compact: compact);
  }
}
