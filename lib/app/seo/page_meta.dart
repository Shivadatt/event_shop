import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:om_events/app/seo/om_seo.dart';

/// What kind of page a route is, for the purposes of metadata.
enum OmPageKind {
  home,
  collection,
  product,
  content,
  account,
  transactional,
  admin,
  error,
}

/// One route's indexing decision and metadata recipe.
///
/// Screens do not invent titles: they ask [OmRouteMeta] for the entry that matches their route and
/// fill in the entity-specific parts. `noIndex` is a decision, not a gap in coverage — every route
/// in the app must resolve to an entry, which `test/seo/om_seo_test.dart` enforces against the real
/// `OmRoutes` source file.
@immutable
final class PageMeta {
  const PageMeta({
    required this.route,
    required this.kind,
    required this.noIndex,
    this.titleTemplate,
    this.descriptionTemplate,
    this.ogType = 'website',
    this.followLinks = true,
    this.canonicalFromPath = true,
    this.robotsDirectives = const <String>['index', 'follow'],
  });

  /// The `OmRoutes` constant this entry belongs to.
  final String route;
  final OmPageKind kind;

  /// True means the page must never appear in a search index (carts, checkouts, admin, account).
  final bool noIndex;

  /// Static title text, or null when the page derives its title from an entity.
  final String? titleTemplate;
  final String? descriptionTemplate;

  /// `website`, `product`, `article`… consumed verbatim by the `<meta property="og:type">` tag.
  final String ogType;

  /// False on transactional pages so a crawler does not spend budget following `/checkout`.
  final bool followLinks;

  /// False on paginated or filtered views where the path itself is not the canonical resource.
  final bool canonicalFromPath;

  /// Raw robots directive list, derived from [noIndex] and [followLinks] by [directives].
  final List<String> robotsDirectives;

  bool get isIndexable => !noIndex;

  /// Effective directives, honouring the flags rather than the (possibly stale) literal list.
  List<String> get directives => <String>[
        noIndex ? 'noindex' : 'index',
        followLinks ? 'follow' : 'nofollow',
        ...robotsDirectives.where((d) => d != 'index' && d != 'follow'),
      ];

  /// Title for a page that has an entity name available.
  String titleFor({String? seoTitle, String? primary, String? secondary}) => OmSeo.title(
        seoTitle: titleTemplate ?? seoTitle,
        primary: primary,
        secondary: secondary,
        includeBrand: true,
      );

  String descriptionFor({String? seoDescription, String? body}) => OmSeo.description(
        seoDescription: descriptionTemplate ?? seoDescription,
        body: body,
      );

  /// The absolute URL this page should declare as canonical, or null when indexing is off — a
  /// noindex page must not advertise a self-canonical.
  String? canonicalFor(String path) => noIndex ? null : OmSeo.absoluteUrl(path);

  @override
  String toString() => 'PageMeta($route, ${kind.name}, noIndex: $noIndex)';
}

/// A single `<meta>` / `<link>` pair in the document head.
@immutable
final class OmHeadTag {
  const OmHeadTag({
    required this.name,
    required this.content,
    this.isProperty = false,
    this.href,
  });

  factory OmHeadTag.name(String name, String content) =>
      OmHeadTag(name: name, content: content);

  factory OmHeadTag.property(String property, String content) =>
      OmHeadTag(name: property, content: content, isProperty: true);

  factory OmHeadTag.link(String rel, String href) =>
      OmHeadTag(name: rel, content: '', href: href);

  final String name;
  final String content;
  final bool isProperty;
  final String? href;

  /// HTML text for the tag. Escaping is done here because the only writer of the head must not
  /// have to remember it: attribute values are quoted and `&`/`<`/`"` neutralised.
  String toHtml() {
    final escaped = _escape(content);
    if (href != null) {
      return '<link rel="$name" href="${_escape(href!)}">';
    }
    final attribute = isProperty ? 'property' : 'name';
    return '<meta $attribute="$name" content="$escaped">';
  }

  static String _escape(String value) => value
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;');

  @override
  String toString() => toHtml();
}

/// The full head recipe for one rendered page: everything a head writer (or a prerenderer) needs,
/// as data.
@immutable
final class OmDocumentMeta {
  const OmDocumentMeta({
    required this.title,
    required this.description,
    required this.path,
    required this.noIndex,
    this.ogType = 'website',
    this.imageUrls = const <String>[],
    this.jsonLd = const <Map<String, Object?>>[],
  });

  final String title;
  final String description;
  final String path;
  final bool noIndex;
  final String ogType;
  final List<String> imageUrls;

  /// Already-built JSON-LD objects; the writer serialises each into its own `<script>` block.
  final List<Map<String, Object?>> jsonLd;

  /// Tags in emission order. Deliberately excludes `<title>`, charset and the bootstrap script —
  /// those belong to `web/index.html` and to the framework.
  List<OmHeadTag> get tags => <OmHeadTag>[
        OmHeadTag.name('robots', noIndex ? 'noindex,nofollow' : 'index,follow'),
        if (!noIndex) OmHeadTag.link('canonical', OmSeo.absoluteUrl(path)),
        OmHeadTag.property('og:site_name', OmSeo.siteName),
        OmHeadTag.property('og:title', title),
        if (description.isNotEmpty) OmHeadTag.property('og:description', description),
        OmHeadTag.property('og:type', ogType),
        OmHeadTag.property('og:url', OmSeo.absoluteUrl(path)),
        for (final image in imageUrls.take(3)) OmHeadTag.property('og:image', image),
        OmHeadTag.name('twitter:card', imageUrls.isEmpty ? 'summary' : 'summary_large_image'),
        OmHeadTag.name('twitter:title', title),
        if (description.isNotEmpty) OmHeadTag.name('twitter:description', description),
      ];

  /// The head block as HTML text. Used by the deploy step and by tests; a runtime writer can walk
  /// [tags] instead when it needs to update one tag without rewriting the head.
  String render() => <String>[
        '<title>${OmHeadTag._escape(title)}</title>',
        ...tags.map((tag) => tag.toHtml()),
        ...jsonLd.map(
          (obj) => '<script type="application/ld+json">${jsonEncode(obj)}</script>',
        ),
      ].join('\n');
}
