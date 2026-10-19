import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:om_events/app/core/widgets/media/om_image_picker_field.dart';
import 'package:om_events/app/core/widgets/media/om_media_storage_notice.dart';
import 'package:om_events/app/core/widgets/om_buttons.dart';
import 'package:om_events/app/core/widgets/om_inputs.dart';
import 'package:om_events/app/core/widgets/om_surfaces.dart';
import 'package:om_events/app/theme/om_tokens.dart';
import 'package:om_events/app/theme/om_typography.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/features/admin/categories/categories_controller.dart';
import 'package:om_events/features/admin/shared/admin_widgets.dart';

/// Create / edit panel for one category.
///
/// It sits above the tree rather than on its own route because `OmRoutes` exposes no
/// `/admin/categories/:id` constant and inventing a route string here would break the "routes come
/// from `OmRoutes` only" rule. The panel is keyed by the selected id from the parent view, so
/// switching rows cannot leave the previous draft's text in these fields.
final class CategoryEditPanel extends StatelessWidget {
  const CategoryEditPanel({super.key, required this.list, required this.editor});

  final CategoriesController list;
  final CategoryEditController editor;

  @override
  Widget build(BuildContext context) => Obx(() {
        final draft = editor.draft.value;
        if (draft == null) {
          return const OmAdminSection(
            title: 'Category editor',
            spaceAbove: 0,
            child: OmCard(
              child: OmText(
                'Pick a category below to edit it, or create a new one.',
                variant: OmTextVariant.caption,
              ),
            ),
          );
        }
        final options = list.parentOptions(draft.id.isEmpty ? null : draft.id);
        return OmAdminSection(
          title: editor.isNew ? 'New category' : 'Editing ${draft.name}',
          spaceAbove: 0,
          subtitle: editor.isNew
              ? 'A new category is invisible until it is active and a product points at it.'
              : '${draft.productCount} product(s) currently assigned (count maintained by the '
                  'server).',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              Obx(() {
                final issues = editor.issues;
                if (issues.isEmpty) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(bottom: OmSpacing.md),
                  child: OmAdminNotice(
                    tone: OmTone.danger,
                    icon: Icons.report_gmailerrorred_outlined,
                    title: '${issues.length} thing(s) block this save',
                    message: issues.map((i) => '• $i').join('\n'),
                  ),
                );
              }),
              OmAdminFormGrid(
                children: <Widget>[
                  OmTextField(
                    label: 'Name',
                    required: true,
                    initialValue: draft.name,
                    onChanged: editor.setName,
                  ),
                  _SlugField(editor: editor, draft: draft),
                  OmDropdown<String>(
                    label: 'Parent',
                    value: draft.parentId ?? '',
                    hint: 'Top level',
                    items: <String>['', ...options.map((c) => c.id)],
                    itemLabel: (id) =>
                        id.isEmpty ? 'Top level (no parent)' : list.labelFor(id),
                    onChanged: editor.setParent,
                  ),
                  _OrderField(draft: draft, onChanged: editor.setOrder),
                  OmTextField(
                    label: 'Short description',
                    initialValue: draft.description,
                    maxLines: 3,
                    hint: 'Shown on the category landing page',
                    onChanged: editor.setDescription,
                  ),
                  OmTextField(
                    label: 'SEO title',
                    initialValue: draft.seoTitle,
                    onChanged: (value) => editor.setSeo(title: value),
                  ),
                  OmTextField(
                    label: 'SEO description',
                    initialValue: draft.seoDescription,
                    maxLines: 2,
                    helper: 'Falls back to the store default when empty.',
                    onChanged: (value) => editor.setSeo(description: value),
                  ),
                ],
              ),
              OmSwitchRow(
                label: 'Active',
                value: draft.isActive,
                description: 'Inactive categories disappear from the shop navigation.',
                onChanged: editor.setActive,
              ),
              OmSwitchRow(
                label: 'Feature on the home page',
                value: draft.isFeatured,
                onChanged: editor.setFeatured,
              ),
              const SizedBox(height: OmSpacing.md),
              if (draft.id.isEmpty)
                const OmAdminNotice(
                  tone: OmTone.warning,
                  icon: Icons.image_not_supported_outlined,
                  title: 'Image attaches after the first save',
                  message: 'Storage objects are filed under a category id. Save this category once '
                      'and the picker opens.',
                )
              else if (!editor.mediaConfigured)
                const OmMediaStorageNotice(compact: true)
              else
                OmImagePickerField(
                  label: 'Category image',
                  kind: MediaKind.category,
                  ownerId: draft.id,
                  entityKey: draft.slug.isEmpty ? draft.id : draft.slug,
                  existing: draft.images.isEmpty ? null : draft.images.first,
                  defaultAltText: draft.name,
                  onChanged: (ref, removed) {
                    editor.setImage(ref);
                    if (removed != null) editor.dropImage(removed);
                  },
                ),
              const SizedBox(height: OmSpacing.lg),
              Wrap(
                spacing: OmSpacing.sm,
                runSpacing: OmSpacing.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: <Widget>[
                  Obx(
                    () => OmButton(
                      label: editor.isNew ? 'Create category' : 'Save changes',
                      icon: Icons.save_outlined,
                      loading: editor.isSubmitting.value,
                      onPressed: editor.isSubmitting.value ? null : editor.save,
                    ),
                  ),
                  OmButton(
                    label: 'Close editor',
                    variant: OmButtonVariant.ghost,
                    onPressed: list.closeEditor,
                  ),
                  if (!editor.isNew)
                    _DeleteButton(controller: list, category: draft),
                ],
              ),
              const SizedBox(height: OmSpacing.md),
              const OmAdminNotice(
                message: 'Privileged write: role, slug collisions and product references are '
                    're-checked by the server on save, and the change is written to the audit log. '
                    'This panel hiding a button is never the permission.',
              ),
            ],
          ),
        );
      });
}

class _SlugField extends StatelessWidget {
  const _SlugField({required this.editor, required this.draft});

  final CategoryEditController editor;
  final Category draft;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          OmTextField(
            label: 'URL slug',
            initialValue: draft.slug,
            hint: 'gold-balloon-arches',
            helper: 'Used in /c/<slug>. Changing it breaks indexed links.',
            onChanged: editor.setSlug,
          ),
          Obx(() {
            if (editor.checkingSlug.value) {
              return const Padding(
                padding: EdgeInsets.only(top: OmSpacing.xs),
                child: OmText('Checking…', variant: OmTextVariant.caption),
              );
            }
            final note = editor.slugAvailability.value;
            if (note == null) return const SizedBox.shrink();
            return Padding(
              padding: const EdgeInsets.only(top: OmSpacing.xs),
              child: OmText(note, variant: OmTextVariant.caption, maxLines: 2),
            );
          }),
          OmButton(
            label: 'Check availability',
            size: OmButtonSize.small,
            variant: OmButtonVariant.ghost,
            onPressed: () => editor.checkSlug(draft.slug),
          ),
        ],
      );
}

class _OrderField extends StatefulWidget {
  const _OrderField({required this.draft, required this.onChanged});

  final Category draft;
  final ValueChanged<int> onChanged;

  @override
  State<_OrderField> createState() => _OrderFieldState();
}

class _OrderFieldState extends State<_OrderField> {
  late final TextEditingController _text =
      TextEditingController(text: '${widget.draft.order}');

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => OmNumberField(
        label: 'Display order',
        controller: _text,
        max: 9999,
        helper: 'Lower numbers appear first among siblings.',
        validator: (value) {
          final parsed = int.tryParse((value ?? '').trim());
          if ((value ?? '').trim().isEmpty) return 'Order is required';
          if (parsed == null) return 'Order must be a whole number';
          if (parsed < 0) return 'Order cannot be negative';
          return null;
        },
        onChanged: (value) => widget.onChanged(int.tryParse(value.trim()) ?? 0),
      );
}

/// Delete is refused here when a *local* read proves the server will refuse it, and the server
/// still decides: `productCount` is a trigger-maintained hint, not the authority.
class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.controller, required this.category});

  final CategoriesController controller;
  final Category category;

  Future<void> _run(BuildContext context) async {
    final blocked = controller.deleteBlockReason(category);
    if (blocked != null) {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Cannot delete yet'),
          content: Text(blocked),
          actions: <Widget>[
            OmButton(
              label: 'Understood',
              onPressed: () => Navigator.of(dialogContext).pop(),
            ),
          ],
        ),
      );
      return;
    }
    final ok = await omConfirmAdminAction(
      context: context,
      title: 'Delete ${category.name}?',
      message: 'The category document is removed. Products that referenced it keep their stored '
          'id, so the shop would show an unknown category until they are reassigned — that is why '
          'the server refuses this write while any product still points here.',
      confirmLabel: 'Delete category',
      destructive: true,
    );
    if (ok) await controller.remove(category);
  }

  @override
  Widget build(BuildContext context) => OmButton(
        label: 'Delete category',
        icon: Icons.delete_outline,
        variant: OmButtonVariant.danger,
        onPressed: () => _run(context),
      );
}
