import 'dart:io';

import 'package:dio/dio.dart';

import 'tus_upload_client.dart';

/// Production [TusTransport] over Dio implementing the tus 1.0 core protocol.
///
/// Chunks are read from disk on demand via a [RandomAccessFile] — the whole
/// video is never loaded into memory. Expiry / gone responses map to
/// [TusExpiredUploadException] so the client surfaces a clean "re-provision"
/// path.
class DioTusTransport implements TusTransport {
  DioTusTransport({required this.filePath, Dio? dio})
      : _dio = dio ?? Dio();

  final String filePath;
  final Dio _dio;

  static const String _tusVersion = '1.0.0';

  @override
  Future<int> head(String uploadUrl) async {
    try {
      final res = await _dio.head<void>(
        uploadUrl,
        options: Options(
          headers: {'Tus-Resumable': _tusVersion},
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode == 404 || res.statusCode == 410) {
        throw const TusExpiredUploadException();
      }
      final offset = res.headers.value('upload-offset');
      return int.tryParse(offset ?? '0') ?? 0;
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
          validateStatus: (s) => s != null && s < 500,
        ),
      );
      if (res.statusCode == 404 || res.statusCode == 410) {
        throw const TusExpiredUploadException();
      }
      final newOffset =
          int.tryParse(res.headers.value('upload-offset') ?? '') ??
              (offset + bytes.length);
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
