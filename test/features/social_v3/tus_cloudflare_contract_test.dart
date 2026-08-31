import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/upload/tus_upload_client.dart';

class _RecordingTusTransport implements TusTransport {
  final List<int> lengths = <int>[];
  int offset = 0;

  @override
  Future<int> head(String uploadUrl) async => offset;

  @override
  Future<TusTransportResult> patch(
    String uploadUrl, {
    required int offset,
    required int length,
    required int total,
  }) async {
    expect(offset, this.offset);
    lengths.add(length);
    this.offset += length;
    return TusTransportResult(
      offset: this.offset,
      completed: this.offset >= total,
    );
  }
}

void main() {
  test('default tus chunks follow Cloudflare 5 MiB minimum contract', () async {
    const fiveMiB = 5 * 1024 * 1024;
    const total = (2 * fiveMiB) + 123;
    final transport = _RecordingTusTransport();
    final client = TusUploadClient(
      transport: transport,
      uploadUrl: 'https://upload.example.invalid/tus',
      totalBytes: total,
      assetId: 1,
    );

    final state = await client.start();

    expect(state, TusUploadState.completed);
    expect(transport.lengths, <int>[fiveMiB, fiveMiB, 123]);
    await client.dispose();
  });
}
