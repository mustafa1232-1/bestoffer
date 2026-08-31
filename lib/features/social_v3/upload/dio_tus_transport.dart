import 'dart:io';

import 'package:dio/dio.dart';

import 'tus_upload_client.dart';

/// Production [TusTransport] over Dio implementing the tus 1.0 core protocol.
///
/// Chunks are read from disk on demand via a [RandomAccessFile] — the whole
/// video is never loaded into memory. This transport intentionally uses a
/// dedicated Dio instance with no Maslaki API interceptors so backend auth,
/// request signing and the API's short generic timeout are never sent/applied
/// to the one-time Cloudflare upload URL.
class DioTusTransport implements TusTransport {
  DioTusTransport({required this.filePath, Dio? dio})
      : _dio =
            dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 20),
                sendTimeout: const Duration(minutes: 2),
                receiveTimeout: const Duration(seconds: 30),
                responseType: ResponseType.plain,
              ),
            );

  final String filePath;
  final Dio _dio;

  static const String _tusVersion = '1.0.0';

  @override
  Future<int> head(String uploadUrl) async {
    try {
      final res = await _dio.head<void>(
        uploadUrl,
        options: Options(
          headers: const {'Tus-Resumable': _tusVersion},
          validateStatus: (_) => true,
        ),
      );
      final status = res.statusCode ?? 0;
      if (status == 404 || status == 410) {
        throw const TusExpiredUploadException();
      }
      if (status < 200 || status >= 300) {
        throw DioException.badResponse(
          statusCode: status,
          requestOptions: res.requestOptions,
          response: res,
        );
      }
      final rawOffset = res.headers.value('upload-offset');
      final offset = int.tryParse(rawOffset ?? '');
      if (offset == null || offset < 0) {
        throw StateError('TUS_HEAD_MISSING_UPLOAD_OFFSET');
      }
      return offset;
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 410) {
        throw const TusExpiredUploadException();
      }
      rethrow;
    }
  }

  @override
  Future<TusTransportResult> patch(
    String uploadUrl, {
    required int offset,
    required int length,
    required int total,
  }) async {
    final raf = await File(filePath).open();
    try {
      await raf.setPosition(offset);
      final bytes = await raf.read(length);
      if (bytes.isEmpty && offset < total) {
        throw StateError('TUS_SOURCE_ENDED_BEFORE_UPLOAD_LENGTH');
      }
      final res = await _dio.patchUri<void>(
        Uri.parse(uploadUrl),
        data: Stream<List<int>>.fromIterable([bytes]),
        options: Options(
          headers: {
            'Tus-Resumable': _tusVersion,
            'Upload-Offset': '$offset',
            'Content-Type': 'application/offset+octet-stream',
            Headers.contentLengthHeader: bytes.length,
          },
          validateStatus: (_) => true,
        ),
      );
      final status = res.statusCode ?? 0;
      if (status == 404 || status == 410) {
        throw const TusExpiredUploadException();
      }
      // 409/412 and every other non-success response must be retried through
      // TusUploadClient, which performs an authoritative HEAD before retrying.
      // Never infer progress from a failed response.
      if (status < 200 || status >= 300) {
        throw DioException.badResponse(
          statusCode: status,
          requestOptions: res.requestOptions,
          response: res,
        );
      }
      final rawOffset = res.headers.value('upload-offset');
      final newOffset = int.tryParse(rawOffset ?? '');
      if (newOffset == null || newOffset < offset || newOffset > total) {
        throw StateError('TUS_PATCH_INVALID_UPLOAD_OFFSET');
      }
      return TusTransportResult(
        offset: newOffset,
        completed: newOffset >= total,
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 404 || e.response?.statusCode == 410) {
        throw const TusExpiredUploadException();
      }
      rethrow;
    } finally {
      await raf.close();
    }
  }
}
