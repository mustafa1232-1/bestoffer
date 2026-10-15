import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/services/emergency/emergency_contacts.dart';

void main() {
  test(
    'Iraq emergency contacts keep verified unified and specialist numbers',
    () {
      final contacts = {
        for (final contact in iraqEmergencyContacts) contact.key: contact.phone,
      };

      expect(contacts['other'], '911');
      expect(contacts['ambulance'], '911');
      expect(contacts['fire'], '911');
      expect(contacts['traffic_accident'], '911');
      expect(contacts['police'], '104');
      expect(contacts['family_protection'], '139');
      expect(contacts['community_police'], '497');
      expect(contacts['drugs'], '278');
      expect(contacts['national_security'], '131');
      expect(contacts['intelligence'], '400');
      expect(contacts['road_hazard'], '455');
    },
  );
}
