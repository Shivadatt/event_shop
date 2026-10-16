import 'dart:typed_data';

import 'package:om_events/app/core/services/media/image_dimensions_probe.dart';
import 'package:om_events/app/core/services/media/media_limits.dart';
import 'package:om_events/app/core/services/media/media_signature.dart';
import 'package:om_events/data/models/media_ref.dart';
import 'package:om_events/data/repositories/media_repository.dart';

/// Everything the pipeline learned from a file's bytes in one pass, so the uploader never re-reads
/// a header it has already validated. Carries the rejection reason when validation failed.
final class MediaAnalysis {
  const MediaAnalysis({
    required this.format,
    required this.rules,
    required this.bytes,
    this.dimensions,
    this.sniff,
    this.error,
  });

  final MediaFormat format;
  final MediaKindRules rules;
  final Uint8List bytes;
  final ImageDimensions? dimensions;
  final MediaSniffResult? sniff;
  final String? error;

  int get byteLength => bytes.lengthInBytes;

  bool get isAccepted => error == null;

  /// MIME written into the object's `Content-Type`. Taken from the sniffed header, never from the
  /// browser's claim, because the bucket's allowed-MIME list and the CDN's format negotiation both
  /// key off the bytes.
  String get contentType => format.mime;

  String get extension => format.extension;

  /// Only an exact reading may be written into `MediaRef.width/height`; an approximate one is
  /// stored as null so nothing downstream trusts a tile size as a canvas size.
  int? get width => dimensions == null || dimensions!.approximate ? null : dimensions!.width;

  int? get height => dimensions == null || dimensions!.approximate ? null : dimensions!.height;

  /// Admin-facing advisory text (renamed extension, approximate size, …). Never an error.
  String? get note {
    final found = sniff;
    if (found != null && found.hasNameMismatch) return found.mismatchNote;
    return dimensions?.note;
  }

  MediaValidation get validation => error == null
      ? MediaValidation(isValid: true, maximumBytes: rules.maxBytes)
      : MediaValidation(isValid: false, error: error, maximumBytes: rules.maxBytes);

  MediaAnalysis reject(String message) => MediaAnalysis(
        format: format,
        rules: rules,
        bytes: bytes,
        dimensions: dimensions,
        sniff: sniff,
        error: message,
      );

  static MediaAnalysis unsupported(Uint8List bytes, MediaKindRules rules, MediaSniffResult sniff) =>
      MediaAnalysis(
        format: MediaFormat.unsupported,
        rules: rules,
        bytes: bytes,
        sniff: sniff,
        error: sniff.reason ?? 'That file is not a supported image.',
      );
}

/// Client-side gate. Every rule that can be answered from the bytes is answered here, before a
/// byte is transferred: a rejected upload costs the admin one toast, an upload-then-reject costs
/// the bucket an object, the CDN a cache entry and the admin a mystery.
final class MediaValidator {
  const MediaValidator();

  /// The context-free check that matches [MediaRepository.validate]. It has no `MediaKind`, so it
  /// applies the loosest byte cap in [MediaLimits]; the pipeline always runs [preflight] with the
  /// real kind.
  MediaValidation validate({
    required int byteLength,
    required String mimeType,
    required List<int> leadingBytes,
  }) {
    if (byteLength <= 0) {
      return const MediaValidation(isValid: false, error: 'That file is empty.');
    }
    final sniff = MediaSignature.sniff(leadingBytes);
    if (!sniff.isAccepted) {
      return MediaValidation(isValid: false, error: sniff.reason);
    }
    if (byteLength > MediaLimits.maxBytesCeiling) {
      return MediaValidation(
        isValid: false,
        error: 'That file is ${_size(byteLength)}. The media bucket accepts at most '
            '${_size(MediaLimits.maxBytesCeiling)}.',
        maximumBytes: MediaLimits.maxBytesCeiling,
      );
    }
    if (mimeType.isNotEmpty &&
        !MediaLimits.allowedMimeTypes.contains(mimeType) &&
        !MediaLimits.allowedMimeTypes.contains(sniff.format.mime)) {
      return const MediaValidation(
        isValid: false,
        error: 'Only JPEG, PNG, WebP and AVIF images can be uploaded.',
      );
    }
    return MediaValidation(isValid: true, maximumBytes: MediaLimits.maxBytesCeiling);
  }

  /// Validates and returns the findings; [MediaAnalysis.validation] is the interface-shaped result.
  MediaAnalysis analyse({
    required Uint8List bytes,
    required MediaKind kind,
    required String altText,
    required int alreadyAttached,
    String? fileName,
    String? declaredMimeType,
  }) {
    final rules = MediaLimits.rulesFor(kind);
    final header = bytes.length > MediaLimits.sniffWindowBytes
        ? Uint8List.sublistView(bytes, 0, MediaLimits.sniffWindowBytes)
        : bytes;
    final sniff = MediaSignature.sniff(header, fileName: fileName);
    if (!sniff.isAccepted) return MediaAnalysis.unsupported(bytes, rules, sniff);

    final analysis = MediaAnalysis(format: sniff.format, rules: rules, bytes: bytes, sniff: sniff);

    if (bytes.lengthInBytes == 0) return analysis.reject('That file is empty.');

    // A declared MIME the header cannot corroborate is the one contradiction worth refusing: it
    // means the caller already lost the real format, so the object would be stored mislabelled.
    if (declaredMimeType != null &&
        declaredMimeType.isNotEmpty &&
        !MediaLimits.allowedMimeTypes.contains(declaredMimeType)) {
      return analysis.reject(
        'That file reports an unsupported type ($declaredMimeType). '
        'Allowed: JPEG, PNG, WebP, AVIF.',
      );
    }

    if (bytes.lengthInBytes > rules.maxBytes) {
      return analysis.reject(
        'That file is ${_size(bytes.lengthInBytes)}. '
        '${_label(kind)} images must be ${_size(rules.maxBytes)} or smaller.',
      );
    }

    final alt = altText.trim();
    if (alt.length < MediaLimits.altTextMinLength) {
      return analysis.reject(
        'Alt text is required before uploading: describe what the picture shows '
        '(for example "gold balloon arch with LED fairy lights").',
      );
    }
    if (alt.length > MediaLimits.altTextMaxLength) {
      return analysis.reject(
        'Alt text must be ${MediaLimits.altTextMaxLength} characters or fewer (currently '
        '${alt.length}).',
      );
    }

    if (alreadyAttached >= rules.maxPerEntity) {
      return analysis.reject(
        'This ${_label(kind).toLowerCase()} already has the maximum of '
        '${rules.maxPerEntity} images. Remove one before adding another.',
      );
    }

    final dimensions = ImageDimensionsProbe.probe(bytes);
    if (dimensions == null) {
      // PNG/JPEG/WebP headers always expose their size, so null means truncated or corrupt. AVIF
      // alone can be unreadable without being broken (tiled containers), and refusing a valid
      // image is worse than publishing one whose size could not be confirmed.
      if (sniff.format == MediaFormat.avif) return analysis;
      return analysis.reject(
        'Could not read that image\'s dimensions. The file is probably truncated or corrupt — '
        're-export it as JPEG, PNG or WebP.',
      );
    }
    final withDimensions = MediaAnalysis(
      format: sniff.format,
      rules: rules,
      bytes: bytes,
      dimensions: dimensions,
      sniff: sniff,
    );
    if (dimensions.approximate) return withDimensions;
    if (dimensions.width < rules.minWidth || dimensions.height < rules.minHeight) {
      return withDimensions.reject(
        'That image is ${dimensions.width}x${dimensions.height}. ${_label(kind)} images must be '
        'at least ${rules.minWidth}x${rules.minHeight} so the grid thumbnail stays sharp.',
      );
    }
    if (dimensions.width > rules.maxWidth || dimensions.height > rules.maxHeight) {
      return withDimensions.reject(
        'That image is ${dimensions.width}x${dimensions.height}, above the '
        '${rules.maxWidth}x${rules.maxHeight} cap. Resize it before uploading.',
      );
    }
    return withDimensions;
  }

  /// Convenience for call sites that only care about accept/reject.
  MediaValidation preflight({
    required Uint8List bytes,
    required MediaKind kind,
    required String altText,
    required int alreadyAttached,
    String? fileName,
    String? declaredMimeType,
  }) =>
      analyse(
        bytes: bytes,
        kind: kind,
        altText: altText,
        alreadyAttached: alreadyAttached,
        fileName: fileName,
        declaredMimeType: declaredMimeType,
      ).validation;

  /// Helper text for admin forms, so a limit is stated before the admin wastes a file pick.
  String describeRules(MediaKind kind) {
    final rules = MediaLimits.rulesFor(kind);
    return '${_label(kind)} — ${rules.describe()}. '
        'Formats: JPEG, PNG, WebP, AVIF. Alt text required.';
  }

  static String _size(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
  }

  static String _label(MediaKind kind) => switch (kind) {
        MediaKind.product => 'Product',
        MediaKind.category => 'Category',
        MediaKind.banner => 'Banner',
        MediaKind.review => 'Review photo',
        MediaKind.other => 'Image',
      };
}
