import 'package:flutter/material.dart';

import '../../../core/auth/auth_guard.dart';
import '../../social_v3/composer/social_create_selector_v3.dart';

/// Live post/reel/story creation entry — cut over to Social V3 (§2/§4).
///
/// Delegates to [showSocialCreateSelectorV3] so every caller (feed, community,
/// profile) opens the V3 Post/Story/Reel composers. The old
/// `_CreatePostModePickerSheet` + `showSocialPostComposerScreen` +
/// `SocialCreatePostSheet` UI were deleted in the final live cutover.
Future<bool?> showSocialCreatePostSheet(BuildContext context) async {
  if (!await requireAuthBeforeAction(
    context,
    featureArabic: 'إنشاء منشور أو ريل',
    featureEnglish: 'creating a post or reel',
  )) {
    return null;
  }
  if (!context.mounted) return null;
  return showSocialCreateSelectorV3(context);
}
