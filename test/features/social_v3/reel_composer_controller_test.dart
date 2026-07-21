import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:maslaki/features/social_v3/composer/reel_composer_state.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';
import 'package:maslaki/features/social_v3/upload/reel_map_normalizer.dart';
import 'package:maslaki/features/social_v3/upload/tus_upload_client.dart';

class _OkServer implements TusTransport {
  int offset = 0;
  final int total;
  _OkServer(this.total);
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

class _FakeApi implements ReelUploadApi {
  _FakeApi({
    this.statuses = const ['processing', 'ready'],
    this.createFailure,
    this.publishFailure,
  });
  final List<String> statuses;
  final Object? createFailure;
  final Object? publishFailure;
  int _pollCount = 0;
  int createCalls = 0;
  int publishCalls = 0;
  final List<String> publishKeys = [];
  Map<String, dynamic>? lastReelStyle;

  @override
  Future<({String uploadUrl, int assetId})> createUploadSession({
    required int sizeBytes,
    required String mimeType,
    required String fileName,
    required String idempotencyKey,
  }) async {
    final failure = createFailure;
    if (failure != null) throw failure;
    createCalls++;
    return (uploadUrl: 'https://upload.test/tus/x', assetId: 555);
  }

  @override
  Future<String> pollStatus(int assetId) async {
    final s = statuses[_pollCount.clamp(0, statuses.length - 1)];
    _pollCount++;
    return s;
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
    final failure = publishFailure;
    if (failure != null) throw failure;
    publishCalls++;
    publishKeys.add(idempotencyKey);
    lastReelStyle = normalizeOptionalMap(reelStyle);
    return 9001;
  }
}

const _video = PickedSocialMedia(
  path: '/tmp/reel.mp4',
  name: 'reel.mp4',
  mimeType: 'video/mp4',
  sizeBytes: 8 * 1024 * 1024,
  type: PickedMediaType.video,
);

ReelComposerController _controller(_FakeApi api) {
  return ReelComposerController(
    api: api,
    idempotencyKey: 'idem-1',
    tusFactory: ({required uploadUrl, required totalBytes, required assetId}) {
      return TusUploadClient(
        transport: _OkServer(totalBytes),
        uploadUrl: uploadUrl,
        totalBytes: totalBytes,
        assetId: assetId,
        chunkSize: totalBytes,
      );
    },
  );
}

void main() {
  test('full publish lifecycle reaches published', () async {
    final api = _FakeApi();
    final c = _controller(api);
    await c.publish(video: _video, caption: 'hello', audience: 'public');
    expect(c.stage, ReelComposerStage.published);
    expect(c.publishedReelId, 9001);
    expect(api.createCalls, 1);
    expect(api.publishCalls, 1);
    c.dispose();
  });

  test('publishing fails closed when the asset never reaches ready', () async {
    final api = _FakeApi(statuses: const ['processing', 'failed']);
    final c = _controller(api);
    await c.publish(video: _video, caption: '', audience: 'public');
    expect(c.stage, ReelComposerStage.failed);
    expect(c.error, reelProcessingFailureMessage);
    expect(api.publishCalls, 0);
    c.dispose();
  });

  test('publish carries an idempotency key (retry-safe)', () async {
    final api = _FakeApi();
    final c = _controller(api);
    await c.publish(video: _video, caption: 'x', audience: 'public');
    expect(api.publishKeys, ['idem-1']);
    c.dispose();
  });

  test('publish forwards reel style payload to backend', () async {
    final api = _FakeApi();
    final c = _controller(api);
    await c.publish(
      video: _video,
      caption: 'x',
      audience: 'public',
      reelStyle: const {
        'version': 2,
        'mode': 'media',
        'layers': <Map<String, dynamic>>[],
      },
    );
    expect(api.lastReelStyle, isNotNull);
    expect(api.lastReelStyle?['mode'], 'media');
    expect(api.lastReelStyle?['version'], 2);
    c.dispose();
  });

  test('publish accepts deeply dynamic reel style maps', () async {
    final api = _FakeApi();
    final c = _controller(api);
    await c.publish(
      video: _video,
      caption: 'dynamic style',
      audience: 'public',
      reelStyle: <dynamic, dynamic>{
        'version': 2,
        'mode': 'media',
        77: 'numeric-key',
        'layers': <dynamic>[
          <dynamic, dynamic>{
            'type': 'text',
            12: <dynamic, dynamic>{'nested': true},
          },
        ],
      },
    );
    expect(c.stage, ReelComposerStage.published);
    expect(api.lastReelStyle?['77'], 'numeric-key');
    final layers = api.lastReelStyle?['layers'] as List<dynamic>;
    final firstLayer = layers.single as Map<String, dynamic>;
    expect(firstLayer['12'], isA<Map<String, dynamic>>());
    c.dispose();
  });

  test('invalid reel responses are hidden behind Arabic copy', () async {
    final api = _FakeApi(
      createFailure: const ReelInvalidResponseException(
        'UPLOAD_SESSION_INVALID_RESPONSE',
      ),
    );
    final c = _controller(api);
    await c.publish(video: _video, caption: '', audience: 'public');
    expect(c.stage, ReelComposerStage.failed);
    expect(c.error, reelInvalidResponseMessage);
    expect(c.error, isNot(contains('DioException')));
    expect(c.error, isNot(contains('_Map<dynamic')));
    expect(c.error, isNot(contains('Map<String, dynamic>')));
    expect(c.error, isNot(contains('RequestOptions')));
    c.dispose();
  });

  test('network Dio failures are hidden behind Arabic copy', () async {
    final api = _FakeApi(
      publishFailure: DioException(
        requestOptions: RequestOptions(path: '/api/feed/reels'),
        type: DioExceptionType.connectionError,
        error: 'socket',
      ),
    );
    final c = _controller(api);
    await c.publish(video: _video, caption: '', audience: 'public');
    expect(c.stage, ReelComposerStage.failed);
    expect(c.error, reelNetworkMessage);
    expect(c.error, isNot(contains('DioException')));
    expect(c.error, isNot(contains('_Map<dynamic')));
    expect(c.error, isNot(contains('Map<String, dynamic>')));
    expect(c.error, isNot(contains('RequestOptions')));
    c.dispose();
  });

  test(
    'stage transitions pass through processing before ready publish',
    () async {
      final api = _FakeApi(
        statuses: const ['processing', 'processing', 'ready'],
      );
      final c = _controller(api);
      final stages = <ReelComposerStage>[];
      c.addListener(() => stages.add(c.stage));
      await c.publish(video: _video, caption: 'x', audience: 'public');
      expect(stages, contains(ReelComposerStage.creatingSession));
      expect(stages, contains(ReelComposerStage.uploading));
      expect(stages, contains(ReelComposerStage.processing));
      expect(stages.last, ReelComposerStage.published);
      c.dispose();
    },
  );
}
