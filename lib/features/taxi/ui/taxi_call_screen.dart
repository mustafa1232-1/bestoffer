import 'dart:async';

import 'package:bestoffer/features/auth/state/auth_controller.dart';
import 'package:bestoffer/features/taxi/data/taxi_api.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

final taxiCallApiProvider = Provider<TaxiApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return TaxiApi(dio);
});

class TaxiCallScreen extends ConsumerStatefulWidget {
  final int rideId;
  final bool isCaller;
  final int? initialSessionId;
  final String? remoteDisplayName;

  const TaxiCallScreen({
    super.key,
    required this.rideId,
    required this.isCaller,
    this.initialSessionId,
    this.remoteDisplayName,
  });

  @override
  ConsumerState<TaxiCallScreen> createState() => _TaxiCallScreenState();
}

class _TaxiCallScreenState extends ConsumerState<TaxiCallScreen> {
  TaxiApi get _api => ref.read(taxiCallApiProvider);

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  StreamSubscription<TaxiLiveEvent>? _streamSub;
  Timer? _ticker;

  final Set<int> _handledSignalIds = <int>{};

  int? _sessionId;
  bool _busy = true;
  bool _inCall = false;
  bool _muted = false;
  bool _speakerOn = true;
  bool _pendingIncomingAccept = false;
  bool _acceptedIncoming = false;
  bool _disposed = false;
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
    unawaited(_disposeRtc());
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      await _prepareRtc();
      await _connectSignalStream();
      await _loadCallState();

      if (widget.isCaller && _sessionId == null) {
        final out = await _api.startRideCall(rideId: widget.rideId);
        final session = out['session'];
        if (session is Map) {
          _sessionId = _asInt(session['id']);
        }
        await _createAndSendOffer();
        _setStatus('جاري الاتصال بالطرف الآخر...');
      } else if (!widget.isCaller) {
        _setStatus('مكالمة واردة...');
      }

      _startTicker();
    } catch (_) {
      _setStatus('تعذر بدء الاتصال داخل التطبيق');
    } finally {
      if (!_disposed && mounted) {
        setState(() => _busy = false);
      }
    }
  }

  Future<void> _prepareRtc() async {
    final config = <String, dynamic>{
      'iceServers': [
        {
          'urls': [
            'stun:stun.l.google.com:19302',
            'stun:stun1.l.google.com:19302',
          ],
        },
      ],
      'sdpSemantics': 'unified-plan',
    };

    _pc = await createPeerConnection(config);

    _pc!.onConnectionState = (state) {
      if (!mounted) return;
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        setState(() {
          _inCall = true;
          _connectedAt ??= DateTime.now();
          _statusText = 'المكالمة متصلة';
        });
      } else if (state ==
          RTCPeerConnectionState.RTCPeerConnectionStateDisconnected) {
        setState(() => _statusText = 'إعادة محاولة الاتصال...');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        setState(() => _statusText = 'فشل الاتصال');
      } else if (state == RTCPeerConnectionState.RTCPeerConnectionStateClosed) {
        setState(() => _statusText = 'انتهت المكالمة');
      }
    };

    _pc!.onIceCandidate = (candidate) {
      if (candidate.candidate == null || candidate.candidate!.isEmpty) return;
      unawaited(
        _sendSignal(
          signalType: 'ice',
          signalPayload: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        ),
      );
    };

    _localStream = await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });

    for (final track in _localStream!.getAudioTracks()) {
      await _pc!.addTrack(track, _localStream!);
    }

    await Helper.setSpeakerphoneOn(true);
  }

  Future<void> _connectSignalStream() async {
    _streamSub?.cancel();
    _streamSub = _api.streamEvents().listen(
      (event) {
        if (event.event != 'taxi_call_update') return;
        final rideId = _asInt(event.data['rideId']);
        if (rideId != widget.rideId) return;
        _handleCallUpdateEvent(event.data);
      },
      onError: (_) {
        if (mounted) {
          setState(() => _statusText = 'تقطّع في الاتصال، جاري الاستعادة...');
        }
      },
    );
  }

  Future<void> _loadCallState() async {
    final state = await _api.getRideCallState(rideId: widget.rideId);
    final session = state['session'];
    if (session is Map) {
      _sessionId = _asInt(session['id']) ?? _sessionId;
      final status = _asString(session['status']);
      if (status == 'active') {
        _inCall = true;
        _connectedAt ??= DateTime.now();
        _statusText = 'المكالمة متصلة';
      } else if (status == 'ringing') {
        _statusText = 'جاري الرنين...';
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

  Future<void> _createAndSendOffer() async {
    if (_pc == null) return;
    final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(offer);
    await _sendSignal(
      signalType: 'offer',
      signalPayload: {'sdp': offer.sdp, 'type': offer.type},
    );
  }

  Future<void> _sendSignal({
    required String signalType,
    Map<String, dynamic>? signalPayload,
  }) async {
    final out = await _api.sendRideCallSignal(
      rideId: widget.rideId,
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

    final eventType = _asString(data['eventType']);
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

    final type = _asString(signal['signalType']);
    final payload = signal['signalPayload'] is Map
        ? Map<String, dynamic>.from(signal['signalPayload'] as Map)
        : <String, dynamic>{};

    if (type == 'offer') {
      if (!widget.isCaller && !_acceptedIncoming) {
        _pendingOfferPayload = payload;
        _pendingIncomingAccept = true;
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
      _setStatus('تم قبول المكالمة');
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
    final answer = await _pc!.createAnswer({'offerToReceiveAudio': true});
    await _pc!.setLocalDescription(answer);
    await _sendSignal(
      signalType: 'answer',
      signalPayload: {'sdp': answer.sdp, 'type': answer.type},
    );

    if (mounted) {
      setState(() {
        _inCall = true;
        _connectedAt ??= DateTime.now();
      });
    }
    _setStatus('المكالمة متصلة');
  }

  Future<void> _handleAnswer(Map<String, dynamic> payload) async {
    if (_pc == null) return;
    final sdp = _asString(payload['sdp']);
    final type = _asString(payload['type']) ?? 'answer';
    if (sdp == null || sdp.isEmpty) return;

    await _pc!.setRemoteDescription(RTCSessionDescription(sdp, type));
    if (mounted) {
      setState(() {
        _inCall = true;
        _connectedAt ??= DateTime.now();
      });
    }
    _setStatus('المكالمة متصلة');
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
    await _pc!.addCandidate(candidate);
  }

  Future<void> _acceptIncoming() async {
    if (_pendingOfferPayload == null || _pendingIncomingAccept) return;
    setState(() => _pendingIncomingAccept = true);
    try {
      await _sendSignal(signalType: 'accept');
      _acceptedIncoming = true;
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
    try {
      await _api.endRideCall(
        rideId: widget.rideId,
        status: status,
        reason: reason,
      );
    } catch (_) {
      // ignore
    }
    await _disposeRtc();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _disposeRtc() async {
    _ticker?.cancel();
    _ticker = null;
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
    try {
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
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

  @override
  Widget build(BuildContext context) {
    final incomingAwaitingAccept =
        !widget.isCaller && _pendingOfferPayload != null && !_acceptedIncoming;

    return Scaffold(
      appBar: AppBar(
        title: const Text('مكالمة التكسي'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => _endCall(),
        ),
      ),
      body: Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                const SizedBox(height: 20),
                CircleAvatar(
                  radius: 48,
                  backgroundColor: Colors.blue.withValues(alpha: 0.16),
                  child: const Icon(Icons.person_rounded, size: 52),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.remoteDisplayName ?? 'الطرف الآخر',
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _busy ? 'جاري التحميل...' : _statusText,
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 6),
                Text(
                  _inCall ? _durationText() : '00:00',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
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
                        icon: _muted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
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
