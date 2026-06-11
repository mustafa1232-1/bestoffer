import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/data/notifications_api.dart';
import '../../notifications/models/app_notification_model.dart';
import '../../notifications/state/notifications_controller.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_call_screen.dart';
import 'social_chat_thread_screen.dart';
import 'social_message_requests_screen.dart';
import 'social_profile_screen.dart';
import 'social_story_quick_viewer.dart';
import 'widgets/basmaya_shell_bars.dart';
import 'widgets/social_identity_view.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

const Duration _kThreadsFallbackPollInterval = Duration(seconds: 10);
const Duration _kThreadsTypingResetDelay = Duration(seconds: 4);
const Duration _kThreadsRefreshDebounce = Duration(milliseconds: 300);

final _socialThreadsLiveNotificationsApiProvider = Provider<NotificationsApi>((
  ref,
) {
  return NotificationsApi(ref.read(socialApiProvider).dio);
});

/// Purpose: ???? ????? ??????? ??????? ?? ?????? ???????? ?????? ??? unread counts ?????????? ?????.
/// Used by: ?????? ???????? deep links ??? thread ????? ????? notification routing ?????????.
/// Depends on: `socialControllerProvider`, `notificationsControllerProvider`, ??????? thread/profile/call.
/// Critical notes: ?????? ?????? polling ???? ?? fallback ??? ??? ???? realtime? ????? ????? ????? ???? SSE ?????.
/// Maintenance notes: ??? ????? ????????? ??????? ???? `loadThreads`, ?? notifications unread snapshot, ?? `social_chat_thread_screen.dart`.
/// ???? inbox ?????? ???????? ???????? ????? ??? ????????? ?????? ???????? ?????.
class SocialChatThreadsScreen extends ConsumerStatefulWidget {
  final int? initialThreadId;

  const SocialChatThreadsScreen({super.key, this.initialThreadId});

  @override
  ConsumerState<SocialChatThreadsScreen> createState() =>
      _SocialChatThreadsScreenState();
}

class _SocialChatThreadsScreenState
    extends ConsumerState<SocialChatThreadsScreen>
    with WidgetsBindingObserver {
  late final NotificationsApi _liveApi;
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _autoRefreshTimer;
  Timer? _reconnectTimer;
  Timer? _refreshDebounceTimer;
  StreamSubscription<NotificationLiveEvent>? _liveSub;
  final Map<int, Timer> _typingTimers = <int, Timer>{};

  String _query = '';
  String _threadBucket = 'private';
  String _threadFilter = 'all';
  bool _didHandleInitialThread = false;
  bool _appInForeground = true;
  bool _liveConnected = false;
  Map<int, int> _threadUnreadSnapshot = const <int, int>{};
  Map<int, String> _typingLabels = const <int, String>{};
  int _requestsCount = 0;
  int? _lastEventId;
  int _reconnectAttempt = 0;

  int? get _currentUserId => ref.read(authControllerProvider).user?.id;

  intl.DateFormat get _dateFormat => intl.DateFormat(
    'd/M hh:mm a',
    Localizations.localeOf(context).languageCode,
  );

  /// ???? ?????? ???? ??? snapshot ?????????? ?? ????? fallback polling ???????.
  ///
  /// polling ?? ????? ??????? ??? ???? realtime ??? ??? ??????? ?? ???????
  /// ?? ????? ???????? ???? ??? ?????? ??? ?????? ??? ????? ???? ?????? ?????.
  @override
  void initState() {
    super.initState();
    _liveApi = ref.read(_socialThreadsLiveNotificationsApiProvider);
    WidgetsBinding.instance.addObserver(this);
    _searchCtrl.addListener(() {
      final next = _searchCtrl.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
    Future.microtask(() async {
      if (!mounted) return;
      await _refreshThreads();
      if (!mounted) return;
      await _captureUnreadSnapshotAndClearNotifications();
      if (!mounted) return;
      _connectRealtime();
    });
    _autoRefreshTimer = Timer.periodic(_kThreadsFallbackPollInterval, (_) {
      if (!mounted) return;
      if (!_appInForeground) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      if (_liveConnected) {
        return;
      }
      unawaited(_refreshThreads(silent: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    _reconnectTimer?.cancel();
    _refreshDebounceTimer?.cancel();
    _liveSub?.cancel();
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _searchCtrl.dispose();
    super.dispose();
  }

  /// ????? threads ?????? ??????? ?? ??? ????? ??? ???? ???????? ?? ??? AppBar ???????.
  Future<void> _refreshThreads({bool silent = false}) async {
    if (!mounted) return;
    await Future.wait<void>([
      ref.read(socialControllerProvider.notifier).loadThreads(silent: silent),
      _loadRequestsCount(),
    ]);
  }

  /// ???? ??? ????? ??????? ??? ???????? ???.
  Future<void> _loadRequestsCount() async {
    if (!mounted) return;
    try {
      final out = await ref.read(socialApiProvider).listChatRequests();
      final raw = List<dynamic>.from(out['threads'] as List? ?? const []);
      if (!mounted) return;
      setState(() => _requestsCount = raw.length);
    } catch (_) {
      if (!mounted) return;
      setState(() => _requestsCount = 0);
    }
  }

  /// ???? unread notifications ??? ???? ???? ??? thread.
  Map<int, int> _buildThreadUnreadCounts(
    List<AppNotificationModel> notifications,
  ) {
    final out = <int, int>{..._threadUnreadSnapshot};
    for (final notification in notifications) {
      if (notification.isRead) continue;
      final target = (notification.target ?? '').trim().toLowerCase();
      final type = notification.type.trim().toLowerCase();
      final isChat = target == 'social_chat' || type.startsWith('social.chat.');
      if (!isChat) continue;
      final rawThreadId =
          notification.payload?['threadId'] ??
          notification.payload?['thread_id'];
      final threadId = int.tryParse('$rawThreadId');
      if (threadId == null || threadId <= 0) continue;
      out.update(threadId, (value) => value + 1, ifAbsent: () => 1);
    }
    return out;
  }

  /// ????? unread ??????? ???????? ?????????? ?? ??????? ?? inbox ?????.
  Future<void> _captureUnreadSnapshotAndClearNotifications() async {
    if (!mounted) return;
    final notifications = ref
        .read(notificationsControllerProvider)
        .notifications;
    final snapshot = <int, int>{};
    for (final notification in notifications) {
      if (notification.isRead) continue;
      final target = (notification.target ?? '').trim().toLowerCase();
      final type = notification.type.trim().toLowerCase();
      final isChat = target == 'social_chat' || type.startsWith('social.chat.');
      if (!isChat) continue;
      final rawThreadId =
          notification.payload?['threadId'] ??
          notification.payload?['thread_id'];
      final threadId = int.tryParse('$rawThreadId');
      if (threadId == null || threadId <= 0) continue;
      snapshot.update(threadId, (value) => value + 1, ifAbsent: () => 1);
    }
    if (mounted) {
      setState(() => _threadUnreadSnapshot = snapshot);
    }
    if (!mounted) return;
    await ref
        .read(notificationsControllerProvider.notifier)
        .markSocialChatNotificationsRead();
  }

  Future<void> _openProfile(SocialAuthor author) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: author.id,
          initialName: author.fullName,
        ),
      ),
    );
  }

  Future<void> _openAvatar(SocialAuthor author) async {
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
      if (item.userId == author.id && item.stories.isNotEmpty) {
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

    await _openProfile(author);
  }

  /// ???? thread ?????? ??? ????? ????? ?????? ?????? ?? ????????? ??????.
  Future<void> _openThread(SocialChatThread thread) async {
    setState(() {
      _threadUnreadSnapshot = Map<int, int>.from(_threadUnreadSnapshot)
        ..remove(thread.id);
    });
    await ref
        .read(notificationsControllerProvider.notifier)
        .markSocialChatNotificationsRead(threadId: thread.id);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: thread.id,
          peerName: thread.displayTitle,
          peerPhone: thread.peerPhone,
          peerUserId: thread.isGroup ? null : thread.peer.id,
          peerImageUrl: thread.displayImageUrl,
        ),
      ),
    );
    if (!mounted) return;
    await _refreshThreads();
  }

  Future<void> _setThreadPinned(
    SocialChatThread thread, {
    required bool enabled,
  }) async {
    final l10n = context.l10n;
    try {
      await ref
          .read(socialApiProvider)
          .setThreadPinned(threadId: thread.id, enabled: enabled);
      if (!mounted) return;
      await _refreshThreads(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled
                ? l10n.socialChatThreadsPinSuccess
                : l10n.socialChatThreadsUnpinSuccess,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: enabled
                  ? l10n.socialChatThreadsPinFailed
                  : l10n.socialChatThreadsUnpinFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _toggleMuteThread(SocialChatThread thread) async {
    final nextEnabled = !thread.state.muted;
    try {
      await ref
          .read(socialApiProvider)
          .setThreadMute(threadId: thread.id, enabled: nextEnabled);
      if (!mounted) return;
      await _refreshThreads(silent: true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: nextEnabled
                  ? context.l10n.socialChatThreadsMuteFailed
                  : context.l10n.socialChatThreadsUnmuteFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openThreadActions(SocialChatThread thread) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(
                thread.state.pinnedAt != null
                    ? Icons.push_pin_outlined
                    : Icons.push_pin_rounded,
              ),
              title: Text(
                thread.state.pinnedAt != null
                    ? context.l10n.socialChatThreadsUnpinAction
                    : context.l10n.socialChatThreadsPinAction,
              ),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(
                  _setThreadPinned(
                    thread,
                    enabled: thread.state.pinnedAt == null,
                  ),
                );
              },
            ),
            ListTile(
              leading: Icon(
                thread.state.muted
                    ? Icons.volume_up_rounded
                    : Icons.volume_off_rounded,
              ),
              title: Text(
                thread.state.muted
                    ? context.l10n.socialChatThreadsUnmuteAction
                    : context.l10n.socialChatThreadsMuteAction,
              ),
              onTap: () {
                Navigator.of(context).pop();
                unawaited(_toggleMuteThread(thread));
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final foreground =
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
    if (_appInForeground == foreground) return;
    _appInForeground = foreground;
    if (!_appInForeground) {
      _liveConnected = false;
      _reconnectTimer?.cancel();
      _liveSub?.cancel();
      _clearTypingLabels();
      return;
    }
    _connectRealtime();
    unawaited(_refreshThreads(silent: true));
  }

  void _connectRealtime() {
    _reconnectTimer?.cancel();
    _liveSub?.cancel();
    _liveSub = _liveApi
        .streamEvents(lastEventId: _lastEventId, channel: 'social')
        .listen(
          (event) {
            _reconnectAttempt = 0;
            _liveConnected = true;
            if (!_acceptRealtimeEventId(event.eventId)) return;
            if (event.event == 'resync_required') {
              _lastEventId = _parseInt(event.data['latestEventId']);
              _scheduleRefreshThreads();
              return;
            }
            if (event.event == 'social_chat_typing') {
              _handleTypingEvent(event.data);
              return;
            }
            if (event.event == 'social_chat_message' ||
                event.event == 'social_chat_state' ||
                event.event == 'social_chat_thread_updated') {
              final threadId = _parseInt(
                event.data['threadId'] ?? event.data['thread_id'],
              );
              if (threadId != null) {
                _clearTypingLabel(threadId);
              }
              _scheduleRefreshThreads();
            }
          },
          onError: (_) => _scheduleReconnect(),
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleReconnect() {
    if (!mounted || !_appInForeground) return;
    if (_reconnectTimer?.isActive == true) return;
    _liveConnected = false;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 8);
    final delaySeconds = switch (_reconnectAttempt) {
      1 => 2,
      2 => 4,
      3 => 6,
      4 => 10,
      _ => 15,
    };
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted || !_appInForeground) return;
      _connectRealtime();
    });
  }

  void _scheduleRefreshThreads() {
    _refreshDebounceTimer?.cancel();
    _refreshDebounceTimer = Timer(_kThreadsRefreshDebounce, () {
      if (!mounted || !_appInForeground) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      unawaited(_refreshThreads(silent: true));
    });
  }

  bool _acceptRealtimeEventId(int? eventId) {
    if (eventId == null || eventId <= 0) return true;
    if (_lastEventId != null && eventId <= _lastEventId!) return false;
    _lastEventId = eventId;
    return true;
  }

  void _handleTypingEvent(Map<String, dynamic> data) {
    final threadId = _parseInt(data['threadId'] ?? data['thread_id']);
    final actorUserId = _parseInt(data['actorUserId'] ?? data['actor_user_id']);
    if (threadId == null ||
        actorUserId == null ||
        actorUserId == _currentUserId) {
      return;
    }
    if (data['typing'] != true) {
      _clearTypingLabel(threadId);
      return;
    }
    final thread = ref
        .read(socialControllerProvider)
        .threads
        .where((entry) => entry.id == threadId)
        .cast<SocialChatThread?>()
        .firstWhere((entry) => entry != null, orElse: () => null);
    final actorName =
        '${data['actorDisplayName'] ?? data['actor_display_name'] ?? ''}'
            .trim();
    if (!mounted) return;
    final l10n = context.l10n;
    final label = thread?.isGroup == true && actorName.isNotEmpty
        ? l10n.socialChatThreadTypingBy(actorName)
        : l10n.socialChatThreadTyping;
    setState(() {
      _typingLabels = <int, String>{..._typingLabels, threadId: label};
    });
    _typingTimers[threadId]?.cancel();
    _typingTimers[threadId] = Timer(
      _kThreadsTypingResetDelay,
      () => _clearTypingLabel(threadId),
    );
  }

  void _clearTypingLabel(int threadId) {
    final timer = _typingTimers.remove(threadId);
    timer?.cancel();
    if (!_typingLabels.containsKey(threadId) || !mounted) return;
    final next = <int, String>{..._typingLabels}..remove(threadId);
    setState(() => _typingLabels = next);
  }

  void _clearTypingLabels() {
    for (final timer in _typingTimers.values) {
      timer.cancel();
    }
    _typingTimers.clear();
    if (!mounted || _typingLabels.isEmpty) return;
    setState(() => _typingLabels = const <int, String>{});
  }

  Future<void> _openCreateGroupSheet() async {
    final thread = await showModalBottomSheet<SocialChatThread>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _CreateGroupThreadSheet(),
    );
    if (!mounted || thread == null) return;
    await _openThread(thread);
  }

  Future<void> _openMessageRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SocialMessageRequestsScreen(),
      ),
    );
    if (!mounted) return;
    await _refreshThreads();
  }

  /// ?????? ?? deep link ???? ??? ?????? ?????? ??? ?????? ??? ????? ???????.
  void _tryOpenInitialThread(List<SocialChatThread> threads) {
    final targetId = widget.initialThreadId;
    if (_didHandleInitialThread || targetId == null || targetId <= 0) return;
    final matched = threads
        .where((t) => t.id == targetId)
        .cast<SocialChatThread?>()
        .firstWhere((t) => t != null, orElse: () => null);
    if (matched == null) return;
    _didHandleInitialThread = true;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openThread(matched));
    });
  }

  int _chatNotificationsSignature(List<AppNotificationModel> notifications) {
    var unreadCount = 0;
    var latestChatNotificationId = 0;
    for (final notification in notifications) {
      final target = (notification.target ?? '').trim().toLowerCase();
      final type = notification.type.trim().toLowerCase();
      final isChat =
          target == 'social_chat' ||
          type.startsWith('social.chat.') ||
          type.startsWith('social_chat.') ||
          type == 'social_chat_message';
      if (!isChat) continue;
      if (!notification.isRead) unreadCount += 1;
      if (notification.id > latestChatNotificationId) {
        latestChatNotificationId = notification.id;
      }
    }
    return Object.hash(unreadCount, latestChatNotificationId);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialControllerProvider);

    ref.listen<SocialState>(socialControllerProvider, (previous, next) {
      if (!mounted) return;
      final error = next.error;
      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    });

    ref.listen<NotificationsState>(notificationsControllerProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      final previousSignature = _chatNotificationsSignature(
        previous?.notifications ?? const <AppNotificationModel>[],
      );
      final nextSignature = _chatNotificationsSignature(next.notifications);
      if (previousSignature == nextSignature) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      _scheduleRefreshThreads();
    });

    final threads = state.threads;
    _tryOpenInitialThread(threads);
    final notificationsState = ref.watch(notificationsControllerProvider);
    final unreadByThread = _buildThreadUnreadCounts(
      notificationsState.notifications,
    );

    final normalizedQuery = _query.toLowerCase();
    final searched = normalizedQuery.isEmpty
        ? threads
        : threads
              .where((thread) {
                final name = thread.displayTitle.toLowerCase();
                final username = (thread.peer.username ?? '').toLowerCase();
                final phone = thread.peerPhone.toLowerCase();
                final body =
                    thread.lastMessage?.previewText.toLowerCase() ?? '';
                return name.contains(normalizedQuery) ||
                    username.contains(normalizedQuery) ||
                    phone.contains(normalizedQuery) ||
                    body.contains(normalizedQuery);
              })
              .toList(growable: false);
    final bucketFiltered = searched
        .where(
          (thread) => _threadBucket == 'work'
              ? thread.threadKind == 'business'
              : thread.threadKind != 'business',
        )
        .toList(growable: false);
    final filtered = _applyThreadFilter(bucketFiltered, unreadByThread);

    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final isLtr = Directionality.of(context) == TextDirection.ltr;

    Widget buildListBody() {
      if (state.loadingThreads && threads.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: const [
            SizedBox(
              height: 320,
              child: Center(child: CircularProgressIndicator()),
            ),
          ],
        );
      }

      if (filtered.isEmpty) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(24, 90, 24, 24),
          children: [
            Icon(
              Icons.forum_outlined,
              size: 54,
              color: scheme.onSurface.withValues(alpha: 0.75),
            ),
            const SizedBox(height: 10),
            Text(
              _query.trim().isEmpty
                  ? l10n.socialChatThreadsEmptyTitle
                  : l10n.socialChatThreadsSearchEmptyTitle,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              _query.trim().isEmpty
                  ? l10n.socialChatThreadsEmptySubtitle
                  : l10n.socialChatThreadsSearchEmptySubtitle,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurface.withValues(alpha: 0.78),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        );
      }

      return ListView.separated(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        itemCount: filtered.length,
        separatorBuilder: (context, index) => const SizedBox(height: 10),
        itemBuilder: (_, index) {
          final thread = filtered[index];
          final unreadCount = [
            unreadByThread[thread.id] ?? 0,
            thread.state.unreadCount,
          ].reduce((a, b) => a > b ? a : b);
          final hasUnread = unreadCount > 0;
          final typingLabel = _typingLabels[thread.id];
          final isTyping = (typingLabel ?? '').trim().isNotEmpty;
          final lastBody = thread.lastMessage?.previewText.trim() ?? '';
          final lastAt = thread.lastMessageAt;
          final subtitle = isTyping
              ? typingLabel!
              : lastBody.isNotEmpty
              ? lastBody
              : l10n.socialChatThreadsStartNow;
          final trimmedPeerUsername = thread.peer.username?.trim() ?? '';
          final remoteDisplayName = thread.isGroup
              ? thread.displayTitle
              : trimmedPeerUsername.isNotEmpty
              ? '@$trimmedPeerUsername'
              : thread.peer.fullName;

          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => _openThread(thread),
              onLongPress: () => _openThreadActions(thread),
              child: Ink(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [
                      scheme.surfaceContainerHighest.withValues(alpha: 0.92),
                      scheme.surfaceContainerHighest.withValues(alpha: 0.55),
                    ],
                  ),
                  border: Border.all(
                    color: scheme.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                  child: Row(
                    children: [
                      InkWell(
                        onTap: thread.isGroup
                            ? null
                            : () => _openAvatar(thread.peer),
                        borderRadius: BorderRadius.circular(999),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            CircleAvatar(
                              radius: 24,
                              backgroundImage:
                                  (thread.displayImageUrl ?? '')
                                      .trim()
                                      .isNotEmpty
                                  ? AppCachedImageProvider(
                                      thread.displayImageUrl!,
                                    )
                                  : null,
                              child:
                                  (thread.displayImageUrl ?? '').trim().isEmpty
                                  ? Icon(
                                      thread.isGroup
                                          ? Icons.group_outlined
                                          : Icons.person_outline,
                                    )
                                  : null,
                            ),
                            if (!thread.isGroup &&
                                thread.presence.canSeeOnlineStatus &&
                                thread.presence.isOnline)
                              PositionedDirectional(
                                end: -1,
                                bottom: -1,
                                child: Container(
                                  width: 12,
                                  height: 12,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: Colors.green.shade500,
                                    border: Border.all(
                                      color: scheme.surface,
                                      width: 2,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: isLtr
                              ? CrossAxisAlignment.start
                              : CrossAxisAlignment.end,
                          children: [
                            if (thread.isGroup)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      thread.displayTitle,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontWeight: hasUnread
                                            ? FontWeight.w900
                                            : FontWeight.w800,
                                        fontSize: 15,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  _ThreadMetaBadge(
                                    label: l10n
                                        .socialChatThreadsGroupMembersCount(
                                          thread.group?.memberCount ?? 0,
                                        ),
                                  ),
                                ],
                              )
                            else
                              InkWell(
                                onTap: () => _openProfile(thread.peer),
                                borderRadius: BorderRadius.circular(8),
                                child: SocialIdentityView(
                                  author: thread.peer,
                                  primaryStyle: TextStyle(
                                    fontWeight: hasUnread
                                        ? FontWeight.w900
                                        : FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                            if (thread.threadKind == 'business' &&
                                thread.context != null) ...[
                              const SizedBox(height: 4),
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: [
                                  _ThreadMetaBadge(
                                    label:
                                        thread.contextType ==
                                            'real_estate_listing'
                                        ? l10n.socialChatThreadsContextRealEstate
                                        : l10n.socialChatThreadsContextCar,
                                  ),
                                  if (thread.context!.title.trim().isNotEmpty)
                                    _ThreadMetaBadge(
                                      label: thread.context!.title,
                                    ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 2),
                            Text(
                              subtitle,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: isTyping
                                    ? FontWeight.w800
                                    : hasUnread
                                    ? FontWeight.w800
                                    : FontWeight.w600,
                                color: isTyping
                                    ? scheme.primary
                                    : scheme.onSurface.withValues(alpha: 0.88),
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (lastAt != null)
                            Text(
                              _dateFormat.format(lastAt.toLocal()),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: scheme.onSurface.withValues(alpha: 0.7),
                              ),
                            )
                          else
                            const SizedBox(height: 16),
                          if (thread.state.pinnedAt != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Icon(
                                Icons.push_pin_rounded,
                                size: 16,
                                color: scheme.primary,
                              ),
                            ),
                          if (thread.state.muted)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 4),
                              child: Icon(
                                Icons.volume_off_rounded,
                                size: 16,
                                color: scheme.onSurface.withValues(alpha: 0.58),
                              ),
                            ),
                          if (hasUnread)
                            Container(
                              margin: const EdgeInsets.symmetric(vertical: 3),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 7,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: scheme.primary,
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                unreadCount > 99 ? '99+' : '$unreadCount',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          if (appInAppCallsEnabled && !thread.isGroup)
                            IconButton(
                              tooltip: l10n.commonCall,
                              onPressed: () async {
                                await Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => SocialCallScreen(
                                      threadId: thread.id,
                                      isCaller: true,
                                      remoteDisplayName: remoteDisplayName,
                                    ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.call_outlined),
                              style: IconButton.styleFrom(
                                minimumSize: const Size(36, 36),
                                padding: EdgeInsets.zero,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      drawer: const MaslakiBasmayaDrawer(),
      appBar: MaslakiTopBar(
        title: l10n.socialChatThreadsTitle,
        subtitle: context.lt(
          ar: 'كل المحادثات الخاصة والعمل ضمن واجهة واحدة مرتبة.',
          en: 'Private and work threads in one organized surface.',
        ),
        leading: canPop
            ? IconButton(
                tooltip: l10n.commonBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : const MaslakiUserDrawerButton(openStartDrawer: true),
        actions: [
          if (canPop) const MaslakiUserDrawerButton(openStartDrawer: true),
          IconButton(
            tooltip: l10n.socialChatThreadsCreateGroupTooltip,
            onPressed: _openCreateGroupSheet,
            icon: const Icon(Icons.group_add_rounded),
          ),
          IconButton(
            tooltip: l10n.socialChatThreadsMessageRequests,
            onPressed: _openMessageRequests,
            icon: _ShellThreadActionBadgeIcon(
              icon: Icons.mark_chat_unread_outlined,
              count: _requestsCount,
            ),
          ),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _refreshThreads,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _openCreateGroupSheet,
        icon: const Icon(Icons.group_add_rounded),
        label: Text(l10n.socialChatThreadsCreateGroupCreate),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
            child: MaslakiSearchField(
              controller: _searchCtrl,
              hintText: l10n.socialChatThreadsSearchHint,
              onSubmitted: (_) => _refreshThreads(silent: true),
              trailing: _query.isEmpty
                  ? null
                  : IconButton(
                      tooltip: l10n.commonClear,
                      onPressed: _searchCtrl.clear,
                      icon: const Icon(Icons.close_rounded),
                    ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
            child: _ChatBucketSegmentedControl(
              selected: _threadBucket,
              privateCount: _countByBucket(threads, 'private'),
              workCount: _countByBucket(threads, 'work'),
              onSelect: (value) => setState(() => _threadBucket = value),
            ),
          ),
          _ChatThreadsFilterStrip(
            selected: _threadFilter,
            allCount: bucketFiltered.length,
            unreadCount: _countByFilter(
              bucketFiltered,
              unreadByThread,
              'unread',
            ),
            withMessagesCount: _countByFilter(
              bucketFiltered,
              unreadByThread,
              'with_messages',
            ),
            onSelect: (value) => setState(() => _threadFilter = value),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _refreshThreads,
              child: buildListBody(),
            ),
          ),
        ],
      ),
    );
  }

  List<SocialChatThread> _applyThreadFilter(
    List<SocialChatThread> source,
    Map<int, int> unreadByThread,
  ) {
    switch (_threadFilter) {
      case 'unread':
        return source
            .where((thread) => (unreadByThread[thread.id] ?? 0) > 0)
            .toList(growable: false);
      case 'with_messages':
        return source
            .where(
              (thread) =>
                  thread.lastMessage != null &&
                  thread.lastMessage!.previewText.trim().isNotEmpty,
            )
            .toList(growable: false);
      default:
        return source;
    }
  }

  int _countByFilter(
    List<SocialChatThread> source,
    Map<int, int> unreadByThread,
    String filter,
  ) {
    switch (filter) {
      case 'unread':
        return source
            .where((thread) => (unreadByThread[thread.id] ?? 0) > 0)
            .length;
      case 'with_messages':
        return source
            .where(
              (thread) =>
                  thread.lastMessage != null &&
                  thread.lastMessage!.previewText.trim().isNotEmpty,
            )
            .length;
      default:
        return source.length;
    }
  }

  int _countByBucket(List<SocialChatThread> source, String bucket) {
    if (bucket == 'work') {
      return source.where((thread) => thread.threadKind == 'business').length;
    }
    return source.where((thread) => thread.threadKind != 'business').length;
  }
}

class _CreateGroupThreadSheet extends ConsumerStatefulWidget {
  const _CreateGroupThreadSheet();

  @override
  ConsumerState<_CreateGroupThreadSheet> createState() =>
      _CreateGroupThreadSheetState();
}

class _CreateGroupThreadSheetState
    extends ConsumerState<_CreateGroupThreadSheet> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;
  bool _loading = true;
  bool _creating = false;
  String? _error;
  List<SocialUserSearchResult> _results = const <SocialUserSearchResult>[];
  final Set<int> _selectedUserIds = <int>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadUsers);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _titleController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadUsers({String search = ''}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .searchUsers(search: search, limit: search.trim().isEmpty ? 28 : 50);
      final me = ref.read(authControllerProvider).user?.id;
      final users = List<dynamic>.from(out['users'] ?? const <dynamic>[])
          .map(
            (entry) => SocialUserSearchResult.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .where((entry) => me == null || entry.user.id != me)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _results = users;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.socialChatThreadsCreateGroupLoadFailed,
        );
      });
    }
  }

  void _scheduleSearch(String value) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 280),
      () => _loadUsers(search: value.trim()),
    );
  }

  Future<void> _create() async {
    final l10n = context.l10n;
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = l10n.socialChatThreadsCreateGroupNameRequired);
      return;
    }
    if (_selectedUserIds.isEmpty) {
      setState(() => _error = l10n.socialChatThreadsCreateGroupMembersRequired);
      return;
    }
    setState(() {
      _creating = true;
      _error = null;
    });
    final thread = await ref
        .read(socialControllerProvider.notifier)
        .createGroupThread(
          title: title,
          memberIds: _selectedUserIds.toList(growable: false),
        );
    if (!mounted) return;
    setState(() => _creating = false);
    if (thread == null) {
      setState(() {
        _error =
            ref.read(socialControllerProvider).error ??
            l10n.socialChatThreadsCreateGroupFailed;
      });
      return;
    }
    Navigator.of(context).pop(thread);
  }

  @override
  Widget build(BuildContext context) {
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
                l10n.socialChatThreadsCreateGroupTitle,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: TextField(
                controller: _titleController,
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  hintText: l10n.socialChatThreadsCreateGroupNameHint,
                  prefixIcon: const Icon(Icons.group_rounded),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: TextField(
                controller: _searchController,
                onChanged: _scheduleSearch,
                decoration: InputDecoration(
                  hintText: l10n.socialChatThreadsCreateGroupSearchHint,
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _searchController.text.trim().isEmpty
                      ? null
                      : IconButton(
                          tooltip: l10n.commonClear,
                          onPressed: () {
                            _searchController.clear();
                            _loadUsers();
                          },
                          icon: const Icon(Icons.close_rounded),
                        ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: Text(
                l10n.socialChatThreadsCreateGroupSelectedCount(
                  _selectedUserIds.length,
                ),
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
            ),
            if ((_error ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Text(
                  _error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _results.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Text(
                          l10n.socialChatThreadsCreateGroupNoUsers,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: _results.length,
                      separatorBuilder: (_, separatorIndex) =>
                          const SizedBox(height: 8),
                      itemBuilder: (_, index) {
                        final result = _results[index];
                        final selected = _selectedUserIds.contains(
                          result.user.id,
                        );
                        return CheckboxListTile(
                          value: selected,
                          onChanged: (_) {
                            setState(() {
                              if (selected) {
                                _selectedUserIds.remove(result.user.id);
                              } else {
                                _selectedUserIds.add(result.user.id);
                              }
                            });
                          },
                          title: SocialIdentityView(author: result.user),
                          subtitle: Text(
                            result.user.phone ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          secondary: CircleAvatar(
                            backgroundImage:
                                (result.user.imageUrl ?? '').trim().isNotEmpty
                                ? AppCachedImageProvider(result.user.imageUrl!)
                                : null,
                            child: (result.user.imageUrl ?? '').trim().isEmpty
                                ? const Icon(Icons.person_outline)
                                : null,
                          ),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              child: FilledButton.icon(
                onPressed: _creating ? null : _create,
                icon: _creating
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.group_add_rounded),
                label: Text(l10n.socialChatThreadsCreateGroupCreate),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChatBucketSegmentedControl extends StatelessWidget {
  final String selected;
  final int privateCount;
  final int workCount;
  final ValueChanged<String> onSelect;

  const _ChatBucketSegmentedControl({
    required this.selected,
    required this.privateCount,
    required this.workCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _ThreadBucketButton(
            label: context.l10n.socialChatThreadsBucketPrivate,
            count: privateCount,
            selected: selected == 'private',
            onTap: () => onSelect('private'),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ThreadBucketButton(
            label: context.l10n.socialChatThreadsBucketWork,
            count: workCount,
            selected: selected == 'work',
            onTap: () => onSelect('work'),
          ),
        ),
      ],
    );
  }
}

class _ThreadBucketButton extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _ThreadBucketButton({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: selected
              ? scheme.primary.withValues(alpha: 0.14)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.42),
          border: Border.all(
            color: selected
                ? scheme.primary.withValues(alpha: 0.35)
                : scheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? scheme.primary : scheme.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadMetaBadge extends StatelessWidget {
  final String label;

  const _ThreadMetaBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w800,
          fontSize: 11.5,
        ),
      ),
    );
  }
}

class _ChatThreadsFilterStrip extends StatelessWidget {
  final String selected;
  final int allCount;
  final int unreadCount;
  final int withMessagesCount;
  final ValueChanged<String> onSelect;

  const _ChatThreadsFilterStrip({
    required this.selected,
    required this.allCount,
    required this.unreadCount,
    required this.withMessagesCount,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 82,
      child: ListView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        children: [
          _ChatFilterCard(
            label: context.l10n.commonAll,
            count: allCount,
            selected: selected == 'all',
            onTap: () => onSelect('all'),
          ),
          const SizedBox(width: 8),
          _ChatFilterCard(
            label: context.l10n.socialChatThreadsFilterUnread,
            count: unreadCount,
            selected: selected == 'unread',
            onTap: () => onSelect('unread'),
          ),
          const SizedBox(width: 8),
          _ChatFilterCard(
            label: context.l10n.socialChatThreadsFilterWithMessages,
            count: withMessagesCount,
            selected: selected == 'with_messages',
            onTap: () => onSelect('with_messages'),
          ),
        ],
      ),
    );
  }
}

class _ShellThreadActionBadgeIcon extends StatelessWidget {
  final IconData icon;
  final int count;

  const _ShellThreadActionBadgeIcon({required this.icon, required this.count});

  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Icon(icon),
        if (count > 0)
          PositionedDirectional(
            end: -6,
            top: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.error,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                count > 99 ? '99+' : '$count',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onError,
                  fontSize: 9,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ChatFilterCard extends StatelessWidget {
  final String label;
  final int count;
  final bool selected;
  final VoidCallback onTap;

  const _ChatFilterCard({
    required this.label,
    required this.count,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Ink(
          width: 138,
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: selected
                ? scheme.primary.withValues(alpha: 0.2)
                : scheme.surfaceContainerHighest.withValues(alpha: 0.44),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: 0.34)
                  : Colors.transparent,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$count',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: selected ? scheme.primary : scheme.onSurface,
                ),
              ),
              const Spacer(),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? scheme.primary
                      : scheme.onSurface.withValues(alpha: 0.88),
                ),
              ),
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
