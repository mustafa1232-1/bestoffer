import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/company/models/company_models.dart';

void main() {
  test('CompanyPortalLoginResult parses access token aliases and refresh token', () {
    final result = CompanyPortalLoginResult.fromJson({
      'accessToken': 'access-token-1',
      'refresh_token': 'refresh-token-1',
      'session_id': 42,
      'user': {
        'id': 7,
        'fullName': 'Company User',
        'phone': '07700000000',
        'role': 'company_portal',
      },
      'memberships': const [],
    });

    expect(result.token, 'access-token-1');
    expect(result.refreshToken, 'refresh-token-1');
    expect(result.sessionId, 42);
    expect(result.user.id, 7);
    expect(result.user.fullName, 'Company User');
    expect(result.user.phone, '07700000000');
    expect(result.user.role, 'company_portal');
  });
}
