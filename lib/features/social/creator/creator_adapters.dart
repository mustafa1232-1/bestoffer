import '../../../core/files/local_media_file.dart';
import '../models/social_story_document.dart';
import 'creator_models.dart';

SocialStoryDraft buildStoryDraftFromCreator(CreatorPreviewDraft preview) {
  final clip = preview.clip;
  return SocialStoryDraft.initialText().copyWith(
    mode: SocialStoryComposerMode.media,
    mediaPath: clip.mediaFile.path,
    mediaName: clip.mediaFile.name,
    mediaMimeType: clip.mediaFile.mimeType,
    filterId: clip.filterId,
    effectId: clip.effectId,
    captureSource: clip.captureSource,
    timeMoodKey: clip.timeMoodKey,
    placePulseLabel: clip.placePulseLabel,
    hasMaslakiSeal: clip.hasMaslakiSeal,
  );
}

LocalMediaFile buildReelMediaFromCreator(CreatorPreviewDraft preview) {
  return preview.clip.mediaFile;
}

Map<String, dynamic> buildReelStyleFromCreator(CreatorPreviewDraft preview) {
  final clip = preview.clip;
  return <String, dynamic>{
    if ((clip.filterId ?? '').trim().isNotEmpty) 'filterId': clip.filterId,
    if ((clip.effectId ?? '').trim().isNotEmpty) 'effectId': clip.effectId,
    'captureSource': clip.captureSource,
    'durationSec': double.parse(
      (clip.duration.inMilliseconds / 1000.0).toStringAsFixed(3),
    ),
    if ((clip.coverFrameMs ?? 0) > 0) 'coverFrameMs': clip.coverFrameMs,
    if ((clip.timeMoodKey ?? '').trim().isNotEmpty) 'timeMoodKey': clip.timeMoodKey,
    if ((clip.placePulseLabel ?? '').trim().isNotEmpty) 'placePulseLabel': clip.placePulseLabel,
    if (clip.hasMaslakiSeal) 'hasMaslakiSeal': true,
  };
}
