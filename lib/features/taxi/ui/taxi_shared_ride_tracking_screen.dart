import 'package:flutter/material.dart';

import '../../tracking/ui/taxi_live_tracking_screen.dart';

class TaxiSharedRideTrackingScreen extends StatelessWidget {
  final int rideId;

  const TaxiSharedRideTrackingScreen({super.key, required this.rideId});

  @override
  Widget build(BuildContext context) {
    return TaxiLiveTrackingScreen(
      rideId: rideId,
      sharedReadonly: true,
    );
  }
}
