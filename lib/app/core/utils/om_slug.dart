/// URL-safe slugs for SEO-friendly product and category paths.
final class OmSlug {
  const OmSlug._();

  static final RegExp _separator = RegExp(r'[^a-z0-9]+');

  static String from(String input) {
    final slug = input
        .toLowerCase()
        .replaceAll('&', ' and ')
        .replaceAll(_separator, '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    return slug.isEmpty ? 'item' : slug;
  }

  static bool isValid(String value) =>
      value.length >= 2 &&
      value.length <= 96 &&
      RegExp(r'^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$').hasMatch(value);
}
