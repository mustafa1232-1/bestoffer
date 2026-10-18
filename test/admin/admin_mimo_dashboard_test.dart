import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/admin/data/admin_api.dart';
import 'package:maslaki/features/admin/state/admin_controller.dart';
import 'package:maslaki/features/admin/ui/admin_mimo_dashboard_screen.dart';

class _Api extends AdminApi {
  _Api() : super(Dio());

  final updates = <String>[];
  final deleted = <int>[];
  List<Map<String, dynamic>> knowledge = [
    {
      'id': 3,
      'question': 'شنو أكلة بسمايا المشهورة؟',
      'answer': 'الكص بالصمون',
      'status': 'community',
      'confirmations': 1,
      'uses': 4,
      'playbook': false,
    },
  ];

  @override
  Future<Map<String, dynamic>> mimoDashboard({int days = 30}) async => {
    'days': days,
    'kpis': {
      'questions': 1200,
      'users': 140,
      'satisfaction': 91,
      'avgReplySeconds': 3.2,
      'estimatedCostUsd': 4.75,
      'costPerQuestionUsd': 0.004,
      'cartAdds': 77,
      'escalations': 6,
      'escalationsOpen': 2,
      'learnedVerified': 12,
      'learnedCommunity': 3,
      'playbooks': 4,
      'nudgesShown': 80,
      'nudgesTapped': 12,
      'feedbackDown': 9,
    },
    'daily': [
      {'day': '2026-10-17', 'questions': 40, 'cost_usd': 0.2},
      {'day': '2026-10-18', 'questions': 55, 'cost_usd': 0.3},
    ],
    'tools': [
      {'tool': 'search_products', 'n': 70},
    ],
    'badAnswers': [
      {'question': 'وين طلبي', 'answer': 'ما أعرف', 'reason': 'مو مفيد'},
    ],
    'demand': {
      'unmet': [
        {'text': 'شاورما عربي', 'times': 14},
      ],
      'misses': [],
      'synonyms': [],
    },
    'tickets': [
      {
        'id': 9,
        'ticket_number': 'SUP-9',
        'subject': 'الطلب وصل تالف',
        'status': 'OPEN',
        'priority': 'urgent',
      },
    ],
    'costNote': 'تقدير تقريبي',
  };

  @override
  Future<List<Map<String, dynamic>>> mimoKnowledge({
    String? status,
    String? query,
    int offset = 0,
  }) async => knowledge;

  @override
  Future<void> updateMimoKnowledge(
    int id, {
    String? status,
    String? answer,
  }) async {
    updates.add('$id:${status ?? answer}');
    knowledge = [
      {...knowledge.single, 'status': status ?? knowledge.single['status']},
    ];
  }

  @override
  Future<void> deleteMimoKnowledge(int id) async => deleted.add(id);
}

void main() {
  testWidgets('admin sees Mimo KPIs, demand, and manages what he learned', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1000, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = _Api();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [adminApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: AdminMimoDashboardScreen(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('1,200'), findsOneWidget);
    expect(find.text('91%'), findsOneWidget);
    expect(find.text('\$4.75'), findsOneWidget);
    expect(find.text('البحث بالمنتجات'), findsOneWidget);

    await tester.tap(find.text('يطلبون وماكو'));
    await tester.pumpAndSettle();
    expect(find.text('شاورما عربي'), findsOneWidget);
    expect(find.text('14 مرة'), findsOneWidget);

    await tester.tap(find.text('شنو تعلم'));
    await tester.pumpAndSettle();
    expect(find.text('الكص بالصمون'), findsOneWidget);
    await tester.tap(find.text('اعتمد'));
    await tester.pumpAndSettle();
    expect(api.updates, ['3:verified']);
    expect(find.text('مؤكدة'), findsWidgets);

    await tester.tap(find.byTooltip('حذف'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('احذف'));
    await tester.pumpAndSettle();
    expect(api.deleted, [3]);

    await tester.tap(find.text('تذاكر ميمو'));
    await tester.pumpAndSettle();
    expect(find.text('الطلب وصل تالف'), findsOneWidget);
    expect(find.byIcon(Icons.notification_important_rounded), findsOneWidget);
  });
}
