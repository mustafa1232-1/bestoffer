import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../pickers/social_media_picker_v3.dart';
import '../upload/dio_tus_transport.dart';
import '../upload/reel_upload_api_impl.dart';
import '../upload/tus_upload_client.dart';
import 'reel_composer_state.dart';
import 'reel_composer_v3.dart';
import 'story_composer_source.dart';
import 'story_composer_v3.dart';

/// Builds a **production** [ReelComposerController] — real HTTP API + real tus
/// transport, no fakes. The tus client reads chunks from [videoPath] on disk.
ReelComposerController buildProductionReelComposerController(
  WidgetRef ref, {
  required String videoPath,
  required String idempotencyKey,
}) {
  final dio = ref.read(dioClientProvider).dio;
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

/// The canonical live "Create Reel" entry (§1): opens the native **video-only**
/// gallery, then the V3 editor driven by a production controller. Cancellation
/// (null pick) is a no-op.
Future<void> openReelComposerV3(
  BuildContext context,
  WidgetRef ref, {
  SocialMediaPickerV3? picker,
  int idempotencySeed = 0,
  void Function(int reelId)? onPublished,
}) async {
  final p = picker ?? SocialMediaPickerV3();
  final video = await p.pickReelVideo();
  if (video == null || !context.mounted) return;
  final controller = buildProductionReelComposerController(
    ref,
    videoPath: video.path,
    idempotencyKey: 'reel-$idempotencySeed-${video.name}-${video.sizeBytes}',
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

/// The canonical live "Create Story" entry: opens the native gallery then the
/// V3 story composer with the chosen local media.
Future<void> openStoryComposerV3FromGallery(
  BuildContext context,
  WidgetRef ref, {
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

/// The canonical "Add Reel to Story" entry (§5): opens the V3 story composer
/// with the reel already the full-canvas base media.
Future<void> openStoryComposerV3WithReel(
  BuildContext context, {
  required SharedReelSource reel,
}) {
  return Navigator.of(context).push(
    StoryComposerV3.route(StoryComposerSource.sharedReel(reel)),
  );
}
