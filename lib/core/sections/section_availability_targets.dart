import 'section_availability_models.dart';

String? resolveSectionKeyForNavigationTarget({
  required String? target,
  String? targetModule,
}) {
  final normalizedTarget = (target ?? '').trim().toLowerCase();
  final normalizedModule = (targetModule ?? '').trim().toLowerCase();

  if (normalizedTarget.isEmpty && normalizedModule.isEmpty) {
    return null;
  }

  if (normalizedTarget == 'pharmacy_conversation' ||
      normalizedTarget.startsWith('pharmacy_') ||
      normalizedModule == AppSectionKeys.pharmacy) {
    return AppSectionKeys.pharmacy;
  }
  if (normalizedTarget == 'services_marketplace' ||
      normalizedTarget == 'services_provider_workspace' ||
      normalizedTarget == 'service_request_details' ||
      normalizedTarget == 'services_provider_requests' ||
      normalizedTarget == 'service_provider_profile' ||
      normalizedTarget == 'service_provider_details' ||
      normalizedTarget == 'service_offering_details' ||
      normalizedTarget == 'service_offering') {
    return AppSectionKeys.services;
  }
  if (normalizedTarget == 'real_estate_marketplace' ||
      normalizedTarget == 'real_estate_workspace' ||
      normalizedModule == AppSectionKeys.realEstate) {
    return AppSectionKeys.realEstate;
  }
  if (normalizedTarget == 'taxi_live' ||
      normalizedTarget == 'taxi_shared_ride' ||
      normalizedTarget.startsWith('taxi_') ||
      normalizedModule == AppSectionKeys.taxi) {
    return AppSectionKeys.taxi;
  }
  if (normalizedTarget == 'social_shell' ||
      normalizedTarget == 'social_community' ||
      normalizedTarget.startsWith('social_') ||
      normalizedModule == AppSectionKeys.community) {
    return AppSectionKeys.community;
  }
  if (normalizedTarget == 'jobs_applications' ||
      normalizedTarget == 'jobs_my_applications' ||
      normalizedTarget.startsWith('jobs_') ||
      normalizedModule == AppSectionKeys.jobs) {
    return AppSectionKeys.jobs;
  }
  if (normalizedTarget.contains('cars') || normalizedModule == AppSectionKeys.cars) {
    return AppSectionKeys.cars;
  }
  if (normalizedTarget == 'shopping' ||
      normalizedTarget == 'market' ||
      normalizedTarget == 'customer_discovery' ||
      normalizedModule == AppSectionKeys.shopping) {
    return AppSectionKeys.shopping;
  }
  return null;
}
