import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';

bool looksCorruptedArabicText(String value) {
  if (value.isEmpty) return false;
  if (RegExp(r'[\uFFFD]').hasMatch(value)) return true;
  if (RegExp(r'[\u0080-\u009F]').hasMatch(value)) return true;
  if (RegExp(r'[\u00C2\u00C3\u00D8\u00D9\u00E2]').hasMatch(value)) {
    return true;
  }
  return false;
}

String safeCommunityLt(
  BuildContext context, {
  required String ar,
  required String en,
}) {
  final safeAr = looksCorruptedArabicText(ar) ? en : ar;
  final locale = Localizations.localeOf(context).languageCode.toLowerCase();
  return locale == 'en' ? en : safeAr;
}

Map<String, String> communityApiMessages(BuildContext context) {
  final l10n = context.l10n;
  return {
    'COMMUNITY_SCOPE_FORBIDDEN': l10n.socialCommunityScopeForbidden,
    'COMMUNITY_MANAGER_REQUIRED': l10n.socialCommunityManagerRequired,
    'COMMUNITY_CHAT_LOCKED': l10n.socialCommunityChatLocked,
    'COMMUNITY_CHAT_BANNED': l10n.socialCommunityChatBanned,
    'COMMUNITY_MEMBER_MUTED': l10n.socialCommunityMemberMuted,
    'COMMUNITY_MEMBER_REMOVED': l10n.socialCommunityMemberRemoved,
    'COMMUNITY_MEMBER_REMOVE_FORBIDDEN':
        l10n.socialCommunityMemberRemoveForbidden,
    'COMMUNITY_MEMBER_REMOVE_SELF_NOT_ALLOWED':
        l10n.socialCommunityMemberRemoveSelfNotAllowed,
    'COMMUNITY_MANAGER_ASSIGN_FORBIDDEN':
        l10n.socialCommunityManagerAssignForbidden,
    'COMMUNITY_MANAGER_REVOKE_FORBIDDEN':
        l10n.socialCommunityManagerRevokeForbidden,
  };
}
