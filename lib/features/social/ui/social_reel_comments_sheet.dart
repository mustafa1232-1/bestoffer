import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/social_models.dart';
import 'social_post_details_screen.dart';

Future<int?> showSocialReelCommentsSheet(
  BuildContext context, {
  required SocialPost reelPost,
}) {
  return showSocialPostCommentsSheet(
    context,
    post: reelPost,
    title: context.l10n.socialReelCommentsTitle,
  );
}
