import 'dart:async';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/notifications/data/notifications_api.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/calls/call_tone_service.dart';
import '../../../core/calls/rtc_call_support.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/notifications/local_notification_service.dart';
import '../../../core/realtime/maslaki_realtime_service.dart';
import '../../../l10n/app_localizations.dart';
import '../state/social_call_voice_controller.dart';

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
final socialCallVoiceFactoryProvider =
    Provider<SocialCallVoiceController Function()>(
      (ref) => SocialCallVoiceController.new,
    );

class SocialCallScreen extends ConsumerStatefulWidget {
  final int threadId;
  final bool isCaller;
  final int? initialSessionId;
  final String? remoteDisplayName;
  final String? initialAction;
  final int? notificationId;

  const SocialCallScreen({
    super.key,
    required this.threadId,
    required this.isCaller,
    this.initialSessionId,
    this.remoteDisplayName,
    this.initialAction,
    this.notificationId,
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
class _SocialCallScreenState extends ConsumerState<SocialCallScreen>
    with WidgetsBindingObserver {
  SocialApi get _api => ref.read(socialCallApiProvider);
  NotificationsApi get _liveApi => ref.read(socialCallLiveApiProvider);
  late final CallToneService _callToneService;
  late final LocalNotificationService _localNotifications;

  RTCPeerConnection? _pc;
  late final SocialCallVoiceController _voice;
  final RTCVideoRenderer _remoteAudio = RTCVideoRenderer();
  bool _remoteAudioReady = false;
  String _voiceTransport = 'webrtc';
  bool _voiceConnecting = false;
  MediaStream? _localStream;
  MediaStream? _remoteStream;
  StreamSubscription<NotificationLiveEvent>? _streamSub;
  Timer? _ticker;
  Timer? _reconnectTimer;
  Timer? _iceRecoverTimer;
  Timer? _stateSyncTimer;
  Timer? _legacyOfferTimer;
  Timer? _voiceReconnectTimer;
  Future<void>? _rtcWork;
  bool _peerSupportsLiveKit = false;
  bool _announcedLiveKit = false;
  bool _legacyOfferSent = false;
  bool _microphonePermissionDenied = false;
  String? _sessionStatus;

  final Set<int> _handledSignalIds = <int>{};
  final Map<String, MediaStreamTrack> _boundRemoteAudioTracks =
      <String, MediaStreamTrack>{};
  final List<RTCIceCandidate> _queuedRemoteCandidates = <RTCIceCandidate>[];

  int? _sessionId;
  late bool _isCaller;
  bool _busy = true;
  bool _inCall = false;
  bool _muted = false;
  bool _speakerOn = false;
  bool _pendingIncomingAccept = false;
  bool _acceptedIncoming = false;
  bool _initialActionHandled = false;
  bool _callNotificationCancelled = false;
  bool _disposed = false;
  bool _remoteDescriptionSet = false;
  bool _callEnded = false;
  bool _stateSyncInFlight = false;
  Future<void>? _stateWork;
  int _reconnectAttempt = 0;
  int _voiceReconnectAttempt = 0;
  int? _lastEventId;
  String? _statusText;
  _SocialCallStatusTone _statusTone = _SocialCallStatusTone.info;
  DateTime? _connectedAt;
  Map<String, dynamic>? _pendingOfferPayload;

  AppLocalizations get _l10n => context.l10n;

  /// يبدأ bootstrap الكامل للمكالمة.
  ///
  /// تُقرأ الجلسة ويُحدد مسار الصوت قبل فتح الميكروفون.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _callToneService = ref.read(callToneServiceProvider);
    _localNotifications = ref.read(localNotificationsProvider);
    _voice = ref.read(socialCallVoiceFactoryProvider)();
    _voice.addListener(_onVoiceChanged);
    _sessionId = widget.initialSessionId;
    _isCaller = widget.isCaller;
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
    WidgetsBinding.instance.removeObserver(this);
    _voice.removeListener(_onVoiceChanged);
    _voice.dispose();
    if (_remoteAudioReady) unawaited(_remoteAudio.dispose());
    _ticker?.cancel();
    _streamSub?.cancel();
    _reconnectTimer?.cancel();
    _iceRecoverTimer?.cancel();
    _stateSyncTimer?.cancel();
    _legacyOfferTimer?.cancel();
    _voiceReconnectTimer?.cancel();
    unawaited(_disposeRtc());
    super.dispose();
  }

  /// يهيئ الاتصال من الصفر ويربط الواجهة بحالة الجلسة الحالية.
  Future<void> _bootstrap() async {
    final api = _api;
    if (_isCaller) {
      // Give immediate feedback while the start-call request is in flight.
      _startRinging(incoming: false);
      _setStatus(_l10n.socialCallRinging, tone: _SocialCallStatusTone.warning);
    } else {
      _startRinging(incoming: true);
      _setStatus(_l10n.socialCallIncoming, tone: _SocialCallStatusTone.warning);
    }
    try {
      await _connectSignalStream();
      _startTicker();
      _startStateSync();
      await _loadCallState();
      if (_disposed || _callEnded) return;
      await _applyInitialNotificationAction();
      if (_disposed || _callEnded) return;

      if (_isCaller && _sessionId == null) {
        final out = await _api.startThreadCall(
          threadId: widget.threadId,
          preferLiveKit: true,
        );
        final session = out['session'];
        if (session is Map) {
          _sessionId = _asInt(session['id']);
          _readSession(session);
        }
        if (_disposed || _callEnded) {
          if (_sessionId != null) {
            await api.sendThreadCallSignal(
              threadId: widget.threadId,
              sessionId: _sessionId,
              signalType: 'hangup',
            );
          }
          return;
        }
        if (!_acceptedIncoming) {
          _startRinging(incoming: false);
          _setStatus(_l10n.socialCallRinging);
        }
      }

      _scheduleLegacyOffer();
    } on _MicPermissionDenied {
      _stopRinging();
      _microphonePermissionDenied = true;
      _setStatus(
        _l10n.socialCallMicrophonePermissionRequired,
        tone: _SocialCallStatusTone.error,
      );
    } on DioException catch (e) {
      _stopRinging();
      _setStatus(_mapCallError(e), tone: _SocialCallStatusTone.error);
    } catch (_) {
      _stopRinging();
      _setStatus(
        _l10n.socialCallStartFailed,
        tone: _SocialCallStatusTone.error,
      );
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
  Future<void> _prepareRtc() => _rtcWork ??= _initializeRtc()
      .catchError((Object error, StackTrace stack) async {
        await _disposeLegacyMedia();
        Error.throwWithStackTrace(error, stack);
      })
      .whenComplete(() => _rtcWork = null);

  bool get _legacyMediaAllowed =>
      !_disposed &&
      !_callEnded &&
      _voiceTransport != 'livekit' &&
      !(_voiceTransport == 'auto' && _peerSupportsLiveKit);

  Future<void> _initializeRtc() async {
    if (!_legacyMediaAllowed || _pc != null) return;
    await _ensureMicrophonePermission();
    if (!_legacyMediaAllowed) return;
    if (!_remoteAudioReady) await _remoteAudio.initialize();
    if (!_legacyMediaAllowed) {
      await _remoteAudio.dispose();
      _remoteAudioReady = false;
      return;
    }
    _remoteAudioReady = true;
    // Initialize the native WebRTC audio module before configuring routing or
    // creating the peer connection. Idempotent (guarded internally).
    try {
      await WebRTC.initialize();
    } catch (_) {}
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
    final config = await resolveRtcCallConfig(_api.dio).timeout(
      const Duration(seconds: 4),
      onTimeout: () => buildRtcCallConfig(),
    );
    if (!_legacyMediaAllowed) return;
    final pc = await createPeerConnection(config);
    if (!_legacyMediaAllowed) {
      await pc.close();
      return;
    }
    _pc = pc;

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
      if (!mounted || _disposed || _callEnded || _voiceTransport == 'livekit') {
        return;
      }

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
      if (!mounted || _disposed || _callEnded || _voiceTransport == 'livekit') {
        return;
      }
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

    final local = await navigator.mediaDevices.getUserMedia(
      buildHighQualityAudioConstraints(),
    );
    if (!_legacyMediaAllowed || !identical(_pc, pc)) {
      for (final track in local.getTracks()) {
        await track.stop();
      }
      await local.dispose();
      return;
    }
    _localStream = local;

    for (final track in _localStream!.getAudioTracks()) {
      await pc.addTrack(track, local);
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
              unawaited(_loadCallState().catchError((_) {}));
              return;
            }

            if (event.event != 'social_call_update') return;
            if (!_acceptRealtimeEventId(event.eventId)) return;
            final threadId = _asInt(
              event.data['threadId'] ?? event.data['thread_id'],
            );
            if (threadId != widget.threadId) return;
            unawaited(
              _handleCallUpdateEvent(event.data).catchError((_) {
                _setStatus(
                  _l10n.socialCallRecoverFailed,
                  tone: _SocialCallStatusTone.error,
                );
              }),
            );
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
  Future<void> _loadCallState() =>
      _stateWork ??= _fetchCallState().whenComplete(() => _stateWork = null);

  // Transport selection is one-way for a session. Late ringing/ICE responses
  // must not undo LiveKit negotiation after the peer has accepted.
  void _readSession(Map session) {
    if (session['isCaller'] is bool) _isCaller = session['isCaller'] as bool;
    if (_voiceTransport != 'livekit') {
      _voiceTransport = '${session['voiceTransport'] ?? _voiceTransport}';
    }
    final status = _asString(session['status']);
    // Start/snapshot responses can arrive after the acceptance event.
    if (status != 'ringing' || _sessionStatus != 'active') {
      _sessionStatus = status ?? _sessionStatus;
    }
    if (_sessionStatus == 'active') _acceptedIncoming = true;
  }

  Future<void> _announceLiveKit() async {
    if (_isCaller ||
        _announcedLiveKit ||
        _voiceTransport != 'auto' ||
        _sessionStatus != 'ringing' ||
        _callEnded) {
      return;
    }
    _announcedLiveKit = true;
    try {
      // Capability acknowledgement only: never accepts or captures audio.
      await _sendSignal(
        signalType: 'ringing',
        signalPayload: {'transport': 'livekit'},
      );
    } catch (_) {
      _announcedLiveKit = false;
    }
  }

  void _scheduleLegacyOffer() {
    if (!_isCaller ||
        !_legacyMediaAllowed ||
        _legacyOfferSent ||
        _sessionId == null ||
        _legacyOfferTimer?.isActive == true) {
      return;
    }
    // Older clients require SDP before showing Answer. Allow current clients
    // to announce LiveKit first, without making either call setup depend on SDP.
    _legacyOfferTimer = Timer(
      _voiceTransport == 'auto' ? const Duration(seconds: 5) : Duration.zero,
      () => unawaited(_startLegacyOffer()),
    );
  }

  Future<void> _startLegacyOffer() async {
    if (!_legacyMediaAllowed || _legacyOfferSent) return;
    try {
      await _prepareRtc();
      if (!_legacyMediaAllowed) return;
      await _createAndSendOffer();
      _legacyOfferSent = true;
    } catch (_) {
      // LiveKit-capable recipients can still answer an auto session.
      if (_legacyMediaAllowed && _voiceTransport == 'webrtc') {
        _setStatus(
          _l10n.socialCallStartFailed,
          tone: _SocialCallStatusTone.error,
        );
      }
    }
  }

  Future<void> _fetchCallState() async {
    final requestedSessionId = _sessionId;
    final state = await _api.getThreadCallState(threadId: widget.threadId);
    if (_disposed || !mounted || _callEnded) return;
    final session = state['session'];
    if (session == null &&
        requestedSessionId != null &&
        _sessionId == requestedSessionId) {
      await _remoteEndCall();
      return;
    }
    if (session is Map) {
      if (_sessionId != null && _asInt(session['id']) != _sessionId) return;
      _sessionId = _asInt(session['id']) ?? _sessionId;
      _readSession(session);
      final status = _sessionStatus;
      if (status == 'active') {
        if (_voiceTransport == 'livekit') await _connectLiveKit();
      } else if (status == 'ringing') {
        unawaited(_announceLiveKit());
        _scheduleLegacyOffer();
        _startRinging(incoming: !_isCaller);
        _setStatus(
          _isCaller ? _l10n.socialCallRinging : _l10n.socialCallIncoming,
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
    if (_pc == null || !_legacyMediaAllowed) return;
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
    if (_voiceTransport == 'livekit' &&
        ['offer', 'answer', 'ice'].contains(signalType)) {
      return;
    }
    final out = await _api.sendThreadCallSignal(
      threadId: widget.threadId,
      sessionId: _sessionId,
      signalType: signalType,
      signalPayload: signalPayload,
    );
    final session = out['session'];
    if (session is Map) {
      _sessionId = _asInt(session['id']) ?? _sessionId;
      _readSession(session);
    }
  }

  /// يفسر event الحي القادم من الخادم ويحوّله إلى إجراءات محلية على الجلسة.
  Future<void> _handleCallUpdateEvent(Map<String, dynamic> data) async {
    if (_disposed || _callEnded) return;
    final session = data['session'];
    if (session is Map) {
      if (_sessionId != null && _asInt(session['id']) != _sessionId) return;
      _sessionId = _asInt(session['id']) ?? _sessionId;
      _readSession(session);
      if (_sessionStatus == 'active' && _voiceTransport == 'livekit') {
        await _connectLiveKit();
      }
    }

    final eventType = _asString(data['eventType']) ?? '';
    if (eventType == 'incoming_call' && _sessionStatus == 'ringing') {
      unawaited(_announceLiveKit());
      _startRinging(incoming: true);
      _setStatus(_l10n.socialCallIncoming, tone: _SocialCallStatusTone.warning);
    }
    if (eventType == 'outgoing_call' && _sessionStatus == 'ringing') {
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
    if (_disposed || _callEnded) return;
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

    if (_voiceTransport == 'livekit' &&
        ['ringing', 'accept', 'offer', 'answer', 'ice'].contains(type)) {
      return;
    }

    if (type == 'ringing') {
      if (_isCaller &&
          payload['transport'] == 'livekit' &&
          _voiceTransport == 'auto') {
        _peerSupportsLiveKit = true;
        _legacyOfferTimer?.cancel();
      }
      if (_sessionStatus == 'active' || _acceptedIncoming) return;
      _startRinging(incoming: !_isCaller);
      _setStatus(
        _isCaller ? _l10n.socialCallRinging : _l10n.socialCallIncoming,
        tone: _SocialCallStatusTone.warning,
      );
      return;
    }

    if (type == 'offer') {
      if (!_isCaller && !_acceptedIncoming) {
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
      if (_isCaller) _scheduleLegacyOffer();
      return;
    }

    if (type == 'hangup' || type == 'decline') {
      await _remoteEndCall();
      return;
    }
  }

  Future<void> _handleOffer(Map<String, dynamic> payload) async {
    await _prepareRtc();
    if (_pc == null || !_legacyMediaAllowed) return;
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

    // SDP acceptance does not mean ICE/audio connected. Connection callbacks
    // are authoritative for the connected indicator and duration.
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    await _prepareRtc();
    if (_pc == null || !_legacyMediaAllowed) return;
    final sdp = _asString(payload['sdp']);
    final type = _asString(payload['type']) ?? 'answer';
    if (sdp == null || sdp.isEmpty) return;

    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    await _flushQueuedCandidates();
    await _syncRemoteReceivers();
  }

  Future<void> _handleIce(Map<String, dynamic> payload) async {
    final candidateText = _asString(payload['candidate']);
    if (candidateText == null || candidateText.isEmpty) return;
    final candidate = RTCIceCandidate(
      candidateText,
      _asString(payload['sdpMid']),
      _asInt(payload['sdpMLineIndex']),
    );

    if (_pc == null || !_remoteDescriptionSet) {
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
    if (!_isCaller) return;
    try {
      _setStatus(_l10n.socialCallRecovering, tone: _SocialCallStatusTone.info);
      await _createAndSendOffer(iceRestart: true);
    } on _MicPermissionDenied {
      _microphonePermissionDenied = true;
      _setStatus(
        _l10n.socialCallMicrophonePermissionRequired,
        tone: _SocialCallStatusTone.error,
      );
    } catch (_) {
      _setStatus(
        _l10n.socialCallRecoverFailed,
        tone: _SocialCallStatusTone.error,
      );
    }
  }

  Future<void> _acceptIncoming() async {
    if (_sessionId == null ||
        _acceptedIncoming ||
        _pendingIncomingAccept ||
        _callEnded) {
      return;
    }
    setState(() => _pendingIncomingAccept = true);
    try {
      if (_voiceTransport == 'webrtc') await _ensureMicrophonePermission();
      if (_disposed || _callEnded) return;
      await _sendSignal(
        signalType: 'accept',
        signalPayload: {if (_voiceTransport == 'auto') 'transport': 'livekit'},
      );
      if (_disposed || _callEnded) return;
      _acceptedIncoming = true;
      _stopRinging();
      final pending = _pendingOfferPayload;
      _pendingOfferPayload = null;
      if (_voiceTransport == 'livekit') {
        await _connectLiveKit();
      } else if (pending != null) {
        await _handleOffer(pending);
      }
      await _applyAudioRoute();
    } on _MicPermissionDenied {
      _microphonePermissionDenied = true;
      _setStatus(
        _l10n.socialCallMicrophonePermissionRequired,
        tone: _SocialCallStatusTone.error,
      );
    } catch (_) {
      _setStatus(
        _l10n.socialCallRecoverFailed,
        tone: _SocialCallStatusTone.error,
      );
    } finally {
      if (mounted) setState(() => _pendingIncomingAccept = false);
    }
  }

  Future<void> _applyInitialNotificationAction() async {
    if (_initialActionHandled || _isCaller || _sessionId == null) return;
    _initialActionHandled = true;
    final action = (widget.initialAction ?? '').trim().toLowerCase();
    if (action == 'accept' || action == 'answer') {
      await _acceptIncoming();
      return;
    }
    if (action == 'reject' || action == 'decline') {
      await _declineIncoming();
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
    await _closeScreen();
  }

  Future<void> _endCall({
    String status = 'ended',
    String reason = 'user_hangup',
  }) async {
    if (_callEnded) return;
    _callEnded = true;
    _stopRinging();
    // Stop local capture immediately, even when the signaling network is slow.
    // The session-scoped signal also ends the server session and informs peers.
    await _disposeRtc();
    if (_sessionId != null) {
      try {
        await _sendSignal(
          signalType: status == 'declined' ? 'decline' : 'hangup',
        ).timeout(const Duration(seconds: 4));
      } catch (_) {
        // Never end a different, newer call through a thread-only fallback.
      }
    }
    await _closeScreen();
  }

  Future<void> _closeScreen() async {
    if (!mounted || _disposed) return;
    setState(() {});
    await WidgetsBinding.instance.endOfFrame;
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposeRtc() async {
    _voiceReconnectTimer?.cancel();
    _legacyOfferTimer?.cancel();
    _stateSyncTimer?.cancel();
    _ticker?.cancel();
    _ticker = null;
    _stopRinging();
    _iceRecoverTimer?.cancel();
    _iceRecoverTimer = null;
    await _voice.disconnect();
    await _disposeLegacyMedia();
  }

  Future<void> _disposeLegacyMedia() async {
    final hadLegacyMedia = _pc != null || _localStream != null;
    if (_remoteAudioReady && !_disposed) _remoteAudio.srcObject = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      for (final track in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await track.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    try {
      await _remoteStream?.dispose();
    } catch (_) {}
    _remoteStream = null;
    _remoteDescriptionSet = false;
    _boundRemoteAudioTracks.clear();
    _queuedRemoteCandidates.clear();
    if (hadLegacyMedia && WebRTC.platformIsAndroid) {
      try {
        await Helper.clearAndroidCommunicationDevice();
      } catch (_) {}
    }
  }

  Future<void> _connectLiveKit() async {
    if (_disposed || _callEnded || _voiceConnecting || _sessionId == null) {
      return;
    }
    if (_voice.connected || _voice.reconnecting) return;
    _voiceConnecting = true;
    _acceptedIncoming = true;
    _stopRinging();
    _setStatus(_l10n.socialCallAnsweredConnectingAudio);
    try {
      _iceRecoverTimer?.cancel();
      _legacyOfferTimer?.cancel();
      // Finish a legacy capture already in flight before LiveKit owns the mic.
      try {
        await _rtcWork;
      } catch (_) {}
      await _disposeLegacyMedia();
      if (_disposed || _callEnded) return;
      await _voice.setMuted(_muted);
      await _voice.setSpeaker(_speakerOn);
      await _voice.connect(
        () => _api.getThreadCallVoiceToken(
          threadId: widget.threadId,
          sessionId: _sessionId!,
        ),
      );
      _onVoiceChanged();
    } on _MicPermissionDenied {
      _microphonePermissionDenied = true;
      _setStatus(
        _l10n.socialCallMicrophonePermissionRequired,
        tone: _SocialCallStatusTone.error,
      );
    } on DioException catch (error) {
      _setStatus(_mapCallError(error), tone: _SocialCallStatusTone.error);
    } catch (_) {
      _setStatus(
        _l10n.socialCallRecoverFailed,
        tone: _SocialCallStatusTone.error,
      );
    } finally {
      _voiceConnecting = false;
      if (!_voice.connected &&
          _sessionStatus == 'active' &&
          _voiceTransport == 'livekit' &&
          !_microphonePermissionDenied) {
        _scheduleVoiceReconnect();
      }
    }
  }

  void _onVoiceChanged() {
    if (_disposed || !mounted || _callEnded) return;
    if (_voice.mediaReady) {
      _onConnected();
    } else {
      setState(() => _inCall = false);
      _setStatus(
        _voice.needsMicrophoneRetry
            ? _l10n.socialCallMicrophonePermissionRequired
            : _voice.connected && !_voice.peerPresent
            ? context.lt(
                ar: 'بانتظار اتصال الطرف الآخر بالصوت',
                en: 'Waiting for the other participant to join audio',
              )
            : _l10n.socialCallAnsweredConnectingAudio,
        tone: _SocialCallStatusTone.warning,
      );
      if (!_voice.connected && !_voice.reconnecting) {
        _scheduleVoiceReconnect();
      }
    }
  }

  void _scheduleVoiceReconnect() {
    if (_disposed ||
        _callEnded ||
        _sessionStatus != 'active' ||
        _voiceTransport != 'livekit' ||
        _voice.connected ||
        _voice.reconnecting ||
        _voiceReconnectTimer?.isActive == true) {
      return;
    }
    _voiceReconnectAttempt = (_voiceReconnectAttempt + 1).clamp(1, 6);
    final delay = switch (_voiceReconnectAttempt) {
      1 => const Duration(seconds: 1),
      2 => const Duration(seconds: 2),
      3 => const Duration(seconds: 4),
      4 => const Duration(seconds: 8),
      _ => const Duration(seconds: 15),
    };
    _voiceReconnectTimer = Timer(delay, () {
      if (_disposed || _callEnded) return;
      unawaited(_connectLiveKit());
    });
  }

  Future<void> _retryCallAudio() async {
    try {
      if (_microphonePermissionDenied) {
        final permission = await Permission.microphone.status;
        if (permission.isPermanentlyDenied || permission.isRestricted) {
          await openAppSettings();
          return;
        }
        _microphonePermissionDenied = false;
      }
      if (_sessionId == null) {
        await _bootstrap();
        return;
      }
      if (_voice.needsMicrophoneRetry) {
        await _ensureMicrophonePermission();
        if (_disposed || _callEnded) return;
        await _voice.setMuted(_muted);
      }
      if (_voice.needsAudioStart) await _voice.startAudio();
      if (!_voice.connected) await _loadCallState();
      if (!_isCaller && !_acceptedIncoming) return;
      _scheduleLegacyOffer();
      if (_voiceTransport == 'livekit') _onVoiceChanged();
    } on _MicPermissionDenied {
      _microphonePermissionDenied = true;
      _setStatus(
        _l10n.socialCallMicrophonePermissionRequired,
        tone: _SocialCallStatusTone.error,
      );
    } catch (_) {
      _setStatus(
        _l10n.socialCallRecoverFailed,
        tone: _SocialCallStatusTone.error,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && !_callEnded) {
      unawaited(
        _loadCallState().catchError((_) {
          _setStatus(
            _l10n.socialCallRecoverFailed,
            tone: _SocialCallStatusTone.error,
          );
        }),
      );
    }
  }

  void _onConnected() {
    if (_disposed || _callEnded) return;
    _voiceReconnectTimer?.cancel();
    _voiceReconnectAttempt = 0;
    _stopRinging();
    unawaited(_applyAudioRoute().catchError((_) {}));
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
    _stateSyncTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || _disposed || _callEnded || _stateSyncInFlight) return;
      _stateSyncInFlight = true;
      _loadCallState().catchError((_) {}).whenComplete(() {
        _stateSyncInFlight = false;
      });
    });
  }

  void _startRinging({required bool incoming}) {
    if (_disposed || _callEnded || _inCall) return;
    unawaited(
      incoming
          ? _callToneService.startIncoming()
          : _callToneService.startOutgoing(),
    );
  }

  void _stopRinging() {
    unawaited(_callToneService.stop());
    if (_callNotificationCancelled) return;
    final sessionId = _sessionId;
    final notificationId = widget.notificationId;
    if ((sessionId == null || sessionId <= 0) &&
        (notificationId == null || notificationId <= 0)) {
      return;
    }
    _callNotificationCancelled = true;
    if (sessionId != null && sessionId > 0) {
      unawaited(_localNotifications.cancelIncomingCall(sessionId));
    }
    if (notificationId != null && notificationId > 0) {
      unawaited(_localNotifications.cancelNotification(notificationId));
    }
  }

  Future<void> _toggleMute() async {
    if (_voiceTransport == 'livekit') {
      final next = !_muted;
      setState(() => _muted = next);
      try {
        await _voice.setMuted(next);
      } catch (_) {
        _setStatus(
          _l10n.socialCallMicrophonePermissionRequired,
          tone: _SocialCallStatusTone.error,
        );
      }
      return;
    }
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
    try {
      await _applyAudioRoute();
    } catch (_) {
      _setStatus(
        _l10n.socialCallRecoverFailed,
        tone: _SocialCallStatusTone.error,
      );
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _applyAudioRoute() async {
    if (_voiceTransport == 'livekit') {
      await _voice.setSpeaker(_speakerOn);
      return;
    }
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
    for (final track in _boundRemoteAudioTracks.values) {
      track.enabled = true;
      unawaited(Helper.setVolume(1.0, track).catchError((_) {}));
    }
  }

  void _bindRemoteStream(MediaStream stream) {
    _remoteStream = stream;
    if (_remoteAudioReady && !_disposed) _remoteAudio.srcObject = stream;
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
    _boundRemoteAudioTracks[trackId] = track;
    track.enabled = true;
    unawaited(_applyAudioRoute().catchError((_) {}));
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
        case 'SOCIAL_CALL_NOT_ACTIVE':
          return context.lt(
            ar: 'انتهت هذه المكالمة. ابدأ مكالمة جديدة.',
            en: 'This call has ended. Start a new call.',
          );
        case 'SOCIAL_VOICE_UNAVAILABLE':
          return context.lt(
            ar: 'خدمة صوت المكالمات غير متاحة الآن. حاول مجددًا.',
            en: 'Call audio is unavailable right now. Try again.',
          );
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
        !_isCaller && _sessionId != null && !_acceptedIncoming && !_callEnded;
    final statusColor = _statusColor();
    final headline = incomingAwaitingAccept
        ? l10n.socialCallIncomingHeadline(
            widget.remoteDisplayName ?? l10n.socialCallParticipantFallback,
          )
        : (widget.remoteDisplayName ?? l10n.socialCallOtherParticipant);

    return PopScope(
      canPop: _callEnded,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_endCall());
      },
      child: Scaffold(
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
                    if (_remoteAudioReady && _voiceTransport != 'livekit')
                      SizedBox(
                        width: 1,
                        height: 1,
                        child: RTCVideoView(_remoteAudio),
                      ),
                    if (_voice.needsAudioStart)
                      TextButton.icon(
                        onPressed: _retryCallAudio,
                        icon: const Icon(Icons.volume_up, color: Colors.white),
                        label: Text(
                          context.lt(
                            ar: 'تشغيل صوت المكالمة',
                            en: 'Play call audio',
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    if (_voice.needsMicrophoneRetry ||
                        (!_voice.connected &&
                            _statusTone == _SocialCallStatusTone.error))
                      TextButton.icon(
                        onPressed: _retryCallAudio,
                        icon: const Icon(Icons.refresh, color: Colors.white),
                        label: Text(
                          context.lt(
                            ar: 'إعادة محاولة الاتصال والصوت',
                            en: 'Retry connection and audio',
                          ),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    const SizedBox(height: 20),
                    TweenAnimationBuilder<double>(
                      duration: const Duration(milliseconds: 900),
                      tween: Tween<double>(
                        begin: 0.96,
                        end: _inCall ? 1 : 0.98,
                      ),
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
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      context.lt(
                        ar: 'مكالمة صوتية خاصة',
                        en: 'Private voice call',
                      ),
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.white.withValues(alpha: 0.68),
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
                        _statusText ??
                            (_busy
                                ? l10n.commonLoading
                                : l10n.socialCallInitializing),
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
                        color: Colors.white,
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
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                                backgroundColor: const Color(0xFF7D2635),
                                foregroundColor: Colors.white,
                              ),
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
                              style: FilledButton.styleFrom(
                                minimumSize: const Size.fromHeight(56),
                                backgroundColor: const Color(0xFF198754),
                                foregroundColor: Colors.white,
                              ),
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
