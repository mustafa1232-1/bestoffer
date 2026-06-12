import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/auth/app_permission_matrix.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';

UserModel _user({required String role, bool isSuperAdmin = false}) {
  return UserModel(
    id: 1,
    fullName: 'Test',
    phone: '07700000000',
    role: role,
    block: 'A',
    buildingNumber: 'A101',
    apartment: '101',
    imageUrl: null,
    workTitle: null,
    workCompany: null,
    preferredLocale: 'ar',
    isSuperAdmin: isSuperAdmin,
  );
}

void main() {
  group('AppPermissionMatrix', () {
    test('customer capabilities for normal user', () {
      final auth = AuthState(
        token: 'token',
        user: _user(role: 'user'),
      );
      final matrix = AppPermissionMatrix.fromAuth(auth);

      expect(matrix.can(AppCapability.customerHome), isTrue);
      expect(matrix.can(AppCapability.customerFavorites), isTrue);
      expect(matrix.can(AppCapability.customerActivity), isTrue);
      expect(matrix.can(AppCapability.ownerDashboard), isFalse);
      expect(matrix.can(AppCapability.adminDashboard), isFalse);
    });

    test('owner and delivery isolated capabilities', () {
      final owner = AppPermissionMatrix.fromAuth(
        AuthState(
          token: 'token',
          user: _user(role: 'owner'),
        ),
      );
      final delivery = AppPermissionMatrix.fromAuth(
        AuthState(
          token: 'token',
          user: _user(role: 'delivery'),
        ),
      );

      expect(owner.can(AppCapability.ownerDashboard), isTrue);
      expect(owner.can(AppCapability.customerHome), isFalse);
      expect(delivery.can(AppCapability.deliveryDashboard), isTrue);
      expect(delivery.can(AppCapability.customerHome), isFalse);
    });

    test('admin and super admin boundaries', () {
      final admin = AppPermissionMatrix.fromAuth(
        AuthState(
          token: 'token',
          user: _user(role: 'admin'),
        ),
      );
      final superAdmin = AppPermissionMatrix.fromAuth(
        AuthState(
          token: 'token',
          user: _user(role: 'admin', isSuperAdmin: true),
        ),
      );
      final deputy = AppPermissionMatrix.fromAuth(
        AuthState(
          token: 'token',
          user: _user(role: 'deputy_admin'),
        ),
      );

      expect(admin.can(AppCapability.adminDashboard), isTrue);
      expect(admin.can(AppCapability.adminCustomerInsights), isFalse);
      expect(admin.can(AppCapability.adminCompanies), isTrue);
      expect(admin.can(AppCapability.adminApproveCriticalActions), isTrue);
      expect(deputy.can(AppCapability.adminDashboard), isTrue);
      expect(deputy.can(AppCapability.adminCompanies), isFalse);

      for (final capability in AppCapability.values) {
        expect(
          superAdmin.can(capability),
          isTrue,
          reason: 'super admin should access $capability',
        );
      }
    });
  });
}
