import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/ui/taxi_customer_tools_screen.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _FakeTaxiApi extends TaxiApi {
  _FakeTaxiApi() : super(Dio());

  @override
  Future<List<Map<String, dynamic>>> listSavedPlaces() async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 1,
        'label': 'Home',
        'addressText': 'Bismayah A1',
        'latitude': 33.31,
        'longitude': 44.37,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> listFavoriteTrips() async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 4,
        'label': 'Home to Work',
        'pickupSnapshot': <String, dynamic>{'label': 'Home'},
        'dropoffSnapshot': <String, dynamic>{'label': 'Office'},
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> listScheduledRides({
    String status = 'scheduled',
    int limit = 40,
  }) async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 8,
        'status': 'scheduled',
        'scheduleFor': '2026-04-02 09:00',
        'pickupSnapshot': <String, dynamic>{'label': 'Home'},
        'dropoffSnapshot': <String, dynamic>{'label': 'Mall'},
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> listMyCoupons() async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 2,
        'title': 'Taxi 50%',
        'code': 'TAXI50',
        'remainingUses': 2,
      },
    ];
  }

  @override
  Future<List<Map<String, dynamic>>> listMyRideHistory({
    String period = 'month',
    int limit = 20,
  }) async {
    return <Map<String, dynamic>>[
      <String, dynamic>{
        'id': 12,
        'status': 'completed',
        'pickup': <String, dynamic>{'label': 'Home'},
        'dropoff': <String, dynamic>{'label': 'Office'},
        'proposedFareIqd': 12000,
        'completedAt': '2026-04-01 10:30',
      },
    ];
  }
}

Future<void> _pumpTools(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        taxiCustomerToolsApiProvider.overrideWithValue(_FakeTaxiApi()),
      ],
      child: const MaterialApp(
        locale: Locale('en'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        home: TaxiCustomerToolsScreen(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('taxi tools render saved/favorite/scheduled/coupon surfaces', (
    tester,
  ) async {
    await _pumpTools(tester);

    expect(find.text('Taxi Tools'), findsOneWidget);
    expect(find.text('Saved Places'), findsOneWidget);
    expect(find.text('Favorite Trips'), findsOneWidget);
    expect(find.text('Scheduled Rides'), findsOneWidget);
    expect(find.text('My Taxi Coupons'), findsOneWidget);

    expect(find.text('Home'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('Favorite Trips'));
    await tester.pumpAndSettle();
    expect(find.text('Home to Work'), findsOneWidget);
    expect(find.text('Use now'), findsOneWidget);

    await tester.tap(find.text('Scheduled Rides'));
    await tester.pumpAndSettle();
    expect(find.textContaining('2026-04-02 09:00'), findsOneWidget);
    expect(find.text('Cancel'), findsOneWidget);

    await tester.ensureVisible(find.text('My Taxi Coupons'));
    await tester.tap(find.text('My Taxi Coupons'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.text('Coupon code'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Taxi 50%'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Taxi 50%'), findsOneWidget);
  });
}
