import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/ui/social_chat_thread_screen.dart';

void main() {
  group('social chat thread policy', () {
    test('relation required errors do not trigger thread recovery', () {
      final error = _dioError(403, 'RELATION_REQUIRED');

      expect(
        socialChatShouldRecoverMissingThread(
          error,
          hasPeerUserId: true,
          recoveryAttempted: false,
        ),
        isFalse,
      );
      expect(socialChatIsRelationRequiredThreadError(error), isTrue);
    });

    test('thread not found errors can recover when a peer user exists', () {
      final error = _dioError(404, 'THREAD_NOT_FOUND');

      expect(
        socialChatShouldRecoverMissingThread(
          error,
          hasPeerUserId: true,
          recoveryAttempted: false,
        ),
        isTrue,
      );
      expect(socialChatIsRelationRequiredThreadError(error), isFalse);
    });

    test('pending or blocked threads lock the composer', () {
      expect(
        socialChatShouldLockComposer(
          readOnly: false,
          monitorMode: false,
          pendingRequest: true,
          accessBlocked: false,
        ),
        isTrue,
      );
      expect(
        socialChatShouldLockComposer(
          readOnly: false,
          monitorMode: false,
          pendingRequest: false,
          accessBlocked: true,
        ),
        isTrue,
      );
      expect(
        socialChatShouldLockComposer(
          readOnly: false,
          monitorMode: false,
          pendingRequest: false,
          accessBlocked: false,
        ),
        isFalse,
      );
    });
  });
}

DioException _dioError(int statusCode, String code) {
  final requestOptions = RequestOptions(
    path: '/api/feed/chats/threads/1/messages',
  );
  return DioException(
    requestOptions: requestOptions,
    response: Response<dynamic>(
      requestOptions: requestOptions,
      statusCode: statusCode,
      data: <String, dynamic>{'code': code},
    ),
    type: DioExceptionType.badResponse,
  );
}
