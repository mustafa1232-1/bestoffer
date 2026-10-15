import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/assistant/data/assistant_api.dart';
import 'package:maslaki/features/assistant/ui/assistant_chat_screen.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeAssistantApi extends AssistantApi {
  _FakeAssistantApi() : super(Dio());

  String? lastCommerceQuery;
  String? lastCommerceKind;
  String? lastCommercePriority;
  double? lastCommerceMaxPrice;

  @override
  Future<Map<String, dynamic>> getCurrentSession() async {
    return <String, dynamic>{
      'sessionId': 1,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{'role': 'assistant', 'text': 'Assistant response'},
      ],
    };
  }

  @override
  Future<Map<String, dynamic>> getAiUserProfile() async {
    return <String, dynamic>{
      'profile': <String, dynamic>{
        'displayName': 'Test user',
        'city': 'Baghdad',
        'consentFlags': <String, dynamic>{'memoryEnabled': true},
      },
    };
  }

  @override
  Future<List<Map<String, dynamic>>> listAiTopics() async {
    return const <Map<String, dynamic>>[];
  }

  @override
  Future<Map<String, dynamic>> recommendCommerce({
    required String query,
    String kind = 'shopping',
    String priority = 'balanced',
    double? maxPrice,
    int limit = 12,
  }) async {
    lastCommerceQuery = query;
    lastCommerceKind = kind;
    lastCommercePriority = priority;
    lastCommerceMaxPrice = maxPrice;
    return <String, dynamic>{
      'summary': 'وجدنا خياراً مناسباً',
      'items': <Map<String, dynamic>>[
        <String, dynamic>{
          'productId': 11,
          'productName': 'سماعة ذكية',
          'merchantId': 22,
          'merchantName': 'متجر الاختبار',
          'merchantType': 'market',
          'effectivePrice': 18000,
          'basePrice': 20000,
          'avgRating': 4.8,
          'ratingCount': 120,
          'avgDeliveryMinutes': 25,
          'recommendationKey': 'best_match',
          'recommendationTags': <String>['best_match', 'best_price'],
          'reason': 'أفضل توازن متاح.',
        },
      ],
    };
  }
}

class _FakeAuthController extends AuthController {
  _FakeAuthController(super.ref) {
    state = AuthState(
      token: 'test-token',
      user: UserModel(
        id: 6,
        fullName: 'Test user',
        phone: '07700000000',
        role: 'user',
        block: 'A1',
        buildingNumber: '10',
        apartment: '2',
        imageUrl: null,
        workTitle: null,
        workCompany: null,
        preferredLocale: 'ar',
        isSuperAdmin: false,
      ),
    );
  }
}

Future<void> _pumpAssistant(WidgetTester tester, _FakeAssistantApi api) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        assistantApiProvider.overrideWithValue(api),
        authControllerProvider.overrideWith(_FakeAuthController.new),
      ],
      child: MaterialApp(
        theme: AppTheme.themed(MaslakiTheme.original),
        locale: const Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: const AssistantChatScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('starts with task choices without an unbounded viewport', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await _pumpAssistant(tester, _FakeAssistantApi());

    expect(tester.takeException(), isNull);
    expect(find.text('ما الذي تريد إنجازه؟'), findsOneWidget);
    expect(find.text('تسوق بذكاء'), findsOneWidget);
    expect(find.text('احجز تكسي'), findsOneWidget);
  });

  testWidgets('free chat remains available as a secondary mode', (
    tester,
  ) async {
    await _pumpAssistant(tester, _FakeAssistantApi());

    await tester.tap(find.text('اسأل بحرية'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Assistant response'), findsOneWidget);
  });

  testWidgets('guided shopping returns actionable ranked cards', (
    tester,
  ) async {
    final api = _FakeAssistantApi();
    await _pumpAssistant(tester, api);

    await tester.tap(find.text('تسوق بذكاء'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'سماعة لاسلكية');
    await tester.ensureVisible(find.text('اعرض أفضل الخيارات'));
    await tester.tap(find.text('اعرض أفضل الخيارات'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(api.lastCommerceQuery, 'سماعة لاسلكية');
    expect(api.lastCommerceKind, 'shopping');
    expect(api.lastCommercePriority, 'balanced');
    expect(find.text('سماعة ذكية'), findsOneWidget);
    expect(find.text('الأفضل والأوفر'), findsOneWidget);
    expect(find.text('عرض المنتج في المتجر'), findsOneWidget);
  });
}
