import 'dart:typed_data';

/// The image formats the pipeline can identify from the file itself rather than from its name or
/// the MIME the browser reported. Browser-supplied MIME types lie often enough (a `.jpg` that is
/// really a WebP, an iPhone HEIC renamed by an export tool) that the header is the only
/// trustworthy signal available before a byte is transferred.
enum MediaFormat {
  jpeg('image/jpeg', 'jpg'),
  png('image/png', 'png'),
  webp('image/webp', 'webp'),
  avif('image/avif', 'avif'),

  /// Recognised as something, but deliberately unsupported. Carries the reason the user is told.
  unsupported('application/octet-stream', 'bin');

  const MediaFormat(this.mime, this.extension);

  final String mime;
  final String extension;

  bool get isAccepted => this != MediaFormat.unsupported;

  static MediaFormat fromMime(String mime) {
    final normalised = mime.toLowerCase().split(';').first.trim();
    for (final format in MediaFormat.values) {
      if (format.mime == normalised) return format;
    }
    return MediaFormat.unsupported;
  }
}

/// What the header sniff found. A name/extension mismatch is *not* a rejection: the pipeline
/// writes the object key and the `Content-Type` from the sniffed format, so a WebP named `.jpg`
/// becomes a correct `.webp` object instead of a mislabelled one.
final class MediaSniffResult {
  const MediaSniffResult._({
    required this.format,
    this.claimedExtension,
    this.reason,
  });

  const MediaSniffResult.accepted(MediaFormat format)
      : this._(format: format, claimedExtension: null, reason: null);

  const MediaSniffResult.mismatched(MediaFormat format, String claimedExtension)
      : this._(format: format, claimedExtension: claimedExtension, reason: null);

  const MediaSniffResult.rejected(String reason)
      : this._(
          format: MediaFormat.unsupported,
          claimedExtension: null,
          reason: reason,
        );

  final MediaFormat format;

  /// Extension the file name claimed, kept so the admin UI can explain that the stored object was
  /// renamed to match its real bytes.
  final String? claimedExtension;
  final String? reason;

  bool get isAccepted => format.isAccepted && reason == null;

  bool get hasNameMismatch => claimedExtension != null;

  String get mismatchNote {
    final claimed = claimedExtension;
    if (claimed == null) return '';
    return 'Stored as .${format.extension} because its bytes are '
        '${format.mime}, not .$claimed.';
  }
}

abstract final class MediaSignature {
  /// Inspects the leading bytes only — that is why this can run before a transfer and again,
  /// cheaply, inside the upload path where the caller may have skipped the pre-flight.
  static MediaSniffResult sniff(List<int> bytes, {String? fileName}) {
    if (bytes.length < 12) {
      return const MediaSniffResult.rejected(
        'The file is too small to be an image. It may be truncated or corrupt.',
      );
    }
    final claimed = extensionOf(fileName);
    final MediaFormat? found;
    if (_hasBytes(bytes, _pngMagic, 0)) {
      found = MediaFormat.png;
    } else if (_hasBytes(bytes, const <int>[0xFF, 0xD8, 0xFF], 0)) {
      found = MediaFormat.jpeg;
    } else if (_hasBytes(bytes, _riff, 0) && _hasBytes(bytes, _webpTag, 8)) {
      found = MediaFormat.webp;
    } else if (_hasBytes(bytes, _ftyp, 4) && _isAvifBrand(bytes)) {
      found = MediaFormat.avif;
    } else {
      found = null;
    }

    if (found != null) {
      final isFine = claimed == null || claimed == found.extension || claimed == _altExt(found);
      return isFine
          ? MediaSniffResult.accepted(found)
          : MediaSniffResult.mismatched(found, claimed);
    }

    if (_hasBytes(bytes, _gifMagic, 0)) {
      return const MediaSniffResult.rejected(
        'Animated GIF is not accepted. Export a JPEG, WebP or PNG still frame.',
      );
    }
    if (_hasBytes(bytes, _ftyp, 4) && _isHeicBrand(bytes)) {
      return const MediaSniffResult.rejected(
        'HEIC/HEIF does not decode in desktop browsers. Convert it to JPEG or WebP first.',
      );
    }
    if (_hasBytes(bytes, _pdfMagic, 0)) {
      return const MediaSniffResult.rejected('That file is a PDF, not an image.');
    }
    if (_hasBytes(bytes, const <int>[0x42, 0x4D], 0)) {
      return const MediaSniffResult.rejected('BMP is not accepted. Use JPEG, PNG or WebP.');
    }
    if (_hasBytes(bytes, const <int>[0x49, 0x49, 0x2A], 0) ||
        _hasBytes(bytes, const <int>[0x4D, 0x4D, 0x2A], 0)) {
      return const MediaSniffResult.rejected('TIFF is not accepted. Use JPEG, PNG or WebP.');
    }
    if (claimed == 'svg') {
      return const MediaSniffResult.rejected(
        'SVG is not accepted: it can carry scripts and it is served from the store origin.',
      );
    }
    return MediaSniffResult.rejected(
      'Unrecognised file format${claimed == null ? '' : ' (.$claimed declared)'}. '
      'Allowed: JPEG, PNG, WebP, AVIF.',
    );
  }

  /// Lower-case extension without the dot, or null when the name has none.
  static String? extensionOf(String? fileName) {
    if (fileName == null) return null;
    final dot = fileName.lastIndexOf('.');
    if (dot <= 0 || dot == fileName.length - 1) return null;
    return fileName.substring(dot + 1).toLowerCase();
  }

  static String? _altExt(MediaFormat format) =>
      format == MediaFormat.jpeg ? 'jpeg' : null;

  static const List<int> _pngMagic = <int>[0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];
  static const List<int> _riff = <int>[0x52, 0x49, 0x46, 0x46]; // RIFF
  static const List<int> _webpTag = <int>[0x57, 0x45, 0x42, 0x50]; // WEBP
  static const List<int> _ftyp = <int>[0x66, 0x74, 0x79, 0x70]; // ftyp
  static const List<int> _gifMagic = <int>[0x47, 0x49, 0x46, 0x38]; // GIF8
  static const List<int> _pdfMagic = <int>[0x25, 0x50, 0x44, 0x46]; // %PDF

  static bool _isAvifBrand(List<int> bytes) =>
      _hasAscii(bytes, 8, 'avif') || _hasAscii(bytes, 8, 'avis');

  static bool _isHeicBrand(List<int> bytes) =>
      _hasAscii(bytes, 8, 'heic') ||
      _hasAscii(bytes, 8, 'heix') ||
      _hasAscii(bytes, 8, 'heim') ||
      _hasAscii(bytes, 8, 'hevc') ||
      _hasAscii(bytes, 8, 'hevm') ||
      _hasAscii(bytes, 12, 'mif1') ||
      _hasAscii(bytes, 12, 'msf1');

  static bool _hasBytes(List<int> bytes, List<int> pattern, int offset) {
    if (bytes.length < offset + pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (bytes[offset + i] != pattern[i]) return false;
    }
    return true;
  }

  static bool _hasAscii(List<int> bytes, int offset, String text) =>
      _hasBytes(bytes, Uint8List.fromList(text.codeUnits), offset);
}
