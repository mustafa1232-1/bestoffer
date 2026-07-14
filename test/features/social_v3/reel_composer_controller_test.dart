import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/composer/reel_composer_state.dart';
import 'package:maslaki/features/social_v3/pickers/social_media_picker_v3.dart';
import 'package:maslaki/features/social_v3/upload/tus_upload_client.dart';

class _OkServer implements TusTransport {
  int offset = 0;
  final int total;
  _OkServer(this.total);
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

class _FakeApi implements ReelUploadApi {
  _FakeApi({this.statuses = const ['processing', 'ready']});
  final List<String> statuses;
  int _pollCount = 0;
  int createCalls = 0;
  int publishCalls = 0;
  final List<String> publishKeys = [];

  @override
  Future<({String uploadUrl, int assetId})> createUploadSession({
    required int sizeBytes,
    required String mimeType,
    required String fileName,
    required String idempotencyKey,
  }) async {
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
    required String idempotencyKey,
  }) async {
    publishCalls++;
    publishKeys.add(idempotencyKey);
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
    await c.publish(
      video: _video,
      caption: 'hello',
      audience: 'public',
      pollInterval: Duration.zero,
    );
    expect(c.stage, ReelComposerStage.published);
    expect(c.publishedReelId, 9001);
    expect(api.createCalls, 1);
    expect(api.publishCalls, 1);
    c.dispose();
  });

  test('processing failure stops before publish', () async {
    final api = _FakeApi(statuses: const ['processing', 'failed']);
    final c = _controller(api);
    await c.publish(
      video: _video,
      caption: '',
      audience: 'public',
      pollInterval: Duration.zero,
    );
    expect(c.stage, ReelComposerStage.failed);
    expect(api.publishCalls, 0, reason: 'must not publish a failed asset');
    c.dispose();
  });

  test('publish carries an idempotency key (retry-safe)', () async {
    final api = _FakeApi();
    final c = _controller(api);
    await c.publish(
      video: _video,
      caption: 'x',
      audience: 'public',
      pollInterval: Duration.zero,
    );
    expect(api.publishKeys, ['idem-1']);
    c.dispose();
  });

  test('stage transitions pass through processing', () async {
    final api = _FakeApi(statuses: const ['processing', 'processing', 'ready']);
    final c = _controller(api);
    final stages = <ReelComposerStage>[];
    c.addListener(() => stages.add(c.stage));
    await c.publish(
      video: _video,
      caption: 'x',
      audience: 'public',
      pollInterval: Duration.zero,
    );
    expect(stages, contains(ReelComposerStage.creatingSession));
    expect(stages, contains(ReelComposerStage.uploading));
    expect(stages, contains(ReelComposerStage.processing));
    expect(stages.last, ReelComposerStage.published);
    c.dispose();
  });
}
