import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// One image chosen in the browser, held as bytes so the media repository owns the transfer.
///
/// Bytes rather than a path: on Flutter Web a picked file has no filesystem path, and a `path`
/// would be meaningless to the upload service anyway.
final class PickedImage {
  const PickedImage({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  final String name;
  final String mimeType;
  final Uint8List bytes;

  int get sizeBytes => bytes.length;
}

/// The only place in the admin panel that touches `file_picker`.
///
/// Keeping the plugin behind three small methods means a plugin upgrade can only break this file,
/// and every screen gets the same cancel/empty behaviour. Nothing here validates the bytes — the
/// media repository does that from magic bytes, and an unconfigured bucket still has to refuse.
abstract final class AdminFiles {
  /// Images only, multi-select, read into memory. Returns an empty list when the operator cancels
  /// or picks files the browser could not read; callers must treat empty as "nothing happened".
  static Future<List<PickedImage>> pickImages() async {
    // file_picker 13.x: pickFiles is a static returning the picked list directly (empty on cancel),
    // and bytes are read per-file rather than eagerly captured by a `withData` flag.
    final files = await FilePicker.pickFiles(type: FileType.image);
    final picked = <PickedImage>[];
    for (final file in files) {
      Uint8List data;
      try {
        data = await file.readAsBytes();
      } catch (_) {
        // A browser that cannot read one picked file is skipped, not a fatal error.
        continue;
      }
      if (data.isEmpty) continue;
      picked.add(
        PickedImage(
          name: file.name,
          mimeType: mimeTypeForName(file.name),
          bytes: data,
        ),
      );
    }
    return picked;
  }

  /// A CSV sheet read as text, BOM stripped. Null means cancelled; an empty string means the file
  /// had nothing in it, which the import preview shows as "no rows" rather than an error.
  static Future<String?> pickCsvText() async {
    final file = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const <String>['csv'],
    );
    if (file == null) return null;
    final Uint8List data;
    try {
      data = await file.readAsBytes();
    } catch (_) {
      return null;
    }
    if (data.isEmpty) return null;
    return _stripBom(utf8.decode(data, allowMalformed: true));
  }

  static String _stripBom(String text) =>
      text.startsWith('\uFEFF') ? text.substring(1) : text;

  /// Extension-derived MIME type.
  ///
  /// The browser reports its own type for a picked file, but it is not something this app should
  /// trust as a gate; the media repository checks the leading bytes. This value only labels the
  /// upload and picks a sensible default, and an unknown extension becomes `application/octet-stream`
  /// so the repository rejects it rather than accepting a disguised file.
  static String mimeTypeForName(String name) {
    final dot = name.lastIndexOf('.');
    final ext = dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
    return switch (ext) {
      'jpg' || 'jpeg' => 'image/jpeg',
      'png' => 'image/png',
      'webp' => 'image/webp',
      'gif' => 'image/gif',
      _ => 'application/octet-stream',
    };
  }

  static bool isAcceptedImageName(String name) =>
      mimeTypeForName(name) != 'application/octet-stream';

  static String describeBytes(int length) {
    if (length < 1024) return '$length B';
    if (length < 1024 * 1024) return '${(length / 1024).toStringAsFixed(0)} KB';
    return '${(length / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
