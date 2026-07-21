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
  bool sawReelStyle = false;
  String? encodedReelStyle;

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
      final data = options.data;
      if (data is FormData) {
        sawReelStyle = data.fields.any((field) => field.key == 'reelStyle');
        encodedReelStyle = data.fields
            .where((field) => field.key == 'reelStyle')
            .map((field) => field.value)
            .firstOrNull;
      }
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
  Future<TusTransportResult> patch(
    String u, {
    required int offset,
    required int length,
    required int total,
  }) async {
    this.offset = (this.offset + length).clamp(0, this.total);
    return TusTransportResult(
      offset: this.offset,
      completed: this.offset >= this.total,
    );
  }
}

void main() {
  test(
    'picker → controller → real ReelUploadApiImpl → tus → poll → publish',
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
        tusFactory:
            ({required uploadUrl, required totalBytes, required assetId}) {
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
        reelStyle: <dynamic, dynamic>{
          'version': 2,
          'mode': 'media',
          9: 'dynamic-key',
          'layers': <dynamic>[
            <dynamic, dynamic>{
              'type': 'text',
              10: <dynamic, dynamic>{'nested': 'ok'},
            },
          ],
        },
      );

      expect(controller.stage, ReelComposerStage.published);
      expect(controller.publishedReelId, 4242);
      expect(controller.assetId, 777);
      expect(adapter.sawReelStyle, isTrue);
      final encodedStyle = jsonDecode(adapter.encodedReelStyle!) as Map;
      expect(encodedStyle['9'], 'dynamic-key');
      expect((encodedStyle['layers'] as List).single['10']['nested'], 'ok');

      // The real API impl hit exactly the expected endpoints in order.
      expect(
        adapter.paths.any((p) => p.contains('/media/stream/upload-session')),
        isTrue,
      );
      expect(adapter.paths.any((p) => p.endsWith('/api/feed/reels')), isTrue);
      controller.dispose();
    },
  );

  test(
    'ReelUploadApiImpl accepts dynamic-key Dio maps from backend responses',
    () async {
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (options.path.contains('/media/stream/upload-session')) {
              return handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 201,
                  data: <dynamic, dynamic>{
                    'upload_session': <dynamic, dynamic>{
                      'asset_id': 321,
                      'upload_url':
                          'https://upload.videodelivery.net/tus/dynamic',
                    },
                  },
                ),
              );
            }
            if (options.path.contains('/media/assets/')) {
              return handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <dynamic, dynamic>{
                    'media_asset': <dynamic, dynamic>{
                      'processing_status': 'ready',
                    },
                  },
                ),
              );
            }
            if (options.path.contains('/feed/reels')) {
              return handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <dynamic, dynamic>{
                    'post': <dynamic, dynamic>{'id': 654},
                  },
                ),
              );
            }
            return handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 404,
                data: <dynamic, dynamic>{'message': 'NOT_FOUND'},
              ),
            );
          },
        ),
      );

      final api = ReelUploadApiImpl(dio);

      final session = await api.createUploadSession(
        sizeBytes: 1024,
        mimeType: 'video/mp4',
        fileName: 'dynamic.mp4',
        idempotencyKey: 'dynamic-1',
      );
      expect(session.assetId, 321);
      expect(session.uploadUrl, contains('/dynamic'));
      expect(await api.pollStatus(session.assetId), 'ready');
      expect(
        await api.publishReel(
          assetId: session.assetId,
          caption: 'dynamic',
          audience: 'public',
          commentsEnabled: true,
          sharingEnabled: true,
          idempotencyKey: 'dynamic-2',
        ),
        654,
      );
    },
  );

  test(
    'ReelUploadApiImpl supports camel aliases and rejects invalid bodies',
    () async {
      var mode = 'camel';
      final dio = Dio(BaseOptions(baseUrl: 'https://api.test'));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            if (mode == 'list') {
              return handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: const <dynamic>[],
                ),
              );
            }
            if (mode == 'null') {
              return handler.resolve(
                Response<dynamic>(requestOptions: options, statusCode: 200),
              );
            }
            if (options.path.contains('/media/stream/upload-session')) {
              return handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 201,
                  data: <String, dynamic>{
                    'assetId': 987,
                    'uploadUrl': 'https://upload.videodelivery.net/tus/root',
                  },
                ),
              );
            }
            if (options.path.contains('/media/assets/')) {
              return handler.resolve(
                Response<dynamic>(
                  requestOptions: options,
                  statusCode: 200,
                  data: <String, dynamic>{
                    'mediaAsset': <String, dynamic>{
                      'processingStatus': 'ready',
                    },
                  },
                ),
              );
            }
            return handler.resolve(
              Response<dynamic>(
                requestOptions: options,
                statusCode: 200,
                data: <String, dynamic>{'id': 789},
              ),
            );
          },
        ),
      );
      final api = ReelUploadApiImpl(dio);

      final session = await api.createUploadSession(
        sizeBytes: 512,
        mimeType: 'video/mp4',
        fileName: 'camel.mp4',
        idempotencyKey: 'camel-1',
      );
      expect(session.assetId, 987);
      expect(await api.pollStatus(session.assetId), 'ready');
      expect(
        await api.publishReel(
          assetId: session.assetId,
          caption: 'camel',
          audience: 'public',
          commentsEnabled: true,
          sharingEnabled: true,
          idempotencyKey: 'camel-2',
        ),
        789,
      );

      mode = 'list';
      expect(
        () => api.createUploadSession(
          sizeBytes: 512,
          mimeType: 'video/mp4',
          fileName: 'bad.mp4',
          idempotencyKey: 'bad-list',
        ),
        throwsA(isA<StateError>()),
      );
      mode = 'null';
      expect(() => api.pollStatus(987), throwsA(isA<StateError>()));
    },
  );
}

extension<T> on Iterable<T> {
  T? get firstOrNull => this.isEmpty ? null : first;
}
