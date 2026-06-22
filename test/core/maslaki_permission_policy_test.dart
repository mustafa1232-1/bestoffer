import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/permissions/maslaki_permission_models.dart';
import 'package:maslaki/core/permissions/maslaki_permission_policy.dart';
import 'package:maslaki/core/permissions/maslaki_permission_service.dart';

void main() {
  group('MaslakiPermissionService.ensure* (graceful, no-crash)', () {
    // permission_handler has no platform impl in the test VM; the ensure
    // helpers must degrade to false instead of throwing into the UI.
    TestWidgetsFlutterBinding.ensureInitialized();
    const service = MaslakiPermissionService();

    test('ensureCameraPermission returns false without throwing', () async {
      expect(await service.ensureCameraPermission(), isFalse);
    });
    test('ensureLocationPermission returns false without throwing', () async {
      expect(await service.ensureLocationPermission(), isFalse);
    });
    test('ensureMediaImagesPermission returns false without throwing', () async {
      expect(await service.ensureMediaImagesPermission(), isFalse);
    });
    test('ensureNotificationPermission returns false without throwing', () async {
      expect(await service.ensureNotificationPermission(), isFalse);
    });
  });

  group('MaslakiPermissionPolicy', () {
    test('customer: notifications + foreground location required, no background', () {
      const role = MaslakiAppRole.customer;
      final required = MaslakiPermissionPolicy.requiredPermissions(role);
      expect(required, contains(MaslakiPermission.notifications));
      expect(required, contains(MaslakiPermission.locationWhenInUse));
      expect(required, isNot(contains(MaslakiPermission.locationAlways)));
      expect(MaslakiPermissionPolicy.requiresBackgroundLocation(role), isFalse);
      // camera/mic/photos must be on-demand (never spammed at startup).
      final firstRun = MaslakiPermissionPolicy.firstRunRequirements(role)
          .map((r) => r.permission);
      expect(firstRun, isNot(contains(MaslakiPermission.camera)));
      expect(firstRun, isNot(contains(MaslakiPermission.microphone)));
      expect(firstRun, isNot(contains(MaslakiPermission.photos)));
    });

    test('taxi captain requires background location', () {
      const role = MaslakiAppRole.taxiCaptain;
      expect(MaslakiPermissionPolicy.requiresBackgroundLocation(role), isTrue);
      expect(
        MaslakiPermissionPolicy.requiredPermissions(role),
        containsAll(<MaslakiPermission>[
          MaslakiPermission.notifications,
          MaslakiPermission.locationWhenInUse,
          MaslakiPermission.locationAlways,
        ]),
      );
    });

    test('delivery requires background location', () {
      const role = MaslakiAppRole.delivery;
      expect(MaslakiPermissionPolicy.requiresBackgroundLocation(role), isTrue);
      expect(
        MaslakiPermissionPolicy.isRequiredForRole(
            role, MaslakiPermission.locationAlways),
        isTrue,
      );
    });

    test('merchant: notifications required, camera optional, no location', () {
      const role = MaslakiAppRole.merchant;
      expect(MaslakiPermissionPolicy.requiredPermissions(role),
          <MaslakiPermission>[MaslakiPermission.notifications]);
      expect(MaslakiPermissionPolicy.requiresBackgroundLocation(role), isFalse);
      final optional = MaslakiPermissionPolicy.requirementsForRole(role)
          .where((r) => r.isOptional)
          .map((r) => r.permission);
      expect(optional, contains(MaslakiPermission.camera));
      // Photos uses the permissionless Photo Picker → on-demand, not first-run.
      final firstRun = MaslakiPermissionPolicy.firstRunRequirements(role)
          .map((r) => r.permission);
      expect(firstRun, isNot(contains(MaslakiPermission.photos)));
    });

    test('admin: only notifications required, no location at all', () {
      const role = MaslakiAppRole.admin;
      expect(MaslakiPermissionPolicy.requiredPermissions(role),
          <MaslakiPermission>[MaslakiPermission.notifications]);
      expect(MaslakiPermissionPolicy.requiresBackgroundLocation(role), isFalse);
      final all = MaslakiPermissionPolicy.requirementsForRole(role)
          .map((r) => r.permission);
      expect(all, isNot(contains(MaslakiPermission.locationWhenInUse)));
      expect(all, isNot(contains(MaslakiPermission.locationAlways)));
    });

    test('only delivery and taxi captain get background location', () {
      for (final role in MaslakiAppRole.values) {
        final expected =
            role == MaslakiAppRole.delivery || role == MaslakiAppRole.taxiCaptain;
        expect(
          MaslakiPermissionPolicy.requiresBackgroundLocation(role),
          expected,
          reason: '$role background-location gating',
        );
      }
    });

    test('every role requires notifications', () {
      for (final role in MaslakiAppRole.values) {
        expect(
          MaslakiPermissionPolicy.isRequiredForRole(
              role, MaslakiPermission.notifications),
          isTrue,
          reason: '$role notifications',
        );
      }
    });

    test('firstRunRequirements never include on-demand permissions', () {
      for (final role in MaslakiAppRole.values) {
        for (final req in MaslakiPermissionPolicy.firstRunRequirements(role)) {
          expect(req.isOnDemand, isFalse);
        }
      }
    });
  });
}
