import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'section_availability_controller.dart';
import 'section_availability_models.dart';
import 'section_availability_registry.dart';
import 'section_unavailable_screen.dart';

SectionAvailabilityEntry resolveSectionAvailability(
  WidgetRef ref,
  String sectionKey, {
  String? displayName,
}) {
  return ref
      .read(sectionAvailabilityControllerProvider)
      .entryFor(sectionKey, displayName: displayName);
}

Future<bool> guardSectionAccess(
  BuildContext context,
  WidgetRef ref, {
  required String sectionKey,
  String? displayName,
}) async {
  var entry = resolveSectionAvailability(
    ref,
    sectionKey,
    displayName: displayName,
  );
  final availability = ref.read(sectionAvailabilityControllerProvider);
  final lastSyncedAt = availability.lastSyncedAt;
  final isStale =
      lastSyncedAt == null ||
      DateTime.now().difference(lastSyncedAt) > const Duration(seconds: 30);

  if (!entry.isOpen || (availability.initialized && isStale)) {
    try {
      await ref
          .read(sectionAvailabilityControllerProvider.notifier)
          .refresh(silent: true)
          .timeout(const Duration(seconds: 5));
    } catch (_) {
      // Keep the last known state when the availability check cannot complete.
    }
    if (!context.mounted) return false;
    entry = resolveSectionAvailability(
      ref,
      sectionKey,
      displayName: displayName,
    );
  }
  if (entry.isOpen) return true;
  await showSectionUnavailableSheet(context, entry);
  return false;
}

SectionAvailabilityEntry resolveSectionAvailabilitySnapshot(
  String sectionKey, {
  String? displayName,
}) {
  return SectionAvailabilityRegistry.getOrDefault(
    sectionKey,
    displayName: displayName,
  );
}
