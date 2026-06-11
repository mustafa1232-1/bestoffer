import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import 'customer_cars_marketplace_screen.dart';

class CustomerCarsHubScreen extends ConsumerWidget {
  const CustomerCarsHubScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final carsSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.cars, displayName: 'السيارات');
    if (carsSection.isBlocked) {
      return SectionUnavailableScreen(entry: carsSection);
    }
    return const CustomerCarsMarketplaceScreen();
  }
}
