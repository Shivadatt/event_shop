import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/utils/om_slug.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';
import 'package:om_events/data/repositories/media_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';

/// Category tree for the admin panel.
///
/// Reads are `CategoryRepository.tree()` — one bounded read of the whole collection, which is what
/// the storefront's navigation already uses. There is no pagination here because a category tree is
/// a single small document set and a partial tree would render a broken parent chooser.
final class CategoriesController extends AdminController {
  CategoriesController();

  final AdminRepository _admin = Get.find<AdminRepository>();
  final CategoryRepository _categories = Get.find<CategoryRepository>();

  final RxList<Category> all = <Category>[].obs;
  final RxString query = ''.obs;
  final RxBool showInactive = true.obs;

  /// Which row the editor is showing. `newDraft` marks a blank create rather than an edit, because
  /// the header text and the delete affordance differ and a real id must not be invented.
  final RxnString selectedId = RxnString();
  final RxBool newDraft = false.obs;

  bool get isEditingSelected => selectedId.value != null && !newDraft.value;
  bool get editorOpen => selectedId.value != null;

  @override
  void onInit() {
    super.onInit();
    load();
  }

  Future<void> load() => guard<bool>(() async {
        all.assignAll(await _categories.tree());
        return true;
      });

  /// Depth-first, display order. A flat alphabetical list of a two-level tree hides which category
  /// is whose parent, which is exactly the thing an operator editing `parentId` needs to see.
  List<Category> get visibleTree {
    final term = query.value.trim().toLowerCase();
    final byParent = <String?, List<Category>>{};
    for (final category in all) {
      final key = category.isTopLevel ? null : category.parentId;
      (byParent[key] ??= <Category>[]).add(category);
    }
    for (final list in byParent.values) {
      list.sort((a, b) {
        final byOrder = a.order.compareTo(b.order);
        return byOrder != 0 ? byOrder : a.name.toLowerCase().compareTo(b.name.toLowerCase());
      });
    }

    bool matches(Category category) {
      if (!showInactive.value && !category.isActive) return false;
      if (term.isEmpty) return true;
      return category.name.toLowerCase().contains(term) ||
          category.slug.toLowerCase().contains(term);
    }

    final out = <Category>[];
    void walk(String? parentId, int depth) {
      for (final category in byParent[parentId] ?? const <Category>[]) {
        // A matching child of a non-matching parent is still shown, so the row cannot disappear
        // from the tree while it is visible in the flat index.
        if (matches(category)) out.add(_withDepth(category, depth));
        walk(category.id, depth + 1);
      }
    }

    walk(null, 0);
    if (term.isEmpty) return out;
    // While searching, depth-first grouping is noise: show every hit once, alphabetically.
    final hits = all.where(matches).toList(growable: false)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return hits;
  }

  final Map<String, int> _depths = <String, int>{};

  /// Depth is carried out-of-band rather than added to [Category], which is a document model and
  /// must not grow view concerns.
  Category _withDepth(Category category, int depth) {
    _depths[category.id] = depth;
    return category;
  }

  int depthOf(String categoryId) => _depths[categoryId] ?? 0;

  Category? byId(String? id) {
    if (id == null) return null;
    for (final category in all) {
      if (category.id == id) return category;
    }
    return null;
  }

  String labelFor(String? id) {
    final category = byId(id);
    if (category == null) return id == null ? 'Top level' : 'Unknown category';
    return category.name;
  }

  bool get hasFilters => query.value.trim().isNotEmpty || !showInactive.value;

  void applyQuery(String value) => query.value = value;

  void toggleShowInactive(bool value) => showInactive.value = value;

  void clearFilters() {
    query.value = '';
    showInactive.value = true;
  }

  void select(Category category) {
    newDraft.value = false;
    selectedId.value = category.id;
  }

  void startNew() {
    newDraft.value = true;
    selectedId.value = 'new';
  }

  void closeEditor() {
    selectedId.value = null;
    newDraft.value = false;
  }

  /// Every id reachable from [categoryId] below it, used to keep a category from becoming its own
  /// descendant. The server also refuses a cycle; blocking it here stops an operator from
  /// discovering that only after a save.
  Set<String> descendantIds(String categoryId) {
    final found = <String>{categoryId};
    var grew = true;
    while (grew) {
      grew = false;
      for (final category in all) {
        final parent = category.parentId;
        if (parent != null && found.contains(parent) && !found.contains(category.id)) {
          found.add(category.id);
          grew = true;
        }
      }
    }
    return found;
  }

  /// Parent dropdown contents: everything except the draft itself and its own subtree.
  List<Category> parentOptions(String? editingId) {
    if (editingId == null || editingId.isEmpty || editingId == 'new') {
      return <Category>[...all]..sort((a, b) => a.name.compareTo(b.name));
    }
    final blocked = descendantIds(editingId);
    return <Category>[...all.where((c) => !blocked.contains(c.id))]
      ..sort((a, b) => a.name.compareTo(b.name));
  }

  /// Why a delete would be refused, or null when nothing local blocks it.
  ///
  /// `Category.productCount` is maintained by a Firestore trigger, so it is a hint about what the
  /// server will say — never the authority. The repository call below is the real gate; this only
  /// spares an operator a write that is certain to fail.
  String? deleteBlockReason(Category category) {
    if (category.productCount > 0) {
      return '${category.name} still has ${category.productCount} product(s) assigned. Move them '
          'to another category on the product screen first.';
    }
    final children = all.where((c) => c.parentId == category.id).toList(growable: false);
    if (children.isNotEmpty) {
      return '${category.name} has ${children.length} subcategor'
          '${children.length == 1 ? 'y' : 'ies'} (${children.map((c) => c.name).join(', ')}). '
          'Delete or re-parent them first.';
    }
    return null;
  }

  /// Deletes through the admin repository.
  ///
  /// NEEDS OWNER(AdminRepository): `Future<void> deleteCategory(String categoryId)` — the server
  /// must re-check the role, refuse while any product still references the id, and write the audit
  /// row. `CategoryRepository` is read-only by design, so no admin write path exists yet.
  Future<bool> remove(Category category) async {
    final blocked = deleteBlockReason(category);
    if (blocked != null) {
      announce(blocked, error: true);
      return false;
    }
    final ok = await mutateVoid(() => _admin.deleteCategory(category.id));
    if (ok) {
      if (selectedId.value == category.id) closeEditor();
      await load();
      announce('${category.name} deleted. The write is in the audit log.');
    } else {
      announce(failure.value?.message ?? 'Could not delete ${category.name}.', error: true);
    }
    return ok;
  }
}

/// One category's draft: fields, slug, parent, order, tile image and the active flag.
///
/// The save is a repository write only — no image upload happens here beyond what the media widget
/// already published, and `productCount` is never an input because a Firestore trigger owns it.
final class CategoryEditController extends AdminController {
  CategoryEditController();

  final AdminRepository _admin = Get.find<AdminRepository>();
  final CategoriesController _list = Get.find<CategoriesController>();
  final MediaRepository _media = Get.find<MediaRepository>();
  final CategoryRepository _catalog = Get.find<CategoryRepository>();

  final Rxn<Category> draft = Rxn<Category>();
  final RxList<String> issues = <String>.obs();
  final RxnString slugSource = RxnString();

  bool get isNew => draft.value?.id.isEmpty ?? true;
  Category? get value => draft.value;

  /// Opens a document, or a blank draft when [category] is null.
  void open(Category? category) {
    issues.clear();
    if (category == null) {
      draft.value = const Category(id: '', name: '');
      slugSource.value = null;
      return;
    }
    draft.value = category;
    slugSource.value = category.slug;
  }

  void patch(Category Function(Category current) update) {
    final current = draft.value;
    if (current == null) return;
    draft.value = update(current);
  }

  /// `Category.copyWith` cannot clear a parent back to top level, so writes go through a rebuild
  /// that can set `parentId` to null explicitly.
  Category _rebuild({
    String? name,
    String? slug,
    String? description,
    String? parentId,
    bool clearParent = false,
    int? order,
    List<MediaRef>? images,
    bool? isActive,
    bool? isFeatured,
    String? seoTitle,
    String? seoDescription,
  }) {
    final c = draft.value;
    if (c == null) throw const NotFoundFailure('Category draft not loaded');
    return Category(
      id: c.id,
      name: name ?? c.name,
      slug: slug ?? c.slug,
      description: description ?? c.description,
      parentId: clearParent ? null : (parentId ?? c.parentId),
      order: order ?? c.order,
      images: images ?? c.images,
      seoTitle: seoTitle ?? c.seoTitle,
      seoDescription: seoDescription ?? c.seoDescription,
      isFeatured: isFeatured ?? c.isFeatured,
      isActive: isActive ?? c.isActive,
      productCount: c.productCount,
      createdAt: c.createdAt,
      updatedAt: c.updatedAt,
    );
  }

  void setName(String name) {
    final current = draft.value;
    if (current == null) return;
    final follows = current.slug.isEmpty || current.slug == OmSlug.from(current.name);
    patch((c) => _rebuild(name: name, slug: follows ? OmSlug.from(name) : c.slug));
    if (follows) slugSource.value = null;
  }

  void setSlug(String raw) {
    patch((c) => _rebuild(slug: OmSlug.from(raw)));
    slugSource.value = raw.trim();
  }

  void setDescription(String value) => patch((c) => _rebuild(description: value));

  /// Null / empty means top level, stored as null so the tree builder sees one representation.
  void setParent(String? parentId) => patch(
        (c) => parentId == null || parentId.isEmpty
            ? _rebuild(clearParent: true)
            : _rebuild(parentId: parentId),
      );

  void setOrder(int order) => patch((c) => _rebuild(order: order));

  void setActive(bool value) => patch((c) => _rebuild(isActive: value));

  void setFeatured(bool value) => patch((c) => _rebuild(isFeatured: value));

  void setImage(MediaRef? ref) => patch((c) => _rebuild(images: ref == null ? const <MediaRef>[] : <MediaRef>[ref]));

  /// The media service owns the object; this only removes the storage copy after the draft has
  /// dropped the reference, mirroring the product editor so the two screens behave identically.
  Future<void> dropImage(MediaRef ref) async {
    final ok = await mutateVoid(() => _media.delete(ref));
    if (!ok) announce(failure.value?.message ?? 'The image was unlinked but not deleted.', error: true);
  }

  bool get mediaConfigured => _media.isConfigured;

  /// Slug availability is *asked about*, never asserted — same rule as the product editor. A
  /// collision created by another operator between this read and the save is refused by the write.
  final RxBool checkingSlug = false.obs;
  final RxnString slugAvailability = RxnString();

  Future<void> checkSlug(String raw) async {
    final candidate = OmSlug.from(raw);
    if (candidate.isEmpty || !OmSlug.isValid(candidate)) {
      slugAvailability.value = candidate.isEmpty
          ? null
          : 'Not a valid slug: 2–96 lowercase letters, digits and single hyphens.';
      return;
    }
    checkingSlug.value = true;
    try {
      final existing = await _catalog.bySlug(candidate);
      final isSelf = !isNew && existing.id == draft.value?.id;
      slugAvailability.value = isSelf
          ? 'This slug is already the one this category uses.'
          : 'Taken by ${existing.name}. Choose another.';
    } on NotFoundFailure {
      slugAvailability.value = 'Not used by any category.';
    } on OmFailure catch (error) {
      slugAvailability.value = 'Could not check: ${error.message}';
    } finally {
      checkingSlug.value = false;
    }
  }

  void setSeo({String? title, String? description}) => patch(
        (c) => _rebuild(
          seoTitle: title ?? c.seoTitle,
          seoDescription: description ?? c.seoDescription,
        ),
      );

  List<String> blockingIssues() {
    final current = draft.value;
    if (current == null) return const <String>['Category not loaded.'];
    final found = <String>[];
    if (current.name.trim().isEmpty) found.add('Name is required.');
    if (!OmSlug.isValid(current.slug)) {
      found.add('URL slug must be 2–96 lowercase letters, digits and single hyphens.');
    }
    if (current.order < 0) found.add('Display order cannot be negative.');
    final parent = current.parentId;
    if (parent != null && parent.isNotEmpty && parent == current.id) {
      found.add('A category cannot be its own parent.');
    }
    if (current.images.any((image) => image.altText.trim().isEmpty)) {
      found.add('The category image needs alt text before saving.');
    }
    return found;
  }

  /// Creates or updates. The slug uniqueness check that matters is the one inside the write: two
  /// operators can hold the same candidate at the same time and only the server can order them.
  ///
  /// NEEDS OWNER(AdminRepository): `Future<Category> saveCategory(Category category)` — server-side
  /// role re-check, slug collision refusal, cycle refusal, and the audit row.
  Future<Category?> save() async {
    final current = draft.value;
    if (current == null) return null;
    final found = blockingIssues();
    issues.assignAll(found);
    if (found.isNotEmpty) {
      announce(found.first, error: true);
      return null;
    }
    final saved = await mutate<Category>(() => _admin.saveCategory(current));
    if (saved != null) {
      draft.value = saved;
      issues.clear();
      await _list.load();
      _list.select(saved);
      announce('Saved ${saved.name}. The write is in the audit log.');
      return saved;
    }
    final error = failure.value;
    if (error != null) announce(error.message, error: true);
    return null;
  }
}
