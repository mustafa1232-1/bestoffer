// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../creator/creator_models.dart';
import '../creator/story_segmentation_service.dart';
import '../data/social_stream_upload_service.dart';
import '../models/social_story_document.dart';
import '../state/social_controller.dart';
import '../state/social_story_draft_controller.dart';
import 'widgets/social_story_canvas.dart';

class SocialStoryPublishScreen extends ConsumerStatefulWidget {
  const SocialStoryPublishScreen({super.key});

  @override
  ConsumerState<SocialStoryPublishScreen> createState() =>
      _SocialStoryPublishScreenState();
}

class _SocialStoryPublishScreenState
    extends ConsumerState<SocialStoryPublishScreen> {
  bool _publishing = false;
  bool _loadingSegments = false;
  String? _error;
  List<StorySegmentDraft> _segments = const <StorySegmentDraft>[];

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadSegments);
  }

  String _publishCaption() {
    final l10n = context.l10n;
    final draft = ref.read(socialStoryDraftControllerProvider).draft;
    final explicit = draft.caption.trim();
    if (explicit.isNotEmpty) return explicit;
    for (final layer in draft.layers) {
      if (layer.type == SocialStoryLayerType.text &&
          (layer.text ?? '').trim().isNotEmpty) {
        return layer.text!.trim();
      }
    }
    if (draft.attachment?.isReelShare == true) {
      return l10n.socialStoryPublishSharedReel;
    }
    if (draft.attachment?.isPostShare == true) {
      return l10n.socialStoryPublishSharedPost;
    }
    return '';
  }

  Future<void> _loadSegments() async {
    final draft = ref.read(socialStoryDraftControllerProvider).draft;
    final media = draft.buildLocalMediaFile();
    if (media == null || !media.isVideo) return;
    setState(() => _loadingSegments = true);
    try {
      final segments = await StorySegmentationService().buildSegments(media);
      if (!mounted) return;
      setState(() => _segments = segments);
    } finally {
      if (mounted) {
        setState(() => _loadingSegments = false);
      }
    }
  }

  void _removeSegment(int index) {
    if (index < 0 || index >= _segments.length) return;
    setState(() {
      _segments = List<StorySegmentDraft>.from(_segments)..removeAt(index);
    });
  }

  Future<void> _publish() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'نشر ستوري',
      featureEnglish: 'publishing a story',
    )) {
      return;
    }
    if (!mounted) return;
    if (_publishing) return;
    final l10n = context.l10n;
    final draft = ref.read(socialStoryDraftControllerProvider).draft;
    final media = draft.buildLocalMediaFile();
    final caption = _publishCaption();
    if (caption.isEmpty && media == null && draft.attachment == null) {
      setState(() {
        _error = l10n.socialStoryPublishEmptyError;
      });
      return;
    }
    if (media != null &&
        media.isVideo &&
        _segments.isEmpty &&
        !_loadingSegments) {
      final computed = await StorySegmentationService().buildSegments(media);
      if (computed.isNotEmpty && mounted) {
        setState(() => _segments = computed);
      }
    }
    if (media != null && media.isVideo && _segments.isEmpty) {
      setState(() {
        _error = l10n.socialCreatorStorySegmentsMissing;
      });
      return;
    }
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final uploader = SocialStreamUploadService(ref.read(socialApiProvider));
      final baseStyle = Map<String, dynamic>.from(draft.toStoryStyleJson())
        ..remove('clipStartSec')
        ..remove('clipDurationSec');
      if ((draft.filterId ?? '').trim().isNotEmpty) {
        baseStyle['filterId'] = draft.filterId;
      }
      if ((draft.effectId ?? '').trim().isNotEmpty) {
        baseStyle['effectId'] = draft.effectId;
      }
      if ((draft.captureSource ?? '').trim().isNotEmpty) {
        baseStyle['captureSource'] = draft.captureSource;
      }
      if ((draft.timeMoodKey ?? '').trim().isNotEmpty) {
        baseStyle['timeMoodKey'] = draft.timeMoodKey;
      }
      if ((draft.placePulseLabel ?? '').trim().isNotEmpty) {
        baseStyle['placePulseLabel'] = draft.placePulseLabel;
      }
      if (draft.hasMaslakiSeal) {
        baseStyle['hasMaslakiSeal'] = true;
      }
      if ((draft.maslakiMoodKey ?? '').trim().isNotEmpty) {
        baseStyle['maslakiMoodKey'] = draft.maslakiMoodKey;
      }
      int? streamAssetId;
      if (media != null && media.isVideo) {
        final uploaded = await uploader.uploadVideoAndWaitReady(
          mediaFile: media,
          sourceType: 'story',
          title: caption.isNotEmpty ? caption : 'story',
        );
        streamAssetId = uploaded.id;
      }
      if (media != null && media.isVideo && _segments.length > 1) {
        final sequenceId =
            '${draft.draftId}-${DateTime.now().microsecondsSinceEpoch}';
        for (var index = 0; index < _segments.length; index++) {
          final segment = _segments[index];
          final storyStyle = Map<String, dynamic>.from(baseStyle)
            ..['clipStartSec'] = segment.startSec
            ..['clipDurationSec'] = segment.durationSec
            ..['sequenceId'] = sequenceId
            ..['segmentIndex'] = index
            ..['segmentCount'] = _segments.length;
          await ref
              .read(socialControllerProvider.notifier)
              .createStory(
                caption: index == 0 ? caption : '',
                mediaAssetId: streamAssetId,
                storyStyle: storyStyle,
              );
        }
      } else if (media != null && media.isVideo && _segments.length == 1) {
        final onlySegment = _segments.first;
        final storyStyle = Map<String, dynamic>.from(baseStyle)
          ..['clipStartSec'] = onlySegment.startSec
          ..['clipDurationSec'] = onlySegment.durationSec;
        await ref
            .read(socialControllerProvider.notifier)
            .createStory(
              caption: caption,
              mediaAssetId: streamAssetId,
              storyStyle: storyStyle,
            );
      } else {
        await ref
            .read(socialControllerProvider.notifier)
            .createStory(
              caption: caption,
              mediaFile: media,
              storyStyle: baseStyle,
            );
      }
      await ref
          .read(socialControllerProvider.notifier)
          .loadStories(silent: true);
      await ref
          .read(socialStoryDraftControllerProvider.notifier)
          .clearPersistedDraft();
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapAnyError(e, fallback: l10n.socialStoryPublishFailed);
      });
    } finally {
      if (mounted) {
        setState(() => _publishing = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final draft = ref.watch(socialStoryDraftControllerProvider).draft;
    final media = draft.buildLocalMediaFile();
    final showSegments = media != null && media.isVideo;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialStoryPublishTitle)),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Center(child: SocialStoryCanvas(draft: draft)),
              ),
              const SizedBox(height: 18),
              Text(
                l10n.socialStoryPublishSharingTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(l10n.socialStoryPublishSharingBody),
              ),
              if (showSegments) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.socialCreatorStorySegments(_segments.length),
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (_loadingSegments)
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_segments.isEmpty && !_loadingSegments)
                  Text(
                    l10n.socialCreatorStorySegmentsMissing,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  )
                else
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: List<Widget>.generate(_segments.length, (index) {
                      final segment = _segments[index];
                      return InputChip(
                        onDeleted: _segments.length > 1
                            ? () => _removeSegment(index)
                            : null,
                        label: Text(
                          '${index + 1}: ${segment.startSec.toStringAsFixed(0)}s - ${(segment.startSec + segment.durationSec).toStringAsFixed(0)}s',
                        ),
                      );
                    }),
                  ),
              ],
              if ((_error ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _publishing
                          ? null
                          : () async {
                              final messenger = ScaffoldMessenger.of(context);
                              final savedLabel =
                                  l10n.socialStoryPublishDraftSaved;
                              await ref
                                  .read(
                                    socialStoryDraftControllerProvider.notifier,
                                  )
                                  .saveDraft();
                              if (!mounted) return;
                              messenger.showSnackBar(
                                SnackBar(content: Text(savedLabel)),
                              );
                            },
                      icon: const Icon(Icons.save_outlined),
                      label: Text(l10n.socialStoryPublishSaveDraft),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _publishing ? null : _publish,
                      icon: _publishing
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(
                        _publishing
                            ? l10n.socialStoryPublishPublishing
                            : l10n.commonPublish,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
