import 'package:flutter/material.dart';

import '../models/order_model.dart';
import '../../tracking/ui/delivery_live_tracking_screen.dart';

class OrderTrackingScreen extends StatelessWidget {
  final OrderModel order;

  const OrderTrackingScreen({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return DeliveryLiveTrackingScreen(orderId: order.id);
  }
}
