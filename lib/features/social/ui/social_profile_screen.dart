import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:video_player/video_player.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/network/api_error_mapper.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_call_screen.dart';
import 'social_chat_thread_screen.dart';
import 'social_relation_requests_screen.dart';
import 'social_story_quick_viewer.dart';

class SocialProfileScreen extends ConsumerStatefulWidget {
  final int userId;
  final String? initialName;

  const SocialProfileScreen({
    super.key,
    required this.userId,
    this.initialName,
  });

  @override
  ConsumerState<SocialProfileScreen> createState() =>
      _SocialProfileScreenState();
}

class _SocialProfileScreenState extends ConsumerState<SocialProfileScreen> {
  late final SocialApi _api;

  final Map<String, List<SocialPost>> _postsByKey = <String, List<SocialPost>>{
    _allPostsKey: <SocialPost>[],
  };
  final Map<String, int?> _nextCursorByKey = <String, int?>{};
  final Map<String, bool> _loadingByKey = <String, bool>{};

  SocialUserProfile? _profile;
  List<SocialStoryHighlight> _highlights = <SocialStoryHighlight>[];

  bool _loadingProfile = false;
  bool _loadingHighlights = false;
  bool _postsPrivateForViewer = false;
  bool _storiesPrivateForViewer = false;
  String? _selectedKind;
  String? _error;
  bool _relationBusy = false;

  final intl.DateFormat _dateFmt = intl.DateFormat('yyyy/MM/dd', 'ar');

  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    await Future.wait([
      _loadProfile(),
      _loadHighlights(),
      _loadPosts(kind: null, refresh: true),
    ]);
  }

  String _keyOfKind(String? kind) => kind ?? _allPostsKey;

  List<SocialPost> _postsForKind(String? kind) {
    final key = _keyOfKind(kind);
    return _postsByKey[key] ?? const <SocialPost>[];
  }

  int? _nextCursorForKind(String? kind) => _nextCursorByKey[_keyOfKind(kind)];

  bool _isLoadingKind(String? kind) => _loadingByKey[_keyOfKind(kind)] == true;

  Future<void> _loadProfile() async {
    setState(() {
      _loadingProfile = true;
      _error = null;
    });
    try {
      final out = await _api.getUserProfile(widget.userId);
      final raw = out['profile'];
      if (!mounted) return;
      if (raw is Map) {
        setState(() {
          _profile = SocialUserProfile.fromJson(Map<String, dynamic>.from(raw));
          _loadingProfile = false;
        });
      } else {
        setState(() {
          _loadingProfile = false;
          _error = 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingProfile = false;
        _error = mapAnyError(
          e,
          fallback: 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ.',
        );
      });
    }
  }

  Future<void> _loadHighlights() async {
    setState(() {
      _loadingHighlights = true;
      _error = null;
    });
    try {
      final out = await _api.listUserHighlights(widget.userId);
      final storiesPrivate = _parseBool(
        out['storiesPrivate'] ?? out['stories_private'],
      );
      final raw = List<dynamic>.from(out['highlights'] as List? ?? const []);
      final next = raw
          .map(
            (e) => SocialStoryHighlight.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _storiesPrivateForViewer = storiesPrivate;
        _highlights = storiesPrivate ? const <SocialStoryHighlight>[] : next;
        _loadingHighlights = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingHighlights = false;
        _error = mapAnyError(
          e,
          fallback: 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„Ù‡Ø§ÙŠÙ„Ø§ÙŠØª.',
        );
      });
    }
  }

  Future<void> _loadPosts({required String? kind, bool refresh = false}) async {
    final key = _keyOfKind(kind);
    if (_isLoadingKind(kind)) return;

    final beforeId = refresh ? null : _nextCursorByKey[key];
    if (!refresh && beforeId == null) return;

    setState(() {
      _loadingByKey[key] = true;
      _error = null;
    });

    try {
      final out = await _api.listUserPosts(
        userId: widget.userId,
        kind: kind,
        limit: 24,
        beforeId: beforeId,
      );
      final postsPrivate = _parseBool(
        out['postsPrivate'] ?? out['posts_private'],
      );
      final raw = List<dynamic>.from(out['posts'] as List? ?? const []);
      final fetched = raw
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      if (!mounted) return;

      final previous = refresh
          ? const <SocialPost>[]
          : (_postsByKey[key] ?? const <SocialPost>[]);
      final mergedById = <int, SocialPost>{};
      for (final post in previous) {
        mergedById[post.id] = post;
      }
      for (final post in fetched) {
        mergedById[post.id] = post;
      }
      final merged = mergedById.values.toList(growable: false)
        ..sort((a, b) => b.id.compareTo(a.id));

      setState(() {
        _postsPrivateForViewer = postsPrivate;
        _postsByKey[key] = merged;
        _nextCursorByKey[key] = _parseInt(out['nextCursor']);
        _loadingByKey[key] = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingByKey[key] = false;
        _error = mapAnyError(
          e,
          fallback: 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù….',
        );
      });
    }
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadProfile(),
      _loadHighlights(),
      _loadPosts(kind: null, refresh: true),
      if (_selectedKind != null) _loadPosts(kind: _selectedKind, refresh: true),
    ]);
  }

  Future<void> _onSelectFilter(String? kind) async {
    final nextKind = _selectedKind == kind ? null : kind;
    setState(() {
      _selectedKind = nextKind;
    });
    if (!_postsByKey.containsKey(_keyOfKind(nextKind))) {
      await _loadPosts(kind: nextKind, refresh: true);
    }
  }

  SocialUserProfile _copyProfileWithRelation(
    SocialUserProfile profile,
    SocialRelation relation,
  ) {
    return SocialUserProfile(
      id: profile.id,
      fullName: profile.fullName,
      role: profile.role,
      bio: profile.bio,
      age: profile.age,
      imageUrl: profile.imageUrl,
      phone: profile.phone,
      showPhone: profile.showPhone,
      postsPublic: profile.postsPublic,
      storiesPublic: profile.storiesPublic,
      joinedAt: profile.joinedAt,
      isMe: profile.isMe,
      relation: relation,
      stats: profile.stats,
    );
  }

  Future<void> _runRelationAction(
    Future<Map<String, dynamic>> Function() action, {
    required String successMessage,
  }) async {
    final profile = _profile;
    if (profile == null || profile.isMe || _relationBusy) return;

    setState(() {
      _relationBusy = true;
      _error = null;
    });

    try {
      final out = await action();
      final rawRelation = out['relation'];
      if (!mounted) return;
      if (rawRelation is Map && _profile != null) {
        final relation = SocialRelation.fromJson(
          Map<String, dynamic>.from(rawRelation),
        );
        setState(() {
          _profile = _copyProfileWithRelation(_profile!, relation);
        });
      }
      await _loadProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: 'ØªØ¹Ø°Ø± ØªÙ†ÙÙŠØ° Ø§Ù„Ø¥Ø¬Ø±Ø§Ø¡ Ø­Ø§Ù„ÙŠØ§Ù‹.',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _relationBusy = false);
      }
    }
  }

  Future<void> _sendRelationRequest() async {
    await _runRelationAction(
      () => _api.sendRelationRequest(widget.userId),
      successMessage: 'ØªÙ… Ø¥Ø±Ø³Ø§Ù„ Ø·Ù„Ø¨ Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø©',
    );
  }

  Future<void> _acceptRelationRequest() async {
    await _runRelationAction(
      () => _api.acceptRelationRequest(widget.userId),
      successMessage: 'ØªÙ… Ù‚Ø¨ÙˆÙ„ Ø·Ù„Ø¨ Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø©',
    );
    await ref.read(socialControllerProvider.notifier).loadThreads();
  }

  Future<void> _rejectRelationRequest() async {
    await _runRelationAction(
      () => _api.rejectRelationRequest(widget.userId),
      successMessage: 'ØªÙ… Ø±ÙØ¶ Ø·Ù„Ø¨ Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø©',
    );
  }

  Future<void> _cancelRelationRequest() async {
    await _runRelationAction(
      () => _api.cancelRelationRequest(widget.userId),
      successMessage: 'ØªÙ… Ø¥Ù„ØºØ§Ø¡ Ø§Ù„Ø·Ù„Ø¨',
    );
  }

  Future<void> _removeRelation() async {
    await _runRelationAction(
      () => _api.removeRelation(widget.userId),
      successMessage: 'ØªÙ… Ø¥Ù„ØºØ§Ø¡ Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø©',
    );
  }

  Future<void> _blockRelation() async {
    await _runRelationAction(
      () => _api.blockRelation(widget.userId),
      successMessage: 'ØªÙ… Ø­Ø¸Ø± Ù‡Ø°Ø§ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù…',
    );
  }

  Future<void> _unblockRelation() async {
    await _runRelationAction(
      () => _api.unblockRelation(widget.userId),
      successMessage: 'ØªÙ… ÙÙƒ Ø§Ù„Ø­Ø¸Ø±',
    );
  }

  Future<void> _openChatWithUser() async {
    final profile = _profile;
    if (profile == null || profile.isMe) return;

    final thread = await ref
        .read(socialControllerProvider.notifier)
        .createThreadWithUser(profile.id);
    if (thread == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: thread.id,
          peerName: thread.peer.fullName,
          peerPhone: thread.peerPhone,
          peerUserId: thread.peer.id,
          peerImageUrl: thread.peer.imageUrl,
        ),
      ),
    );
  }

  Future<void> _openInAppCall() async {
    final profile = _profile;
    if (profile == null || profile.isMe) return;

    final thread = await ref
        .read(socialControllerProvider.notifier)
        .createThreadWithUser(profile.id);
    if (thread == null || !mounted) return;

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialCallScreen(
          threadId: thread.id,
          isCaller: true,
          remoteDisplayName: profile.fullName,
        ),
      ),
    );
  }

  Future<void> _confirmRemoveRelation({
    required String title,
    required String content,
    required String confirmLabel,
  }) async {
    if (!mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
    if (approved == true) {
      await _removeRelation();
    }
  }

  Future<void> _onFollowPressed() async {
    final profile = _profile;
    if (profile == null || profile.isMe || _relationBusy) return;
    final relation = profile.relation;
    if (relation.isBlocked) return;

    if (relation.isAccepted) {
      await _confirmRemoveRelation(
        title: 'إلغاء المتابعة',
        content: 'سيتم إلغاء المتابعة وحالة الصداقة الحالية.',
        confirmLabel: 'إلغاء المتابعة',
      );
      return;
    }
    if (relation.isPendingOutgoing) {
      await _cancelRelationRequest();
      return;
    }
    if (relation.isPendingIncoming) {
      await _acceptRelationRequest();
      return;
    }
    await _sendRelationRequest();
  }

  Future<void> _onFriendPressed() async {
    final profile = _profile;
    if (profile == null || profile.isMe || _relationBusy) return;
    final relation = profile.relation;
    if (relation.isBlocked) return;

    if (relation.isAccepted) {
      await _confirmRemoveRelation(
        title: 'إلغاء الصداقة',
        content: 'سيتم إلغاء الصداقة والمتابعة بينكما.',
        confirmLabel: 'إلغاء الصداقة',
      );
      return;
    }
    if (relation.isPendingOutgoing) {
      await _cancelRelationRequest();
      return;
    }
    if (relation.isPendingIncoming) {
      await _acceptRelationRequest();
      return;
    }
    await _sendRelationRequest();
  }

  String _followButtonLabel(SocialRelation relation) {
    if (relation.isAccepted) return 'متابع';
    if (relation.isPendingOutgoing) return 'متابعة قيد الانتظار';
    if (relation.isPendingIncoming) return 'قبول المتابعة';
    return 'متابعة';
  }

  String _friendButtonLabel(SocialRelation relation) {
    if (relation.isAccepted) return 'صديق';
    if (relation.isPendingOutgoing) return 'طلب صداقة قيد الانتظار';
    if (relation.isPendingIncoming) return 'قبول الصداقة';
    return 'إضافة صديق';
  }

  Widget? _buildRelationActions(SocialUserProfile profile) {
    if (profile.isMe) return null;
    final relation = profile.relation;

    if (relation.isBlockedByMe) {
      return FilledButton.tonalIcon(
        onPressed: _relationBusy ? null : _unblockRelation,
        icon: const Icon(Icons.lock_open_rounded),
        label: const Text('فك الحظر'),
      );
    }

    if (relation.isBlockedByOther) {
      return const Text(
        'لا يمكن التفاعل مع هذا الحساب حالياً بسبب الحظر.',
        style: TextStyle(fontWeight: FontWeight.w700),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _relationBusy ? null : _onFollowPressed,
                icon: Icon(
                  relation.isAccepted
                      ? Icons.check_circle_rounded
                      : Icons.person_add_alt_1_rounded,
                ),
                label: Text(_followButtonLabel(relation)),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _relationBusy ? null : _onFriendPressed,
                icon: Icon(
                  relation.isAccepted
                      ? Icons.verified_rounded
                      : Icons.group_add_rounded,
                ),
                label: Text(_friendButtonLabel(relation)),
              ),
            ),
          ],
        ),
        if (relation.isPendingIncoming) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              OutlinedButton(
                onPressed: _relationBusy ? null : _rejectRelationRequest,
                child: const Text('رفض الطلب'),
              ),
              FilledButton(
                onPressed: _relationBusy ? null : _acceptRelationRequest,
                child: const Text('قبول الطلب'),
              ),
            ],
          ),
        ],
        if (relation.isAccepted) ...[
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: _openChatWithUser,
                icon: const Icon(Icons.chat_bubble_outline_rounded),
                label: const Text('مراسلة'),
              ),
              FilledButton.tonalIcon(
                onPressed: _openInAppCall,
                icon: const Icon(Icons.call_outlined),
                label: const Text('اتصال'),
              ),
            ],
          ),
        ],
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            onPressed: _relationBusy ? null : _blockRelation,
            icon: const Icon(Icons.block_rounded),
            label: const Text('حظر'),
          ),
        ),
      ],
    );
  }

  String _relationStatusText(SocialRelation relation) {
    if (relation.isBlockedByMe) return 'هذا الحساب محظور من طرفك';
    if (relation.isBlockedByOther) return 'هذا الحساب قام بحظرك';
    if (relation.isAccepted) return 'صديقك ومتابع لك';
    if (relation.isPendingIncoming) return 'أرسل لك طلب صداقة/متابعة';
    if (relation.isPendingOutgoing) return 'طلب الصداقة بانتظار الرد';
    return 'غير متابع';
  }

  Future<void> _openMediaViewer(SocialPost post) async {
    final mediaUrl = (post.mediaUrl ?? '').trim();
    if (mediaUrl.isEmpty) return;
    final isVideo = (post.mediaKind ?? post.postKind).toLowerCase() == 'video';
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileMediaViewerPage(
          mediaUrl: mediaUrl,
          isVideo: isVideo,
          title: post.author.fullName,
          subtitle: _formatDateTime(post.createdAt),
          caption: post.caption,
        ),
      ),
    );
  }

  Future<void> _openAvatarStoryOrImage() async {
    final profile = _profile;
    if (profile == null) return;

    var stories = ref.read(socialControllerProvider).stories;
    if (stories.isEmpty) {
      await ref
          .read(socialControllerProvider.notifier)
          .loadStories(silent: true);
      if (!mounted) return;
      stories = ref.read(socialControllerProvider).stories;
    }

    for (final group in stories) {
      if (group.userId == profile.id && group.stories.isNotEmpty) {
        await showSocialStoryQuickViewer(
          context: context,
          group: group,
          onStoryViewed: (storyId) => ref
              .read(socialControllerProvider.notifier)
              .markStoryViewed(storyId),
        );
        if (!mounted) return;
        return;
      }
    }

    final avatarUrl = (profile.imageUrl ?? '').trim();
    if (avatarUrl.isEmpty) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _ProfileMediaViewerPage(
          mediaUrl: avatarUrl,
          isVideo: false,
          title: profile.fullName,
          subtitle: 'Ø§Ù„ØµÙˆØ±Ø© Ø§Ù„Ø´Ø®ØµÙŠØ©',
          caption: profile.bio,
        ),
      ),
    );
  }

  List<_HighlightAlbum> _buildHighlightAlbums() {
    if (_highlights.isEmpty) return const <_HighlightAlbum>[];
    final grouped = <String, List<SocialStoryHighlight>>{};
    for (final item in _highlights) {
      final title = item.title.trim();
      final key = title.isEmpty ? '__single_${item.id}' : title;
      grouped.putIfAbsent(key, () => <SocialStoryHighlight>[]).add(item);
    }

    final albums =
        grouped.entries
            .map((entry) {
              final highlights = List<SocialStoryHighlight>.from(entry.value)
                ..sort((a, b) {
                  final aTime = a.createdAt?.millisecondsSinceEpoch ?? 0;
                  final bTime = b.createdAt?.millisecondsSinceEpoch ?? 0;
                  return bTime.compareTo(aTime);
                });
              final cover = highlights.first;
              return _HighlightAlbum(
                id: cover.id,
                title: cover.title.trim().isEmpty
                    ? 'Ù‡Ø§ÙŠÙ„Ø§ÙŠØª'
                    : cover.title.trim(),
                cover: cover,
                stories: highlights.map((h) => h.story).toList(growable: false),
              );
            })
            .toList(growable: false)
          ..sort((a, b) {
            final aTime = a.cover.createdAt?.millisecondsSinceEpoch ?? 0;
            final bTime = b.cover.createdAt?.millisecondsSinceEpoch ?? 0;
            return bTime.compareTo(aTime);
          });
    return albums;
  }

  Future<void> _openHighlightAlbum(_HighlightAlbum album) async {
    final profile = _profile;
    if (profile == null || album.stories.isEmpty) return;
    final group = SocialStoryGroup(
      userId: profile.id,
      author: SocialAuthor(
        id: profile.id,
        fullName: profile.fullName,
        imageUrl: profile.imageUrl,
        phone: profile.phone,
        role: profile.role,
      ),
      latestAt: album.cover.createdAt,
      hasUnviewed: false,
      stories: album.stories,
    );
    await showSocialStoryQuickViewer(
      context: context,
      group: group,
      onStoryViewed: (storyId) =>
          ref.read(socialControllerProvider.notifier).markStoryViewed(storyId),
    );
  }

  Future<void> _removeHighlight(_HighlightAlbum album) async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    try {
      await _api.removeStoryHighlight(album.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('ØªÙ… Ø­Ø°Ù Ø§Ù„Ù‡Ø§ÙŠÙ„Ø§ÙŠØª')),
      );
      await Future.wait([_loadHighlights(), _loadProfile()]);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: 'ØªØ¹Ø°Ø± Ø­Ø°Ù Ø§Ù„Ù‡Ø§ÙŠÙ„Ø§ÙŠØª.'),
          ),
        ),
      );
    }
  }

  Future<void> _openAddHighlightSheet() async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddHighlightSheet(api: _api),
    );
    if (result == true) {
      await Future.wait([_loadHighlights(), _loadProfile()]);
    }
  }

  Future<void> _openEditProfileSheet() async {
    final profile = _profile;
    if (profile == null || !profile.isMe) return;
    final next = await showModalBottomSheet<SocialUserProfile>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _EditProfileSheet(api: _api, initialProfile: profile),
    );
    if (next != null && mounted) {
      setState(() => _profile = next);
    }
  }

  String _formatDate(DateTime? dateTime) {
    if (dateTime == null) return '-';
    return _dateFmt.format(dateTime.toLocal());
  }

  String _formatDateTime(DateTime? dateTime) {
    if (dateTime == null) return '-';
    final d = dateTime.toLocal();
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    final h = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$y/$m/$day  $h:$min';
  }

  String _friendlyRole(String role) {
    switch (role.toLowerCase()) {
      case 'admin':
        return 'Ø£Ø¯Ù…Ù†';
      case 'super_admin':
        return 'Ø³ÙˆØ¨Ø± Ø£Ø¯Ù…Ù†';
      case 'deputy_admin':
        return 'Ù†Ø§Ø¦Ø¨ Ø£Ø¯Ù…Ù†';
      case 'owner':
        return 'ØµØ§Ø­Ø¨ Ù…ØªØ¬Ø±';
      case 'delivery':
        return 'Ø¯Ù„ÙØ±ÙŠ';
      case 'taxi_captain':
        return 'ÙƒØ§Ø¨ØªÙ† ØªÙƒØ³ÙŠ';
      default:
        return 'Ù…Ø³ØªØ®Ø¯Ù…';
    }
  }

  List<String> _favoriteMerchants() {
    final allPosts = _postsForKind(null);
    if (allPosts.isEmpty) return const <String>[];
    final counts = <String, int>{};
    for (final post in allPosts) {
      final name = (post.merchantName ?? '').trim();
      if (name.isEmpty) continue;
      counts[name] = (counts[name] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(6).map((e) => e.key).toList(growable: false);
  }

  bool _isMediaFilter(String? kind) => kind == 'image' || kind == 'video';

  @override
  Widget build(BuildContext context) {
    final profile = _profile;
    final currentPosts = _postsForKind(_selectedKind);
    final currentNextCursor = _nextCursorForKind(_selectedKind);
    final loadingCurrentKind = _isLoadingKind(_selectedKind);
    final favorites = _favoriteMerchants();
    final albums = _buildHighlightAlbums();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: const Color(0xFF0F2140),
        appBar: AppBar(
          title: Text(
            profile?.fullName ??
                widget.initialName ??
                'Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ',
          ),
          actions: [
            IconButton(
              tooltip: 'ØªØ­Ø¯ÙŠØ«',
              onPressed: _refreshAll,
              icon: const Icon(Icons.refresh_rounded),
            ),
            if (profile?.isMe == true)
              IconButton(
                tooltip: 'Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø©',
                onPressed: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const SocialRelationRequestsScreen(),
                    ),
                  );
                  if (!mounted) return;
                  await _loadProfile();
                },
                icon: const Icon(Icons.person_add_alt_1_rounded),
              ),
            if (profile?.isMe == true)
              IconButton(
                tooltip: 'ØªØ¹Ø¯ÙŠÙ„',
                onPressed: _openEditProfileSheet,
                icon: const Icon(Icons.edit_outlined),
              ),
          ],
        ),
        body: _loadingProfile && profile == null
            ? const Center(child: CircularProgressIndicator())
            : Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0xFF122A4F), Color(0xFF0A1832)],
                  ),
                ),
                child: RefreshIndicator(
                  onRefresh: _refreshAll,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                    children: [
                      if (_error != null) _ErrorBanner(message: _error!),
                      if (profile != null)
                        _ProfileHeaderCard(
                          profile: profile,
                          roleLabel: _friendlyRole(profile.role),
                          joinedAt: _formatDate(profile.joinedAt),
                          favorites: favorites,
                          onAvatarTap: _openAvatarStoryOrImage,
                          relationStatus: _relationStatusText(profile.relation),
                          relationActions: _buildRelationActions(profile),
                          onRequestsTap: profile.isMe
                              ? () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) =>
                                          const SocialRelationRequestsScreen(),
                                    ),
                                  );
                                  if (!mounted) return;
                                  await _loadProfile();
                                }
                              : null,
                          onEditTap: profile.isMe
                              ? _openEditProfileSheet
                              : null,
                        ),
                      const SizedBox(height: 12),
                      _HighlightsSection(
                        loading: _loadingHighlights,
                        albums: albums,
                        isPrivateForViewer: _storiesPrivateForViewer,
                        canManage: profile?.isMe == true,
                        onAdd: _openAddHighlightSheet,
                        onOpen: _openHighlightAlbum,
                        onRemove: _removeHighlight,
                      ),
                      const SizedBox(height: 12),
                      _FiltersSection(
                        selectedKind: _selectedKind,
                        onSelect: _onSelectFilter,
                      ),
                      const SizedBox(height: 10),
                      if (loadingCurrentKind && currentPosts.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 30),
                          child: Center(child: CircularProgressIndicator()),
                        )
                      else if (_postsPrivateForViewer)
                        _PrivatePostsNotice(
                          name:
                              profile?.fullName ??
                              widget.initialName ??
                              'Ø§Ù„Ø­Ø³Ø§Ø¨',
                        )
                      else if (currentPosts.isEmpty)
                        const _EmptyPostsNotice()
                      else if (_isMediaFilter(_selectedKind))
                        _ProfileMediaGrid(
                          posts: currentPosts,
                          onOpenMedia: _openMediaViewer,
                        )
                      else
                        ...currentPosts.map(
                          (post) => _ProfilePostCard(
                            post: post,
                            dateText: _formatDateTime(post.createdAt),
                            onOpenMedia: () => _openMediaViewer(post),
                          ),
                        ),
                      if (currentNextCursor != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: OutlinedButton.icon(
                            onPressed: loadingCurrentKind
                                ? null
                                : () => _loadPosts(
                                    kind: _selectedKind,
                                    refresh: false,
                                  ),
                            icon: loadingCurrentKind
                                ? const SizedBox(
                                    width: 14,
                                    height: 14,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.expand_more_rounded),
                            label: const Text('Ø¹Ø±Ø¶ Ø§Ù„Ù…Ø²ÙŠØ¯'),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;

  const _ErrorBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Theme.of(context).colorScheme.errorContainer,
      ),
      child: Text(
        message,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onErrorContainer,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _EmptyPostsNotice extends StatelessWidget {
  const _EmptyPostsNotice();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 30),
      child: Center(
        child: Text(
          'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø¶Ù…Ù† Ù‡Ø°Ø§ Ø§Ù„ÙÙ„ØªØ±.',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}

class _PrivatePostsNotice extends StatelessWidget {
  final String name;

  const _PrivatePostsNotice({required this.name});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 30),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline_rounded),
              const SizedBox(height: 8),
              Text(
                'Ù…Ù†Ø´ÙˆØ±Ø§Øª $name Ù…Ø®ÙÙŠØ© Ø§Ù„Ø¢Ù†.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileHeaderCard extends StatelessWidget {
  final SocialUserProfile profile;
  final String roleLabel;
  final String joinedAt;
  final List<String> favorites;
  final VoidCallback onAvatarTap;
  final String relationStatus;
  final Widget? relationActions;
  final VoidCallback? onRequestsTap;
  final VoidCallback? onEditTap;

  const _ProfileHeaderCard({
    required this.profile,
    required this.roleLabel,
    required this.joinedAt,
    required this.favorites,
    required this.onAvatarTap,
    required this.relationStatus,
    required this.relationActions,
    required this.onRequestsTap,
    required this.onEditTap,
  });

  @override
  Widget build(BuildContext context) {
    final stats = profile.stats;
    return Card(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Theme.of(
                context,
              ).colorScheme.primaryContainer.withValues(alpha: 0.42),
              Theme.of(
                context,
              ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          profile.fullName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$roleLabel • عضو منذ $joinedAt',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurface.withValues(alpha: 0.72),
                          ),
                        ),
                        if (profile.age != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              'العمر: ${profile.age} سنة',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                        if (profile.phone != null &&
                            profile.phone!.trim().isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              profile.phone!,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurface.withValues(alpha: 0.72),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: onAvatarTap,
                    child: CircleAvatar(
                      radius: 36,
                      backgroundImage:
                          (profile.imageUrl ?? '').trim().isNotEmpty
                          ? NetworkImage(profile.imageUrl!)
                          : null,
                      child: (profile.imageUrl ?? '').trim().isEmpty
                          ? const Icon(Icons.person_outline, size: 28)
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (!profile.isMe) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.7),
                  ),
                  child: Text(
                    relationStatus,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (relationActions != null) ...[
                  const SizedBox(height: 8),
                  relationActions!,
                ],
              ],
              if (profile.isMe && onRequestsTap != null) ...[
                Align(
                  alignment: Alignment.centerRight,
                  child: OutlinedButton.icon(
                    onPressed: onRequestsTap,
                    icon: const Icon(Icons.person_add_alt_1_rounded),
                    label: const Text('Ø·Ù„Ø¨Ø§Øª Ø§Ù„Ù…ØªØ§Ø¨Ø¹Ø©'),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _PrivacyPill(
                    icon: Icons.phone_enabled_outlined,
                    label: profile.showPhone
                        ? 'Ø§Ù„Ù‡Ø§ØªÙ Ø¸Ø§Ù‡Ø±'
                        : 'Ø§Ù„Ù‡Ø§ØªÙ Ù…Ø®ÙÙŠ',
                    active: profile.showPhone,
                  ),
                  _PrivacyPill(
                    icon: Icons.public_rounded,
                    label: profile.postsPublic
                        ? 'Ø§Ù„Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø¹Ø§Ù…Ø©'
                        : 'Ø§Ù„Ù…Ù†Ø´ÙˆØ±Ø§Øª Ø®Ø§ØµØ©',
                    active: profile.postsPublic,
                  ),
                  _PrivacyPill(
                    icon: Icons.auto_stories_rounded,
                    label: profile.storiesPublic
                        ? 'Ø§Ù„Ø³ØªÙˆØ±ÙŠØ§Øª Ø¹Ø§Ù…Ø©'
                        : 'Ø§Ù„Ø³ØªÙˆØ±ÙŠØ§Øª Ø®Ø§ØµØ©',
                    active: profile.storiesPublic,
                  ),
                ],
              ),
              if (profile.bio.trim().isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                  ),
                  child: Text(
                    profile.bio.trim(),
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _StatChip(
                    label: 'Ø£ØµØ¯Ù‚Ø§Ø¡',
                    value: stats.friendsCount.toString(),
                  ),
                  _StatChip(
                    label: 'Ù…ØªØ§Ø¨Ø¹ÙˆÙ†',
                    value: stats.followersCount.toString(),
                  ),
                  _StatChip(
                    label: 'ÙŠØªØ§Ø¨Ø¹',
                    value: stats.followingCount.toString(),
                  ),
                  _StatChip(
                    label: 'Ù…Ù†Ø´ÙˆØ±Ø§Øª',
                    value: stats.totalPosts.toString(),
                  ),
                  _StatChip(
                    label: 'ØµÙˆØ±',
                    value: stats.imagePosts.toString(),
                  ),
                  _StatChip(
                    label: 'Ø±ÙŠÙ„Ø²',
                    value: stats.videoPosts.toString(),
                  ),
                  _StatChip(
                    label: 'ØªÙ‚ÙŠÙŠÙ…Ø§Øª',
                    value: stats.reviewPosts.toString(),
                  ),
                  _StatChip(
                    label: 'Ø¥Ø¹Ø¬Ø§Ø¨Ø§Øª',
                    value: stats.likesReceived.toString(),
                  ),
                  _StatChip(
                    label: 'ØªØ¹Ù„ÙŠÙ‚Ø§Øª',
                    value: stats.commentsReceived.toString(),
                  ),
                  _StatChip(
                    label: 'Ø³ØªÙˆØ±ÙŠ Ù†Ø´Ø·Ø©',
                    value: stats.activeStories.toString(),
                  ),
                  if (stats.pendingIncomingCount > 0)
                    _StatChip(
                      label: 'Ø·Ù„Ø¨Ø§Øª ÙˆØ§Ø±Ø¯Ø©',
                      value: stats.pendingIncomingCount.toString(),
                    ),
                  if (stats.pendingOutgoingCount > 0)
                    _StatChip(
                      label: 'Ø·Ù„Ø¨Ø§Øª ØµØ§Ø¯Ø±Ø©',
                      value: stats.pendingOutgoingCount.toString(),
                    ),
                ],
              ),
              if (favorites.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  'Ø§Ù„Ù…ØªØ§Ø¬Ø± Ø§Ù„Ù…ÙØ¶Ù„Ø©',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: favorites
                      .map(
                        (name) => Chip(
                          label: Text(name, textDirection: TextDirection.rtl),
                        ),
                      )
                      .toList(growable: false),
                ),
              ],
              if (onEditTap != null) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: onEditTap,
                    icon: const Icon(Icons.edit_outlined),
                    label: const Text('ØªØ¹Ø¯ÙŠÙ„ Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;

  const _StatChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Text(
        '$label: $value',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _PrivacyPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;

  const _PrivacyPill({
    required this.icon,
    required this.label,
    required this.active,
  });

  @override
  Widget build(BuildContext context) {
    final bg = active
        ? Theme.of(context).colorScheme.secondaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final fg = active
        ? Theme.of(context).colorScheme.onSecondaryContainer
        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: bg,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

class _HighlightsSection extends StatelessWidget {
  final bool loading;
  final List<_HighlightAlbum> albums;
  final bool isPrivateForViewer;
  final bool canManage;
  final VoidCallback onAdd;
  final ValueChanged<_HighlightAlbum> onOpen;
  final ValueChanged<_HighlightAlbum> onRemove;

  const _HighlightsSection({
    required this.loading,
    required this.albums,
    required this.isPrivateForViewer,
    required this.canManage,
    required this.onAdd,
    required this.onOpen,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (canManage)
                  IconButton(
                    tooltip: 'ØªØ«Ø¨ÙŠØª Ø³ØªÙˆØ±ÙŠ',
                    onPressed: onAdd,
                    icon: const Icon(Icons.add_circle_outline_rounded),
                  ),
                const Spacer(),
                const Text(
                  'Ø§Ù„Ù‡Ø§ÙŠÙ„Ø§ÙŠØª',
                  style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                ),
              ],
            ),
            if (loading)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (isPrivateForViewer)
              Text(
                'Ø§Ù„Ø³ØªÙˆØ±ÙŠØ§Øª Ù…Ø®ÙÙŠØ© Ù…Ù† ØµØ§Ø­Ø¨ Ø§Ù„Ø­Ø³Ø§Ø¨.',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              )
            else if (albums.isEmpty)
              Text(
                canManage
                    ? 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù‡Ø§ÙŠÙ„Ø§ÙŠØª Ø¨Ø¹Ø¯. Ø«Ø¨Ù‘Øª Ø³ØªÙˆØ±ÙŠ Ù…Ù† Ø§Ù„Ø£Ø±Ø´ÙŠÙ.'
                    : 'Ù„Ø§ ØªÙˆØ¬Ø¯ Ù‡Ø§ÙŠÙ„Ø§ÙŠØª Ù„Ù‡Ø°Ø§ Ø§Ù„Ù…Ø³ØªØ®Ø¯Ù….',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              )
            else
              SizedBox(
                height: 94,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: albums.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(width: 10),
                  itemBuilder: (context, index) {
                    final album = albums[index];
                    final coverUrl = (album.cover.story.mediaUrl ?? '').trim();
                    return GestureDetector(
                      onTap: () => onOpen(album),
                      onLongPress: canManage ? () => onRemove(album) : null,
                      child: SizedBox(
                        width: 74,
                        child: Column(
                          children: [
                            Container(
                              width: 62,
                              height: 62,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary,
                                  width: 1.8,
                                ),
                                image:
                                    coverUrl.isNotEmpty &&
                                        album.cover.story.mediaKind == 'image'
                                    ? DecorationImage(
                                        image: NetworkImage(coverUrl),
                                        fit: BoxFit.cover,
                                      )
                                    : null,
                                gradient:
                                    coverUrl.isEmpty ||
                                        album.cover.story.mediaKind != 'image'
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF163A6B),
                                          Color(0xFF2D78B7),
                                        ],
                                      )
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child:
                                  (coverUrl.isEmpty ||
                                      album.cover.story.mediaKind != 'image')
                                  ? const Icon(
                                      Icons.auto_stories_rounded,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                            const SizedBox(height: 6),
                            Text(
                              album.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _FiltersSection extends StatelessWidget {
  final String? selectedKind;
  final ValueChanged<String?> onSelect;

  const _FiltersSection({required this.selectedKind, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _profileFilters
              .map(
                (filter) => FilterChip(
                  selected: selectedKind == filter.kind,
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(filter.label),
                      const SizedBox(width: 6),
                      Icon(filter.icon, size: 16),
                    ],
                  ),
                  onSelected: (_) => onSelect(filter.kind),
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _ProfileMediaGrid extends StatelessWidget {
  final List<SocialPost> posts;
  final ValueChanged<SocialPost> onOpenMedia;

  const _ProfileMediaGrid({required this.posts, required this.onOpenMedia});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
      ),
      itemBuilder: (context, index) {
        final post = posts[index];
        final isVideo = (post.mediaKind ?? post.postKind) == 'video';
        final mediaUrl = (post.mediaUrl ?? '').trim();

        return GestureDetector(
          onTap: () => onOpenMedia(post),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              image: mediaUrl.isNotEmpty && !isVideo
                  ? DecorationImage(
                      image: NetworkImage(mediaUrl),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: isVideo
                ? Stack(
                    children: [
                      if (mediaUrl.isNotEmpty)
                        Positioned.fill(
                          child: Image.network(
                            mediaUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      const Center(
                        child: Icon(
                          Icons.play_circle_fill_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                    ],
                  )
                : null,
          ),
        );
      },
    );
  }
}

class _ProfilePostCard extends StatelessWidget {
  final SocialPost post;
  final String dateText;
  final VoidCallback onOpenMedia;

  const _ProfilePostCard({
    required this.post,
    required this.dateText,
    required this.onOpenMedia,
  });

  @override
  Widget build(BuildContext context) {
    final mediaUrl = (post.mediaUrl ?? '').trim();
    final isVideo = (post.mediaKind ?? post.postKind) == 'video';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Text(
                  dateText,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
                const Spacer(),
                _KindPill(kind: post.postKind),
              ],
            ),
            if (mediaUrl.isNotEmpty) ...[
              const SizedBox(height: 10),
              GestureDetector(
                onTap: onOpenMedia,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        Image.network(
                          mediaUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) =>
                              Container(
                                color: const Color(0xFF15355F),
                                alignment: Alignment.center,
                                child: const Icon(Icons.broken_image_outlined),
                              ),
                        ),
                        if (isVideo)
                          const Center(
                            child: Icon(
                              Icons.play_circle_fill_rounded,
                              color: Colors.white,
                              size: 52,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
            if (post.caption.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                post.caption.trim(),
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  height: 1.35,
                ),
              ),
            ],
            if (post.postKind == 'merchant_review') ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Text(
                    post.reviewRating == null
                        ? '-'
                        : 'â­ ${post.reviewRating}/5',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const Spacer(),
                  Text(
                    post.merchantName?.trim().isEmpty ?? true
                        ? 'ØªÙ‚ÙŠÙŠÙ… Ù…ØªØ¬Ø±'
                        : post.merchantName!.trim(),
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Row(
              children: [
                _MetricBadge(
                  icon: Icons.comment_outlined,
                  label: post.commentsCount.toString(),
                ),
                const SizedBox(width: 8),
                _MetricBadge(
                  icon: post.isLiked ? Icons.favorite : Icons.favorite_border,
                  label: post.likesCount.toString(),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _KindPill extends StatelessWidget {
  final String kind;

  const _KindPill({required this.kind});

  @override
  Widget build(BuildContext context) {
    final String label;
    final IconData icon;
    switch (kind) {
      case 'image':
        label = 'ØµÙˆØ±';
        icon = Icons.image_outlined;
        break;
      case 'video':
        label = 'Ø±ÙŠÙ„Ø²';
        icon = Icons.ondemand_video_rounded;
        break;
      case 'merchant_review':
        label = 'ØªÙ‚ÙŠÙŠÙ…';
        icon = Icons.rate_review_outlined;
        break;
      default:
        label = 'Ù†Øµ';
        icon = Icons.text_fields_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primaryContainer,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              color: Theme.of(context).colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            icon,
            size: 14,
            color: Theme.of(context).colorScheme.onPrimaryContainer,
          ),
        ],
      ),
    );
  }
}

class _MetricBadge extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetricBadge({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
          const SizedBox(width: 4),
          Icon(icon, size: 15),
        ],
      ),
    );
  }
}

class _AddHighlightSheet extends StatefulWidget {
  final SocialApi api;

  const _AddHighlightSheet({required this.api});

  @override
  State<_AddHighlightSheet> createState() => _AddHighlightSheetState();
}

class _AddHighlightSheetState extends State<_AddHighlightSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  List<SocialStory> _stories = <SocialStory>[];
  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadArchive);
  }

  Future<void> _loadArchive() async {
    try {
      final out = await widget.api.listMyStoryArchive(limit: 80);
      final raw = List<dynamic>.from(out['stories'] as List? ?? const []);
      final stories = raw
          .map((e) => SocialStory.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _stories = stories;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø£Ø±Ø´ÙŠÙ Ø§Ù„Ø³ØªÙˆØ±ÙŠ.',
        );
      });
    }
  }

  Future<void> _pinStory(SocialStory story) async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      await widget.api.addStoryHighlight(
        story.id,
        title: _titleCtrl.text.trim().isEmpty ? null : _titleCtrl.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _stories = _stories
            .where((item) => item.id != story.id)
            .toList(growable: false);
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'ØªÙ… ØªØ«Ø¨ÙŠØª Ø§Ù„Ø³ØªÙˆØ±ÙŠ ÙÙŠ Ø§Ù„Ù‡Ø§ÙŠÙ„Ø§ÙŠØª.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = mapAnyError(
          e,
          fallback: 'ØªØ¹Ø°Ø± ØªØ«Ø¨ÙŠØª Ø§Ù„Ø³ØªÙˆØ±ÙŠ.',
        );
      });
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          children: [
            const ListTile(
              title: Text(
                'ØªØ«Ø¨ÙŠØª Ø³ØªÙˆØ±ÙŠ ÙÙŠ Ø§Ù„Ù‡Ø§ÙŠÙ„Ø§ÙŠØª',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.end,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
              child: TextField(
                controller: _titleCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'Ø¹Ù†ÙˆØ§Ù† Ø§Ù„Ù‡Ø§ÙŠÙ„Ø§ÙŠØª (Ø§Ø®ØªÙŠØ§Ø±ÙŠ)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
                child: Text(
                  _error!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _stories.isEmpty
                  ? const Center(
                      child: Text(
                        'Ù„Ø§ ØªÙˆØ¬Ø¯ Ø³ØªÙˆØ±ÙŠØ§Øª Ø¨Ø§Ù„Ø£Ø±Ø´ÙŠÙ Ø­Ø§Ù„ÙŠØ§Ù‹.',
                        textDirection: TextDirection.rtl,
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
                      itemCount: _stories.length,
                      itemBuilder: (context, index) {
                        final story = _stories[index];
                        final mediaUrl = (story.mediaUrl ?? '').trim();
                        final isImage =
                            story.mediaKind == 'image' && mediaUrl.isNotEmpty;
                        return Card(
                          child: ListTile(
                            leading: isImage
                                ? ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: Image.network(
                                      mediaUrl,
                                      width: 46,
                                      height: 46,
                                      fit: BoxFit.cover,
                                    ),
                                  )
                                : const CircleAvatar(
                                    child: Icon(Icons.auto_stories_rounded),
                                  ),
                            title: Text(
                              story.caption.trim().isEmpty
                                  ? 'Ø³ØªÙˆØ±ÙŠ Ø¨Ø¯ÙˆÙ† Ù†Øµ'
                                  : story.caption.trim(),
                              textDirection: TextDirection.rtl,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            trailing: FilledButton(
                              onPressed: _saving
                                  ? null
                                  : () => _pinStory(story),
                              child: const Text('ØªØ«Ø¨ÙŠØª'),
                            ),
                          ),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Ø¥Ù†Ù‡Ø§Ø¡'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EditProfileSheet extends StatefulWidget {
  final SocialApi api;
  final SocialUserProfile initialProfile;

  const _EditProfileSheet({required this.api, required this.initialProfile});

  @override
  State<_EditProfileSheet> createState() => _EditProfileSheetState();
}

class _EditProfileSheetState extends State<_EditProfileSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _bioCtrl;
  late final TextEditingController _ageCtrl;
  late bool _showPhone;
  late bool _postsPublic;
  late bool _storiesPublic;

  LocalMediaFile? _pickedImage;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.initialProfile.fullName);
    _bioCtrl = TextEditingController(text: widget.initialProfile.bio);
    _ageCtrl = TextEditingController(
      text: widget.initialProfile.age?.toString() ?? '',
    );
    _showPhone = widget.initialProfile.showPhone;
    _postsPublic = widget.initialProfile.postsPublic;
    _storiesPublic = widget.initialProfile.storiesPublic;
  }

  Future<void> _pickImage() async {
    final media = await pickPostMediaFromDevice();
    if (media == null) return;
    final mime = (media.mimeType ?? '').toLowerCase();
    if (!mime.startsWith('image/')) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ø§Ø®ØªØ± ØµÙˆØ±Ø© ÙÙ‚Ø· Ù„ØªØ­Ø¯ÙŠØ« Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ.',
          ),
        ),
      );
      return;
    }
    setState(() {
      _pickedImage = media;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final fullName = _nameCtrl.text.trim();
    final bio = _bioCtrl.text.trim();
    final ageText = _ageCtrl.text.trim();
    int? age;
    if (fullName.isEmpty) {
      setState(() => _error = 'Ø§Ù„Ø§Ø³Ù… Ù…Ø·Ù„ÙˆØ¨.');
      return;
    }
    if (ageText.isNotEmpty) {
      age = int.tryParse(ageText);
      if (age == null || age < 13 || age > 100) {
        setState(() => _error = 'يرجى إدخال عمر صحيح بين 13 و100.');
        return;
      }
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final out = await widget.api.updateMyProfile(
        fullName: fullName,
        bio: bio,
        age: age,
        showPhone: _showPhone,
        postsPublic: _postsPublic,
        storiesPublic: _storiesPublic,
        imageFile: _pickedImage,
      );
      final raw = out['profile'];
      if (!mounted) return;
      if (raw is! Map) {
        setState(() {
          _saving = false;
          _error = 'ØªØ¹Ø°Ø± Ø­ÙØ¸ Ø§Ù„ØªØ¹Ø¯ÙŠÙ„Ø§Øª.';
        });
        return;
      }
      final profile = SocialUserProfile.fromJson(
        Map<String, dynamic>.from(raw),
      );
      Navigator.of(context).pop(profile);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = mapAnyError(
          e,
          fallback: 'ØªØ¹Ø°Ø± Ø­ÙØ¸ Ø§Ù„ØªØ¹Ø¯ÙŠÙ„Ø§Øª.',
        );
      });
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _bioCtrl.dispose();
    _ageCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avatarUrl = (widget.initialProfile.imageUrl ?? '').trim();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'ØªØ¹Ø¯ÙŠÙ„ Ø§Ù„Ù…Ù„Ù Ø§Ù„Ø´Ø®ØµÙŠ',
                textDirection: TextDirection.rtl,
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
              ),
              const SizedBox(height: 10),
              Center(
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 42,
                      backgroundImage:
                          _pickedImage == null && avatarUrl.isNotEmpty
                          ? NetworkImage(avatarUrl)
                          : null,
                      child: _pickedImage != null
                          ? const Icon(Icons.image_rounded, size: 30)
                          : (avatarUrl.isEmpty
                                ? const Icon(Icons.person_outline, size: 30)
                                : null),
                    ),
                    Positioned(
                      right: -2,
                      bottom: -2,
                      child: IconButton.filled(
                        onPressed: _pickImage,
                        icon: const Icon(Icons.camera_alt_outlined),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: _nameCtrl,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'Ø§Ù„Ø§Ø³Ù… Ø§Ù„ÙƒØ§Ù…Ù„',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _ageCtrl,
                keyboardType: TextInputType.number,
                textDirection: TextDirection.rtl,
                decoration: const InputDecoration(
                  labelText: 'العمر (اختياري)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _bioCtrl,
                textDirection: TextDirection.rtl,
                minLines: 3,
                maxLines: 6,
                maxLength: 280,
                decoration: const InputDecoration(
                  labelText: 'Ù†Ø¨Ø°Ø© ØªØ¹Ø±ÙŠÙÙŠØ©',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 10),
              SwitchListTile.adaptive(
                value: _showPhone,
                onChanged: (value) => setState(() => _showPhone = value),
                title: const Text(
                  'Ø¥Ø¸Ù‡Ø§Ø± Ø±Ù‚Ù… Ø§Ù„Ù‡Ø§ØªÙ ÙÙŠ Ø§Ù„ØµÙØ­Ø© Ø§Ù„Ø´Ø®ØµÙŠØ©',
                  textDirection: TextDirection.rtl,
                ),
              ),
              SwitchListTile.adaptive(
                value: _postsPublic,
                onChanged: (value) => setState(() => _postsPublic = value),
                title: const Text(
                  'Ø§Ù„Ø³Ù…Ø§Ø­ Ù„Ù„Ø¬Ù…ÙŠØ¹ Ø¨Ø±Ø¤ÙŠØ© Ù…Ù†Ø´ÙˆØ±Ø§ØªÙŠ',
                  textDirection: TextDirection.rtl,
                ),
              ),
              SwitchListTile.adaptive(
                value: _storiesPublic,
                onChanged: (value) => setState(() => _storiesPublic = value),
                title: const Text(
                  'Ø§Ù„Ø³Ù…Ø§Ø­ Ù„Ù„Ø¬Ù…ÙŠØ¹ Ø¨Ø±Ø¤ÙŠØ© Ø³ØªÙˆØ±ÙŠØ§ØªÙŠ',
                  textDirection: TextDirection.rtl,
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_outlined),
                label: const Text('Ø­ÙØ¸ Ø§Ù„ØªØ¹Ø¯ÙŠÙ„Ø§Øª'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileMediaViewerPage extends StatefulWidget {
  final String mediaUrl;
  final bool isVideo;
  final String title;
  final String subtitle;
  final String? caption;

  const _ProfileMediaViewerPage({
    required this.mediaUrl,
    required this.isVideo,
    required this.title,
    required this.subtitle,
    this.caption,
  });

  @override
  State<_ProfileMediaViewerPage> createState() =>
      _ProfileMediaViewerPageState();
}

class _ProfileMediaViewerPageState extends State<_ProfileMediaViewerPage> {
  VideoPlayerController? _video;
  bool _videoReady = false;
  String? _videoError;

  @override
  void initState() {
    super.initState();
    if (widget.isVideo) {
      _initVideo();
    }
  }

  Future<void> _initVideo() async {
    try {
      final uri = Uri.tryParse(widget.mediaUrl);
      if (uri == null) {
        setState(
          () => _videoError = 'Ø±Ø§Ø¨Ø· Ø§Ù„ÙÙŠØ¯ÙŠÙˆ ØºÙŠØ± ØµØ§Ù„Ø­.',
        );
        return;
      }
      final controller = VideoPlayerController.networkUrl(uri);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _video = controller;
        _videoReady = true;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _videoError = 'ØªØ¹Ø°Ø± ØªØ´ØºÙŠÙ„ Ø§Ù„ÙÙŠØ¯ÙŠÙˆ.');
    }
  }

  Future<void> _togglePlayPause() async {
    final video = _video;
    if (video == null || !video.value.isInitialized) return;
    if (video.value.isPlaying) {
      await video.pause();
    } else {
      await video.play();
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _video?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            Text(widget.subtitle, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ),
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (!widget.isVideo)
            InteractiveViewer(
              minScale: 0.7,
              maxScale: 4,
              child: Center(
                child: Image.network(
                  widget.mediaUrl,
                  fit: BoxFit.contain,
                  errorBuilder: (context, error, stackTrace) =>
                      const _MediaError(
                        message: 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„ØµÙˆØ±Ø©.',
                      ),
                ),
              ),
            )
          else if (_videoError != null)
            Center(child: _MediaError(message: _videoError!))
          else if (!_videoReady)
            const Center(child: CircularProgressIndicator())
          else
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _togglePlayPause,
              child: Center(
                child: AspectRatio(
                  aspectRatio: _video!.value.aspectRatio,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      VideoPlayer(_video!),
                      AnimatedOpacity(
                        opacity: _video!.value.isPlaying ? 0 : 1,
                        duration: const Duration(milliseconds: 180),
                        child: const Icon(
                          Icons.play_circle_fill_rounded,
                          size: 72,
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          if ((widget.caption ?? '').trim().isNotEmpty)
            Positioned(
              right: 12,
              left: 12,
              bottom: 16,
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.52),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white24),
                ),
                child: Text(
                  widget.caption!.trim(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MediaError extends StatelessWidget {
  final String message;

  const _MediaError({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF14243E),
      alignment: Alignment.center,
      child: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ProfileFilterOption {
  final String label;
  final String? kind;
  final IconData icon;

  const _ProfileFilterOption(this.label, this.kind, this.icon);
}

class _HighlightAlbum {
  final int id;
  final String title;
  final SocialStoryHighlight cover;
  final List<SocialStory> stories;

  const _HighlightAlbum({
    required this.id,
    required this.title,
    required this.cover,
    required this.stories,
  });
}

const String _allPostsKey = '__all__';

const List<_ProfileFilterOption> _profileFilters = <_ProfileFilterOption>[
  _ProfileFilterOption('Ø§Ù„ÙƒÙ„', null, Icons.grid_view_rounded),
  _ProfileFilterOption('ØµÙˆØ±', 'image', Icons.image_outlined),
  _ProfileFilterOption('Ø±ÙŠÙ„Ø²', 'video', Icons.ondemand_video_rounded),
  _ProfileFilterOption(
    'ØªÙ‚ÙŠÙŠÙ…Ø§Øª',
    'merchant_review',
    Icons.rate_review_outlined,
  ),
  _ProfileFilterOption('Ù†ØµÙˆØµ', 'text', Icons.text_fields_rounded),
];

int? _parseInt(dynamic value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

bool _parseBool(dynamic value, {bool fallback = false}) {
  if (value == null) return fallback;
  if (value is bool) return value;
  if (value is num) return value != 0;
  final normalized = value.toString().trim().toLowerCase();
  if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
    return true;
  }
  if (normalized == 'false' || normalized == '0' || normalized == 'no') {
    return false;
  }
  return fallback;
}
