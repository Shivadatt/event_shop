import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/features/storefront/common/store_shell.dart';

/// Chrome shared by the four auth screens: a narrow centred card so a credential form never
/// stretches across a desktop viewport, plus the two notices every one of them must be able to
/// show (a presentable failure and the blocked-account warning).
final class AuthShell extends StatelessWidget {
  const AuthShell({
    super.key,
    required this.title,
    required this.eyebrow,
    required this.child,
    this.intro,
    this.notice,
    this.failure,
    this.footer = const <Widget>[],
  });

  final String title;
  final String eyebrow;
  final Widget child;
  final String? intro;
  final String? notice;
  final OmFailure? failure;
  final List<Widget> footer;

  @override
  Widget build(BuildContext context) {
    return StoreScaffold(
      title: title,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: OmSpacing.xl),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: OmCard(
              elevated: true,
              padding: const EdgeInsets.all(OmSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  OmText(eyebrow.toUpperCase(), variant: OmTextVariant.label),
                  const SizedBox(height: OmSpacing.xs),
                  OmText(title, variant: OmTextVariant.h2),
                  if (intro != null) ...<Widget>[
                    const SizedBox(height: OmSpacing.sm),
                    OmText(intro!, variant: OmTextVariant.muted, overflow: TextOverflow.visible),
                  ],
                  if (notice != null) ...<Widget>[
                    const SizedBox(height: OmSpacing.md),
                    OmCard(
                      borderColor: OmColors.warning,
                      padding: const EdgeInsets.all(OmSpacing.sm),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Icon(Icons.person_off_outlined,
                              size: 18, color: OmColors.warning),
                          const SizedBox(width: OmSpacing.sm),
                          Expanded(
                            child: OmText(notice!, variant: OmTextVariant.caption,
                                overflow: TextOverflow.visible),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: OmSpacing.lg),
                  child,
                  if (failure != null) ...<Widget>[
                    const SizedBox(height: OmSpacing.md),
                    OmCard(
                      borderColor: OmColors.danger,
                      padding: const EdgeInsets.all(OmSpacing.sm),
                      child: OmText(failure!.message,
                          variant: OmTextVariant.caption,
                          color: OmColors.danger,
                          overflow: TextOverflow.visible),
                    ),
                  ],
                  if (footer.isNotEmpty) ...<Widget>[
                    const SizedBox(height: OmSpacing.md),
                    OmDivider(space: OmSpacing.sm),
                    ...footer,
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Password visibility control. A text field the user cannot inspect is a sign-in defect, but the
/// eye icon needs a label a screen reader can announce.
final class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.visible,
    required this.onPressed,
  });

  final bool visible;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => IconButton(
        icon: Icon(visible ? Icons.visibility_off_outlined : Icons.visibility_outlined),
        tooltip: visible ? 'Hide password' : 'Show password',
        onPressed: onPressed,
      );
}
