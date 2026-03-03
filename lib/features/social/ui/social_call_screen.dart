import 'dart:async';
import 'dart:convert';

import 'package:bestoffer/features/auth/state/auth_controller.dart';
import 'package:bestoffer/features/notifications/data/notifications_api.dart';
import 'package:bestoffer/features/social/data/social_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

final socialCallApiProvider = Provider<SocialApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return SocialApi(dio);
});

final socialCallLiveApiProvider = Provider<NotificationsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return NotificationsApi(dio);
});

class SocialCallScreen extends ConsumerStatefulWidget {
  final int threadId;
  final bool isCaller;
  final int? initialSessionId;
  final String? remoteDisplayName;

  const SocialCallScreen({
    super.key,
    required this.threadId,
    required this.isCaller,
    this.initialSessionId,
    this.remoteDisplayName,
  });

  @override
  ConsumerState<SocialCallScreen> createState() => _SocialCallScreenState();
}

class _SocialCallScreenState extends ConsumerState<SocialCallScreen> {
  SocialApi get _api => ref.read(socialCallApiProvider);
  NotificationsApi get _liveApi => ref.read(socialCallLiveApiProvider);

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<NotificationLiveEvent>? _streamSub;
  Timer? _ticker;
  Timer? _reconnectTimer;
  Timer? _ringTimer;
  Timer? _iceRecoverTimer;

  final Set<int> _handledSignalIds = <int>{};
  final List<RTCIceCandidate> _queuedRemoteCandidates = <RTCIceCandidate>[];

  int? _sessionId;
  bool _busy = true;
  bool _inCall = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _pendingIncomingAccept = false;
  bool _acceptedIncoming = false;
  bool _disposed = false;
  bool _remoteDescriptionSet = false;
  bool _callEnded = false;
  int _reconnectAttempt = 0;
  int? _lastEventId;
  String _statusText = 'جاري تهيئة الاتصال...';
  DateTime? _connectedAt;
  Map<String, dynamic>? _pendingOfferPayload;

  @override
  void initState() {
    super.initState();
    _sessionId = widget.initialSessionId;
    unawaited(_bootstrap());
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _streamSub?.cancel();
    _reconnectTimer?.cancel();
    _ringTimer?.cancel();
    _iceRecoverTimer?.cancel();
    unawaited(_disposeRtc());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _prepareRtc();
      await _connectSignalStream();
      await _loadCallState();

      if (widget.isCaller && _sessionId == null) {
        final out = await _api.startThreadCall(threadId: widget.threadId);
        final session = out['session'];
        if (session is Map) {
          _sessionId = _asInt(session['id']);
        }
        _startRinging(incoming: false);
        await _createAndSendOffer();
        _setStatus('جاري الاتصال بالطرف الآخر...');
      } else if (!widget.isCaller) {
        _startRinging(incoming: true);
        _setStatus('مكالمة واردة...');
      }

      _startTicker();
    } on DioException catch (e) {
      _setStatus(_mapCallError(e));
    } catch (_) {
      _setStatus('تعذر بدء الاتصال داخل التطبيق');
    } finally {
      if (!_disposed && mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _prepareRtc() async {
    _pc = await createPeerConnection(_buildRtcConfig());

    _pc!.onConnectionState = (state) {
      if (!mounted || _disposed) return;

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _onConnected();
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setStatus('انقطع الاتصال، جاري محاولة الاستعادة...');
        _scheduleIceRecover();
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setStatus('فشل الاتصال، جاري إعادة المحاولة...');
        _scheduleIceRecover(force: true);
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _stopRinging();
        _setStatus('انتهت المكالمة');
      }
    };

    _pc!.onIceConnectionState = (state) {
      if (!mounted || _disposed) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _onConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _scheduleIceRecover(force: true);
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
        _scheduleIceRecover();
      }
    };

    _pc!.onIceCandidate = (candidate) {
      final text = candidate.candidate;
      if (text == null || text.isEmpty) return;
      unawaited(
        _sendSignal(
          signalType: 'ice',
          signalPayload: {
            'candidate': text,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    await Helper.setSpeakerphoneOn(true);
  }

  Map<String, dynamic> _buildRtcConfig() {
    final servers = <Map<String, dynamic>>[
      {
        'urls': <String>[
          'stun:stun.l.google.com:19302',
          'stun:stun1.l.google.com:19302',
        ],
      },
    ];

    const turnUrl = String.fromEnvironment('RTC_TURN_URL', defaultValue: '');
    const turnUsername = String.fromEnvironment(
      'RTC_TURN_USERNAME',
      defaultValue: '',
    );
    const turnCredential = String.fromEnvironment(
      'RTC_TURN_CREDENTIAL',
      defaultValue: '',
    );
    if (turnUrl.trim().isNotEmpty) {
      servers.add({
        'urls': turnUrl.trim(),
        if (turnUsername.trim().isNotEmpty) 'username': turnUsername.trim(),
        if (turnCredential.trim().isNotEmpty) 'credential': turnCredential,
      });
    }

    servers.addAll(_parseExtraIceServers());

    return {
      'iceServers': servers,
      'iceTransportPolicy': 'all',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'sdpSemantics': 'unified-plan',
    };
  }

  List<Map<String, dynamic>> _parseExtraIceServers() {
    const raw = String.fromEnvironment(
      'RTC_ICE_SERVERS_JSON',
      defaultValue: '',
    );
    final text = raw.trim();
    if (text.isEmpty) return const [];

    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) return const [];
      final out = <Map<String, dynamic>>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final urls = map['urls'];
        final hasUrls =
            (urls is String && urls.trim().isNotEmpty) ||
            (urls is List && urls.any((e) => '$e'.trim().isNotEmpty));
        if (!hasUrls) continue;
        out.add(map);
      }
      return out;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _connectSignalStream() async {
    _streamSub?.cancel();
    _reconnectTimer?.cancel();
    _streamSub = _liveApi
        .streamEvents(lastEventId: _lastEventId)
        .listen(
          (event) {
            if (event.eventId != null && event.eventId! > 0) {
              _lastEventId = event.eventId;
            }

            if (event.event == 'connected' || event.event == 'replayed') {
              _reconnectAttempt = 0;
              return;
            }

            if (event.event != 'social_call_update') return;
            final threadId = _asInt(
              event.data['threadId'] ?? event.data['thread_id'],
            );
            if (threadId != widget.threadId) return;
            unawaited(_handleCallUpdateEvent(event.data));
          },
          onError: (_) {
            if (mounted) {
              setState(
                () => _statusText = 'تقطّع في الاتصال، جاري الاستعادة...',
              );
            }
            _scheduleReconnect();
          },
          onDone: _scheduleReconnect,
          cancelOnError: true,
        );
  }

  void _scheduleReconnect() {
    if (!mounted || _disposed) return;
    if (_reconnectTimer?.isActive == true) return;

    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6);
    final delaySeconds = switch (_reconnectAttempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 12,
      5 => 20,
      _ => 30,
    };

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted || _disposed) return;
      unawaited(_connectSignalStream());
    });
  }

  Future<void> _loadCallState() async {
    final state = await _api.getThreadCallState(threadId: widget.threadId);
    final session = state['session'];
    if (session is Map) {
      _sessionId = _asInt(session['id']) ?? _sessionId;
      final status = _asString(session['status']);
      if (status == 'active') {
        _onConnected();
      } else if (status == 'ringing') {
        _startRinging(incoming: !widget.isCaller);
        _setStatus(widget.isCaller ? 'جاري الرنين...' : 'مكالمة واردة...');
      }
    }

    final signalsRaw = state['signals'];
    if (signalsRaw is List) {
      for (final row in signalsRaw) {
        if (row is! Map) continue;
        await _consumeSignal(Map<String, dynamic>.from(row));
      }
    }
  }

  Future<void> _createAndSendOffer({bool iceRestart = false}) async {
    if (_pc == null) return;
    final offer = await _pc!.createOffer({
      'offerToReceiveAudio': true,
      if (iceRestart) 'iceRestart': true,
    });
    await _pc!.setLocalDescription(offer);
    await _sendSignal(
      signalType: 'offer',
      signalPayload: {
        'sdp': offer.sdp,
        'type': offer.type,
        if (iceRestart) 'iceRestart': true,
      },
    );
  }

  Future<void> _sendSignal({
    required String signalType,
    Map<String, dynamic>? signalPayload,
  }) async {
    final out = await _api.sendThreadCallSignal(
      threadId: widget.threadId,
      sessionId: _sessionId,
      signalType: signalType,
      signalPayload: signalPayload,
    );
    final session = out['session'];
    if (session is Map) {
      _sessionId = _asInt(session['id']) ?? _sessionId;
    }
  }

  Future<void> _handleCallUpdateEvent(Map<String, dynamic> data) async {
    final session = data['session'];
    if (session is Map) {
      _sessionId = _asInt(session['id']) ?? _sessionId;
    }

    final eventType = _asString(data['eventType']) ?? '';
    if (eventType == 'incoming_call') {
      _startRinging(incoming: true);
      _setStatus('مكالمة واردة...');
    }
    if (eventType == 'outgoing_call') {
      _startRinging(incoming: false);
      _setStatus('جاري الرنين...');
    }
    if (eventType == 'call_ended') {
      await _remoteEndCall();
      return;
    }

    final signalRaw = data['signal'];
    if (signalRaw is Map) {
      await _consumeSignal(Map<String, dynamic>.from(signalRaw));
    }
  }

  Future<void> _consumeSignal(Map<String, dynamic> signal) async {
    final signalId = _asInt(signal['id']);
    if (signalId != null && _handledSignalIds.contains(signalId)) return;
    if (signalId != null) _handledSignalIds.add(signalId);

    final type = _asString(signal['signalType'] ?? signal['signal_type']);
    final payload = signal['signalPayload'] is Map
        ? Map<String, dynamic>.from(signal['signalPayload'] as Map)
        : (signal['signal_payload'] is Map
              ? Map<String, dynamic>.from(signal['signal_payload'] as Map)
              : <String, dynamic>{});

    if (type == 'ringing') {
      _startRinging(incoming: !widget.isCaller);
      _setStatus(widget.isCaller ? 'جاري الرنين...' : 'مكالمة واردة...');
      return;
    }

    if (type == 'offer') {
      if (!widget.isCaller && !_acceptedIncoming) {
        _pendingOfferPayload = payload;
        _pendingIncomingAccept = false;
        _startRinging(incoming: true);
        _setStatus('مكالمة واردة...');
        if (mounted) setState(() {});
        return;
      }
      await _handleOffer(payload);
      return;
    }

    if (type == 'answer') {
      await _handleAnswer(payload);
      return;
    }

    if (type == 'ice') {
      await _handleIce(payload);
      return;
    }

    if (type == 'accept') {
      _stopRinging();
      _setStatus('تم الرد، جاري تثبيت الصوت...');
      return;
    }

    if (type == 'hangup' || type == 'decline') {
      await _remoteEndCall();
      return;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    if (_pc == null) return;
    final sdp = _asString(payload['sdp']);
    final type = _asString(payload['type']) ?? 'offer';
    if (sdp == null || sdp.isEmpty) return;

    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    await _flushQueuedCandidates();

    final answer = await _pc!.createAnswer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(answer);
    await _sendSignal(
      signalType: 'answer',
      signalPayload: {'sdp': answer.sdp, 'type': answer.type},
    );

    _onConnected();
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    if (_pc == null) return;
    final sdp = _asString(payload['sdp']);
    final type = _asString(payload['type']) ?? 'answer';
    if (sdp == null || sdp.isEmpty) return;

    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    await _flushQueuedCandidates();
    _onConnected();
  }

  Future<void> _handleIce(Map<String, dynamic> payload) async {
    if (_pc == null) return;
    final candidateText = _asString(payload['candidate']);
    if (candidateText == null || candidateText.isEmpty) return;
    final candidate = RTCIceCandidate(
      candidateText,
      _asString(payload['sdpMid']),
      _asInt(payload['sdpMLineIndex']),
    );

    if (!_remoteDescriptionSet) {
      _queuedRemoteCandidates.add(candidate);
      return;
    }
    await _pc!.addCandidate(candidate);
  }

  Future<void> _flushQueuedCandidates() async {
    if (_pc == null || !_remoteDescriptionSet) return;
    if (_queuedRemoteCandidates.isEmpty) return;
    final pending = List<RTCIceCandidate>.from(_queuedRemoteCandidates);
    _queuedRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await _pc!.addCandidate(candidate);
      } catch (_) {}
    }
  }

  void _scheduleIceRecover({bool force = false}) {
    if (_disposed || !mounted) return;
    if (_iceRecoverTimer?.isActive == true && !force) return;
    _iceRecoverTimer?.cancel();
    _iceRecoverTimer = Timer(const Duration(seconds: 2), () {
      if (_disposed || !mounted) return;
      unawaited(_recoverIce());
    });
  }

  Future<void> _recoverIce() async {
    if (_pc == null) return;
    if (!widget.isCaller) return;
    try {
      _setStatus('جاري إعادة تثبيت المكالمة...');
      await _createAndSendOffer(iceRestart: true);
    } catch (_) {
      _setStatus('تعذر استعادة الاتصال حاليًا');
    }
  }

  Future<void> _acceptIncoming() async {
    if (_pendingOfferPayload == null || _pendingIncomingAccept) return;
    setState(() => _pendingIncomingAccept = true);
    try {
      await _sendSignal(signalType: 'accept');
      _acceptedIncoming = true;
      _stopRinging();
      final pending = _pendingOfferPayload;
      _pendingOfferPayload = null;
      if (pending != null) {
        await _handleOffer(pending);
      }
    } finally {
      if (mounted) setState(() => _pendingIncomingAccept = false);
    }
  }

  Future<void> _declineIncoming() async {
    await _endCall(status: 'declined', reason: 'declined_by_user');
  }

  Future<void> _remoteEndCall() async {
    if (_callEnded) return;
    _callEnded = true;
    _stopRinging();
    _setStatus('انتهت المكالمة');
    await _disposeRtc();
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  Future<void> _endCall({
    String status = 'ended',
    String reason = 'user_hangup',
  }) async {
    if (_callEnded) return;
    _callEnded = true;
    _stopRinging();
    try {
      await _api.endThreadCall(
        threadId: widget.threadId,
        status: status,
        reason: reason,
      );
    } catch (_) {
      // Ignore network errors at call end.
    }
    await _disposeRtc();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposeRtc() async {
    _ticker?.cancel();
    _ticker = null;
    _stopRinging();
    _iceRecoverTimer?.cancel();
    _iceRecoverTimer = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    _remoteDescriptionSet = false;
    _queuedRemoteCandidates.clear();
  }

  void _onConnected() {
    _stopRinging();
    if (mounted) {
      setState(() {
        _inCall = true;
        _connectedAt ??= DateTime.now();
        _statusText = 'المكالمة متصلة';
      });
    }
  }

  void _setStatus(String value) {
    if (!mounted) return;
    setState(() => _statusText = value);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_connectedAt != null) {
        setState(() {});
      }
    });
  }

  void _startRinging({required bool incoming}) {
    if (_inCall) return;
    if (_ringTimer?.isActive == true) return;
    final interval = incoming
        ? const Duration(milliseconds: 1450)
        : const Duration(milliseconds: 1900);
    SystemSound.play(SystemSoundType.alert);
    _ringTimer = Timer.periodic(interval, (_) {
      if (_disposed || _inCall) return;
      SystemSound.play(SystemSoundType.alert);
      if (incoming) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }

  Future<void> _toggleMute() async {
    final local = _localStream;
    if (local == null) return;
    final next = !_muted;
    for (final track in local.getAudioTracks()) {
      track.enabled = !next;
    }
    if (mounted) {
      setState(() => _muted = next);
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    await Helper.setSpeakerphoneOn(next);
    if (mounted) {
      setState(() => _speakerOn = next);
    }
  }

  String _durationText() {
    if (_connectedAt == null) return '00:00';
    final d = DateTime.now().difference(_connectedAt!);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return int.tryParse('$value');
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    final t = '$value'.trim();
    return t.isEmpty ? null : t;
  }

  String _mapCallError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final message = '${data['message'] ?? ''}'.trim();
      switch (message) {
        case 'SOCIAL_CALL_PEER_NOT_AVAILABLE':
          return 'الطرف الآخر غير متاح حاليًا للاتصال';
        case 'SOCIAL_CALL_SESSION_NOT_FOUND':
          return 'جلسة الاتصال غير موجودة أو انتهت';
        case 'SOCIAL_CALL_FORBIDDEN':
          return 'لا تملك صلاحية الاتصال لهذا المستخدم';
      }
      if (message.isNotEmpty) return message;
    }
    return 'تعذر بدء المكالمة، تحقق من الشبكة ثم حاول مرة أخرى';
  }

  Color _statusColor() {
    if (_inCall) return const Color(0xFF63F0B0);
    if (_statusText.contains('الرنين') || _statusText.contains('واردة')) {
      return const Color(0xFFFFC766);
    }
    if (_statusText.contains('فشل') || _statusText.contains('تعذر')) {
      return const Color(0xFFFF7C8A);
    }
    return const Color(0xFF66D4FF);
  }

  @override
  Widget build(BuildContext context) {
    final incomingAwaitingAccept =
        !widget.isCaller && _pendingOfferPayload != null && !_acceptedIncoming;
    final statusColor = _statusColor();

    return Scaffold(
      appBar: AppBar(
        title: const Text('مكالمة شخصية'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _endCall(),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF102E4D), Color(0xFF081528)],
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  const SizedBox(height: 20),
                  TweenAnimationBuilder<double>(
                    duration: const Duration(milliseconds: 900),
                    tween: Tween<double>(begin: 0.96, end: _inCall ? 1 : 0.98),
                    curve: Curves.easeOutCubic,
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Container(
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: statusColor.withValues(alpha: 0.22),
                            blurRadius: 24,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: CircleAvatar(
                        radius: 52,
                        backgroundColor: Colors.white.withValues(alpha: 0.12),
                        child: const Icon(Icons.person_rounded, size: 56),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    widget.remoteDisplayName ?? 'الطرف الآخر',
                    style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: statusColor.withValues(alpha: 0.16),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.65),
                      ),
                    ),
                    child: Text(
                      _busy ? 'جاري التحميل...' : _statusText,
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                        color: statusColor,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _inCall ? _durationText() : '00:00',
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                  ),
                  const Spacer(),
                  if (incomingAwaitingAccept)
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.tonalIcon(
                            onPressed: _pendingIncomingAccept
                                ? null
                                : _declineIncoming,
                            icon: const Icon(Icons.call_end_rounded),
                            label: const Text('رفض'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _pendingIncomingAccept
                                ? null
                                : _acceptIncoming,
                            icon: const Icon(Icons.call_rounded),
                            label: const Text('رد'),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundActionButton(
                          icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                          label: _muted ? 'إلغاء الكتم' : 'كتم',
                          onTap: _toggleMute,
                        ),
                        _RoundActionButton(
                          icon: _speakerOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_disabled_rounded,
                          label: _speakerOn ? 'السماعة' : 'سماعة الأذن',
                          onTap: _toggleSpeaker,
                        ),
                        _RoundActionButton(
                          icon: Icons.call_end_rounded,
                          label: 'إنهاء',
                          color: Colors.redAccent,
                          onTap: _endCall,
                        ),
                      ],
                    ),
                  const SizedBox(height: 18),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  final VoidCallback onTap;

  const _RoundActionButton({
    required this.icon,
    required this.label,
    this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fill = color ?? Colors.blueAccent;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(100),
          child: Container(
            width: 62,
            height: 62,
            decoration: BoxDecoration(
              color: fill.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: fill),
          ),
        ),
        const SizedBox(height: 6),
        Text(label),
      ],
    );
  }
}
