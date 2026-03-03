import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/data/notifications_api.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
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
  int? _nextCursor;
  int? _lastEventId;
  bool _loading = false;
  bool _loadingMore = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
    _liveApi = ref.read(_liveNotificationsApiProvider);
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    await _loadMessages(initial: true);
    if (!mounted) return;
    _connectRealtime();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(const Duration(seconds: 6), (_) {
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

      if (initial || !loadMore) {
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
            _loadMessages(silent: true);
          },
          onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
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

  Future<void> _callPeer() async {
    final phone = (widget.peerPhone ?? '').trim();
    if (phone.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('رقم الهاتف غير متوفر لهذا المستخدم.')),
      );
      return;
    }
    final uri = Uri.parse('tel:$phone');
    final ok = await launchUrl(uri);
    if (!ok && mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تعذر فتح الاتصال.')));
    }
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
            onPressed: _callPeer,
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
                            timeText: message.createdAt == null
                                ? ''
                                : _timeFormat.format(
                                    message.createdAt!.toLocal(),
                                  ),
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
  final String timeText;
  final VoidCallback onOpenAuthorAvatar;
  final VoidCallback onOpenAuthorProfile;

  const _ChatBubble({
    required this.message,
    required this.timeText,
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
