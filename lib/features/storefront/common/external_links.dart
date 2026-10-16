import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';
// ignore: depend_on_referenced_packages
import 'package:url_launcher/url_launcher.dart';

/// Every exit from the SPA (WhatsApp click-to-chat, Google Maps, payment gateways) goes through
/// this one helper so no screen invents its own launch path and the un-declared dependency note
/// lives in exactly one file.
///
/// NEEDS OWNER: `url_launcher` resolves transitively (via the supabase/app_links chain) but is
/// not declared in `pubspec.yaml`; declare it to remove the ignore above.
abstract final class OmExternalLink {
  /// Opens [url] in a new browser context. Falls back to copying it when the browser blocks the
  /// popup or the plugin is unavailable, and always tells the user which happened.
  static Future<void> open(BuildContext context, String url, {String? label}) async {
    final uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) return;
    var launched = false;
    try {
      launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      launched = false;
    }
    if (launched) return;
    await Clipboard.setData(ClipboardData(text: url));
    Get.snackbar(
      'Link copied',
      'Your browser blocked the pop-up. The link (${label ?? uri.host}) was copied to the '
          'clipboard — paste it into a new tab.',
      snackDuration: const Duration(seconds: 4),
    );
  }

  static String whatsappChat(String baseUrl, {String message = ''}) {
    if (baseUrl.isEmpty) return '';
    if (message.trim().isEmpty) return baseUrl;
    final joiner = baseUrl.contains('?') ? '&' : '?';
    return '$baseUrl${joiner}text=${Uri.encodeComponent(message)}';
  }

  static Future<void> copy(String text, {String note = 'Copied to clipboard'}) async {
    await Clipboard.setData(ClipboardData(text: text));
    Get.snackbar('Copied', note, snackDuration: const Duration(seconds: 2));
  }
}
