import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social_v3/upload/tus_upload_client.dart';

/// A fake tus server. Holds an authoritative offset and can be told to fail,
/// expire, or interrupt so we can exercise the whole recovery matrix.
class FakeTusServer implements TusTransport {
  FakeTusServer({required this.total});

  final int total;
  int serverOffset = 0;

  int failNextPatches = 0; // transient failures (network/provider)
  bool expired = false;
  int? interruptAtOffset; // throw once when reaching/passing this offset
  bool _interrupted = false;
  int headCalls = 0;
  int patchCalls = 0;

  @override
  Future<int> head(String uploadUrl) async {
    headCalls++;
    if (expired) throw const TusExpiredUploadException();
    return serverOffset;
  }

  @override
  Future<TusTransportResult> patch(
    String uploadUrl, {
    required int offset,
    required int length,
    required int total,
  }) async {
    patchCalls++;
    if (expired) throw const TusExpiredUploadException();
    if (failNextPatches > 0) {
      failNextPatches--;
      throw Exception('network timeout');
    }
    // Offset mismatch: ignore the write, report the true offset.
    if (offset != serverOffset) {
      return TusTransportResult(offset: serverOffset);
    }
    if (interruptAtOffset != null &&
        !_interrupted &&
        serverOffset + length >= interruptAtOffset!) {
      _interrupted = true;
      throw Exception('interrupted');
    }
    serverOffset = (serverOffset + length).clamp(0, this.total);
    return TusTransportResult(
      offset: serverOffset,
      completed: serverOffset >= this.total,
    );
  }
}

TusUploadClient _client(
  FakeTusServer server, {
  int total = 20 * 1024 * 1024,
  int chunk = 8 * 1024 * 1024,
  int initialOffset = 0,
  Future<void> Function(TusSessionSnapshot)? persist,
}) {
  return TusUploadClient(
    transport: server,
    uploadUrl: 'https://upload.videodelivery.net/tus/abc',
    totalBytes: total,
    assetId: 42,
    chunkSize: chunk,
    initialOffset: initialOffset,
    persist: persist,
  );
}

void main() {
  const total = 20 * 1024 * 1024; // 20 MB, 3 chunks at 8 MB

  test('normal upload completes', () async {
    final server = FakeTusServer(total: total);
    final client = _client(server);
    final state = await client.start();
    expect(state, TusUploadState.completed);
    expect(server.serverOffset, total);
    await client.dispose();
  });

  test('interruption at ~10% recovers and completes', () async {
    final server = FakeTusServer(total: total)
      ..interruptAtOffset = (total * 0.1).round();
    final client = _client(server, chunk: 1024 * 1024); // 1MB chunks
    // A single transient interrupt is retried and recovered within one run.
    final state = await client.start();
    expect(state, TusUploadState.completed);
    expect(server.serverOffset, total);
    await client.dispose();
  });

  test('interruption at ~80% recovers and completes', () async {
    final server = FakeTusServer(total: total)
      ..interruptAtOffset = (total * 0.8).round();
    final client = _client(server, chunk: 1024 * 1024);
    await client.start();
    final s2 = await client.start();
    expect(s2, TusUploadState.completed);
    expect(server.serverOffset, total);
    await client.dispose();
  });

  test('offset mismatch is reconciled from the server', () async {
    final server = FakeTusServer(total: total);
    server.serverOffset = 4 * 1024 * 1024; // server already has 4MB
    // Client thinks it is at 0; start() HEADs first and syncs to 4MB.
    final client = _client(server);
    final state = await client.start();
    expect(state, TusUploadState.completed);
    await client.dispose();
  });

  test('expired upload URL surfaces TusExpiredUploadException', () async {
    final server = FakeTusServer(total: total)..expired = true;
    final client = _client(server);
    await expectLater(client.start(), throwsA(isA<TusExpiredUploadException>()));
    expect(client.state, TusUploadState.failed);
    await client.dispose();
  });

  test('cancellation stops the upload', () async {
    final server = FakeTusServer(total: total);
    final client = _client(server, chunk: 1024 * 1024);
    client.cancel();
    final state = await client.start();
    expect(state, TusUploadState.cancelled);
    await client.dispose();
  });

  test('transient failures are retried then succeed', () async {
    final server = FakeTusServer(total: total)..failNextPatches = 2;
    final client = _client(server, chunk: total); // single chunk
    final state = await client.start();
    expect(state, TusUploadState.completed);
    expect(server.patchCalls, greaterThan(1));
    await client.dispose();
  });

  test('retry exhaustion fails cleanly', () async {
    final server = FakeTusServer(total: total)..failNextPatches = 999;
    final client = TusUploadClient(
      transport: server,
      uploadUrl: 'u',
      totalBytes: total,
      assetId: 1,
      chunkSize: total,
      maxRetries: 2,
    );
    final state = await client.start();
    expect(state, TusUploadState.failed);
    await client.dispose();
  });

  test('app restart recovery resumes from a persisted snapshot', () async {
    final server = FakeTusServer(total: total);
    server.serverOffset = 12 * 1024 * 1024; // 12MB already uploaded pre-restart
    TusSessionSnapshot? saved;
    final client = _client(
      server,
      initialOffset: 12 * 1024 * 1024,
      persist: (s) async => saved = s,
    );
    final state = await client.start();
    expect(state, TusUploadState.completed);
    expect(saved, isNotNull);
    expect(saved!.assetId, 42);
    await client.dispose();
  });

  test('duplicate completion is idempotent (already at total)', () async {
    final server = FakeTusServer(total: total)..serverOffset = total;
    final client = _client(server);
    final state = await client.start();
    expect(state, TusUploadState.completed);
    // Starting again stays completed, no extra patches.
    final patchesBefore = server.patchCalls;
    final again = await client.start();
    expect(again, TusUploadState.completed);
    expect(server.patchCalls, patchesBefore);
    await client.dispose();
  });

  test('progress stream reports increasing fractions to 1.0', () async {
    final server = FakeTusServer(total: total);
    final client = _client(server, chunk: 1024 * 1024);
    final fractions = <double>[];
    final sub = client.progress.listen((p) => fractions.add(p.fraction));
    await client.start();
    await Future<void>.delayed(Duration.zero);
    expect(fractions.isNotEmpty, isTrue);
    expect(fractions.last, 1.0);
    await sub.cancel();
    await client.dispose();
  });
}
