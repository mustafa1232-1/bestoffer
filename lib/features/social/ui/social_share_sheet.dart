import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'widgets/social_identity_view.dart';
import 'social_message_client_id.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

String socialEntityTypeFromPost(SocialPost post) {
  if ((post.sharedEntity?.type.trim().toLowerCase() ?? '') == 'reel') {
    return 'reel';
  }
  final kind = post.postKind.trim().toLowerCase();
  if (kind == 'reel' || kind == 'video') return 'reel';
  if (kind == 'merchant_review' || kind == 'review') return 'review';
  return 'post';
}

Map<String, dynamic> buildSocialSharedSnapshotFromPost(SocialPost post) {
  final isMerchantReview = isSocialMerchantReviewPost(post);
  return <String, dynamic>{
    'id': post.id,
    'postKind': post.postKind,
    'title': isMerchantReview ? post.merchantName : null,
    'caption': post.caption,
    'mediaKind': post.mediaKind,
    'mediaUrl': post.mediaUrl,
    'posterUrl': post.asset?.thumbnailUrl ?? post.asset?.posterUrl,
    'playbackUrl': post.asset?.playbackUrl,
    'createdAt': post.createdAt?.toIso8601String(),
    'authorName': post.author.fullName,
    'authorUsername': post.author.username,
    'authorImageUrl': post.author.imageUrl,
    'merchantId': post.merchantId,
    'merchantName': post.merchantName,
    'merchantType': post.merchantType,
    'merchantImageUrl': post.merchantImageUrl,
    'reviewRating': post.reviewRating,
    'author': <String, dynamic>{
      'id': post.author.id,
      'fullName': post.author.fullName,
      'username': post.author.username,
      'imageUrl': post.author.imageUrl,
    },
  }..removeWhere((_, value) => value == null);
}

Map<String, dynamic> buildSocialSharedSnapshotFromStory({
  required SocialStoryGroup group,
  required SocialStory story,
}) {
  return <String, dynamic>{
    'id': story.id,
    'type': 'story',
    'title': group.author.fullName,
    'caption': story.caption,
    'mediaKind': story.mediaKind,
    'mediaUrl': story.mediaUrl,
    'posterUrl': story.asset?.thumbnailUrl ?? story.asset?.posterUrl,
    'playbackUrl': story.asset?.playbackUrl,
    'createdAt': story.createdAt?.toIso8601String(),
    'author': <String, dynamic>{
      'id': group.author.id,
      'fullName': group.author.fullName,
      'username': group.author.username,
      'imageUrl': group.author.imageUrl,
    },
    'authorName': group.author.fullName,
    'authorUsername': group.author.username,
    'authorImageUrl': group.author.imageUrl,
  }..removeWhere((_, value) => value == null);
}

Future<bool?> showSocialShareSheet({
  required BuildContext context,
  required String entityType,
  required int entityId,
  required String previewTitle,
  String? previewSubtitle,
  String? externalShareText,
  Map<String, dynamic>? sharedSnapshot,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (_) => SocialShareSheet(
      entityType: entityType,
      entityId: entityId,
      previewTitle: previewTitle,
      previewSubtitle: previewSubtitle,
      externalShareText: externalShareText,
      sharedSnapshot: sharedSnapshot,
    ),
  );
}

class SocialShareSheet extends ConsumerStatefulWidget {
  final String entityType;
  final int entityId;
  final String previewTitle;
  final String? previewSubtitle;
  final String? externalShareText;
  final Map<String, dynamic>? sharedSnapshot;

  const SocialShareSheet({
    super.key,
    required this.entityType,
    required this.entityId,
    required this.previewTitle,
    this.previewSubtitle,
    this.externalShareText,
    this.sharedSnapshot,
  });

  @override
  ConsumerState<SocialShareSheet> createState() => _SocialShareSheetState();
}

class _SocialShareSheetState extends ConsumerState<SocialShareSheet> {
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  List<_ShareRecipient> _recentRecipients = const <_ShareRecipient>[];
  List<_ShareRecipient> _recipients = const <_ShareRecipient>[];
  final Set<int> _selectedUserIds = <int>{};

  SocialApi get _api => ref.read(socialApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load({String search = ''}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final loaded = await _loadRecipients(search: search);
      if (!mounted) return;
      setState(() {
        _recentRecipients = loaded.recentRecipients;
        _recipients = loaded.recipients;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialShareRecipientsLoadFailed,
        );
      });
    }
  }

  Future<_LoadedRecipients> _loadRecipients({required String search}) async {
    try {
      final out = await _api.listShareRecipients(search: search);
      return _LoadedRecipients(
        recentRecipients: _mapRecentRecipients(out),
        recipients: _mapRecipients(out),
      );
    } on DioException catch (error) {
      final statusCode = error.response?.statusCode;
      final routeMissing =
          statusCode == 404 ||
          '${error.response?.data is Map ? (error.response?.data as Map)['message'] : ''}'
                  .trim()
                  .toUpperCase() ==
              'ROUTE_NOT_FOUND';
      if (!routeMissing) rethrow;
      final fallback = await _loadRecipientsFallback(search: search);
      return fallback;
    }
  }

  Future<_LoadedRecipients> _loadRecipientsFallback({
    required String search,
  }) async {
    final results = await Future.wait([
      _api.listThreads(),
      _api.searchUsers(search: search, limit: search.trim().isEmpty ? 24 : 40),
    ]);
    final threadsOut = results[0];
    final usersOut = results[1];
    final recent = _mapRecentRecipients(threadsOut);
    final usersRaw = List<dynamic>.from(
      usersOut['users'] ?? usersOut['items'] ?? const <dynamic>[],
    );
    final recipients = usersRaw
        .map(
          (row) => _ShareRecipient.fromUserSearchResult(
            SocialUserSearchResult.fromJson(
              Map<String, dynamic>.from(row as Map),
            ),
          ),
        )
        .where((recipient) => recipient.user.id > 0)
        .toList(growable: false);
    return _LoadedRecipients(recentRecipients: recent, recipients: recipients);
  }

  List<_ShareRecipient> _mapRecentRecipients(Map<String, dynamic> out) {
    final recentRaw = List<dynamic>.from(
      out['recentThreads'] ?? out['threads'] ?? const <dynamic>[],
    );
    return recentRaw
        .map(
          (row) => _ShareRecipient.fromRecentThread(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  List<_ShareRecipient> _mapRecipients(Map<String, dynamic> out) {
    final recipientsRaw = List<dynamic>.from(
      out['recipients'] ?? out['users'] ?? const <dynamic>[],
    );
    return recipientsRaw
        .map(
          (row) => _ShareRecipient.fromRecipientRow(
            Map<String, dynamic>.from(row as Map),
          ),
        )
        .toList(growable: false);
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 250),
      () => _load(search: value.trim()),
    );
  }

  void _toggleRecipient(_ShareRecipient recipient) {
    if (!recipient.canSend) return;
    setState(() {
      if (_selectedUserIds.contains(recipient.user.id)) {
        _selectedUserIds.remove(recipient.user.id);
      } else {
        _selectedUserIds.add(recipient.user.id);
      }
    });
  }

  Future<void> _shareExternal() async {
    final text = [
      widget.previewTitle.trim(),
      (widget.previewSubtitle ?? '').trim(),
      (widget.externalShareText ?? '').trim(),
    ].where((item) => item.isNotEmpty).join('\n');
    if (text.isEmpty) return;
    await SharePlus.instance.share(ShareParams(text: text));
  }

  Future<void> _send() async {
    if (_sending || _selectedUserIds.isEmpty) return;
    final targets = _mergeRecipients().where(
      (recipient) => _selectedUserIds.contains(recipient.user.id),
    );
    setState(() {
      _sending = true;
      _error = null;
    });
    var sentCount = 0;
    try {
      for (final recipient in targets) {
        if (!recipient.canSend) continue;
        var threadId = recipient.threadId;
        if (threadId == null || threadId <= 0) {
          final threadOut = await _api.createThread(recipient.user.id);
          final threadMap = Map<String, dynamic>.from(
            threadOut['thread'] as Map? ?? const <String, dynamic>{},
          );
          threadId = int.tryParse('${threadMap['id']}');
        }
        if (threadId == null || threadId <= 0) continue;
        await _api.sendThreadMessage(
          threadId,
          '',
          sharedEntityType: widget.entityType,
          sharedEntityId: widget.entityId,
          sharedSnapshot: widget.sharedSnapshot,
          clientMessageId: buildSocialMessageClientId(
            scopeKey: 'thread:$threadId',
            body: '',
            sharedEntityType: widget.entityType,
            sharedEntityId: widget.entityId,
            sharedSnapshot: widget.sharedSnapshot,
          ),
        );
        sentCount += 1;
      }
      if (!mounted) return;
      Navigator.of(context).pop(sentCount > 0);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            sentCount == 1
                ? context.l10n.socialShareContentSharedSingle
                : context.l10n.socialShareContentSharedMultiple(sentCount),
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialShareSendFailed,
        );
      });
      return;
    }
  }

  List<_ShareRecipient> _mergeRecipients() {
    final merged = <int, _ShareRecipient>{};
    for (final recipient in _recipients) {
      merged[recipient.user.id] = recipient;
    }
    for (final recipient in _recentRecipients) {
      final current = merged[recipient.user.id];
      merged[recipient.user.id] = current == null
          ? recipient
          : current.copyWith(
              threadId: current.threadId ?? recipient.threadId,
              inboxBucket: current.inboxBucket ?? recipient.inboxBucket,
            );
    }
    return merged.values.toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final mergedRecipients = _mergeRecipients();
    final l10n = context.l10n;
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.86,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
              child: Text(
                l10n.socialShareSheetTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(18),
                  color: Theme.of(
                    context,
                  ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.previewTitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                    ),
                    if ((widget.previewSubtitle ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        widget.previewSubtitle!.trim(),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: _scheduleSearch,
                decoration: InputDecoration(
                  hintText: l10n.socialShareSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.commonClear,
                          onPressed: () {
                            _searchController.clear();
                            _load();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _shareExternal,
                      icon: const Icon(Icons.ios_share_rounded),
                      label: Text(l10n.socialShareExternal),
                    ),
                  ),
                ],
              ),
            ),
            if ((_error ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_recentRecipients.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                child: Text(
                  l10n.socialShareRecentChats,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              SizedBox(
                height: 126,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: _recentRecipients.length,
                  separatorBuilder: (_, separatorIndex) =>
                      const SizedBox(width: 10),
                  itemBuilder: (_, index) {
                    final recipient = _recentRecipients[index];
                    final selected = _selectedUserIds.contains(
                      recipient.user.id,
                    );
                    return _RecentShareRecipientCard(
                      recipient: recipient,
                      selected: selected,
                      onTap: () => _toggleRecipient(recipient),
                    );
                  },
                ),
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : mergedRecipients.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          l10n.socialShareNoRecipients,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: mergedRecipients.length,
                      separatorBuilder: (_, separatorIndex) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final recipient = mergedRecipients[index];
                        final selected = _selectedUserIds.contains(
                          recipient.user.id,
                        );
                        return _ShareRecipientTile(
                          recipient: recipient,
                          selected: selected,
                          onTap: () => _toggleRecipient(recipient),
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _sending || _selectedUserIds.isEmpty ? null : _send,
                icon: _sending
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send_rounded),
                label: Text(
                  _selectedUserIds.isEmpty
                      ? l10n.socialShareSelectAtLeastOne
                      : l10n.socialShareSendToCount(_selectedUserIds.length),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareRecipient {
  final SocialAuthor user;
  final SocialRelation relation;
  final int? threadId;
  final String? inboxBucket;
  final bool canSend;

  const _ShareRecipient({
    required this.user,
    required this.relation,
    required this.threadId,
    required this.inboxBucket,
    required this.canSend,
  });

  factory _ShareRecipient.fromRecentThread(Map<String, dynamic> json) {
    final thread = SocialChatThread.fromJson(json);
    return _ShareRecipient(
      user: thread.peer,
      relation: const SocialRelation(
        state: 'accepted',
        rawStatus: null,
        requestDirection: null,
        canChat: true,
        canCall: false,
        canSendRequest: false,
        blockedByMe: false,
        blockedByOther: false,
        otherUserId: null,
        initiatorUserId: null,
        requestedAt: null,
        respondedAt: null,
        updatedAt: null,
      ),
      threadId: thread.id,
      inboxBucket: thread.state.inboxBucket,
      canSend: true,
    );
  }

  factory _ShareRecipient.fromRecipientRow(Map<String, dynamic> json) {
    final userRaw = Map<String, dynamic>.from(
      json['user'] is Map ? json['user'] as Map : json,
    );
    final relationRaw = Map<String, dynamic>.from(
      json['relation'] as Map? ?? const <String, dynamic>{},
    );
    return _ShareRecipient(
      user: SocialAuthor.fromJson(userRaw),
      relation: SocialRelation.fromJson(relationRaw),
      threadId: int.tryParse('${json['threadId'] ?? json['thread_id']}'),
      inboxBucket: '${json['inboxBucket'] ?? json['inbox_bucket'] ?? ''}'
          .trim(),
      canSend: relationRaw.isEmpty
          ? true
          : (json['canSend'] == true || json['can_send'] == true),
    );
  }

  factory _ShareRecipient.fromUserSearchResult(SocialUserSearchResult item) {
    return _ShareRecipient(
      user: item.user,
      relation: item.relation,
      threadId: null,
      inboxBucket: null,
      canSend: !item.relation.isBlocked,
    );
  }

  _ShareRecipient copyWith({int? threadId, String? inboxBucket}) {
    return _ShareRecipient(
      user: user,
      relation: relation,
      threadId: threadId ?? this.threadId,
      inboxBucket: inboxBucket ?? this.inboxBucket,
      canSend: canSend,
    );
  }

  String get usernameLabel {
    final username = (user.username ?? '').trim();
    if (username.isEmpty) return '';
    return '@$username';
  }
}

class _LoadedRecipients {
  final List<_ShareRecipient> recentRecipients;
  final List<_ShareRecipient> recipients;

  const _LoadedRecipients({
    required this.recentRecipients,
    required this.recipients,
  });
}

class _RecentShareRecipientCard extends StatelessWidget {
  final _ShareRecipient recipient;
  final bool selected;
  final VoidCallback onTap;

  const _RecentShareRecipientCard({
    required this.recipient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: recipient.canSend ? onTap : null,
      child: Ink(
        width: 98,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: selected
              ? scheme.primary.withValues(alpha: 0.16)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.64),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
          ),
        ),
        child: Column(
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage:
                      (recipient.user.imageUrl ?? '').trim().isNotEmpty
                      ? AppCachedImageProvider(recipient.user.imageUrl!)
                      : null,
                  child: (recipient.user.imageUrl ?? '').trim().isEmpty
                      ? const Icon(Icons.person_outline)
                      : null,
                ),
                if (selected)
                  PositionedDirectional(
                    end: -2,
                    bottom: -2,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: scheme.primary,
                      child: Icon(
                        Icons.check_rounded,
                        size: 13,
                        color: scheme.onPrimary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Expanded(
              child: Center(
                child: SocialIdentityView(
                  author: recipient.user,
                  center: true,
                  showRoleFallback: false,
                  primaryStyle: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                  ),
                  secondaryStyle: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareRecipientTile extends StatelessWidget {
  final _ShareRecipient recipient;
  final bool selected;
  final VoidCallback onTap;

  const _ShareRecipientTile({
    required this.recipient,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: recipient.canSend ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.56),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.6)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundImage:
                    (recipient.user.imageUrl ?? '').trim().isNotEmpty
                    ? AppCachedImageProvider(recipient.user.imageUrl!)
                    : null,
                child: (recipient.user.imageUrl ?? '').trim().isEmpty
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SocialIdentityView(
                      author: recipient.user,
                      showRoleFallback: true,
                      primaryStyle: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 14,
                      ),
                      secondaryStyle: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                    if ((recipient.inboxBucket ?? '').trim() == 'requests')
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          context.l10n.socialShareWillArriveInRequests,
                          style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    if (!recipient.canSend)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          context.l10n.socialShareMessagingUnavailable,
                          style: TextStyle(
                            color: scheme.error,
                            fontWeight: FontWeight.w700,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Checkbox(
                value: selected,
                onChanged: recipient.canSend ? (_) => onTap() : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
