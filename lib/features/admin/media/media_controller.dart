import 'package:get/get.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/query.dart';
import 'package:om_events/data/repositories/admin_repository.dart';
import 'package:om_events/data/repositories/media_repository.dart';
import 'package:om_events/features/admin/shared/admin_controller_base.dart';
import 'package:om_events/features/admin/shared/admin_csv.dart';

/// One image reference joined to the entity that uses it — this is the "entity usage" row.
final class MediaUsageRow {
  const MediaUsageRow({
    required this.ref,
    required this.entityId,
    required this.entityName,
    required this.entityKind,
  });

  final MediaRef ref;
  final String entityId;
  final String entityName;
  final String entityKind;

  bool get missingAlt => ref.altText.trim().isEmpty;
}

/// Media library assembled from the live catalogue.
///
/// There is no dedicated media-listing endpoint, so this enumerates product images page by page
/// through `listProducts`; every asset is attributed to the product that uses it, and a missing alt
/// text is surfaced because it is an accessibility and SEO defect. Category and banner assets are
/// out of scope here (NEEDS OWNER note on [fetch]).
final class MediaController extends AdminController with PagedAdminList<Product> {
  MediaController();

  final AdminRepository _admin = Get.find<AdminRepository>();

  /// Only product images are enumerable without a server media endpoint.
  MediaRepository? get media =>
      Get.isRegistered<MediaRepository>() ? Get.find<MediaRepository>() : null;

  bool get isConfigured => media?.isConfigured ?? false;

  final RxBool altOnly = false.obs;

  @override
  void onInit() {
    super.onInit();
    loadFirstPage();
  }

  @override
  Future<PagedResult<Product>> fetch({String? cursor}) => _admin.listProducts(
        pageSize: pageSize,
        cursor: cursor,
        query: const CatalogQuery(status: ProductStatus.active),
        // NEEDS OWNER(MediaRepository): a `listMedia({String? kind, bool missingAltOnly})` that
        // reads the `media_objects` ledger. Until it exists, category and banner assets and a
        // cross-entity "used by" roll-up cannot be shown without walking every catalogue page.
      );

  void toggleAltOnly() {
    altOnly.value = !altOnly.value;
  }

  /// Derived rows for the loaded pages, optionally filtered to the accessibility defects.
  List<MediaUsageRow> get usageRows {
    final result = <MediaUsageRow>[];
    for (final product in rows) {
      for (final image in product.images) {
        if (altOnly.value && image.altText.trim().isNotEmpty) continue;
        result.add(MediaUsageRow(
          ref: image,
          entityId: product.id,
          entityName: product.name,
          entityKind: 'product',
        ));
      }
    }
    return result;
  }

  int get totalImages {
    var count = 0;
    for (final product in rows) {
      count += product.images.length;
    }
    return count;
  }

  int get missingAltCount {
    var count = 0;
    for (final product in rows) {
      for (final image in product.images) {
        if (image.altText.trim().isEmpty) count++;
      }
    }
    return count;
  }

  String exportLoaded() => OmCsv.build(
        headers: const <String>[
          'entityKind',
          'entityId',
          'entityName',
          'mediaId',
          'storagePath',
          'kind',
          'altText',
          'missingAlt',
          'isPrimary',
        ],
        rows: <List<Object?>>[
          for (final row in usageRows)
            <Object?>[
              row.entityKind,
              row.entityId,
              row.entityName,
              row.ref.id,
              row.ref.storagePath,
              row.ref.kind.code,
              row.ref.altText,
              row.missingAlt ? 'yes' : 'no',
              row.ref.isPrimary ? 'yes' : 'no',
            ],
        ],
      );
}
