import 'dart:async';

import 'package:core_design_system/core_design_system.dart';
import 'package:core_maps/core_maps.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/notifications/active_chat_context_registry.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../../auth/ui/merchants_list_screen.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../notifications/data/notifications_api.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../notifications/state/notifications_controller.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_content_navigation.dart';
import 'social_profile_screen.dart';
import 'social_search_screen.dart';
import 'widgets/basmaya_shell_bars.dart';
import 'widgets/social_community_content_widgets.dart';
import 'widgets/social_community_sheets.dart';
import 'widgets/social_community_support.dart';
import 'widgets/social_attachment_preview_card.dart';
import 'widgets/social_feed_controls.dart';
import 'widgets/social_post_card_v2.dart';
import 'widgets/social_voice_composer_controller.dart';
import 'widgets/social_voice_message_widgets.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

final _communityLiveNotificationsApiProvider = Provider<NotificationsApi>((
  ref,
) {
  final dio = ref.read(dioClientProvider).dio;
  return NotificationsApi(
    dio,
    realtime: ref.read(maslakiRealtimeServiceProvider),
  );
});

enum _CommunityChatComposerAttachmentAction { image, video, file, location }

class SocialCommunityScreen extends ConsumerStatefulWidget {
  final String scopeType;
  final String scopeCode;
  final String? title;
  final int initialTab;

  const SocialCommunityScreen({
    super.key,
    required this.scopeType,
    required this.scopeCode,
    this.title,
    this.initialTab = 0,
  });

  @override
  ConsumerState<SocialCommunityScreen> createState() =>
      _SocialCommunityScreenState();
}

class _SocialCommunityScreenState extends ConsumerState<SocialCommunityScreen>
    with WidgetsBindingObserver {
  intl.DateFormat get _timeFmt =>
      intl.DateFormat('d/M hh:mm a', context.isEnglishLocale ? 'en' : 'ar');
  final TextEditingController _chatCtrl = TextEditingController();
  final TextEditingController _chatSearchCtrl = TextEditingController();
  final ScrollController _chatScrollCtrl = ScrollController();
  final Map<int, GlobalKey> _chatMessageItemKeys = <int, GlobalKey>{};
  String _t(String ar, String en) => safeCommunityLt(context, ar: ar, en: en);

  bool _loading = true;
  bool _sending = false;
  int _tab = 0;
  String? _error;
  String _scopeTitle = '';
  String _scopeSubtitle = '';
  String? _billCategory;
  SocialCommunityChatMessage? _replyingToMessage;

  bool _canManageAnnouncements = false;
  bool _canManageChat = false;
  bool _canManageBills = false;
  bool _canManageManagers = false;
  bool _chatLocked = false;
  bool _isBanned = false;
  LocalMediaFile? _chatAttachmentDraft;
  SocialSharedEntity? _chatSharedEntityDraft;

  List<SocialPost> _posts = const [];
  List<SocialCommunityAnnouncement> _announcements = const [];
  List<SocialCommunityChatMessage> _chatMessages = const [];
  List<SocialCommunityBill> _bills = const [];
  List<SocialCommunityManager> _managers = const [];
  StreamSubscription<NotificationLiveEvent>? _liveSub;
  Timer? _chatPollTimer;
  Timer? _chatReconnectTimer;
  Timer? _typingStopTimer;
  Timer? _peerTypingResetTimer;
  Timer? _chatSearchDebounceTimer;
  int? _chatLastEventId;
  int _chatReconnectAttempt = 0;
  bool _communityRealtimeConnected = false;
  int _communityConnectedPollTick = 0;
  bool _communityComposerHasText = false;
  late final SocialVoiceComposerController _voiceComposer;
  bool _typingActive = false;
  bool _peerTyping = false;
  String? _peerTypingActorName;
  DateTime? _lastTypingEmitAt;
  bool? _lastTypingSent;
  bool _chatSearchMode = false;
  bool _chatSearchLoading = false;
  String? _chatSearchError;
  String _chatSearchQuery = '';
  int _chatSearchResultIndex = 0;
  int? _highlightedChatMessageId;
  List<SocialCommunityChatMessage> _chatSearchResults = const [];

  SocialApi get _api => ref.read(socialApiProvider);
  NotificationsApi get _liveApi =>
      ref.read(_communityLiveNotificationsApiProvider);
  int? get _currentUserId => ref.read(authControllerProvider).user?.id;
  String get _scopeType => widget.scopeType.trim().toLowerCase();
  String get _scopeCode => widget.scopeCode.trim().toUpperCase();

  void _setTab(int tab) {
    if (_tab == tab) return;
    if (_tab == 2 && tab != 2) {
      _stopCommunityTyping();
      _peerTypingResetTimer?.cancel();
      _peerTyping = false;
      _peerTypingActorName = null;
    }
    setState(() => _tab = tab);
    _syncActiveCommunityChatContext();
    if (tab == 2) {
      unawaited(_markCommunityChatNotificationsRead());
    }
  }

  @override
  void initState() {
    super.initState();
    _tab = widget.initialTab < 0 || widget.initialTab > 3
        ? 0
        : widget.initialTab;
    _scopeTitle = widget.title ?? '${widget.scopeType} ${widget.scopeCode}';
    _voiceComposer = SocialVoiceComposerController()
      ..addListener(_handleVoiceComposerChanged);
    _chatSearchCtrl.addListener(_handleCommunitySearchTextChanged);
    WidgetsBinding.instance.addObserver(this);
    Future<void>.microtask(_bootstrapCommunityRealtime);
  }

  String _scopeKindLabel() {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    return switch (_scopeType.trim().toLowerCase()) {
      'building' =>
        isEnglish ? 'Building' : '\u0627\u0644\u0639\u0645\u0627\u0631\u0629',
      'compound' =>
        isEnglish ? 'Compound' : '\u0627\u0644\u0645\u062c\u0645\u0639',
      _ => isEnglish ? 'Block' : '\u0627\u0644\u0628\u0644\u0648\u0643',
    };
  }

  String _scopeHomeTitle() {
    final code = _scopeCode.trim().toUpperCase();
    final kind = _scopeKindLabel();
    return context.isEnglishLocale
        ? 'Shdysir $kind $code'
        : '\u0634\u062f\u064a\u0635\u064a\u0631 $kind $code';
  }

  String _scopeDefaultSubtitle() {
    final code = _scopeCode.trim().toUpperCase();
    final kind = _scopeKindLabel();
    return _t(
      '\u0645\u0646\u0634\u0648\u0631\u0627\u062a \u0648\u062a\u0628\u0644\u064a\u063a\u0627\u062a \u0648\u062f\u0631\u062f\u0634\u0629 \u0648\u0641\u0648\u0627\u062a\u064a\u0631 $kind $code \u0636\u0645\u0646 \u0645\u062c\u062a\u0645\u0639 \u0628\u0633\u0645\u0627\u064a\u0629.',
      'Posts, announcements, chat, and bills for $kind $code inside the Basmaya community.',
    );
  }

  Future<void> _runCommunityDrawerAction(
    FutureOr<void> Function() action,
  ) async {
    Navigator.of(context).pop();
    await Future<void>.delayed(Duration.zero);
    if (!mounted) return;
    await Future<void>.value(action());
  }

  Future<void> _focusCommunityTabFromDrawer(int tab) async {
    await _runCommunityDrawerAction(() async {
      _setTab(tab);
      if (tab == 2) {
        await _markCommunityChatNotificationsRead();
      }
    });
  }

  BasmayaNavKey get _currentBasmayaNavKey => switch (_scopeType) {
    'building' => BasmayaNavKey.building,
    'compound' => BasmayaNavKey.compound,
    _ => BasmayaNavKey.block,
  };

  List<MaslakiDrawerSection> _buildCommunityDrawerSections() {
    final communityEntries = <MaslakiDrawerEntry>[
      MaslakiDrawerEntry(
        icon: Icons.feed_outlined,
        label: _t(
          '\u0645\u0646\u0634\u0648\u0631\u0627\u062a \u0627\u0644\u0645\u062c\u062a\u0645\u0639',
          'Community posts',
        ),
        onTap: () => _focusCommunityTabFromDrawer(0),
      ),
      MaslakiDrawerEntry(
        icon: Icons.campaign_outlined,
        label: _t(
          '\u062a\u0628\u0644\u064a\u063a\u0627\u062a \u0627\u0644\u0625\u062f\u0627\u0631\u0629',
          'Announcements',
        ),
        onTap: () => _focusCommunityTabFromDrawer(1),
      ),
      MaslakiDrawerEntry(
        icon: Icons.forum_outlined,
        label: _t(
          '\u0645\u062d\u0627\u062f\u062b\u0629 \u0627\u0644\u0645\u062c\u0645\u0648\u0639\u0629',
          'Group chat',
        ),
        onTap: () => _focusCommunityTabFromDrawer(2),
      ),
      MaslakiDrawerEntry(
        icon: Icons.receipt_long_rounded,
        label: _t('\u0627\u0644\u0641\u0648\u0627\u062a\u064a\u0631', 'Bills'),
        onTap: () => _focusCommunityTabFromDrawer(3),
      ),
    ];

    final tools = <MaslakiDrawerEntry>[
      MaslakiDrawerEntry(
        icon: Icons.refresh_rounded,
        label: _t(
          '\u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0635\u0641\u062d\u0629',
          'Refresh page',
        ),
        onTap: () => _runCommunityDrawerAction(_reload),
      ),
      MaslakiDrawerEntry(
        icon: Icons.post_add_rounded,
        label: _t(
          '\u0625\u0636\u0627\u0641\u0629 \u0645\u0646\u0634\u0648\u0631',
          'Add post',
        ),
        onTap: () => _runCommunityDrawerAction(_openScopedCreatePostSheet),
      ),
      MaslakiDrawerEntry(
        icon: Icons.add_circle_outline_rounded,
        label: _t(
          '\u0625\u0636\u0627\u0641\u0629 \u0633\u062a\u0648\u0631\u064a',
          'Add story',
        ),
        onTap: () => _runCommunityDrawerAction(_openCreateStorySheet),
      ),
    ];

    if (_canManageManagers) {
      tools.add(
        MaslakiDrawerEntry(
          icon: Icons.admin_panel_settings_outlined,
          label: _t(
            '\u0625\u062f\u0627\u0631\u0629 \u0627\u0644\u0645\u062f\u0631\u0627\u0621',
            'Manage managers',
          ),
          onTap: () => _runCommunityDrawerAction(_openManagerAssignmentSheet),
        ),
      );
    }
    if (_canManageChat) {
      tools.add(
        MaslakiDrawerEntry(
          icon: _chatLocked
              ? Icons.lock_open_rounded
              : Icons.lock_outline_rounded,
          label: _chatLocked
              ? _t(
                  '\u0641\u062a\u062d \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0629',
                  'Unlock chat',
                )
              : _t(
                  '\u0642\u0641\u0644 \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0629',
                  'Lock chat',
                ),
          onTap: () => _runCommunityDrawerAction(_toggleChatLock),
        ),
      );
      tools.add(
        MaslakiDrawerEntry(
          icon: Icons.person_off_outlined,
          label: _t(
            '\u0625\u062f\u0627\u0631\u0629 \u0623\u0639\u0636\u0627\u0621 \u0627\u0644\u0645\u062d\u0627\u062f\u062b\u0629',
            'Manage chat members',
          ),
          onTap: () => _runCommunityDrawerAction(_openChatModerationSheet),
        ),
      );
    }
    if (_canManageAnnouncements) {
      tools.add(
        MaslakiDrawerEntry(
          icon: Icons.campaign_outlined,
          label: _t(
            '\u0625\u0636\u0627\u0641\u0629 \u062a\u0628\u0644\u064a\u063a',
            'Add announcement',
          ),
          onTap: () => _runCommunityDrawerAction(_createAnnouncement),
        ),
      );
    }
    if (_canManageBills) {
      tools.add(
        MaslakiDrawerEntry(
          icon: Icons.receipt_long_rounded,
          label: _t(
            '\u0625\u0636\u0627\u0641\u0629 \u0641\u0627\u062a\u0648\u0631\u0629',
            'Add bill',
          ),
          onTap: () => _runCommunityDrawerAction(_createBill),
        ),
      );
    }

    return <MaslakiDrawerSection>[
      MaslakiDrawerSection(
        title: _scopeTitle.isEmpty ? _scopeHomeTitle() : _scopeTitle,
        entries: communityEntries,
      ),
      MaslakiDrawerSection(
        title: _t(
          '\u0625\u062c\u0631\u0627\u0621\u0627\u062a \u0627\u0644\u0635\u0641\u062d\u0629',
          'Page actions',
        ),
        entries: tools,
      ),
    ];
  }

  Widget _buildScopeTopQuickControls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: SocialFeedActionStrip(
        onOpenSearch: () {
          Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SocialSearchScreen()),
          );
        },
        onOpenCreateMenu: _openScopedCreatePostSheet,
      ),
    );
  }

  void _handleVoiceComposerChanged() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _stopCommunityTyping();
      unawaited(_handleVoiceLifecyclePause());
    }
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    _chatPollTimer?.cancel();
    _chatReconnectTimer?.cancel();
    _typingStopTimer?.cancel();
    _peerTypingResetTimer?.cancel();
    _chatSearchDebounceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    ActiveChatContextRegistry.leaveCommunityScope(
      scopeType: _scopeType,
      scopeCode: _scopeCode,
    );
    _voiceComposer
      ..removeListener(_handleVoiceComposerChanged)
      ..dispose();
    _chatCtrl.dispose();
    _chatSearchCtrl.dispose();
    _chatScrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrapCommunityRealtime() async {
    await _reload();
    if (!mounted) return;
    _connectCommunityRealtime();
    _chatPollTimer?.cancel();
    _chatPollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || _tab != 2) return;
      final route = ModalRoute.of(context);
      if (route?.isCurrent != true) return;
      if (_communityRealtimeConnected) {
        _communityConnectedPollTick = (_communityConnectedPollTick + 1) % 6;
        if (_communityConnectedPollTick != 0) return;
      }
      _reloadCommunityChatOnly(silent: true);
    });
    _syncActiveCommunityChatContext();
  }

  void _snack(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: context.appTextDirection),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  void _syncActiveCommunityChatContext() {
    if (!mounted) return;
    if (_tab == 2) {
      ActiveChatContextRegistry.enterCommunityScope(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
      );
    } else {
      ActiveChatContextRegistry.leaveCommunityScope(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
      );
    }
  }

  Future<void> _markCommunityChatNotificationsRead() async {
    await ref
        .read(notificationsControllerProvider.notifier)
        .markSocialCommunityNotificationsRead(
          scopeType: _scopeType,
          scopeCode: _scopeCode,
        );
  }

  void _connectCommunityRealtime() {
    _liveSub?.cancel();
    _chatReconnectTimer?.cancel();
    _communityRealtimeConnected = false;
    _communityConnectedPollTick = 0;
    _liveSub = _liveApi
        .streamEvents(lastEventId: _chatLastEventId, channel: 'social')
        .listen(
          _onCommunityRealtimeEvent,
          onError: (_) => _scheduleCommunityReconnect(),
          onDone: _scheduleCommunityReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleCommunityReconnect() {
    if (!mounted) return;
    _communityRealtimeConnected = false;
    _communityConnectedPollTick = 0;
    if (_chatReconnectTimer?.isActive == true) return;
    _chatReconnectAttempt = (_chatReconnectAttempt + 1).clamp(1, 8);
    final delaySeconds = switch (_chatReconnectAttempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 12,
      _ => 16,
    };
    _chatReconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) return;
      _connectCommunityRealtime();
    });
  }

  bool _acceptCommunityRealtimeEvent(int? eventId) {
    if (eventId == null || eventId <= 0) return true;
    if (_chatLastEventId != null && eventId <= _chatLastEventId!) return false;
    _chatLastEventId = eventId;
    return true;
  }

  bool _matchesRealtimeScope(Map<String, dynamic> data) {
    final rawScope = data['scope'];
    if (rawScope is! Map) return false;
    final scope = Map<String, dynamic>.from(rawScope);
    final type = '${scope['scopeType'] ?? scope['scope_type'] ?? ''}'
        .trim()
        .toLowerCase();
    final code = '${scope['scopeCode'] ?? scope['scope_code'] ?? ''}'
        .trim()
        .toUpperCase();
    return type == _scopeType && code == _scopeCode;
  }

  Future<void> _onCommunityRealtimeEvent(NotificationLiveEvent event) async {
    _communityRealtimeConnected = true;
    _communityConnectedPollTick = 0;
    _chatReconnectAttempt = 0;
    if (event.event == 'resync_required') {
      _chatLastEventId = int.tryParse('${event.data['latestEventId'] ?? ''}');
      await _reloadCommunityChatOnly(silent: true);
      return;
    }
    if (!_acceptCommunityRealtimeEvent(event.eventId)) return;
    if (!_matchesRealtimeScope(event.data)) return;

    if (event.event == 'social_community_chat_typing') {
      final actorUserId = int.tryParse(
        '${event.data['actorUserId'] ?? event.data['actor_user_id'] ?? ''}',
      );
      final currentUserId = _currentUserId;
      if (actorUserId == null || actorUserId == currentUserId) return;
      _handleCommunityPeerTypingEvent(
        event.data['typing'] == true,
        actorName:
            '${event.data['actorDisplayName'] ?? event.data['actor_display_name'] ?? ''}'
                .trim(),
      );
      return;
    }

    if (event.event == 'social_community_chat_message') {
      final rawMessage = event.data['message'];
      if (rawMessage is Map) {
        try {
          final next = SocialCommunityChatMessage.fromJson(
            Map<String, dynamic>.from(rawMessage),
          );
          final nearBottom = _isNearCommunityBottom();
          if (!mounted) return;
          setState(() {
            _chatMessages = [
              ..._chatMessages.where((m) => m.id != next.id),
              next,
            ]..sort((a, b) => a.id.compareTo(b.id));
          });
          if (nearBottom) {
            _scrollCommunityChatToBottom();
          }
          final route = ModalRoute.of(context);
          if (_tab == 2 && route?.isCurrent == true) {
            await _markCommunityChatNotificationsRead();
          }
          return;
        } catch (_) {
          // Fallback to direct API sync.
        }
      }
      await _reloadCommunityChatOnly(silent: true);
      return;
    }

    if (event.event == 'social_community_chat_message_deleted' ||
        event.event == 'social_community_chat_message_updated' ||
        event.event == 'social_community_chat_message_reaction' ||
        event.event == 'social_community_chat_lock_updated' ||
        event.event == 'social_community_chat_user_restricted' ||
        event.event == 'social_community_chat_user_restored') {
      await _reloadCommunityChatOnly(silent: true);
      return;
    }

    if (event.event == 'social_community_member_removed' ||
        event.event == 'social_community_member_restored') {
      await _reload(silent: true);
    }
  }

  bool _isNearCommunityBottom({double threshold = 180}) {
    if (!_chatScrollCtrl.hasClients) return true;
    final max = _chatScrollCtrl.position.maxScrollExtent;
    final current = _chatScrollCtrl.offset;
    return (max - current) <= threshold;
  }

  void _scrollCommunityChatToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_chatScrollCtrl.hasClients) return;
      _chatScrollCtrl.animateTo(
        _chatScrollCtrl.position.maxScrollExtent + 40,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _handleCommunityPeerTypingEvent(bool typing, {String? actorName}) {
    _peerTypingResetTimer?.cancel();
    if (!typing) {
      if (!mounted) return;
      setState(() {
        _peerTyping = false;
        _peerTypingActorName = null;
      });
      return;
    }
    if (!mounted) return;
    setState(() {
      _peerTyping = true;
      _peerTypingActorName = actorName;
    });
    _peerTypingResetTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      setState(() {
        _peerTyping = false;
        _peerTypingActorName = null;
      });
    });
  }

  Future<void> _emitCommunityTyping(bool typing) async {
    final now = DateTime.now();
    if (_lastTypingSent == typing &&
        _lastTypingEmitAt != null &&
        now.difference(_lastTypingEmitAt!) <
            const Duration(milliseconds: 900)) {
      return;
    }
    _lastTypingSent = typing;
    _lastTypingEmitAt = now;
    try {
      await _api.emitCommunityChatTyping(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        typing: typing,
      );
    } catch (_) {}
  }

  void _stopCommunityTyping() {
    _typingStopTimer?.cancel();
    if (!_typingActive) return;
    _typingActive = false;
    unawaited(_emitCommunityTyping(false));
  }

  void _handleCommunityComposerChanged(String value) {
    if (_sending ||
        _voiceComposerBusy ||
        _isBanned ||
        (_chatLocked && !_canManageChat)) {
      return;
    }
    final hasText = value.trim().isNotEmpty;
    if (_communityComposerHasText != hasText) {
      _communityComposerHasText = hasText;
      if (mounted) setState(() {});
    }
    if (!hasText) {
      _stopCommunityTyping();
      return;
    }
    if (!_typingActive) {
      _typingActive = true;
      unawaited(_emitCommunityTyping(true));
    }
    _typingStopTimer?.cancel();
    _typingStopTimer = Timer(const Duration(seconds: 2), _stopCommunityTyping);
  }

  void _handleCommunitySearchTextChanged() {
    final next = _chatSearchCtrl.text.trim();
    if (next == _chatSearchQuery) return;
    setState(() => _chatSearchQuery = next);
    _chatSearchDebounceTimer?.cancel();
    if (next.isEmpty) {
      if (!mounted) return;
      setState(() {
        _chatSearchLoading = false;
        _chatSearchError = null;
        _chatSearchResults = const [];
        _chatSearchResultIndex = 0;
        _highlightedChatMessageId = null;
      });
      return;
    }
    setState(() {
      _chatSearchLoading = true;
      _chatSearchError = null;
    });
    _chatSearchDebounceTimer = Timer(
      const Duration(milliseconds: 260),
      _runCommunitySearch,
    );
  }

  Future<void> _runCommunitySearch() async {
    final query = _chatSearchQuery.trim();
    if (query.isEmpty) return;
    try {
      final out = await _api.searchCommunityChatMessages(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        search: query,
        limit: 20,
      );
      final results =
          List<dynamic>.from(out['messages'] as List? ?? const [])
              .map(
                (entry) => SocialCommunityChatMessage.fromJson(
                  Map<String, dynamic>.from(entry as Map),
                ),
              )
              .toList(growable: false)
            ..sort((a, b) => a.id.compareTo(b.id));
      if (!mounted || query != _chatSearchQuery.trim()) return;
      setState(() {
        _chatSearchLoading = false;
        _chatSearchError = null;
        _chatSearchResults = results;
        _chatSearchResultIndex = results.isEmpty ? 0 : 0;
      });
      if (results.isNotEmpty) {
        _focusCommunitySearchResult(0);
      }
    } catch (error) {
      if (!mounted || query != _chatSearchQuery.trim()) return;
      setState(() {
        _chatSearchLoading = false;
        _chatSearchResults = const [];
        _chatSearchResultIndex = 0;
        _chatSearchError = mapAnyError(
          error,
          fallback: _t(
            'تعذر البحث داخل المحادثة.',
            'Unable to search this chat.',
          ),
        );
      });
    }
  }

  void _toggleCommunitySearchMode() {
    if (!_chatSearchMode) {
      setState(() => _chatSearchMode = true);
      return;
    }
    _chatSearchDebounceTimer?.cancel();
    _chatSearchCtrl.clear();
    setState(() {
      _chatSearchMode = false;
      _chatSearchLoading = false;
      _chatSearchError = null;
      _chatSearchResults = const [];
      _chatSearchResultIndex = 0;
      _highlightedChatMessageId = null;
    });
  }

  void _jumpToCommunitySearchResult(int delta) {
    if (_chatSearchResults.isEmpty) return;
    final count = _chatSearchResults.length;
    final nextIndex = (_chatSearchResultIndex + delta) % count;
    _focusCommunitySearchResult(nextIndex < 0 ? nextIndex + count : nextIndex);
  }

  void _focusCommunitySearchResult(int index) {
    if (index < 0 || index >= _chatSearchResults.length) return;
    final target = _chatSearchResults[index];
    final merged = <int, SocialCommunityChatMessage>{
      for (final message in _chatMessages) message.id: message,
      target.id: target,
    }.values.toList(growable: false)..sort((a, b) => a.id.compareTo(b.id));
    setState(() {
      _chatMessages = merged;
      _chatSearchResultIndex = index;
      _highlightedChatMessageId = target.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _chatMessageItemKeys[target.id];
      final context = key?.currentContext;
      if (context != null) {
        Scrollable.ensureVisible(
          context,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: 0.2,
        );
      } else {
        _scrollCommunityChatToBottom();
      }
    });
  }

  Future<void> _reloadCommunityChatOnly({bool silent = false}) async {
    try {
      final chat = await _api.listCommunityChatMessages(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        limit: 120,
      );
      final messages =
          List<dynamic>.from(chat['messages'] as List? ?? const [])
              .map(
                (e) => SocialCommunityChatMessage.fromJson(
                  Map<String, dynamic>.from(e as Map),
                ),
              )
              .toList(growable: false)
            ..sort((a, b) => a.id.compareTo(b.id));

      if (!mounted) return;
      setState(() {
        _chatMessages = messages;
        _chatLocked = chat['chatLocked'] == true;
        _isBanned = chat['isBanned'] == true;
      });
      final route = ModalRoute.of(context);
      if (_tab == 2 && route?.isCurrent == true) {
        await _markCommunityChatNotificationsRead();
      }
      if (!silent) {
        _scrollCommunityChatToBottom();
      }
    } catch (_) {
      // keep current snapshot; full reload/pull-to-refresh will recover
    }
  }

  Future<void> _reload({bool silent = false}) async {
    if (!mounted) return;
    setState(() {
      _loading = !silent;
      if (!silent) _error = null;
    });
    try {
      final coreOut = await Future.wait([
        _api.listCommunityFeed(
          scopeType: _scopeType,
          scopeCode: _scopeCode,
          limit: 25,
        ),
        _api.listCommunityChatMessages(
          scopeType: _scopeType,
          scopeCode: _scopeCode,
          limit: 120,
        ),
        _api.listCommunityBills(
          scopeType: _scopeType,
          scopeCode: _scopeCode,
          category: _billCategory,
          limit: 120,
        ),
        _api.listCommunityManagers(
          scopeType: _scopeType,
          scopeCode: _scopeCode,
        ),
      ]);
      final feed = Map<String, dynamic>.from(coreOut[0]);
      final chat = Map<String, dynamic>.from(coreOut[1]);
      final bills = Map<String, dynamic>.from(coreOut[2]);
      final managers = Map<String, dynamic>.from(coreOut[3]);
      Map<String, dynamic> ann = const {'announcements': <dynamic>[]};
      try {
        final annOut = await _api.listCommunityAnnouncements(
          scopeType: _scopeType,
          scopeCode: _scopeCode,
          limit: 50,
        );
        ann = Map<String, dynamic>.from(annOut);
      } catch (_) {
        ann = const {'announcements': <dynamic>[]};
      }
      final scope = Map<String, dynamic>.from(
        feed['scope'] as Map? ?? ann['scope'] as Map? ?? const {},
      );
      if (!mounted) return;
      setState(() {
        _scopeTitle = '${scope['title'] ?? _scopeTitle}'.trim();
        _scopeSubtitle = '${scope['subtitle'] ?? ''}'.trim();
        _posts = List<dynamic>.from(feed['posts'] as List? ?? const [])
            .map(
              (e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false);
        _announcements =
            List<dynamic>.from(ann['announcements'] as List? ?? const [])
                .map(
                  (e) => SocialCommunityAnnouncement.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList(growable: false);
        _chatMessages =
            List<dynamic>.from(chat['messages'] as List? ?? const [])
                .map(
                  (e) => SocialCommunityChatMessage.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList(growable: false)
              ..sort((a, b) => a.id.compareTo(b.id));
        _bills = List<dynamic>.from(bills['bills'] as List? ?? const [])
            .map(
              (e) => SocialCommunityBill.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(growable: false);
        _managers =
            List<dynamic>.from(managers['managers'] as List? ?? const [])
                .map(
                  (e) => SocialCommunityManager.fromJson(
                    Map<String, dynamic>.from(e as Map),
                  ),
                )
                .toList(growable: false);
        _canManageAnnouncements = ann['canManageAnnouncements'] == true;
        _canManageChat = chat['canManageChat'] == true;
        _canManageBills = bills['canManageBills'] == true;
        _canManageManagers = managers['canManageManagers'] == true;
        _chatLocked = chat['chatLocked'] == true;
        _isBanned = chat['isBanned'] == true;
        _loading = false;
      });
      final route = ModalRoute.of(context);
      if (_tab == 2 && route?.isCurrent == true) {
        await _markCommunityChatNotificationsRead();
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_chatScrollCtrl.hasClients) {
          _chatScrollCtrl.jumpTo(_chatScrollCtrl.position.maxScrollExtent);
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapDioError(
          e,
          fallback: _t(
            'تعذر تحميل مجتمع السكن.',
            'Failed to load housing community.',
          ),
          customMessages: communityApiMessages(context),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: _t('تعذر تحميل البيانات.', 'Failed to load data.'),
        );
      });
    }
  }

  Future<void> _sendChat() async {
    final text = _chatCtrl.text.trim();
    final sharedDraft = _chatSharedEntityDraft;
    if ((text.isEmpty &&
            _chatAttachmentDraft == null &&
            _voiceComposer.state.draft == null &&
            sharedDraft == null) ||
        _sending ||
        _voiceComposerBusy) {
      return;
    }
    final replyTo = _replyingToMessage;
    _stopCommunityTyping();
    setState(() => _sending = true);
    try {
      final out = await _api.sendCommunityChatMessage(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        body: text,
        replyToMessageId: replyTo?.id,
        attachmentFile:
            _voiceComposer.state.draft?.file ?? _chatAttachmentDraft,
        attachmentDurationMs: _voiceComposer.state.draft?.durationMs,
        sharedEntityType: sharedDraft?.type,
        sharedEntityId: sharedDraft?.id,
        sharedSnapshot: sharedDraft?.snapshot,
      );
      _applySentCommunityMessage(out);
      if (!mounted) return;
      setState(() {
        _chatCtrl.clear();
        _communityComposerHasText = false;
        _replyingToMessage = null;
        _chatAttachmentDraft = null;
        _chatSharedEntityDraft = null;
      });
      if (_voiceComposer.state.draft != null) {
        await _voiceComposer.discardDraft();
      }
      _scrollCommunityChatToBottom();
    } on DioException catch (e) {
      if (!mounted) return;
      _snack(
        mapDioError(
          e,
          fallback: sharedDraft?.type == 'location'
              ? _t(
                  'تعذر مشاركة الموقع الآن.',
                  'Unable to share location right now.',
                )
              : _t('تعذر إرسال الرسالة.', 'Failed to send message.'),
          customMessages: communityApiMessages(context),
        ),
        error: true,
      );
    } catch (e) {
      if (!mounted) return;
      _snack(
        mapAnyError(
          e,
          fallback: sharedDraft?.type == 'location'
              ? _t(
                  'تعذر مشاركة الموقع الآن.',
                  'Unable to share location right now.',
                )
              : _t('تعذر إرسال الرسالة.', 'Failed to send message.'),
        ),
        error: true,
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _pickCommunityChatAttachment(
    _CommunityChatComposerAttachmentAction action,
  ) async {
    if (_sending || _voiceComposerBusy) return;
    try {
      if (action == _CommunityChatComposerAttachmentAction.location) {
        final draft = await _buildCommunityLocationDraft();
        if (!mounted || draft == null) return;
        setState(() {
          _chatSharedEntityDraft = draft;
          _chatAttachmentDraft = null;
        });
        return;
      }
      final file = switch (action) {
        _CommunityChatComposerAttachmentAction.image =>
          await pickChatImageFromDevice(),
        _CommunityChatComposerAttachmentAction.video =>
          await pickChatVideoFromDevice(),
        _CommunityChatComposerAttachmentAction.file =>
          await pickChatFileFromDevice(),
        _CommunityChatComposerAttachmentAction.location => null,
      };
      if (!mounted || file == null) return;
      setState(() {
        _chatAttachmentDraft = file;
        _chatSharedEntityDraft = null;
      });
    } catch (error) {
      if (!mounted) return;
      _snack(
        mapAnyError(
          error,
          fallback: _t('تعذر اختيار المرفق.', 'Unable to pick attachment.'),
        ),
        error: true,
      );
    }
  }

  Future<void> _openCommunityAttachmentsMenu() async {
    if (_sending || _voiceComposerBusy) return;
    final action =
        await showModalBottomSheet<_CommunityChatComposerAttachmentAction>(
          context: context,
          showDragHandle: true,
          builder: (sheetContext) => SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.location_on_outlined),
                  title: Text(_t('مشاركة الموقع', 'Share location')),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_CommunityChatComposerAttachmentAction.location),
                ),
                ListTile(
                  leading: const Icon(Icons.insert_drive_file_outlined),
                  title: Text(_t('ملف', 'File')),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_CommunityChatComposerAttachmentAction.file),
                ),
                ListTile(
                  leading: const Icon(Icons.image_outlined),
                  title: Text(_t('صورة', 'Image')),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_CommunityChatComposerAttachmentAction.image),
                ),
                ListTile(
                  leading: const Icon(Icons.videocam_outlined),
                  title: Text(_t('فيديو', 'Video')),
                  onTap: () => Navigator.of(
                    sheetContext,
                  ).pop(_CommunityChatComposerAttachmentAction.video),
                ),
              ],
            ),
          ),
        );
    if (!mounted || action == null) return;
    await _pickCommunityChatAttachment(action);
  }

  Future<void> _openCommunityStickersGifMenu() async {
    if (_sending || _voiceComposerBusy) return;
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
                    _t('الملصقات و GIF', 'Stickers & GIF'),
                    style: Theme.of(sheetContext).textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: ['😀', '😍', '🔥', '👏', '👍', '💯']
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
                _snack(
                  _t(
                    'ميزة GIF تحتاج إعداد Tenor.',
                    'GIF requires Tenor configuration.',
                  ),
                );
              },
              icon: const Icon(Icons.gif_box_outlined),
              label: Text(_t('فتح GIF', 'Open GIF')),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (!mounted || (selectedText ?? '').trim().isEmpty) return;
    final current = _chatCtrl.text;
    final prefix = current.trim().isEmpty ? '' : '$current ';
    _chatCtrl.value = TextEditingValue(
      text: '$prefix${selectedText!.trim()}',
      selection: TextSelection.collapsed(
        offset: '$prefix${selectedText.trim()}'.length,
      ),
    );
    _communityComposerHasText = _chatCtrl.text.trim().isNotEmpty;
    if (mounted) setState(() {});
  }

  Future<SocialSharedEntity?> _buildCommunityLocationDraft() async {
    final service = ref.read(locationPermissionServiceProvider);
    var status = await service.getStatus();
    if (!status.isGranted || !status.serviceEnabled) {
      status = await service.requestPermission();
    }
    if (!status.serviceEnabled || !status.isGranted) {
      if (!mounted) return null;
      _snack(
        _t(
          'يجب منح صلاحية الموقع لمشاركة موقعك الحالي.',
          'Location permission is required to share your current location.',
        ),
        error: true,
      );
      return null;
    }
    final position = await service.getCurrentPosition();
    if (position == null) {
      if (!mounted) return null;
      _snack(
        _t('تعذر قراءة موقعك الحالي الآن.', 'Unable to read your location.'),
        error: true,
      );
      return null;
    }
    final lat = position.latitude;
    final lng = position.longitude;
    return SocialSharedEntity(
      type: 'location',
      id: DateTime.now().millisecondsSinceEpoch,
      snapshot: <String, dynamic>{
        'title': _t('موقعي الحالي', 'My current location'),
        'address': '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}',
        'latitude': lat,
        'longitude': lng,
      },
    );
  }

  Future<void> _handleVoiceLifecyclePause() async {
    final result = await _voiceComposer.handleAppPause();
    _handleVoiceResult(
      result,
      fallbackMessage: _t(
        'تعذر تجهيز الرسالة الصوتية.',
        'Unable to prepare the voice message.',
      ),
    );
  }

  bool get _voiceComposerBusy =>
      _voiceComposer.state.isRecording ||
      _voiceComposer.state.hasPreview ||
      _voiceComposer.state.isSending;

  Future<void> _startVoiceHold() async {
    if (_sending || _voiceComposerBusy) return;
    final result = await _voiceComposer.startHolding(
      draftKey: 'community_${_scopeType}_$_scopeCode',
    );
    if (result.type == SocialVoiceComposerResultType.started) {
      HapticFeedback.mediumImpact();
      return;
    }
    _handleVoiceResult(
      result,
      fallbackMessage: _t(
        'تعذر بدء التسجيل الصوتي.',
        'Unable to start voice recording.',
      ),
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

  Future<void> _finishVoiceHold() async {
    final result = await _voiceComposer.releaseHoldToPreview();
    _handleVoiceResult(
      result,
      fallbackMessage: _t(
        'تعذر تجهيز الرسالة الصوتية.',
        'Unable to prepare the voice message.',
      ),
    );
  }

  Future<void> _stopLockedVoiceRecording() async {
    final result = await _voiceComposer.stopLockedRecordingToPreview();
    _handleVoiceResult(
      result,
      fallbackMessage: _t(
        'تعذر تجهيز الرسالة الصوتية.',
        'Unable to prepare the voice message.',
      ),
    );
  }

  Future<void> _cancelVoiceComposer() async {
    await _voiceComposer.cancelRecording();
  }

  Future<void> _sendVoiceDraft() async {
    final replyTo = _replyingToMessage;
    _stopCommunityTyping();
    final result = await _voiceComposer.sendDraft((draft) async {
      final out = await _api.sendCommunityChatMessage(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        body: '',
        replyToMessageId: replyTo?.id,
        attachmentFile: draft.file,
        attachmentDurationMs: draft.durationMs,
      );
      _applySentCommunityMessage(out);
      if (!mounted) return;
      setState(() => _replyingToMessage = null);
      _scrollCommunityChatToBottom();
    });
    if (result.type == SocialVoiceComposerResultType.failed) {
      if (!mounted) return;
      _snack(
        mapAnyError(
          result.error ?? StateError('COMMUNITY_VOICE_SEND_FAILED'),
          fallback: _t(
            'تعذر إرسال الرسالة الصوتية.',
            'Unable to send the voice message.',
          ),
        ),
        error: true,
      );
    }
  }

  void _handleVoiceResult(
    SocialVoiceComposerResult result, {
    required String fallbackMessage,
  }) {
    if (!mounted) return;
    switch (result.type) {
      case SocialVoiceComposerResultType.permissionDenied:
        _snack(
          _t(
            'يجب منح إذن المايكروفون لتسجيل رسالة صوتية.',
            'Microphone permission is required to record a voice message.',
          ),
          error: true,
        );
        break;
      case SocialVoiceComposerResultType.tooShort:
        _snack(
          _t('التسجيل الصوتي قصير جدًا.', 'The voice recording is too short.'),
          error: true,
        );
        break;
      case SocialVoiceComposerResultType.failed:
        _snack(
          mapAnyError(
            result.error ?? StateError('COMMUNITY_VOICE_FAILED'),
            fallback: fallbackMessage,
          ),
          error: true,
        );
        break;
      default:
        break;
    }
  }

  void _applySentCommunityMessage(Map<String, dynamic> out) {
    final raw = out['message'];
    if (raw is! Map) return;
    final item = SocialCommunityChatMessage.fromJson(
      Map<String, dynamic>.from(raw),
    );
    if (!mounted) return;
    setState(() {
      _chatMessages = [..._chatMessages.where((m) => m.id != item.id), item]
        ..sort((a, b) => a.id.compareTo(b.id));
    });
  }

  String _communityReplyPreviewText(SocialCommunityChatMessage message) {
    final body = message.body.trim();
    if (body.isNotEmpty) return body;
    final attachment = message.attachment;
    if (attachment != null) return attachment.previewLabel;
    if (message.sharedEntity != null) return message.sharedEntity!.previewLabel;
    return _t('الرد على رسالة', 'Replying to a message');
  }

  Future<void> _openCommunityAttachment(SocialChatAttachment attachment) async {
    final kind = attachment.kind.trim().toLowerCase();
    if (kind == 'image') {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          insetPadding: const EdgeInsets.all(12),
          backgroundColor: Colors.black,
          child: InteractiveViewer(
            minScale: 0.8,
            maxScale: 4,
            child: CachedAppImage(
              imageUrl: attachment.url,
              fit: BoxFit.contain,
            ),
          ),
        ),
      );
      return;
    }
    final uri = Uri.tryParse(attachment.url);
    if (uri == null) {
      _snack(
        _t('رابط المرفق غير صالح.', 'Invalid attachment link.'),
        error: true,
      );
      return;
    }
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      _snack(_t('تعذر فتح المرفق.', 'Failed to open attachment.'), error: true);
    }
  }

  Future<void> _toggleChatLock() async {
    try {
      await _api.setCommunityChatLock(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        locked: !_chatLocked,
      );
      setState(() => _chatLocked = !_chatLocked);
      _snack(
        _chatLocked
            ? _t('تم قفل المحادثة.', 'Chat locked.')
            : _t('تم فتح المحادثة.', 'Chat unlocked.'),
      );
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t(
            'تعذر تحديث حالة المحادثة.',
            'Failed to update chat lock state.',
          ),
        ),
        error: true,
      );
    }
  }

  Future<void> _openChatModerationSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CommunityChatModerationSheet(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
      ),
    );
    if (!mounted) return;
    await _reload(silent: true);
  }

  Future<void> _openManagerAssignmentSheet() async {
    final selectedUserId = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => CommunityManagerSearchSheet(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
      ),
    );
    if (selectedUserId == null || !mounted) return;
    try {
      await _api.assignCommunityManager(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        managerUserId: selectedUserId,
      );
      _snack(_t('تم تعيين المدير بنجاح.', 'Manager assigned successfully.'));
      await _reload(silent: true);
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t('تعذر تعيين المدير.', 'Failed to assign manager.'),
        ),
        error: true,
      );
    }
  }

  Future<void> _removeManager(int userId) async {
    try {
      await _api.revokeCommunityManager(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        userId: userId,
      );
      _snack(_t('تمت إزالة المدير.', 'Manager removed.'));
      await _reload(silent: true);
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t('تعذر إزالة المدير.', 'Failed to remove manager.'),
        ),
        error: true,
      );
    }
  }

  Future<void> _createAnnouncement() async {
    final titleCtrl = TextEditingController();
    final bodyCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.campaign_rounded),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _t('إضافة تبليغ جديد', 'Add new announcement'),
                textDirection: context.appTextDirection,
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Theme.of(context).colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.6),
                  ),
                  child: Text(
                    _t(
                      'هذا التبليغ سيظهر لجميع أعضاء هذا القسم حسب صلاحيات الوصول.',
                      'This announcement will be visible to all members in this scope.',
                    ),
                    textDirection: context.appTextDirection,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  _t('بيانات التبليغ', 'Announcement details'),
                  textDirection: context.appTextDirection,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: titleCtrl,
                  textDirection: context.appTextDirection,
                  maxLength: 90,
                  textInputAction: TextInputAction.next,
                  decoration: InputDecoration(
                    labelText: _t('العنوان', 'Title'),
                    hintText: _t(
                      'مثال: قطع ماء اليوم من 2 إلى 5 مساءً',
                      'Example: Water outage today from 2 to 5 PM',
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: bodyCtrl,
                  textDirection: context.appTextDirection,
                  minLines: 4,
                  maxLines: 8,
                  maxLength: 500,
                  decoration: InputDecoration(
                    labelText: _t('تفاصيل التبليغ', 'Announcement body'),
                    hintText: _t(
                      'اكتب التفاصيل بشكل واضح ومختصر.',
                      'Write clear and concise details.',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(false),
            icon: const Icon(Icons.close_rounded),
            label: Text(_t('إلغاء', 'Cancel')),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.campaign_rounded),
            label: Text(_t('نشر التبليغ', 'Publish announcement')),
          ),
        ],
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    final body = bodyCtrl.text.trim();
    if (title.isEmpty || body.isEmpty) {
      _snack(
        _t(
          'يرجى إدخال عنوان ومحتوى التبليغ.',
          'Please enter title and body for announcement.',
        ),
        error: true,
      );
      return;
    }
    try {
      await _api.createCommunityAnnouncement(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        title: title,
        body: body,
      );
      _snack(_t('تم نشر التبليغ.', 'Announcement published.'));
      await _reload(silent: true);
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t('تعذر نشر التبليغ.', 'Failed to publish announcement.'),
        ),
        error: true,
      );
    } finally {
      titleCtrl.dispose();
      bodyCtrl.dispose();
    }
  }

  String? _normalizeApartmentCode(String raw) {
    final normalized = raw.trim().toUpperCase();
    if (RegExp(r'^G(0[1-9]|1[0-2])$').hasMatch(normalized)) {
      return normalized;
    }
    if (RegExp(r'^[1-9](0[1-9]|1[0-2])$').hasMatch(normalized)) {
      return normalized;
    }
    return null;
  }

  List<String> _buildingApartmentCodes() {
    final codes = <String>[];
    for (var i = 1; i <= 12; i++) {
      codes.add('G${i.toString().padLeft(2, '0')}');
    }
    for (var floor = 1; floor <= 9; floor++) {
      for (var i = 1; i <= 12; i++) {
        codes.add('$floor${i.toString().padLeft(2, '0')}');
      }
    }
    return codes;
  }

  Future<void> _createBill() async {
    final titleCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final apartmentCtrl = TextEditingController();
    final dueDateCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    final apartmentCodes = _scopeType == 'building'
        ? _buildingApartmentCodes()
        : const <String>[];
    String? selectedApartment = apartmentCodes.isNotEmpty
        ? apartmentCodes.first
        : null;
    if (selectedApartment != null) {
      apartmentCtrl.text = selectedApartment;
    }
    String category = 'electricity';
    LocalMediaFile? attachment;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setInnerState) {
          Future<void> pickDueDate() async {
            final typed = dueDateCtrl.text.trim();
            final initial =
                DateTime.tryParse(typed) ??
                DateTime.now().add(const Duration(days: 7));
            final picked = await showDatePicker(
              context: context,
              initialDate: initial,
              firstDate: DateTime(2020),
              lastDate: DateTime(2100),
            );
            if (picked == null) return;
            dueDateCtrl.text = intl.DateFormat('yyyy-MM-dd').format(picked);
            setInnerState(() {});
          }

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: Row(
              children: [
                const Icon(Icons.receipt_long_rounded),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _t('إضافة فاتورة جديدة', 'Add new bill'),
                    textDirection: context.appTextDirection,
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _t('تصنيف الفاتورة', 'Bill classification'),
                      textDirection: context.appTextDirection,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: category,
                      decoration: InputDecoration(
                        labelText: _t('نوع الفاتورة', 'Bill category'),
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'electricity',
                          child: Text(_t('كهرباء', 'Electricity')),
                        ),
                        DropdownMenuItem(
                          value: 'water',
                          child: Text(_t('ماء', 'Water')),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text(_t('أخرى', 'Other')),
                        ),
                      ],
                      onChanged: (v) {
                        if (v == null) return;
                        setInnerState(() => category = v);
                      },
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _t('تحديد المستفيد', 'Target apartment'),
                      textDirection: context.appTextDirection,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    if (_scopeType == 'building') ...[
                      DropdownButtonFormField<String>(
                        key: ValueKey(selectedApartment ?? 'apartment-empty'),
                        initialValue: selectedApartment,
                        isExpanded: true,
                        menuMaxHeight: 320,
                        decoration: InputDecoration(
                          labelText: _t('اختر الشقة بسرعة', 'Quick apartment'),
                        ),
                        items: apartmentCodes
                            .map(
                              (code) => DropdownMenuItem<String>(
                                value: code,
                                child: Text(
                                  code,
                                  textDirection: TextDirection.ltr,
                                ),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (value) {
                          setInnerState(() {
                            selectedApartment = value;
                            apartmentCtrl.text = value ?? '';
                          });
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    TextField(
                      controller: apartmentCtrl,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: _scopeType == 'building'
                            ? _t(
                                'رقم الشقة (يمكنك التعديل يدويًا)',
                                'Apartment code (editable)',
                              )
                            : _t(
                                'رقم الشقة (اختياري)',
                                'Apartment code (optional)',
                              ),
                        hintText: 'G01 / 101 / 912',
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      _t('معلومات الفاتورة', 'Bill information'),
                      textDirection: context.appTextDirection,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: titleCtrl,
                      textDirection: context.appTextDirection,
                      decoration: InputDecoration(
                        labelText: _t('عنوان الفاتورة', 'Bill title'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: amountCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            decoration: InputDecoration(
                              labelText: _t(
                                'المبلغ (اختياري)',
                                'Amount (optional)',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            controller: dueDateCtrl,
                            textDirection: TextDirection.ltr,
                            decoration: InputDecoration(
                              labelText: _t('تاريخ الاستحقاق', 'Due date'),
                              hintText: 'YYYY-MM-DD',
                              helperText: _t(
                                'اكتب التاريخ أو اختره من التقويم',
                                'Type date or pick from calendar',
                              ),
                              suffixIcon: IconButton(
                                tooltip: _t(
                                  'اختيار من التقويم',
                                  'Pick from calendar',
                                ),
                                onPressed: pickDueDate,
                                icon: const Icon(Icons.calendar_today_rounded),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: detailsCtrl,
                      maxLines: 3,
                      textDirection: context.appTextDirection,
                      decoration: InputDecoration(
                        labelText: _t('تفاصيل الفاتورة', 'Bill details'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t('المرفقات', 'Attachments'),
                      textDirection: context.appTextDirection,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              final picked =
                                  await pickChatAttachmentFromDevice();
                              if (picked == null) return;
                              setInnerState(() => attachment = picked);
                            },
                            icon: const Icon(Icons.attach_file_rounded),
                            label: Text(
                              _t('إرفاق ملف/صورة', 'Attach file/image'),
                            ),
                          ),
                        ),
                        if (attachment != null) ...[
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: () =>
                                setInnerState(() => attachment = null),
                            icon: const Icon(Icons.close_rounded),
                            tooltip: _t('إزالة المرفق', 'Remove attachment'),
                          ),
                        ],
                      ],
                    ),
                    if (attachment != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          attachment!.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton.icon(
                onPressed: () => Navigator.of(context).pop(false),
                icon: const Icon(Icons.close_rounded),
                label: Text(_t('إلغاء', 'Cancel')),
              ),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(true),
                icon: const Icon(Icons.save_rounded),
                label: Text(_t('حفظ الفاتورة', 'Save bill')),
              ),
            ],
          );
        },
      ),
    );
    if (ok != true) return;
    final title = titleCtrl.text.trim();
    if (title.isEmpty) {
      _snack(
        _t('يرجى كتابة عنوان الفاتورة.', 'Please enter bill title.'),
        error: true,
      );
      return;
    }

    final apartmentRaw = apartmentCtrl.text.trim();
    final apartment = apartmentRaw.isEmpty
        ? null
        : _normalizeApartmentCode(apartmentRaw);
    if (_scopeType == 'building' && apartment == null) {
      _snack(
        _t(
          'أدخل رقم شقة صحيح مثل G01 أو 101.',
          'Enter a valid apartment code like G01 or 101.',
        ),
        error: true,
      );
      return;
    }
    if (_scopeType != 'building' &&
        apartmentRaw.isNotEmpty &&
        apartment == null) {
      _snack(
        _t(
          'رقم الشقة غير صالح. استخدم صيغة مثل G01 أو 101.',
          'Invalid apartment code. Use format like G01 or 101.',
        ),
        error: true,
      );
      return;
    }

    final dueDateRaw = dueDateCtrl.text.trim();
    if (dueDateRaw.isNotEmpty && DateTime.tryParse(dueDateRaw) == null) {
      _snack(
        _t(
          'تاريخ الاستحقاق غير صالح. استخدم YYYY-MM-DD أو اختر من التقويم.',
          'Invalid due date. Use YYYY-MM-DD or pick from calendar.',
        ),
        error: true,
      );
      return;
    }

    final amount = double.tryParse(amountCtrl.text.trim());
    try {
      await _api.createCommunityBill(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        category: category,
        title: title,
        apartment: apartment ?? '',
        amount: amount,
        dueDate: dueDateRaw.isEmpty ? null : dueDateRaw,
        details: detailsCtrl.text.trim().isEmpty
            ? null
            : detailsCtrl.text.trim(),
        attachmentFile: attachment,
      );
      _snack(_t('تمت إضافة الفاتورة.', 'Bill added.'));
      await _reload(silent: true);
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t('تعذر إضافة الفاتورة.', 'Failed to add bill.'),
        ),
        error: true,
      );
    } finally {
      titleCtrl.dispose();
      amountCtrl.dispose();
      apartmentCtrl.dispose();
      dueDateCtrl.dispose();
      detailsCtrl.dispose();
    }
  }

  Future<void> _openAuthorProfile(SocialAuthor author) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: author.id,
          initialName: author.fullName,
        ),
      ),
    );
  }

  Future<void> _openBillAttachment(SocialCommunityBill bill) async {
    final url = (bill.attachment?.url ?? '').trim();
    if (url.isEmpty) return;
    final uri = Uri.tryParse(url);
    if (uri == null) {
      _snack(
        _t('رابط المرفق غير صالح.', 'Invalid attachment link.'),
        error: true,
      );
      return;
    }
    final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!ok) {
      _snack(_t('تعذر فتح المرفق.', 'Failed to open attachment.'), error: true);
    }
  }

  int _asInt(dynamic value, {int fallback = 0}) {
    final parsed = int.tryParse('$value');
    if (parsed == null) return fallback;
    return parsed;
  }

  Future<void> _togglePostLike(SocialPost post) async {
    final optimistic = post.copyWith(
      isLiked: !post.isLiked,
      likesCount: (post.likesCount + (post.isLiked ? -1 : 1)).clamp(0, 999999),
    );
    setState(() {
      _posts = _posts
          .map((p) => p.id == post.id ? optimistic : p)
          .toList(growable: false);
    });
    try {
      final out = await _api.toggleLike(post.id);
      final next = optimistic.copyWith(
        isLiked: out['liked'] == true,
        likesCount: _asInt(out['likesCount'], fallback: optimistic.likesCount),
      );
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map((p) => p.id == post.id ? next : p)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map((p) => p.id == post.id ? post : p)
            .toList(growable: false);
      });
    }
  }

  Future<void> _togglePostSave(SocialPost post) async {
    final optimistic = post.copyWith(
      isSaved: !post.isSaved,
      savesCount: (post.savesCount + (post.isSaved ? -1 : 1)).clamp(0, 999999),
    );
    setState(() {
      _posts = _posts
          .map((p) => p.id == post.id ? optimistic : p)
          .toList(growable: false);
    });
    final entityType = post.postKind == 'merchant_review'
        ? 'review'
        : post.postKind == 'reel'
        ? 'reel'
        : 'post';
    try {
      final out = await _api.toggleSaved(
        entityType: entityType,
        entityId: post.id,
      );
      final next = optimistic.copyWith(
        isSaved: out['saved'] == true,
        savesCount: _asInt(out['savesCount'] ?? out['saves_count']),
      );
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map((p) => p.id == post.id ? next : p)
            .toList(growable: false);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _posts = _posts
            .map((p) => p.id == post.id ? post : p)
            .toList(growable: false);
      });
    }
  }

  Future<void> _openMerchantFromReview(SocialPost post) async {
    final merchantId = post.merchantId;
    if (merchantId == null || merchantId <= 0) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => MerchantsListScreen(
            initialSearchQuery: (post.merchantName ?? '').trim(),
            compactCustomerMode: true,
          ),
        ),
      );
      return;
    }

    final merchantName = (post.merchantName ?? '').trim();
    final merchantType = (post.merchantType ?? '').trim().toLowerCase();
    final merchant = MerchantModel(
      id: merchantId,
      name: merchantName.isEmpty ? _t('متجر', 'Store') : merchantName,
      type: merchantType.isEmpty ? 'market' : merchantType,
      description: null,
      phone: null,
      imageUrl: post.merchantImageUrl,
      tagline: null,
      workingHours: null,
      serviceAreaNote: null,
      isOpen: true,
      hasDiscountOffer: false,
      hasFreeDeliveryOffer: false,
    );

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantProductsScreen(merchant: merchant),
      ),
    );
  }

  Future<void> _openScopedCreatePostSheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => ScopedCommunityPostSheet(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
      ),
    );
    if (created == true && mounted) {
      await _reload(silent: true);
    }
  }

  void _startReplyToMessage(SocialCommunityChatMessage message) {
    if (!mounted) return;
    setState(() => _replyingToMessage = message);
  }

  bool _isCommunityMessageWithinEditDeleteWindow(
    SocialCommunityChatMessage message,
  ) {
    final createdAt = message.createdAt;
    if (createdAt == null) return false;
    return DateTime.now().difference(createdAt.toLocal()) <=
        const Duration(minutes: 5);
  }

  bool _canEditCommunityMessage(SocialCommunityChatMessage message) {
    return message.isMine &&
        !message.isSystem &&
        !message.isDeleted &&
        _isCommunityMessageWithinEditDeleteWindow(message);
  }

  bool _canDeleteCommunityMessage(SocialCommunityChatMessage message) {
    if (message.isDeleted) return false;
    if (_canManageChat && !message.isSystem) return true;
    return message.isMine &&
        !message.isSystem &&
        _isCommunityMessageWithinEditDeleteWindow(message);
  }

  Future<void> _toggleCommunityReaction(
    SocialCommunityChatMessage message,
    String reaction,
  ) async {
    try {
      final out = await _api.toggleCommunityChatMessageReaction(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        messageId: message.id,
        reaction: reaction,
      );
      final reactions = Map<String, dynamic>.from(
        out['reactions'] as Map? ?? const {},
      );
      final counts = Map<String, int>.fromEntries(
        Map<String, dynamic>.from(
          reactions['counts'] as Map? ?? const {},
        ).entries.map((e) => MapEntry(e.key, _asInt(e.value))),
      );
      final totalCount = _asInt(reactions['totalCount']);
      final myReaction = '${reactions['myReaction'] ?? ''}'.trim();
      if (!mounted) return;
      setState(() {
        _chatMessages = _chatMessages
            .map(
              (m) => m.id != message.id
                  ? m
                  : SocialCommunityChatMessage(
                      id: m.id,
                      scopeType: m.scopeType,
                      scopeCode: m.scopeCode,
                      senderUserId: m.senderUserId,
                      body: m.body,
                      replyToMessage: m.replyToMessage,
                      isSystem: m.isSystem,
                      isDeleted: m.isDeleted,
                      isMine: m.isMine,
                      createdAt: m.createdAt,
                      updatedAt: m.updatedAt,
                      editedAt: m.editedAt,
                      deletedAt: m.deletedAt,
                      reactionCounts: counts,
                      reactionTotalCount: totalCount,
                      myReaction: myReaction.isEmpty ? null : myReaction,
                      attachment: m.attachment,
                      sharedEntity: m.sharedEntity,
                      sender: m.sender,
                    ),
            )
            .toList(growable: false);
      });
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t('تعذر تحديث التفاعل.', 'Failed to update reaction.'),
        ),
        error: true,
      );
    }
  }

  Future<void> _editCommunityMessage(SocialCommunityChatMessage message) async {
    if (!_canEditCommunityMessage(message)) return;
    final ctrl = TextEditingController(text: message.body);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          _t('تعديل الرسالة', 'Edit message'),
          textDirection: context.appTextDirection,
        ),
        content: TextField(
          controller: ctrl,
          textDirection: context.appTextDirection,
          minLines: 2,
          maxLines: 6,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(_t('إلغاء', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(_t('حفظ', 'Save')),
          ),
        ],
      ),
    );
    if (ok != true) {
      ctrl.dispose();
      return;
    }
    final body = ctrl.text.trim();
    ctrl.dispose();
    if (body.isEmpty || body == message.body.trim()) return;
    try {
      final out = await _api.updateCommunityChatMessage(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        messageId: message.id,
        body: body,
      );
      final raw = out['message'];
      if (raw is Map && mounted) {
        final updated = SocialCommunityChatMessage.fromJson(
          Map<String, dynamic>.from(raw),
        );
        setState(() {
          _chatMessages = _chatMessages
              .map((m) => m.id == updated.id ? updated : m)
              .toList(growable: false);
        });
      }
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t('تعذر تعديل الرسالة.', 'Failed to edit message.'),
        ),
        error: true,
      );
    }
  }

  Future<void> _deleteCommunityMessage(
    SocialCommunityChatMessage message,
  ) async {
    if (!_canDeleteCommunityMessage(message)) return;
    try {
      final out = await _api.deleteCommunityChatMessage(
        scopeType: _scopeType,
        scopeCode: _scopeCode,
        messageId: message.id,
      );
      if (!mounted) return;
      final raw = out['message'];
      if (raw is Map) {
        final deleted = SocialCommunityChatMessage.fromJson(
          Map<String, dynamic>.from(raw),
        );
        setState(() {
          _chatMessages = _chatMessages
              .map((m) => m.id == deleted.id ? deleted : m)
              .toList(growable: false);
        });
      } else {
        setState(() {
          _chatMessages = _chatMessages
              .where((m) => m.id != message.id)
              .toList(growable: false);
        });
      }
    } catch (e) {
      _snack(
        mapAnyError(
          e,
          fallback: _t('تعذر حذف الرسالة.', 'Failed to delete message.'),
        ),
        error: true,
      );
    }
  }

  Future<void> _openCommunityMessageActions(
    SocialCommunityChatMessage message,
  ) async {
    final canEdit = _canEditCommunityMessage(message);
    final canDelete = _canDeleteCommunityMessage(message);
    final canReact = !message.isDeleted;
    final canReply = !message.isDeleted;
    if (!canEdit && !canDelete && !canReact && !canReply) return;

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (canEdit)
              ListTile(
                leading: const Icon(Icons.edit_outlined),
                title: Text(
                  _t('Edit', 'Edit'),
                  textDirection: context.appTextDirection,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _editCommunityMessage(message);
                },
              ),
            if (canDelete)
              ListTile(
                leading: const Icon(Icons.delete_outline_rounded),
                title: Text(
                  _t('Delete', 'Delete'),
                  textDirection: context.appTextDirection,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _deleteCommunityMessage(message);
                },
              ),
            if (canReact)
              Wrap(
                spacing: 6,
                children: [
                  for (final reaction in const [
                    'like',
                    'heart',
                    'laugh',
                    'fire',
                  ])
                    ActionChip(
                      label: Text(reaction),
                      onPressed: () {
                        Navigator.of(context).pop();
                        _toggleCommunityReaction(message, reaction);
                      },
                    ),
                ],
              ),
            if (canReply)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: Text(
                  _t('Reply', 'Reply'),
                  textDirection: context.appTextDirection,
                ),
                onTap: () {
                  Navigator.of(context).pop();
                  _startReplyToMessage(message);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openCreateStorySheet() async {
    final created = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const ScopedCommunityStorySheet(),
    );
    if (created != true || !mounted) return;
    _snack(_t('تم نشر الستوري بنجاح.', 'Story published successfully.'));
    await _reload();
  }

  Widget _buildSectionTabs() {
    final tabs = <(int, IconData, String)>[
      (0, Icons.feed_outlined, _t('منشورات', 'Posts')),
      (1, Icons.notifications_outlined, _t('تبليغات', 'Announcements')),
      (2, Icons.forum_outlined, _t('محادثة المجموعة', 'Group Chat')),
      (3, Icons.receipt_long_rounded, _t('فواتير', 'Bills')),
    ];
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 6),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        reverse: true,
        child: Row(
          children: [
            for (final item in tabs)
              Padding(
                padding: const EdgeInsets.only(left: 8),
                child: ChoiceChip(
                  selected: _tab == item.$1,
                  showCheckmark: false,
                  avatar: Icon(item.$2, size: 16),
                  label: Text(item.$3),
                  onSelected: (_) => _setTab(item.$1),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCards() {
    final stats = <(IconData, String, String, bool, VoidCallback)>[
      (
        Icons.feed_rounded,
        _t('منشورات', 'Posts'),
        '${_posts.length}',
        _tab == 0,
        () => _setTab(0),
      ),
      (
        Icons.campaign_rounded,
        _t('تبليغات', 'Announcements'),
        '${_announcements.length}',
        _tab == 1,
        () => _setTab(1),
      ),
      (
        Icons.forum_rounded,
        _t('رسائل', 'Messages'),
        '${_chatMessages.length}',
        _tab == 2,
        () => _setTab(2),
      ),
      (
        Icons.receipt_long_rounded,
        _t('فواتير', 'Bills'),
        '${_bills.length}',
        _tab == 3,
        () => _setTab(3),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      child: MaslakiCard(
        elevated: false,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
        child: Row(
          children: [
            for (var i = 0; i < stats.length; i++) ...[
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(18),
                  onTap: stats[i].$5,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(18),
                      color: stats[i].$4
                          ? context.maslakiTokens.primaryAccent.withValues(
                              alpha: 0.12,
                            )
                          : Colors.transparent,
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          stats[i].$1,
                          size: 16,
                          color: stats[i].$4
                              ? context.maslakiTokens.primaryAccent
                              : context.maslakiTokens.textMuted,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          stats[i].$3,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          stats[i].$2,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: context.maslakiTokens.textMuted,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (i != stats.length - 1)
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: context.maslakiTokens.borderSubtle.withValues(
                    alpha: 0.35,
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textDirection: context.appTextDirection),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: _reload,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_t('إعادة المحاولة', 'Retry')),
              ),
            ],
          ),
        ),
      );
    }
    if (_tab == 0) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              _t('منشورات المجتمع', 'Community Posts'),
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 8),
            if (_posts.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _t(
                      'لا توجد منشورات محلية في هذا القسم حالياً.',
                      'No local posts in this section yet.',
                    ),
                    textDirection: context.appTextDirection,
                  ),
                ),
              ),
            for (final p in _posts) ...[
              SocialPostCardV2(
                post: p,
                autoPlayVideoPreview: p.postKind == 'reel',
                onOpenDetails: () => openSocialContent(
                  context,
                  post: p,
                  reelContextPosts: _posts,
                ),
                onOpenProfile: () => _openAuthorProfile(p.author),
                onToggleLike: () => _togglePostLike(p),
                onToggleSave: () => _togglePostSave(p),
                onOpenComments: () async {
                  final count = await openSocialComments(context, post: p);
                  if (!mounted || count == null) return;
                  setState(() {
                    _posts = _posts
                        .map(
                          (post) => post.id == p.id
                              ? post.copyWith(commentsCount: count)
                              : post,
                        )
                        .toList(growable: false);
                  });
                },
                onOpenMerchantLink: () => _openMerchantFromReview(p),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 120),
          ],
        ),
      );
    }

    if (_tab == 1) {
      return RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.all(12),
          children: [
            Text(
              _t('تبليغات الإدارة', 'Management Announcements'),
              textDirection: context.appTextDirection,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 6),
            if (_announcements.isEmpty)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    _t('لا توجد تبليغات حالياً.', 'No announcements yet.'),
                    textDirection: context.appTextDirection,
                  ),
                ),
              ),
            for (final a in _announcements)
              Card(
                child: ListTile(
                  title: Text(a.title, textDirection: TextDirection.rtl),
                  subtitle: Text(a.body, textDirection: TextDirection.rtl),
                ),
              ),
            if (_canManageManagers) ...[
              const SizedBox(height: 10),
              Text(
                _t('مدراء المجتمع', 'Community Managers'),
                textDirection: context.appTextDirection,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              for (final m in _managers)
                ListTile(
                  title: Text(
                    m.manager.fullName,
                    textDirection: TextDirection.rtl,
                  ),
                  subtitle: Text(
                    (m.manager.phone ?? '').trim().isEmpty
                        ? 'ID: ${m.managerUserId}'
                        : m.manager.phone!,
                    textDirection: TextDirection.rtl,
                  ),
                  trailing: TextButton(
                    onPressed: () => _removeManager(m.managerUserId),
                    child: Text(_t('إزالة', 'Remove')),
                  ),
                ),
            ],
            const SizedBox(height: 120),
          ],
        ),
      );
    }

    if (_tab == 2) {
      final cannotSend = _isBanned || (_chatLocked && !_canManageChat);
      final peerTypingLabel = _peerTyping
          ? ((_peerTypingActorName ?? '').trim().isNotEmpty
                ? _t(
                    '${_peerTypingActorName!.trim()} يكتب الآن...',
                    '${_peerTypingActorName!.trim()} is typing...',
                  )
                : _t('جاري الكتابة...', 'Typing...'))
          : null;
      return Column(
        children: [
          if (_chatLocked)
            Container(
              width: double.infinity,
              color: Colors.amber.shade800,
              padding: const EdgeInsets.all(8),
              child: Text(
                _t('المحادثة مقفلة.', 'Chat is locked.'),
                textDirection: context.appTextDirection,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          if (_isBanned)
            Container(
              width: double.infinity,
              color: Colors.red.shade700,
              padding: const EdgeInsets.all(8),
              child: Text(
                _t('أنت محظور من الإرسال.', 'You are banned from sending.'),
                textDirection: context.appTextDirection,
                style: const TextStyle(color: Colors.white),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        _t('دردشة المجتمع', 'Community chat'),
                        textDirection: context.appTextDirection,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: _chatSearchMode
                          ? _t('إغلاق البحث', 'Close search')
                          : _t('بحث داخل المحادثة', 'Search in chat'),
                      onPressed: _toggleCommunitySearchMode,
                      icon: Icon(
                        _chatSearchMode
                            ? Icons.close_rounded
                            : Icons.search_rounded,
                      ),
                    ),
                  ],
                ),
                if (_chatSearchMode)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _chatSearchCtrl,
                            textDirection: context.appTextDirection,
                            decoration: InputDecoration(
                              hintText: _t(
                                'ابحث داخل دردشة المجتمع',
                                'Search community chat',
                              ),
                              prefixIcon: const Icon(Icons.search_rounded),
                              suffixIcon: _chatSearchCtrl.text.trim().isEmpty
                                  ? null
                                  : IconButton(
                                      tooltip: _t('مسح', 'Clear'),
                                      onPressed: _chatSearchCtrl.clear,
                                      icon: const Icon(Icons.close_rounded),
                                    ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (_chatSearchLoading)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else if (_chatSearchResults.isNotEmpty)
                          Text(
                            '${_chatSearchResultIndex + 1}/${_chatSearchResults.length}',
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                        IconButton(
                          tooltip: _t('السابق', 'Previous'),
                          onPressed: _chatSearchResults.length > 1
                              ? () => _jumpToCommunitySearchResult(-1)
                              : null,
                          icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        ),
                        IconButton(
                          tooltip: _t('التالي', 'Next'),
                          onPressed: _chatSearchResults.length > 1
                              ? () => _jumpToCommunitySearchResult(1)
                              : null,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        ),
                      ],
                    ),
                  ),
                if ((_chatSearchError ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        _chatSearchError!,
                        textDirection: context.appTextDirection,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                if ((peerTypingLabel ?? '').trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        peerTypingLabel!,
                        textDirection: context.appTextDirection,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.primary,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: ListView(
              controller: _chatScrollCtrl,
              padding: const EdgeInsets.all(12),
              children: [
                for (final c in _chatMessages)
                  Container(
                    key: _chatMessageItemKeys.putIfAbsent(
                      c.id,
                      () => GlobalKey(debugLabel: 'community-chat-${c.id}'),
                    ),
                    decoration: BoxDecoration(
                      color: _highlightedChatMessageId == c.id
                          ? Theme.of(context).colorScheme.primaryContainer
                                .withValues(alpha: 0.32)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: CommunityChatBubble(
                      message: c,
                      timeLabel: c.createdAt == null
                          ? ''
                          : _timeFmt.format(c.createdAt!.toLocal()),
                      onOpenProfile: (author) => _openAuthorProfile(author),
                      onOpenAttachment: c.attachment == null
                          ? null
                          : () => _openCommunityAttachment(c.attachment!),
                      onOpenSharedEntity: c.sharedEntity == null
                          ? null
                          : () => openSocialSharedEntity(
                              context,
                              entity: c.sharedEntity!,
                            ),
                      onMore: () => _openCommunityMessageActions(c),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_voiceComposer.state.isRecording)
                  SocialVoiceRecordingStatusCard(
                    duration: _voiceComposer.state.duration,
                    locked: _voiceComposer.state.isLocked,
                    title: _t('تسجيل رسالة صوتية', 'Recording voice message'),
                    slideToLockLabel: _t(
                      'اسحب للأعلى للقفل',
                      'Slide up to lock',
                    ),
                    lockedLabel: _t(
                      'التسجيل مقفل ويمكنك المتابعة بدون ضغط.',
                      'Recording locked. You can continue hands-free.',
                    ),
                    cancelLabel: _t('حذف التسجيل', 'Delete recording'),
                    stopLabel: _t('إيقاف التسجيل', 'Stop recording'),
                    onCancel: () {
                      unawaited(_cancelVoiceComposer());
                    },
                    onStop: _voiceComposer.state.isLocked
                        ? () {
                            unawaited(_stopLockedVoiceRecording());
                          }
                        : null,
                  ),
                if (_voiceComposer.state.draft != null)
                  SocialVoicePreviewCard(
                    draft: _voiceComposer.state.draft!,
                    sending: _voiceComposer.state.isSending,
                    title: _t(
                      'معاينة الرسالة الصوتية',
                      'Voice message preview',
                    ),
                    playLabel: _t('تشغيل', 'Play'),
                    pauseLabel: _t('إيقاف', 'Pause'),
                    deleteLabel: _t('حذف التسجيل', 'Delete recording'),
                    sendLabel: _t(
                      'إرسال الرسالة الصوتية',
                      'Send voice message',
                    ),
                    onDelete: () {
                      unawaited(_cancelVoiceComposer());
                    },
                    onSend: _sendVoiceDraft,
                  ),
                if (_chatAttachmentDraft != null)
                  SocialAttachmentPreviewCard(
                    file: _chatAttachmentDraft!,
                    onClear: () {
                      setState(() => _chatAttachmentDraft = null);
                    },
                  ),
                if (_chatSharedEntityDraft != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Ink(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.82),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.location_on_rounded),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _chatSharedEntityDraft!.address ??
                                  _chatSharedEntityDraft!.title,
                              textDirection: context.appTextDirection,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: _t('حذف', 'Delete'),
                            onPressed: () {
                              setState(() => _chatSharedEntityDraft = null);
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_replyingToMessage != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 6),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surfaceContainerHighest
                          .withValues(alpha: 0.85),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: () =>
                              setState(() => _replyingToMessage = null),
                          icon: const Icon(Icons.close_rounded),
                          tooltip: _t('إلغاء الرد', 'Cancel reply'),
                        ),
                        Expanded(
                          child: Text(
                            _communityReplyPreviewText(_replyingToMessage!),
                            textDirection: TextDirection.rtl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ),
                Builder(
                  builder: (context) {
                    final hasComposerText = _communityComposerHasText;
                    final showSendAction =
                        hasComposerText ||
                        _chatAttachmentDraft != null ||
                        _chatSharedEntityDraft != null ||
                        _voiceComposer.state.hasPreview;
                    return Row(
                      children: [
                        IconButton(
                          tooltip: _t('إضافة مرفق', 'Add attachment'),
                          onPressed:
                              (cannotSend || _sending || _voiceComposerBusy)
                              ? null
                              : _openCommunityAttachmentsMenu,
                          icon: const Icon(Icons.add_circle_outline_rounded),
                        ),
                        IconButton(
                          tooltip: _t('الملصقات و GIF', 'Stickers & GIF'),
                          onPressed:
                              (cannotSend || _sending || _voiceComposerBusy)
                              ? null
                              : _openCommunityStickersGifMenu,
                          icon: const Icon(
                            Icons.sentiment_satisfied_alt_rounded,
                          ),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _chatCtrl,
                            textDirection: context.appTextDirection,
                            enabled: !cannotSend && !_voiceComposerBusy,
                            textInputAction: TextInputAction.send,
                            onSubmitted: (_) {
                              if (cannotSend || _voiceComposerBusy) return;
                              _sendChat();
                            },
                            onChanged: _handleCommunityComposerChanged,
                            decoration: InputDecoration(
                              hintText: _voiceComposer.state.hasPreview
                                  ? _t(
                                      'معاينة الرسالة الصوتية',
                                      'Voice message preview',
                                    )
                                  : _t('رسالة...', 'Message...'),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (showSendAction)
                          FilledButton(
                            onPressed: (cannotSend || _voiceComposerBusy)
                                ? null
                                : _sendChat,
                            child: _sending
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(_t('إرسال', 'Send')),
                          )
                        else
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onLongPressStart:
                                (cannotSend ||
                                    _sending ||
                                    _voiceComposerBusy ||
                                    _chatAttachmentDraft != null)
                                ? null
                                : (_) => _startVoiceHold(),
                            onLongPressMoveUpdate:
                                (cannotSend ||
                                    _sending ||
                                    _voiceComposerBusy ||
                                    _chatAttachmentDraft != null)
                                ? null
                                : _updateVoiceHoldDrag,
                            onLongPressEnd: (cannotSend || _sending)
                                ? null
                                : (_) => _finishVoiceHold(),
                            onTap:
                                (cannotSend ||
                                    _sending ||
                                    _voiceComposerBusy ||
                                    _chatAttachmentDraft != null)
                                ? null
                                : () {
                                    _snack(
                                      _t(
                                        'اضغط مطولًا لتسجيل رسالة صوتية',
                                        'Hold to record a voice message',
                                      ),
                                    );
                                  },
                            child: Semantics(
                              button: true,
                              label: _t(
                                'اضغط مطولًا لتسجيل رسالة صوتية',
                                'Hold to record a voice message',
                              ),
                              child: Container(
                                width: 48,
                                height: 48,
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  color: _voiceComposer.state.isRecording
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.errorContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                ),
                                child: Icon(
                                  _voiceComposer.state.isRecording
                                      ? Icons.lock_open_rounded
                                      : Icons.mic_none_rounded,
                                  color: _voiceComposer.state.isRecording
                                      ? Theme.of(context).colorScheme.error
                                      : Theme.of(
                                          context,
                                        ).colorScheme.onSurfaceVariant,
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
        ],
      );
    }

    return RefreshIndicator(
      onRefresh: _reload,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              ChoiceChip(
                label: Text(_t('الكل', 'All')),
                selected: _billCategory == null,
                onSelected: (_) async {
                  setState(() => _billCategory = null);
                  await _reload();
                },
              ),
              ChoiceChip(
                label: Text(_t('كهرباء', 'Electricity')),
                selected: _billCategory == 'electricity',
                onSelected: (_) async {
                  setState(() => _billCategory = 'electricity');
                  await _reload();
                },
              ),
              ChoiceChip(
                label: Text(_t('ماء', 'Water')),
                selected: _billCategory == 'water',
                onSelected: (_) async {
                  setState(() => _billCategory = 'water');
                  await _reload();
                },
              ),
              ChoiceChip(
                label: Text(_t('أخرى', 'Other')),
                selected: _billCategory == 'other',
                onSelected: (_) async {
                  setState(() => _billCategory = 'other');
                  await _reload();
                },
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final b in _bills)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.title,
                      textDirection: context.appTextDirection,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${b.category} â€¢ ${b.amount ?? '-'}',
                      textDirection: context.appTextDirection,
                    ),
                    if ((b.apartmentCode ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '${_t('الشقة', 'Apartment')}: ${b.apartmentCode}',
                          textDirection: context.appTextDirection,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    if ((b.dueDate ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Due: ${b.dueDate}',
                          textDirection: TextDirection.ltr,
                        ),
                      ),
                    if ((b.details ?? '').trim().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Text(
                          b.details!,
                          textDirection: context.appTextDirection,
                        ),
                      ),
                    if (b.attachment != null) ...[
                      const SizedBox(height: 8),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: OutlinedButton.icon(
                          onPressed: () => _openBillAttachment(b),
                          icon: Icon(
                            b.attachment!.kind == 'image'
                                ? Icons.image_outlined
                                : Icons.attach_file_rounded,
                          ),
                          label: Text(
                            (b.attachment!.name ?? '').trim().isEmpty
                                ? _t('فتح المرفق', 'Open attachment')
                                : b.attachment!.name!,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          const SizedBox(height: 120),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: MaslakiBasmayaDrawer(
        extraSections: _buildCommunityDrawerSections(),
      ),
      appBar: MaslakiTopBar(
        title: _scopeHomeTitle(),
        subtitle: _scopeSubtitle.isEmpty
            ? _scopeDefaultSubtitle()
            : _scopeSubtitle,
        leading: const MaslakiUserDrawerButton(openStartDrawer: true),
        actions: const [NotificationsBellButton()],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'community-post-fab-_',
        onPressed: _openScopedCreatePostSheet,
        icon: const Icon(Icons.post_add_rounded),
        label: Text(
          _t(
            '\u0625\u0636\u0627\u0641\u0629 \u0645\u0646\u0634\u0648\u0631',
            'Add post',
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Column(
        children: [
          _buildScopeTopQuickControls(),
          _buildSectionTabs(),
          _buildOverviewCards(),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: BasmayaBottomNavBar(current: _currentBasmayaNavKey),
    );
  }
}
