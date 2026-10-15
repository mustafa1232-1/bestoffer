import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_ai_chat_review_screen.dart';

class _FakeAdminApi extends AdminApi {
  _FakeAdminApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> aiChatReviewUsers({
    String? search,
    int limit = 40,
    int offset = 0,
  }) async {
    return {
      'total': 1,
      'items': [
        {
          'customer_user_id': 7,
          'full_name': 'مستخدم الاختبار',
          'phone': '07800000000',
          'sessions_count': 1,
          'messages_count': 2,
          'last_message_at': '2026-09-26T10:00:00.000Z',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> aiChatReviewUserSessions({
    required int customerUserId,
    int limit = 40,
    int offset = 0,
  }) async {
    return {
      'total': 1,
      'items': [
        {
          'id': 70,
          'customer_user_id': customerUserId,
          'title': 'البحث عن مطعم',
          'phone': '07800000000',
          'messages_count': 2,
          'last_message_text': 'هذه أفضل الخيارات',
          'last_message_at': '2026-09-26T10:00:00.000Z',
          'created_at': '2026-09-26T09:58:00.000Z',
        },
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> aiChatReviewMessages({
    required int sessionId,
    int limit = 160,
    int? beforeId,
  }) async {
    return {
      'items': [
        {
          'id': 2,
          'session_id': sessionId,
          'role': 'assistant',
          'text': 'هذه أفضل الخيارات المتاحة.',
          'created_at': '2026-09-26T10:00:00.000Z',
          'metadata': {'assistDomain': 'commerce'},
        },
        {
          'id': 1,
          'session_id': sessionId,
          'role': 'user',
          'text': 'أريد مطعماً قريباً.',
          'created_at': '2026-09-26T09:59:00.000Z',
        },
      ],
    };
  }
}

void main() {
  testWidgets('mobile AI review drills from users to sessions to messages', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminApiProvider.overrideWithValue(_FakeAdminApi())],
        child: const MaterialApp(home: AdminAiChatReviewScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('مراجعة محادثات الذكاء الاصطناعي'), findsOneWidget);
    expect(find.text('مستخدم الاختبار'), findsOneWidget);

    await tester.tap(find.text('مستخدم الاختبار'));
    await tester.pumpAndSettle();

    expect(find.text('جلسات المستخدم'), findsOneWidget);
    expect(find.text('البحث عن مطعم'), findsWidgets);

    await tester.tap(find.text('البحث عن مطعم').last);
    await tester.pumpAndSettle();

    expect(find.text('رسائل جلسة المساعد'), findsOneWidget);
    expect(find.text('أريد مطعماً قريباً.'), findsOneWidget);
    expect(find.text('هذه أفضل الخيارات المتاحة.'), findsOneWidget);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('جلسات المستخدم'), findsOneWidget);

    await tester.tap(find.byTooltip('رجوع'));
    await tester.pumpAndSettle();
    expect(find.text('مستخدم الاختبار'), findsOneWidget);
  });
}
