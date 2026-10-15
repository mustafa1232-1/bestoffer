import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/state/social_read_receipt_queue.dart';

void main() {
  testWidgets('read receipts stop after four attempts with backoff', (
    tester,
  ) async {
    var calls = 0;
    final queue = SocialReadReceiptQueue(
      canSend: () => true,
      send: (_) async {
        calls++;
        throw StateError('offline');
      },
    );
    addTearDown(queue.dispose);
    queue.request(5);
    await tester.pump();
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 999));
    expect(calls, 1);
    await tester.pump(const Duration(milliseconds: 1));
    expect(calls, 2);
    await tester.pump(const Duration(seconds: 2));
    expect(calls, 3);
    await tester.pump(const Duration(seconds: 4));
    expect(calls, 4);
    queue.request(5);
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 4);
    queue.resume();
    await tester.pump();
    expect(calls, 5);
    queue.dispose();
  });

  testWidgets('coalesces new cursors while a receipt is in flight', (
    tester,
  ) async {
    final first = Completer<int>();
    final sent = <int>[];
    final queue = SocialReadReceiptQueue(
      canSend: () => true,
      send: (id) {
        sent.add(id);
        return sent.length == 1 ? first.future : Future.value(id);
      },
    );
    addTearDown(queue.dispose);
    queue.request(5);
    queue.request(6);
    queue.request(9);
    expect(sent, [5]);
    first.complete(5);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 1));
    expect(sent, [5, 9]);
    queue.request(8);
    queue.request(9);
    await tester.pump();
    expect(sent, [5, 9]);
    queue.dispose();
  });

  testWidgets('paused background receipts wait and dispose cancels retries', (
    tester,
  ) async {
    var foreground = false;
    var calls = 0;
    final queue = SocialReadReceiptQueue(
      canSend: () => foreground,
      send: (_) async {
        calls++;
        throw StateError('offline');
      },
    );
    queue.request(8);
    await tester.pump();
    expect(calls, 0);
    foreground = true;
    queue.resume();
    await tester.pump();
    expect(calls, 1);
    foreground = false;
    queue.pause();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 1);
    foreground = true;
    queue.resume();
    await tester.pump();
    expect(calls, 2);
    queue.dispose();
    await tester.pump(const Duration(minutes: 1));
    expect(calls, 2);
  });
}
