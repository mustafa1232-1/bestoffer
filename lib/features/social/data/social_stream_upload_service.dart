import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/files/local_media_file.dart';
import '../models/social_models.dart';
import 'social_api.dart';

class SocialStreamUploadService {
  static const Duration defaultReadyTimeout = Duration(minutes: 2);
  static const Duration defaultReadyPollInterval = Duration(seconds: 2);
  static const int defaultChunkSizeBytes = 1024 * 1024;

  final SocialApi api;
  final Dio dio;

  SocialStreamUploadService(this.api) : dio = api.dio;

  Future<SocialMediaAsset> uploadVideoAndWaitReady({
    required LocalMediaFile mediaFile,
    required String sourceType,
    String? title,
    void Function(double progress)? onProgress,
    Duration readyTimeout = defaultReadyTimeout,
    Duration readyPollInterval = defaultReadyPollInterval,
    // When false, publishing does NOT block on Cloudflare encoding: the method
    // returns as soon as the upload is accepted (asset is PROCESSING). The Story
    // is created immediately and reconciled PROCESSING → READY later.
    bool waitForReady = true,
  }) async {
    if (!mediaFile.isVideo) {
      throw StateError('Stream upload requires a video media file.');
    }

    final fileName = _resolvedFileName(mediaFile);
    final mimeType = _resolvedMimeType(mediaFile);
    final sizeBytes = await _resolveSizeBytes(mediaFile);
    if (sizeBytes <= 0) {
      throw StateError('Selected media has no readable bytes.');
    }

    final session =
        await _loadMatchingSession(
          mediaFile: mediaFile,
          sourceType: sourceType,
          sizeBytes: sizeBytes,
          mimeType: mimeType,
        ) ??
        await api.createStreamUploadSession(
          sourceType: sourceType,
          sizeBytes: sizeBytes,
          fileName: fileName,
          mimeType: mimeType,
          title: title ?? fileName,
        );

    final persistedKey = _buildSessionKey(
      assetId: session.assetId,
      sourceType: sourceType,
      filePath: mediaFile.path ?? '',
      sizeBytes: sizeBytes,
    );
    var uploadedBytes = 0;
    final persisted = await _loadPersistedSession(persistedKey);
    if (persisted != null) {
      uploadedBytes = persisted.uploadedBytes.clamp(0, sizeBytes).toInt();
    }

    final offsetFromServer = await _readUploadOffset(session.uploadUrl);
    if (offsetFromServer != null) {
      uploadedBytes = uploadedBytes > offsetFromServer
          ? uploadedBytes
          : offsetFromServer;
    }

    await _savePersistedSession(
      _PersistedSocialStreamUploadSession(
        key: persistedKey,
        assetId: session.assetId,
        streamUid: session.streamUid,
        uploadUrl: session.uploadUrl,
        sourceType: sourceType.toLowerCase().trim(),
        filePath: mediaFile.path ?? '',
        fileName: fileName,
        mimeType: mimeType,
        sizeBytes: sizeBytes,
        uploadedBytes: uploadedBytes,
        title: title ?? fileName,
        createdAt: DateTime.now().toUtc(),
        updatedAt: DateTime.now().toUtc(),
      ),
    );

    final completedBytes = await _uploadInChunks(
      mediaFile: mediaFile,
      uploadUrl: session.uploadUrl,
      totalBytes: sizeBytes,
      alreadyUploaded: uploadedBytes,
      onProgress: onProgress,
      sessionKey: persistedKey,
      assetId: session.assetId,
      sourceType: sourceType,
      title: title ?? fileName,
      fileName: fileName,
      mimeType: mimeType,
    );

    if (completedBytes < sizeBytes) {
      throw StateError('Stream upload did not reach the expected size.');
    }

    // Upload accepted. The Stream asset already exists (created by the upload
    // session) and is now PROCESSING with a persisted stream UID.
    if (!waitForReady) {
      // KEEP the persisted session (upload bytes == full): a create retry then
      // resumes with zero re-upload and reuses the SAME assetId — no duplicate
      // upload or media asset. It expires naturally if never reused.
      final processing = await api.getMediaAsset(session.assetId);
      return processing ?? _processingAssetFrom(session);
    }

    await _removePersistedSession(persistedKey);
    final asset = await _waitForAssetReady(
      session.assetId,
      timeout: readyTimeout,
      pollInterval: readyPollInterval,
    );
    if (asset == null || !asset.isReady) {
      // Do not fail the publish just because encoding is still running — return
      // the PROCESSING asset so the Story is created and reconciled later.
      final processing = asset ?? await api.getMediaAsset(session.assetId);
      return processing ?? _processingAssetFrom(session);
    }
    return asset;
  }

  /// Minimal PROCESSING asset synthesized from the accepted upload session, so a
  /// Story can be created immediately even before the media-asset row is
  /// re-fetched.
  SocialMediaAsset _processingAssetFrom(SocialMediaUploadSession session) {
    return SocialMediaAsset(
      id: session.assetId,
      provider: 'stream',
      streamUid: session.streamUid,
      normalizedUrl: null,
      posterUrl: null,
      playbackUrl: null,
      thumbnailUrl: null,
      aspectRatio: null,
      durationMs: null,
      failureCode: null,
      processingStatus: 'processing',
      createdAt: DateTime.now().toUtc(),
    );
  }

  Future<SocialMediaAsset?> waitForAssetReady(
    int assetId, {
    Duration timeout = defaultReadyTimeout,
    Duration pollInterval = defaultReadyPollInterval,
  }) async {
    return _waitForAssetReady(
      assetId,
      timeout: timeout,
      pollInterval: pollInterval,
    );
  }

  Future<SocialMediaAsset?> _waitForAssetReady(
    int assetId, {
    required Duration timeout,
    required Duration pollInterval,
  }) async {
    final startedAt = DateTime.now();
    SocialMediaAsset? latest;
    while (DateTime.now().difference(startedAt) < timeout) {
      latest = await api.getMediaAsset(assetId);
      if (latest != null) {
        final status = (latest.processingStatus ?? '').trim().toLowerCase();
        if (status == 'ready' || latest.isReady) {
          return latest;
        }
        if (status == 'failed' || status == 'rejected') {
          throw StateError('Stream processing failed.');
        }
      }
      await Future.delayed(pollInterval);
    }
    return latest;
  }

  Future<SocialMediaUploadSession?> _loadMatchingSession({
    required LocalMediaFile mediaFile,
    required String sourceType,
    required int sizeBytes,
    required String mimeType,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys().where((key) => key.startsWith(_sessionPrefix));
    for (final key in keys) {
      final persisted = _decodePersistedSession(prefs.getString(key));
      if (persisted == null) continue;
      if (persisted.sourceType != sourceType.trim().toLowerCase()) continue;
      if (persisted.filePath != (mediaFile.path ?? '')) continue;
      if (persisted.sizeBytes != sizeBytes) continue;
      if (persisted.mimeType != mimeType) continue;
      return SocialMediaUploadSession(
        assetId: persisted.assetId,
        streamUid: persisted.streamUid,
        uploadUrl: persisted.uploadUrl,
        sourceType: persisted.sourceType,
        mediaKind: 'video',
        processingStatus: 'pending',
        readyToStream: false,
        asset: null,
      );
    }
    return null;
  }

  Future<int> _uploadInChunks({
    required LocalMediaFile mediaFile,
    required String uploadUrl,
    required int totalBytes,
    required int alreadyUploaded,
    required void Function(double progress)? onProgress,
    required String sessionKey,
    required int assetId,
    required String sourceType,
    required String title,
    required String fileName,
    required String mimeType,
  }) async {
    var uploaded = alreadyUploaded.clamp(0, totalBytes).toInt();
    while (uploaded < totalBytes) {
      final end = (uploaded + defaultChunkSizeBytes)
          .clamp(0, totalBytes)
          .toInt();
      final chunk = await _readBytes(mediaFile, uploaded, end);
      final response = await dio.requestUri(
        Uri.parse(uploadUrl),
        data: chunk,
        options: Options(
          method: 'PATCH',
          responseType: ResponseType.plain,
          headers: <String, dynamic>{
            'Tus-Resumable': '1.0.0',
            'Upload-Offset': uploaded.toString(),
            'Upload-Length': totalBytes.toString(),
            'Content-Type': 'application/offset+octet-stream',
          },
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
        ),
      );
      final statusCode = response.statusCode ?? 0;
      if (statusCode != 200 && statusCode != 204) {
        throw StateError('Stream upload failed with status $statusCode.');
      }
      final serverOffset = int.tryParse(
        response.headers.value('upload-offset') ?? '',
      );
      uploaded = serverOffset ?? end;
      onProgress?.call(uploaded / totalBytes);
      await _savePersistedSession(
        _PersistedSocialStreamUploadSession(
          key: sessionKey,
          assetId: assetId,
          streamUid: '',
          uploadUrl: uploadUrl,
          sourceType: sourceType.toLowerCase().trim(),
          filePath: mediaFile.path ?? '',
          fileName: fileName,
          mimeType: mimeType,
          sizeBytes: totalBytes,
          uploadedBytes: uploaded,
          title: title,
          createdAt: DateTime.now().toUtc(),
          updatedAt: DateTime.now().toUtc(),
        ),
      );
    }
    return uploaded;
  }

  Future<int?> _readUploadOffset(String uploadUrl) async {
    try {
      final response = await dio.requestUri(
        Uri.parse(uploadUrl),
        options: Options(
          method: 'HEAD',
          validateStatus: (status) =>
              status != null && status >= 200 && status < 500,
          headers: const {'Tus-Resumable': '1.0.0'},
        ),
      );
      final header = response.headers.value('upload-offset');
      final offset = int.tryParse(header ?? '');
      return offset != null && offset >= 0 ? offset : null;
    } catch (_) {
      return null;
    }
  }

  Future<List<int>> _readBytes(
    LocalMediaFile mediaFile,
    int start,
    int end,
  ) async {
    if (mediaFile.bytes != null && mediaFile.bytes!.isNotEmpty) {
      return Uint8List.fromList(mediaFile.bytes!.sublist(start, end));
    }
    final filePath = mediaFile.path;
    if (filePath == null || filePath.trim().isEmpty) {
      throw StateError('Media file path is required for Stream upload.');
    }
    final file = File(filePath);
    final builder = BytesBuilder(copy: false);
    await for (final chunk in file.openRead(start, end)) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<int> _resolveSizeBytes(LocalMediaFile mediaFile) async {
    if (mediaFile.sizeBytes != null && mediaFile.sizeBytes! > 0) {
      return mediaFile.sizeBytes!;
    }
    if (mediaFile.bytes != null && mediaFile.bytes!.isNotEmpty) {
      return mediaFile.bytes!.length;
    }
    final filePath = mediaFile.path;
    if (filePath == null || filePath.trim().isEmpty) return 0;
    return File(filePath).length();
  }

  String _resolvedFileName(LocalMediaFile mediaFile) {
    final raw = mediaFile.name.trim();
    if (raw.isNotEmpty) return raw;
    final filePath = mediaFile.path;
    if (filePath == null || filePath.trim().isEmpty) return 'social_video';
    final base = p.basename(filePath.trim());
    return base.isNotEmpty ? base : 'social_video';
  }

  String _resolvedMimeType(LocalMediaFile mediaFile) {
    final raw = (mediaFile.mimeType ?? '').trim();
    if (raw.isNotEmpty) return raw;
    final ext = p
        .extension(_resolvedFileName(mediaFile))
        .replaceFirst('.', '')
        .toLowerCase();
    switch (ext) {
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      case 'webm':
        return 'video/webm';
      case 'mkv':
        return 'video/x-matroska';
      case '3gp':
        return 'video/3gpp';
      default:
        return 'video/mp4';
    }
  }

  String _buildSessionKey({
    required int assetId,
    required String sourceType,
    required String filePath,
    required int sizeBytes,
  }) {
    return '$_sessionPrefix:$assetId:${sourceType.trim().toLowerCase()}:${Uri.encodeComponent(filePath)}:$sizeBytes';
  }

  Future<void> _savePersistedSession(
    _PersistedSocialStreamUploadSession session,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(session.key, jsonEncode(session.toJson()));
  }

  Future<_PersistedSocialStreamUploadSession?> _loadPersistedSession(
    String key,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    return _decodePersistedSession(prefs.getString(key), fallbackKey: key);
  }

  Future<void> _removePersistedSession(String key) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(key);
  }

  _PersistedSocialStreamUploadSession? _decodePersistedSession(
    String? raw, {
    String? fallbackKey,
  }) {
    if (raw == null || raw.trim().isEmpty) return null;
    try {
      final map = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      return _PersistedSocialStreamUploadSession.fromJson(
        map,
        fallbackKey: fallbackKey,
      );
    } catch (_) {
      return null;
    }
  }
}

const String _sessionPrefix = 'social_stream_upload_session';

class _PersistedSocialStreamUploadSession {
  final String key;
  final int assetId;
  final String streamUid;
  final String uploadUrl;
  final String sourceType;
  final String filePath;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final int uploadedBytes;
  final String title;
  final DateTime createdAt;
  final DateTime updatedAt;

  const _PersistedSocialStreamUploadSession({
    required this.key,
    required this.assetId,
    required this.streamUid,
    required this.uploadUrl,
    required this.sourceType,
    required this.filePath,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.uploadedBytes,
    required this.title,
    required this.createdAt,
    required this.updatedAt,
  });

  factory _PersistedSocialStreamUploadSession.fromJson(
    Map<String, dynamic> json, {
    String? fallbackKey,
  }) {
    return _PersistedSocialStreamUploadSession(
      key: '${json['key'] ?? fallbackKey ?? ''}',
      assetId: int.tryParse('${json['assetId'] ?? json['asset_id'] ?? 0}') ?? 0,
      streamUid: '${json['streamUid'] ?? json['stream_uid'] ?? ''}',
      uploadUrl: '${json['uploadUrl'] ?? json['upload_url'] ?? ''}',
      sourceType: '${json['sourceType'] ?? json['source_type'] ?? ''}',
      filePath: '${json['filePath'] ?? json['file_path'] ?? ''}',
      fileName: '${json['fileName'] ?? json['file_name'] ?? ''}',
      mimeType: '${json['mimeType'] ?? json['mime_type'] ?? 'video/mp4'}',
      sizeBytes:
          int.tryParse('${json['sizeBytes'] ?? json['size_bytes'] ?? 0}') ?? 0,
      uploadedBytes:
          int.tryParse(
            '${json['uploadedBytes'] ?? json['uploaded_bytes'] ?? 0}',
          ) ??
          0,
      title: '${json['title'] ?? ''}',
      createdAt:
          DateTime.tryParse(
            '${json['createdAt'] ?? json['created_at'] ?? ''}',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      updatedAt:
          DateTime.tryParse(
            '${json['updatedAt'] ?? json['updated_at'] ?? ''}',
          ) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
    'key': key,
    'assetId': assetId,
    'streamUid': streamUid,
    'uploadUrl': uploadUrl,
    'sourceType': sourceType,
    'filePath': filePath,
    'fileName': fileName,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'uploadedBytes': uploadedBytes,
    'title': title,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}
