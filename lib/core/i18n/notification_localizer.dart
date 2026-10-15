import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../features/notifications/models/app_notification_model.dart';

AppLocalizations appLocalizationsForLocale(Locale locale) {
  final normalized = locale.languageCode.toLowerCase().startsWith('en')
      ? const Locale('en')
      : const Locale('ar');
  return lookupAppLocalizations(normalized);
}

AppLocalizations appLocalizationsForCurrentLocale() {
  return appLocalizationsForLocale(Locale(Intl.getCurrentLocale()));
}

class LocalizedNotificationText {
  final String title;
  final String? body;

  const LocalizedNotificationText({required this.title, required this.body});
}

LocalizedNotificationText resolveNotificationText({
  required AppLocalizations l10n,
  required AppNotificationModel notification,
}) {
  final payload = notification.payload ?? const <String, dynamic>{};
  final title = _resolveNotificationPiece(
    l10n: l10n,
    key: payload['i18nTitleKey']?.toString(),
    args: _readArgs(payload['i18nTitleArgs']),
    fallback: notification.title.trim().isEmpty
        ? l10n.notificationsGenericTitle
        : notification.title.trim(),
  );
  final body = _resolveNotificationPiece(
    l10n: l10n,
    key: payload['i18nBodyKey']?.toString(),
    args: _readArgs(payload['i18nBodyArgs']),
    fallback: notification.body?.trim(),
  );
  return LocalizedNotificationText(
    title: title ?? l10n.notificationsGenericTitle,
    body: body,
  );
}

Map<String, String> _readArgs(dynamic raw) {
  if (raw is! Map) return const <String, String>{};
  return raw.map(
    (key, value) => MapEntry('$key', value == null ? '' : '$value'),
  );
}

bool _isEnglish(AppLocalizations l10n) =>
    l10n.localeName.toLowerCase().startsWith('en');

String _localizedTemplate(
  AppLocalizations l10n,
  Map<String, String> args, {
  required String ar,
  required String en,
}) {
  final template = _isEnglish(l10n) ? en : ar;
  return template
      .replaceAllMapped(RegExp(r'\{(\w+)\}'), (match) {
        final key = match.group(1) ?? '';
        return args[key]?.trim() ?? '';
      })
      .replaceAllMapped(RegExp(r'\s+([.،,])'), (match) => match.group(1) ?? '')
      .trim();
}

String? _resolveDetailedNotificationPiece({
  required AppLocalizations l10n,
  required String key,
  required Map<String, String> args,
}) {
  final english = _isEnglish(l10n);
  final titles = <String, ({String ar, String en})>{
    'notifications.orders.merchant_accepted.title': (
      ar: 'تم قبول طلبك',
      en: 'Your order was accepted',
    ),
    'notifications.orders.preparing.title': (
      ar: 'طلبك قيد التحضير',
      en: 'Your order is being prepared',
    ),
    'notifications.orders.ready.title': (
      ar: 'طلبك جاهز',
      en: 'Your order is ready',
    ),
    'notifications.orders.courier_assigned.title': (
      ar: 'تم تعيين دلفري لطلبك',
      en: 'Courier assigned',
    ),
    'notifications.orders.courier_reassigned.title': (
      ar: 'تم تغيير الدلفري',
      en: 'Courier changed',
    ),
    'notifications.orders.on_the_way.title': (
      ar: 'طلبك في الطريق',
      en: 'Your order is on the way',
    ),
    'notifications.orders.arrived.title': (
      ar: 'الدلفري وصل',
      en: 'Courier arrived',
    ),
    'notifications.orders.delivered.title': (
      ar: 'تم تسليم طلبك',
      en: 'Order delivered',
    ),
    'notifications.orders.cancelled.title': (
      ar: 'تم إلغاء الطلب',
      en: 'Order cancelled',
    ),
    'notifications.orders.rejected.title': (
      ar: 'تعذر قبول الطلب',
      en: 'Order could not be accepted',
    ),
    'notifications.orders.pending_no_driver.title': (
      ar: 'نبحث عن دلفري',
      en: 'Finding a courier',
    ),
    'notifications.store.new_order.title': (
      ar: 'طلب جديد في المتجر',
      en: 'New store order',
    ),
    'notifications.store.preparing.title': (
      ar: 'تم بدء تحضير الطلب',
      en: 'Order preparation started',
    ),
    'notifications.store.ready_for_pickup.title': (
      ar: 'الطلب جاهز للتسليم',
      en: 'Order ready for handoff',
    ),
    'notifications.store.courier_assigned.title': (
      ar: 'تم تعيين دلفري للطلب',
      en: 'Courier assigned to order',
    ),
    'notifications.store.courier_reassigned.title': (
      ar: 'تم تغيير دلفري الطلب',
      en: 'Order courier changed',
    ),
    'notifications.store.no_driver.title': (
      ar: 'لا يوجد دلفري متاح حالياً',
      en: 'No courier available yet',
    ),
    'notifications.store.customer_confirmed.title': (
      ar: 'الزبون أكد استلام الطلب',
      en: 'Customer confirmed delivery',
    ),
    'notifications.store.customer_cancelled.title': (
      ar: 'الزبون ألغى الطلب',
      en: 'Customer cancelled the order',
    ),
    'notifications.store.settlement_approved.title': (
      ar: 'تمت الموافقة على المستحقات',
      en: 'Store payout approved',
    ),
    'notifications.store.settlement_rejected.title': (
      ar: 'تحتاج المستحقات إلى مراجعة',
      en: 'Payout needs review',
    ),
    'notifications.store.merchant_approved.title': (
      ar: 'تم تفعيل المتجر',
      en: 'Store activated',
    ),
    'notifications.delivery.assigned.title': (
      ar: 'طلب توصيل جديد',
      en: 'New delivery task',
    ),
    'notifications.delivery.reassigned.title': (
      ar: 'تم تحديث مهمة التوصيل',
      en: 'Delivery task updated',
    ),
    'notifications.delivery.removed.title': (
      ar: 'تم إلغاء مهمة التوصيل',
      en: 'Delivery task removed',
    ),
    'notifications.delivery.available.title': (
      ar: 'طلب توصيل متاح',
      en: 'Delivery task available',
    ),
    'notifications.delivery.reconciliation_approved.title': (
      ar: 'تم اعتماد تسوية الطلب',
      en: 'Order settlement approved',
    ),
    'notifications.delivery.reconciliation_rejected.title': (
      ar: 'تسوية الطلب تحتاج تصحيحاً',
      en: 'Order settlement needs correction',
    ),
    'notifications.taxi.assigned.title': (
      ar: 'تم قبول رحلتك',
      en: 'Your ride was accepted',
    ),
    'notifications.taxi.arriving.title': (
      ar: 'الكابتن في الطريق إليك',
      en: 'Captain is on the way',
    ),
    'notifications.taxi.arrived.title': (
      ar: 'الكابتن وصل',
      en: 'Captain arrived',
    ),
    'notifications.taxi.started.title': (ar: 'بدأت الرحلة', en: 'Ride started'),
    'notifications.taxi.completed.title': (
      ar: 'انتهت الرحلة',
      en: 'Ride completed',
    ),
    'notifications.taxi.cancelled.title': (
      ar: 'تم إلغاء الرحلة',
      en: 'Ride cancelled',
    ),
    'notifications.taxi.fare_update.title': (
      ar: 'تحديث سعر الرحلة',
      en: 'Ride fare update',
    ),
    'notifications.services.title': (ar: 'تحديث خدمة', en: 'Service update'),
    'notifications.services.new_request.title': (
      ar: 'طلب خدمة جديد',
      en: 'New service request',
    ),
    'notifications.services.accepted.title': (
      ar: 'تم قبول طلب الخدمة',
      en: 'Service request accepted',
    ),
    'notifications.services.rejected.title': (
      ar: 'تعذر قبول طلب الخدمة',
      en: 'Service request declined',
    ),
    'notifications.services.quote_sent.title': (
      ar: 'وصل عرض سعر',
      en: 'Service quote received',
    ),
    'notifications.services.completed.title': (
      ar: 'اكتملت الخدمة',
      en: 'Service completed',
    ),
    'notifications.services.cancelled.title': (
      ar: 'تم إلغاء طلب الخدمة',
      en: 'Service request cancelled',
    ),
    'notifications.services.message.title': (
      ar: 'رسالة خدمة جديدة',
      en: 'New service message',
    ),
  };
  final title = titles[key];
  if (title != null) return english ? title.en : title.ar;

  switch (key) {
    case 'notifications.orders.status.title':
      return english ? 'Order status update' : 'تحديث حالة الطلب';
    case 'notifications.orders.status.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'قام {storeName} بتحديث حالة طلبك رقم #{orderNumber}: {statusText}',
        en: '{storeName} updated your order #{orderNumber}: {statusText}',
      );
    case 'notifications.orders.merchant_accepted.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'قبل {storeName} طلبك {orderRef} وبدأت مرحلة التحضير.',
        en: '{storeName} accepted your order {orderRef} and started preparing it.',
      );
    case 'notifications.orders.preparing.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: '{storeName} يحضر طلبك {orderRef} الآن.',
        en: '{storeName} is preparing your order {orderRef}.',
      );
    case 'notifications.orders.ready.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'طلبك {orderRef} جاهز وسيتم تسليمه للدلفري قريبا.',
        en: 'Your order {orderRef} is ready and will be handed to the courier soon.',
      );
    case 'notifications.orders.courier_assigned.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تعيين {courierName} لتوصيل طلبك {orderRef}.',
        en: '{courierName} was assigned to deliver your order {orderRef}.',
      );
    case 'notifications.orders.courier_reassigned.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تعيين {courierName} بدلا من الدلفري السابق لطلبك {orderRef}.',
        en: '{courierName} is now assigned to deliver your order {orderRef}.',
      );
    case 'notifications.orders.on_the_way.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: '{courierName} خرج بطلبك {orderRef} وهو في الطريق إليك.',
        en: '{courierName} picked up your order {orderRef} and is heading to you.',
      );
    case 'notifications.orders.arrived.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: '{courierName} وصل إلى موقعك لتسليم طلبك {orderRef}.',
        en: '{courierName} has arrived to deliver your order {orderRef}.',
      );
    case 'notifications.orders.delivered.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تسليم طلبك {orderRef}. شكرا لاستخدام مسلكي.',
        en: 'Your order {orderRef} was delivered. Thank you for using Maslaki.',
      );
    case 'notifications.orders.cancelled.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم إلغاء طلبك {orderRef}. افتح الطلب لمعرفة التفاصيل.',
        en: 'Your order {orderRef} was cancelled. Open the order for details.',
      );
    case 'notifications.orders.rejected.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'لم يتمكن {storeName} من قبول طلبك {orderRef}. افتح الطلب لمعرفة السبب أو اطلب من متجر آخر.',
        en: '{storeName} could not accept your order {orderRef}. Open the order for details or try another store.',
      );
    case 'notifications.orders.pending_no_driver.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'طلبك {orderRef} مقبول، ونبحث الآن عن دلفري متاح لتوصيله.',
        en: 'Your order {orderRef} is accepted, and we are looking for an available courier.',
      );
    case 'notifications.store.new_order.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'وصل طلب {orderRef} من {customerName}. افتح الطلب لقبوله أو بدء التحضير.',
        en: 'Order {orderRef} from {customerName} arrived. Open it to accept or start preparing.',
      );
    case 'notifications.store.preparing.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'طلب {orderRef} أصبح قيد التحضير داخل {storeName}.',
        en: 'Order {orderRef} is now being prepared at {storeName}.',
      );
    case 'notifications.store.ready_for_pickup.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'طلب {orderRef} جاهز. بانتظار تسليمه للدلفري أو تأكيد الاستلام.',
        en: 'Order {orderRef} is ready. Hand it to the courier or confirm pickup.',
      );
    case 'notifications.store.courier_assigned.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تعيين {courierName} لاستلام طلب {orderRef} من {storeName}.',
        en: '{courierName} was assigned to pick up order {orderRef} from {storeName}.',
      );
    case 'notifications.store.courier_reassigned.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تحديث دلفري طلب {orderRef}. الدلفري الحالي: {courierName}.',
        en: 'The courier for order {orderRef} changed. Current courier: {courierName}.',
      );
    case 'notifications.store.no_driver.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'طلب {orderRef} ما زال بانتظار دلفري متاح. سنحدثك عند التعيين.',
        en: 'Order {orderRef} is still waiting for an available courier. We will update you when one is assigned.',
      );
    case 'notifications.store.customer_confirmed.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تأكيد استلام طلب {orderRef} من الزبون. سيظهر ضمن الطلبات المكتملة.',
        en: 'The customer confirmed receiving order {orderRef}. It will appear under completed orders.',
      );
    case 'notifications.store.customer_cancelled.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم إلغاء طلب {orderRef}. افتح لوحة الطلبات لمعرفة التفاصيل.',
        en: 'Order {orderRef} was cancelled. Open the orders dashboard for details.',
      );
    case 'notifications.store.settlement_approved.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تمت الموافقة على مستحقات {storeName} بقيمة {amount} د.ع.',
        en: 'The payout for {storeName} was approved for {amount} IQD.',
      );
    case 'notifications.store.settlement_rejected.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'طلب مستحقات {storeName} بقيمة {amount} د.ع يحتاج إلى مراجعة قبل الصرف.',
        en: 'The payout request for {storeName} worth {amount} IQD needs review before payment.',
      );
    case 'notifications.store.merchant_approved.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تفعيل {storeName}. يمكن للزبائن الآن رؤية المتجر وإرسال الطلبات.',
        en: '{storeName} is now active. Customers can see the store and place orders.',
      );
    case 'notifications.delivery.assigned.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تعيينك لتوصيل طلب {orderRef} من {storeName} إلى {customerName}.',
        en: 'You were assigned to deliver order {orderRef} from {storeName} to {customerName}.',
      );
    case 'notifications.delivery.reassigned.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تغيير مهمة التوصيل لطلب {orderRef}. افتح طلبات الدلفري لمعرفة التفاصيل.',
        en: 'The delivery task for order {orderRef} changed. Open current delivery orders for details.',
      );
    case 'notifications.delivery.removed.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'لم تعد مسؤولا عن توصيل طلب {orderRef}.',
        en: 'You are no longer assigned to deliver order {orderRef}.',
      );
    case 'notifications.delivery.available.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'يوجد طلب توصيل جديد من {storeName}. افتح الطلب لقبوله.',
        en: 'A new delivery task from {storeName} is available. Open it to accept.',
      );
    case 'notifications.delivery.reconciliation_approved.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'اعتمدت الإدارة تسوية الطلب {orderRef}. اضغط لعرض التقرير المالي.',
        en: 'Admin approved the settlement for order {orderRef}. Open the financial report for details.',
      );
    case 'notifications.delivery.reconciliation_rejected.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'رفضت الإدارة تسوية الطلب {orderRef}: {reviewNote}. اضغط لمراجعة التقرير.',
        en: 'Admin rejected the settlement for order {orderRef}: {reviewNote}. Open the report to review it.',
      );
    case 'notifications.taxi.assigned.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم تعيين {captainName} لرحلتك {rideRef}.',
        en: '{captainName} was assigned to your ride {rideRef}.',
      );
    case 'notifications.taxi.arriving.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: '{captainName} يتحرك الآن باتجاه نقطة الانطلاق لرحلتك {rideRef}.',
        en: '{captainName} is heading to the pickup point for ride {rideRef}.',
      );
    case 'notifications.taxi.arrived.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: '{captainName} وصل إلى نقطة الانطلاق لرحلتك {rideRef}.',
        en: '{captainName} arrived at the pickup point for ride {rideRef}.',
      );
    case 'notifications.taxi.started.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'بدأت رحلتك {rideRef}. نتمنى لك رحلة آمنة.',
        en: 'Your ride {rideRef} has started. Have a safe trip.',
      );
    case 'notifications.taxi.completed.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم إنهاء رحلتك {rideRef}. شكرا لاستخدام مسلكي.',
        en: 'Your ride {rideRef} was completed. Thank you for using Maslaki.',
      );
    case 'notifications.taxi.cancelled.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم إلغاء رحلتك {rideRef}. افتح الرحلة لمعرفة التفاصيل.',
        en: 'Your ride {rideRef} was cancelled. Open the ride for details.',
      );
    case 'notifications.taxi.fare_update.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'يوجد تحديث على سعر رحلتك {rideRef}. السعر الحالي {fare} د.ع.',
        en: 'There is a fare update for ride {rideRef}. Current fare: {fare} IQD.',
      );
    case 'notifications.services.body':
      return english
          ? 'There is a new update on your Maslaki service request.'
          : 'هناك تحديث جديد على طلب خدمة مسلكي.';
    case 'notifications.services.new_request.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'لديك طلب جديد لخدمة {serviceName} {requestRef}.',
        en: 'You have a new request for {serviceName} {requestRef}.',
      );
    case 'notifications.services.accepted.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'قبل {providerName} طلب {serviceName} {requestRef}.',
        en: '{providerName} accepted your {serviceName} request {requestRef}.',
      );
    case 'notifications.services.rejected.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'لم يتمكن {providerName} من قبول طلب {serviceName} {requestRef}.',
        en: '{providerName} could not accept your {serviceName} request {requestRef}.',
      );
    case 'notifications.services.quote_sent.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'أرسل {providerName} عرض سعر لخدمة {serviceName} {requestRef}.',
        en: '{providerName} sent a quote for {serviceName} {requestRef}.',
      );
    case 'notifications.services.completed.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم إكمال طلب خدمة {serviceName} {requestRef}.',
        en: 'Your {serviceName} request {requestRef} was completed.',
      );
    case 'notifications.services.cancelled.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'تم إلغاء طلب خدمة {serviceName} {requestRef}.',
        en: 'Your {serviceName} request {requestRef} was cancelled.',
      );
    case 'notifications.services.message.body':
      return _localizedTemplate(
        l10n,
        args,
        ar: 'أرسل {providerName} رسالة بخصوص خدمة {serviceName} {requestRef}.',
        en: '{providerName} sent a message about {serviceName} {requestRef}.',
      );
    default:
      return null;
  }
}

String? _resolveNotificationPiece({
  required AppLocalizations l10n,
  required String? key,
  required Map<String, String> args,
  required String? fallback,
}) {
  final normalizedKey = (key ?? '').trim();
  if (normalizedKey.isEmpty) return fallback;
  final detailed = _resolveDetailedNotificationPiece(
    l10n: l10n,
    key: normalizedKey,
    args: args,
  );
  if (detailed != null) return detailed;
  switch (normalizedKey) {
    case 'notifications.generic.title':
      return l10n.notificationsGenericTitle;
    case 'notifications.generic.body':
      return l10n.notificationsGenericBody;
    case 'notifications.orders.title':
      return l10n.notificationsOrdersTitle;
    case 'notifications.orders.body':
      return l10n.notificationsOrdersBody;
    case 'notifications.delivery.title':
      return l10n.notificationsDeliveryTitle;
    case 'notifications.delivery.body':
      return l10n.notificationsDeliveryBody;
    case 'notifications.taxi.title':
      return l10n.notificationsTaxiTitle;
    case 'notifications.taxi.body':
      return l10n.notificationsTaxiBody;
    case 'notifications.jobs.title':
      return l10n.notificationsJobsTitle;
    case 'notifications.jobs.body':
      return l10n.notificationsJobsBody;
    case 'notifications.real_estate.title':
      return l10n.notificationsRealEstateTitle;
    case 'notifications.real_estate.body':
      return l10n.notificationsRealEstateBody;
    case 'notifications.paid_upgrades.title':
      return l10n.notificationsPaidUpgradesTitle;
    case 'notifications.paid_upgrades.body':
      return l10n.notificationsPaidUpgradesBody;
    case 'notifications.company.title':
      return l10n.notificationsCompanyTitle;
    case 'notifications.company.body':
      return l10n.notificationsCompanyBody;
    case 'notifications.admin.title':
      return l10n.notificationsAdminTitle;
    case 'notifications.admin.body':
      return l10n.notificationsAdminBody;
    case 'notifications.hr.title':
      return l10n.notificationsHrTitle;
    case 'notifications.hr.body':
      return l10n.notificationsHrBody;
    case 'notifications.profile.title':
      return l10n.notificationsProfileTitle;
    case 'notifications.profile.body':
      return l10n.notificationsProfileBody;
    case 'notifications.social.activity.title':
      return l10n.notificationsSocialActivityTitle;
    case 'notifications.social.activity.body':
      return l10n.notificationsSocialActivityBody;
    case 'notifications.social.post.like.title':
      return l10n.notificationsSocialPostLikeTitle;
    case 'notifications.social.post.like.body':
      return l10n.notificationsSocialPostLikeBody;
    case 'notifications.social.reel.like.title':
      return l10n.notificationsSocialReelLikeTitle;
    case 'notifications.social.reel.like.body':
      return l10n.notificationsSocialReelLikeBody;
    case 'notifications.social.comment.title':
      return l10n.notificationsSocialCommentTitle;
    case 'notifications.social.comment.body':
      return l10n.notificationsSocialCommentBody;
    case 'notifications.social.mention.title':
      return l10n.notificationsSocialMentionTitle;
    case 'notifications.social.mention.body':
      return l10n.notificationsSocialMentionBody;
    case 'notifications.social.relation.title':
      return l10n.notificationsSocialRelationTitle;
    case 'notifications.social.relation.body':
      return l10n.notificationsSocialRelationBody;
    case 'notifications.social.story.title':
      return l10n.notificationsSocialStoryTitle;
    case 'notifications.social.story.body':
      return l10n.notificationsSocialStoryBody(
        args['senderName']?.trim().isNotEmpty == true
            ? args['senderName']!.trim()
            : l10n.commonUnknown,
      );
    case 'notifications.social.report.title':
      return l10n.notificationsSocialReportTitle;
    case 'notifications.social.report.body':
      return l10n.notificationsSocialReportBody;
    case 'notifications.social.community.title':
      return l10n.notificationsSocialCommunityTitle;
    case 'notifications.social.community.body':
      return l10n.notificationsSocialCommunityBody;
    case 'notifications.social.call.title':
      return l10n.notificationsSocialCallTitle;
    case 'notifications.social.call.body':
      return l10n.notificationsSocialCallBody(
        args['senderName']?.trim().isNotEmpty == true
            ? args['senderName']!.trim()
            : l10n.commonUnknown,
      );
    case 'notifications.chat.message.title':
      return l10n.notificationsChatMessageTitle;
    case 'notifications.chat.message.body':
      return l10n.notificationsChatMessageBody(
        args['senderName']?.trim().isNotEmpty == true
            ? args['senderName']!.trim()
            : l10n.commonUnknown,
      );
    default:
      return fallback;
  }
}
