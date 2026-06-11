import 'package:flutter/material.dart';

import '../../../features/notifications/ui/notifications_screen.dart';
import '../../../features/settings/ui/settings_screen.dart';
import 'owner_dashboard_screen.dart';
import 'store_owner_couriers_screen.dart';
import 'store_owner_kpis_screen.dart';
import 'store_owner_offers_screen.dart';
import 'store_owner_orders_screen.dart';
import 'store_owner_receivables_screen.dart';

class MerchantDashboardPage extends StatelessWidget {
  const MerchantDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const OwnerDashboardScreen(initialTab: OwnerDashboardTab.dashboard);
  }
}

class MerchantOrdersCurrentPage extends StatelessWidget {
  const MerchantOrdersCurrentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerOrdersScreen(view: StoreOwnerOrdersView.current);
  }
}

class MerchantOrdersCompletedPage extends StatelessWidget {
  const MerchantOrdersCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerOrdersScreen(view: StoreOwnerOrdersView.completed);
  }
}

class MerchantOrdersCancelledPage extends StatelessWidget {
  const MerchantOrdersCancelledPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerOrdersScreen(view: StoreOwnerOrdersView.cancelled);
  }
}

class MerchantOrderDetailsPage extends StatelessWidget {
  const MerchantOrderDetailsPage({super.key, this.orderId});

  final int? orderId;

  @override
  Widget build(BuildContext context) {
    return StoreOwnerOrdersScreen(
      view: StoreOwnerOrdersView.details,
      initialOrderId: orderId,
    );
  }
}

class MerchantReceivablesPage extends StatelessWidget {
  const MerchantReceivablesPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerReceivablesScreen();
  }
}

class MerchantPaymentRequestsPage extends StatelessWidget {
  const MerchantPaymentRequestsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerReceivablesScreen();
  }
}

class MerchantCouriersPage extends StatelessWidget {
  const MerchantCouriersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerCouriersScreen();
  }
}

class MerchantOffersPage extends StatelessWidget {
  const MerchantOffersPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerOffersScreen();
  }
}

class MerchantReportsPage extends StatelessWidget {
  const MerchantReportsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const StoreOwnerKpisScreen();
  }
}

class MerchantNotificationsPage extends StatelessWidget {
  const MerchantNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const NotificationsScreen();
  }
}

class MerchantSettingsPage extends StatelessWidget {
  const MerchantSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const SettingsScreen();
  }
}
