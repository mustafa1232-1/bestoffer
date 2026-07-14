import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_core/local_media_file.dart';

import '../../auth/state/auth_controller.dart';
import '../../social/state/social_controller.dart';
import '../pickers/social_media_picker_v3.dart';
import '../upload/dio_tus_transport.dart';
import '../upload/reel_upload_api_impl.dart';
import '../upload/tus_upload_client.dart';
import 'post_composer_v3.dart';
import 'reel_composer_state.dart';
import 'reel_composer_v3.dart';
import 'story_composer_source.dart';
import 'story_composer_v3.dart';

/// Builds a **production** [ReelComposerController] — real HTTP API + real tus
/// transport, no fakes. Reads providers from [context] via the enclosing
/// [ProviderScope], so any BuildContext (including a modal sheet) can call it.
ReelComposerController buildProductionReelComposerController(
  BuildContext context, {
  required String videoPath,
  required String idempotencyKey,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  final dio = container.read(dioClientProvider).dio;
  return ReelComposerController(
    api: ReelUploadApiImpl(dio),
    idempotencyKey: idempotencyKey,
    tusFactory: ({required uploadUrl, required totalBytes, required assetId}) {
      return TusUploadClient(
        transport: DioTusTransport(filePath: videoPath),
        uploadUrl: uploadUrl,
        totalBytes: totalBytes,
        assetId: assetId,
      );
    },
  );
}

/// Live "Create Reel" (§1): native **video-only** gallery → V3 editor.
Future<void> openReelComposerV3(
  BuildContext context, {
  SocialMediaPickerV3? picker,
  void Function(int reelId)? onPublished,
}) async {
  final p = picker ?? SocialMediaPickerV3();
  final video = await p.pickReelVideo();
  if (video == null || !context.mounted) return;
  final controller = buildProductionReelComposerController(
    context,
    videoPath: video.path,
    idempotencyKey: 'reel-${video.name}-${video.sizeBytes}',
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReelComposerV3(
        video: video,
        controller: controller,
        onPublished: onPublished,
      ),
    ),
  );
}

/// Live "Create Story": native gallery → V3 story composer.
Future<void> openStoryComposerV3FromGallery(
  BuildContext context, {
  SocialMediaPickerV3? picker,
}) async {
  final p = picker ?? SocialMediaPickerV3();
  final media = await p.pickStoryImageOrVideo();
  if (media == null || !context.mounted) return;
  final local = LocalStoryMedia(
    path: media.path,
    isVideo: media.isVideo,
    width: media.width,
    height: media.height,
  );
  final source = media.isVideo
      ? StoryComposerSource.localVideo(local)
      : StoryComposerSource.localImage(local);
  await Navigator.of(context).push(StoryComposerV3.route(source));
}

/// Live "Create text Story": V3 story composer in text mode.
Future<void> openStoryComposerV3Text(BuildContext context) {
  return Navigator.of(context)
      .push(StoryComposerV3.route(StoryComposerSource.text('')));
}

/// Live "Add Reel to Story" (§5): reel is the full-canvas base media.
Future<void> openStoryComposerV3WithReel(
  BuildContext context, {
  required SharedReelSource reel,
}) {
  return Navigator.of(context)
      .push(StoryComposerV3.route(StoryComposerSource.sharedReel(reel)));
}

/// Live "Create Post" (§2): native multi-select gallery → V3 post composer.
/// Publishing goes through the existing `createPost` controller (native picker
/// paths only — never FilePicker).
Future<bool?> openPostComposerV3(
  BuildContext context, {
  SocialMediaPickerV3? picker,
}) async {
  final p = picker ?? SocialMediaPickerV3();
  final media = await p.pickMultiplePostMedia();
  if (!context.mounted) return null;
  final container = ProviderScope.containerOf(context, listen: false);
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => PostComposerV3(
        initialMedia: media,
        onAddMore: p.pickMultiplePostMedia,
        onPublish: (result) async {
          final files = result.media
              .map((m) => LocalMediaFile(
                    name: m.name,
                    path: m.path,
                    bytes: null,
                    mimeType: m.mimeType,
                  ))
              .toList();
          await container.read(socialControllerProvider.notifier).createPost(
                caption: result.caption,
                postKind: result.postKind,
                mediaFiles: files.isEmpty ? null : files,
                audienceScopeType:
                    result.audience == 'public' ? 'global' : 'followers',
              );
          final err = container.read(socialControllerProvider).error;
          return err == null || err.trim().isEmpty;
        },
      ),
    ),
  );
}
