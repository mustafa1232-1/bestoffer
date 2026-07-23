import 'dart:async';

import 'package:dio/dio.dart';
import 'package:core_maps/core_maps.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:social_ui/social_scheduled_message_widgets.dart';
import 'package:social_ui/social_thread_theme.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/widgets/appbar_quick_actions.dart';
import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/media/media_cache_models.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/notifications/active_chat_context_registry.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/data/notifications_api.dart';
import '../../notifications/state/notifications_controller.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../models/social_pending_message.dart';
import '../state/social_controller.dart';
import 'social_call_screen.dart';
import 'social_content_navigation.dart';
import 'social_profile_screen.dart';
import 'social_story_quick_viewer.dart';
import 'widgets/social_business_context_banner.dart';
import 'widgets/social_attachment_preview_card.dart';
import 'widgets/social_group_thread_sheet.dart';
import 'widgets/social_identity_view.dart';
import 'widgets/social_inline_attachment_message_card.dart';
import 'widgets/social_mention_hashtag_text.dart';
import 'widgets/social_pending_message_bubble.dart';
import 'widgets/social_shared_reel_message_card.dart';
import 'widgets/social_voice_composer_controller.dart';
import 'widgets/social_voice_message_widgets.dart';
import 'social_message_client_id.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

final _liveNotificationsApiProvider = Provider<NotificationsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return NotificationsApi(
    dio,
    realtime: ref.read(maslakiRealtimeServiceProvider),
  );
});

enum _ChatRealtimeStatus { connecting, connected, reconnecting, offline }

const Duration _kMessageEditDeleteWindow = Duration(minutes: 5);
const Duration _kChatFallbackPollInterval = Duration(seconds: 5);
const int _kChatConnectedSyncEveryTicks = 9;
const Duration _kTypingStateEmitThrottle = Duration(milliseconds: 900);

enum _ChatComposerAttachmentAction { image, video, file, location }

String? _socialChatErrorCode(Object error) {
  if (error is DioException) {
    final data = error.response?.data;
    if (data is Map) {
      final rawCode =
          data['code'] ?? data['errorCode'] ?? data['message'] ?? data['error'];
      final code = '$rawCode'.trim().toUpperCase();
      if (code.isNotEmpty) return code;
    }
    final statusMessage = error.response?.statusMessage?.trim().toUpperCase();
    if (statusMessage != null && statusMessage.isNotEmpty) {
      return statusMessage;
    }
  }
  final text = error.toString().trim().toUpperCase();
  return text.isEmpty ? null : text;
}

bool socialChatShouldRecoverMissingThread(
  Object error, {
  required bool hasPeerUserId,
  required bool recoveryAttempted,
}) {
  if (!hasPeerUserId || recoveryAttempted) return false;
  if (error is DioException) {
    final code = error.response?.statusCode;
    final apiCode = _socialChatErrorCode(error);
    if (code == 404) return true;
    if (code == 403 &&
        (apiCode == 'THREAD_NOT_FOUND' ||
            apiCode == 'CHAT_REQUEST_UNAVAILABLE')) {
      return true;
    }
  }
  final text = error.toString().toUpperCase();
  return text.contains('THREAD_NOT_FOUND') ||
      text.contains('CHAT_REQUEST_UNAVAILABLE');
}

bool socialChatIsRelationRequiredThreadError(Object error) {
  final apiCode = _socialChatErrorCode(error);
  if (apiCode == 'RELATION_REQUIRED' ||
      apiCode == 'RELATION_BLOCKED' ||
      apiCode == 'CHAT_REQUEST_PENDING') {
    return true;
  }
  final text = error.toString().toUpperCase();
  return text.contains('RELATION_REQUIRED') ||
      text.contains('RELATION_BLOCKED') ||
      text.contains('CHAT_REQUEST_PENDING');
}

bool socialChatShouldLockComposer({
  required bool readOnly,
  required bool monitorMode,
  required bool pendingRequest,
  required bool accessBlocked,
}) {
  return readOnly || monitorMode || pendingRequest || accessBlocked;
}

/// شاشة thread الواحدة للمحادثات الاجتماعية، وتشمل الرسائل، المرفقات،
/// الردود، typing، read receipts، والـ realtime fallback.
class SocialChatThreadScreen extends ConsumerStatefulWidget {
  final int threadId;
  final String peerName;
  final String? peerPhone;
  final int? peerUserId;
  final String? peerImageUrl;
  final bool readOnly;
  final bool monitorMode;

  const SocialChatThreadScreen({
    super.key,
    required this.threadId,
    required this.peerName,
    this.peerPhone,
    this.peerUserId,
    this.peerImageUrl,
    this.readOnly = false,
    this.monitorMode = false,
  });

  @override
  ConsumerState<SocialChatThreadScreen> createState() =>
      _SocialChatThreadScreenState();
}

class _SocialChatThreadScreenState extends ConsumerState<SocialChatThreadScreen>
    with WidgetsBindingObserver {
  late final SocialApi _api;
  late final NotificationsApi _liveApi;

  final ScrollController _scrollController = ScrollController();
  final TextEditingController _inputController = TextEditingController();
  final TextEditingController _searchController = TextEditingController();
  double _lastViewInsetBottom = 0;
  final Map<int, GlobalKey> _messageItemKeys = <int, GlobalKey>{};

  bool get _isEnglishLocale =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'en';

  intl.DateFormat get _timeFormat =>
      intl.DateFormat('hh:mm a', _isEnglishLocale ? 'en' : 'ar');

  StreamSubscription<NotificationLiveEvent>? _liveSub;
  Timer? _pollTimer;
  Timer? _reconnectTimer;
  Timer? _typingStopTimer;
  Timer? _peerTypingResetTimer;
  Timer? _searchDebounceTimer;
  int _connectedPollTick = 0;
  _ChatRealtimeStatus _chatRealtimeStatus = _ChatRealtimeStatus.connecting;
  int _reconnectAttempt = 0;
  DateTime? _lastTypingEmitAt;
  bool? _lastTypingSent;
  bool _markReadInFlight = false;
  int? _queuedReadMessageId;
  int? _lastMarkedReadMessageId;

  List<SocialChatMessage> _messages = const [];
  List<SocialChatMessage> _pinnedMessages = const [];
  List<SocialScheduledChatMessage> _scheduledMessages = const [];
  SocialChatThread? _thread;
  final Set<int> _reactionBusyMessageIds = <int>{};
  final Set<int> _translationBusyMessageIds = <int>{};
  final Map<int, SocialChatMessageTranslation> _messageTranslations =
      <int, SocialChatMessageTranslation>{};
  int? _nextCursor;
  int? _lastEventId;
  int? _resolvedThreadId;
  bool _threadRecoveryAttempted = false;
  SocialChatReplyPreview? _replyingTo;
  LocalMediaFile? _attachmentDraft;
  SocialSharedEntity? _sharedEntityDraft;
  late final SocialVoiceComposerController _voiceComposer;
  late final LocalPendingMessageController _pendingMessagesController;
  bool _loading = false;
  bool _loadingMore = false;
  bool _sending = false;
  bool _showJumpToBottom = false;
  bool _typingActive = false;
  bool _peerTyping = false;
  String? _peerTypingActorName;
  bool _appInForeground = true;
  bool _composerHasText = false;
  bool _searchMode = false;
  bool _searchLoading = false;
  String? _error;
  bool _threadAccessBlocked = false;
  String? _searchError;
  String _searchQuery = '';
  int _searchResultIndex = 0;
  int? _highlightedMessageId;
  List<SocialChatMessage> _searchResults = const [];
  final Set<String> _cancelledPendingClientIds = <String>{};

  int? get _currentUserId => ref.read(authControllerProvider).user?.id;
  int get _threadId => _resolvedThreadId ?? widget.threadId;
  SocialAuthor get _widgetPeerAuthor => SocialAuthor(
    id: widget.peerUserId ?? 0,
    username: null,
    fullName: widget.peerName,
    imageUrl: widget.peerImageUrl,
    phone: widget.peerPhone,
    role: 'user',
  );
  SocialAuthor? get _currentUserAuthor {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return null;
    return SocialAuthor(
      id: user.id,
      username: null,
      fullName: user.fullName,
      imageUrl: user.imageUrl,
      phone: user.phone,
      role: user.role,
    );
  }

  Future<bool> _recoverMissingThread() async {
    final peerUserId = widget.peerUserId;
    if (peerUserId == null || peerUserId <= 0) return false;
    if (_threadRecoveryAttempted) return false;
    _threadRecoveryAttempted = true;
    try {
      final out = await _api.createThread(peerUserId);
      final threadMap = Map<String, dynamic>.from(out['thread'] as Map? ?? out);
      final recoveredThreadId = _parseInt(threadMap['id']);
      if (recoveredThreadId == null || recoveredThreadId <= 0) return false;
      if (!mounted) return false;
      setState(() {
        _resolvedThreadId = recoveredThreadId;
        _error = null;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  SocialAuthor get _resolvedPeer =>
      (_thread?.resolvedWithPeerFallback(_widgetPeerAuthor).peer ??
              _widgetPeerAuthor)
          .mergedWith(_widgetPeerAuthor);
  String get _resolvedPeerDisplayLabel =>
      socialPrimaryIdentityLabel(_resolvedPeer);
  String get _resolvedPeerOpenName => _resolvedPeer.fullName.trim().isNotEmpty
      ? _resolvedPeer.fullName.trim()
      : widget.peerName;
  String get _translationTargetLanguage => _isEnglishLocale ? 'ar' : 'en';
  SocialThreadVisualTheme get _threadVisualTheme => resolveSocialThreadTheme(
    Theme.of(context).colorScheme,
    _thread?.state.themeKey,
  );

  SocialChatMessage _resolveMessageForViewer(
    SocialChatMessage message, {
    int? currentUserId,
    SocialAuthor? currentUserAuthor,
    SocialAuthor? peerAuthor,
  }) {
    return message.resolvedForViewer(
      viewerUserId: currentUserId ?? _currentUserId,
      selfAuthor: currentUserAuthor ?? _currentUserAuthor,
      peerAuthor: peerAuthor ?? _resolvedPeer,
    );
  }

  bool _isMessageMine(SocialChatMessage message) {
    return _resolveMessageForViewer(message).isMine;
  }

  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
    _liveApi = ref.read(_liveNotificationsApiProvider);
    _voiceComposer = SocialVoiceComposerController()
      ..addListener(_handleVoiceComposerChanged);
    _pendingMessagesController = LocalPendingMessageController()
      ..addListener(_handlePendingMessagesChanged);
    WidgetsBinding.instance.addObserver(this);
    ActiveChatContextRegistry.enterSocialThread(_threadId);
    _scrollController.addListener(_handleScroll);
    _searchController.addListener(_handleSearchTextChanged);
    Future.microtask(_bootstrap);
  }

  void _handleVoiceComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _handlePendingMessagesChanged() {
    if (!mounted) return;
    setState(() {});
  }

  /// يجهز read-state الأولية، يحمل الرسائل، ثم يربط realtime/polling.
  Future<void> _bootstrap() async {
    await ref
        .read(notificationsControllerProvider.notifier)
        .markSocialChatNotificationsRead(threadId: _threadId);
    await _loadMessages(initial: true);
    await _loadScheduledMessages(silent: true);
    if (!mounted) return;
    if (!widget.monitorMode) {
      _connectRealtime();
    }
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(_kChatFallbackPollInterval, (_) {
      if (!mounted || !_appInForeground) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) {
        ActiveChatContextRegistry.leaveSocialThread(_threadId);
        return;
      }
      ActiveChatContextRegistry.enterSocialThread(_threadId);
      if (_chatRealtimeStatus == _ChatRealtimeStatus.connected) {
        _connectedPollTick =
            (_connectedPollTick + 1) % _kChatConnectedSyncEveryTicks;
        if (_connectedPollTick != 0) return;
      }
      _loadMessages(silent: true);
      _loadScheduledMessages(silent: true);
    });
  }

  Future<void> _loadScheduledMessages({bool silent = false}) async {
    if (widget.monitorMode) return;
    try {
      final out = await _api.listScheduledThreadMessages(_threadId);
      final raw = List<dynamic>.from(
        out['items'] ?? out['scheduledMessages'] ?? const [],
      );
      final items = raw
          .map(
            (e) => SocialScheduledChatMessage.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() => _scheduledMessages = items);
    } catch (_) {
      if (!silent) {
        // Keep scheduled messages best-effort to avoid blocking the thread UI.
      }
    }
  }

  SocialChatMessageTranslation? _translatedMessageFor(int messageId) =>
      _messageTranslations[messageId];

  String _themeLabel(BuildContext context, String key) {
    final l10n = context.l10n;
    switch (key) {
      case 'sunset':
        return l10n.socialChatThreadThemeSunset;
      case 'ocean':
        return l10n.socialChatThreadThemeOcean;
      case 'forest':
        return l10n.socialChatThreadThemeForest;
      case 'violet':
        return l10n.socialChatThreadThemeViolet;
      default:
        return l10n.socialChatThreadThemeDefault;
    }
  }

  Future<void> _toggleMessageTranslation(SocialChatMessage message) async {
    if (message.isDeleted || message.body.trim().isEmpty) return;
    final existing = _translatedMessageFor(message.id);
    if (existing != null) {
      setState(() {
        _messageTranslations.remove(message.id);
      });
      return;
    }
    if (_translationBusyMessageIds.contains(message.id)) return;
    setState(() {
      _translationBusyMessageIds.add(message.id);
    });
    try {
      final out = await _api.translateThreadMessage(
        threadId: _threadId,
        messageId: message.id,
        targetLanguage: _translationTargetLanguage,
      );
      final raw = out['translation'];
      if (raw is Map && mounted) {
        setState(() {
          _messageTranslations[message.id] =
              SocialChatMessageTranslation.fromJson(
                Map<String, dynamic>.from(raw),
              );
        });
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialChatThreadTranslationFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _translationBusyMessageIds.remove(message.id);
        });
      }
    }
  }

  Future<void> _openThemePicker() async {
    final currentKey = (_thread?.state.themeKey ?? 'default')
        .trim()
        .toLowerCase();
    final selectedKey = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(sheetContext.l10n.socialChatThreadThemePickerTitle),
            ),
            for (final key in socialThreadThemeKeys)
              ListTile(
                leading: Icon(
                  key == currentKey
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_off_rounded,
                ),
                title: Text(_themeLabel(sheetContext, key)),
                onTap: () => Navigator.of(sheetContext).pop(key),
              ),
          ],
        ),
      ),
    );
    if (!mounted ||
        selectedKey == null ||
        selectedKey.trim().toLowerCase() == currentKey) {
      return;
    }
    try {
      final out = await _api.setThreadTheme(
        threadId: _threadId,
        themeKey: selectedKey,
      );
      final threadRaw = out['thread'];
      final nextState = threadRaw is Map
          ? SocialChatThread.fromJson(Map<String, dynamic>.from(threadRaw))
          : _thread?.copyWith(
              state: _thread!.state.copyWith(
                themeKey: selectedKey.trim().toLowerCase(),
              ),
            );
      if (!mounted) return;
      setState(() {
        if (nextState != null) {
          _thread = nextState;
        }
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: context.l10n.socialChatThreadThemeUpdateFailed,
            ),
          ),
        ),
      );
    }
  }

  /// يحمل الرسائل الأولية أو incremental sync أو pagination الأقدم.
  ///
  /// Critical notes:
  /// - هذه الدالة هي نقطة دمج الرسائل بين initial load وlive refresh،
  ///   لذلك أي تعديل يجب أن يحافظ على ترتيب الرسائل وعدم duplications.
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
      final out = widget.monitorMode
          ? await _api.listAdminMonitoredThreadMessages(
              _threadId,
              limit: 40,
              beforeId: loadMore ? _nextCursor : null,
            )
          : await _api.listThreadMessages(
              _threadId,
              limit: 40,
              beforeId: loadMore ? _nextCursor : null,
            );
      final raw = List<dynamic>.from(out['messages'] as List? ?? const []);
      final pinnedRaw = List<dynamic>.from(
        out['pinnedMessages'] as List? ?? const [],
      );
      final threadRaw = out['thread'];
      final parsed = raw
          .map(
            (e) =>
                SocialChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);
      final pinnedParsed = pinnedRaw
          .map(
            (e) =>
                SocialChatMessage.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList(growable: false);

      if (!mounted) return;

      setState(() {
        _threadAccessBlocked = false;
        if (threadRaw is Map) {
          _thread = SocialChatThread.fromJson(
            Map<String, dynamic>.from(threadRaw),
          ).resolvedWithPeerFallback(_widgetPeerAuthor);
          final serverReadId = _thread?.state.lastReadMessageId;
          if (serverReadId != null &&
              (_lastMarkedReadMessageId == null ||
                  serverReadId > _lastMarkedReadMessageId!)) {
            _lastMarkedReadMessageId = serverReadId;
          }
        }
        _nextCursor = _parseInt(out['nextCursor']);
        if (pinnedRaw.isNotEmpty || !loadMore) {
          _setPinnedMessages(
            pinnedParsed
                .map((message) => _resolveMessageForViewer(message))
                .toList(growable: false),
          );
        }
        if (loadMore) {
          _messages = [
            ...parsed.map((message) => _resolveMessageForViewer(message)),
            ..._messages,
          ];
        } else if (initial) {
          _messages = parsed
              .map((message) => _resolveMessageForViewer(message))
              .toList(growable: false);
        } else {
          final merged = <int, SocialChatMessage>{};
          for (final m in _messages) {
            merged[m.id] = m;
          }
          for (final m in parsed) {
            merged[m.id] = _resolveMessageForViewer(m);
          }
          final ordered = merged.values.toList()
            ..sort((a, b) => a.id.compareTo(b.id));
          _messages = ordered;
        }
        _loading = false;
        _loadingMore = false;
      });

      if (!widget.monitorMode && !loadMore) {
        unawaited(_markThreadReadIfNeeded());
      }

      if (initial || (!loadMore && _isNearBottom(threshold: 260))) {
        _scrollToBottom(animated: !initial);
      }
    } catch (e) {
      if (!mounted) return;
      if (!loadMore &&
          socialChatShouldRecoverMissingThread(
            e,
            hasPeerUserId: widget.peerUserId != null && widget.peerUserId! > 0,
            recoveryAttempted: _threadRecoveryAttempted,
          ) &&
          await _recoverMissingThread()) {
        await _loadMessages(initial: initial, silent: silent, loadMore: false);
        return;
      }
      setState(() {
        _loading = false;
        _loadingMore = false;
        if (socialChatIsRelationRequiredThreadError(e)) {
          _threadAccessBlocked = true;
        }
        if (!silent) {
          _error = mapAnyError(
            e,
            fallback: context.l10n.socialChatThreadLoadFailed,
          );
        }
      });
    }
  }

  /// يربط الشاشة بقناة الإشعارات الحية الخاصة بالسوشال chat.
  ///
  /// Maintenance notes:
  /// - إذا توقفت الرسائل الجديدة عن الظهور افحص هذه الدالة مع
  ///   `NotificationsApi.stream` و`NotificationsController`.
  void _connectRealtime() {
    _setRealtimeStatus(
      _reconnectAttempt > 0
          ? _ChatRealtimeStatus.reconnecting
          : _ChatRealtimeStatus.connecting,
    );
    _liveSub?.cancel();
    _liveSub = _liveApi
        .streamThreadEvents(threadId: _threadId, lastEventId: _lastEventId)
        .listen(
          (event) {
            _reconnectAttempt = 0;
            _setRealtimeStatus(_ChatRealtimeStatus.connected);
            if (event.event == 'resync_required') {
              _lastEventId = _parseInt(event.data['latestEventId']);
              _loadMessages(silent: true);
              return;
            }

            final threadId = _parseInt(
              event.data['threadId'] ?? event.data['thread_id'],
            );
            if (threadId != _threadId) return;
            if (!_acceptRealtimeEventId(event.eventId)) return;

            if (event.event == 'social_chat_typing') {
              final actorUserId = _parseInt(
                event.data['actorUserId'] ?? event.data['actor_user_id'],
              );
              if (actorUserId == null || actorUserId == _currentUserId) return;
              _handlePeerTypingEvent(
                event.data['typing'] == true,
                actorName:
                    '${event.data['actorDisplayName'] ?? event.data['actor_display_name'] ?? ''}'
                        .trim(),
              );
              return;
            }

            if (event.event == 'social_chat_state') {
              _handleRealtimeStateEvent(event.data);
              return;
            }

            if (event.event == 'social_chat_scheduled_message') {
              _loadScheduledMessages(silent: true);
              return;
            }

            if (event.event == 'social_chat_thread_updated') {
              if (event.data['action'] == 'theme_updated') {
                final nextThemeKey =
                    '${event.data['themeKey'] ?? event.data['theme_key'] ?? ''}'
                        .trim()
                        .toLowerCase();
                if (nextThemeKey.isNotEmpty && mounted && _thread != null) {
                  setState(() {
                    _thread = _thread!.copyWith(
                      state: _thread!.state.copyWith(themeKey: nextThemeKey),
                    );
                  });
                }
                return;
              }
              final affectedUserIds = List<dynamic>.from(
                event.data['memberUserIds'] as List? ??
                    event.data['member_user_ids'] as List? ??
                    const <dynamic>[],
              );
              final currentUserId = _currentUserId;
              if ((event.data['action'] == 'member_removed' ||
                      event.data['action'] == 'member_left') &&
                  currentUserId != null &&
                  affectedUserIds.any(
                    (value) => int.tryParse('$value') == currentUserId,
                  )) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        context.l10n.socialChatThreadGroupRemovedFromGroup,
                      ),
                    ),
                  );
                  Navigator.of(context).maybePop();
                }
                return;
              }
              _loadMessages(silent: true);
              return;
            }

            if (event.event != 'social_chat_message') return;

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
            final rawMessage = event.data['message'];
            if (rawMessage is Map) {
              try {
                final parsed = SocialChatMessage.fromJson(
                  Map<String, dynamic>.from(rawMessage),
                );
                if (parsed.id > 0) {
                  _upsertRealtimeMessage(parsed);
                  return;
                }
              } catch (_) {
                // Fall back to API sync below.
              }
            }
            _loadMessages(silent: true);
          },
          onError: (error) {
            if (_isUnauthorized(error)) {
              _setRealtimeStatus(_ChatRealtimeStatus.offline);
              if (mounted) {
                setState(() {
                  _error = context.l10n.socialChatThreadSessionExpired;
                });
              }
              return;
            }
            _scheduleReconnect();
          },
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  bool _acceptRealtimeEventId(int? eventId) {
    if (eventId == null || eventId <= 0) return true;
    if (_lastEventId != null && eventId <= _lastEventId!) return false;
    _lastEventId = eventId;
    return true;
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

  void _handleRealtimeStateEvent(Map<String, dynamic> data) {
    final deliveredMessageId = _parseInt(
      data['lastDeliveredMessageId'] ?? data['last_delivered_message_id'],
    );
    final readMessageId = _parseInt(
      data['lastReadMessageId'] ?? data['last_read_message_id'],
    );
    final actorUserId = _parseInt(
      data['readerUserId'] ?? data['reader_user_id'],
    );
    if (deliveredMessageId == null && readMessageId == null) return;
    if (!mounted) return;
    setState(() {
      if (_thread != null) {
        _thread = _thread!.copyWith(
          state: _thread!.state.copyWith(
            lastDeliveredMessageId:
                deliveredMessageId ?? _thread!.state.lastDeliveredMessageId,
            lastReadMessageId:
                readMessageId ?? _thread!.state.lastReadMessageId,
          ),
        );
      }
      if (actorUserId == null || actorUserId == _currentUserId) {
        return;
      }
      _messages = _messages
          .map((message) {
            if (!_isMessageMine(message)) return message;
            final delivered = deliveredMessageId != null
                ? (message.deliveredToPeer || message.id <= deliveredMessageId)
                : message.deliveredToPeer;
            final read = readMessageId != null
                ? (message.readByPeer || message.id <= readMessageId)
                : message.readByPeer;
            return message.copyWith(
              deliveredToPeer: delivered,
              readByPeer: read,
            );
          })
          .toList(growable: false);
    });
  }

  int? _latestPeerMessageId([Iterable<SocialChatMessage>? source]) {
    final currentUserId = _currentUserId;
    if (currentUserId == null) return null;
    int? latestId;
    for (final message in source ?? _messages) {
      if (message.senderUserId == currentUserId) continue;
      if (latestId == null || message.id > latestId) {
        latestId = message.id;
      }
    }
    return latestId;
  }

  Future<void> _markThreadReadIfNeeded({int? messageId}) async {
    if (widget.monitorMode) return;
    final candidateMessageId = messageId ?? _latestPeerMessageId();
    if (candidateMessageId == null || candidateMessageId <= 0) return;
    if (_lastMarkedReadMessageId != null &&
        candidateMessageId <= _lastMarkedReadMessageId!) {
      return;
    }
    if (_markReadInFlight) {
      if (_queuedReadMessageId == null ||
          candidateMessageId > _queuedReadMessageId!) {
        _queuedReadMessageId = candidateMessageId;
      }
      return;
    }

    _markReadInFlight = true;
    try {
      final response = await _api.markThreadRead(threadId: _threadId);
      final acknowledgedId =
          _parseInt(
            response['lastReadMessageId'] ?? response['last_read_message_id'],
          ) ??
          candidateMessageId;
      if (_lastMarkedReadMessageId == null ||
          acknowledgedId > _lastMarkedReadMessageId!) {
        _lastMarkedReadMessageId = acknowledgedId;
      }
    } catch (_) {
      if (_queuedReadMessageId == null ||
          candidateMessageId > _queuedReadMessageId!) {
        _queuedReadMessageId = candidateMessageId;
      }
    } finally {
      _markReadInFlight = false;
      final queuedMessageId = _queuedReadMessageId;
      _queuedReadMessageId = null;
      if (queuedMessageId != null &&
          (_lastMarkedReadMessageId == null ||
              queuedMessageId > _lastMarkedReadMessageId!)) {
        unawaited(_markThreadReadIfNeeded(messageId: queuedMessageId));
      }
    }
  }

  void _upsertRealtimeMessage(SocialChatMessage next) {
    if (!mounted) return;
    final wasNearBottom = _isNearBottom(threshold: 260);
    final resolvedNext = _resolveMessageForViewer(next);
    final current = [..._messages];
    final index = current.indexWhere((m) => m.id == resolvedNext.id);
    if (index >= 0) {
      current[index] = resolvedNext;
    } else {
      current.add(resolvedNext);
    }
    current.sort((a, b) => a.id.compareTo(b.id));
    setState(() => _messages = current);
    if (!widget.monitorMode &&
        _currentUserId != null &&
        resolvedNext.senderUserId != _currentUserId) {
      unawaited(_markThreadReadIfNeeded(messageId: resolvedNext.id));
    }
    _syncPinnedMessage(resolvedNext);
    if (wasNearBottom) {
      _scrollToBottom(animated: true);
    }
  }

  void _setPinnedMessages(List<SocialChatMessage> messages) {
    final ordered = [...messages]
      ..sort((a, b) {
        final aTime = a.pinnedAt?.millisecondsSinceEpoch ?? 0;
        final bTime = b.pinnedAt?.millisecondsSinceEpoch ?? 0;
        if (aTime != bTime) return bTime.compareTo(aTime);
        return b.id.compareTo(a.id);
      });
    _pinnedMessages = ordered.take(3).toList(growable: false);
  }

  void _syncPinnedMessage(SocialChatMessage message) {
    if (!mounted) return;
    final current = [..._pinnedMessages];
    current.removeWhere((entry) => entry.id == message.id);
    if (message.pinnedAt != null && !message.isDeleted) {
      current.add(message);
    }
    setState(() => _setPinnedMessages(current));
  }

  void _handlePeerTypingEvent(bool typing, {String? actorName}) {
    _peerTypingResetTimer?.cancel();
    if (!typing) {
      if (mounted) {
        setState(() {
          _peerTyping = false;
          _peerTypingActorName = null;
        });
      }
      return;
    }
    if (mounted) {
      setState(() {
        _peerTyping = true;
        _peerTypingActorName = actorName;
      });
    }
    _peerTypingResetTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _peerTyping = false;
        _peerTypingActorName = null;
      });
    });
  }

  Future<void> _openGroupManagementSheet() async {
    final thread = _thread;
    if (thread == null || !thread.isGroup) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SocialGroupThreadSheet(
        initialThread: thread,
        onThreadUpdated: (nextThread) {
          if (!mounted) return;
          setState(() => _thread = nextThread);
        },
        onLeftGroup: () {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(context.l10n.socialChatThreadGroupLeaveSuccess),
            ),
          );
          Navigator.of(context).pop();
        },
      ),
    );
    if (!mounted) return;
    await _loadMessages(silent: true);
  }

  Future<void> _emitTyping(bool typing) async {
    if (widget.readOnly || widget.monitorMode) return;
    final now = DateTime.now();
    if (_lastTypingSent == typing &&
        _lastTypingEmitAt != null &&
        now.difference(_lastTypingEmitAt!) < _kTypingStateEmitThrottle) {
      return;
    }
    _lastTypingSent = typing;
    _lastTypingEmitAt = now;
    try {
      await _api.emitThreadTyping(threadId: _threadId, typing: typing);
    } catch (_) {}
  }

  void _stopTyping() {
    _typingStopTimer?.cancel();
    if (!_typingActive) return;
    _typingActive = false;
    unawaited(_emitTyping(false));
  }

  void _handleComposerChanged(String value) {
    if (widget.readOnly || widget.monitorMode) return;
    final hasText = value.trim().isNotEmpty;
    if (_composerHasText != hasText) {
      _composerHasText = hasText;
      if (mounted) setState(() {});
    }
    if (!hasText) {
      _stopTyping();
      return;
    }
    if (!_typingActive) {
      _typingActive = true;
      unawaited(_emitTyping(true));
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), _stopTyping);
  }

  String _buildPresenceLabel() {
    final l10n = context.l10n;
    if (_peerTyping && (_thread?.presence.canSeeTypingIndicators ?? false)) {
      if (_thread?.isGroup == true &&
          (_peerTypingActorName ?? '').trim().isNotEmpty) {
        return l10n.socialChatThreadTypingBy(_peerTypingActorName!.trim());
      }
      return l10n.socialChatThreadTyping;
    }
    if (_thread?.isGroup == true) {
      return l10n.socialChatThreadsGroupMembersCount(
        _thread?.group?.memberCount ?? 0,
      );
    }
    final presence = _thread?.presence;
    if (presence == null) return '';
    if (presence.canSeeOnlineStatus && presence.isOnline) {
      return l10n.socialChatThreadOnlineNow;
    }
    if (presence.canSeeLastSeen && presence.lastSeenAt != null) {
      final lastSeen = presence.lastSeenAt!.toLocal();
      final now = DateTime.now();
      final sameDay =
          now.year == lastSeen.year &&
          now.month == lastSeen.month &&
          now.day == lastSeen.day;
      final format = intl.DateFormat(
        sameDay ? 'hh:mm a' : 'd MMM, hh:mm a',
        _isEnglishLocale ? 'en' : 'ar',
      );
      return l10n.socialChatThreadLastSeen(format.format(lastSeen));
    }
    return '';
  }

  void _scheduleReconnect() {
    if (!mounted || !_appInForeground) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 8);
    _setRealtimeStatus(_ChatRealtimeStatus.reconnecting);
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

  void _setRealtimeStatus(_ChatRealtimeStatus status) {
    if (!mounted) return;
    if (status != _ChatRealtimeStatus.connected) {
      _connectedPollTick = 0;
    }
    setState(() => _chatRealtimeStatus = status);
  }

  bool _isUnauthorized(Object error) {
    if (error is DioException) {
      final code = error.response?.statusCode;
      return code == 401 || code == 403;
    }
    return false;
  }

  /// يرسل الرسالة الحالية مع أي draft attachment/reply preview مرتبط.
  GlobalKey _messageKey(int messageId) {
    return _messageItemKeys.putIfAbsent(
      messageId,
      () => GlobalKey(debugLabel: 'chat_message_$messageId'),
    );
  }

  void _handleSearchTextChanged() {
    final query = _searchController.text.trim();
    if (query == _searchQuery) return;
    _searchDebounceTimer?.cancel();
    setState(() {
      _searchQuery = query;
      _searchError = null;
      if (query.isEmpty) {
        _searchResults = const [];
        _searchResultIndex = 0;
        _searchLoading = false;
        _highlightedMessageId = null;
      } else {
        _searchLoading = true;
      }
    });
    if (query.isEmpty) return;
    _searchDebounceTimer = Timer(
      const Duration(milliseconds: 280),
      () => unawaited(_runSearchQuery(query)),
    );
  }

  Future<void> _runSearchQuery(String query, {bool jumpToFirst = true}) async {
    final normalized = query.trim();
    if (normalized.isEmpty) return;
    try {
      final out = await _api.searchThreadMessages(
        _threadId,
        search: normalized,
        limit: 40,
      );
      final raw = List<dynamic>.from(out['messages'] as List? ?? const []);
      final parsed = raw
          .map(
            (entry) => SocialChatMessage.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted || normalized != _searchQuery) return;
      setState(() {
        _searchLoading = false;
        _searchError = null;
        _searchResults = parsed
            .map((message) => _resolveMessageForViewer(message))
            .toList(growable: false);
        if (parsed.isEmpty) {
          _searchResultIndex = 0;
          _highlightedMessageId = null;
        } else if (_searchResultIndex >= parsed.length) {
          _searchResultIndex = 0;
        }
      });
      if (jumpToFirst && parsed.isNotEmpty) {
        await _focusSearchResult(0);
      }
    } catch (error) {
      if (!mounted || normalized != _searchQuery) return;
      setState(() {
        _searchLoading = false;
        _searchResults = const [];
        _searchError = mapAnyError(
          error,
          fallback: context.l10n.socialChatThreadSearchLoadFailed,
        );
      });
    }
  }

  Future<bool> _ensureMessageLoaded(int messageId) async {
    if (_messages.any((message) => message.id == messageId)) return true;
    await _loadMessagesAroundMessage(messageId);
    if (_messages.any((message) => message.id == messageId)) return true;
    var guard = 0;
    while (mounted &&
        !_messages.any((message) => message.id == messageId) &&
        _nextCursor != null &&
        guard < 120) {
      final previousCount = _messages.length;
      await _loadMessages(loadMore: true);
      guard += 1;
      if (_messages.length == previousCount) break;
    }
    return _messages.any((message) => message.id == messageId);
  }

  Future<void> _loadMessagesAroundMessage(int messageId) async {
    if (messageId <= 0) return;
    try {
      final beforeId = messageId + 1;
      final out = widget.monitorMode
          ? await _api.listAdminMonitoredThreadMessages(
              _threadId,
              limit: 40,
              beforeId: beforeId,
            )
          : await _api.listThreadMessages(
              _threadId,
              limit: 40,
              beforeId: beforeId,
            );
      final raw = List<dynamic>.from(out['messages'] as List? ?? const []);
      if (raw.isEmpty || !mounted) return;
      final parsed = raw
          .map(
            (entry) => SocialChatMessage.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false);
      final pinnedRaw = List<dynamic>.from(
        out['pinnedMessages'] as List? ?? const [],
      );
      final pinnedParsed = pinnedRaw
          .map(
            (entry) => SocialChatMessage.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false);
      final threadRaw = out['thread'];
      setState(() {
        if (threadRaw is Map) {
          _thread = SocialChatThread.fromJson(
            Map<String, dynamic>.from(threadRaw),
          ).resolvedWithPeerFallback(_widgetPeerAuthor);
        }
        if (pinnedParsed.isNotEmpty) {
          _setPinnedMessages(
            pinnedParsed
                .map((message) => _resolveMessageForViewer(message))
                .toList(growable: false),
          );
        }
        final merged = <int, SocialChatMessage>{};
        for (final message in _messages) {
          merged[message.id] = message;
        }
        for (final message in parsed) {
          merged[message.id] = _resolveMessageForViewer(message);
        }
        final ordered = merged.values.toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        _messages = ordered;
      });
    } catch (_) {
      // Fallback pagination path in _ensureMessageLoaded will continue.
    }
  }

  Future<void> _focusMessageById(int messageId) async {
    final found = await _ensureMessageLoaded(messageId);
    if (!mounted || !found) return;
    setState(() => _highlightedMessageId = messageId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final itemContext = _messageKey(messageId).currentContext;
      if (itemContext != null) {
        Scrollable.ensureVisible(
          itemContext,
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          alignment: 0.18,
        );
      }
    });
  }

  Future<void> _focusSearchResult(int index) async {
    if (_searchResults.isEmpty) return;
    final safeIndex = index.clamp(0, _searchResults.length - 1);
    final targetMessage = _searchResults[safeIndex];
    setState(() {
      _searchResultIndex = safeIndex;
    });
    await _focusMessageById(targetMessage.id);
  }

  Future<void> _focusNextSearchResult(int step) async {
    if (_searchResults.isEmpty) return;
    final length = _searchResults.length;
    final nextIndex = (_searchResultIndex + step) % length;
    final normalized = nextIndex < 0 ? nextIndex + length : nextIndex;
    await _focusSearchResult(normalized);
  }

  void _openSearchMode() {
    setState(() {
      _searchMode = true;
      _searchError = null;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _searchController.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _searchController.text.length,
      );
    });
  }

  void _closeSearchMode() {
    _searchDebounceTimer?.cancel();
    _searchController.clear();
    FocusScope.of(context).unfocus();
    setState(() {
      _searchMode = false;
      _searchLoading = false;
      _searchError = null;
      _searchResults = const [];
      _searchResultIndex = 0;
      _highlightedMessageId = null;
    });
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    final sharedDraft = _sharedEntityDraft;
    if ((text.isEmpty &&
            _attachmentDraft == null &&
            _voiceComposer.state.draft == null &&
            sharedDraft == null) ||
        _sending ||
        widget.readOnly) {
      return;
    }

    final attachmentFile = _voiceComposer.state.draft?.file ?? _attachmentDraft;
    final attachmentDurationMs = _voiceComposer.state.draft?.durationMs;
    final clientMessageId = buildSocialMessageClientId(
      scopeKey: 'thread:$_threadId',
      body: text,
      replyToMessageId: _replyingTo?.id,
      attachmentFile: attachmentFile,
      attachmentDurationMs: attachmentDurationMs,
      sharedEntityType: sharedDraft?.type,
      sharedEntityId: sharedDraft?.id,
      sharedSnapshot: sharedDraft?.snapshot,
    );
    final pending = _enqueuePendingMessage(
      clientMessageId: clientMessageId,
      body: text,
      attachmentFile: attachmentFile,
      attachmentDurationMs: attachmentDurationMs,
      replyToMessageId: _replyingTo?.id,
      sharedEntityType: sharedDraft?.type,
      sharedEntityId: sharedDraft?.id,
      sharedSnapshot: sharedDraft?.snapshot,
    );

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      _stopTyping();
      final out = await _api.sendThreadMessage(
        _threadId,
        text,
        replyToMessageId: _replyingTo?.id,
        attachmentFile: attachmentFile,
        attachmentDurationMs: attachmentDurationMs,
        sharedEntityType: sharedDraft?.type,
        sharedEntityId: sharedDraft?.id,
        sharedSnapshot: sharedDraft?.snapshot,
        clientMessageId: clientMessageId,
      );
      if (_cancelledPendingClientIds.contains(clientMessageId)) return;
      _applySentMessage(out);
      _inputController.clear();
      _composerHasText = false;
      _replyingTo = null;
      _attachmentDraft = null;
      if (_voiceComposer.state.draft != null) {
        await _voiceComposer.discardDraft();
      }
      _sharedEntityDraft = null;
      _scrollToBottom();
    } catch (e) {
      if (!mounted) return;
      _pendingMessagesController.markFailed(
        pending.clientMessageId,
        errorCode: _socialChatErrorCode(e),
      );
      setState(() {
        _error = mapAnyError(
          e,
          fallback: sharedDraft?.type == 'location'
              ? context.l10n.socialChatThreadLocationShareFailed
              : context.l10n.socialChatThreadSendFailed,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _pickAttachment(_ChatComposerAttachmentAction action) async {
    if (_sending || widget.readOnly || _voiceComposerBusy) return;
    final l10n = context.l10n;
    try {
      if (action == _ChatComposerAttachmentAction.location) {
        final draft = await _buildLocationDraft();
        if (!mounted || draft == null) return;
        setState(() {
          _sharedEntityDraft = draft;
          _attachmentDraft = null;
        });
        return;
      }
      final file = switch (action) {
        _ChatComposerAttachmentAction.image => await pickChatImageFromDevice(),
        _ChatComposerAttachmentAction.video => await pickChatVideoFromDevice(),
        _ChatComposerAttachmentAction.file => await pickChatFileFromDevice(),
        _ChatComposerAttachmentAction.location => null,
      };
      if (!mounted || file == null) return;
      setState(() {
        _attachmentDraft = file;
        _sharedEntityDraft = null;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.socialChatThreadAttachmentPickFailed),
          ),
        ),
      );
    }
  }

  Future<void> _handleVoiceLifecyclePause() async {
    final l10n = context.l10n;
    final result = await _voiceComposer.handleAppPause();
    _handleVoiceResult(
      result,
      fallbackMessage: l10n.socialChatThreadVoiceMessageRecordFailed,
    );
  }

  bool get _voiceComposerBusy =>
      _voiceComposer.state.isRecording ||
      _voiceComposer.state.hasPreview ||
      _voiceComposer.state.isSending;

  Future<void> _startVoiceHold() async {
    if (_sending ||
        widget.readOnly ||
        _attachmentDraft != null ||
        _voiceComposerBusy) {
      return;
    }
    final l10n = context.l10n;
    final result = await _voiceComposer.startHolding(
      draftKey: 'thread_${_threadId}_voice',
    );
    if (result.type == SocialVoiceComposerResultType.started) {
      setState(() => _attachmentDraft = null);
      HapticFeedback.mediumImpact();
      return;
    }
    _handleVoiceResult(
      result,
      fallbackMessage: l10n.socialChatThreadVoiceMessageRecordFailed,
    );
  }

  void _updateVoiceHoldDrag(LongPressMoveUpdateDetails details) {
    if (_voiceComposer.state.phase != SocialVoiceComposerPhase.holding) return;
    if (details.offsetFromOrigin.dy <= -56) {
      final result = _voiceComposer.lock();
      if (result.type == SocialVoiceComposerResultType.locked) {
        HapticFeedback.mediumImpact();
      }
    }
  }

  void _applySentMessage(Map<String, dynamic> out) {
    final raw = out['message'];
    if (raw is! Map) return;
    final message = SocialChatMessage.fromJson(Map<String, dynamic>.from(raw));
    if (!mounted) return;
    setState(() {
      final clientId = (message.clientMessageId ?? '').trim();
      if (clientId.isNotEmpty) {
        _cancelledPendingClientIds.remove(clientId);
      }
      _pendingMessagesController.reconcileServerMessage(message);
      _messages = upsertSocialChatMessage(_messages, message);
    });
  }

  Future<void> _retryPendingMessage(LocalPendingMessage pending) async {
    if (_sending || widget.readOnly) return;
    final clientMessageId = pending.clientMessageId.trim();
    if (clientMessageId.isEmpty ||
        _cancelledPendingClientIds.contains(clientMessageId)) {
      return;
    }

    final sharedDraft = pending.sharedEntityType == null
        ? null
        : SocialSharedEntity(
            type: pending.sharedEntityType!,
            id: pending.sharedEntityId ?? 0,
            snapshot: pending.sharedSnapshot,
          );
    final attachmentFile = pending.localFile;
    setState(() {
      _sending = true;
      _error = null;
    });
    _pendingMessagesController.retry(clientMessageId);

    try {
      _stopTyping();
      final out = await _api.sendThreadMessage(
        _threadId,
        pending.body,
        replyToMessageId: pending.replyToMessageId,
        attachmentFile: attachmentFile,
        attachmentDurationMs: pending.durationMs,
        sharedEntityType: sharedDraft?.type,
        sharedEntityId: sharedDraft?.id,
        sharedSnapshot: sharedDraft?.snapshot,
        clientMessageId: clientMessageId,
      );
      if (!mounted || _cancelledPendingClientIds.contains(clientMessageId)) {
        return;
      }
      _applySentMessage(out);
      if (_replyingTo?.id == pending.replyToMessageId) {
        _replyingTo = null;
      }
      _attachmentDraft = null;
      if (_voiceComposer.state.draft != null &&
          _voiceComposer.state.draft?.file.path == attachmentFile?.path) {
        await _voiceComposer.discardDraft();
      }
      _sharedEntityDraft = null;
      _inputController.clear();
      _composerHasText = false;
      _scrollToBottom();
      _pendingMessagesController.markSent(clientMessageId);
    } catch (e) {
      if (!mounted || _cancelledPendingClientIds.contains(clientMessageId)) {
        return;
      }
      _pendingMessagesController.markFailed(
        clientMessageId,
        errorCode: _socialChatErrorCode(e),
      );
      setState(() {
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialChatThreadSendFailed,
        );
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _cancelPendingMessage(LocalPendingMessage pending) async {
    final clientMessageId = pending.clientMessageId.trim();
    if (clientMessageId.isEmpty) return;
    _cancelledPendingClientIds.add(clientMessageId);
    _pendingMessagesController.cancel(clientMessageId);
    if (_voiceComposer.state.draft != null &&
        _voiceComposer.state.draft?.file.path == pending.localFile?.path) {
      await _voiceComposer.discardDraft();
    }
    if (!mounted) return;
    setState(() {
      if (_replyingTo?.id == pending.replyToMessageId) {
        _replyingTo = null;
      }
      _attachmentDraft = null;
      _sharedEntityDraft = null;
      _inputController.clear();
      _composerHasText = false;
      _error = null;
    });
  }

  LocalPendingMessage _enqueuePendingMessage({
    required String clientMessageId,
    required String body,
    required LocalMediaFile? attachmentFile,
    required int? attachmentDurationMs,
    required int? replyToMessageId,
    String? sharedEntityType,
    int? sharedEntityId,
    Map<String, dynamic>? sharedSnapshot,
  }) {
    final pending = _pendingMessagesController.enqueue(
      clientMessageId: clientMessageId,
      threadId: _threadId,
      kind: attachmentFile == null
          ? 'text'
          : pendingAttachmentKindForFile(attachmentFile),
      localFile: attachmentFile,
      body: body,
      durationMs: attachmentDurationMs,
      replyToMessageId: replyToMessageId,
      sharedEntityType: sharedEntityType,
      sharedEntityId: sharedEntityId,
      sharedSnapshot: sharedSnapshot,
    );
    _pendingMessagesController.markUploading(clientMessageId);
    _cancelledPendingClientIds.remove(clientMessageId);
    return pending;
  }

  Future<void> _finishVoiceHold() async {
    final l10n = context.l10n;
    final result = await _voiceComposer.releaseHoldToPreview();
    _handleVoiceResult(
      result,
      fallbackMessage: l10n.socialChatThreadVoiceMessageRecordFailed,
    );
  }

  Future<void> _stopLockedVoiceRecording() async {
    final l10n = context.l10n;
    final result = await _voiceComposer.stopLockedRecordingToPreview();
    _handleVoiceResult(
      result,
      fallbackMessage: l10n.socialChatThreadVoiceMessageRecordFailed,
    );
  }

  Future<void> _cancelVoiceComposer() async {
    await _voiceComposer.cancelRecording();
  }

  Future<void> _sendVoiceDraft() async {
    final l10n = context.l10n;
    final result = await _voiceComposer.sendDraft((draft) async {
      final clientMessageId = buildSocialMessageClientId(
        scopeKey: 'thread:$_threadId',
        body: '',
        replyToMessageId: _replyingTo?.id,
        attachmentFile: draft.file,
        attachmentDurationMs: draft.durationMs,
      );
      final pending = _enqueuePendingMessage(
        clientMessageId: clientMessageId,
        body: '',
        attachmentFile: draft.file,
        attachmentDurationMs: draft.durationMs,
        replyToMessageId: _replyingTo?.id,
      );
      final out = await _api.sendThreadMessage(
        _threadId,
        '',
        replyToMessageId: _replyingTo?.id,
        attachmentFile: draft.file,
        attachmentDurationMs: draft.durationMs,
        clientMessageId: clientMessageId,
      );
      if (_cancelledPendingClientIds.contains(clientMessageId)) return;
      _applySentMessage(out);
      _replyingTo = null;
      _scrollToBottom();
      _pendingMessagesController.markSent(pending.clientMessageId);
    });
    if (result.type == SocialVoiceComposerResultType.failed) {
      final draft = _voiceComposer.state.draft;
      final Object voiceError = result.error ?? StateError('VOICE_SEND_FAILED');
      if (draft != null) {
        final pendingId = buildSocialMessageClientId(
          scopeKey: 'thread:$_threadId',
          body: '',
          replyToMessageId: _replyingTo?.id,
          attachmentFile: draft.file,
          attachmentDurationMs: draft.durationMs,
        );
        if (!_cancelledPendingClientIds.contains(pendingId) &&
            _pendingMessagesController.contains(pendingId)) {
          _pendingMessagesController.markFailed(
            pendingId,
            errorCode: _socialChatErrorCode(voiceError),
          );
        }
      }
      if (!mounted) return;
      setState(() {
        _error = mapAnyError(
          voiceError,
          fallback: l10n.socialChatThreadVoiceMessageSendFailed,
        );
      });
    }
  }

  Future<void> _scheduleCurrentDraft() async {
    if (_sending || widget.readOnly) return;
    final l10n = context.l10n;
    final text = _inputController.text.trim();
    final voiceDraft = _voiceComposer.state.draft;
    final attachmentFile = voiceDraft?.file ?? _attachmentDraft;
    final attachmentDurationMs = voiceDraft?.durationMs;
    if (text.isEmpty && attachmentFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.socialChatThreadScheduleRequiresContent)),
      );
      return;
    }
    final scheduledFor = await pickSocialScheduledDateTime(context);
    if (!mounted || scheduledFor == null) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await _api.scheduleThreadMessage(
        _threadId,
        text,
        scheduledFor: scheduledFor,
        replyToMessageId: _replyingTo?.id,
        attachmentFile: attachmentFile,
        attachmentDurationMs: attachmentDurationMs,
      );
      _inputController.clear();
      _replyingTo = null;
      _attachmentDraft = null;
      if (voiceDraft != null) {
        await _voiceComposer.discardDraft();
      }
      await _loadScheduledMessages(silent: true);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.socialChatThreadMessageScheduled)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapAnyError(e, fallback: l10n.socialChatThreadScheduleFailed);
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _cancelScheduledMessage(int scheduledMessageId) async {
    try {
      await _api.cancelScheduledThreadMessage(
        threadId: _threadId,
        scheduledMessageId: scheduledMessageId,
      );
      if (!mounted) return;
      setState(() {
        _scheduledMessages = _scheduledMessages
            .where((item) => item.id != scheduledMessageId)
            .toList(growable: false);
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.socialChatThreadCancelScheduledFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openAttachmentsMenu() async {
    if (_sending || widget.readOnly || _voiceComposerBusy) return;
    final l10n = context.l10n;
    final action = await showModalBottomSheet<_ChatComposerAttachmentAction>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.location_on_outlined),
              title: Text(l10n.socialChatThreadShareLocation),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_ChatComposerAttachmentAction.location),
            ),
            ListTile(
              leading: const Icon(Icons.insert_drive_file_outlined),
              title: Text(l10n.commonFile),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_ChatComposerAttachmentAction.file),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: Text(l10n.commonImage),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_ChatComposerAttachmentAction.image),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: Text(l10n.commonVideo),
              onTap: () => Navigator.of(
                sheetContext,
              ).pop(_ChatComposerAttachmentAction.video),
            ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    await _pickAttachment(action);
  }

  Future<void> _openStickersGifMenu() async {
    if (_sending || widget.readOnly || _voiceComposerBusy) return;
    final selectedText = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
              child: Row(
                children: [
                  Text(
                    _isEnglishLocale ? 'Stickers & GIF' : 'الملصقات و GIF',
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ['ðŸ˜€', 'ðŸ˜', 'ðŸ”¥', 'ðŸ‘', 'ðŸ‘', 'ðŸ’¯']
                  .map(
                    (emoji) => InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => Navigator.of(sheetContext).pop(emoji),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Text(
                          emoji,
                          style: const TextStyle(fontSize: 28),
                        ),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
            const SizedBox(height: 14),
            TextButton.icon(
              onPressed: () {
                Navigator.of(sheetContext).pop();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      _isEnglishLocale
                          ? 'GIF requires Tenor configuration.'
                          : 'ميزة GIF تحتاج إعداد Tenor.',
                    ),
                  ),
                );
              },
              icon: const Icon(Icons.gif_box_outlined),
              label: Text(_isEnglishLocale ? 'Open GIF' : 'فتح GIF'),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || (selectedText ?? '').trim().isEmpty) return;
    final current = _inputController.text;
    final prefix = current.trim().isEmpty ? '' : '$current ';
    _inputController.value = TextEditingValue(
      text: '$prefix${selectedText!.trim()}',
      selection: TextSelection.collapsed(
        offset: '$prefix${selectedText.trim()}'.length,
      ),
    );
    _composerHasText = _inputController.text.trim().isNotEmpty;
    if (mounted) setState(() {});
  }

  Future<SocialSharedEntity?> _buildLocationDraft() async {
    if (_sending || widget.readOnly || _voiceComposerBusy) return null;
    final l10n = context.l10n;
    final service = ref.read(locationPermissionServiceProvider);
    var status = await service.getStatus();
    if (!status.isGranted || !status.serviceEnabled) {
      status = await service.requestPermission();
    }
    if (!status.serviceEnabled || !status.isGranted) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(l10n.socialChatThreadLocationPermissionRequired),
        ),
      );
      return null;
    }
    final position = await service.getCurrentPosition();
    if (position == null) {
      if (!mounted) return null;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.socialChatThreadLocationShareFailed)),
      );
      return null;
    }
    final lat = position.latitude;
    final lng = position.longitude;
    return SocialSharedEntity(
      type: 'location',
      id: DateTime.now().millisecondsSinceEpoch,
      snapshot: <String, dynamic>{
        'title': l10n.socialChatThreadCurrentLocation,
        'address': '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
        'latitude': lat,
        'longitude': lng,
      },
    );
  }

  void _handleVoiceResult(
    SocialVoiceComposerResult result, {
    required String fallbackMessage,
  }) {
    if (!mounted) return;
    switch (result.type) {
      case SocialVoiceComposerResultType.permissionDenied:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.socialChatThreadMicrophonePermissionDenied,
            ),
          ),
        );
        break;
      case SocialVoiceComposerResultType.tooShort:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n.socialChatThreadVoiceMessageTooShort),
          ),
        );
        break;
      case SocialVoiceComposerResultType.failed:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mapAnyError(
                result.error ?? StateError('VOICE_FAILED'),
                fallback: fallbackMessage,
              ),
            ),
          ),
        );
        break;
      default:
        break;
    }
  }

  void _setReplyTo(SocialChatMessage message) {
    if (widget.readOnly) return;
    setState(() {
      _replyingTo = SocialChatReplyPreview(
        id: message.id,
        senderUserId: message.senderUserId,
        senderUsername: message.sender.username,
        senderFullName: message.sender.fullName,
        body: message.body,
        attachmentKind: message.attachment?.kind,
        attachmentName: message.attachment?.name,
      );
    });
  }

  bool _isWithinEditDeleteWindow(SocialChatMessage message) {
    final createdAt = message.createdAt;
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt.toLocal()) <=
        _kMessageEditDeleteWindow;
  }

  bool _canEditMessage(SocialChatMessage message) {
    return _isMessageMine(message) &&
        !message.isDeleted &&
        _isWithinEditDeleteWindow(message);
  }

  bool _canDeleteMessage(SocialChatMessage message) {
    return _isMessageMine(message) &&
        !message.isDeleted &&
        _isWithinEditDeleteWindow(message);
  }

  Future<void> _editMessage(SocialChatMessage message) async {
    if (!_canEditMessage(message)) return;
    final l10n = context.l10n;
    final controller = TextEditingController(text: message.body);
    final shouldSave = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.socialChatThreadEditMessage),
        content: TextField(
          controller: controller,
          minLines: 2,
          maxLines: 6,
          textInputAction: TextInputAction.done,
          textDirection: Directionality.of(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonSave),
          ),
        ],
      ),
    );
    if (shouldSave != true) {
      controller.dispose();
      return;
    }
    final nextBody = controller.text.trim();
    controller.dispose();
    if (nextBody.isEmpty || nextBody == message.body.trim()) return;

    try {
      final out = await _api.updateThreadMessage(
        threadId: _threadId,
        messageId: message.id,
        body: nextBody,
      );
      final raw = out['message'];
      if (raw is! Map || !mounted) return;
      _upsertRealtimeMessage(
        SocialChatMessage.fromJson(Map<String, dynamic>.from(raw)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.socialChatThreadEditFailed),
            textDirection: Directionality.of(context),
          ),
        ),
      );
    }
  }

  Future<void> _deleteMessage(SocialChatMessage message) async {
    if (!_canDeleteMessage(message)) return;
    final l10n = context.l10n;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.socialChatThreadDeleteMessage),
        content: Text(
          l10n.socialChatThreadDeleteConfirm,
          textDirection: Directionality.of(context),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.commonDelete),
          ),
        ],
      ),
    );
    if (shouldDelete != true) return;

    try {
      final out = await _api.deleteThreadMessage(
        threadId: _threadId,
        messageId: message.id,
      );
      final raw = out['message'];
      if (raw is! Map || !mounted) return;
      _upsertRealtimeMessage(
        SocialChatMessage.fromJson(Map<String, dynamic>.from(raw)),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: l10n.socialChatThreadDeleteFailed),
            textDirection: Directionality.of(context),
          ),
        ),
      );
    }
  }

  Future<void> _pinMessage(SocialChatMessage message) async {
    final l10n = context.l10n;
    try {
      final out = await _api.pinThreadMessage(
        threadId: _threadId,
        messageId: message.id,
      );
      final rawMessage = out['message'];
      final rawPinned = List<dynamic>.from(
        out['pinnedMessages'] as List? ?? const [],
      );
      if (!mounted) return;
      if (rawMessage is Map) {
        final parsed = SocialChatMessage.fromJson(
          Map<String, dynamic>.from(rawMessage),
        );
        _patchMessage(parsed.id, (_) => parsed);
      }
      setState(() {
        _setPinnedMessages(
          rawPinned
              .map(
                (entry) => SocialChatMessage.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList(growable: false),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: l10n.socialChatThreadPinMessageFailed),
          ),
        ),
      );
    }
  }

  Future<void> _unpinMessage(SocialChatMessage message) async {
    final l10n = context.l10n;
    try {
      final out = await _api.unpinThreadMessage(
        threadId: _threadId,
        messageId: message.id,
      );
      final rawMessage = out['message'];
      final rawPinned = List<dynamic>.from(
        out['pinnedMessages'] as List? ?? const [],
      );
      if (!mounted) return;
      if (rawMessage is Map) {
        final parsed = SocialChatMessage.fromJson(
          Map<String, dynamic>.from(rawMessage),
        );
        _patchMessage(parsed.id, (_) => parsed);
      } else {
        _patchMessage(
          message.id,
          (current) => current.copyWith(pinnedAt: null, pinnedByUserId: null),
        );
      }
      setState(() {
        _setPinnedMessages(
          rawPinned
              .map(
                (entry) => SocialChatMessage.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList(growable: false),
        );
      });
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: l10n.socialChatThreadUnpinMessageFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openMessageActions(SocialChatMessage message) async {
    if (widget.readOnly) return;
    final canEdit = _canEditMessage(message);
    final canDelete = _canDeleteMessage(message);
    final canReact = !message.isDeleted;
    final canReply = !message.isDeleted;
    final canPin = !message.isDeleted;
    final canTranslate = !message.isDeleted && message.body.trim().isNotEmpty;
    if (!canEdit &&
        !canDelete &&
        !canReact &&
        !canReply &&
        !canPin &&
        !canTranslate) {
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canPin)
              ListTile(
                leading: Icon(
                  message.pinnedAt != null
                      ? Icons.push_pin_outlined
                      : Icons.push_pin_rounded,
                ),
                title: Text(
                  message.pinnedAt != null
                      ? context.l10n.socialChatThreadUnpinMessage
                      : context.l10n.socialChatThreadPinMessage,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  if (message.pinnedAt != null) {
                    _unpinMessage(message);
                  } else {
                    _pinMessage(message);
                  }
                },
              ),
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(context.l10n.commonEdit),
                onTap: () {
                  Navigator.of(context).pop();
                  _editMessage(message);
                },
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(context.l10n.commonDelete),
                onTap: () {
                  Navigator.of(context).pop();
                  _deleteMessage(message);
                },
              ),
            if (canTranslate)
              ListTile(
                leading: Icon(
                  _translatedMessageFor(message.id) == null
                      ? Icons.translate_rounded
                      : Icons.translate_outlined,
                ),
                title: Text(
                  _translatedMessageFor(message.id) == null
                      ? context.l10n.socialChatThreadTranslateMessage
                      : context.l10n.socialChatThreadHideTranslation,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  unawaited(_toggleMessageTranslation(message));
                },
              ),
            if (canReact)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _kMessageReactionSpecs
                      .map((spec) {
                        final selected = message.myReaction == spec.key;
                        final count = message.reactionCounts[spec.key] ?? 0;
                        return ActionChip(
                          onPressed:
                              _reactionBusyMessageIds.contains(message.id)
                              ? null
                              : () {
                                  Navigator.of(context).pop();
                                  _toggleReaction(message, spec.key);
                                },
                          avatar: Text(spec.emoji),
                          label: Text(count > 0 ? '$count' : ' '),
                          side: BorderSide(
                            color: selected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.transparent,
                          ),
                        );
                      })
                      .toList(growable: false),
                ),
              ),
            if (canReply)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(context.l10n.commonReply),
                onTap: () {
                  Navigator.of(context).pop();
                  _setReplyTo(message);
                },
              ),
          ],
        ),
      ),
    );
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
        threadId: _threadId,
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
            mapAnyError(
              e,
              fallback: context.l10n.socialChatThreadReactionUpdateFailed,
            ),
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
          threadId: _threadId,
          isCaller: true,
          remoteDisplayName: _resolvedPeerDisplayLabel,
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

  Future<void> _openAttachment(SocialChatAttachment attachment) async {
    final kind = attachment.kind.trim().toLowerCase();
    if (kind == 'image') {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(16),
          child: InteractiveViewer(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
              child: CachedAppImage(
                imageUrl: attachment.url,
                cacheIdentity: 'chat_attachment_${attachment.url.hashCode}',
                scope: MediaCacheScope.userPrivate,
                userId: _currentUserId,
                fit: BoxFit.contain,
              ),
            ),
          ),
        ),
      );
      return;
    }

    final uri = Uri.tryParse(attachment.url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
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

  String _realtimeLabel() {
    final l10n = context.l10n;
    switch (_chatRealtimeStatus) {
      case _ChatRealtimeStatus.connected:
        return l10n.socialChatThreadRealtimeConnected;
      case _ChatRealtimeStatus.reconnecting:
        return l10n.socialChatThreadRealtimeReconnecting;
      case _ChatRealtimeStatus.connecting:
        return l10n.socialChatThreadRealtimeConnecting;
      case _ChatRealtimeStatus.offline:
        return l10n.socialChatThreadRealtimeOffline;
    }
  }

  IconData _realtimeIcon() {
    switch (_chatRealtimeStatus) {
      case _ChatRealtimeStatus.connected:
        return Icons.bolt_rounded;
      case _ChatRealtimeStatus.reconnecting:
        return Icons.sync_rounded;
      case _ChatRealtimeStatus.connecting:
        return Icons.wifi_tethering_rounded;
      case _ChatRealtimeStatus.offline:
        return Icons.wifi_off_rounded;
    }
  }

  Color _realtimeColor() {
    switch (_chatRealtimeStatus) {
      case _ChatRealtimeStatus.connected:
        return const Color(0xFF4ADE80);
      case _ChatRealtimeStatus.reconnecting:
        return const Color(0xFFF59E0B);
      case _ChatRealtimeStatus.connecting:
        return const Color(0xFF60A5FA);
      case _ChatRealtimeStatus.offline:
        return const Color(0xFF94A3B8);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ActiveChatContextRegistry.leaveSocialThread(_threadId);
    _chatRealtimeStatus = _ChatRealtimeStatus.offline;
    _stopTyping();
    _liveSub?.cancel();
    _pollTimer?.cancel();
    _reconnectTimer?.cancel();
    _voiceComposer.removeListener(_handleVoiceComposerChanged);
    _voiceComposer.dispose();
    _pendingMessagesController.removeListener(_handlePendingMessagesChanged);
    _pendingMessagesController.dispose();
    _searchDebounceTimer?.cancel();
    _typingStopTimer?.cancel();
    _peerTypingResetTimer?.cancel();
    _scrollController.dispose();
    _inputController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    // When the keyboard opens, keep the latest message pinned just above the
    // composer (WhatsApp-style) instead of leaving the list mid-scroll.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final bottomInset = MediaQuery.of(context).viewInsets.bottom;
      if (bottomInset > _lastViewInsetBottom + 1) {
        _scrollToBottom(animated: true);
      }
      _lastViewInsetBottom = bottomInset;
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _appInForeground = true;
      ActiveChatContextRegistry.enterSocialThread(_threadId);
      if (!widget.monitorMode) {
        _connectRealtime();
      }
      unawaited(_loadMessages(silent: true));
      unawaited(_loadScheduledMessages(silent: true));
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _appInForeground = false;
      _liveSub?.cancel();
      _liveSub = null;
      _reconnectTimer?.cancel();
      if (!widget.monitorMode) {
        _setRealtimeStatus(_ChatRealtimeStatus.offline);
      }
      unawaited(_handleVoiceLifecyclePause());
    }
  }

  @override
  /// يبني shell المحادثة مع القائمة، حقل الإدخال، والحالات اللحظية.
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final currentAuthUser = ref.watch(
      authControllerProvider.select((state) => state.user),
    );
    final currentUserId = currentAuthUser?.id;
    final currentUserAuthor = currentAuthUser == null
        ? null
        : SocialAuthor(
            id: currentAuthUser.id,
            username: null,
            fullName: currentAuthUser.fullName,
            imageUrl: currentAuthUser.imageUrl,
            phone: currentAuthUser.phone,
            role: currentAuthUser.role,
          );
    final peer = _resolvedPeer;
    final presenceLabel = _buildPresenceLabel();
    final isEmpty = _messages.isEmpty;
    final visualTheme = _threadVisualTheme;
    final isPendingRequest =
        (_thread?.state.inboxBucket ?? '').trim() == 'requests' &&
        (_thread?.state.requestStatus ?? '').trim() == 'pending';
    final composerLocked = socialChatShouldLockComposer(
      readOnly: widget.readOnly,
      monitorMode: widget.monitorMode,
      pendingRequest: isPendingRequest,
      accessBlocked: _threadAccessBlocked,
    );
    final readOnlyLabel = widget.monitorMode
        ? l10n.socialChatThreadReadOnlyMonitor
        : (isPendingRequest || _threadAccessBlocked)
        ? l10n.socialChatThreadReadOnlyRequests
        : l10n.socialChatThreadReadOnlyDefault;

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(
          title: _searchMode
              ? TextField(
                  controller: _searchController,
                  autofocus: true,
                  textInputAction: TextInputAction.search,
                  onSubmitted: (value) {
                    final query = value.trim();
                    if (query.isEmpty) return;
                    unawaited(_runSearchQuery(query));
                  },
                  decoration: InputDecoration(
                    hintText: l10n.socialChatThreadSearchHint,
                    border: InputBorder.none,
                    isDense: true,
                    hintStyle: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                )
              : InkWell(
                  onTap:
                      (_thread?.isGroup == true ||
                          (widget.peerUserId ?? peer.id) <= 0)
                      ? null
                      : () => _openUserProfile(
                          userId: widget.peerUserId ?? peer.id,
                          fullName: _resolvedPeerOpenName,
                        ),
                  borderRadius: BorderRadius.circular(10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap:
                            (_thread?.isGroup == true ||
                                (widget.peerUserId ?? peer.id) <= 0)
                            ? null
                            : () => _openUserAvatar(
                                userId: widget.peerUserId ?? peer.id,
                                fullName: _resolvedPeerOpenName,
                              ),
                        borderRadius: BorderRadius.circular(999),
                        child: CircleAvatar(
                          radius: 16,
                          backgroundImage:
                              ((_thread?.displayImageUrl ?? peer.imageUrl) ??
                                      '')
                                  .trim()
                                  .isNotEmpty
                              ? appCachedImageProvider(
                                  (_thread?.displayImageUrl ?? peer.imageUrl)!,
                                  cacheIdentity:
                                      'chat_peer_${widget.peerUserId ?? peer.id}',
                                  scope: MediaCacheScope.userPrivate,
                                  userId: _currentUserId,
                                )
                              : null,
                          child:
                              ((_thread?.displayImageUrl ?? peer.imageUrl) ??
                                      '')
                                  .trim()
                                  .isEmpty
                              ? Icon(
                                  _thread?.isGroup == true
                                      ? Icons.group_outlined
                                      : Icons.person_outline,
                                  size: 16,
                                )
                              : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (_thread?.isGroup == true)
                              Text(
                                _thread?.displayTitle ??
                                    _resolvedPeerDisplayLabel,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                ),
                              )
                            else
                              SocialIdentityView(
                                author: peer,
                                showRoleFallback: false,
                                primaryStyle: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 14.5,
                                ),
                                secondaryStyle: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w600,
                                  fontSize: 11.5,
                                ),
                              ),
                            if (presenceLabel.isNotEmpty)
                              Text(
                                presenceLabel,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onSurfaceVariant,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
          actions: [
            if (_searchMode) ...[
              if (_searchLoading)
                const Padding(
                  padding: EdgeInsetsDirectional.only(end: 8),
                  child: Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else if (_searchQuery.isNotEmpty)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 4),
                  child: Center(
                    child: Text(
                      _searchResults.isEmpty
                          ? '0/0'
                          : l10n.socialChatThreadSearchResultCounter(
                              _searchResultIndex + 1,
                              _searchResults.length,
                            ),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  ),
                ),
              IconButton(
                tooltip: l10n.socialChatThreadSearchPrevious,
                onPressed: _searchResults.length > 1
                    ? () => unawaited(_focusNextSearchResult(-1))
                    : null,
                icon: const Icon(Icons.keyboard_arrow_up_rounded),
              ),
              IconButton(
                tooltip: l10n.socialChatThreadSearchNext,
                onPressed: _searchResults.length > 1
                    ? () => unawaited(_focusNextSearchResult(1))
                    : null,
                icon: const Icon(Icons.keyboard_arrow_down_rounded),
              ),
              IconButton(
                tooltip: l10n.commonClose,
                onPressed: _closeSearchMode,
                icon: const Icon(Icons.close_rounded),
              ),
            ] else ...[
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 6),
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: _realtimeColor().withValues(alpha: 0.14),
                      border: Border.all(
                        color: _realtimeColor().withValues(alpha: 0.7),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _realtimeIcon(),
                          size: 13,
                          color: _realtimeColor(),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _realtimeLabel(),
                          style: TextStyle(
                            color: _realtimeColor(),
                            fontWeight: FontWeight.w800,
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton(
                tooltip: l10n.socialChatThreadSearchTooltip,
                onPressed: _openSearchMode,
                icon: const Icon(Icons.search_rounded),
              ),
              IconButton(
                tooltip: l10n.socialChatThreadThemePickerTitle,
                onPressed: _openThemePicker,
                icon: const Icon(Icons.palette_outlined),
              ),
              if (_thread?.isGroup == true)
                IconButton(
                  tooltip: l10n.socialChatThreadGroupManage,
                  onPressed: _openGroupManagementSheet,
                  icon: const Icon(Icons.groups_2_outlined),
                ),
              if (appInAppCallsEnabled &&
                  !composerLocked &&
                  _thread?.isGroup != true)
                IconButton(
                  tooltip: l10n.commonCall,
                  onPressed: _startInAppCall,
                  icon: const Icon(Icons.call_outlined),
                ),
              const AppBarQuickActions(compact: true),
            ],
          ],
        ),
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: visualTheme.backgroundGradient,
            ),
          ),
          child: Column(
            children: [
              if (_searchMode && _searchQuery.isNotEmpty)
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    _searchLoading
                        ? l10n.socialChatThreadSearching
                        : _searchError?.trim().isNotEmpty == true
                        ? _searchError!
                        : _searchResults.isEmpty
                        ? l10n.socialChatThreadSearchNoResults
                        : l10n.socialChatThreadSearchResultCounter(
                            _searchResultIndex + 1,
                            _searchResults.length,
                          ),
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              if (_thread?.threadKind == 'business' && _thread?.context != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: SocialBusinessContextBanner(
                    contextModel: _thread!.context!,
                  ),
                ),
              if (_pinnedMessages.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                  child: _PinnedMessagesBanner(
                    messages: _pinnedMessages,
                    onOpenMessage: (messageId) {
                      unawaited(_focusMessageById(messageId));
                    },
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
                                // Bottom padding kept minimal so the latest
                                // message sits right against the composer
                                // (no raised gap above the bottom boundary).
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  14,
                                  12,
                                  2,
                                ),
                                children: [
                                  if (_nextCursor != null)
                                    Align(
                                      alignment: Alignment.center,
                                      child: OutlinedButton.icon(
                                        onPressed: _loadingMore
                                            ? null
                                            : () =>
                                                  _loadMessages(loadMore: true),
                                        icon: _loadingMore
                                            ? const SizedBox(
                                                width: 14,
                                                height: 14,
                                                child:
                                                    CircularProgressIndicator(
                                                      strokeWidth: 2,
                                                    ),
                                              )
                                            : const Icon(
                                                Icons.expand_less_rounded,
                                              ),
                                        label: Text(
                                          l10n.socialChatThreadShowOlderMessages,
                                        ),
                                      ),
                                    ),
                                  if (isEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 80),
                                      child: Center(
                                        child: _error != null
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 24,
                                                    ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons
                                                          .error_outline_rounded,
                                                      color: Theme.of(
                                                        context,
                                                      ).colorScheme.error,
                                                      size: 42,
                                                    ),
                                                    const SizedBox(height: 10),
                                                    Text(
                                                      _error!,
                                                      textAlign:
                                                          TextAlign.center,
                                                      style: const TextStyle(
                                                        fontWeight:
                                                            FontWeight.w700,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 14),
                                                    OutlinedButton(
                                                      onPressed: () =>
                                                          _loadMessages(),
                                                      child: Text(
                                                        l10n.commonRetry,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              )
                                            : Text(l10n.socialChatThreadEmpty),
                                      ),
                                    ),
                                  ...(() {
                                    final pendingMessages =
                                        _pendingMessagesController.items
                                            .where(
                                              (item) =>
                                                  item.threadId == _threadId &&
                                                  item.status !=
                                                      LocalPendingMessageStatus
                                                          .cancelled,
                                            )
                                            .toList(growable: false)
                                          ..sort(
                                            (a, b) => a.createdAt.compareTo(
                                              b.createdAt,
                                            ),
                                          );
                                    return <Widget>[
                                      for (final message in _messages)
                                        KeyedSubtree(
                                          key: _messageKey(message.id),
                                          child: _ChatBubble(
                                            message: _resolveMessageForViewer(
                                              message,
                                              currentUserId: currentUserId,
                                              currentUserAuthor:
                                                  currentUserAuthor,
                                              peerAuthor: peer,
                                            ),
                                            translation: _translatedMessageFor(
                                              message.id,
                                            ),
                                            translationBusy:
                                                _translationBusyMessageIds
                                                    .contains(message.id),
                                            visualTheme: visualTheme,
                                            highlighted:
                                                _highlightedMessageId ==
                                                message.id,
                                            readOnly: widget.readOnly,
                                            showReadReceipts:
                                                ((_thread?.isGroup ?? false)
                                                    ? false
                                                    : _thread
                                                          ?.presence
                                                          .canSeeReadReceipts) ??
                                                false,
                                            reactionBusy:
                                                _reactionBusyMessageIds
                                                    .contains(message.id),
                                            timeText: message.createdAt == null
                                                ? ''
                                                : _timeFormat.format(
                                                    message.createdAt!
                                                        .toLocal(),
                                                  ),
                                            currentUserId: currentUserId,
                                            onOpenAttachment:
                                                message.attachment == null
                                                ? null
                                                : () => _openAttachment(
                                                    message.attachment!,
                                                  ),
                                            onOpenSharedEntity:
                                                message.sharedEntity == null
                                                ? null
                                                : () => openSocialSharedEntity(
                                                    context,
                                                    entity:
                                                        message.sharedEntity!,
                                                  ),
                                            onOpenAuthorAvatar: () =>
                                                _openUserAvatar(
                                                  userId:
                                                      _resolveMessageForViewer(
                                                        message,
                                                        currentUserId:
                                                            currentUserId,
                                                        currentUserAuthor:
                                                            currentUserAuthor,
                                                        peerAuthor: peer,
                                                      ).sender.id,
                                                  fullName:
                                                      _resolveMessageForViewer(
                                                        message,
                                                        currentUserId:
                                                            currentUserId,
                                                        currentUserAuthor:
                                                            currentUserAuthor,
                                                        peerAuthor: peer,
                                                      ).sender.fullName,
                                                ),
                                            onOpenAuthorProfile: () =>
                                                _openUserProfile(
                                                  userId:
                                                      _resolveMessageForViewer(
                                                        message,
                                                        currentUserId:
                                                            currentUserId,
                                                        currentUserAuthor:
                                                            currentUserAuthor,
                                                        peerAuthor: peer,
                                                      ).sender.id,
                                                  fullName:
                                                      _resolveMessageForViewer(
                                                        message,
                                                        currentUserId:
                                                            currentUserId,
                                                        currentUserAuthor:
                                                            currentUserAuthor,
                                                        peerAuthor: peer,
                                                      ).sender.fullName,
                                                ),
                                            onMore: widget.readOnly
                                                ? null
                                                : () => _openMessageActions(
                                                    message,
                                                  ),
                                          ),
                                        ),
                                      for (final pending in pendingMessages)
                                        KeyedSubtree(
                                          key: ValueKey<String>(
                                            'pending_${pending.clientMessageId}',
                                          ),
                                          child: SocialPendingMessageBubble(
                                            message: pending,
                                            onRetry:
                                                pending.status ==
                                                    LocalPendingMessageStatus
                                                        .failed
                                                ? () {
                                                    unawaited(
                                                      _retryPendingMessage(
                                                        pending,
                                                      ),
                                                    );
                                                  }
                                                : null,
                                            onCancel: () {
                                              unawaited(
                                                _cancelPendingMessage(pending),
                                              );
                                            },
                                          ),
                                        ),
                                    ];
                                  }()),
                                  if (_peerTyping &&
                                      (_thread
                                              ?.presence
                                              .canSeeTypingIndicators ??
                                          false))
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Align(
                                        alignment: Alignment.centerRight,
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 14,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            borderRadius: BorderRadius.circular(
                                              999,
                                            ),
                                            color: Theme.of(context)
                                                .colorScheme
                                                .surfaceContainerHighest,
                                          ),
                                          child: Text(
                                            l10n.socialChatThreadTyping,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                        ),
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
                          tooltip: l10n.socialChatThreadLatestMessages,
                          onPressed: _scrollToBottom,
                          child: const Icon(
                            Icons.keyboard_double_arrow_down_rounded,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              DecoratedBox(
                // Surface fills all the way to the bottom screen edge so there
                // is no background-gradient gap under the composer; the inner
                // SafeArea just pads the input above the gesture/nav bar.
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                ),
                child: Padding(
                  // Only a small margin above the gesture/home bar so the input
                  // box hugs the bottom edge (no large empty gap). Collapses to
                  // zero when the keyboard is open.
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.paddingOf(
                      context,
                    ).bottom.clamp(0.0, 8.0).toDouble(),
                  ),
                  child: composerLocked
                      ? Container(
                          width: double.infinity,
                          padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
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
                          child: Text(
                            readOnlyLabel,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        )
                      : Container(
                          padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
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
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_replyingTo != null)
                                _ComposerMetaCard(
                                  icon: Icons.reply_rounded,
                                  title: l10n.socialChatThreadReplyingTo(
                                    _replyingTo!.senderFullName,
                                  ),
                                  subtitle: _replyingTo!.previewText,
                                  onClear: () =>
                                      setState(() => _replyingTo = null),
                                ),
                              if (_voiceComposer.state.isRecording)
                                SocialVoiceRecordingStatusCard(
                                  duration: _voiceComposer.state.duration,
                                  locked: _voiceComposer.state.isLocked,
                                  title: l10n.socialChatThreadRecordVoice,
                                  slideToLockLabel:
                                      l10n.socialChatThreadSlideUpToLock,
                                  lockedLabel:
                                      l10n.socialChatThreadRecordingLocked,
                                  cancelLabel:
                                      l10n.socialChatThreadDeleteVoiceDraft,
                                  stopLabel: l10n.socialChatThreadStopRecording,
                                  onCancel: () {
                                    unawaited(_cancelVoiceComposer());
                                  },
                                  onStop: _voiceComposer.state.isLocked
                                      ? () {
                                          unawaited(
                                            _stopLockedVoiceRecording(),
                                          );
                                        }
                                      : null,
                                ),
                              if (_voiceComposer.state.draft != null)
                                SocialVoicePreviewCard(
                                  draft: _voiceComposer.state.draft!,
                                  sending: _voiceComposer.state.isSending,
                                  title:
                                      l10n.socialChatThreadPreviewVoiceMessage,
                                  playLabel:
                                      l10n.socialChatThreadVoiceMessagePlay,
                                  pauseLabel:
                                      l10n.socialChatThreadVoiceMessagePause,
                                  deleteLabel:
                                      l10n.socialChatThreadDeleteVoiceDraft,
                                  sendLabel:
                                      l10n.socialChatThreadSendVoiceMessage,
                                  onDelete: () {
                                    unawaited(_cancelVoiceComposer());
                                  },
                                  onSend: _sendVoiceDraft,
                                ),
                              if (_attachmentDraft != null)
                                SocialAttachmentPreviewCard(
                                  file: _attachmentDraft!,
                                  onClear: () =>
                                      setState(() => _attachmentDraft = null),
                                ),
                              if (_sharedEntityDraft != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Row(
                                    children: [
                                      Expanded(
                                        child: _SharedEntityCard(
                                          entity: _sharedEntityDraft!,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        tooltip: l10n.commonDelete,
                                        onPressed: () {
                                          setState(
                                            () => _sharedEntityDraft = null,
                                          );
                                        },
                                        icon: const Icon(Icons.close_rounded),
                                      ),
                                    ],
                                  ),
                                ),
                              if (!composerLocked &&
                                  _scheduledMessages.isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Text(
                                        l10n.socialChatThreadScheduledMessages,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelLarge
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 8),
                                      for (final item in _scheduledMessages)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          child: SocialScheduledMessageCard(
                                            item: item,
                                            title: l10n
                                                .socialChatThreadScheduleMessage,
                                            scheduledLabel: l10n
                                                .socialChatThreadScheduledStatus,
                                            failedLabel: l10n
                                                .socialChatThreadScheduledFailed,
                                            processingLabel: l10n
                                                .socialChatThreadScheduledProcessing,
                                            deleteLabel: l10n
                                                .socialChatThreadCancelScheduledMessage,
                                            onDelete: () {
                                              unawaited(
                                                _cancelScheduledMessage(
                                                  item.id,
                                                ),
                                              );
                                            },
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                              Builder(
                                builder: (context) {
                                  final hasComposerText = _composerHasText;
                                  final showSendAction =
                                      hasComposerText ||
                                      _attachmentDraft != null ||
                                      _sharedEntityDraft != null ||
                                      _voiceComposer.state.hasPreview;
                                  return Row(
                                    children: [
                                      IconButton(
                                        tooltip: l10n.socialChatThreadAttach,
                                        onPressed:
                                            (_sending || _voiceComposerBusy)
                                            ? null
                                            : _openAttachmentsMenu,
                                        icon: const Icon(
                                          Icons.add_circle_outline_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: _isEnglishLocale
                                            ? 'Stickers & GIF'
                                            : 'الملصقات و GIF',
                                        onPressed:
                                            (_sending ||
                                                widget.readOnly ||
                                                _voiceComposerBusy)
                                            ? null
                                            : _openStickersGifMenu,
                                        icon: const Icon(
                                          Icons.sentiment_satisfied_alt_rounded,
                                        ),
                                      ),
                                      IconButton(
                                        tooltip: l10n
                                            .socialChatThreadScheduleMessage,
                                        onPressed:
                                            (_sending ||
                                                widget.readOnly ||
                                                _voiceComposer
                                                    .state
                                                    .isRecording)
                                            ? null
                                            : _scheduleCurrentDraft,
                                        icon: const Icon(
                                          Icons.schedule_send_rounded,
                                        ),
                                      ),
                                      Expanded(
                                        child: TextField(
                                          controller: _inputController,
                                          onChanged: _handleComposerChanged,
                                          textInputAction: TextInputAction.send,
                                          onSubmitted: (_) {
                                            if (_voiceComposerBusy) return;
                                            _sendMessage();
                                          },
                                          minLines: 1,
                                          maxLines: 4,
                                          enabled: !_voiceComposerBusy,
                                          decoration: InputDecoration(
                                            hintText:
                                                _voiceComposer.state.hasPreview
                                                ? l10n.socialChatThreadPreviewVoiceMessage
                                                : l10n.socialChatThreadWriteMessageHint,
                                            isDense: true,
                                            border: OutlineInputBorder(
                                              borderRadius:
                                                  BorderRadius.circular(16),
                                            ),
                                            contentPadding:
                                                const EdgeInsets.symmetric(
                                                  horizontal: 12,
                                                  vertical: 10,
                                                ),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      if (showSendAction)
                                        FilledButton(
                                          onPressed:
                                              (_sending || _voiceComposerBusy)
                                              ? null
                                              : _sendMessage,
                                          style: FilledButton.styleFrom(
                                            minimumSize: const Size(52, 48),
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 14,
                                            ),
                                          ),
                                          child: _sending
                                              ? const SizedBox(
                                                  width: 16,
                                                  height: 16,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                      ),
                                                )
                                              : const Icon(Icons.send_rounded),
                                        )
                                      else
                                        GestureDetector(
                                          behavior: HitTestBehavior.opaque,
                                          onLongPressStart:
                                              (_sending ||
                                                  widget.readOnly ||
                                                  _attachmentDraft != null ||
                                                  _voiceComposerBusy)
                                              ? null
                                              : (_) => _startVoiceHold(),
                                          onLongPressMoveUpdate:
                                              (_sending ||
                                                  widget.readOnly ||
                                                  _attachmentDraft != null ||
                                                  _voiceComposerBusy)
                                              ? null
                                              : _updateVoiceHoldDrag,
                                          onLongPressEnd:
                                              (_sending ||
                                                  widget.readOnly ||
                                                  _attachmentDraft != null)
                                              ? null
                                              : (_) => _finishVoiceHold(),
                                          onTap:
                                              (_sending ||
                                                  widget.readOnly ||
                                                  _attachmentDraft != null ||
                                                  _voiceComposerBusy)
                                              ? null
                                              : () {
                                                  ScaffoldMessenger.of(
                                                    context,
                                                  ).showSnackBar(
                                                    SnackBar(
                                                      content: Text(
                                                        l10n.socialChatThreadHoldToRecord,
                                                      ),
                                                    ),
                                                  );
                                                },
                                          child: Semantics(
                                            button: true,
                                            label: l10n
                                                .socialChatThreadHoldToRecord,
                                            child: Container(
                                              width: 48,
                                              height: 48,
                                              alignment: Alignment.center,
                                              decoration: BoxDecoration(
                                                borderRadius:
                                                    BorderRadius.circular(999),
                                                color:
                                                    _voiceComposer
                                                        .state
                                                        .isRecording
                                                    ? Theme.of(context)
                                                          .colorScheme
                                                          .errorContainer
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .surfaceContainerHighest,
                                              ),
                                              child: Icon(
                                                _voiceComposer.state.isRecording
                                                    ? Icons.lock_open_rounded
                                                    : Icons.mic_none_rounded,
                                                color:
                                                    _voiceComposer
                                                        .state
                                                        .isRecording
                                                    ? Theme.of(
                                                        context,
                                                      ).colorScheme.error
                                                    : Theme.of(context)
                                                          .colorScheme
                                                          .onSurfaceVariant,
                                              ),
                                            ),
                                          ),
                                        ),
                                    ],
                                  );
                                },
                              ),
                            ],
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final SocialChatMessage message;
  final SocialChatMessageTranslation? translation;
  final bool translationBusy;
  final SocialThreadVisualTheme visualTheme;
  final bool highlighted;
  final bool readOnly;
  final bool showReadReceipts;
  final bool reactionBusy;
  final String timeText;
  final int? currentUserId;
  final VoidCallback? onOpenAttachment;
  final VoidCallback? onOpenSharedEntity;
  final VoidCallback onOpenAuthorAvatar;
  final VoidCallback onOpenAuthorProfile;
  final VoidCallback? onMore;

  const _ChatBubble({
    required this.message,
    required this.translation,
    required this.translationBusy,
    required this.visualTheme,
    required this.highlighted,
    required this.readOnly,
    required this.showReadReceipts,
    required this.reactionBusy,
    required this.timeText,
    required this.currentUserId,
    required this.onOpenAttachment,
    required this.onOpenSharedEntity,
    required this.onOpenAuthorAvatar,
    required this.onOpenAuthorProfile,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    final mine = message.isMine;
    final isDeleted = message.isDeleted;
    final displayBody = isDeleted
        ? context.l10n.socialChatThreadDeletedMessage
        : message.body;
    final showEdited = !isDeleted && message.editedAt != null;
    final bubbleColor = mine ? visualTheme.mineBubble : visualTheme.peerBubble;
    final textColor = mine ? visualTheme.mineText : visualTheme.peerText;

    return Align(
      alignment: mine ? Alignment.centerLeft : Alignment.centerRight,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 320),
        child: GestureDetector(
          onLongPress: onMore,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.circular(14),
              border: highlighted
                  ? Border.all(
                      color: Theme.of(context).colorScheme.primary,
                      width: 1.6,
                    )
                  : null,
              boxShadow: highlighted
                  ? [
                      BoxShadow(
                        color: Theme.of(
                          context,
                        ).colorScheme.primary.withValues(alpha: 0.18),
                        blurRadius: 16,
                        spreadRadius: 1,
                      ),
                    ]
                  : null,
            ),
            child: Column(
              crossAxisAlignment: mine
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.end,
              children: [
                if (!mine)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      InkWell(
                        onTap: onOpenAuthorAvatar,
                        borderRadius: BorderRadius.circular(999),
                        child: CircleAvatar(
                          radius: 11,
                          backgroundImage:
                              (message.sender.imageUrl ?? '').trim().isNotEmpty
                              ? appCachedImageProvider(
                                  message.sender.imageUrl!,
                                  cacheIdentity:
                                      'chat_sender_${message.sender.id}',
                                  scope: MediaCacheScope.userPrivate,
                                  userId: currentUserId,
                                )
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
                        child: SocialIdentityView(
                          author: message.sender,
                          showRoleFallback: false,
                          primaryStyle: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: textColor.withValues(alpha: 0.86),
                            fontSize: 12,
                          ),
                          secondaryStyle: TextStyle(
                            color: textColor.withValues(alpha: 0.68),
                            fontWeight: FontWeight.w700,
                            fontSize: 10.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                if (!mine) const SizedBox(height: 4),
                if (!isDeleted && message.replyToMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: textColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                      border: BorderDirectional(
                        start: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 3,
                        ),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          message.replyToMessage!.senderFullName,
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            color: textColor.withValues(alpha: 0.82),
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          message.replyToMessage!.previewText,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.7),
                            fontWeight: FontWeight.w600,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (displayBody.trim().isNotEmpty)
                  isDeleted
                      ? Text(
                          displayBody,
                          style: TextStyle(
                            color: textColor.withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                            fontStyle: FontStyle.italic,
                          ),
                        )
                      : SocialMentionHashtagText(
                          text: displayBody,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            height: 1.4,
                          ),
                        ),
                if (!isDeleted && translation != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: visualTheme.accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: visualTheme.accent.withValues(alpha: 0.28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          context.l10n.socialChatThreadTranslatedLabel,
                          style: TextStyle(
                            color: visualTheme.accent,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          translation!.translatedText,
                          style: TextStyle(
                            color: textColor,
                            fontWeight: FontWeight.w600,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                if (!isDeleted && message.attachment != null) ...[
                  if (displayBody.trim().isNotEmpty) const SizedBox(height: 8),
                  if (message.attachment!.isAudio)
                    SocialAudioAttachmentBubble(
                      attachment: message.attachment!,
                      textColor: textColor,
                    )
                  else
                    SocialInlineAttachmentMessageCard(
                      attachment: message.attachment!,
                      scope: MediaCacheScope.userPrivate,
                      userId: currentUserId,
                      onTap: onOpenAttachment ?? () {},
                    ),
                ],
                if (!isDeleted && message.sharedEntity != null) ...[
                  if (displayBody.trim().isNotEmpty ||
                      message.attachment != null)
                    const SizedBox(height: 8),
                  _SharedEntityCard(
                    entity: message.sharedEntity!,
                    onTap: onOpenSharedEntity,
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (!isDeleted && message.pinnedAt != null) ...[
                      Icon(
                        Icons.push_pin_rounded,
                        size: 14,
                        color: textColor.withValues(alpha: 0.78),
                      ),
                      const SizedBox(width: 6),
                    ],
                    if (!isDeleted &&
                        (message.myReaction ?? '').trim().isNotEmpty)
                      Text(
                        _reactionEmojiForKey(message.myReaction),
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.88),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    if (!isDeleted &&
                        (message.myReaction ?? '').trim().isNotEmpty &&
                        message.reactionTotalCount > 0)
                      const SizedBox(width: 6),
                    if (!isDeleted && message.reactionTotalCount > 0)
                      Text(
                        '${message.reactionTotalCount}',
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.74),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if ((!isDeleted &&
                                ((message.myReaction ?? '').trim().isNotEmpty ||
                                    message.reactionTotalCount > 0) ||
                            showEdited) &&
                        timeText.isNotEmpty)
                      const SizedBox(width: 6),
                    if (showEdited)
                      Text(
                        context.l10n.socialChatThreadEdited,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.68),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    if (showEdited && timeText.isNotEmpty)
                      const SizedBox(width: 6),
                    if (timeText.isNotEmpty)
                      Text(
                        timeText,
                        style: TextStyle(
                          color: textColor.withValues(alpha: 0.68),
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    if (message.isMine) ...[
                      const SizedBox(width: 6),
                      Icon(
                        message.readByPeer
                            ? Icons.done_all_rounded
                            : message.deliveredToPeer
                            ? Icons.done_all_rounded
                            : Icons.check_rounded,
                        size: 15,
                        color: message.readByPeer
                            ? Theme.of(context).colorScheme.primary
                            : textColor.withValues(alpha: 0.7),
                      ),
                      if (showReadReceipts) ...[
                        const SizedBox(width: 4),
                        Text(
                          message.readByPeer
                              ? context.l10n.socialChatThreadSeen
                              : message.deliveredToPeer
                              ? context.l10n.socialChatThreadDelivered
                              : context.l10n.socialChatThreadSent,
                          style: TextStyle(
                            color: message.readByPeer
                                ? Theme.of(context).colorScheme.primary
                                : textColor.withValues(alpha: 0.68),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ],
                ),
                if (reactionBusy)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.l10n.socialChatThreadSavingReaction,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                if (translationBusy)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      context.l10n.socialChatThreadSearching,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: textColor.withValues(alpha: 0.7),
                      ),
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

class _PinnedMessagesBanner extends StatelessWidget {
  final List<SocialChatMessage> messages;
  final ValueChanged<int> onOpenMessage;

  const _PinnedMessagesBanner({
    required this.messages,
    required this.onOpenMessage,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 6),
              Text(
                context.l10n.socialChatThreadPinnedMessagesTitle,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final message in messages)
            InkWell(
              onTap: () => onOpenMessage(message.id),
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            message.sender.fullName.trim().isNotEmpty
                                ? message.sender.fullName.trim()
                                : message.sender.username?.trim().isNotEmpty ==
                                      true
                                ? '@${message.sender.username!.trim()}'
                                : context.l10n.socialChatThreadPinnedMessage,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: scheme.onSurface,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            message.previewText,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: scheme.onSurfaceVariant,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: scheme.onSurfaceVariant,
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

class _SharedEntityCard extends StatelessWidget {
  final SocialSharedEntity entity;
  final VoidCallback? onTap;

  const _SharedEntityCard({required this.entity, this.onTap});

  @override
  Widget build(BuildContext context) {
    final normalizedType = entity.type.trim().toLowerCase();
    if (normalizedType == 'reel') {
      return SocialSharedReelMessageCard(entity: entity, onTap: onTap);
    }

    final subtitle = entity.subtitle;
    final subtitleParts = <String>[
      if ((entity.authorDisplayName ?? '').trim().isNotEmpty)
        entity.authorDisplayName!.trim(),
      if ((entity.authorUsername ?? '').trim().isNotEmpty)
        '@${entity.authorUsername}',
    ];
    final posterUrl = (entity.imageUrl ?? entity.authorAvatarUrl ?? '').trim();
    final icon = switch (entity.type.trim().toLowerCase()) {
      'reel' => Icons.play_circle_outline_rounded,
      'story' => Icons.bolt_rounded,
      'review' => Icons.rate_review_outlined,
      'merchant_review' => Icons.rate_review_outlined,
      'car_listing' => Icons.directions_car_filled_rounded,
      'real_estate_listing' => Icons.apartment_rounded,
      'location' => Icons.location_on_rounded,
      'profile' => Icons.person_outline_rounded,
      'user' => Icons.person_outline_rounded,
      _ => Icons.article_outlined,
    };
    final titleText = normalizedType == 'location'
        ? (entity.address ?? entity.title)
        : entity.title;
    final typeLabel = normalizedType == 'location'
        ? 'موقع مشترك'
        : entity.previewLabel;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Ink(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.black.withValues(alpha: 0.08),
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.14),
                image: posterUrl.isEmpty
                    ? null
                    : DecorationImage(
                        image: AppCachedImageProvider(
                          posterUrl,
                          cacheIdentity: 'shared_entity_${entity.id}',
                        ),
                        fit: BoxFit.cover,
                      ),
              ),
              child: posterUrl.isEmpty
                  ? Icon(icon, color: Theme.of(context).colorScheme.primary)
                  : null,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    typeLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    titleText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  if (subtitleParts.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitleParts.join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if ((subtitle ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      subtitle!.trim(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w700,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  if (entity.price != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      '${entity.price}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ComposerMetaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onClear;

  const _ComposerMetaCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.72),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurface.withValues(alpha: 0.72),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: context.l10n.commonRemove,
            onPressed: onClear,
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

int? _parseInt(dynamic value) {
  if (value == null) return null;
  return int.tryParse('$value');
}

String _reactionEmojiForKey(String? key) {
  final normalized = (key ?? '').trim().toLowerCase();
  for (final spec in _kMessageReactionSpecs) {
    if (spec.key == normalized) {
      return spec.emoji;
    }
  }
  return '';
}

const Set<String> _kMessageReactionKeys = <String>{
  'like',
  'heart',
  'laugh',
  'fire',
};

const List<_MessageReactionSpec> _kMessageReactionSpecs =
    <_MessageReactionSpec>[
      _MessageReactionSpec('like', 'ðŸ‘'),
      _MessageReactionSpec('heart', '❤️'),
      _MessageReactionSpec('laugh', 'ðŸ˜‚'),
      _MessageReactionSpec('fire', 'ðŸ”¥'),
    ];

class _MessageReactionSpec {
  final String key;
  final String emoji;

  const _MessageReactionSpec(this.key, this.emoji);
}
