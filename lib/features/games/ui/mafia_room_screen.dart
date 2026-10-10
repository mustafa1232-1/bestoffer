import 'dart:async';
import 'dart:math' as math;

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/realtime/maslaki_realtime_service.dart';
import '../data/games_api.dart';
import '../state/mafia_voice_controller.dart';
import 'mafia_interactions.dart';

class MafiaRoomScreen extends ConsumerStatefulWidget {
  final int roomId;

  const MafiaRoomScreen({required this.roomId, super.key});

  @override
  ConsumerState<MafiaRoomScreen> createState() => _MafiaRoomScreenState();
}

class _MafiaRoomScreenState extends ConsumerState<MafiaRoomScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  final MafiaVoiceController _voice = MafiaVoiceController();
  final TextEditingController _message = TextEditingController();
  late final AnimationController _ambience;
  Timer? _pollTimer;
  Timer? _heartbeatTimer;
  Timer? _clockTimer;
  final _interactions = MafiaInteractionController();
  bool _silenceInteractionsOnResume = false;
  bool _artPrecached = false;
  Timer? _eliminationTimer;
  StreamSubscription<MaslakiRealtimeEvent>? _realtimeEvents;
  Map<String, dynamic>? _snapshot;
  bool _loading = true;
  bool _refreshing = false;
  bool _refreshQueued = false;
  bool _foreground = true;
  bool _heartbeating = false;
  bool _sendingMessage = false;
  String? _messageError;
  String? _pendingMessageId;
  String? _pendingMessageBody;
  String? _pendingMessageChannel;
  final ValueNotifier<int> _chatRevision = ValueNotifier(0);
  final Map<String, String> _channelDrafts = {};
  final Stopwatch _snapshotAge = Stopwatch();
  int _snapshotRemaining = 0;
  bool _acting = false;
  String? _error;
  int? _lastPhaseVersion;
  int _remainingSeconds = 0;
  int? _selectedPlayerId;
  String? _selectedNightAction;
  bool _roleDialogOpen = false;
  bool _removedFromRoom = false;
  bool _sendingInteraction = false;
  int _lastEliminationId = 0;
  Map<String, dynamic>? _activeElimination;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _ambience = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 7),
    )..repeat(reverse: true);
    _voice.addListener(_voiceChanged);
    unawaited(_refresh(initial: true));
    unawaited(_bindRealtime());
    _pollTimer = Timer.periodic(
      const Duration(seconds: 15),
      (_) => unawaited(_refresh()),
    );
    _heartbeatTimer = Timer.periodic(
      const Duration(seconds: 12),
      (_) => unawaited(_heartbeat()),
    );
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _foreground) {
        final next = math.max(
          0,
          _snapshotRemaining - _snapshotAge.elapsed.inSeconds,
        );
        if (next != _remainingSeconds) setState(() => _remainingSeconds = next);
        if (next == 0 && _snapshotRemaining > 0) unawaited(_refresh());
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_artPrecached) {
      _artPrecached = true;
      unawaited(
        precacheImage(
          const ResizeImage(AssetImage(mafiaGiftsAsset), width: 768),
          context,
        ),
      );
      unawaited(
        precacheImage(
          const ResizeImage(AssetImage(mafiaCourtyardAsset), width: 1200),
          context,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _silenceInteractionsOnResume = true;
      _interactions.clear();
    }
    if (state == AppLifecycleState.resumed) {
      unawaited(_refresh());
      if (_voice.state == MafiaVoiceState.error ||
          _voice.state == MafiaVoiceState.reconnecting ||
          _voice.state == MafiaVoiceState.idle) {
        unawaited(_voice.retry());
      } else {
        unawaited(_voice.refreshPermissions());
      }
    }
  }

  void _voiceChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _bindRealtime() async {
    try {
      final stream = await ref
          .read(maslakiRealtimeServiceProvider)
          .subscribeDefaultUserChannel();
      if (!mounted || stream == null) return;
      await _realtimeEvents?.cancel();
      _realtimeEvents = stream.listen((event) {
        if (event.event == 'mafia_room_updated' &&
            _int(event.data['roomId']) == widget.roomId) {
          final revision = _int(event.data['stateVersion']);
          if (revision > 0 && revision <= _int(_snapshot?['stateVersion'])) {
            return;
          }
          final me = _map(_snapshot?['me']);
          if (event.data['reason'] == 'player_kicked' &&
              _int(event.data['kickedUserId']) == _int(me['userId'])) {
            unawaited(_handleKicked());
            return;
          }
          unawaited(_refresh());
        }
      });
    } catch (_) {
      // The 15-second fallback refresh keeps the room usable without realtime.
    }
  }

  Future<void> _refresh({bool initial = false}) async {
    if (!mounted || !_foreground || _removedFromRoom) return;
    if (_refreshing) {
      _refreshQueued = true;
      return;
    }
    _refreshing = true;
    try {
      final api = ref.read(gamesApiProvider);
      final next = await api.mafiaSnapshot(widget.roomId);
      if (!mounted) return;
      _applySnapshot(next, initial: initial);
    } catch (exception) {
      if (!mounted) return;
      if ('$exception'.contains('MAFIA_ROOM_FORBIDDEN')) {
        unawaited(_handleKicked());
        return;
      }
      setState(() {
        _loading = false;
        _error = _friendlyError(exception);
      });
    } finally {
      _refreshing = false;
      if (_refreshQueued) {
        _refreshQueued = false;
        unawaited(_refresh());
      }
    }
  }

  void _applySnapshot(Map<String, dynamic> next, {bool initial = false}) {
    if (!mounted ||
        _int(next['stateVersion']) < _int(_snapshot?['stateVersion'])) {
      return;
    }
    final firstSnapshot = _snapshot == null;
    final api = ref.read(gamesApiProvider);
    final room = _map(next['room']);
    final phase = _map(next['phase']);
    final voice = _map(next['voice']);
    final version = _int(room['phaseVersion']);
    final phaseChanged =
        _lastPhaseVersion != null && version != _lastPhaseVersion;
    final previousChannel = _chatChannel(_snapshot);
    final nextChannel = _chatChannel(next);
    if (previousChannel != nextChannel) {
      // A private night draft must never silently become a public message.
      _channelDrafts[previousChannel] = _message.text;
      _message.text = _channelDrafts[nextChannel] ?? '';
    }
    setState(() {
      _snapshot = next;
      _remainingSeconds = _int(phase['remainingSeconds']);
      _snapshotRemaining = _remainingSeconds;
      _snapshotAge
        ..reset()
        ..start();
      _lastPhaseVersion = version;
      _loading = false;
      _error = null;
      if (phaseChanged) {
        _selectedPlayerId = null;
        _selectedNightAction = null;
      }
    });
    _chatRevision.value++;
    _consumeLatestInteraction(next, initial: initial || firstSnapshot);
    _consumeLatestElimination(next, initial: initial);
    if (phaseChanged) {
      HapticFeedback.mediumImpact();
      SystemSound.play(SystemSoundType.click);
      _ambience
        ..reset()
        ..repeat(reverse: true);
    }
    if (voice['enabled'] != true) {
      if (_voice.state != MafiaVoiceState.disabled) {
        unawaited(_voice.connect(api, widget.roomId, force: true));
      }
    } else if (voice['canRequestToken'] != true) {
      unawaited(_voice.disconnect());
    } else if (_voice.state == MafiaVoiceState.idle ||
        _voice.state == MafiaVoiceState.error) {
      unawaited(_voice.connect(api, widget.roomId));
    } else if (phaseChanged) {
      unawaited(_voice.refreshPermissions());
    }
    _maybeRevealRole(next);
  }

  Future<void> _heartbeat() async {
    final status = '${_map(_snapshot?['room'])['status']}';
    if (!_foreground ||
        _heartbeating ||
        _removedFromRoom ||
        status == 'completed' ||
        status == 'cancelled') {
      return;
    }
    try {
      _heartbeating = true;
      await ref.read(gamesApiProvider).mafiaHeartbeat(widget.roomId);
    } catch (_) {
      // Snapshot polling exposes persistent transport errors in the UI.
    } finally {
      _heartbeating = false;
    }
  }

  void _maybeRevealRole(Map<String, dynamic> snapshot) {
    final room = _map(snapshot['room']);
    final me = _map(snapshot['me']);
    if (room['status'] != 'role_reveal' ||
        me['roleAcknowledged'] == true ||
        _roleDialogOpen ||
        me['role'] == null) {
      return;
    }
    _roleDialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _RoleRevealDialog(role: '${me['role']}'),
      );
      _roleDialogOpen = false;
      if (!mounted) return;
      await _run(
        () => ref.read(gamesApiProvider).acknowledgeMafiaRole(widget.roomId),
      );
    });
  }

  Future<void> _run(Future<Map<String, dynamic>> Function() action) async {
    if (_acting) return;
    setState(() {
      _acting = true;
      _error = null;
    });
    try {
      final next = await action();
      if (!mounted) return;
      if (next['room'] is Map) {
        _applySnapshot(next);
      } else {
        unawaited(_refresh());
      }
    } catch (exception) {
      if (mounted) setState(() => _error = _friendlyError(exception));
      if ('$exception'.contains('MAFIA_PHASE_')) unawaited(_refresh());
    } finally {
      if (mounted) setState(() => _acting = false);
    }
  }

  Future<void> _handleKicked() async {
    if (_removedFromRoom) return;
    _removedFromRoom = true;
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    await _voice.disconnect();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.person_remove_rounded),
        title: const Text('تم إخراجك من الغرفة'),
        content: const Text(
          'أنهى صاحب الغرفة مشاركتك في هذه الجولة. يمكنك إنشاء غرفة جديدة أو الانضمام إلى غرفة أخرى.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('العودة إلى الألعاب'),
          ),
        ],
      ),
    );
    if (mounted) Navigator.pop(context);
  }

  Future<void> _showHostControls({
    required Map<String, dynamic> room,
    required Map<String, dynamic> me,
    required List<Map<String, dynamic>> players,
  }) async {
    final action = await showModalBottomSheet<_MafiaHostAction>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => _HostControlsSheet(
        room: room,
        players: players,
        myPlayerId: _int(me['playerId']),
      ),
    );
    if (!mounted || action == null) return;
    switch (action.type) {
      case _MafiaHostActionType.copyCode:
        await Clipboard.setData(
          ClipboardData(text: '${room['inviteCode'] ?? ''}'),
        );
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('تم نسخ رمز الغرفة.')));
        }
        break;
      case _MafiaHostActionType.kick:
        final player = action.player;
        if (player == null) return;
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.person_remove_rounded),
            title: const Text('طرد اللاعب؟'),
            content: Text(
              'سيتم إخراج ${player['name'] ?? 'اللاعب'} من الغرفة ولن يستطيع العودة إليها بالرمز نفسه.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                key: const ValueKey('mafia-confirm-kick'),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('طرد اللاعب'),
              ),
            ],
          ),
        );
        if (accepted == true) {
          await _run(
            () => ref
                .read(gamesApiProvider)
                .kickMafiaPlayer(widget.roomId, _int(player['playerId'])),
          );
        }
        break;
      case _MafiaHostActionType.close:
        final accepted = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            icon: const Icon(Icons.power_settings_new_rounded),
            title: const Text('إغلاق الغرفة؟'),
            content: const Text(
              'ستنتهي الجولة للجميع وسيُغلق الاتصال الصوتي. لا يمكن التراجع عن هذا القرار.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('إبقاء الغرفة'),
              ),
              FilledButton(
                key: const ValueKey('mafia-confirm-close'),
                onPressed: () => Navigator.pop(context, true),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9F302B),
                ),
                child: const Text('إغلاق الغرفة'),
              ),
            ],
          ),
        );
        if (accepted == true) {
          await _run(
            () => ref.read(gamesApiProvider).closeMafiaRoom(widget.roomId),
          );
          await _voice.disconnect();
        }
        break;
    }
  }

  String _commandId() =>
      'mafia-${DateTime.now().microsecondsSinceEpoch}-${math.Random().nextInt(99999)}';

  Future<void> _submitSelection() async {
    final snapshot = _snapshot;
    if (snapshot == null) return;
    final room = _map(snapshot['room']);
    final me = _map(snapshot['me']);
    final phase = '${room['status']}';
    String? type;
    if (phase == 'day_nomination') {
      type = 'nominate';
    } else if (phase == 'day_vote' || phase == 'day_revote') {
      type = 'vote';
    } else if (phase == 'night') {
      type = _selectedNightAction ?? _defaultNightAction('${me['role']}');
    }
    if (type == null || (type != 'vote' && _selectedPlayerId == null)) return;
    final selectable = _selectablePlayerIds(
      snapshot: snapshot,
      actionType: type,
    );
    if (_selectedPlayerId != null && !selectable.contains(_selectedPlayerId)) {
      setState(() => _selectedPlayerId = null);
      return;
    }
    await _run(
      () => ref
          .read(gamesApiProvider)
          .mafiaAction(
            widget.roomId,
            type: type!,
            targetPlayerId: _selectedPlayerId,
            commandId: _commandId(),
            phaseVersion: _int(room['phaseVersion']),
          ),
    );
  }

  Future<void> _sendMessage(String channel) async {
    final body = _message.text.trim();
    if (body.isEmpty || _sendingMessage) return;
    if (_pendingMessageBody != body || _pendingMessageChannel != channel) {
      _pendingMessageId = _commandId();
      _pendingMessageBody = body;
      _pendingMessageChannel = channel;
    }
    _sendingMessage = true;
    _messageError = null;
    _chatRevision.value++;
    try {
      final response = await ref
          .read(gamesApiProvider)
          .sendMafiaMessage(
            widget.roomId,
            body: body,
            channel: channel,
            clientMessageId: _pendingMessageId,
          );
      if (!mounted) return;
      if (_chatChannel(_snapshot) == channel && _message.text.trim() == body) {
        _message.clear();
      }
      _channelDrafts.remove(channel);
      final received = _map(response['message']);
      if (received.isNotEmpty && _snapshot != null) {
        final messages = _list(_snapshot!['messages']);
        if (!messages.any((m) => _map(m)['id'] == received['id'])) {
          setState(
            () => _snapshot = {
              ..._snapshot!,
              'messages': [...messages, received],
            },
          );
        }
      } else {
        unawaited(_refresh());
      }
      _pendingMessageBody = null;
    } catch (exception) {
      if (mounted) _messageError = _friendlyError(exception);
    } finally {
      _sendingMessage = false;
      if (mounted) _chatRevision.value++;
    }
  }

  void _consumeLatestInteraction(
    Map<String, dynamic> snapshot, {
    required bool initial,
  }) {
    _interactions.ingest(
      _list(snapshot['events']).map(_map),
      silent: initial || !_foreground || _silenceInteractionsOnResume,
      serverTime: DateTime.tryParse('${snapshot['serverTime'] ?? ''}'),
    );
    if (_foreground) _silenceInteractionsOnResume = false;
  }

  void _consumeLatestElimination(
    Map<String, dynamic> snapshot, {
    required bool initial,
  }) {
    final eliminations = _list(
      snapshot['events'],
    ).map(_map).where((event) => event['type'] == 'player_eliminated').toList();
    if (eliminations.isEmpty) return;
    final latest = eliminations.last;
    final eventId = _int(latest['id']);
    if (eventId <= _lastEliminationId) return;
    _lastEliminationId = eventId;
    if (initial || !mounted) return;
    _eliminationTimer?.cancel();
    HapticFeedback.heavyImpact();
    setState(() => _activeElimination = latest);
    _eliminationTimer = Timer(const Duration(milliseconds: 3200), () {
      if (mounted && _int(_activeElimination?['id']) == eventId) {
        setState(() => _activeElimination = null);
      }
    });
  }

  Future<void> _shareInvite(Map<String, dynamic> room) async {
    final code = '${room['inviteCode'] ?? ''}'.trim();
    if (code.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(
        text:
            'ليلة مسلكي تنتظر قرارك. افتح ألعاب مسلكي وانضم إلى غرفة المافيا بالرمز: $code',
      ),
    );
  }

  Future<void> _sendInteraction(String kind, {int? targetPlayerId}) async {
    if (_sendingInteraction) return;
    setState(() => _sendingInteraction = true);
    try {
      final result = await ref
          .read(gamesApiProvider)
          .sendMafiaInteraction(
            widget.roomId,
            kind: kind,
            targetPlayerId: targetPlayerId,
            commandId: _commandId(),
          );
      if (!mounted) return;
      // Animate the confirmed receipt immediately; the next snapshot is deduped.
      final event = _map(result['event']);
      if (event.isNotEmpty) {
        _interactions.ingest([event], silent: !_foreground);
      } else {
        await _refresh();
      }
    } catch (exception) {
      if (!mounted) return;
      final rawError = '$exception';
      final message = rawError.contains('MAFIA_INTERACTION_RATE_LIMIT')
          ? 'تمهّل قليلًا قبل إرسال تفاعل آخر.'
          : rawError.contains('MAFIA_HONOR_ALREADY_CAST')
          ? 'سبق أن اخترت نجم هذه الجولة.'
          : 'تعذر إرسال التفاعل الآن.';
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _sendingInteraction = false);
    }
  }

  Future<void> _showPlayerGifts(Map<String, dynamic> player) async {
    final targetUserId = _int(player['userId']);
    final isMuted = _voice.isUserMuted(targetUserId);
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '${player['name'] ?? 'اللاعب'}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final gift in const ['rose', 'tea', 'egg']) ...[
                    Expanded(
                      child: _InteractionChoice(
                        kind: gift,
                        onTap: () => Navigator.pop(context, gift),
                      ),
                    ),
                    if (gift != 'egg') const SizedBox(width: 8),
                  ],
                ],
              ),
              const SizedBox(height: 10),
              OutlinedButton.icon(
                key: ValueKey('mafia-local-mute-${player['playerId']}'),
                onPressed: () => Navigator.pop(context, '__local_mute'),
                icon: Icon(
                  isMuted ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                ),
                label: Text(isMuted ? 'إلغاء الكتم لدي' : 'كتم صوت اللاعب لدي'),
              ),
              TextButton.icon(
                key: ValueKey('mafia-report-${player['playerId']}'),
                onPressed: () => Navigator.pop(context, '__report'),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('إرسال بلاغ إلى إدارة مسلكي'),
              ),
            ],
          ),
        ),
      ),
    );
    if (kind == '__local_mute') {
      await _voice.toggleUserMute(targetUserId);
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            isMuted
                ? 'أصبح صوت اللاعب مسموعاً لديك.'
                : 'تم كتم اللاعب لديك فقط.',
          ),
        ),
      );
    } else if (kind == '__report') {
      await _reportPlayer(player);
    } else if (kind != null) {
      await _sendInteraction(kind, targetPlayerId: _int(player['playerId']));
    }
  }

  Future<void> _reportPlayer(Map<String, dynamic> player) async {
    final details = TextEditingController();
    var reason = 'harassment';
    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              0,
              16,
              MediaQuery.viewInsetsOf(context).bottom + 18,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  'الإبلاغ عن ${player['name'] ?? 'اللاعب'}',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: reason,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'سبب البلاغ'),
                  items: const [
                    DropdownMenuItem(
                      value: 'harassment',
                      child: Text('إساءة أو مضايقة'),
                    ),
                    DropdownMenuItem(
                      value: 'inappropriate_audio',
                      child: Text('محتوى صوتي غير مناسب'),
                    ),
                    DropdownMenuItem(
                      value: 'cheating',
                      child: Text('غش أو تواطؤ خارج اللعبة'),
                    ),
                    DropdownMenuItem(value: 'spam', child: Text('إزعاج متكرر')),
                    DropdownMenuItem(value: 'other', child: Text('سبب آخر')),
                  ],
                  onChanged: (value) {
                    if (value != null) setSheetState(() => reason = value);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: details,
                  minLines: 2,
                  maxLines: 4,
                  maxLength: 300,
                  decoration: const InputDecoration(
                    labelText: 'تفاصيل إضافية (اختياري)',
                    alignLabelWithHint: true,
                  ),
                ),
                FilledButton.icon(
                  key: const ValueKey('mafia-submit-report'),
                  onPressed: () => Navigator.pop(context, true),
                  icon: const Icon(Icons.shield_outlined),
                  label: const Text('إرسال البلاغ بسرية'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    final note = details.text.trim();
    details.dispose();
    if (submitted != true || !mounted) return;
    try {
      await ref
          .read(gamesApiProvider)
          .reportMafiaPlayer(
            widget.roomId,
            targetPlayerId: _int(player['playerId']),
            reason: reason,
            details: note.isEmpty ? null : note,
            commandId: _commandId(),
          );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context)..clearSnackBars();
      messenger.showSnackBar(
        const SnackBar(
          content: Text('وصل البلاغ إلى الإدارة بسرية. لن يظهر للاعب.'),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تعذر إرسال البلاغ الآن. حاول مجدداً.')),
      );
    }
  }

  Future<void> _showChat() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: const Color(0xFFF8FAF9),
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: ValueListenableBuilder<int>(
          valueListenable: _chatRevision,
          builder: (context, _, child) {
            final channel = _chatChannel(_snapshot);
            final messages = _list(_snapshot?['messages'])
                .where((m) => _map(m)['channel'] == channel)
                .toList()
                .reversed
                .toList();
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                0,
                16,
                MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: SizedBox(
                height: math.max(
                  160,
                  math.min(
                    MediaQuery.sizeOf(context).height * .62,
                    MediaQuery.sizeOf(context).height -
                        MediaQuery.viewInsetsOf(context).bottom -
                        100,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      _channelTitle(channel),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF15382C),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_messageError != null)
                      Text(
                        _messageError!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    Expanded(
                      child: messages.isEmpty
                          ? const Center(
                              child: Text('ابدأ الحديث مع اللاعبين.'),
                            )
                          : ListView.builder(
                              reverse: true,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final item = _map(messages[index]);
                                final own =
                                    _int(item['userId']) ==
                                    _int(_map(_snapshot?['me'])['userId']);
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: ListTile(
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    tileColor: own
                                        ? const Color(0xFFE3F0E8)
                                        : Colors.white,
                                    leading: CircleAvatar(
                                      radius: 17,
                                      backgroundColor: own
                                          ? const Color(0xFF215540)
                                          : const Color(0xFFE7EDF2),
                                      foregroundColor: own
                                          ? Colors.white
                                          : const Color(0xFF15382C),
                                      child: Text(
                                        '${item['seatNumber'] ?? '?'}',
                                      ),
                                    ),
                                    title: Text(
                                      '${item['senderName'] ?? 'لاعب'}',
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: Color(0xFF215540),
                                      ),
                                    ),
                                    subtitle: Text(
                                      '${item['body'] ?? ''}',
                                      style: const TextStyle(
                                        color: Color(0xFF182B37),
                                        fontSize: 15,
                                        height: 1.5,
                                      ),
                                    ),
                                  ),
                                );
                              },
                            ),
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            key: const ValueKey('mafia-chat-input'),
                            controller: _message,
                            maxLength: 300,
                            minLines: 1,
                            maxLines: 3,
                            style: const TextStyle(
                              color: Color(0xFF182B37),
                              fontSize: 15,
                            ),
                            decoration: const InputDecoration(
                              hintText: 'اكتب رسالتك...',
                              counterText: '',
                              filled: true,
                              fillColor: Colors.white,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.all(
                                  Radius.circular(8),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        IconButton.filled(
                          key: const ValueKey('mafia-chat-send'),
                          tooltip: 'إرسال',
                          style: IconButton.styleFrom(
                            backgroundColor: const Color(0xFF215540),
                            foregroundColor: Colors.white,
                          ),
                          onPressed: _sendingMessage
                              ? null
                              : () => _sendMessage(channel),
                          icon: _sendingMessage
                              ? const SizedBox.square(
                                  dimension: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Icon(Icons.send_rounded),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _snapshot == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final snapshot = _snapshot ?? const <String, dynamic>{};
    final room = _map(snapshot['room']);
    final me = _map(snapshot['me']);
    final phase = '${room['status'] ?? 'lobby'}';
    final isNight = phase == 'night' || phase == 'role_reveal';
    final palette = _mafiaPalette(
      '${_map(room['settings'])['tableTheme'] ?? 'emerald'}',
    );
    final players = _list(snapshot['players']).map(_map).toList()
      ..sort((a, b) => _int(a['seatNumber']).compareTo(_int(b['seatNumber'])));
    final isHost = _int(room['hostUserId']) == _int(me['userId']);
    final isCompleted = phase == 'completed' || phase == 'cancelled';
    final selectablePlayerIds = _selectablePlayerIds(snapshot: snapshot);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: isNight ? palette.nightTop : palette.dayTop,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          foregroundColor: isNight ? Colors.white : const Color(0xFF102337),
          title: Column(
            children: [
              const Text(
                'ليلة مسلكي',
                style: TextStyle(fontWeight: FontWeight.w900),
              ),
              Text(
                'الغرفة ${room['inviteCode'] ?? ''}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          actions: [
            if (!isCompleted)
              IconButton(
                key: const ValueKey('mafia-share-invite'),
                tooltip: 'دعوة الأصدقاء',
                onPressed: () => _shareInvite(room),
                icon: const Icon(Icons.ios_share_rounded),
              ),
            if (isHost && !isCompleted)
              IconButton(
                key: const ValueKey('mafia-host-controls'),
                tooltip: 'إدارة الغرفة',
                onPressed: _acting
                    ? null
                    : () => _showHostControls(
                        room: room,
                        me: me,
                        players: players,
                      ),
                icon: const Icon(Icons.admin_panel_settings_rounded),
              ),
            IconButton(
              tooltip: 'قوانين اللعبة',
              onPressed: () => _showRules(context),
              icon: const Icon(Icons.menu_book_rounded),
            ),
            IconButton(
              tooltip: 'المحادثة',
              onPressed: _showChat,
              icon: Badge(
                isLabelVisible: _list(snapshot['messages']).isNotEmpty,
                child: const Icon(Icons.forum_outlined),
              ),
            ),
          ],
        ),
        body: AnimatedContainer(
          duration: Duration(
            milliseconds: MediaQuery.disableAnimationsOf(context) ? 0 : 900,
          ),
          curve: Curves.easeInOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isNight
                  ? [palette.nightTop, palette.nightBottom]
                  : [palette.dayTop, palette.dayBottom],
            ),
          ),
          child: SafeArea(
            top: false,
            child: Stack(
              children: [
                Positioned.fill(
                  child: RefreshIndicator(
                    onRefresh: _refresh,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(12, 8, 12, 28),
                      children: [
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 650),
                          switchInCurve: Curves.easeOutBack,
                          switchOutCurve: Curves.easeInCubic,
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, -.08),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _PhaseStage(
                            key: ValueKey('${room['phaseVersion']}-$phase'),
                            phase: phase,
                            dayNumber: _int(room['dayNumber']),
                            remainingSeconds: _remainingSeconds,
                            totalSeconds: _phaseDuration(room),
                            ambience: _ambience,
                            isNight: isNight,
                            themeAccent: palette.accent,
                            stageColor: isNight
                                ? palette.nightSurface
                                : palette.daySurface,
                          ),
                        ),
                        if (_map(snapshot['narrator']).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          _NarratorBanner(
                            narrator: _map(snapshot['narrator']),
                            isNight: isNight,
                          ),
                        ],
                        const SizedBox(height: 10),
                        if (!isCompleted)
                          _VoiceBar(controller: _voice, isNight: isNight),
                        if (_error != null) ...[
                          const SizedBox(height: 8),
                          _ErrorBanner(message: _error!, onRetry: _refresh),
                        ],
                        const SizedBox(height: 12),
                        if (!isCompleted) ...[
                          _ReactionBar(
                            busy: _sendingInteraction,
                            isNight: isNight,
                            onReact: (kind) => _sendInteraction(kind),
                          ),
                          const SizedBox(height: 10),
                        ],
                        _RoomPulseStrip(
                          players: players,
                          phase: phase,
                          isNight: isNight,
                        ),
                        const SizedBox(height: 8),
                        _PlayerGrid(
                          interactions: _interactions,
                          players: players,
                          me: me,
                          selectedPlayerId: _selectedPlayerId,
                          candidateIds: _intList(
                            _map(snapshot['phase'])['candidateIds'],
                          ),
                          activeSpeakerUserIds: _voice.activeSpeakerUserIds,
                          isNight: isNight,
                          phase: phase,
                          ambience: _ambience,
                          selectablePlayerIds: selectablePlayerIds,
                          onSelect: isCompleted
                              ? null
                              : (id) {
                                  HapticFeedback.selectionClick();
                                  setState(() => _selectedPlayerId = id);
                                },
                          onInteract: isCompleted ? null : _showPlayerGifts,
                        ),
                        const SizedBox(height: 14),
                        AnimatedSwitcher(
                          duration: const Duration(milliseconds: 420),
                          transitionBuilder: (child, animation) =>
                              FadeTransition(
                                opacity: animation,
                                child: SlideTransition(
                                  position: Tween(
                                    begin: const Offset(0, .08),
                                    end: Offset.zero,
                                  ).animate(animation),
                                  child: child,
                                ),
                              ),
                          child: _buildPhasePanel(
                            key: ValueKey('${room['phaseVersion']}-$phase'),
                            snapshot: snapshot,
                            players: players,
                            isHost: isHost,
                          ),
                        ),
                        if (_map(snapshot['mission']).isNotEmpty) ...[
                          _SecretMissionCard(
                            mission: _map(snapshot['mission']),
                            isNight: isNight,
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_map(snapshot['profile']).isNotEmpty) ...[
                          _MafiaProfileStrip(
                            profile: _map(snapshot['profile']),
                          ),
                          const SizedBox(height: 8),
                        ],
                        if (_list(snapshot['events']).isNotEmpty) ...[
                          const SizedBox(height: 14),
                          _EventTimeline(events: _list(snapshot['events'])),
                        ],
                      ],
                    ),
                  ),
                ),
                if (_activeElimination != null)
                  Positioned.fill(
                    child: _EliminationReveal(event: _activeElimination!),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Set<int> _selectablePlayerIds({
    required Map<String, dynamic> snapshot,
    String? actionType,
  }) {
    final room = _map(snapshot['room']);
    final me = _map(snapshot['me']);
    if (me['lifeStatus'] != 'alive') return const <int>{};
    final phase = '${room['status']}';
    final meId = _int(me['playerId']);
    final players = _list(snapshot['players']).map(_map).toList();
    final aliveIds = players
        .where((player) => player['lifeStatus'] == 'alive')
        .map((player) => _int(player['playerId']))
        .toSet();

    if (phase == 'day_nomination') return aliveIds..remove(meId);
    if (phase == 'day_vote' || phase == 'day_revote') {
      final candidates = _intList(_map(snapshot['phase'])['candidateIds']);
      return aliveIds.intersection(candidates.toSet());
    }
    if (phase != 'night' || _int(room['dayNumber']) < 1) {
      return const <int>{};
    }

    final type =
        actionType ??
        _selectedNightAction ??
        _defaultNightAction('${me['role']}');
    if (type == null) return const <int>{};
    if (type == 'doctor_protect') {
      final previous = _int(me['previousDoctorTargetId']);
      if (previous > 0) aliveIds.remove(previous);
      return aliveIds;
    }

    aliveIds.remove(meId);
    if (type == 'mafia_kill' ||
        type == 'framer_frame' ||
        type == 'don_inspect') {
      final teammates = _intList(me['mafiaTeammateIds']).toSet();
      aliveIds.removeAll(teammates);
    }
    return aliveIds;
  }

  Widget _buildPhasePanel({
    required Key key,
    required Map<String, dynamic> snapshot,
    required List<Map<String, dynamic>> players,
    required bool isHost,
  }) {
    final room = _map(snapshot['room']);
    final me = _map(snapshot['me']);
    final phase = '${room['status']}';
    if (phase == 'lobby') {
      final everyoneReady =
          players.length >= 7 &&
          players.every((player) => player['isReady'] == true);
      return _GamePanel(
        key: key,
        title: 'قاعة الانتظار',
        icon: Icons.groups_rounded,
        children: [
          Text(
            '${players.length} من ${room['maxPlayers'] ?? 14} لاعبين',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: _acting
                ? null
                : () => _run(
                    () => ref
                        .read(gamesApiProvider)
                        .setMafiaReady(widget.roomId, me['isReady'] != true),
                  ),
            icon: Icon(
              me['isReady'] == true
                  ? Icons.check_circle_rounded
                  : Icons.radio_button_unchecked_rounded,
            ),
            label: Text(me['isReady'] == true ? 'أنا جاهز' : 'تأكيد الجاهزية'),
          ),
          if (isHost) ...[
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: !_acting && everyoneReady
                  ? () => _run(
                      () =>
                          ref.read(gamesApiProvider).startMafia(widget.roomId),
                    )
                  : null,
              icon: const Icon(Icons.play_arrow_rounded),
              label: Text(
                everyoneReady ? 'بدء اللعبة' : 'يلزم 7 لاعبين جاهزين على الأقل',
              ),
            ),
          ],
        ],
      );
    }
    if (phase == 'role_reveal') {
      return _GamePanel(
        key: key,
        title: 'احفظ دورك جيداً',
        icon: Icons.visibility_off_rounded,
        children: [
          const Text(
            'دورك سرّي. تبدأ الليلة عند استعداد الجميع أو انتهاء العدّاد.',
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => _RoleRevealDialog(role: '${me['role']}'),
            ),
            icon: const Icon(Icons.badge_outlined),
            label: const Text('عرض دوري مرة أخرى'),
          ),
        ],
      );
    }
    if (phase == 'completed' || phase == 'cancelled') {
      final winner = '${room['winner'] ?? ''}';
      return _GameSummaryPanel(
        key: key,
        cancelled: phase == 'cancelled',
        winner: winner,
        myTeam: '${me['team'] ?? ''}',
        myPlayerId: _int(me['playerId']),
        summary: _map(snapshot['summary']),
        players: players,
        busy: _sendingInteraction,
        onHonor: (playerId) =>
            _sendInteraction('mvp', targetPlayerId: playerId),
        onExit: () => Navigator.pop(context),
      );
    }

    final actionOptions = _nightActions('${me['role']}');
    final isAlive = me['lifeStatus'] == 'alive';
    final actionable =
        isAlive &&
        (phase == 'night' ||
            phase == 'day_nomination' ||
            phase == 'day_vote' ||
            phase == 'day_revote');
    final title = _phaseInstruction(phase, '${me['role']}');
    final actionType =
        _selectedNightAction ??
        (actionOptions.isEmpty ? '' : actionOptions.first);
    final ballotType = phase == 'day_nomination'
        ? 'nomination'
        : phase == 'day_revote'
        ? 'revote'
        : 'vote';
    final submitted = phase == 'night'
        ? _map(snapshot['myActions'])
        : _map(snapshot['myBallots']);
    final submittedKey = phase == 'night' ? actionType : ballotType;
    return _GamePanel(
      key: key,
      title: title,
      icon: _phaseIcon(phase),
      children: [
        if (!isAlive)
          const Text(
            'أنت خارج الجولة. يمكنك متابعة الأحداث والحديث مع المستبعدين.',
          )
        else if (phase == 'night' && actionOptions.isEmpty)
          const Text(
            'أغلق عينيك واستمع إلى أجواء الليل. لا يوجد فعل لدورك الآن.',
          )
        else ...[
          if (phase == 'night' && actionOptions.length > 1)
            SegmentedButton<String>(
              segments: actionOptions
                  .map(
                    (type) => ButtonSegment(
                      value: type,
                      label: Text(_actionLabel(type)),
                      icon: Icon(_actionIcon(type)),
                    ),
                  )
                  .toList(),
              selected: {_selectedNightAction ?? actionOptions.first},
              onSelectionChanged: (values) => setState(() {
                _selectedNightAction = values.first;
                _selectedPlayerId = null;
              }),
            ),
          if (actionable) ...[
            if (submitted.containsKey(submittedKey)) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFF2E8860),
                    size: 20,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      submitted[submittedKey] == null
                          ? 'تم تسجيل الامتناع عن التصويت'
                          : 'تم تسجيل اختيارك: ${_seatFor(players, _int(submitted[submittedKey]))}',
                      key: const ValueKey('mafia-action-receipt'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 10),
            Text(
              _selectedPlayerId == null
                  ? 'اختر لاعباً من المقاعد أولاً.'
                  : 'تم اختيار اللاعب رقم ${_seatFor(players, _selectedPlayerId!)}',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              key: const ValueKey('mafia-submit-action'),
              onPressed:
                  !_acting &&
                      (_selectedPlayerId != null ||
                          phase == 'day_vote' ||
                          phase == 'day_revote')
                  ? _submitSelection
                  : null,
              icon: Icon(_phaseIcon(phase)),
              label: Text(_submitLabel(phase, _selectedPlayerId)),
            ),
          ],
        ],
        if (phase == 'day_discussion')
          const Text('ناقشوا الأدلة بحرية. بعد انتهاء الوقت يبدأ الترشيح.'),
        if (phase == 'day_defense')
          Text(
            _intList(
                  _map(snapshot['phase'])['candidateIds'],
                ).contains(_int(me['playerId']))
                ? 'أنت مرشح الآن. دافع عن نفسك قبل بدء التصويت.'
                : 'استمع إلى دفاع المرشحين. يُفتح صوتهم فقط في هذه المرحلة.',
          ),
      ],
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pollTimer?.cancel();
    _heartbeatTimer?.cancel();
    _clockTimer?.cancel();
    _interactions.dispose();
    _eliminationTimer?.cancel();
    unawaited(_realtimeEvents?.cancel());
    _ambience.dispose();
    _message.dispose();
    _chatRevision.dispose();
    _voice.removeListener(_voiceChanged);
    _voice.dispose();
    super.dispose();
  }
}

enum _MafiaHostActionType { copyCode, kick, close }

class _MafiaHostAction {
  final _MafiaHostActionType type;
  final Map<String, dynamic>? player;

  const _MafiaHostAction(this.type, {this.player});
}

class _HostControlsSheet extends StatelessWidget {
  final Map<String, dynamic> room;
  final List<Map<String, dynamic>> players;
  final int myPlayerId;

  const _HostControlsSheet({
    required this.room,
    required this.players,
    required this.myPlayerId,
  });

  @override
  Widget build(BuildContext context) {
    final canKick = !const {'completed', 'cancelled'}.contains(room['status']);
    final hostUserId = _int(room['hostUserId']);
    return SafeArea(
      child: FractionallySizedBox(
        heightFactor: .78,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.admin_panel_settings_rounded),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'إدارة الغرفة',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  OutlinedButton.icon(
                    key: const ValueKey('mafia-copy-room-code'),
                    onPressed: () => Navigator.pop(
                      context,
                      const _MafiaHostAction(_MafiaHostActionType.copyCode),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 18),
                    label: Text('${room['inviteCode'] ?? ''}'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                canKick
                    ? 'يمكنك طرد لاعب غير نشط، وسيُستبعد فورًا من الصوت والتصويت والجولة.'
                    : 'انتهت الجولة، ويمكنك إغلاق الغرفة أو إعادة تنشيطها من غرفي.',
                style: const TextStyle(
                  color: Color(0xFF52605B),
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.separated(
                  itemCount: players.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final player = players[index];
                    final playerId = _int(player['playerId']);
                    final isMe = playerId == myPlayerId;
                    final isHost = _int(player['userId']) == hostUserId;
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                      leading: CircleAvatar(
                        backgroundColor: const Color(0xFFDCE8DE),
                        child: Text('${player['seatNumber'] ?? index + 1}'),
                      ),
                      title: Row(
                        children: [
                          Flexible(
                            child: Text(
                              '${player['name'] ?? 'لاعب'}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (isHost) ...[
                            const SizedBox(width: 6),
                            const Icon(
                              Icons.workspace_premium_rounded,
                              color: Color(0xFFB99035),
                              size: 18,
                            ),
                          ],
                        ],
                      ),
                      subtitle: Text(
                        isHost
                            ? 'صاحب الغرفة'
                            : player['isReady'] == true
                            ? 'جاهز'
                            : 'بانتظار الجاهزية',
                      ),
                      trailing:
                          canKick && !isMe && player['lifeStatus'] != 'left'
                          ? IconButton(
                              key: ValueKey('mafia-kick-player-$playerId'),
                              tooltip: 'طرد اللاعب',
                              onPressed: () => Navigator.pop(
                                context,
                                _MafiaHostAction(
                                  _MafiaHostActionType.kick,
                                  player: player,
                                ),
                              ),
                              icon: const Icon(
                                Icons.person_remove_rounded,
                                color: Color(0xFF9F302B),
                              ),
                            )
                          : null,
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                key: const ValueKey('mafia-close-room'),
                onPressed: () => Navigator.pop(
                  context,
                  const _MafiaHostAction(_MafiaHostActionType.close),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF9F302B),
                  foregroundColor: Colors.white,
                ),
                icon: const Icon(Icons.power_settings_new_rounded),
                label: const Text('إغلاق الغرفة للجميع'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PhaseStage extends StatelessWidget {
  final String phase;
  final int dayNumber;
  final int remainingSeconds;
  final int totalSeconds;
  final Animation<double> ambience;
  final bool isNight;
  final Color themeAccent;
  final Color stageColor;
  const _PhaseStage({
    super.key,
    required this.phase,
    required this.dayNumber,
    required this.remainingSeconds,
    required this.totalSeconds,
    required this.ambience,
    required this.isNight,
    required this.themeAccent,
    required this.stageColor,
  });

  @override
  Widget build(BuildContext context) {
    final foreground = isNight ? Colors.white : const Color(0xFF18383E);
    final accent = remainingSeconds > 0 && remainingSeconds <= 10
        ? const Color(0xFFD94A46)
        : themeAccent;
    return RepaintBoundary(
      key: const ValueKey('mafia-room-stage'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
        child: Row(
          children: [
            Icon(_phaseIcon(phase), color: accent, size: 27),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _phaseTitle(phase, dayNumber),
                    style: TextStyle(
                      color: foreground,
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    _phaseSubtitle(phase),
                    style: TextStyle(
                      color: isNight ? Colors.white70 : const Color(0xFF53666A),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (remainingSeconds > 0) ...[
              const SizedBox(width: 10),
              TweenAnimationBuilder<double>(
                tween: Tween(
                  end: (remainingSeconds / math.max(1, totalSeconds)).clamp(
                    0.0,
                    1.0,
                  ),
                ),
                duration: Duration(
                  milliseconds: MediaQuery.disableAnimationsOf(context)
                      ? 0
                      : 900,
                ),
                builder: (context, progress, child) => CustomPaint(
                  painter: _CountdownRingPainter(
                    color: accent,
                    progress: progress,
                  ),
                  child: child,
                ),
                child: SizedBox.square(
                  dimension: 57,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        '$remainingSeconds',
                        style: TextStyle(
                          color: foreground,
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        'ثانية',
                        style: TextStyle(color: foreground, fontSize: 9),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountdownRingPainter extends CustomPainter {
  final Color color;
  final double progress;

  const _CountdownRingPainter({required this.color, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide / 2) - 3;
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..color = Colors.black.withValues(alpha: .18)
        ..style = PaintingStyle.fill,
    );
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _CountdownRingPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}

class _VoiceBar extends StatelessWidget {
  final MafiaVoiceController controller;
  final bool isNight;

  const _VoiceBar({required this.controller, required this.isNight});

  @override
  Widget build(BuildContext context) {
    final connected = controller.state == MafiaVoiceState.connected;
    final reconnecting =
        controller.state == MafiaVoiceState.reconnecting ||
        controller.state == MafiaVoiceState.connecting;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: isNight ? Colors.white.withValues(alpha: .08) : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: connected ? const Color(0xFF4A9871) : const Color(0xFFD0BA82),
        ),
      ),
      child: Row(
        children: [
          Icon(
            connected
                ? Icons.graphic_eq_rounded
                : reconnecting
                ? Icons.sync_rounded
                : Icons.cloud_off_rounded,
            color: connected
                ? const Color(0xFF49A878)
                : const Color(0xFFC28B22),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              controller.state == MafiaVoiceState.disabled
                  ? 'الصوت الحي غير مهيأ على الخادم'
                  : reconnecting
                  ? 'جارٍ تأمين الاتصال الصوتي...'
                  : connected
                  ? controller.isInAfterlife
                        ? 'تسمع الجولة وتتحدث في قناة المستبعدين'
                        : controller.canPublish
                        ? controller.microphoneRequested
                              ? 'الصوت متصل والميكروفون تحت تحكمك'
                              : 'الصوت متصل والميكروفون مغلق باختيارك'
                        : controller.microphoneRequested
                        ? 'مرحلة صامتة، سيعود الميكروفون تلقائيًا بعدها'
                        : 'تستمع الآن والميكروفون سيبقى مغلقًا'
                  : 'تعذر الاتصال الصوتي',
              style: TextStyle(
                color: isNight ? Colors.white : const Color(0xFF183129),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          if (controller.needsAudioStart)
            IconButton.filledTonal(
              tooltip: 'تشغيل الصوت',
              onPressed: controller.startAudio,
              icon: const Icon(Icons.play_arrow_rounded),
            ),
          IconButton(
            tooltip: controller.microphoneRequested
                ? 'كتم الميكروفون'
                : 'فتح الميكروفون',
            onPressed: connected ? controller.toggleMicrophone : null,
            icon: Icon(
              controller.microphoneRequested
                  ? Icons.mic_rounded
                  : Icons.mic_off_rounded,
              color: controller.microphoneRequested && !controller.canPublish
                  ? const Color(0xFFC28B22)
                  : null,
            ),
          ),
          IconButton(
            tooltip: controller.speakerEnabled
                ? 'كتم السماعة'
                : 'تشغيل السماعة',
            onPressed: connected ? controller.toggleSpeaker : null,
            icon: Icon(
              controller.speakerEnabled
                  ? Icons.volume_up_rounded
                  : Icons.volume_off_rounded,
            ),
          ),
          if (controller.state == MafiaVoiceState.error)
            IconButton(
              tooltip: 'إعادة الاتصال',
              onPressed: controller.retry,
              icon: const Icon(Icons.refresh_rounded),
            ),
        ],
      ),
    );
  }
}

class _ReactionBar extends StatelessWidget {
  final bool busy;
  final bool isNight;
  final ValueChanged<String> onReact;

  const _ReactionBar({
    required this.busy,
    required this.isNight,
    required this.onReact,
  });

  @override
  Widget build(BuildContext context) => Container(
    height: 62,
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(
      color: isNight
          ? const Color(0xFF17352B).withValues(alpha: .9)
          : Colors.white.withValues(alpha: .94),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isNight ? Colors.white12 : const Color(0xFFD8C89E),
      ),
    ),
    child: Row(
      children: [
        Container(
          width: 62,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isNight ? Colors.white10 : const Color(0xFFF1ECDE),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            'تفاعل\nالآن',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isNight ? Colors.white70 : const Color(0xFF315145),
              fontSize: 10,
              height: 1.15,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        const SizedBox(width: 7),
        for (final kind in const [
          'laugh',
          'happy',
          'angry',
          'surprised',
          'applause',
        ])
          Expanded(
            child: _ReactionButton(
              key: ValueKey('mafia-reaction-$kind'),
              emoji: _interactionEmoji(kind),
              tooltip: _interactionLabel(kind),
              disabled: busy,
              isNight: isNight,
              onTap: () => onReact(kind),
            ),
          ),
      ],
    ),
  );
}

class _ReactionButton extends StatefulWidget {
  final String emoji;
  final String tooltip;
  final bool disabled;
  final bool isNight;
  final VoidCallback onTap;

  const _ReactionButton({
    required this.emoji,
    required this.tooltip,
    required this.disabled,
    required this.isNight,
    required this.onTap,
    super.key,
  });

  @override
  State<_ReactionButton> createState() => _ReactionButtonState();
}

class _ReactionButtonState extends State<_ReactionButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: widget.tooltip,
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: widget.disabled
          ? null
          : (_) => setState(() => _pressed = true),
      onTapCancel: widget.disabled
          ? null
          : () => setState(() => _pressed = false),
      onTapUp: widget.disabled
          ? null
          : (_) {
              setState(() => _pressed = false);
              HapticFeedback.lightImpact();
              widget.onTap();
            },
      child: AnimatedScale(
        scale: _pressed ? .78 : 1,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOutBack,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 2),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: widget.isNight ? Colors.white10 : const Color(0xFFF8F5EC),
            shape: BoxShape.circle,
          ),
          child: Text(widget.emoji, style: const TextStyle(fontSize: 22)),
        ),
      ),
    ),
  );
}

class _InteractionChoice extends StatelessWidget {
  final String kind;
  final VoidCallback onTap;

  const _InteractionChoice({required this.kind, required this.onTap});

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFFF3F1E7),
    borderRadius: BorderRadius.circular(8),
    child: InkWell(
      key: ValueKey('mafia-gift-$kind'),
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            MafiaGiftSprite(kind: kind, size: 56),
            const SizedBox(height: 5),
            Text(
              _interactionLabel(kind),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    ),
  );
}

class _RoomPulseStrip extends StatelessWidget {
  final List<Map<String, dynamic>> players;
  final String phase;
  final bool isNight;

  const _RoomPulseStrip({
    required this.players,
    required this.phase,
    required this.isNight,
  });

  @override
  Widget build(BuildContext context) {
    final alive = players
        .where((player) => player['lifeStatus'] == 'alive')
        .length;
    final connected = players
        .where((player) => player['isConnected'] == true)
        .length;
    final eliminated = players.length - alive;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 8),
      decoration: BoxDecoration(
        color: isNight
            ? const Color(0xFF0D241C).withValues(alpha: .9)
            : const Color(0xFFFFFDF8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNight ? Colors.white12 : const Color(0xFFD8C89E),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: _RoomMetric(
              icon: Icons.favorite_rounded,
              value: '$alive',
              label: 'أحياء',
              color: const Color(0xFF3E9B6D),
              isNight: isNight,
            ),
          ),
          _MetricDivider(isNight: isNight),
          Expanded(
            child: _RoomMetric(
              icon: Icons.wifi_rounded,
              value: '$connected',
              label: 'متصلون',
              color: const Color(0xFF3E86B8),
              isNight: isNight,
            ),
          ),
          _MetricDivider(isNight: isNight),
          Expanded(
            child: _RoomMetric(
              icon: Icons.visibility_rounded,
              value: '$eliminated',
              label: 'مستبعدون',
              color: const Color(0xFFB65C55),
              isNight: isNight,
            ),
          ),
          _MetricDivider(isNight: isNight),
          Expanded(
            child: _RoomMetric(
              icon: _phaseIcon(phase),
              value: '',
              label: _phaseStatusLabel(phase),
              color: const Color(0xFFB99035),
              isNight: isNight,
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricDivider extends StatelessWidget {
  final bool isNight;
  const _MetricDivider({required this.isNight});

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 30,
    color: isNight ? Colors.white12 : const Color(0xFFE2DCCB),
  );
}

class _RoomMetric extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final Color color;
  final bool isNight;

  const _RoomMetric({
    required this.icon,
    required this.value,
    required this.label,
    required this.color,
    required this.isNight,
  });

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 14, color: color),
          if (value.isNotEmpty) ...[
            const SizedBox(width: 3),
            Text(
              value,
              style: TextStyle(
                color: isNight ? Colors.white : const Color(0xFF173A2D),
                fontWeight: FontWeight.w900,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
      const SizedBox(height: 2),
      Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isNight ? Colors.white60 : const Color(0xFF66736E),
          fontSize: 8,
          fontWeight: FontWeight.w700,
        ),
      ),
    ],
  );
}

class _PlayerGrid extends StatelessWidget {
  final List<Map<String, dynamic>> players;
  final Map<String, dynamic> me;
  final int? selectedPlayerId;
  final List<int> candidateIds;
  final Set<int> activeSpeakerUserIds;
  final Set<int> selectablePlayerIds;
  final bool isNight;
  final String phase;
  final Animation<double> ambience;
  final MafiaInteractionController interactions;
  final ValueChanged<int>? onSelect;
  final ValueChanged<Map<String, dynamic>>? onInteract;

  const _PlayerGrid({
    required this.players,
    required this.me,
    required this.selectedPlayerId,
    required this.candidateIds,
    required this.activeSpeakerUserIds,
    required this.selectablePlayerIds,
    required this.isNight,
    required this.phase,
    required this.ambience,
    required this.interactions,
    required this.onSelect,
    required this.onInteract,
  });

  @override
  Widget build(BuildContext context) => RepaintBoundary(
    key: const ValueKey('mafia-player-arena'),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final geometry = MafiaSeatGeometry(
          width: constraints.maxWidth - 16,
          count: math.max(7, players.length),
          rtl: Directionality.of(context) == TextDirection.rtl,
        );
        final seats = <int, Rect>{
          for (var i = 0; i < players.length; i++)
            _int(players[i]['playerId']): geometry.seat(i),
        };
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: [
              Positioned.fill(
                child: Image.asset(
                  mafiaCourtyardAsset,
                  fit: BoxFit.cover,
                  alignment: Alignment.topCenter,
                  cacheWidth: 1200,
                  excludeFromSemantics: true,
                ),
              ),
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        (isNight
                                ? const Color(0xFF102B30)
                                : const Color(0xFFD9E7E7))
                            .withValues(alpha: .65),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                child: Column(
                  children: [
                    const SizedBox(
                      height: 92,
                      child: Align(
                        alignment: AlignmentDirectional.bottomStart,
                        child: Padding(
                          padding: EdgeInsets.only(
                            bottom: 12,
                            right: 6,
                            left: 6,
                          ),
                          child: Text(
                            'ليلة مسلكي',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 25,
                              fontWeight: FontWeight.w900,
                              shadows: [
                                Shadow(color: Colors.black87, blurRadius: 10),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: geometry.height,
                      child: Stack(
                        children: [
                          for (
                            var index = 0;
                            index < math.max(7, players.length);
                            index++
                          )
                            Positioned.fromRect(
                              rect: geometry.seat(index),
                              child: index >= players.length
                                  ? _EmptySeat(
                                      number: index + 1,
                                      isNight: isNight,
                                    )
                                  : _PlayerSeat(
                                      player: players[index],
                                      index: index,
                                      selected:
                                          selectedPlayerId ==
                                          _int(players[index]['playerId']),
                                      speaking: activeSpeakerUserIds.contains(
                                        _int(players[index]['userId']),
                                      ),
                                      candidate: candidateIds.contains(
                                        _int(players[index]['playerId']),
                                      ),
                                      isMe:
                                          _int(players[index]['playerId']) ==
                                          _int(me['playerId']),
                                      isMafiaTeammate:
                                          _int(players[index]['playerId']) !=
                                              _int(me['playerId']) &&
                                          _intList(
                                            me['mafiaTeammateIds'],
                                          ).contains(
                                            _int(players[index]['playerId']),
                                          ) &&
                                          players[index]['lifeStatus'] ==
                                              'alive',
                                      selectable:
                                          onSelect != null &&
                                          selectablePlayerIds.contains(
                                            _int(players[index]['playerId']),
                                          ),
                                      isNight: isNight,
                                      ambience: ambience,
                                      onSelect: onSelect,
                                      onInteract: onInteract,
                                    ),
                            ),
                          Positioned.fill(
                            child: MafiaInteractionLayer(
                              controller: interactions,
                              seats: seats,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

class _PlayerSeat extends StatelessWidget {
  final Map<String, dynamic> player;
  final int index;
  final bool selected;
  final bool speaking;
  final bool candidate;
  final bool isMe;
  final bool isMafiaTeammate;
  final bool selectable;
  final bool isNight;
  final Animation<double> ambience;
  final ValueChanged<int>? onSelect;
  final ValueChanged<Map<String, dynamic>>? onInteract;

  const _PlayerSeat({
    required this.player,
    required this.index,
    required this.selected,
    required this.speaking,
    required this.candidate,
    required this.isMe,
    required this.isMafiaTeammate,
    required this.selectable,
    required this.isNight,
    required this.ambience,
    required this.onSelect,
    required this.onInteract,
  });

  @override
  Widget build(BuildContext context) {
    final id = _int(player['playerId']);
    final dead = player['lifeStatus'] != 'alive';
    final connected = player['isConnected'] == true;
    final borderColor = speaking
        ? const Color(0xFF58D59A)
        : candidate
        ? const Color(0xFFE05B4F)
        : isMafiaTeammate
        ? const Color(0xFFB684DA)
        : isMe
        ? const Color(0xFFD5AD4E)
        : isNight
        ? Colors.white12
        : const Color(0xFFD7D5CB);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: .88, end: 1),
      duration: Duration(
        milliseconds: MediaQuery.disableAnimationsOf(context)
            ? 0
            : 330 + (index * 45),
      ),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.translate(
        offset: Offset(0, (1 - value) * 22),
        child: Opacity(opacity: value.clamp(0, 1), child: child),
      ),
      child: Semantics(
        button: selectable,
        label: 'اللاعب ${player['name']}',
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            key: ValueKey('mafia-player-$id'),
            onTap: selectable ? () => onSelect!(id) : null,
            borderRadius: BorderRadius.circular(8),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              padding: const EdgeInsets.all(5),
              decoration: BoxDecoration(
                color: selected
                    ? const Color(0xFF22685D)
                    : isNight
                    ? const Color(
                        0xFF17383F,
                      ).withValues(alpha: dead ? .82 : .96)
                    : Colors.white.withValues(alpha: dead ? .80 : .96),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: borderColor,
                  width: speaking ? 2.5 : 1.3,
                ),
                boxShadow: [
                  const BoxShadow(
                    color: Color(0x30061D27),
                    blurRadius: 6,
                    offset: Offset(0, 3),
                  ),
                  if (speaking || selected)
                    BoxShadow(
                      color: borderColor.withValues(alpha: .36),
                      blurRadius: speaking ? 15 : 10,
                      spreadRadius: speaking ? 1 : 0,
                    ),
                ],
              ),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AnimatedBuilder(
                          animation: ambience,
                          builder: (context, child) => Transform.scale(
                            scale:
                                speaking &&
                                    !MediaQuery.disableAnimationsOf(context)
                                ? .98 + (ambience.value * .08)
                                : 1,
                            child: child,
                          ),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: borderColor,
                                    width: 2,
                                  ),
                                ),
                                child: CircleAvatar(
                                  radius: 22,
                                  backgroundColor: dead
                                      ? const Color(0xFF8B908D)
                                      : const Color(0xFFDCE8DE),
                                  foregroundImage:
                                      '${player['imageUrl'] ?? ''}'.isNotEmpty
                                      ? NetworkImage('${player['imageUrl']}')
                                      : null,
                                  child: Text(
                                    '${player['name'] ?? ''}'
                                            .characters
                                            .firstOrNull ??
                                        '${player['seatNumber']}',
                                    style: const TextStyle(
                                      color: Color(0xFF173A2D),
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                                ),
                              ),
                              if (speaking)
                                const Positioned(
                                  left: -4,
                                  bottom: -2,
                                  child: CircleAvatar(
                                    radius: 9,
                                    backgroundColor: Color(0xFF49A878),
                                    child: Icon(
                                      Icons.mic,
                                      size: 11,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (isMafiaTeammate)
                                const Positioned(
                                  right: -5,
                                  top: -5,
                                  child: CircleAvatar(
                                    radius: 10,
                                    backgroundColor: Color(0xFF6F3E91),
                                    child: Icon(
                                      Icons.theater_comedy_rounded,
                                      size: 12,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              if (dead)
                                const Positioned.fill(
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 49,
                                    color: Color(0xFFD9584D),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${player['name'] ?? 'لاعب'}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: selected
                                ? Colors.white
                                : isNight
                                ? Colors.white
                                : const Color(0xFF102337),
                            fontSize: 12,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 2),
                        _PlayerStatus(
                          player: player,
                          selected: selected,
                          teammate: isMafiaTeammate,
                          connected: connected,
                          isNight: isNight,
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 1,
                    left: 1,
                    child: Container(
                      width: 7,
                      height: 7,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: connected
                            ? const Color(0xFF4ECB86)
                            : const Color(0xFF8A918E),
                        boxShadow: connected
                            ? const [
                                BoxShadow(
                                  color: Color(0x884ECB86),
                                  blurRadius: 5,
                                ),
                              ]
                            : null,
                      ),
                    ),
                  ),
                  if (candidate)
                    const Positioned(
                      left: 1,
                      bottom: 1,
                      child: Icon(
                        Icons.how_to_vote_rounded,
                        size: 15,
                        color: Color(0xFFE05B4F),
                      ),
                    ),
                  if (!isMe && onInteract != null)
                    Positioned(
                      top: -4,
                      right: -4,
                      child: IconButton(
                        key: ValueKey('mafia-gift-player-$id'),
                        tooltip: 'إهداء وتفاعل',
                        constraints: const BoxConstraints.tightFor(
                          width: 32,
                          height: 32,
                        ),
                        padding: EdgeInsets.zero,
                        style: IconButton.styleFrom(
                          backgroundColor: const Color(0xFFF7E8BC),
                          foregroundColor: const Color(0xFF8B6417),
                        ),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          onInteract!(player);
                        },
                        icon: const Icon(Icons.redeem_rounded, size: 18),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PlayerStatus extends StatelessWidget {
  final Map<String, dynamic> player;
  final bool selected;
  final bool teammate;
  final bool connected;
  final bool isNight;

  const _PlayerStatus({
    required this.player,
    required this.selected,
    required this.teammate,
    required this.connected,
    required this.isNight,
  });

  @override
  Widget build(BuildContext context) {
    final role = player['role'];
    final (label, color) = teammate
        ? ('من فريقك', const Color(0xFFD0A5ED))
        : role != null
        ? (_roleName('$role'), const Color(0xFFD7B65F))
        : player['lifeStatus'] != 'alive'
        ? ('مستبعد', const Color(0xFFE47B72))
        : player['isReady'] == true
        ? ('جاهز', const Color(0xFF58C58A))
        : connected
        ? ('في الغرفة', const Color(0xFF78A8C4))
        : ('غير متصل', const Color(0xFF999F9C));
    return Text(
      label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: selected
            ? Colors.white
            : isNight
            ? color
            : Color.lerp(color, Colors.black, .45),
        fontSize: 10,
        fontWeight: FontWeight.w800,
      ),
    );
  }
}

class _EmptySeat extends StatelessWidget {
  final int number;
  final bool isNight;
  const _EmptySeat({required this.number, required this.isNight});

  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: isNight ? Colors.white.withValues(alpha: .04) : Colors.white54,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(
        color: isNight ? Colors.white12 : const Color(0xFFD6D1C0),
      ),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(
          Icons.chair_alt_outlined,
          color: isNight ? Colors.white30 : Colors.black26,
        ),
        Text(
          '$number',
          style: TextStyle(color: isNight ? Colors.white38 : Colors.black38),
        ),
      ],
    ),
  );
}

class _GamePanel extends StatelessWidget {
  final String title;
  final IconData icon;
  final List<Widget> children;

  const _GamePanel({
    required super.key,
    required this.title,
    required this.icon,
    required this.children,
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: context.maslakiTokens.cardPrimary,
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD0BA82)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Icon(icon, color: const Color(0xFF286046)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        ...children,
      ],
    ),
  );
}

class _RoleRevealDialog extends StatelessWidget {
  final String role;
  const _RoleRevealDialog({required this.role});

  @override
  Widget build(BuildContext context) {
    final mafia = const {'mafia', 'don', 'framer'}.contains(role);
    return Dialog(
      child: Container(
        constraints: const BoxConstraints(maxWidth: 390),
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: mafia ? const Color(0xFF17211E) : const Color(0xFFFFFDF7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFB99035)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _roleIcon(role),
              size: 72,
              color: mafia ? const Color(0xFFE7C36B) : const Color(0xFF286046),
            ),
            const SizedBox(height: 14),
            Text(
              'دورك: ${_roleName(role)}',
              style: TextStyle(
                color: mafia ? Colors.white : const Color(0xFF102337),
                fontSize: 25,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              _roleDescription(role),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mafia ? Colors.white70 : const Color(0xFF465850),
                height: 1.55,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.lock_rounded),
              label: const Text('حفظت دوري'),
            ),
          ],
        ),
      ),
    );
  }
}

class _NarratorBanner extends StatelessWidget {
  final Map<String, dynamic> narrator;
  final bool isNight;

  const _NarratorBanner({required this.narrator, required this.isNight});

  @override
  Widget build(BuildContext context) {
    final tone = '${narrator['tone'] ?? 'guide'}';
    final accent = switch (tone) {
      'danger' => const Color(0xFFD85D50),
      'victory' => const Color(0xFFD4A638),
      'mystery' => const Color(0xFFAE91D6),
      _ => const Color(0xFF55A27A),
    };
    return Semantics(
      liveRegion: true,
      label: '${narrator['title']}. ${narrator['body']}',
      child: Container(
        key: const ValueKey('mafia-narrator'),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: isNight ? const Color(0xFF17352B) : const Color(0xFFFFFCF4),
          borderRadius: BorderRadius.circular(8),
          border: Border(right: BorderSide(color: accent, width: 4)),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: .14),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.record_voice_over_rounded, color: accent),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${narrator['title'] ?? 'راوي المدينة'}',
                    style: TextStyle(
                      color: isNight ? Colors.white : const Color(0xFF102337),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${narrator['body'] ?? ''}',
                    style: TextStyle(
                      color: isNight ? Colors.white70 : const Color(0xFF52605B),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SecretMissionCard extends StatelessWidget {
  final Map<String, dynamic> mission;
  final bool isNight;

  const _SecretMissionCard({required this.mission, required this.isNight});

  @override
  Widget build(BuildContext context) {
    final completed = mission['completed'] == true;
    final accent = completed
        ? const Color(0xFF45A56F)
        : const Color(0xFFC99A31);
    return Container(
      key: const ValueKey('mafia-secret-mission'),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: isNight ? const Color(0xFF142E26) : const Color(0xFFFFF8E8),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: accent.withValues(alpha: .7)),
      ),
      child: Row(
        children: [
          Icon(
            completed ? Icons.task_alt_rounded : Icons.lock_outline_rounded,
            color: accent,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      'مهمتك الخاصة',
                      style: TextStyle(
                        color: isNight
                            ? Colors.white70
                            : const Color(0xFF52605B),
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      completed ? 'مكتملة' : 'قيد اللعب',
                      style: TextStyle(
                        color: accent,
                        fontSize: 11,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${mission['title'] ?? ''}',
                  style: TextStyle(
                    color: isNight ? Colors.white : const Color(0xFF102337),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${mission['description'] ?? ''}',
                  style: TextStyle(
                    color: isNight ? Colors.white70 : const Color(0xFF52605B),
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _MafiaProfileStrip extends StatelessWidget {
  final Map<String, dynamic> profile;

  const _MafiaProfileStrip({required this.profile});

  @override
  Widget build(BuildContext context) {
    final achievements = _list(profile['achievements']);
    return Container(
      key: const ValueKey('mafia-player-profile'),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF183A2E),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFB99035)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: Color(0xFFB99035),
              shape: BoxShape.circle,
            ),
            child: Text(
              '${_int(profile['level'])}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'سجل الموسم',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  '${_int(profile['points'])} نقطة • ${_int(profile['wins'])} فوز • ${_int(profile['gamesPlayed'])} جولة',
                  style: const TextStyle(color: Colors.white70, fontSize: 11),
                ),
              ],
            ),
          ),
          if (achievements.isNotEmpty)
            Tooltip(
              message: achievements
                  .map((item) => '${_map(item)['title']}')
                  .join('، '),
              child: Badge(
                label: Text('${achievements.length}'),
                child: const Icon(
                  Icons.military_tech_rounded,
                  color: Color(0xFFF0CE78),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EliminationReveal extends StatelessWidget {
  final Map<String, dynamic> event;

  const _EliminationReveal({required this.event});

  @override
  Widget build(BuildContext context) {
    final payload = _map(event['payload']);
    final role = '${payload['role'] ?? ''}';
    return IgnorePointer(
      child: ColoredBox(
        color: const Color(0xE6121C19),
        child: Center(
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: .68, end: 1),
            duration: const Duration(milliseconds: 650),
            curve: Curves.easeOutBack,
            builder: (context, value, child) => Transform.scale(
              scale: value,
              child: Opacity(opacity: value.clamp(0, 1), child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.theater_comedy_rounded,
                  size: 76,
                  color: Color(0xFFE25B50),
                ),
                const SizedBox(height: 14),
                Text(
                  'غادر المقعد ${payload['seatNumber'] ?? '?'} المدينة',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 23,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (role.isNotEmpty) ...[
                  const SizedBox(height: 7),
                  Text(
                    'كان دوره: ${_roleName(role)}',
                    style: const TextStyle(
                      color: Color(0xFFF0CE78),
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GameSummaryPanel extends StatelessWidget {
  final bool cancelled;
  final String winner;
  final String myTeam;
  final int myPlayerId;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> players;
  final bool busy;
  final ValueChanged<int> onHonor;
  final VoidCallback onExit;

  const _GameSummaryPanel({
    super.key,
    required this.cancelled,
    required this.winner,
    required this.myTeam,
    required this.myPlayerId,
    required this.summary,
    required this.players,
    required this.busy,
    required this.onHonor,
    required this.onExit,
  });

  @override
  Widget build(BuildContext context) {
    final myHonorPlayerId = _int(summary['myHonorPlayerId']);
    final honors = _list(summary['honors']).map(_map).toList();
    final eliminations = _list(summary['eliminations']).map(_map).toList();
    return _GamePanel(
      key: const ValueKey('mafia-game-summary'),
      title: cancelled
          ? 'أُغلقت الليلة'
          : winner == 'town'
          ? 'أشرقت شمس المدينة'
          : 'أصبحت المدينة للمافيا',
      icon: winner == 'town' ? Icons.wb_sunny_rounded : Icons.dark_mode_rounded,
      children: [
        if (!cancelled)
          Text(
            myTeam == winner
                ? 'انتصرت مع فريقك بعد ${_int(summary['days'])} أيام.'
                : 'كُشفت الأسرار. الجولة القادمة قد تغيّر كل شيء.',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        if (eliminations.isNotEmpty) ...[
          const SizedBox(height: 12),
          const Text(
            'مسار الليلة',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: eliminations.map((item) {
              final role = '${item['role'] ?? ''}';
              return Chip(
                avatar: const Icon(Icons.close_rounded, size: 16),
                label: Text(
                  'اليوم ${item['dayNumber']} • المقعد ${item['seatNumber']}${role.isEmpty ? '' : ' • ${_roleName(role)}'}',
                ),
              );
            }).toList(),
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'كشف الأدوار',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: players.map((player) {
            final role = '${player['role'] ?? ''}';
            return Chip(
              avatar: CircleAvatar(child: Text('${player['seatNumber']}')),
              label: Text(
                '${player['name'] ?? 'لاعب'}${role.isEmpty ? '' : ' • ${_roleName(role)}'}',
              ),
            );
          }).toList(),
        ),
        if (!cancelled) ...[
          const SizedBox(height: 14),
          Text(
            myHonorPlayerId > 0 ? 'تم تسجيل نجمك للجولة' : 'من صنع أجمل لحظة؟',
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          if (myHonorPlayerId == 0)
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: players
                  .where((player) => _int(player['playerId']) != myPlayerId)
                  .map(
                    (player) => ActionChip(
                      key: ValueKey('mafia-honor-${player['playerId']}'),
                      avatar: const Icon(Icons.workspace_premium_rounded),
                      label: Text('${player['name'] ?? 'لاعب'}'),
                      onPressed: busy
                          ? null
                          : () => onHonor(_int(player['playerId'])),
                    ),
                  )
                  .toList(),
            )
          else
            Text(
              honors.isEmpty
                  ? 'شكراً لتكريمك لاعباً من المجلس.'
                  : 'الترتيب الحالي: ${honors.map((item) => 'المقعد ${_seatFor(players, _int(item['playerId']))} (${item['votes']})').join('، ')}',
            ),
        ],
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: onExit,
          icon: const Icon(Icons.home_rounded),
          label: const Text('العودة إلى الألعاب'),
        ),
      ],
    );
  }
}

class _EventTimeline extends StatelessWidget {
  final List<dynamic> events;
  const _EventTimeline({required this.events});

  @override
  Widget build(BuildContext context) {
    final visible = events.reversed
        .where(
          (event) => !const {
            'player_interaction',
            'secret_mission',
            'player_reported',
          }.contains(_map(event)['type']),
        )
        .take(5)
        .toList();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: context.maslakiTokens.cardPrimary,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'سجل المدينة',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 6),
          ...visible.map((raw) {
            final item = _map(raw);
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  const Icon(Icons.circle, size: 7, color: Color(0xFFB99035)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _eventText('${item['type']}', _map(item['payload'])),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function() onRetry;
  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: const Color(0xFFFFE7E2),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFFD35C4F)),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline_rounded, color: Color(0xFFB33D32)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(message, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
        IconButton(onPressed: onRetry, icon: const Icon(Icons.refresh_rounded)),
      ],
    ),
  );
}

void _showRules(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => DraggableScrollableSheet(
      expand: false,
      initialChildSize: .78,
      maxChildSize: .94,
      builder: (context, controller) => ListView(
        controller: controller,
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 28),
        children: const [
          Text(
            'قوانين ليلة مسلكي',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900),
          ),
          SizedBox(height: 12),
          _Rule(
            'الهدف',
            'يفوز أهل المدينة عند إخراج جميع أفراد المافيا. تفوز المافيا عندما يصبح عددها مساوياً لعدد أهل المدينة الأحياء.',
          ),
          _Rule(
            'الليل',
            'يتشاور فريق المافيا ويختار هدفاً. الطبيب يحمي لاعباً، المحقق يفحص لاعباً، والدون يبحث عن المحقق.',
          ),
          _Rule(
            'النهار',
            'يناقش الأحياء ما حدث، ثم يرشحون المشتبه بهم. يحصل المرشحون على وقت للدفاع قبل التصويت.',
          ),
          _Rule(
            'التعادل',
            'إذا تعادل أعلى مرشحين تعاد جولة التصويت بينهما. استمرار التعادل ينهي اليوم بلا إقصاء.',
          ),
          _Rule(
            'بعد الإقصاء',
            'لا يشارك المستبعد في نقاش الأحياء أو التصويت، ويمكنه متابعة اللعب في قناة المستبعدين.',
          ),
          _Rule(
            'الطبيب',
            'يمكنه حماية نفسه، لكنه لا يستطيع حماية الشخص نفسه في ليلتين متتاليتين.',
          ),
          _Rule(
            'الحارس',
            'يحمي لاعباً آخر. إذا استهدفته المافيا ينجو الهدف ويُستبعد الحارس بدلاً منه.',
          ),
          _Rule(
            'المضلّل',
            'يستطيع اختيار مواطن ليظهر للمحقق كأنه من المافيا في تلك الليلة فقط.',
          ),
          _Rule(
            'الصوت',
            'في الليل يسمع ويتحدث فريق المافيا فقط. في الدفاع يتحدث المرشحون وحدهم. بقية الصلاحيات يطبقها الخادم تلقائياً.',
          ),
        ],
      ),
    ),
  );
}

class _Rule extends StatelessWidget {
  final String title;
  final String body;
  const _Rule(this.title, this.body);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 14),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF286046),
          ),
        ),
        const SizedBox(height: 3),
        Text(body, style: const TextStyle(height: 1.5)),
      ],
    ),
  );
}

Map<String, dynamic> _map(dynamic value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};
List<dynamic> _list(dynamic value) => value is List ? value : const [];
int _int(dynamic value) => int.tryParse('$value') ?? 0;
List<int> _intList(dynamic value) => _list(value).map(_int).toList();

String? _defaultNightAction(String role) => switch (role) {
  'mafia' || 'framer' || 'don' => 'mafia_kill',
  'doctor' => 'doctor_protect',
  'bodyguard' => 'bodyguard_protect',
  'detective' => 'detective_inspect',
  _ => null,
};

List<String> _nightActions(String role) => switch (role) {
  'mafia' => const ['mafia_kill'],
  'framer' => const ['mafia_kill', 'framer_frame'],
  'don' => const ['mafia_kill', 'don_inspect'],
  'doctor' => const ['doctor_protect'],
  'bodyguard' => const ['bodyguard_protect'],
  'detective' => const ['detective_inspect'],
  _ => const [],
};

String _phaseTitle(String phase, int day) => switch (phase) {
  'lobby' => 'نجمع أهل المدينة',
  'role_reveal' => 'الأدوار السرية',
  'night' => day == 0 ? 'ليلة التعارف' : 'الليلة $day',
  'day_discussion' => 'نقاش اليوم $day',
  'day_nomination' => 'وقت الترشيح',
  'day_defense' => 'دفاع المرشحين',
  'day_vote' => 'قرار المدينة',
  'day_revote' => 'كسر التعادل',
  'completed' => 'انتهت الجولة',
  _ => 'ليلة مسلكي',
};

String _phaseSubtitle(String phase) => switch (phase) {
  'lobby' => 'ادعُ أصدقاءك واضغط جاهز',
  'role_reveal' => 'دورك لك وحدك',
  'night' => 'الصمت يكشف أكثر مما يخفي',
  'day_discussion' => 'تكلم، راقب، واستنتج',
  'day_nomination' => 'رشح من تشك به',
  'day_defense' => 'اسمع قبل أن تحكم',
  'day_vote' || 'day_revote' => 'صوت واحد قد يغيّر المدينة',
  'completed' => 'انكشفت كل الأسرار',
  _ => '',
};

String _phaseStatusLabel(String phase) => switch (phase) {
  'lobby' => 'تجهيز الغرفة',
  'role_reveal' => 'كشف الأدوار',
  'night' => 'وقت الليل',
  'day_discussion' => 'نقاش مباشر',
  'day_nomination' => 'الترشيح',
  'day_defense' => 'الدفاع',
  'day_vote' || 'day_revote' => 'التصويت',
  'completed' => 'النتيجة',
  'cancelled' => 'مغلقة',
  _ => 'جولة نشطة',
};

String _phaseInstruction(String phase, String role) => switch (phase) {
  'night' =>
    _defaultNightAction(role) == null
        ? 'انتظر بزوغ النهار'
        : 'اختر قرارك لهذه الليلة',
  'day_discussion' => 'ناقشوا ما حدث',
  'day_nomination' => 'من يستحق الدفاع عن نفسه؟',
  'day_defense' => 'وقت الدفاع',
  'day_vote' => 'اختر من سيغادر المدينة',
  'day_revote' => 'احسم التعادل',
  _ => 'تابع الجولة',
};

IconData _phaseIcon(String phase) => switch (phase) {
  'night' => Icons.dark_mode_rounded,
  'day_discussion' => Icons.record_voice_over_rounded,
  'day_nomination' => Icons.front_hand_rounded,
  'day_defense' => Icons.campaign_rounded,
  'day_vote' || 'day_revote' => Icons.how_to_vote_rounded,
  _ => Icons.groups_rounded,
};

String _roleName(String role) => switch (role) {
  'citizen' => 'مواطن',
  'mafia' => 'مافيا',
  'don' => 'الدون',
  'detective' => 'المحقق',
  'doctor' => 'الطبيب',
  'bodyguard' => 'الحارس',
  'framer' => 'المضلّل',
  _ => role,
};

IconData _roleIcon(String role) => switch (role) {
  'mafia' => Icons.theater_comedy_rounded,
  'don' => Icons.workspace_premium_rounded,
  'detective' => Icons.search_rounded,
  'doctor' => Icons.medical_services_rounded,
  'bodyguard' => Icons.shield_rounded,
  'framer' => Icons.psychology_alt_rounded,
  _ => Icons.person_rounded,
};

String _roleDescription(String role) => switch (role) {
  'citizen' =>
    'راقب النقاش وصوّت بحكمة. لا تملك فعلاً ليلياً، لكن قرار المدينة بيدك.',
  'mafia' =>
    'تعرف فريقك وتتحدث معه ليلاً. اتفقوا على هدف واحد ولا تكشفوا أنفسكم نهاراً.',
  'don' => 'تقود فريق المافيا، وتستطيع أيضاً فحص لاعب لمعرفة إن كان هو المحقق.',
  'detective' =>
    'افحص لاعباً كل ليلة لتعرف إن كان من فريق المافيا، وانتبه لخداع المضلّل.',
  'doctor' =>
    'احمِ لاعباً من هجوم الليل. يمكنك حماية نفسك لكن ليس الهدف نفسه ليلتين متتاليتين.',
  'bodyguard' =>
    'احمِ لاعباً آخر. إن هاجمته المافيا تنقذه وتغادر أنت بدلاً منه.',
  'framer' =>
    'تقاتل مع المافيا، ويمكنك تضليل المحقق بجعل مواطن يبدو مشبوهاً لليلة واحدة.',
  _ => '',
};

String _actionLabel(String type) => switch (type) {
  'mafia_kill' => 'استهداف',
  'framer_frame' => 'تضليل',
  'don_inspect' => 'بحث',
  'doctor_protect' => 'حماية',
  'bodyguard_protect' => 'حراسة',
  'detective_inspect' => 'تحقيق',
  _ => 'اختيار',
};

IconData _actionIcon(String type) => switch (type) {
  'mafia_kill' => Icons.gps_fixed_rounded,
  'framer_frame' => Icons.psychology_alt_rounded,
  'don_inspect' || 'detective_inspect' => Icons.search_rounded,
  'doctor_protect' => Icons.medical_services_rounded,
  'bodyguard_protect' => Icons.shield_rounded,
  _ => Icons.touch_app_rounded,
};

String _submitLabel(String phase, int? selected) {
  if ((phase == 'day_vote' || phase == 'day_revote') && selected == null) {
    return 'امتناع عن التصويت';
  }
  return switch (phase) {
    'day_nomination' => 'تأكيد الترشيح',
    'day_vote' || 'day_revote' => 'تأكيد التصويت',
    'night' => 'تثبيت قرار الليل',
    _ => 'تأكيد',
  };
}

String _channelTitle(String channel) => switch (channel) {
  'mafia' => 'محادثة فريق المافيا',
  'dead' => 'محادثة المستبعدين',
  _ => 'محادثة المدينة',
};

String _interactionEmoji(String kind) => switch (kind) {
  'laugh' => '😂',
  'happy' => '😍',
  'angry' => '😠',
  'surprised' => '😮',
  'applause' => '👏',
  'rose' => '🌹',
  'tea' => '🍵',
  'egg' => '🥚',
  'mvp' => '🏆',
  _ => '✨',
};

String _interactionLabel(String kind) => switch (kind) {
  'laugh' => 'يضحك',
  'happy' => 'سعيد',
  'angry' => 'غاضب',
  'surprised' => 'مندهش',
  'applause' => 'تصفيق',
  'rose' => 'وردة',
  'tea' => 'كأس شاي',
  'egg' => 'بيضة',
  'mvp' => 'نجم الجولة',
  _ => 'تفاعل',
};

String _eventText(String type, Map<String, dynamic> payload) => switch (type) {
  'game_started' => 'بدأت الجولة ووزعت الأدوار.',
  'phase_changed' => 'انتقلت المدينة إلى مرحلة جديدة.',
  'player_eliminated' => 'غادر لاعب المدينة.',
  'quiet_night' => 'مرّ الليل دون ضحية.',
  'bodyguard_sacrifice' => 'ضحّى الحارس بنفسه لحماية لاعب.',
  'vote_tied' => 'انتهى التصويت بالتعادل.',
  'investigation_result' =>
    payload['isMafia'] == true
        ? 'نتيجة التحقيق: الهدف مرتبط بالمافيا.'
        : 'نتيجة التحقيق: الهدف لا ينتمي إلى المافيا.',
  'don_result' =>
    payload['isDetective'] == true ? 'وجدت المحقق.' : 'هذا اللاعب ليس المحقق.',
  'player_kicked' => 'أخرج صاحب الغرفة لاعبًا من الجولة.',
  'room_closed' => 'أغلق صاحب الغرفة الجولة.',
  _ => 'حدث جديد في المدينة.',
};

int _seatFor(List<Map<String, dynamic>> players, int playerId) {
  for (final player in players) {
    if (_int(player['playerId']) == playerId) return _int(player['seatNumber']);
  }
  return playerId;
}

String _friendlyError(Object error) {
  final text = '$error';
  if (text.contains('MICROPHONE_PERMISSION_DENIED')) {
    return 'يلزم السماح بالميكروفون لتشغيل الصوت الحي.';
  }
  if (text.contains('MAFIA_PHASE_EXPIRED') ||
      text.contains('MAFIA_PHASE_CHANGED')) {
    return 'انتهى وقت هذه المرحلة. تم تحديث الجولة.';
  }
  if (text.contains('MAFIA_DOCTOR_REPEAT_FORBIDDEN')) {
    return 'لا يمكن للطبيب حماية اللاعب نفسه في ليلتين متتاليتين.';
  }
  if (text.contains('MAFIA_HOST_REQUIRED')) {
    return 'هذا الإجراء متاح لصاحب الغرفة فقط.';
  }
  if (text.contains('MAFIA_KICK_LOBBY_ONLY')) {
    return 'يمكن طرد اللاعبين قبل بدء الجولة فقط.';
  }
  if (text.contains('MAFIA_HONOR_ALREADY_CAST')) {
    return 'سبق أن اخترت نجم هذه الجولة.';
  }
  return 'تعذر تنفيذ القرار. تحقق من الاتصال وحاول مجدداً.';
}

int _phaseDuration(Map<String, dynamic> room) {
  final start = DateTime.tryParse('${room['phaseStartedAt']}');
  final end = DateTime.tryParse('${room['phaseEndsAt']}');
  return start != null && end != null
      ? math.max(1, end.difference(start).inSeconds)
      : 30;
}

String _chatChannel(Map<String, dynamic>? snapshot) {
  final me = _map(snapshot?['me']), room = _map(snapshot?['room']);
  if (me['lifeStatus'] == 'dead' && room['status'] != 'completed') {
    return 'dead';
  }
  return room['status'] == 'night' && me['team'] == 'mafia'
      ? 'mafia'
      : 'public';
}

class _MafiaRoomPalette {
  final Color accent;
  final Color dayTop;
  final Color dayBottom;
  final Color daySurface;
  final Color nightTop;
  final Color nightBottom;
  final Color nightSurface;

  const _MafiaRoomPalette({
    required this.accent,
    required this.dayTop,
    required this.dayBottom,
    required this.daySurface,
    required this.nightTop,
    required this.nightBottom,
    required this.nightSurface,
  });
}

_MafiaRoomPalette _mafiaPalette(String theme) => switch (theme) {
  'royal' => const _MafiaRoomPalette(
    accent: Color(0xFFD8AD4A),
    dayTop: Color(0xFFF5F0E4),
    dayBottom: Color(0xFFE6E0D3),
    daySurface: Color(0xFFFFFCF4),
    nightTop: Color(0xFF20252B),
    nightBottom: Color(0xFF0D1115),
    nightSurface: Color(0xFF292C2F),
  ),
  'cinema' => const _MafiaRoomPalette(
    accent: Color(0xFFE19A5B),
    dayTop: Color(0xFFF5EEE8),
    dayBottom: Color(0xFFE8DDD8),
    daySurface: Color(0xFFFFF9F5),
    nightTop: Color(0xFF321C24),
    nightBottom: Color(0xFF160B0F),
    nightSurface: Color(0xFF41232B),
  ),
  _ => const _MafiaRoomPalette(
    accent: Color(0xFFC59A38),
    dayTop: Color(0xFFF3F7F8),
    dayBottom: Color(0xFFE3EBEB),
    daySurface: Color(0xFFFFFCF2),
    nightTop: Color(0xFF16323A),
    nightBottom: Color(0xFF111D25),
    nightSurface: Color(0xFF122C24),
  ),
};
