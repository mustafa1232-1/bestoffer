import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
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
  String? _error;

  Future<double?> _resolveVideoDurationSeconds(String path) async {
    VideoPlayerController? controller;
    try {
      controller = VideoPlayerController.file(File(path));
      await controller.initialize();
      final duration = controller.value.duration;
      if (duration <= Duration.zero) return null;
      return duration.inMilliseconds / 1000.0;
    } catch (_) {
      return null;
    } finally {
      await controller?.dispose();
    }
  }

  double _roundSeconds(double value) => double.parse(value.toStringAsFixed(3));

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

  Future<void> _publish() async {
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
    setState(() {
      _publishing = true;
      _error = null;
    });
    try {
      final api = ref.read(socialApiProvider);
      final baseStyle = draft.toStoryStyleJson();
      if (media != null &&
          media.isVideo &&
          (media.path ?? '').trim().isNotEmpty) {
        final total = await _resolveVideoDurationSeconds(media.path!);
        if (total != null && total > 60) {
          final chunks = (total / 60.0).ceil();
          for (var index = 0; index < chunks; index++) {
            final start = index * 60.0;
            final remaining = total - start;
            if (remaining <= 0) break;
            final clip = math.min(60.0, remaining);
            final storyStyle = Map<String, dynamic>.from(baseStyle)
              ..['clipStartSec'] = _roundSeconds(start)
              ..['clipDurationSec'] = _roundSeconds(clip);
            await api.createStory(
              caption: index == 0 ? caption : '',
              mediaFile: media,
              storyStyle: storyStyle,
            );
          }
        } else {
          await api.createStory(
            caption: caption,
            mediaFile: media,
            storyStyle: baseStyle,
          );
        }
      } else {
        await api.createStory(
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
