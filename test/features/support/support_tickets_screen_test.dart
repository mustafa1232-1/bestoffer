import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/support/data/customer_support_api.dart';
import 'package:maslaki/features/support/ui/support_tickets_screen.dart';

void main() {
  testWidgets('support requests list opens details and sends a reply', (
    tester,
  ) async {
    final api = _FakeCustomerSupportApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [customerSupportApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: SupportTicketsScreen()),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('طلب سابق'), findsOneWidget);

    await tester.tap(find.text('طلب سابق'));
    await tester.pumpAndSettle();
    expect(find.text('الرسالة الأولى'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'متابعة الطلب');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();

    expect(api.lastSentBody, 'متابعة الطلب');
    expect(find.text('متابعة الطلب'), findsOneWidget);
  });
}

class _FakeCustomerSupportApi extends CustomerSupportApi {
  _FakeCustomerSupportApi() : super(Dio());

  String? lastSentBody;
  final List<Map<String, dynamic>> _messages = [
    {
      'id': 11,
      'author_role': 'agent',
      'body': 'الرسالة الأولى',
      'created_at': '2026-09-07T08:00:00.000Z',
      'attachments_json': [],
    },
  ];

  @override
  Future<List<Map<String, dynamic>>> myTickets({
    String? status,
    int limit = 25,
    int offset = 0,
  }) async {
    return [
      {
        'id': 1,
        'ticket_number': 'TKT-000001',
        'subject': 'طلب سابق',
        'description': 'متابعة دعم',
        'domain': 'SHOPPING',
        'type': 'PROBLEM',
        'priority': 'normal',
        'status': 'IN_PROGRESS',
        'created_at': '2026-09-07T07:55:00.000Z',
        'updated_at': '2026-09-07T08:00:00.000Z',
      },
    ];
  }

  @override
  Future<Map<String, dynamic>> ticketDetails(int ticketId) async {
    return {
      'ticket': (await myTickets()).first,
      'messages': List<Map<String, dynamic>>.from(_messages),
      'links': [
        {'entity_type': 'order', 'entity_id': 25, 'label': 'طلب #25'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> addMessage(
    int ticketId, {
    required String body,
    List<Map<String, dynamic>> attachments = const [],
  }) async {
    lastSentBody = body;
    final message = {
      'id': 12,
      'author_role': 'customer',
      'body': body,
      'created_at': '2026-09-07T08:05:00.000Z',
      'attachments_json': attachments,
    };
    _messages.add(message);
    return message;
  }
}
