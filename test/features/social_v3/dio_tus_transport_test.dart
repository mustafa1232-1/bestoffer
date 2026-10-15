import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/upload/dio_tus_transport.dart';

class _Adapter implements HttpClientAdapter {
  final received = <int>[];
  int calls = 0;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    calls++;
    final chunk = <int>[];
    if (requestStream != null) {
      await for (final bytes in requestStream) {
        chunk.addAll(bytes);
      }
    }
    expect(options.headers['Authorization'], isNull);
    expect(options.headers[Headers.contentLengthHeader], chunk.length);
    received.addAll(chunk);
    return ResponseBody.fromString(
      '',
      204,
      headers: {
        'upload-offset': [
          '${int.parse('${options.headers['Upload-Offset']}') + chunk.length}',
        ],
      },
    );
  }
}

void main() {
  test(
    'transport sends only the requested file range and validates short reads',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'maslaki-tus-test-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = await File(
        '${directory.path}/edited.mp4',
      ).writeAsBytes([11, 22, 33, 44, 55, 66]);
      final adapter = _Adapter();
      final dio = Dio()..httpClientAdapter = adapter;
      addTearDown(() => dio.close(force: true));
      final transport = DioTusTransport(filePath: file.path, dio: dio);
      final result = await transport.patch(
        'https://upload.test/tus',
        offset: 2,
        length: 3,
        total: 6,
      );
      expect(adapter.received, [33, 44, 55]);
      expect(result.offset, 5);
      expect(result.completed, isFalse);
      await expectLater(
        transport.patch(
          'https://upload.test/tus',
          offset: 5,
          length: 3,
          total: 8,
        ),
        throwsStateError,
      );
      expect(adapter.calls, 1);
    },
  );
}
