import 'package:flutter/material.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';

/// The "media storage not configured" state, stated once and stated exactly.
///
/// An unconfigured bucket is a deployment condition, not an error the admin caused, so this reads as
/// an explanation with the missing `--dart-define` key names rather than as a red failure. Upload
/// controls stay visible but disabled, because a hidden control teaches nobody that media exists.
final class OmMediaStorageNotice extends StatelessWidget {
  const OmMediaStorageNotice({
    super.key,
    this.title = 'Media storage is not configured',
    this.message,
    this.icon = Icons.cloud_off,
    this.compact = false,
    this.onRetry,
  });

  final String title;
  final String? message;
  final IconData icon;
  final bool compact;
  final VoidCallback? onRetry;

  /// The canonical text: which key is missing, or why Supabase refused to initialise.
  static String get defaultMessage => MediaConfig.statusMessage;

  static List<String> get missingKeys => MediaConfig.missingKeyNames;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final detail = message ?? MediaConfig.statusMessage;
    return OmCard(
      padding: EdgeInsets.all(compact ? OmSpacing.md : OmSpacing.lg),
      borderColor: OmColors.gold.withValues(alpha: 0.45),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, color: OmColors.gold, size: compact ? 20 : 26),
              const SizedBox(width: OmSpacing.sm),
              Expanded(child: Text(title, style: styles.bodyStrong)),
            ],
          ),
          const SizedBox(height: OmSpacing.sm),
          Text(detail, style: styles.muted),
          if (MediaConfig.missingKeyNames.isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.sm),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.xs,
              children: <Widget>[
                for (final key in MediaConfig.missingKeyNames)
                  OmBadge(label: key, tone: OmTone.warning, dense: true),
              ],
            ),
          ],
          if (onRetry != null) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            OmButton(
              label: 'Check again',
              variant: OmButtonVariant.outline,
              size: OmButtonSize.small,
              onPressed: onRetry,
            ),
          ],
        ],
      ),
    );
  }
}
