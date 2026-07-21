import 'dart:convert';

import 'package:dio/dio.dart';

import '../composer/reel_composer_state.dart';
import 'reel_map_normalizer.dart';

/// Production [ReelUploadApi] wired to the existing feed endpoints:
///  * `POST /api/feed/media/stream/upload-session` — provisions a one-time
///    Cloudflare Stream direct-upload (tus) URL. The video body never touches
///    the backend.
///  * `GET  /api/feed/media/assets/:id` — processing status (driven by the
///    Stream webhook + reconciliation worker).
///  * `POST /api/feed/reels` with `mediaAssetId` (no file body) — publishes the
///    reel from the already-uploaded asset while it is still PROCESSING; the
///    backend reconciles it to READY independently.
///
/// Cloudflare credentials stay on the backend; this client only ever handles the
/// one-time upload URL it is handed.
class ReelUploadApiImpl implements ReelUploadApi {
  ReelUploadApiImpl(this._dio);

  final Dio _dio;

  @override
  Future<({String uploadUrl, int assetId})> createUploadSession({
    required int sizeBytes,
    required String mimeType,
    required String fileName,
    required String idempotencyKey,
  }) async {
    final response = await _dio.post<dynamic>(
      '/api/feed/media/stream/upload-session',
      data: {
        'sourceType': 'reel',
        'sizeBytes': sizeBytes,
        'fileName': fileName,
        'mimeType': mimeType,
      },
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final body = requireStringMap(
      response.data,
      'UPLOAD_SESSION_INVALID_RESPONSE',
    );
    final session = requireStringMap(
      body['uploadSession'] ?? body['upload_session'] ?? body,
      'UPLOAD_SESSION_INVALID_RESPONSE',
    );
    final uploadUrl = (session['uploadUrl'] ?? session['upload_url'] ?? '')
        .toString();
    final assetId =
        int.tryParse('${session['assetId'] ?? session['asset_id']}') ?? 0;
    if (uploadUrl.isEmpty || assetId <= 0) {
      throw const ReelInvalidResponseException(
        'UPLOAD_SESSION_INVALID_RESPONSE',
      );
    }
    return (uploadUrl: uploadUrl, assetId: assetId);
  }

  @override
  Future<String> pollStatus(int assetId) async {
    final response = await _dio.get<dynamic>('/api/feed/media/assets/$assetId');
    final body = requireStringMap(response.data, 'REEL_ASSET_INVALID_RESPONSE');
    final asset =
        body['asset'] ?? body['mediaAsset'] ?? body['media_asset'] ?? body;
    final map = requireStringMap(asset, 'REEL_ASSET_INVALID_RESPONSE');
    return (map['processingStatus'] ?? map['processing_status'] ?? 'processing')
        .toString();
  }

  @override
  Future<int> publishReel({
    required int assetId,
    required String caption,
    required String audience,
    required bool commentsEnabled,
    required bool sharingEnabled,
    Object? reelStyle,
    required String idempotencyKey,
  }) async {
    // Multipart form WITHOUT a file — the backend publishes from mediaAssetId
    // via resolveSocialMediaAssetForPublishing (ownership-checked and allowed
    // while PROCESSING for reels).
    final normalizedReelStyle = normalizeOptionalMap(reelStyle);
    final form = FormData.fromMap({
      'caption': caption,
      'postKind': 'reel',
      'mediaAssetId': assetId,
      'audienceScopeType': audience == 'public' ? 'global' : 'followers',
      'commentsEnabled': commentsEnabled.toString(),
      'sharingEnabled': sharingEnabled.toString(),
      if (normalizedReelStyle != null)
        'reelStyle': jsonEncode(normalizedReelStyle),
    });
    final response = await _dio.post<dynamic>(
      '/api/feed/reels',
      data: form,
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final body = requireStringMap(
      response.data,
      'REEL_PUBLISH_INVALID_RESPONSE',
    );
    final reel = body['reel'] ?? body['post'] ?? body;
    final map = requireStringMap(reel, 'REEL_PUBLISH_INVALID_RESPONSE');
    final reelId = int.tryParse('${map['id']}') ?? 0;
    if (reelId <= 0) {
      throw const ReelInvalidResponseException('REEL_PUBLISH_INVALID_RESPONSE');
    }
    return reelId;
  }
}

Map<String, dynamic> requireStringMap(dynamic raw, String code) {
  if (raw is! Map) {
    throw StateError('استجابة الفيديو غير صالحة ($code). حاول مرة أخرى.');
  }
  return normalizeReelMap(raw, code);
}
