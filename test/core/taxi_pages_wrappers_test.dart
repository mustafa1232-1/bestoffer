import 'package:maslaki/features/taxi/ui/taxi_captain_dashboard_screen.dart';
import 'package:maslaki/features/taxi/ui/taxi_captain_competitions_screen.dart';
import 'package:maslaki/features/taxi/ui/taxi_captain_notifications_screen.dart';
import 'package:maslaki/features/taxi/ui/taxi_pages.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<BuildContext> _buildContext(WidgetTester tester) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const SizedBox.shrink();
        },
      ),
    ),
  );
  return capturedContext;
}

void main() {
  group('Taxi pages wrappers', () {
    testWidgets('TaxiCaptainDashboardPage uses defaultHome intent', (
      tester,
    ) async {
      final context = await _buildContext(tester);
      final built = const TaxiCaptainDashboardPage().build(context);
      expect(built, isA<TaxiCaptainDashboardScreen>());
      final screen = built as TaxiCaptainDashboardScreen;
      expect(screen.initialIntent, TaxiCaptainDashboardIntent.defaultHome);
    });

    testWidgets('Trips wrappers map to expected intents', (tester) async {
      final context = await _buildContext(tester);

      final newTrips = const TaxiTripsNewPage().build(context);
      final currentTrips = const TaxiTripsCurrentPage().build(context);
      final completedTrips = const TaxiTripsCompletedPage().build(context);
      final cancelledTrips = const TaxiTripsCancelledPage().build(context);
      final earnings = const TaxiEarningsPage().build(context);
      final reports = const TaxiReportsPage().build(context);
      final profile = const TaxiCaptainProfilePage().build(context);
      final competitions = const TaxiCaptainCompetitionsPage().build(context);
      final notifications = const TaxiCaptainNotificationsPage().build(context);

      expect(
        (newTrips as TaxiCaptainDashboardScreen).initialIntent,
        TaxiCaptainDashboardIntent.newTrips,
      );
      expect(
        (currentTrips as TaxiCaptainDashboardScreen).initialIntent,
        TaxiCaptainDashboardIntent.currentTrips,
      );
      expect(
        (completedTrips as TaxiCaptainDashboardScreen).initialIntent,
        TaxiCaptainDashboardIntent.completedTrips,
      );
      expect(
        (cancelledTrips as TaxiCaptainDashboardScreen).initialIntent,
        TaxiCaptainDashboardIntent.cancelledTrips,
      );
      expect(
        (earnings as TaxiCaptainDashboardScreen).initialIntent,
        TaxiCaptainDashboardIntent.earnings,
      );
      expect(
        (reports as TaxiCaptainDashboardScreen).initialIntent,
        TaxiCaptainDashboardIntent.reports,
      );
      expect(
        (profile as TaxiCaptainDashboardScreen).initialIntent,
        TaxiCaptainDashboardIntent.profile,
      );
      expect(competitions, isA<TaxiCaptainCompetitionsScreen>());
      expect(notifications, isA<TaxiCaptainNotificationsScreen>());
    });

    testWidgets('TaxiTripDetailsPage forwards rideId and tripDetails intent', (
      tester,
    ) async {
      final context = await _buildContext(tester);
      final built = const TaxiTripDetailsPage(rideId: 44).build(context);
      expect(built, isA<TaxiCaptainDashboardScreen>());
      final screen = built as TaxiCaptainDashboardScreen;
      expect(screen.initialIntent, TaxiCaptainDashboardIntent.tripDetails);
      expect(screen.initialRideId, 44);
    });
  });
}
