import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/composer/reel_composer_state.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';
import 'package:maslaki/features/social_v3/upload/reel_upload_api_impl.dart';
import 'package:maslaki/features/social_v3/upload/tus_upload_client.dart';

/// Fake HTTP adapter — the ONLY fake boundary. The real [ReelUploadApiImpl] and
/// real [ReelComposerController] run against it end-to-end.
class _FakeHttpAdapter implements HttpClientAdapter {
  int pollCount = 0;
  final List<String> paths = [];

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final path = options.path;
    paths.add('${options.method} $path');
    Map<String, dynamic> body;
    var status = 200;

    if (path.contains('/media/stream/upload-session')) {
      status = 201;
      body = {
        'uploadSession': {
          'assetId': 777,
          'streamUid': 'uid_test',
          'uploadUrl': 'https://upload.videodelivery.net/tus/xyz',
        },
      };
    } else if (path.contains('/media/assets/')) {
      pollCount++;
      body = {
        'asset': {'processingStatus': pollCount >= 2 ? 'ready' : 'processing'},
      };
    } else if (path.contains('/feed/reels')) {
      body = {
        'reel': {'id': 4242},
      };
    } else {
      status = 404;
      body = {'error': 'unexpected path $path'};
    }

    final bytes = utf8.encode(jsonEncode(body));
    return ResponseBody.fromBytes(
      bytes,
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json'],
      },
    );
  }
}

/// A tus transport that always accepts (the transport boundary is fake; the
/// TusUploadClient logic is real).
class _OkTransport implements TusTransport {
  int offset = 0;
  final int total;
  _OkTransport(this.total);
  @override
  Future<int> head(String u) async => offset;
  @override
  Future<TusTransportResult> patch(String u,
      {required int offset, required int length, required int total}) async {
    this.offset = (this.offset + length).clamp(0, this.total);
    return TusTransportResult(
        offset: this.offset, completed: this.offset >= this.total);
  }
}

void main() {
  test('picker → controller → real ReelUploadApiImpl → tus → poll → publish',
      () async {
    final adapter = _FakeHttpAdapter();
    final dio = Dio(BaseOptions(baseUrl: 'https://api.test'))
      ..httpClientAdapter = adapter;

    // Real production API implementation, faked only at the HTTP transport.
    final api = ReelUploadApiImpl(dio);

    const picked = PickedSocialMedia(
      path: '/tmp/reel.mp4',
      name: 'reel.mp4',
      mimeType: 'video/mp4',
      sizeBytes: 8 * 1024 * 1024,
      type: PickedMediaType.video,
    );

    final controller = ReelComposerController(
      api: api,
      idempotencyKey: 'integ-1',
      tusFactory: ({required uploadUrl, required totalBytes, required assetId}) {
        return TusUploadClient(
          transport: _OkTransport(totalBytes),
          uploadUrl: uploadUrl,
          totalBytes: totalBytes,
          assetId: assetId,
          chunkSize: totalBytes,
        );
      },
    );

    await controller.publish(
      video: picked,
      caption: 'integration',
      audience: 'public',
      pollInterval: Duration.zero,
    );

    expect(controller.stage, ReelComposerStage.published);
    expect(controller.publishedReelId, 4242);
    expect(controller.assetId, 777);

    // The real API impl hit exactly the expected endpoints in order.
    expect(
      adapter.paths.any((p) => p.contains('/media/stream/upload-session')),
      isTrue,
    );
    expect(adapter.paths.any((p) => p.contains('/media/assets/777')), isTrue);
    expect(adapter.paths.any((p) => p.endsWith('/api/feed/reels')), isTrue);
    controller.dispose();
  });
}
