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
    fallback:
        notification.title.trim().isEmpty
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

String? _resolveNotificationPiece({
  required AppLocalizations l10n,
  required String? key,
  required Map<String, String> args,
  required String? fallback,
}) {
  final normalizedKey = (key ?? '').trim();
  if (normalizedKey.isEmpty) return fallback;
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
