import 'package:flutter/material.dart';

import '../creator/creator_adapters.dart';
import '../creator/social_camera_creator_screen.dart';
import '../models/social_story_document.dart';
import 'social_story_composer_screen.dart';

/// Story creation entry point. Opens the full-screen Maslaki story camera hub
/// directly (camera first), then routes the outcome into the composer:
/// - media (camera capture / layout composite / gallery import) → media composer
/// - text mode → text composer
///
/// Returns `true` when a story was published, mirroring the previous contract.
Future<bool?> showSocialStoryComposerEntrySheet(BuildContext context) async {
  final outcome = await showStoryCamera(context);
  if (outcome == null || !context.mounted) return null;

  SocialStoryDraft? initialDraft;
  final SocialStoryComposerMode mode;
  if (outcome.textMode) {
    mode = SocialStoryComposerMode.text;
  } else {
    final mediaDraft = outcome.mediaDraft;
    if (mediaDraft == null) return null;
    initialDraft = buildStoryDraftFromCreator(mediaDraft);
    mode = SocialStoryComposerMode.media;
  }

  if (!context.mounted) return null;
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) =>
          SocialStoryComposerScreen(initialMode: mode, initialDraft: initialDraft),
    ),
  );
}
