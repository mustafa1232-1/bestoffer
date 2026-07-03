import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/auth/models/user_model.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/customer/state/customer_smart_experience_provider.dart';

UserModel _userWithRole(String role) =>
    UserModel.fromJson({'id': 1, 'full_name': 'Test', 'role': role});

void main() {
  test('guest mode never triggers taxi saved-places/history calls', () {
    const guest = AuthState(guestMode: true);
    expect(shouldLoadCustomerSmartExperience(guest), isFalse);
  });

  test('missing/empty token never triggers taxi calls', () {
    const anonymous = AuthState();
    expect(shouldLoadCustomerSmartExperience(anonymous), isFalse);
    const emptyToken = AuthState(token: '');
    expect(shouldLoadCustomerSmartExperience(emptyToken), isFalse);
  });

  test('authenticated customer loads the smart experience', () {
    final customer = AuthState(token: 'token', user: _userWithRole('user'));
    expect(shouldLoadCustomerSmartExperience(customer), isTrue);
  });

  test('non-customer roles are excluded even when authenticated', () {
    final owner = AuthState(token: 'token', user: _userWithRole('owner'));
    expect(shouldLoadCustomerSmartExperience(owner), isFalse);
    final delivery = AuthState(token: 'token', user: _userWithRole('delivery'));
    expect(shouldLoadCustomerSmartExperience(delivery), isFalse);
  });
}
