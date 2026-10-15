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
        notification: _notification(title: 'عنوان مباشر', body: 'نص مباشر'),
      );

      expect(result.title, 'عنوان مباشر');
      expect(result.body, 'نص مباشر');
    });

    test('resolves detailed order update keys', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final result = resolveNotificationText(
        l10n: l10n,
        notification: _notification(
          title: 'Order update',
          body: 'There is a new update on your order.',
          payload: {
            'i18nTitleKey': 'notifications.orders.courier_assigned.title',
            'i18nBodyKey': 'notifications.orders.courier_assigned.body',
            'i18nBodyArgs': {'courierName': 'Ali', 'orderRef': '#42'},
          },
        ),
      );

      expect(result.title, 'Courier assigned');
      expect(result.body, 'Ali was assigned to deliver your order #42.');
    });

    test('resolves detailed store owner update keys', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final result = resolveNotificationText(
        l10n: l10n,
        notification: _notification(
          title: 'New order',
          body: 'Order received',
          payload: {
            'i18nTitleKey': 'notifications.store.new_order.title',
            'i18nBodyKey': 'notifications.store.new_order.body',
            'i18nBodyArgs': {'customerName': 'Mina', 'orderRef': '#91'},
          },
        ),
      );

      expect(result.title, 'New store order');
      expect(
        result.body,
        'Order #91 from Mina arrived. Open it to accept or start preparing.',
      );
    });

    test('resolves detailed taxi and service update keys', () {
      final l10n = lookupAppLocalizations(const Locale('en'));
      final taxi = resolveNotificationText(
        l10n: l10n,
        notification: _notification(
          title: 'Ride update',
          body: 'Your ride status has been updated.',
          payload: {
            'i18nTitleKey': 'notifications.taxi.arrived.title',
            'i18nBodyKey': 'notifications.taxi.arrived.body',
            'i18nBodyArgs': {'captainName': 'Omar', 'rideRef': '#7'},
          },
        ),
      );
      final service = resolveNotificationText(
        l10n: l10n,
        notification: _notification(
          title: 'Service update',
          body: 'There is a new update on your service request.',
          payload: {
            'i18nTitleKey': 'notifications.services.quote_sent.title',
            'i18nBodyKey': 'notifications.services.quote_sent.body',
            'i18nBodyArgs': {
              'providerName': 'Fix Pro',
              'serviceName': 'AC repair',
              'requestRef': '#19',
            },
          },
        ),
      );

      expect(taxi.title, 'Captain arrived');
      expect(taxi.body, 'Omar arrived at the pickup point for ride #7.');
      expect(service.title, 'Service quote received');
      expect(service.body, 'Fix Pro sent a quote for AC repair #19.');
    });

    test('explains a rejected courier reconciliation', () {
      final l10n = lookupAppLocalizations(const Locale('ar'));
      final result = resolveNotificationText(
        l10n: l10n,
        notification: _notification(
          title: 'fallback',
          body: 'fallback',
          payload: {
            'i18nTitleKey':
                'notifications.delivery.reconciliation_rejected.title',
            'i18nBodyKey':
                'notifications.delivery.reconciliation_rejected.body',
            'i18nBodyArgs': {
              'orderRef': '#148',
              'reviewNote': 'الصورة غير واضحة',
            },
          },
        ),
      );
      expect(result.title, 'تسوية الطلب تحتاج تصحيحاً');
      expect(result.body, contains('#148'));
      expect(result.body, contains('الصورة غير واضحة'));
    });
  });
}
