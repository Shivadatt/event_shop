import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:om_events/data/models/product.dart';
import 'package:om_events/data/providers/firestore_collections.dart';
import 'package:om_events/data/query.dart';

/// Translates an immutable [CatalogQuery] into a Firestore query, plus opaque cursor paging.
/// Widgets never build a `Query` — they call the repository, which calls here.
///
/// Two Firestore constraints shape this builder and are why the code looks the way it does:
///  * a query may hold only ONE inequality *range* (`<`,`<=`,`>`,`>=`), and that field must be the
///    primary `orderBy`; a second range (e.g. price bounds) would be rejected.
///  * combining `in`/`arrayContainsAny` with a range on a different field is rejected.
/// So when a full-text search term is present the search field owns the constraint and price
/// bounds are applied client-side; otherwise the server applies them.
abstract final class CatalogQueryBuilder {
  const CatalogQueryBuilder._();

  static Query<Map<String, dynamic>> base(CatalogQuery query, {List<String> categoryIds = const <String>[]}) {
    Query<Map<String, dynamic>> q = Collections.products_;

    final status = query.status.code;
    q = q.where('status', isEqualTo: status);

    if (query.categorySlug != null && query.categorySlug!.isNotEmpty) {
      q = q.where('categorySlug', isEqualTo: query.categorySlug);
    } else if (categoryIds.length == 1) {
      q = q.where('categoryId', isEqualTo: categoryIds.first);
    } else if (categoryIds.length > 1) {
      // Firestore caps `in` at 30 values; the repository pre-trims the descendant set.
      q = q.where('categoryId', whereIn: categoryIds.take(30).toList(growable: false));
    }

    if (query.featuredOnly) q = q.where('isFeatured', isEqualTo: true);

    // Wholesale-only products are visible only to wholesale buyers: the repository passes
    // wholesaleOnly=false for retail shoppers, which excludes them server-side.
    if (query.wholesaleOnly == false) q = q.where('isWholesaleOnly', isEqualTo: false);

    for (final tag in query.tags.take(5)) {
      q = q.where('tags', arrayContains: tag);
    }

    // A search term occupies the single allowed constraint slot, so ranges move client-side.
    final term = query.search.trim().toLowerCase();
    if (term.isNotEmpty) {
      final tokens = term.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).take(5).toList();
      q = q.where('keywords', arrayContainsAny: tokens);
    } else {
      final min = query.minPricePaise;
      final max = query.maxPricePaise;
      if (min != null && min > 0) q = q.where('retailPricePaise', isGreaterThanOrEqualTo: min);
      if (max != null && max > 0) q = q.where('retailPricePaise', isLessThanOrEqualTo: max);
    }

    return applySort(q, query.sort);
  }

  /// Primary sort + a stable `__name__` tiebreaker so cursors are deterministic. When a range is
  /// active (price bounds, no search), the range field MUST be the first orderBy — which price
  /// sorts already satisfy. Non-price sorts (newest/best/rating) coexist with the price range only
  /// because that range was moved to a client filter when a search term is set; when both a price
  /// range and a non-price sort are requested we drop the server price range to stay legal, and the
  /// repository re-filters client-side.
  static Query<Map<String, dynamic>> applySort(Query<Map<String, dynamic>> q, SortMode sort) {
    switch (sort) {
      case SortMode.relevance:
      case SortMode.bestSelling:
        return q.orderBy('soldCount', descending: true).orderBy(FieldPath.documentId);
      case SortMode.newest:
        return q.orderBy('createdAt', descending: true).orderBy(FieldPath.documentId);
      case SortMode.priceLowHigh:
        return q.orderBy('retailPricePaise').orderBy(FieldPath.documentId);
      case SortMode.priceHighLow:
        return q.orderBy('retailPricePaise', descending: true).orderBy(FieldPath.documentId);
      case SortMode.rating:
        return q.orderBy('ratingAvg', descending: true).orderBy(FieldPath.documentId);
    }
  }

  static Query<Map<String, dynamic>> build(
    CatalogQuery query, {
    List<String> categoryIds = const <String>[],
  }) {
    final baseQuery = base(query, categoryIds: categoryIds);
    final cursor = decodeCursor(query.cursor);
    if (cursor == null) return baseQuery;
    return _applyStartAfter(baseQuery, query.sort, cursor);
  }

  static Query<Map<String, dynamic>> _applyStartAfter(
    Query<Map<String, dynamic>> q,
    SortMode sort,
    CatalogCursor cursor,
  ) {
    switch (sort) {
      case SortMode.relevance:
      case SortMode.bestSelling:
        return q.startAfter([cursor.sortValue, cursor.id]);
      case SortMode.newest:
        return q.startAfter([cursor.timestampValue, cursor.id]);
      case SortMode.priceLowHigh:
      case SortMode.priceHighLow:
        return q.startAfter([cursor.sortValue, cursor.id]);
      case SortMode.rating:
        return q.startAfter([cursor.sortValue, cursor.id]);
    }
  }

  /// Encode the last document of a page into an opaque, base64 cursor.
  static String encodeCursor(QueryDocumentSnapshot<Map<String, dynamic>> last, SortMode sort) {
    final field = _sortField(sort);
    final raw = field == null ? null : last.get(field);
    final encoded = <String, Object?>{
      'v': raw is Timestamp ? raw.millisecondsSinceEpoch : raw,
      'id': last.id,
    };
    return base64Url.encode(utf8.encode(jsonEncode(encoded)));
  }

  static CatalogCursor? decodeCursor(String? cursor) {
    if (cursor == null || cursor.isEmpty) return null;
    try {
      final map = jsonDecode(utf8.decode(base64Url.decode(cursor))) as Map<String, dynamic>;
      return CatalogCursor(
        sortValue: map['v'],
        id: map['id'] as String,
      );
    } catch (_) {
      return null;
    }
  }

  static String? _sortField(SortMode sort) => switch (sort) {
        SortMode.relevance || SortMode.bestSelling => 'soldCount',
        SortMode.newest => 'createdAt',
        SortMode.priceLowHigh || SortMode.priceHighLow => 'retailPricePaise',
        SortMode.rating => 'ratingAvg',
      };

  /// Client-side re-filter for cases the server could not express in one legal query (price bounds
  /// alongside a search, or a non-price sort with a price range).
  static bool matchesClient(Product product, CatalogQuery query) {
    final min = query.minPricePaise;
    final max = query.maxPricePaise;
    if (min != null && min > 0 && product.retailPricePaise < min) return false;
    if (max != null && max > 0 && product.retailPricePaise > max) return false;
    if (query.inStockOnly && !product.isInStock) return false;
    if (query.wholesaleOnly == false && product.isWholesaleOnly) return false;
    return true;
  }
}

/// The decoded half of a [CatalogQueryBuilder.encodeCursor] page token: the sort key of the last
/// document the caller was shown plus its id, which together are what `startAfter` needs to be
/// deterministic. Public because [CatalogQueryBuilder.decodeCursor] hands it back to repositories.
final class CatalogCursor {
  const CatalogCursor({required this.sortValue, required this.id});
  final Object? sortValue;
  final String id;

  Object? get timestampValue => sortValue == null
      ? null
      : Timestamp.fromDate(DateTime.fromMillisecondsSinceEpoch(sortValue as int));
}
