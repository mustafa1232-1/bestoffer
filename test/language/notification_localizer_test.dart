import 'package:maslaki/core/i18n/notification_localizer.dart';
import 'package:maslaki/features/notifications/models/app_notification_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

AppNotificationModel _notification({
  required String title,
  String? body,
  Map<String, dynamic>? payload,
}) {
  return AppNotificationModel(
    id: 1,
    orderId: null,
    rideId: null,
    storyId: null,
    reelId: null,
    merchantId: null,
    target: null,
    type: 'social.chat.message',
    title: title,
    body: body,
    payload: payload,
    isRead: false,
    createdAt: null,
    readAt: null,
  );
}

void main() {
  group('notification localizer', () {
    test('uses i18n payload keys when present', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final result = resolveNotificationText(
        l10n: l10n,
        notification: _notification(
          title: 'fallback title',
          body: 'fallback body',
          payload: {
            'i18nTitleKey': 'notifications.chat.message.title',
            'i18nBodyKey': 'notifications.chat.message.body',
            'i18nBodyArgs': {'senderName': 'Sara'},
          },
        ),
      );

      expect(result.title, 'New message');
      expect(result.body, 'Sara sent you a message.');
    });

    test('falls back to raw title and body when no i18n keys exist', () {
      final l10n = lookupAppLocalizations(const Locale('ar'));
      final result = resolveNotificationText(
        l10n: l10n,
        notification: _notification(
          title: 'عنوان مباشر',
          body: 'نص مباشر',
        ),
      );

      expect(result.title, 'عنوان مباشر');
      expect(result.body, 'نص مباشر');
    });
  });
}
