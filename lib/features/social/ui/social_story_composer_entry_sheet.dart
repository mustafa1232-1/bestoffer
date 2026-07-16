import 'package:flutter/material.dart';

import '../../../core/auth/auth_guard.dart';
import '../../social_v3/composer/reel_gallery_entry_v3.dart';

/// Story creation entry point — cut over to Social V3 (§3).
///
/// Delegates to the V3 blank story editor so every "Create Story" caller
/// (feed ring add, community) opens `StoryComposerV3` directly. The old
/// `SocialStoryComposerScreen` is no longer reachable from normal creation.
Future<bool?> showSocialStoryComposerEntrySheet(BuildContext context) async {
  if (!await requireAuthBeforeAction(
    context,
    featureArabic: 'إنشاء قصة',
    featureEnglish: 'creating a story',
  )) {
    return null;
  }
  if (!context.mounted) return null;
  await openStoryComposerV3Text(context);
  return true;
}
