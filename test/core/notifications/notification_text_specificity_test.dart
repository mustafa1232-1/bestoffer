import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/i18n/notification_localizer.dart';
import 'package:maslaki/features/notifications/models/app_notification_model.dart';
import 'package:maslaki/l10n/app_localizations.dart';
import 'package:flutter/material.dart';

AppNotificationModel _row({
  required String type,
  required String title,
  String? body,
  Map<String, dynamic>? payload,
}) {
  return AppNotificationModel.fromJson({
    'id': 1,
    'type': type,
    'title': title,
    'body': body,
    'payload': payload ?? <String, dynamic>{},
    'is_read': false,
  });
}

void main() {
  final ar = lookupAppLocalizations(const Locale('ar'));
  final en = lookupAppLocalizations(const Locale('en'));

  test('a generic category key never hides the specific stored text', () {
    final text = resolveNotificationText(
      l10n: ar,
      notification: _row(
        type: 'admin_support_ticket_created',
        title: 'تذكرة دعم جديدة ST-9: التطبيق لا يفتح',
        body: 'افتح التذكرة ST-9 للرد على صاحبها.',
        payload: {
          'i18nTitleKey': 'notifications.admin.title',
          'i18nBodyKey': 'notifications.admin.body',
        },
      ),
    );
    expect(text.title, 'تذكرة دعم جديدة ST-9: التطبيق لا يفتح');
    expect(text.body, 'افتح التذكرة ST-9 للرد على صاحبها.');
    expect(isGenericNotificationKey('notifications.admin.title'), isTrue);
    expect(
      isGenericNotificationKey('notifications.orders.ready.title'),
      isFalse,
    );
  });

  test('English devices show the event English copy', () {
    final text = resolveNotificationText(
      l10n: en,
      notification: _row(
        type: 'support.ticket.agent_reply',
        title: 'رد فريق الدعم على تذكرتك ST-9',
        body: 'تم حل المشكلة',
        payload: {
          'textEn': {
            'title': 'Support replied to your ticket ST-9',
            'body': 'The issue is fixed',
          },
        },
      ),
    );
    expect(text.title, 'Support replied to your ticket ST-9');
    expect(text.body, 'The issue is fixed');
  });

  test('chat title names the sender when no stored title exists', () {
    final text = resolveNotificationText(
      l10n: ar,
      notification: _row(
        type: 'social.chat.message',
        title: '',
        payload: {
          'i18nTitleKey': 'notifications.chat.message.title',
          'i18nTitleArgs': {'senderName': 'علي'},
        },
      ),
    );
    expect(text.title, 'رسالة جديدة من علي');
  });

  test('specific event templates still localise', () {
    final text = resolveNotificationText(
      l10n: en,
      notification: _row(
        type: 'customer_order_status',
        title: 'طلبك قيد التحضير',
        payload: {
          'i18nTitleKey': 'notifications.orders.preparing.title',
          'i18nBodyKey': 'notifications.orders.preparing.body',
          'i18nBodyArgs': {'storeName': 'Abu Ali Grill', 'orderRef': '#123'},
        },
      ),
    );
    expect(text.title, 'Your order is being prepared');
    expect(text.body, contains('#123'));
  });
}
