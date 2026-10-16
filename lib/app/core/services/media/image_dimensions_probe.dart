import 'dart:typed_data';

/// Pixel size read out of an image header without decoding the image.
///
/// The pipeline must know the dimensions *before* a byte leaves the browser (never upload then
/// discover the problem), and the `image` package is not a dependency of this build, so the four
/// supported container formats are parsed directly. This is a header sniff, not a decoder: it
/// costs microseconds on the first kilobytes instead of a multi-megabyte decode.
final class ImageDimensions {
  const ImageDimensions({
    required this.width,
    required this.height,
    this.approximate = false,
    this.note,
  });

  final int width;
  final int height;

  /// True when the value came from a container whose true display size cannot be derived from the
  /// header alone (tiled AVIF). The validator treats an approximate reading as inconclusive
  /// instead of rejecting, so an ambiguous header can never block a legitimate upload.
  final bool approximate;
  final String? note;

  int get pixels => width * height;

  double get aspectRatio => height == 0 ? 1 : width / height;

  bool get isLandscape => width >= height;

  @override
  String toString() => '${width}x$height${approximate ? ' (approx)' : ''}';
}

abstract final class ImageDimensionsProbe {
  /// Returns null when the size cannot be determined; the caller decides whether that is a
  /// rejection or a warning, based on the format.
  static ImageDimensions? probe(List<int> bytes) {
    if (bytes.length < 12) return null;
    final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    final view = ByteData.sublistView(data);
    if (_isPng(data)) return _png(view, data.lengthInBytes);
    if (data[0] == 0xFF && data[1] == 0xD8) return _jpeg(data, view);
    if (_has(data, 0, _riff) && _has(data, 8, _webpTag)) return _webp(data, view);
    if (_has(data, 4, _ftyp)) return _avif(data, view);
    return null;
  }

  static const List<int> _riff = <int>[0x52, 0x49, 0x46, 0x46];
  static const List<int> _webpTag = <int>[0x57, 0x45, 0x42, 0x50];
  static const List<int> _ftyp = <int>[0x66, 0x74, 0x79, 0x70];

  static bool _isPng(List<int> data) =>
      data.length > 24 &&
      data[0] == 0x89 &&
      data[1] == 0x50 &&
      data[2] == 0x4E &&
      data[3] == 0x47;

  static bool _has(List<int> data, int offset, List<int> pattern) {
    if (data.length < offset + pattern.length) return false;
    for (var i = 0; i < pattern.length; i++) {
      if (data[offset + i] != pattern[i]) return false;
    }
    return true;
  }

  /// IHDR is always the first chunk: 8-byte signature, 4-byte length, 'IHDR', then width and
  /// height as big-endian 32-bit starting at byte 16.
  static ImageDimensions? _png(ByteData view, int length) {
    if (length < 24) return null;
    final width = view.getUint32(16);
    final height = view.getUint32(20);
    if (width == 0 || height == 0) return null;
    return ImageDimensions(width: width, height: height);
  }

  /// JPEG is a sequence of `FF <marker>` segments and the frame header (SOFn) carries the size.
  /// Everything before it is metadata (APPn/EXIF/ICC/DHT) that runs to hundreds of KB on a camera
  /// original, so the walk is bounded by a segment budget as well as by the file.
  static ImageDimensions? _jpeg(List<int> data, ByteData view) {
    var offset = 2;
    final limit = data.length - 4;
    var segments = 0;
    while (offset < limit && segments++ < 4096) {
      if (data[offset] != 0xFF) {
        offset++; // Stray padding between markers: keep scanning.
        continue;
      }
      final marker = data[offset + 1];
      if (marker == 0xFF || marker == 0x00 || marker == 0x01) {
        offset++;
        continue;
      }
      if (marker == 0xD8 || (marker >= 0xD0 && marker <= 0xD9)) {
        offset += 2; // Stand-alone markers carry no length field.
        continue;
      }
      if (marker == 0xDA) return null; // Start of scan: entropy-coded data, no header left.
      final isFrameHeader = marker >= 0xC0 &&
          marker <= 0xCF &&
          marker != 0xC4 && // DHT
          marker != 0xC8 && // JPGC
          marker != 0xCC; // DAC
      if (offset + 4 > data.length) return null;
      final segmentLength = view.getUint16(offset + 2);
      if (isFrameHeader) {
        // Payload after the 2-byte length field: precision(1), height(2), width(2).
        if (offset + 9 > data.length) return null;
        final height = view.getUint16(offset + 5);
        final width = view.getUint16(offset + 7);
        if (width == 0 || height == 0) return null;
        return ImageDimensions(width: width, height: height);
      }
      if (segmentLength < 2) return null;
      offset += 2 + segmentLength;
    }
    return null;
  }

  /// RIFF container: four-byte tag plus little-endian size, then payload. VP8X wins over VP8 and
  /// VP8L because it reports the canvas size of animated and profiled files.
  static ImageDimensions? _webp(List<int> data, ByteData view) {
    ImageDimensions? lossy;
    var offset = 12;
    while (offset + 8 <= data.length) {
      final tag = _ascii(data, offset, 4);
      final size = view.getUint32(offset + 4, Endian.little);
      final payload = offset + 8;
      if (size > data.length - payload) break; // Truncated container.
      if (tag == 'VP8X' && payload + 10 <= data.length) {
        final width =
            (data[payload + 4] | (data[payload + 5] << 8) | (data[payload + 6] << 16)) + 1;
        final height =
            (data[payload + 7] | (data[payload + 8] << 8) | (data[payload + 9] << 16)) + 1;
        if (width > 0 && height > 0) return ImageDimensions(width: width, height: height);
      }
      if (tag == 'VP8L' && data[payload] == 0x2F && payload + 5 <= data.length) {
        final bits = view.getUint32(payload + 1, Endian.little);
        final width = (bits & 0x3FFF) + 1;
        final height = ((bits >> 14) & 0x3FFF) + 1;
        if (width > 0 && height > 0) return ImageDimensions(width: width, height: height);
      }
      if (tag == 'VP8 ') {
        final read = _lossyFrame(data, payload);
        if (read != null) lossy = read;
      }
      // Chunks are word-aligned: an odd payload size is followed by one padding byte.
      offset = payload + size + (size.isOdd ? 1 : 0);
    }
    return lossy;
  }

  static ImageDimensions? _lossyFrame(List<int> data, int payload) {
    // 3-byte frame tag, then the 9D 01 2A start code, then 14-bit width and height.
    if (payload + 10 > data.length) return null;
    if (data[payload + 3] != 0x9D || data[payload + 4] != 0x01 || data[payload + 5] != 0x2A) {
      return null;
    }
    final width = (data[payload + 6] | (data[payload + 7] << 8)) & 0x3FFF;
    final height = (data[payload + 8] | (data[payload + 9] << 8)) & 0x3FFF;
    if (width == 0 || height == 0) return null;
    return ImageDimensions(width: width, height: height);
  }

  /// ISO base media file format (AVIF/HEIF). The `ispe` box under `iprp/ipco` is the image spatial
  /// extent. A tiled AVIF keeps one `ispe` per image item and the master item may be a grid
  /// derivation whose canvas size needs `iinf`/`ipma`/`grid` parsing — deliberately not attempted,
  /// which is why several extents are reported as approximate rather than guessed at.
  static ImageDimensions? _avif(List<int> data, ByteData view) {
    final found = <ImageDimensions>[];
    _walkBoxes(data, view, 0, data.length, 0, found);
    if (found.isEmpty) return null;
    var largest = found.first;
    for (final candidate in found) {
      if (candidate.pixels > largest.pixels) largest = candidate;
    }
    if (found.length == 1) return largest;
    return ImageDimensions(
      width: largest.width,
      height: largest.height,
      approximate: true,
      note: 'Container exposes ${found.length} image extents; the largest was used. '
          'Export JPEG, PNG or WebP for an exact size check.',
    );
  }

  static void _walkBoxes(
    List<int> data,
    ByteData view,
    int start,
    int end,
    int depth,
    List<ImageDimensions> out,
  ) {
    if (depth > 4) return;
    var offset = start;
    var boxes = 0;
    while (offset + 8 <= end && boxes++ < 2048) {
      var size = view.getUint32(offset);
      final type = _ascii(data, offset + 4, 4);
      var headerSize = 8;
      if (size == 1) {
        if (offset + 16 > end) return;
        final high = view.getUint32(offset + 8);
        final low = view.getUint32(offset + 12);
        if (high != 0) return; // A container beyond 4 GB is not one of our files.
        size = low;
        headerSize = 16;
      } else if (size == 0) {
        size = end - offset;
      }
      if (size < headerSize || offset + size > end) return; // Corrupt box: stop walking.
      final payloadStart = offset + headerSize;
      if (type == 'ispe' && payloadStart + 12 <= offset + size) {
        // version/flags (4 bytes) then width and height as big-endian 32-bit.
        final width = view.getUint32(payloadStart + 4);
        final height = view.getUint32(payloadStart + 8);
        if (width > 0 && height > 0) out.add(ImageDimensions(width: width, height: height));
      }
      final isContainer = type == 'iprp' ||
          type == 'ipco' ||
          type == 'moov' ||
          type == 'moof' ||
          type == 'ipma';
      if (isContainer) {
        _walkBoxes(data, view, payloadStart, offset + size, depth + 1, out);
      } else if (type == 'meta') {
        // `meta` is a full box: 4 version/flags bytes ahead of its children.
        _walkBoxes(data, view, payloadStart + 4, offset + size, depth + 1, out);
      }
      offset += size;
    }
  }

  static String _ascii(List<int> data, int offset, int length) {
    if (data.length < offset + length) return '';
    final buffer = StringBuffer();
    for (var i = 0; i < length; i++) {
      final byte = data[offset + i];
      if (byte < 0x20 || byte > 0x7E) return '';
      buffer.writeCharCode(byte);
    }
    return buffer.toString();
  }
}
