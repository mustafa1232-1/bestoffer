import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/data/notifications_api.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_call_screen.dart';
import 'social_profile_screen.dart';
import 'social_story_quick_viewer.dart';

final _liveNotificationsApiProvider = Provider<NotificationsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return NotificationsApi(dio);
});

class SocialChatThreadScreen extends ConsumerStatefulWidget {
  final int threadId;
  final String peerName;
  final String? peerPhone;
  final int? peerUserId;
  final String? peerImageUrl;

  const SocialChatThreadScreen({
    super.key,
    required this.threadId,
    required this.peerName,
    this.peerPhone,
    this.peerUserId,
    this.peerImageUrl,
  });

  @override
  ConsumerState<SocialChatThreadScreen> createState() =>
      _SocialChatThreadScreenState();
}

class _SocialChatThreadScreenState
    extends ConsumerState<SocialChatThreadScreen> {
  late final SocialApi _api;
  late final NotificationsApi _liveApi;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();

  final intl.DateFormat _timeFormat = intl.DateFormat('hh:mm a', 'ar');

  StreamSubscription<NotificationLiveEvent>? _liveSub;
  Timer? _pollTimer;
  Timer? _reconnectTimer;

  List<SocialChatMessage> _messages = const [];
  final Set<int> _reactionBusyMessageIds = <int>{};
  int? _nextCursor;
  int? _lastEventId;
  bool _loading = false;
  bool _loadingMore = false;
  bool _sending = false;
  bool _showJumpToBottom = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
    _liveApi = ref.read(_liveNotificationsApiProvider);
    _scrollController.addListener(_handleScroll);
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    await _loadMessages(initial: true);
    if (!mounted) return;
    _connectRealtime();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      _loadMessages(silent: true);
    });
  }

  Future<void> _loadMessages({
    bool initial = false,
    bool silent = false,
    bool loadMore = false,
  }) async {
    if (_loading && !loadMore) return;
    if (loadMore && (_loadingMore || _nextCursor == null)) return;

    if (mounted) {
      setState(() {
        if (loadMore) {
          _loadingMore = true;
        } else {
          _loading = !silent;
          if (!silent) _error = null;
        }
      });
    }

    try {
      final out = await _api.listThreadMessages(
        widget.threadId,
        limit: 40,
        beforeId: loadMore ? _nextCursor : null,
      );
      final raw = List<dynamic>.from(out['messages'] as List? ?? const []);
      final parsed = raw
          .map(
            (e) =>
                SocialChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);

      if (!mounted) return;

      setState(() {
        _nextCursor = _parseInt(out['nextCursor']);
        if (loadMore) {
          _messages = [...parsed, ..._messages];
        } else if (initial) {
          _messages = parsed;
        } else {
          final merged = <int, SocialChatMessage>{};
          for (final m in _messages) {
            merged[m.id] = m;
          }
          for (final m in parsed) {
            merged[m.id] = m;
          }
          final ordered = merged.values.toList()
            ..sort((a, b) => a.id.compareTo(b.id));
          _messages = ordered;
        }
        _loading = false;
        _loadingMore = false;
      });

      if (initial || (!loadMore && _isNearBottom(threshold: 260))) {
        _scrollToBottom(animated: !initial);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (!silent) {
          _error = mapAnyError(e, fallback: 'تعذر تحميل المحادثة.');
        }
      });
    }
  }

  void _connectRealtime() {
    _liveSub?.cancel();
    _liveSub = _liveApi
        .streamEvents(lastEventId: _lastEventId)
        .listen(
          (event) {
            if (event.eventId != null && event.eventId! > 0) {
              _lastEventId = event.eventId;
            }
            if (event.event != 'social_chat_message') return;

            final threadId = _parseInt(
              event.data['threadId'] ?? event.data['thread_id'],
            );
            if (threadId != widget.threadId) return;

            final messageId = _parseInt(
              event.data['messageId'] ?? event.data['message_id'],
            );
            if (messageId != null && event.data['reactions'] is Map) {
              final rawSummary = event.data['reactions'];
              final counts = _extractReactionCounts(rawSummary);
              final total = _extractReactionTotalCount(rawSummary, counts);
              _patchMessage(
                messageId,
                (current) => current.copyWith(
                  reactionCounts: counts,
                  reactionTotalCount: total,
                ),
              );
              return;
            }
            _loadMessages(silent: true);
          },
          onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  bool _isNearBottom({double threshold = 160}) {
    if (!_scrollController.hasClients) return true;
    final max = _scrollController.position.maxScrollExtent;
    final current = _scrollController.offset;
    return (max - current) <= threshold;
  }

  void _handleScroll() {
    if (!mounted || !_scrollController.hasClients) return;
    final shouldShow = !_isNearBottom(threshold: 180);
    if (_showJumpToBottom == shouldShow) return;
    setState(() => _showJumpToBottom = shouldShow);
  }

  void _scheduleReconnect() {
    if (!mounted) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _connectRealtime();
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      final out = await _api.sendThreadMessage(widget.threadId, text);
      final raw = out['message'];
      if (raw is Map) {
        final message = SocialChatMessage.fromJson(
          Map<String, dynamic>.from(raw),
        );
        if (!mounted) return;
        setState(() {
          final exists = _messages.any((m) => m.id == message.id);
          if (!exists) {
            _messages = [..._messages, message];
          }
        });
        _inputController.clear();
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapAnyError(e, fallback: 'تعذر إرسال الرسالة.');
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  void _patchMessage(
    int messageId,
    SocialChatMessage Function(SocialChatMessage) transform,
  ) {
    if (!mounted) return;
    setState(() {
      _messages = _messages
          .map((message) {
            if (message.id != messageId) return message;
            return transform(message);
          })
          .toList(growable: false);
    });
  }

  Map<String, int> _extractReactionCounts(dynamic raw) {
    if (raw is! Map) return const <String, int>{};
    final dynamic countsRaw = raw['counts'];
    if (countsRaw is! Map) return const <String, int>{};
    final out = <String, int>{};
    for (final entry in countsRaw.entries) {
      final key = '${entry.key}'.trim().toLowerCase();
      final value = int.tryParse('${entry.value}') ?? 0;
      if (key.isEmpty || value <= 0) continue;
      out[key] = value;
    }
    return out;
  }

  int _extractReactionTotalCount(dynamic raw, Map<String, int> counts) {
    if (raw is Map) {
      final direct = int.tryParse(
        '${raw['totalCount'] ?? raw['total_count'] ?? ''}',
      );
      if (direct != null && direct >= 0) return direct;
    }
    return counts.values.fold<int>(0, (sum, item) => sum + item);
  }

  String? _extractMyReaction(dynamic raw) {
    if (raw is! Map) return null;
    final value = '${raw['myReaction'] ?? raw['my_reaction'] ?? ''}'
        .trim()
        .toLowerCase();
    return value.isEmpty ? null : value;
  }

  SocialChatMessage _optimisticMessageReaction(
    SocialChatMessage message,
    String reactionKey,
  ) {
    final normalized = reactionKey.trim().toLowerCase();
    final counts = <String, int>{...message.reactionCounts};
    final current = message.myReaction?.trim().toLowerCase();

    if (current != null && current.isNotEmpty) {
      final reduced = (counts[current] ?? 0) - 1;
      if (reduced > 0) {
        counts[current] = reduced;
      } else {
        counts.remove(current);
      }
    }

    final togglingOff = current == normalized;
    String? nextMyReaction;
    if (!togglingOff) {
      counts[normalized] = (counts[normalized] ?? 0) + 1;
      nextMyReaction = normalized;
    }

    final total = counts.values.fold<int>(0, (sum, item) => sum + item);
    return message.copyWith(
      reactionCounts: counts,
      reactionTotalCount: total,
      myReaction: nextMyReaction,
      clearMyReaction: nextMyReaction == null,
    );
  }

  Future<void> _toggleReaction(
    SocialChatMessage message,
    String reactionKey,
  ) async {
    if (_reactionBusyMessageIds.contains(message.id)) return;
    final normalized = reactionKey.trim().toLowerCase();
    if (!_kMessageReactionKeys.contains(normalized)) return;

    final previous = message;
    final optimistic = _optimisticMessageReaction(previous, normalized);

    setState(() {
      _reactionBusyMessageIds.add(message.id);
    });
    _patchMessage(message.id, (_) => optimistic);

    try {
      final out = await _api.toggleThreadMessageReaction(
        threadId: widget.threadId,
        messageId: message.id,
        reaction: normalized,
      );
      final rawSummary = out['reactions'];
      final counts = _extractReactionCounts(rawSummary);
      final total = _extractReactionTotalCount(rawSummary, counts);
      final myReaction = _extractMyReaction(rawSummary);

      _patchMessage(
        message.id,
        (current) => current.copyWith(
          reactionCounts: counts,
          reactionTotalCount: total,
          myReaction: myReaction,
          clearMyReaction: myReaction == null,
        ),
      );
    } catch (e) {
      _patchMessage(message.id, (_) => previous);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: 'تعذر إضافة التفاعل على الرسالة.'),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _reactionBusyMessageIds.remove(message.id);
        });
      }
    }
  }

  Future<void> _startInAppCall() async {
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialCallScreen(
          threadId: widget.threadId,
          isCaller: true,
          remoteDisplayName: widget.peerName,
        ),
      ),
    );
  }

  Future<void> _openUserProfile({
    required int userId,
    required String fullName,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SocialProfileScreen(userId: userId, initialName: fullName),
      ),
    );
  }

  Future<void> _openUserAvatar({
    required int userId,
    required String fullName,
  }) async {
    var stories = ref.read(socialControllerProvider).stories;
    if (stories.isEmpty) {
      await ref
          .read(socialControllerProvider.notifier)
          .loadStories(silent: true);
      if (!mounted) return;
      stories = ref.read(socialControllerProvider).stories;
    }

    SocialStoryGroup? group;
    for (final item in stories) {
      if (item.userId == userId && item.stories.isNotEmpty) {
        group = item;
        break;
      }
    }

    if (group != null) {
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

    await _openUserProfile(userId: userId, fullName: fullName);
  }

  void _scrollToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final target = _scrollController.position.maxScrollExtent + 40;
      if (animated) {
        _scrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
        );
      } else {
        _scrollController.jumpTo(target);
      }
    });
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEmpty = _messages.isEmpty;

    return Scaffold(
      appBar: AppBar(
        title: InkWell(
          onTap: widget.peerUserId == null
              ? null
              : () => _openUserProfile(
                  userId: widget.peerUserId!,
                  fullName: widget.peerName,
                ),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            textDirection: TextDirection.rtl,
            children: [
              InkWell(
                onTap: widget.peerUserId == null
                    ? null
                    : () => _openUserAvatar(
                        userId: widget.peerUserId!,
                        fullName: widget.peerName,
                      ),
                borderRadius: BorderRadius.circular(999),
                child: CircleAvatar(
                  radius: 16,
                  backgroundImage: (widget.peerImageUrl ?? '').trim().isNotEmpty
                      ? NetworkImage(widget.peerImageUrl!)
                      : null,
                  child: (widget.peerImageUrl ?? '').trim().isEmpty
                      ? const Icon(Icons.person_outline, size: 16)
                      : null,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(widget.peerName, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: 'اتصال',
            onPressed: _startInAppCall,
            icon: const Icon(Icons.call_outlined),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                _error!,
                textDirection: TextDirection.rtl,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onErrorContainer,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: _loading && isEmpty
                      ? const Center(child: CircularProgressIndicator())
                      : RefreshIndicator(
                          onRefresh: () => _loadMessages(),
                          child: ListView(
                            controller: _scrollController,
                            padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                            children: [
                              if (_nextCursor != null)
                                Align(
                                  alignment: Alignment.center,
                                  child: OutlinedButton.icon(
                                    onPressed: _loadingMore
                                        ? null
                                        : () => _loadMessages(loadMore: true),
                                    icon: _loadingMore
                                        ? const SizedBox(
                                            width: 14,
                                            height: 14,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.expand_less_rounded),
                                    label: const Text('عرض رسائل أقدم'),
                                  ),
                                ),
                              if (isEmpty)
                                const Padding(
                                  padding: EdgeInsets.only(top: 80),
                                  child: Center(
                                    child: Text(
                                      'لا توجد رسائل بعد. ابدأ المحادثة الآن.',
                                      textDirection: TextDirection.rtl,
                                    ),
                                  ),
                                ),
                              for (final message in _messages)
                                _ChatBubble(
                                  message: message,
                                  reactionBusy: _reactionBusyMessageIds
                                      .contains(message.id),
                                  timeText: message.createdAt == null
                                      ? ''
                                      : _timeFormat.format(
                                          message.createdAt!.toLocal(),
                                        ),
                                  onReact: (reactionKey) =>
                                      _toggleReaction(message, reactionKey),
                                  onOpenAuthorAvatar: () => _openUserAvatar(
                                    userId: message.sender.id,
                                    fullName: message.sender.fullName,
                                  ),
                                  onOpenAuthorProfile: () => _openUserProfile(
                                    userId: message.sender.id,
                                    fullName: message.sender.fullName,
                                  ),
                                ),
                            ],
                          ),
                        ),
                ),
                if (_showJumpToBottom)
                  Positioned(
                    left: 14,
                    bottom: 12,
                    child: FloatingActionButton.small(
                      heroTag: 'chat_scroll_bottom',
                      tooltip: 'آخر الرسائل',
                      onPressed: _scrollToBottom,
                      child: const Icon(
                        Icons.keyboard_double_arrow_down_rounded,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  top: BorderSide(
                    color: Theme.of(
                      context,
                    ).dividerColor.withValues(alpha: 0.25),
                  ),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'اكتب رسالتك...',
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _sending ? null : _sendMessage,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(52, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    child: _sending
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final SocialChatMessage message;
  final bool reactionBusy;
  final String timeText;
  final ValueChanged<String> onReact;
  final VoidCallback onOpenAuthorAvatar;
  final VoidCallback onOpenAuthorProfile;

  const _ChatBubble({
    required this.message,
    required this.reactionBusy,
    required this.timeText,
    required this.onReact,
    required this.onOpenAuthorAvatar,
    required this.onOpenAuthorProfile,
  });

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final bubbleColor = mine
        ? Theme.of(context).colorScheme.primaryContainer
        : Theme.of(context).colorScheme.surfaceContainerHighest;
    final textColor = mine
        ? Theme.of(context).colorScheme.onPrimaryContainer
        : Theme.of(context).colorScheme.onSurface;

    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 5),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: mine
                ? CrossAxisAlignment.start
                : CrossAxisAlignment.end,
            children: [
              if (!mine)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  textDirection: TextDirection.rtl,
                  children: [
                    InkWell(
                      onTap: onOpenAuthorAvatar,
                      borderRadius: BorderRadius.circular(999),
                      child: CircleAvatar(
                        radius: 11,
                        backgroundImage:
                            (message.sender.imageUrl ?? '').trim().isNotEmpty
                            ? NetworkImage(message.sender.imageUrl!)
                            : null,
                        child: (message.sender.imageUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.person_outline, size: 11)
                            : null,
                      ),
                    ),
                    const SizedBox(width: 6),
                    InkWell(
                      onTap: onOpenAuthorProfile,
                      borderRadius: BorderRadius.circular(6),
                      child: Text(
                        message.sender.fullName,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: textColor.withValues(alpha: 0.78),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              if (!mine) const SizedBox(height: 4),
              Text(
                message.body,
                textDirection: TextDirection.rtl,
                style: TextStyle(color: textColor, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: _kMessageReactionSpecs
                    .map((spec) {
                      final selected = message.myReaction == spec.key;
                      final count = message.reactionCounts[spec.key] ?? 0;
                      return InkWell(
                        onTap: reactionBusy ? null : () => onReact(spec.key),
                        borderRadius: BorderRadius.circular(999),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: selected
                                  ? Theme.of(context).colorScheme.primary
                                  : textColor.withValues(alpha: 0.25),
                            ),
                            color: selected
                                ? Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.14)
                                : Colors.transparent,
                          ),
                          child: Text(
                            count > 0 ? '${spec.emoji} $count' : spec.emoji,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              color: textColor.withValues(
                                alpha: selected ? 1 : 0.88,
                              ),
                            ),
                          ),
                        ),
                      );
                    })
                    .toList(growable: false),
              ),
              if (reactionBusy)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'جاري حفظ التفاعل...',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              if (timeText.isNotEmpty) ...[
                const SizedBox(height: 3),
                Text(
                  timeText,
                  style: TextStyle(
                    color: textColor.withValues(alpha: 0.68),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
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

int? _parseInt(dynamic value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

const Set<String> _kMessageReactionKeys = <String>{
  'like',
  'heart',
  'laugh',
  'fire',
};

const List<_MessageReactionSpec> _kMessageReactionSpecs =
    <_MessageReactionSpec>[
      _MessageReactionSpec('like', '👍'),
      _MessageReactionSpec('heart', '❤️'),
      _MessageReactionSpec('laugh', '😂'),
      _MessageReactionSpec('fire', '🔥'),
    ];

class _MessageReactionSpec {
  final String key;
  final String emoji;

  const _MessageReactionSpec(this.key, this.emoji);
}
