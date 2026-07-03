import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/notifications/local_notification_service.dart';
import 'package:maslaki/core/notifications/notification_navigation.dart';
import 'package:maslaki/core/notifications/push_notification_service.dart';
import 'package:maslaki/core/platform/app_flavor.dart';

String _jwt(Map<String, dynamic> claims) {
  String part(Map<String, dynamic> value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${part(const {'alg': 'none', 'typ': 'JWT'})}.${part(claims)}.signature';
}

void main() {
  test('push sync context accepts matching user, session, and flavor', () {
    final context = resolvePushTokenSessionContext(
      accessToken: _jwt(const {
        'sub': '42',
        'sid': 77,
        'appSurface': 'delivery',
      }),
      expectedUserId: 42,
      flavor: AppFlavor.delivery,
    );

    expect(context?.userId, 42);
    expect(context?.sessionId, 77);
    expect(context?.appSurface, 'delivery');
  });

  test('push sync context rejects user and flavor mismatches', () {
    final token = _jwt(const {
      'sub': '42',
      'sid': 77,
      'appSurface': 'delivery',
    });
    expect(
      resolvePushTokenSessionContext(
        accessToken: token,
        expectedUserId: 41,
        flavor: AppFlavor.delivery,
      ),
      isNull,
    );
    expect(
      resolvePushTokenSessionContext(
        accessToken: token,
        expectedUserId: 42,
        flavor: AppFlavor.user,
      ),
      isNull,
    );
  });

  test('notification tap surface isolation rejects cross-flavor payloads', () {
    const customerPayload = NotificationTapPayload(appSurface: 'user');
    const taxiPayload = NotificationTapPayload(appSurface: 'taxi');

    expect(
      NotificationNavigation.isPayloadAllowedForFlavor(
        customerPayload,
        AppFlavor.user,
      ),
      isTrue,
    );
    expect(
      NotificationNavigation.isPayloadAllowedForFlavor(
        customerPayload,
        AppFlavor.delivery,
      ),
      isFalse,
    );
    expect(
      NotificationNavigation.isPayloadAllowedForFlavor(
        taxiPayload,
        AppFlavor.taxiCaptain,
      ),
      isTrue,
    );
  });
}
