import 'package:flutter/material.dart';

import '../../../features/notifications/ui/notifications_screen.dart';
import '../../../features/settings/ui/settings_screen.dart';
import 'taxi_captain_dashboard_screen.dart';

class TaxiCaptainDashboardPage extends StatelessWidget {
  const TaxiCaptainDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.defaultHome,
    );
  }
}

class TaxiTripsNewPage extends StatelessWidget {
  const TaxiTripsNewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.newTrips,
    );
  }
}

class TaxiTripsCurrentPage extends StatelessWidget {
  const TaxiTripsCurrentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.currentTrips,
    );
  }
}

class TaxiTripsCompletedPage extends StatelessWidget {
  const TaxiTripsCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.completedTrips,
    );
  }
}

class TaxiTripsCancelledPage extends StatelessWidget {
  const TaxiTripsCancelledPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.cancelledTrips,
    );
  }
}

class TaxiTripDetailsPage extends StatelessWidget {
  const TaxiTripDetailsPage({super.key, this.rideId});

  final int? rideId;

  @override
  Widget build(BuildContext context) {
    return TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.tripDetails,
      initialRideId: rideId,
    );
  }
}

class TaxiEarningsPage extends StatelessWidget {
  const TaxiEarningsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.earnings,
    );
  }
}

class TaxiReportsPage extends StatelessWidget {
  const TaxiReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.reports,
    );
  }
}

class TaxiCaptainProfilePage extends StatelessWidget {
  const TaxiCaptainProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    return const TaxiCaptainDashboardScreen(
      initialIntent: TaxiCaptainDashboardIntent.profile,
    );
  }
}

class TaxiNotificationsPage extends StatelessWidget {
  const TaxiNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const NotificationsScreen();
  }
}

class TaxiSettingsPage extends StatelessWidget {
  const TaxiSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen();
  }
}
