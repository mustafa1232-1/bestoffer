import 'dart:async';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/notifications/data/notifications_api.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/calls/rtc_call_support.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/notifications/attention_alert_service.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import '../../../l10n/app_localizations.dart';

/// Purpose: شاشة المكالمات الصوتية لمحادثات السوشال باستخدام WebRTC مع قناتين:
/// API للحالة الأساسية وSSE للإشارات الفورية.
/// Used by: `social_chat_thread_screen.dart` ومسارات incoming/outgoing call المرتبطة بالمحادثات.
/// Depends on: `SocialApi`, `NotificationsApi.streamEvents`, `rtc_call_support.dart`, و`attention_alert_service.dart`.
/// Critical notes: هذا الملف حساس تشغيلياً؛ أي تعديل في ترتيب الإشارات أو reconnect قد يسبب مكالمات عالقة أو صوتاً صامتاً.
/// Maintenance notes: عند تعطل المكالمات افحص بالتسلسل صلاحية المايكروفون، `getThreadCallState`, stream channel `social`, ثم ICE recovery.
final socialCallApiProvider = Provider<SocialApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return SocialApi(dio);
});

final socialCallLiveApiProvider = Provider<NotificationsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return NotificationsApi(
    dio,
    realtime: ref.read(maslakiRealtimeServiceProvider),
  );
});

/// واجهة المكالمة الفعلية بين طرفي thread اجتماعي.
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

/// استثناء داخلي يميز فشل إذن الميكروفون عن بقية أخطاء الاتصال.
class _MicPermissionDenied implements Exception {
  const _MicPermissionDenied();
}

enum _SocialCallStatusTone { info, warning, error, success }

/// حالة الشاشة التي تدير دورة حياة WebRTC كاملة:
/// إنشاء الجلسة، استقبال/إرسال الإشارات، وإعادة الاتصال عند تقطع الشبكة.
class _SocialCallScreenState extends ConsumerState<SocialCallScreen> {
  SocialApi get _api => ref.read(socialCallApiProvider);
  NotificationsApi get _liveApi => ref.read(socialCallLiveApiProvider);
  AttentionAlertService get _alertService =>
      ref.read(attentionAlertServiceProvider);

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<NotificationLiveEvent>? _streamSub;
  Timer? _ticker;
  Timer? _reconnectTimer;
  Timer? _ringTimer;
  Timer? _iceRecoverTimer;
  Timer? _stateSyncTimer;

  final Set<int> _handledSignalIds = <int>{};
  final Set<String> _boundRemoteTrackIds = <String>{};
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
  bool _stateSyncInFlight = false;
  int _reconnectAttempt = 0;
  int? _lastEventId;
  String? _statusText;
  _SocialCallStatusTone _statusTone = _SocialCallStatusTone.info;
  DateTime? _connectedAt;
  Map<String, dynamic>? _pendingOfferPayload;

  AppLocalizations get _l10n => context.l10n;

  /// يبدأ bootstrap الكامل للمكالمة.
  ///
  /// الترتيب مقصود: تهيئة RTC أولاً، ثم stream الإشارات، ثم state snapshot،
  /// وبعدها فقط يبدأ caller بإنشاء offer إذا لم تكن session موجودة مسبقاً.
  @override
  void initState() {
    super.initState();
    _sessionId = widget.initialSessionId;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed || !mounted) return;
      unawaited(_bootstrap());
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _statusText ??= _l10n.socialCallInitializing;
  }

  /// ينظف timers والـ subscriptions وموارد WebRTC لتفادي microphone leaks أو ghost calls.
  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    _streamSub?.cancel();
    _reconnectTimer?.cancel();
    _ringTimer?.cancel();
    _iceRecoverTimer?.cancel();
    _stateSyncTimer?.cancel();
    unawaited(_disposeRtc());
    super.dispose();
  }

  /// يهيئ الاتصال من الصفر ويربط الواجهة بحالة الجلسة الحالية.
  Future<void> _bootstrap() async {
    if (!widget.isCaller) {
      _startRinging(incoming: true);
      _setStatus(_l10n.socialCallIncoming, tone: _SocialCallStatusTone.warning);
    }
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
        _setStatus(
          _l10n.socialCallDialingPeer,
          tone: _SocialCallStatusTone.info,
        );
      }

      _startTicker();
      _startStateSync();
    } on _MicPermissionDenied {
      _setStatus(
        _l10n.socialCallMicrophonePermissionRequired,
        tone: _SocialCallStatusTone.error,
      );
    } on DioException catch (e) {
      _setStatus(_mapCallError(e), tone: _SocialCallStatusTone.error);
    } catch (_) {
      _setStatus(_l10n.socialCallStartFailed, tone: _SocialCallStatusTone.error);
    } finally {
      if (!_disposed && mounted) {
        setState(() => _busy = false);
      }
    }
  }

  /// يجهز PeerConnection، الميكروفون المحلي، وcallbacks الخاصة بالمسارات الصوتية وICE.
  ///
  /// إذا ظهرت مكالمة بدون صوت أو بدون remote track فابدأ التشخيص من هذا الجزء
  /// ثم تابع إلى `_consumeSignal` و`_bindRemoteTrack`.
  Future<void> _prepareRtc() async {
    await _ensureMicrophonePermission();
    if (WebRTC.platformIsAndroid) {
      await Helper.setAndroidAudioConfiguration(
        AndroidAudioConfiguration.communication,
      );
    }
    if (WebRTC.platformIsIOS) {
      try {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: _speakerOn,
        );
      } catch (_) {}
    }
    _pc = await createPeerConnection(await resolveRtcCallConfig(_api.dio));

    _pc!.onTrack = (event) {
      _bindRemoteTrack(event.track);
      for (final stream in event.streams) {
        _bindRemoteStream(stream);
      }
    };

    _pc!.onAddTrack = (stream, track) {
      _bindRemoteStream(stream);
      _bindRemoteTrack(track);
    };

    _pc!.onAddStream = _bindRemoteStream;

    _pc!.onConnectionState = (state) {
      if (!mounted || _disposed) return;

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _onConnected();
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        _setStatus(
          _l10n.socialCallConnectionInterrupted,
          tone: _SocialCallStatusTone.warning,
        );
        _scheduleIceRecover();
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _setStatus(
          _l10n.socialCallReconnectRetrying,
          tone: _SocialCallStatusTone.error,
        );
        _scheduleIceRecover(force: true);
        return;
      }

      if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        _stopRinging();
        _setStatus(_l10n.socialCallEnded, tone: _SocialCallStatusTone.info);
      }
    };

    _pc!.onIceConnectionState = (state) {
      if (!mounted || _disposed) return;
      if (state == RTCIceConnectionState.RTCIceConnectionStateConnected ||
          state == RTCIceConnectionState.RTCIceConnectionStateCompleted) {
        _onConnected();
      } else if (state == RTCIceConnectionState.RTCIceConnectionStateFailed) {
        _scheduleIceRecover(force: true);
      } else if (state ==
          RTCIceConnectionState.RTCIceConnectionStateDisconnected) {
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

    _localStream = await navigator.mediaDevices.getUserMedia(
      buildHighQualityAudioConstraints(),
    );

    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    await _applyAudioRoute();
  }

  /// يتحقق من إذن المايكروفون على Android/iOS ويفتح إعدادات النظام عند الرفض الدائم.
  Future<void> _ensureMicrophonePermission() async {
    if (!(WebRTC.platformIsAndroid || WebRTC.platformIsIOS)) return;
    var status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
    }
    if (!status.isGranted) {
      if (status.isPermanentlyDenied || status.isRestricted) {
        await openAppSettings();
      }
      throw const _MicPermissionDenied();
    }
  }

  /// يشترك في stream الإشعارات الحية لقناة `social` ويحوّل أحداثها إلى تحديثات call session.
  ///
  /// الـ SSE هنا هو المصدر الأسرع، بينما `getThreadCallState` يمثل fallback/resync path.
  Future<void> _connectSignalStream() async {
    _streamSub?.cancel();
    _reconnectTimer?.cancel();
    _streamSub = _liveApi
        .streamEvents(lastEventId: _lastEventId, channel: 'social')
        .listen(
          (event) {
            if (event.event == 'connected' || event.event == 'replayed') {
              _reconnectAttempt = 0;
              return;
            }

            if (event.event == 'resync_required') {
              _lastEventId = _asInt(event.data['latestEventId']);
              unawaited(_loadCallState());
              return;
            }

            if (event.event != 'social_call_update') return;
            if (!_acceptRealtimeEventId(event.eventId)) return;
            final threadId = _asInt(
              event.data['threadId'] ?? event.data['thread_id'],
            );
            if (threadId != widget.threadId) return;
            unawaited(_handleCallUpdateEvent(event.data));
          },
          onError: (_) {
            _setStatus(
              _l10n.socialCallConnectionInterrupted,
              tone: _SocialCallStatusTone.warning,
            );
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

  /// يسحب snapshot الخادم الحالي للجلسة والإشارات المعلقة لاستعادة التزامن بعد reconnect.
  Future<void> _loadCallState() async {
    final state = await _api.getThreadCallState(threadId: widget.threadId);
    final session = state['session'];
    if (session is Map) {
      _sessionId = _asInt(session['id']) ?? _sessionId;
      final status = _asString(session['status']) ?? '';
      if (status == 'active') {
        _onConnected();
      } else if (status == 'ringing') {
        _startRinging(incoming: !widget.isCaller);
        _setStatus(
          widget.isCaller ? _l10n.socialCallRinging : _l10n.socialCallIncoming,
          tone: _SocialCallStatusTone.warning,
        );
      } else if (status == 'missed') {
        _setStatus(
          _l10n.socialCallMissedTimeout,
          tone: _SocialCallStatusTone.error,
        );
        await _remoteEndCall();
        return;
      } else if (status == 'declined') {
        _setStatus(_l10n.socialCallDeclined, tone: _SocialCallStatusTone.error);
        await _remoteEndCall();
        return;
      } else if (status == 'ended') {
        _setStatus(_l10n.socialCallEnded, tone: _SocialCallStatusTone.info);
        await _remoteEndCall();
        return;
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

  /// ينشئ offer محسن للصوت ويرسله للطرف الآخر مع دعم ICE restart عند الحاجة.
  Future<void> _createAndSendOffer({bool iceRestart = false}) async {
    if (_pc == null) return;
    final offer = optimizeVoiceDescription(
      await _pc!.createOffer({
        'offerToReceiveAudio': true,
        if (iceRestart) 'iceRestart': true,
      }),
    );
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

  /// يغلف إرسال signal إلى الخادم مع تحديث sessionId إذا أعادته الاستجابة.
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

  /// يفسر event الحي القادم من الخادم ويحوّله إلى إجراءات محلية على الجلسة.
  Future<void> _handleCallUpdateEvent(Map<String, dynamic> data) async {
    final session = data['session'];
    if (session is Map) {
      _sessionId = _asInt(session['id']) ?? _sessionId;
    }

    final eventType = _asString(data['eventType']) ?? '';
    if (eventType == 'incoming_call') {
      _startRinging(incoming: true);
      _setStatus(_l10n.socialCallIncoming, tone: _SocialCallStatusTone.warning);
    }
    if (eventType == 'outgoing_call') {
      _startRinging(incoming: false);
      _setStatus(_l10n.socialCallRinging, tone: _SocialCallStatusTone.warning);
    }
    if (eventType == 'call_missed') {
      _setStatus(
        _l10n.socialCallMissedTimeout,
        tone: _SocialCallStatusTone.error,
      );
      await _remoteEndCall();
      return;
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

  /// يستهلك signal واحداً مع dedupe حسب signal id وترتيب آمن بين offer/answer/ice.
  ///
  /// إذا وصلت ICE قبل تثبيت remote description تُحفظ في queue ثم تُفرغ لاحقاً،
  /// وهذه النقطة هي أول ما يجب مراجعته عند ظهور `setRemoteDescription` races.
  Future<void> _consumeSignal(Map<String, dynamic> signal) async {
    final signalId = _asInt(signal['id']);
    if (signalId != null && _handledSignalIds.contains(signalId)) return;
    if (signalId != null) _handledSignalIds.add(signalId);

    final type = _asString(signal['signalType'] ?? signal['signal_type']);
    final senderUserId = _asInt(
      signal['senderUserId'] ?? signal['sender_user_id'],
    );
    if (senderUserId != null && senderUserId == _currentUserId()) {
      return;
    }
    final payload = signal['signalPayload'] is Map
        ? Map<String, dynamic>.from(signal['signalPayload'] as Map)
        : (signal['signal_payload'] is Map
              ? Map<String, dynamic>.from(signal['signal_payload'] as Map)
              : <String, dynamic>{});

    if (type == 'ringing') {
      _startRinging(incoming: !widget.isCaller);
      _setStatus(
        widget.isCaller ? _l10n.socialCallRinging : _l10n.socialCallIncoming,
        tone: _SocialCallStatusTone.warning,
      );
      return;
    }

    if (type == 'offer') {
      if (!widget.isCaller && !_acceptedIncoming) {
        _pendingOfferPayload = payload;
        _pendingIncomingAccept = false;
        _startRinging(incoming: true);
        _setStatus(
          _l10n.socialCallIncoming,
          tone: _SocialCallStatusTone.warning,
        );
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
      _setStatus(
        _l10n.socialCallAnsweredConnectingAudio,
        tone: _SocialCallStatusTone.info,
      );
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
    await _syncRemoteReceivers();

    final answer = optimizeVoiceDescription(
      await _pc!.createAnswer({'offerToReceiveAudio': true}),
    );
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
    await _syncRemoteReceivers();
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
      _setStatus(_l10n.socialCallRecovering, tone: _SocialCallStatusTone.info);
      await _createAndSendOffer(iceRestart: true);
    } catch (_) {
      _setStatus(
        _l10n.socialCallRecoverFailed,
        tone: _SocialCallStatusTone.error,
      );
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
      await _applyAudioRoute();
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
    _setStatus(_l10n.socialCallEnded, tone: _SocialCallStatusTone.info);
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
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    _remoteDescriptionSet = false;
    _boundRemoteTrackIds.clear();
    _queuedRemoteCandidates.clear();
    if (WebRTC.platformIsAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }
  }

  void _onConnected() {
    _stopRinging();
    unawaited(_applyAudioRoute());
    if (mounted) {
      setState(() {
        _inCall = true;
        _connectedAt ??= DateTime.now();
        _statusText = _l10n.socialCallConnected;
        _statusTone = _SocialCallStatusTone.success;
      });
    }
  }

  void _setStatus(
    String value, {
    _SocialCallStatusTone tone = _SocialCallStatusTone.info,
  }) {
    if (!mounted) return;
    setState(() {
      _statusText = value;
      _statusTone = tone;
    });
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

  void _startStateSync() {
    _stateSyncTimer?.cancel();
    _stateSyncTimer = Timer.periodic(const Duration(seconds: 2), (_) {
      if (!mounted || _disposed || _callEnded || _stateSyncInFlight) return;
      _stateSyncInFlight = true;
      _loadCallState().catchError((_) {}).whenComplete(() {
        _stateSyncInFlight = false;
      });
    });
  }

  void _startRinging({required bool incoming}) {
    if (_inCall) return;
    if (_ringTimer?.isActive == true) return;
    final interval = incoming
        ? const Duration(milliseconds: 1450)
        : const Duration(milliseconds: 1900);
    unawaited(_alertService.play());
    SystemSound.play(SystemSoundType.alert);
    _ringTimer = Timer.periodic(interval, (_) {
      if (_disposed || _inCall) return;
      unawaited(_alertService.play());
      SystemSound.play(SystemSoundType.alert);
      if (incoming) {
        HapticFeedback.mediumImpact();
      }
    });
  }

  void _stopRinging() {
    _ringTimer?.cancel();
    _ringTimer = null;
    unawaited(_alertService.stop());
  }

  Future<void> _toggleMute() async {
    final local = _localStream;
    if (local == null) return;
    final next = !_muted;
    for (final track in local.getAudioTracks()) {
      track.enabled = !next;
      unawaited(Helper.setMicrophoneMute(next, track).catchError((_) {}));
    }
    if (mounted) {
      setState(() => _muted = next);
    }
  }

  Future<void> _toggleSpeaker() async {
    final next = !_speakerOn;
    _speakerOn = next;
    await _applyAudioRoute();
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _applyAudioRoute() async {
    final local = _localStream;
    if (local != null) {
      for (final track in local.getAudioTracks()) {
        track.enabled = !_muted;
        unawaited(Helper.setMicrophoneMute(_muted, track).catchError((_) {}));
      }
    }

    if (WebRTC.platformIsIOS) {
      try {
        await Helper.setAppleAudioIOMode(
          AppleAudioIOMode.localAndRemote,
          preferSpeakerOutput: _speakerOn,
        );
      } catch (_) {}
    }
    try {
      if (_speakerOn) {
        await Helper.setSpeakerphoneOnButPreferBluetooth();
      } else {
        await Helper.setSpeakerphoneOn(false);
      }
    } catch (_) {}

    final remote = _remoteStream;
    if (remote != null) {
      for (final track in remote.getAudioTracks()) {
        track.enabled = true;
        unawaited(Helper.setVolume(1.0, track).catchError((_) {}));
      }
    }
  }

  void _bindRemoteStream(MediaStream stream) {
    _remoteStream = stream;
    for (final track in stream.getAudioTracks()) {
      _bindRemoteTrack(track);
    }
  }

  void _bindRemoteTrack(MediaStreamTrack? track) {
    if (track == null || track.kind != 'audio') return;
    final normalizedTrackId = track.id?.trim() ?? '';
    final trackId = normalizedTrackId.isEmpty
        ? 'audio:${track.hashCode}'
        : normalizedTrackId;
    if (!_boundRemoteTrackIds.add(trackId)) return;
    track.enabled = true;
    unawaited(_applyAudioRoute());
    unawaited(Helper.setVolume(1.0, track).catchError((_) {}));
  }

  Future<void> _syncRemoteReceivers() async {
    final pc = _pc;
    if (pc == null) return;
    try {
      final receivers = await pc.getReceivers();
      for (final receiver in receivers) {
        _bindRemoteTrack(receiver.track);
      }
    } catch (_) {}
  }

  String _durationText() {
    if (_connectedAt == null) return '00:00';
    final d = DateTime.now().difference(_connectedAt!);
    final mm = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final ss = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  int? _currentUserId() {
    final auth = ref.read(authControllerProvider);
    return auth.user?.id;
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
          return _l10n.socialCallPeerUnavailable;
        case 'SOCIAL_CALL_SESSION_NOT_FOUND':
          return _l10n.socialCallSessionNotFound;
        case 'SOCIAL_CALL_FORBIDDEN':
          return _l10n.socialCallForbidden;
      }
    }
    return _l10n.socialCallGenericError;
  }

  Color _statusColor() {
    switch (_statusTone) {
      case _SocialCallStatusTone.success:
        return const Color(0xFF63F0B0);
      case _SocialCallStatusTone.warning:
        return const Color(0xFFFFC766);
      case _SocialCallStatusTone.error:
        return const Color(0xFFFF7C8A);
      case _SocialCallStatusTone.info:
        return const Color(0xFF66D4FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = _l10n;
    final incomingAwaitingAccept =
        !widget.isCaller && _pendingOfferPayload != null && !_acceptedIncoming;
    final statusColor = _statusColor();
    final headline = incomingAwaitingAccept
        ? l10n.socialCallIncomingHeadline(
            widget.remoteDisplayName ?? l10n.socialCallParticipantFallback,
          )
        : (widget.remoteDisplayName ?? l10n.socialCallOtherParticipant);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.socialCallTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _endCall(),
        ),
      ),
      body: Directionality(
        textDirection: Directionality.of(context),
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
                    headline,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: statusColor.withValues(alpha: 0.16),
                      border: Border.all(
                        color: statusColor.withValues(alpha: 0.65),
                      ),
                    ),
                    child: Text(
                      _busy ? l10n.commonLoading : (_statusText ?? l10n.socialCallInitializing),
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
                    style: const TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
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
                            label: Text(l10n.socialCallDecline),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _pendingIncomingAccept
                                ? null
                                : _acceptIncoming,
                            icon: const Icon(Icons.call_rounded),
                            label: Text(l10n.socialCallAnswer),
                          ),
                        ),
                      ],
                    )
                  else
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _RoundActionButton(
                          icon: _muted
                              ? Icons.mic_off_rounded
                              : Icons.mic_rounded,
                          label: _muted
                              ? l10n.socialCallUnmute
                              : l10n.socialCallMute,
                          onTap: _toggleMute,
                        ),
                        _RoundActionButton(
                          icon: _speakerOn
                              ? Icons.volume_up_rounded
                              : Icons.hearing_disabled_rounded,
                          label: _speakerOn
                              ? l10n.socialCallSpeaker
                              : l10n.socialCallEarpiece,
                          onTap: _toggleSpeaker,
                        ),
                        _RoundActionButton(
                          icon: Icons.call_end_rounded,
                          label: l10n.socialCallHangup,
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
