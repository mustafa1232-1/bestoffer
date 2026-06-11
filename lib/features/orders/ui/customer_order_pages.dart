import 'package:flutter/material.dart';

import '../../notifications/ui/notifications_screen.dart';
import 'customer_orders_screen.dart';
import '../../tracking/ui/delivery_live_tracking_screen.dart';

class CustomerOrdersCurrentPage extends StatelessWidget {
  const CustomerOrdersCurrentPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomerOrdersScreen(
      initialStatusFilter: CustomerOrdersFilter.active,
    );
  }
}

class CustomerOrdersCompletedPage extends StatelessWidget {
  const CustomerOrdersCompletedPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomerOrdersScreen(
      initialStatusFilter: CustomerOrdersFilter.delivered,
    );
  }
}

class CustomerOrdersCancelledPage extends StatelessWidget {
  const CustomerOrdersCancelledPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const CustomerOrdersScreen(
      initialStatusFilter: CustomerOrdersFilter.cancelled,
    );
  }
}

class CustomerOrderDetailsPage extends StatelessWidget {
  const CustomerOrderDetailsPage({super.key, required this.orderId});

  final int orderId;

  @override
  Widget build(BuildContext context) {
    return DeliveryLiveTrackingScreen(orderId: orderId);
  }
}

class CustomerNotificationsPage extends StatelessWidget {
  const CustomerNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const NotificationsScreen();
  }
}
