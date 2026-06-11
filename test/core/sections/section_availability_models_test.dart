import 'package:maslaki/core/sections/section_availability_models.dart';
import 'package:maslaki/core/sections/section_availability_targets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SectionAvailabilityEntry', () {
    test('maps API status and badge labels correctly', () {
      final entry = SectionAvailabilityEntry.fromJson(const <String, dynamic>{
        'id': 1,
        'sectionKey': 'services',
        'displayName': 'الخدمات',
        'surfaceScope': 'user',
        'status': 'maintenance',
        'isVisible': true,
        'allowExistingActiveAccess': true,
      });

      expect(entry.status, SectionAvailabilityStatus.maintenance);
      expect(entry.isBlocked, isTrue);
      expect(entry.badgeLabel, 'تحت الصيانة');
      expect(entry.effectiveMessage, contains('تحت الصيانة'));
    });

    test('prefers custom effective message when present', () {
      final entry = SectionAvailabilityEntry.fromJson(const <String, dynamic>{
        'id': 2,
        'sectionKey': 'taxi',
        'displayName': 'التكسي',
        'surfaceScope': 'user',
        'status': 'temporarily_closed',
        'isVisible': true,
        'allowExistingActiveAccess': false,
        'effectiveMessage': 'العودة بعد تحديث التسعيرة.',
      });

      expect(entry.effectiveMessage, 'العودة بعد تحديث التسعيرة.');
    });
  });

  group('resolveSectionKeyForNavigationTarget', () {
    test('maps services targets to services section', () {
      expect(
        resolveSectionKeyForNavigationTarget(
          target: 'service_request_details',
          targetModule: 'customer',
        ),
        AppSectionKeys.services,
      );
      expect(
        resolveSectionKeyForNavigationTarget(
          target: 'services_provider_workspace',
          targetModule: 'customer',
        ),
        AppSectionKeys.services,
      );
    });

    test('maps taxi and real estate routes correctly', () {
      expect(
        resolveSectionKeyForNavigationTarget(
          target: 'taxi_live',
          targetModule: 'taxi',
        ),
        AppSectionKeys.taxi,
      );
      expect(
        resolveSectionKeyForNavigationTarget(
          target: 'real_estate_workspace',
          targetModule: 'real_estate',
        ),
        AppSectionKeys.realEstate,
      );
    });
  });
}
