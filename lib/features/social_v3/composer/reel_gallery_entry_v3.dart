import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_core/local_media_file.dart';

import '../../auth/state/auth_controller.dart';
import '../../social/state/social_controller.dart';
import '../capabilities/social_capabilities_controller.dart';
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

/// Live "Create Story": native gallery → V3 story composer, publishing via the
/// existing `createStory` controller with the (backend-validated) scope.
Future<void> openStoryComposerV3FromGallery(
  BuildContext context, {
  SocialMediaPickerV3? picker,
  StoryComposerScope scope = StoryComposerScope.global,
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
  final container = ProviderScope.containerOf(context, listen: false);
  await Navigator.of(context).push(
    StoryComposerV3.route(
      source,
      scope: scope,
      onPublish: (caption, publishScope) => _publishStory(
        container,
        caption: caption,
        media: media,
        scope: publishScope,
      ),
    ),
  );
}

/// Live scoped-community story (§2/§3): consults the authoritative backend
/// capability first. When scoped stories are not yet supported, it informs the
/// user and opens a **global** story instead — never implying restricted
/// visibility, and never sending a scoped request the backend would reject.
Future<void> openStoryComposerV3Scoped(
  BuildContext context, {
  required String scopeType,
  required String scopeCode,
  String? label,
  bool official = false,
  SocialMediaPickerV3? picker,
}) async {
  final container = ProviderScope.containerOf(context, listen: false);
  await container.read(socialCapabilitiesProvider.notifier).ensureFresh();
  final caps = container.read(socialCapabilitiesProvider);

  if (!caps.storyAudienceScope.supportsType(scopeType)) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('القصص المخصصة للبناية ستتوفر قريباً')),
      );
    }
    if (!context.mounted) return;
    // Fall back to a clearly-global story (still fully functional).
    await openStoryComposerV3FromGallery(context, picker: picker);
    return;
  }

  if (!context.mounted) return;
  await openStoryComposerV3FromGallery(
    context,
    picker: picker,
    scope: StoryComposerScope(
      scope: StoryAudienceScopeX.fromWire(scopeType),
      scopeCode: scopeCode,
      label: label,
      isOfficial: official,
      locked: true,
    ),
  );
}

Future<bool> _publishStory(
  ProviderContainer container, {
  required String caption,
  required PickedSocialMedia media,
  required StoryComposerScope scope,
}) async {
  await container.read(socialControllerProvider.notifier).createStory(
        caption: caption,
        mediaFile: LocalMediaFile(
          name: media.name,
          path: media.path,
          bytes: null,
          mimeType: media.mimeType,
        ),
        audienceScopeType: scope.scope.wireType,
        audienceScopeCode: scope.scopeCode,
      );
  final err = container.read(socialControllerProvider).error;
  return err == null || err.trim().isEmpty;
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

/// Live merchant review (§3): opens the V3 post composer in review mode with
/// the merchant preselected. Publishes via `createPost(postKind:merchant_review)`
/// — the backend validates the merchant, rating, and verified-purchase state.
Future<bool?> openPostComposerV3Review(
  BuildContext context, {
  required MerchantReviewDraft review,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return Navigator.of(context).push<bool>(
    MaterialPageRoute<bool>(
      builder: (_) => PostComposerV3(
        initialMedia: const [],
        mode: PostComposerMode.merchantReview,
        review: review,
        onPublish: (result) async {
          await container.read(socialControllerProvider.notifier).createPost(
                caption: result.caption,
                postKind: 'merchant_review',
                merchantId: result.review?.merchantId,
                reviewRating: result.rating,
              );
          final err = container.read(socialControllerProvider).error;
          return err == null || err.trim().isEmpty;
        },
      ),
    ),
  );
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
