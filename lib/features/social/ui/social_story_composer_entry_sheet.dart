import 'package:flutter/material.dart';

import '../../../core/auth/auth_guard.dart';
import '../models/social_story_document.dart';
import 'social_story_composer_screen.dart';

/// Story creation entry point. Opens the gallery-first composer directly so
/// the user lands in the photo/video picker flow instead of a generic file
/// picker or camera-first hub. Camera capture remains available from the
/// composer itself as a secondary action.
Future<bool?> showSocialStoryComposerEntrySheet(BuildContext context) async {
  if (!await requireAuthBeforeAction(
    context,
    featureArabic: 'إنشاء قصة',
    featureEnglish: 'creating a story',
  )) {
    return null;
  }
  if (!context.mounted) return null;
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const SocialStoryComposerScreen(
        initialMode: SocialStoryComposerMode.media,
      ),
    ),
  );
}
