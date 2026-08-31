import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:social_core/local_media_file.dart';

import '../../../core/auth/auth_guard.dart';
import '../../auth/state/auth_controller.dart';
import '../../social/data/social_stream_upload_service.dart';
import '../../social/state/social_controller.dart';
import '../../social/models/social_story_document.dart';
import '../capabilities/social_capabilities_controller.dart';
import '../capabilities/story_scope_error.dart';
import '../pickers/social_media_picker_v3.dart';
import 'story_media_type_picker.dart';
import '../upload/dio_tus_transport.dart';
import '../upload/reel_map_normalizer.dart';
import '../upload/reel_upload_api_impl.dart';
import '../upload/tus_upload_client.dart';
import 'post_composer_v3.dart';
import 'reel_composer_state.dart';
import 'reel_composer_v3.dart';
import 'story_composer_source.dart';
import 'story_composer_v3.dart';
import '../../social/state/social_story_draft_controller.dart';

const int kMaxReelDurationMs = 3600 * 1000;
int _reelIdempotencyCounter = 0;

String createReelIdempotencyKey(PickedSocialMedia video) {
  final timestamp = DateTime.now().toUtc().microsecondsSinceEpoch;
  _reelIdempotencyCounter = (_reelIdempotencyCounter + 1) & 0x7fffffff;
  return 'reel-$timestamp-$_reelIdempotencyCounter-${video.sizeBytes ?? 0}-${video.name.hashCode}';
}

String? validatePickedReelVideo(PickedSocialMedia video) {
  if (!video.isVideo) {
    return 'اختر فيديو فقط لإنشاء الريل.';
  }
  final mime = (video.mimeType ?? '').trim().toLowerCase();
  final inferred = inferMediaTypeFromNameOrMime(
    name: video.name,
    mimeType: mime.isEmpty ? null : mime,
  );
  if (mime.isNotEmpty && !mime.startsWith('video/')) {
    return 'صيغة الملف المختار ليست فيديو.';
  }
  if (inferred != PickedMediaType.video) {
    return 'صيغة الفيديو غير مدعومة.';
  }
  final size = video.sizeBytes;
  if (size == null || size <= 0) {
    return 'تعذر قراءة حجم الفيديو. اختر فيديو آخر.';
  }
  final duration = video.durationMs;
  if (duration != null && duration > kMaxReelDurationMs) {
    return 'مدة الفيديو أطول من الحد المسموح.';
  }
  return null;
}

void _showReelPickerMessage(BuildContext context, String message) {
  if (!context.mounted) return;
  ScaffoldMessenger.maybeOf(
    context,
  )?.showSnackBar(SnackBar(content: Text(message)));
}

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
  if (!await requireAuthBeforeAction(
    context,
    featureArabic: 'إنشاء ريل',
    featureEnglish: 'creating a reel',
  )) {
    return;
  }
  final p = picker ?? SocialMediaPickerV3();
  final PickedSocialMedia? video;
  try {
    video = await p.pickReelVideo();
  } on SocialPickerException {
    if (!context.mounted) return;
    _showReelPickerMessage(
      context,
      'تعذر فتح معرض الفيديو. تحقق من صلاحية الصور والفيديو وحاول مجدداً.',
    );
    return;
  } catch (_) {
    if (!context.mounted) return;
    _showReelPickerMessage(
      context,
      'تعذر فتح معرض الفيديو. تحقق من صلاحية الصور والفيديو وحاول مجدداً.',
    );
    return;
  }
  final selectedVideo = video;
  if (selectedVideo == null || !context.mounted) return;
  final validationError = validatePickedReelVideo(selectedVideo);
  if (validationError != null) {
    _showReelPickerMessage(context, validationError);
    return;
  }
  final controller = buildProductionReelComposerController(
    context,
    videoPath: selectedVideo.path,
    idempotencyKey: createReelIdempotencyKey(selectedVideo),
  );
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => ReelComposerV3(
        video: selectedVideo,
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
  bool audienceScopeSupported = false,
}) async {
  final p = picker ?? SocialMediaPickerV3();
  final type = await pickStoryMediaType(context);
  if (type == null || !context.mounted) return;
  final media = type == PickedMediaType.video
      ? await p.pickStoryVideo()
      : await p.pickStoryImage();
  if (media == null || !context.mounted) return;
  final local = LocalStoryMedia(
    path: media.path,
    isVideo: media.isVideo,
    width: media.width,
    height: media.height,
    name: media.name,
    mimeType: media.mimeType,
  );
  final source = media.isVideo
      ? StoryComposerSource.localVideo(local)
      : StoryComposerSource.localImage(local);
  final container = ProviderScope.containerOf(context, listen: false);
  await Navigator.of(context).push(
    StoryComposerV3.route(
      source,
      scope: scope,
      audienceScopeSupported: audienceScopeSupported,
      onPublish: (caption, publishScope) =>
          _publishStoryDraft(container, caption: caption, scope: publishScope),
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
    if (!context.mounted) return;
    // Explicit confirmation (§3) — never silently redirect a scoped intent into
    // a global publish. Default action is Cancel.
    final createGlobal = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('القصص المخصصة غير متاحة حالياً'),
        content: const Text(
          'ميزة نشر قصة خاصة بسكان البناية ستتوفر قريباً. لن يتم نشر قصتك بشكل '
          'عام دون موافقتك.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('إنشاء قصة عامة'),
          ),
        ],
      ),
    );
    if (createGlobal != true || !context.mounted) return; // default: Cancel
    await openStoryComposerV3FromGallery(context, picker: picker);
    return;
  }

  if (!context.mounted) return;
  await openStoryComposerV3FromGallery(
    context,
    picker: picker,
    audienceScopeSupported: true,
    scope: StoryComposerScope(
      scope: StoryAudienceScopeX.fromWire(scopeType),
      scopeCode: scopeCode,
      label: label,
      isOfficial: official,
      locked: true,
    ),
  );
}

Future<bool> _publishStoryDraft(
  ProviderContainer container, {
  required String caption,
  required StoryComposerScope scope,
}) async {
  final draft = container.read(socialStoryDraftControllerProvider).draft;
  final mediaFile = draft.buildLocalMediaFile();
  final storyStyle = normalizeReelMap(
    draft.toStoryStyleJson(),
    'INVALID_REEL_STORY_STYLE',
  );
  final publishCaption = caption.trim().isNotEmpty
      ? caption.trim()
      : draft.caption.trim();

  if (scope.scope == StoryAudienceScope.global) {
    await container
        .read(socialControllerProvider.notifier)
        .createStory(
          caption: publishCaption,
          mediaFile: mediaFile,
          storyStyle: storyStyle,
        );
    final err = container.read(socialControllerProvider).error;
    final ok = err == null || err.trim().isEmpty;
    if (ok) {
      await container
          .read(socialStoryDraftControllerProvider.notifier)
          .clearPersistedDraft();
    }
    return ok;
  }

  // Non-global remains a direct API call so the existing scoped capability
  // fail-closed behavior and 409 handling stay exactly the same. Only the video
  // transport changes: videos are uploaded directly to Stream first and the
  // Story is then created with mediaAssetId, never with a multipart video body.
  try {
    final api = container.read(socialApiProvider);
    var resolvedMediaFile = mediaFile;
    int? mediaAssetId;
    if (mediaFile?.isVideo == true) {
      final asset = await SocialStreamUploadService(api).uploadVideoAndWaitReady(
        mediaFile: mediaFile!,
        sourceType: 'story',
        title: publishCaption.isEmpty ? null : publishCaption,
        waitForReady: false,
      );
      mediaAssetId = asset.id;
      resolvedMediaFile = null;
    }

    await api.createStory(
      caption: publishCaption,
      mediaFile: resolvedMediaFile,
      mediaAssetId: mediaAssetId,
      storyStyle: storyStyle,
      audienceScopeType: scope.scope.wireType,
      audienceScopeCode: scope.scopeCode,
    );
    await container.read(socialControllerProvider.notifier).loadStories();
    await container
        .read(socialStoryDraftControllerProvider.notifier)
        .clearPersistedDraft();
    return true;
  } catch (error) {
    if (isStoryScopeUnavailableError(error)) {
      // Draft preserved (composer stays open); capability drops to fail-closed;
      // do NOT retry as global.
      container
          .read(socialCapabilitiesProvider.notifier)
          .markStoryScopeUnsupported();
    }
    return false;
  }
}

/// Live "Create text Story": V3 story composer in text mode.
Future<void> openStoryComposerV3Text(BuildContext context) async {
  final container = ProviderScope.containerOf(context, listen: false);
  final notifier = container.read(socialStoryDraftControllerProvider.notifier);
  SocialStoryDraft? restored;
  try {
    restored = await notifier.restoreLastDraft();
  } catch (_) {
    restored = null;
  }
  final source = restored == null
      ? StoryComposerSource.text('')
      : StoryComposerSource.restoredDraft(restored);
  if (!context.mounted) return;
  await Navigator.of(context).push(
    StoryComposerV3.route(
      source,
      onPublish: (caption, scope) =>
          _publishStoryDraft(container, caption: caption, scope: scope),
    ),
  );
}

/// Live "Add Reel to Story" (§5): reel is the full-canvas base media.
Future<void> openStoryComposerV3WithReel(
  BuildContext context, {
  required SharedReelSource reel,
}) {
  final container = ProviderScope.containerOf(context, listen: false);
  return Navigator.of(context).push(
    StoryComposerV3.route(
      StoryComposerSource.sharedReel(reel),
      onPublish: (caption, scope) =>
          _publishStoryDraft(container, caption: caption, scope: scope),
    ),
  );
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
          await container
              .read(socialControllerProvider.notifier)
              .createPost(
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
              .map(
                (m) => LocalMediaFile(
                  name: m.name,
                  path: m.path,
                  bytes: null,
                  mimeType: m.mimeType,
                ),
              )
              .toList();
          await container
              .read(socialControllerProvider.notifier)
              .createPost(
                caption: result.caption,
                postKind: result.postKind,
                mediaFiles: files.isEmpty ? null : files,
                audienceScopeType: result.audience == 'public'
                    ? 'global'
                    : 'followers',
              );
          final err = container.read(socialControllerProvider).error;
          return err == null || err.trim().isEmpty;
        },
      ),
    ),
  );
}