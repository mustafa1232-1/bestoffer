import 'package:dio/dio.dart';

import '../composer/reel_composer_state.dart';

/// Production [ReelUploadApi] wired to the existing feed endpoints:
///  * `POST /api/feed/media/stream/upload-session` — provisions a one-time
///    Cloudflare Stream direct-upload (tus) URL. The video body never touches
///    the backend.
///  * `GET  /api/feed/media/assets/:id` — processing status (driven by the
///    Stream webhook + reconciliation worker).
///  * `POST /api/feed/reels` with `mediaAssetId` (no file body) — publishes the
///    reel from the already-uploaded, READY asset.
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
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/feed/media/stream/upload-session',
      data: {
        'sourceType': 'reel',
        'sizeBytes': sizeBytes,
        'fileName': fileName,
        'mimeType': mimeType,
      },
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final body = Map<String, dynamic>.from(response.data as Map);
    final session = Map<String, dynamic>.from(
      (body['uploadSession'] ?? body['upload_session'] ?? body) as Map,
    );
    final uploadUrl =
        (session['uploadUrl'] ?? session['upload_url'] ?? '').toString();
    final assetId =
        int.tryParse('${session['assetId'] ?? session['asset_id']}') ?? 0;
    if (uploadUrl.isEmpty || assetId <= 0) {
      throw StateError('UPLOAD_SESSION_INVALID_RESPONSE');
    }
    return (uploadUrl: uploadUrl, assetId: assetId);
  }

  @override
  Future<String> pollStatus(int assetId) async {
    final response =
        await _dio.get<Map<String, dynamic>>('/api/feed/media/assets/$assetId');
    final body = Map<String, dynamic>.from(response.data as Map);
    final asset = body['asset'] ?? body['mediaAsset'] ?? body['media_asset'] ?? body;
    final map = Map<String, dynamic>.from(asset as Map);
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
    required String idempotencyKey,
  }) async {
    // Multipart form WITHOUT a file — the backend publishes from mediaAssetId
    // via resolveSocialMediaAssetForPublishing (READY-gated, ownership-checked).
    final form = FormData.fromMap({
      'caption': caption,
      'postKind': 'reel',
      'mediaAssetId': assetId,
      'audienceScopeType': audience == 'public' ? 'global' : 'followers',
      'commentsEnabled': commentsEnabled.toString(),
      'sharingEnabled': sharingEnabled.toString(),
    });
    final response = await _dio.post<Map<String, dynamic>>(
      '/api/feed/reels',
      data: form,
      options: Options(headers: {'Idempotency-Key': idempotencyKey}),
    );
    final body = Map<String, dynamic>.from(response.data as Map);
    final reel = body['reel'] ?? body['post'] ?? body;
    final map = Map<String, dynamic>.from(reel as Map);
    return int.tryParse('${map['id']}') ?? 0;
  }
}
