import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/om_doc.dart';

final class Category {
  const Category({
    required this.id,
    required this.name,
    this.slug = '',
    this.description = '',
    this.parentId,
    this.order = 0,
    this.images = const <MediaRef>[],
    this.seoTitle = '',
    this.seoDescription = '',
    this.isFeatured = false,
    this.isActive = true,
    this.productCount = 0,
    this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String name;
  final String slug;
  final String description;

  /// Null means top level; subcategories keep `parentId` so one query builds the tree.
  final String? parentId;
  final int order;
  final List<MediaRef> images;
  final String seoTitle;
  final String seoDescription;
  final bool isFeatured;
  final bool isActive;

  /// Maintained by a Firestore trigger; used for badge counts without a per-category query.
  final int productCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  String get pathSlug => slug.isNotEmpty ? slug : id;
  bool get isTopLevel => parentId == null || parentId!.isEmpty;

  factory Category.fromMap(Map<String, dynamic> m, {String? id}) => Category(
        id: id ?? readStringOrEmpty(m, 'id'),
        name: readStringOrEmpty(m, 'name'),
        slug: readStringOrEmpty(m, 'slug'),
        description: readStringOrEmpty(m, 'description'),
        parentId: readString(m, 'parentId'),
        order: readIntOrZero(m, 'order'),
        images: readMapList(m, 'images').map(MediaRef.fromMap).toList(growable: false),
        seoTitle: readStringOrEmpty(m, 'seoTitle'),
        seoDescription: readStringOrEmpty(m, 'seoDescription'),
        isFeatured: readBool(m, 'isFeatured'),
        isActive: readBool(m, 'isActive', fallback: true),
        productCount: readIntOrZero(m, 'productCount'),
        createdAt: readDate(m, 'createdAt'),
        updatedAt: readDate(m, 'updatedAt'),
      );

  Map<String, Object?> toWriteMap() => compact(<String, Object?>{
        'name': name,
        'slug': slug,
        'description': description,
        'parentId': parentId,
        'order': order,
        'images': images.map((i) => i.toMap()).toList(),
        'seoTitle': seoTitle,
        'seoDescription': seoDescription,
        'isFeatured': isFeatured,
        'isActive': isActive,
      });

  Category copyWith({
    String? name,
    String? slug,
    String? description,
    String? parentId,
    int? order,
    List<MediaRef>? images,
    bool? isFeatured,
    bool? isActive,
    String? seoTitle,
    String? seoDescription,
  }) =>
      Category(
        id: id,
        name: name ?? this.name,
        slug: slug ?? this.slug,
        description: description ?? this.description,
        parentId: parentId ?? this.parentId,
        order: order ?? this.order,
        images: images ?? this.images,
        seoTitle: seoTitle ?? this.seoTitle,
        seoDescription: seoDescription ?? this.seoDescription,
        isFeatured: isFeatured ?? this.isFeatured,
        isActive: isActive ?? this.isActive,
        productCount: productCount,
        createdAt: createdAt,
        updatedAt: updatedAt,
      );
}
