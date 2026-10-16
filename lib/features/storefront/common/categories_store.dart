import 'package:get/get.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/data/models/category.dart';
import 'package:om_events/data/repositories/catalog_repository.dart';

/// Loads the category tree once per session and shares it with the header menu, the home rail,
/// the zero-result suggestions and the footer. A tree load failure is a visible state, not a
/// silent empty menu.
final class CategoriesStore extends GetxService {
  final RxList<Category> categories = <Category>[].obs;
  final Rxn<OmFailure> failure = Rxn<OmFailure>();
  final RxBool loading = false.obs;

  bool _attempted = false;

  List<Category> get topLevel =>
      categories.where((c) => c.isTopLevel && c.isActive).toList(growable: false);

  Category? byPathSlug(String slug) {
    for (final category in categories) {
      if (category.pathSlug == slug) return category;
    }
    return null;
  }

  Category? byId(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Future<void> ensureLoaded() async {
    if (_attempted || loading.value) return;
    _attempted = true;
    await load();
  }

  Future<void> retry() async {
    _attempted = true;
    await load();
  }

  Future<void> load() async {
    loading.value = true;
    failure.value = null;
    try {
      categories.assignAll(await Get.find<CategoryRepository>().tree());
    } on OmFailure catch (error) {
      failure.value = error;
      _attempted = false;
    } catch (_) {
      failure.value = const ServerFailure('Categories are not connected yet.');
      _attempted = false;
    } finally {
      loading.value = false;
    }
  }
}
