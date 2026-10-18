import 'dart:async';

import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';
import '../../social/ui/widgets/social_design_theme.dart';
import '../../social/ui/widgets/social_mention_composer_field.dart';
import '../pickers/social_media_picker_v3.dart';
import 'reel_composer_state.dart';

class ReelPublishScreen extends StatefulWidget {
  const ReelPublishScreen({
    super.key,
    required this.video,
    required this.controller,
    required this.reelStyle,
    required this.preview,
    this.initialCaption = '',
    this.onCaptionChanged,
    this.prepareVideo,
    this.initialCommentsEnabled = true,
    this.initialSharingEnabled = true,
    this.onSettingsChanged,
  });

  final PickedSocialMedia video;
  final ReelComposerController controller;
  final Map<String, dynamic> reelStyle;
  final Widget preview;
  final String initialCaption;
  final ValueChanged<String>? onCaptionChanged;
  final ReelVideoPreparer? prepareVideo;
  final bool initialCommentsEnabled;
  final bool initialSharingEnabled;
  final void Function(bool comments, bool sharing)? onSettingsChanged;

  @override
  State<ReelPublishScreen> createState() => _ReelPublishScreenState();
}

class _ReelPublishScreenState extends State<ReelPublishScreen> {
  late final SocialMentionComposerController _caption;
  bool _comments = true;
  bool _sharing = true;

  @override
  void initState() {
    super.initState();
    _comments = widget.initialCommentsEnabled;
    _sharing = widget.initialSharingEnabled;
    _caption = SocialMentionComposerController(text: widget.initialCaption);
    _caption.textController.addListener(_captionChanged);
    widget.controller.addListener(_changed);
  }

  void _captionChanged() {
    widget.onCaptionChanged?.call(_caption.plainText);
    setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _caption.textController.removeListener(_captionChanged);
    _caption.dispose();
    super.dispose();
  }

  bool get _editable => const {
    ReelComposerStage.draft,
    ReelComposerStage.failed,
    ReelComposerStage.cancelled,
  }.contains(widget.controller.stage);

  Future<void> _publish() async {
    if (!_editable || _caption.plainText.trim().length > 1200) return;
    FocusScope.of(context).unfocus();
    await widget.controller.publish(
      video: widget.video,
      caption: _caption.plainText.trim(),
      audience: 'public',
      commentsEnabled: _comments,
      sharingEnabled: _sharing,
      reelStyle: widget.reelStyle,
      prepareVideo: widget.prepareVideo,
    );
  }

  Future<void> _cancel() async {
    if (!widget.controller.canCancel) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(context.lt(ar: 'إلغاء الرفع؟', en: 'Cancel upload?')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(context.lt(ar: 'متابعة الرفع', en: 'Keep uploading')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(context.lt(ar: 'إلغاء الرفع', en: 'Cancel upload')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) widget.controller.cancelUpload();
  }

  @override
  Widget build(BuildContext context) {
    final stage = widget.controller.stage;
    final published = stage == ReelComposerStage.published;
    final theme = SocialDesignTheme.of(context);
    return Theme(
      data: theme,
      child: PopScope(
        canPop: _editable || published,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_cancel());
        },
        child: Scaffold(
          appBar: AppBar(
            title: Text(context.lt(ar: 'نشر الريل', en: 'Publish reel')),
          ),
          bottomNavigationBar: _editable
              ? SafeArea(
                  minimum: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _caption.plainText.trim().length > 1200
                        ? null
                        : _publish,
                    icon: Icon(
                      stage == ReelComposerStage.failed
                          ? Icons.refresh
                          : Icons.publish_outlined,
                    ),
                    label: Text(
                      stage == ReelComposerStage.failed
                          ? context.lt(ar: 'إعادة المحاولة', en: 'Retry')
                          : context.lt(ar: 'نشر الآن', en: 'Publish now'),
                    ),
                  ),
                )
              : null,
          body: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (published) ...[
                      const SizedBox(height: 32),
                      const Icon(
                        Icons.check_circle_outline,
                        size: 64,
                        color: SocialDesignTheme.indigo,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        context.lt(
                          ar: 'تم نشر الريل',
                          en: 'Your reel is published',
                        ),
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 24),
                      FilledButton.icon(
                        onPressed: () => Navigator.pop(
                          context,
                          widget.controller.publishedReelId,
                        ),
                        icon: const Icon(Icons.check),
                        label: Text(context.lt(ar: 'تم', en: 'Done')),
                      ),
                    ] else ...[
                      Center(
                        child: SizedBox(
                          width: 100,
                          height: 178,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: IgnorePointer(child: widget.preview),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      SocialMentionComposerField(
                        controller: _caption,
                        hintText: context.lt(
                          ar: 'اكتب وصفاً جذاباً...',
                          en: 'Write a caption...',
                        ),
                        minLines: 3,
                        maxLines: 6,
                        maxLength: 1200,
                        enabled: _editable,
                      ),
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.public),
                        title: Text(context.lt(ar: 'الجمهور', en: 'Audience')),
                        trailing: Text(context.lt(ar: 'عام', en: 'Public')),
                      ),
                      const Divider(),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          context.lt(
                            ar: 'السماح بالتعليقات',
                            en: 'Allow comments',
                          ),
                        ),
                        value: _comments,
                        onChanged: _editable
                            ? (v) {
                                setState(() => _comments = v);
                                widget.onSettingsChanged?.call(
                                  _comments,
                                  _sharing,
                                );
                              }
                            : null,
                      ),
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          context.lt(
                            ar: 'السماح بالمشاركة',
                            en: 'Allow sharing',
                          ),
                        ),
                        value: _sharing,
                        onChanged: _editable
                            ? (v) {
                                setState(() => _sharing = v);
                                widget.onSettingsChanged?.call(
                                  _comments,
                                  _sharing,
                                );
                              }
                            : null,
                      ),
                      const SizedBox(height: 20),
                      ReelUploadProgress(controller: widget.controller),
                      const SizedBox(height: 16),
                      if (stage == ReelComposerStage.uploading)
                        OutlinedButton.icon(
                          onPressed: widget.controller.pauseUpload,
                          icon: const Icon(Icons.pause),
                          label: Text(
                            context.lt(ar: 'إيقاف مؤقت', en: 'Pause upload'),
                          ),
                        ),
                      if (stage == ReelComposerStage.paused)
                        FilledButton.icon(
                          onPressed: widget.controller.resumeUpload,
                          icon: const Icon(Icons.play_arrow),
                          label: Text(
                            context.lt(ar: 'استئناف', en: 'Resume upload'),
                          ),
                        ),
                      if (!_editable && widget.controller.canCancel)
                        TextButton.icon(
                          onPressed: _cancel,
                          icon: const Icon(Icons.close),
                          label: Text(
                            context.lt(ar: 'إلغاء الرفع', en: 'Cancel upload'),
                          ),
                        ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class ReelUploadProgress extends StatelessWidget {
  const ReelUploadProgress({super.key, required this.controller});
  final ReelComposerController controller;

  @override
  Widget build(BuildContext context) {
    final stage = controller.stage;
    if (stage == ReelComposerStage.draft) return const SizedBox.shrink();
    final label = switch (stage) {
      ReelComposerStage.preparing => context.lt(
        ar: 'جارٍ تجهيز الفيديو وتطبيق التعديلات...',
        en: 'Preparing video and applying edits...',
      ),
      ReelComposerStage.creatingSession => context.lt(
        ar: 'جارٍ تجهيز الرفع...',
        en: 'Preparing upload...',
      ),
      ReelComposerStage.uploading => context.lt(
        ar: 'جارٍ رفع الفيديو',
        en: 'Uploading video',
      ),
      ReelComposerStage.paused => context.lt(
        ar: 'الرفع متوقف مؤقتاً',
        en: 'Upload paused',
      ),
      ReelComposerStage.processing => context.lt(
        ar: 'جارٍ معالجة الفيديو...',
        en: 'Processing video...',
      ),
      ReelComposerStage.publishing => context.lt(
        ar: 'جارٍ نشر الريل...',
        en: 'Publishing reel...',
      ),
      ReelComposerStage.failed => context.lt(
        ar: controller.error ?? reelServerFailureMessage,
        en: 'Could not publish your reel. Check your connection and retry.',
      ),
      ReelComposerStage.cancelled => context.lt(
        ar: 'تم إلغاء الرفع',
        en: 'Upload cancelled',
      ),
      ReelComposerStage.published => context.lt(
        ar: 'تم النشر',
        en: 'Published',
      ),
      ReelComposerStage.draft => '',
    };
    final transferring =
        stage == ReelComposerStage.preparing ||
        stage == ReelComposerStage.uploading ||
        stage == ReelComposerStage.paused;
    final busy = const {
      ReelComposerStage.creatingSession,
      ReelComposerStage.processing,
      ReelComposerStage.publishing,
    }.contains(stage);
    return Semantics(
      liveRegion: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            style: TextStyle(
              color: stage == ReelComposerStage.failed
                  ? Theme.of(context).colorScheme.error
                  : SocialDesignTheme.ink,
            ),
          ),
          if (busy || transferring) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: transferring ? controller.progress : null,
            ),
          ],
          if (transferring) ...[
            const SizedBox(height: 8),
            Text(
              '${(controller.progress * 100).round()}%',
              textAlign: TextAlign.end,
            ),
          ],
        ],
      ),
    );
  }
}
