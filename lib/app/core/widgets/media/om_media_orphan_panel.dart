import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/media/media_config.dart';
import 'package:om_events/app/core/widgets/media/om_media_storage_notice.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_states.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/repositories/media_repository.dart';
import 'package:om_events/data/repositories/supabase/supabase_media_repository.dart';

/// Bucket cleanup report: what is in the bucket, what the ledger and the documents claim, and what
/// is therefore unreferenced.
///
/// Two rules shape this panel. A scan never deletes anything — it only reports. Deletion needs an
/// explicit confirmation over the exact list the scan produced, and the repository re-reads the
/// reference set before touching the bucket, so an object that became live between the scan and the
/// click is refused rather than silently removed.
final class OmMediaOrphanPanel extends StatefulWidget {
  const OmMediaOrphanPanel({super.key, this.repository});

  final MediaRepository? repository;

  @override
  State<OmMediaOrphanPanel> createState() => _OmMediaOrphanPanelState();
}

class _OmMediaOrphanPanelState extends State<OmMediaOrphanPanel> {
  OrphanScan? _scan;
  String? _error;
  String? _result;
  bool _busy = false;
  final Set<String> _selected = <String>{};

  MediaRepository? get _repository {
    if (widget.repository != null) return widget.repository;
    return Get.isRegistered<MediaRepository>() ? Get.find<MediaRepository>() : null;
  }

  /// Bucket cleanup is a port on the Supabase implementation only, so a repository that is not one
  /// (the stub, or a Firestore-only build) reports no cleanup rather than failing. The local is
  /// `Object?` deliberately: `is` refines `Object?` to `MediaOrphanControl`, whereas testing a
  /// `MediaRepository?` against an unrelated interface leaves the static type unchanged.
  MediaOrphanControl? get _control {
    final Object? repository = _repository;
    return repository is MediaOrphanControl ? repository : null;
  }

  @override
  void dispose() {
    _selected.clear();
    super.dispose();
  }

  Future<void> _scanNow() async {
    final control = _control;
    if (control == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
      _scan = null;
      _selected.clear();
    });
    try {
      final scan = await control.scanOrphans();
      if (!mounted) return;
      setState(() {
        _scan = scan;
        _busy = false;
      });
    } on OmFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        _error = failure.message;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'The scan could not run (${error.runtimeType}).';
        _busy = false;
      });
    }
  }

  Future<void> _confirmAndDelete() async {
    final control = _control;
    final scan = _scan;
    if (control == null || scan == null || _selected.isEmpty) return;
    final paths = _selected.toList(growable: false);
    final confirmed = await _askForConfirmation(paths);
    if (confirmed != true || !mounted) return;

    setState(() => _busy = true);
    try {
      final deleted = await control.deleteConfirmed(paths);
      if (!mounted) return;
      setState(() {
        _result = '${deleted.length} unreferenced object(s) deleted. '
            'The bucket and the media_objects ledger are back in sync.';
        _scan = null;
        _selected.clear();
        _busy = false;
      });
    } on OmFailure catch (failure) {
      if (!mounted) return;
      // A refusal here is the safety net working: something became referenced between the scan and
      // the confirmation. The admin must re-scan, not force the delete.
      setState(() {
        _error = failure.message;
        _busy = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = 'Deletion failed (${error.runtimeType}).';
        _busy = false;
      });
    }
  }

  Future<bool?> _askForConfirmation(List<String> paths) => showDialog<bool>(
        context: context,
        builder: (context) => _OrphanConfirmDialog(paths: paths, note: _control?.orphanScanNote),
      );

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final repository = _repository;
    final control = _control;

    if (repository == null || control == null) {
      return OmMediaStorageNotice(
        title: 'Bucket cleanup',
        message: 'This route has no Supabase media repository bound, so the bucket cannot be '
            'inspected. ${MediaConfig.statusMessage}',
      );
    }
    if (!repository.isConfigured) {
      return OmMediaStorageNotice(title: 'Bucket cleanup', message: MediaConfig.statusMessage);
    }

    final scan = _scan;
    final candidates = scan?.candidates ?? const <String>[];
    // Read once, before the widget list: a list literal cannot contain a declaration. This is the
    // scan's explanation of why deletion is off the table, when it is.
    final scanNote = control.orphanScanNote;

    return OmCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const OmSectionHeader(
            title: 'Bucket cleanup',
            subtitle: 'Compares the bucket contents against the media_objects ledger and every '
                'document that can hold an image. Reporting only — nothing is deleted until you '
                'confirm this exact list.',
          ),
          const SizedBox(height: OmSpacing.md),
          Wrap(
            spacing: OmSpacing.sm,
            runSpacing: OmSpacing.sm,
            children: <Widget>[
              OmButton(
                label: scan == null ? 'Run scan' : 'Scan again',
                icon: Icons.refresh,
                variant: OmButtonVariant.secondary,
                loading: _busy,
                busyLabel: 'Working',
                onPressed: _busy ? null : _scanNow,
              ),
              if (scan != null && candidates.isNotEmpty)
                OmButton(
                  label: 'Delete ${_selected.length} selected',
                  variant: OmButtonVariant.danger,
                  icon: Icons.delete_forever_outlined,
                  loading: _busy,
                  busyLabel: 'Deleting',
                  onPressed: scan.canDelete && _selected.isNotEmpty && !_busy
                      ? _confirmAndDelete
                      : null,
                ),
            ],
          ),
          if (scan == null && (_error ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            Text(_error!, style: styles.muted.copyWith(color: OmColors.danger)),
          ],
          if (scan != null) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            Wrap(
              spacing: OmSpacing.sm,
              runSpacing: OmSpacing.sm,
              children: <Widget>[
                OmBadge(label: '${scan.objects.length} in bucket'),
                OmBadge(label: '${scan.referencedPaths.length} referenced', tone: OmTone.info),
                OmBadge(
                  label: '${candidates.length} unreferenced',
                  tone: candidates.isEmpty ? OmTone.success : OmTone.warning,
                ),
                OmBadge(
                  label: scan.canDelete ? 'Deletion available' : 'Deletion locked',
                  tone: scan.canDelete ? OmTone.success : OmTone.danger,
                ),
              ],
            ),
            const SizedBox(height: OmSpacing.sm),
            if (candidates.isEmpty)
              const OmEmptyState(
                compact: true,
                title: 'Nothing to clean up',
                message: 'Every object in the bucket is referenced by a live document or ledger row.',
                icon: Icons.task_alt,
              )
            else ...<Widget>[
              Row(
                children: <Widget>[
                  Text('Candidates', style: styles.bodyStrong),
                  const Spacer(),
                  OmButton(
                    label: _selected.length == candidates.length ? 'Clear selection' : 'Select all',
                    variant: OmButtonVariant.ghost,
                    size: OmButtonSize.small,
                    onPressed: () => setState(() {
                      if (_selected.length == candidates.length) {
                        _selected.clear();
                      } else {
                        _selected
                          ..clear()
                          ..addAll(candidates);
                      }
                    }),
                  ),
                ],
              ),
              const SizedBox(height: OmSpacing.xs),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: SingleChildScrollView(
                  child: Column(
                    children: <Widget>[
                      for (final path in candidates)
                        CheckboxListTile(
                          value: _selected.contains(path),
                          visualDensity: VisualDensity.compact,
                          controlAffinity: ListTileControlAffinity.leading,
                          title: Text(path, style: styles.muted),
                          onChanged: (checked) => setState(() {
                            if (checked ?? false) {
                              _selected.add(path);
                            } else {
                              _selected.remove(path);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ),
            ],
            if (scanNote != null) ...<Widget>[
              const SizedBox(height: OmSpacing.sm),
              Text(scanNote, style: styles.muted.copyWith(color: OmColors.warning)),
            ],
          ],
          if ((_result ?? '').isNotEmpty) ...<Widget>[
            const SizedBox(height: OmSpacing.md),
            Text(_result!, style: styles.muted),
          ],
        ],
      ),
    );
  }
}

/// Explicit confirmation: the list is shown, the count is stated, and a checkbox must be ticked.
/// A bare "Are you sure?" is not consent to delete bytes a live page might still be reading.
final class _OrphanConfirmDialog extends StatefulWidget {
  const _OrphanConfirmDialog({required this.paths, this.note});

  final List<String> paths;
  final String? note;

  @override
  State<_OrphanConfirmDialog> createState() => _OrphanConfirmDialogState();
}

class _OrphanConfirmDialogState extends State<_OrphanConfirmDialog> {
  bool _acknowledged = false;

  @override
  Widget build(BuildContext context) {
    final styles = context.omText;
    final shown = widget.paths.take(12).toList(growable: false);
    return AlertDialog(
      title: Text('Delete ${widget.paths.length} unreferenced object(s)?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(
              'This removes the files from the bucket permanently. The scan re-checks every '
              'reference before deleting, so if any of these became live in the meantime the whole '
              'batch is refused.',
              style: styles.muted,
            ),
            const SizedBox(height: OmSpacing.md),
            for (final path in shown)
              Text(path, style: styles.caption, overflow: TextOverflow.ellipsis),
            if (widget.paths.length > shown.length)
              Text('… and ${widget.paths.length - shown.length} more', style: styles.caption),
            if (widget.note != null) ...<Widget>[
              const SizedBox(height: OmSpacing.md),
              Text(widget.note!, style: styles.muted),
            ],
            const SizedBox(height: OmSpacing.sm),
            CheckboxListTile(
              value: _acknowledged,
              dense: true,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('I understand these files cannot be recovered from the app'),
              onChanged: (value) => setState(() => _acknowledged = value ?? false),
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
        OmButton(
          label: 'Delete permanently',
          variant: OmButtonVariant.danger,
          onPressed: _acknowledged ? () => Navigator.of(context).pop(true) : null,
        ),
      ],
    );
  }
}
