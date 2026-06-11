import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/appbar_quick_actions.dart';
import '../data/social_api.dart';
import '../state/social_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialReportedPostsScreen extends ConsumerStatefulWidget {
  const SocialReportedPostsScreen({super.key});

  @override
  ConsumerState<SocialReportedPostsScreen> createState() =>
      _SocialReportedPostsScreenState();
}

class _SocialReportedPostsScreenState
    extends ConsumerState<SocialReportedPostsScreen> {
  bool _loading = true;
  bool _busy = false;
  String? _error;
  List<_ReportedPostItem> _postItems = const <_ReportedPostItem>[];
  List<_ReportedStoryItem> _storyItems = const <_ReportedStoryItem>[];

  SocialApi get _api => ref.read(socialApiProvider);

  @override
  void initState() {
    super.initState();
    Future<void>.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await Future.wait([
        _api.listMyReportedPosts(limit: 50),
        _api.listMyReportedStories(limit: 50),
      ]);
      final postsRaw = List<dynamic>.from(
        results[0]['posts'] as List? ?? const [],
      );
      final storiesRaw = List<dynamic>.from(
        results[1]['stories'] as List? ?? const [],
      );
      final nextPosts = postsRaw
          .map((e) => _ReportedPostItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      final nextStories = storiesRaw
          .map((e) => _ReportedStoryItem.fromJson(Map<String, dynamic>.from(e)))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _postItems = nextPosts;
        _storyItems = nextStories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialReportedContentLoadFailed,
        );
      });
    }
  }

  Future<_ResubmitDraft?> _openResubmitSheet({
    required String title,
    required String initialCaption,
    required bool hasExistingMedia,
  }) {
    final controller = TextEditingController(text: initialCaption);
    LocalMediaFile? pickedMedia;
    var clearExistingMedia = false;

    return showModalBottomSheet<_ResubmitDraft>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final l10n = sheetContext.l10n;
            final selectedIsVideo = (pickedMedia?.mimeType ?? '')
                .toLowerCase()
                .startsWith('video/');
            return Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                10,
                14,
                14 + MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: controller,
                      minLines: 4,
                      maxLines: 8,
                      decoration: InputDecoration(
                        hintText: l10n.socialReportedWriteRevisedText,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 10),
                    if (pickedMedia != null)
                      _SelectedMediaBanner(
                        isVideo: selectedIsVideo,
                        label: l10n.socialReportedNewMediaLabel(
                          pickedMedia!.name,
                        ),
                      )
                    else if (hasExistingMedia && !clearExistingMedia)
                      _InfoBanner(text: l10n.socialReportedCurrentMediaExists)
                    else if (clearExistingMedia)
                      _WarningBanner(
                        text: l10n.socialReportedCurrentMediaWillBeRemoved,
                      ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () async {
                            final selected = await pickPostMediaFromDevice();
                            if (!mounted || selected == null) return;
                            setSheetState(() {
                              pickedMedia = selected;
                              clearExistingMedia = false;
                            });
                          },
                          icon: const Icon(Icons.attach_file_rounded),
                          label: Text(l10n.socialReportedChangeImageOrVideo),
                        ),
                        if (hasExistingMedia || pickedMedia != null)
                          TextButton.icon(
                            onPressed: () {
                              setSheetState(() {
                                pickedMedia = null;
                                clearExistingMedia = true;
                              });
                            },
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(l10n.socialReportedRemoveMedia),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    FilledButton.icon(
                      onPressed: () {
                        Navigator.of(sheetContext).pop(
                          _ResubmitDraft(
                            caption: controller.text.trim(),
                            mediaFile: pickedMedia,
                            clearExistingMedia: clearExistingMedia,
                          ),
                        );
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: Text(l10n.socialReportedSubmitEdit),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).whenComplete(controller.dispose);
  }

  Future<void> _editAndResubmitPost(_ReportedPostItem item) async {
    final l10n = context.l10n;
    final draft = await _openResubmitSheet(
      title: l10n.socialReportedEditPostTitle,
      initialCaption: item.caption,
      hasExistingMedia: item.hasMedia,
    );
    if (draft == null) return;

    final willHaveMedia =
        draft.mediaFile != null || (item.hasMedia && !draft.clearExistingMedia);
    if (draft.caption.isEmpty && !willHaveMedia) {
      _showSnack(l10n.socialReportedCannotSubmitEmptyPost);
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.resubmitModeratedPost(
        postId: item.id,
        caption: draft.caption,
        mediaFile: draft.mediaFile,
        clearMedia: draft.clearExistingMedia,
      );
      if (!mounted) return;
      _showSnack(l10n.socialReportedPostSubmitted);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack(mapAnyError(e, fallback: l10n.socialReportedPostSubmitFailed));
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _editAndResubmitStory(_ReportedStoryItem item) async {
    final l10n = context.l10n;
    final draft = await _openResubmitSheet(
      title: l10n.socialReportedEditStoryTitle,
      initialCaption: item.caption,
      hasExistingMedia: item.hasMedia,
    );
    if (draft == null) return;

    final willHaveMedia =
        draft.mediaFile != null || (item.hasMedia && !draft.clearExistingMedia);
    if (draft.caption.isEmpty && !willHaveMedia) {
      _showSnack(l10n.socialReportedCannotSubmitEmptyStory);
      return;
    }

    if (_busy) return;
    setState(() => _busy = true);
    try {
      await _api.resubmitModeratedStory(
        storyId: item.id,
        caption: draft.caption,
        mediaFile: draft.mediaFile,
        clearMedia: draft.clearExistingMedia,
      );
      if (!mounted) return;
      _showSnack(l10n.socialReportedStorySubmitted);
      await _load();
    } catch (e) {
      if (!mounted) return;
      _showSnack(
        mapAnyError(e, fallback: l10n.socialReportedStorySubmitFailed),
      );
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  void _showSnack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.socialReportedContentTitle),
          bottom: TabBar(
            tabs: [
              Tab(text: l10n.socialReportedPostsTab(_postItems.length)),
              Tab(text: l10n.socialReportedStoriesTab(_storyItems.length)),
            ],
          ),
          actions: const [AppBarQuickActions()],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorState(message: _error!, onRetry: _load)
            : TabBarView(children: [_buildPostsTab(), _buildStoriesTab()]),
      ),
    );
  }

  Widget _buildPostsTab() {
    if (_postItems.isEmpty) {
      return _EmptyState(
        title: context.l10n.socialReportedNoPostsTitle,
        subtitle: context.l10n.socialReportedNoPostsSubtitle,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: _postItems.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _postItems[index];
          return _ReportedPostCard(
            item: item,
            busy: _busy,
            onEdit: _busy ? null : () => _editAndResubmitPost(item),
          );
        },
      ),
    );
  }

  Widget _buildStoriesTab() {
    if (_storyItems.isEmpty) {
      return _EmptyState(
        title: context.l10n.socialReportedNoStoriesTitle,
        subtitle: context.l10n.socialReportedNoStoriesSubtitle,
      );
    }
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
        itemCount: _storyItems.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final item = _storyItems[index];
          return _ReportedStoryCard(
            item: item,
            busy: _busy,
            onEdit: _busy ? null : () => _editAndResubmitStory(item),
          );
        },
      ),
    );
  }
}

class _ResubmitDraft {
  final String caption;
  final LocalMediaFile? mediaFile;
  final bool clearExistingMedia;

  const _ResubmitDraft({
    required this.caption,
    required this.mediaFile,
    required this.clearExistingMedia,
  });
}

class _ReportedPostItem {
  final int id;
  final String caption;
  final String? mediaUrl;
  final String? mediaKind;
  final String moderationStatus;
  final String? moderationNote;
  final DateTime? moderationRequestedAt;
  final DateTime? createdAt;

  const _ReportedPostItem({
    required this.id,
    required this.caption,
    required this.mediaUrl,
    required this.mediaKind,
    required this.moderationStatus,
    required this.moderationNote,
    required this.moderationRequestedAt,
    required this.createdAt,
  });

  bool get hasMedia => (mediaUrl ?? '').trim().isNotEmpty;

  factory _ReportedPostItem.fromJson(Map<String, dynamic> json) {
    return _ReportedPostItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      caption: '${json['caption'] ?? ''}',
      mediaUrl: (json['mediaUrl'] ?? json['media_url'])?.toString(),
      mediaKind: (json['mediaKind'] ?? json['media_kind'])?.toString(),
      moderationStatus:
          (json['moderationStatus'] ?? json['moderation_status'] ?? 'pending')
              .toString(),
      moderationNote: (json['moderationNote'] ?? json['moderation_note'])
          ?.toString(),
      moderationRequestedAt: _parseDate(
        json['moderationRequestedAt'] ?? json['moderation_requested_at'],
      ),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
    );
  }
}

class _ReportedStoryItem {
  final int id;
  final String caption;
  final String? mediaUrl;
  final String? mediaKind;
  final String moderationStatus;
  final String? moderationNote;
  final DateTime? moderationRequestedAt;
  final DateTime? createdAt;

  const _ReportedStoryItem({
    required this.id,
    required this.caption,
    required this.mediaUrl,
    required this.mediaKind,
    required this.moderationStatus,
    required this.moderationNote,
    required this.moderationRequestedAt,
    required this.createdAt,
  });

  bool get hasMedia => (mediaUrl ?? '').trim().isNotEmpty;

  factory _ReportedStoryItem.fromJson(Map<String, dynamic> json) {
    return _ReportedStoryItem(
      id: int.tryParse('${json['id'] ?? 0}') ?? 0,
      caption: '${json['caption'] ?? ''}',
      mediaUrl: (json['mediaUrl'] ?? json['media_url'])?.toString(),
      mediaKind: (json['mediaKind'] ?? json['media_kind'])?.toString(),
      moderationStatus:
          (json['moderationStatus'] ?? json['moderation_status'] ?? 'pending')
              .toString(),
      moderationNote: (json['moderationNote'] ?? json['moderation_note'])
          ?.toString(),
      moderationRequestedAt: _parseDate(
        json['moderationRequestedAt'] ?? json['moderation_requested_at'],
      ),
      createdAt: _parseDate(json['createdAt'] ?? json['created_at']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  return DateTime.tryParse('$value');
}

class _ReportedPostCard extends StatelessWidget {
  final _ReportedPostItem item;
  final VoidCallback? onEdit;
  final bool busy;

  const _ReportedPostCard({
    required this.item,
    required this.onEdit,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return _ModerationCard(
      typeLabel: context.l10n.socialReportedPostType,
      caption: item.caption,
      mediaUrl: item.mediaUrl,
      mediaKind: item.mediaKind,
      moderationStatus: item.moderationStatus,
      moderationNote: item.moderationNote,
      date: item.moderationRequestedAt ?? item.createdAt,
      onEdit: onEdit,
      busy: busy,
    );
  }
}

class _ReportedStoryCard extends StatelessWidget {
  final _ReportedStoryItem item;
  final VoidCallback? onEdit;
  final bool busy;

  const _ReportedStoryCard({
    required this.item,
    required this.onEdit,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    return _ModerationCard(
      typeLabel: context.l10n.socialReportedStoryType,
      caption: item.caption,
      mediaUrl: item.mediaUrl,
      mediaKind: item.mediaKind,
      moderationStatus: item.moderationStatus,
      moderationNote: item.moderationNote,
      date: item.moderationRequestedAt ?? item.createdAt,
      onEdit: onEdit,
      busy: busy,
    );
  }
}

class _ModerationCard extends StatelessWidget {
  final String typeLabel;
  final String caption;
  final String? mediaUrl;
  final String? mediaKind;
  final String moderationStatus;
  final String? moderationNote;
  final DateTime? date;
  final VoidCallback? onEdit;
  final bool busy;

  const _ModerationCard({
    required this.typeLabel,
    required this.caption,
    required this.mediaUrl,
    required this.mediaKind,
    required this.moderationStatus,
    required this.moderationNote,
    required this.date,
    required this.onEdit,
    required this.busy,
  });

  @override
  Widget build(BuildContext context) {
    final mediaUrlValue = (mediaUrl ?? '').trim();
    final mediaKindValue = (mediaKind ?? '').trim().toLowerCase();
    final isVideoMedia =
        mediaKindValue == 'video' ||
        RegExp(
          r'\.(mp4|mov|webm|mkv|3gp)(\?|$)',
          caseSensitive: false,
        ).hasMatch(mediaUrlValue);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              children: [
                Expanded(
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _TypeChip(label: typeLabel),
                      Text(
                        '${context.l10n.commonStatus}: ${_statusLabel(context, moderationStatus)}',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                ),
                Text(
                  _formatDate(context, date),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if ((moderationNote ?? '').trim().isNotEmpty)
              _WarningBanner(text: moderationNote!.trim()),
            if ((moderationNote ?? '').trim().isNotEmpty)
              const SizedBox(height: 8),
            if (caption.trim().isNotEmpty)
              Text(caption.trim(), style: const TextStyle(height: 1.35)),
            if (mediaUrlValue.isNotEmpty) ...[
              const SizedBox(height: 10),
              _ContentMediaPreview(
                mediaUrl: mediaUrlValue,
                isVideoMedia: isVideoMedia,
              ),
            ],
            const SizedBox(height: 10),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: FilledButton.icon(
                onPressed: onEdit,
                icon: busy
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.edit_note_rounded),
                label: Text(context.l10n.socialReportedEditAndResubmit),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

String _statusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  switch (status.trim().toLowerCase()) {
    case 'pending':
      return l10n.socialReportedStatusPendingReview;
    case 'approved':
      return l10n.socialReportedStatusApproved;
    case 'rejected':
      return l10n.socialReportedStatusRejected;
    default:
      return status;
  }
}

String _formatDate(BuildContext context, DateTime? value) {
  if (value == null) return '-';
  final locale = Localizations.localeOf(context).toLanguageTag();
  return intl.DateFormat.yMd(locale).format(value.toLocal());
}

class _TypeChip extends StatelessWidget {
  final String label;

  const _TypeChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.28),
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _SelectedMediaBanner extends StatelessWidget {
  final bool isVideo;
  final String label;

  const _SelectedMediaBanner({required this.isVideo, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        children: [
          Icon(isVideo ? Icons.videocam_rounded : Icons.image_rounded),
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

class _InfoBanner extends StatelessWidget {
  final String text;

  const _InfoBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.4),
        ),
      ),
      child: Text(text),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  final String text;

  const _WarningBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.amber.withValues(alpha: 0.12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.w700)),
    );
  }
}

class _ContentMediaPreview extends StatelessWidget {
  final String mediaUrl;
  final bool isVideoMedia;

  const _ContentMediaPreview({
    required this.mediaUrl,
    required this.isVideoMedia,
  });

  @override
  Widget build(BuildContext context) {
    if (isVideoMedia) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          color: Colors.black12,
        ),
        child: Row(
          children: [
            const Icon(Icons.videocam_rounded),
            const SizedBox(width: 8),
            Expanded(child: Text(context.l10n.socialReportedVideoAttached)),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: CachedAppImage(
        imageUrl: mediaUrl,
        width: double.infinity,
        height: 180,
        fit: BoxFit.cover,
        errorWidget: (context, error, stackTrace) => Container(
          height: 100,
          alignment: Alignment.center,
          color: Colors.black12,
          child: Text(context.l10n.socialReportedMediaLoadFailed),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;

  const _ErrorState({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline_rounded, size: 38),
            const SizedBox(height: 8),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.l10n.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String subtitle;

  const _EmptyState({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.check_circle_outline_rounded, size: 44),
            const SizedBox(height: 8),
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w800),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 6),
            Text(subtitle, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
