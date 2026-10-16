import 'package:flutter/foundation.dart';
import 'package:om_events/app/core/env.dart';
import 'package:om_events/app/core/errors/failures.dart';
import 'package:om_events/app/core/services/app_bootstrap.dart';
import 'package:om_events/data/models/media_ref.dart';

/// Input to the optional server-side optimisation step.
final class MediaOptimiseRequest {
  const MediaOptimiseRequest({
    required this.stagingPath,
    required this.finalPath,
    required this.mediaId,
    required this.bucket,
    required this.kind,
    required this.byteLength,
    required this.contentType,
    this.width,
    this.height,
  });

  final String stagingPath;
  final String finalPath;
  final String mediaId;
  final String bucket;
  final MediaKind kind;
  final int byteLength;
  final String contentType;
  final int? width;
  final int? height;

  Map<String, Object?> toMap() => <String, Object?>{
        'stagingPath': stagingPath,
        'finalPath': finalPath,
        'mediaId': mediaId,
        'bucket': bucket,
        'kind': kind.code,
        'bytes': byteLength,
        'contentType': contentType,
        'width': width,
        'height': height,
      };
}

/// What the optimisation step reports back.
///
/// Every field is optional because the step itself is optional: a deployment without the function
/// keeps the client's own dimensions and the planned final path.
final class MediaOptimiseResult {
  const MediaOptimiseResult({
    this.optimised = false,
    this.finalPath,
    this.width,
    this.height,
    this.byteLength,
    this.note,
  });

  const MediaOptimiseResult.passthrough() : this();

  final bool optimised;

  /// Where the publishable bytes ended up. Must stay inside the bucket; the pipeline refuses a
  /// path outside the managed prefixes.
  final String? finalPath;
  final int? width;
  final int? height;
  final int? byteLength;
  final String? note;
}

/// Port for "make the bytes better before we publish them".
///
/// The browser cannot transcode: this build has no image codec dependency, and adding one for a
/// step that only staff triggers is not worth the bundle weight. So the client uploads the file the
/// admin chose, and the *contract* for resizing/WebP conversion/quality stripping is this interface,
/// implemented by a Cloud Function when one is deployed. Until then [PassthroughOptimiseGateway]
/// publishes the original bytes and the documented limits still bound them.
abstract interface class MediaOptimiseGateway {
  bool get isEnabled;

  String get name;

  Future<MediaOptimiseResult> optimise(MediaOptimiseRequest request);
}

/// Default: no server step. Kept as an explicit class so the pipeline always has a gateway and the
/// "did we optimise?" question has one honest answer.
final class PassthroughOptimiseGateway implements MediaOptimiseGateway {
  const PassthroughOptimiseGateway();

  @override
  bool get isEnabled => false;

  @override
  String get name => 'passthrough';

  @override
  Future<MediaOptimiseResult> optimise(MediaOptimiseRequest request) async =>
      const MediaOptimiseResult.passthrough();
}

/// Wire contract the Cloud Function must satisfy. Documented in docs/supabase-storage.md.
abstract final class MediaOptimiseContract {
  static const String functionName = 'mediaOptimise';

  /// The response must carry this key when it moved or rewrote the object.
  static const String requiredObjectField = 'finalPath';
}

/// Calls the `mediaOptimise` Firebase Cloud Function (us-central1 by default), which holds the
/// Supabase service-role key and does the transcoding server-side.
///
/// Requires the function to be deployed; without Firebase configured the gateway reports itself
/// disabled so the pipeline stays on the passthrough path instead of failing every upload.
final class CallableMediaOptimiseGateway implements MediaOptimiseGateway {
  CallableMediaOptimiseGateway({String? functionName})
      : _functionName = functionName ?? MediaOptimiseContract.functionName;

  final String _functionName;

  @override
  bool get isEnabled => Env.hasFirebase;

  @override
  String get name => _functionName;

  @override
  Future<MediaOptimiseResult> optimise(MediaOptimiseRequest request) async {
    try {
      final response =
          await AppBootstrap.functions.httpsCallable(_functionName).call(request.toMap());
      final Object? data = response.data;
      if (data is! Map) {
        throw MediaFailure('The media optimisation step returned an unreadable result.');
      }
      final map = Map<Object?, Object?>.from(data);
      final path = map['finalPath'];
      final note = map['note'];
      return MediaOptimiseResult(
        optimised: map['optimised'] == true,
        finalPath: path is String ? path : null,
        width: (map['width'] as num?)?.round(),
        height: (map['height'] as num?)?.round(),
        byteLength: (map['bytes'] as num?)?.round(),
        note: note is String ? note : null,
      );
    } on OmFailure {
      rethrow;
    } catch (error) {
      debugPrint('mediaOptimise call failed: ${error.runtimeType}');
      throw MediaFailure(
        'The server-side image optimisation step could not run. The upload was not published — '
        'retry it, or disable optimisation in the media settings.',
      );
    }
  }
}
