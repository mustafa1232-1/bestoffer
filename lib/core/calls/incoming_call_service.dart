import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../constants/api.dart';
import '../platform/app_platform_capabilities.dart';

/// Push contract for in-app calls (see backend feed.call-push.js).
const String kSocialCallInviteType = 'social.call.incoming';
const String kSocialCallEndedType = 'social.call.ended';

/// Path the native decline handlers (Android MainApplication, iOS AppDelegate)
/// post the signed `callActionToken` to when the app is closed.
const String kSocialCallDeclinePath = '/api/feed/chats/calls/decline';

/// Deterministic CallKit UUID for a call session; must match
/// `callUuidForSession` in backend/src/modules/feed/feed.call-push.js.
String callUuidForSession(int sessionId) {
  final hex = sessionId.toRadixString(16).padLeft(12, '0');
  final tail = hex.substring(hex.length - 12);
  return '5a17ca11-0000-4000-8000-$tail';
}

int? sessionIdFromCallUuid(String? uuid) {
  final value = (uuid ?? '').trim().toLowerCase();
  if (!value.startsWith('5a17ca11-0000-4000-8000-')) return null;
  final parsed = int.tryParse(value.split('-').last, radix: 16);
  return parsed != null && parsed > 0 ? parsed : null;
}

/// An incoming call invite parsed from a push data map.
@immutable
class IncomingCallInvite {
  final int threadId;
  final int sessionId;
  final String callUuid;
  final String callerName;
  final String? callerAvatarUrl;
  final int? callerUserId;
  final String? callActionToken;
  final DateTime? expiresAt;

  const IncomingCallInvite({
    required this.threadId,
    required this.sessionId,
    required this.callUuid,
    required this.callerName,
    this.callerAvatarUrl,
    this.callerUserId,
    this.callActionToken,
    this.expiresAt,
  });

  static IncomingCallInvite? fromPushData(Map<String, dynamic> data) {
    if (_text(data['type']) != kSocialCallInviteType) return null;
    final threadId = _int(data['threadId'] ?? data['thread_id']);
    final sessionId = _int(data['sessionId'] ?? data['session_id']);
    if (threadId == null || sessionId == null) return null;
    final callerName =
        _text(data['callerName']) ?? _text(data['remoteDisplayName']) ?? '';
    return IncomingCallInvite(
      threadId: threadId,
      sessionId: sessionId,
      callUuid: _text(data['callUuid']) ?? callUuidForSession(sessionId),
      callerName: callerName,
      callerAvatarUrl: _text(data['callerAvatarUrl']),
      callerUserId: _int(data['senderUserId']),
      callActionToken: _text(data['callActionToken']),
      expiresAt: DateTime.tryParse(_text(data['callExpiresAt']) ?? ''),
    );
  }

  bool isExpired([DateTime? now]) {
    final expiry = expiresAt;
    if (expiry == null) return false;
    return (now ?? DateTime.now()).isAfter(expiry);
  }

  Map<String, dynamic> toExtra({required String declineUrl}) => {
    'threadId': threadId,
    'sessionId': sessionId,
    'callerName': callerName,
    if (callerUserId != null) 'senderUserId': callerUserId,
    if (callActionToken != null) 'callActionToken': callActionToken,
    'declineUrl': declineUrl,
  };
}

/// Call identifiers read back from a native CallKit event / active call.
@immutable
class CallKitCallRef {
  final String callUuid;
  final int threadId;
  final int sessionId;
  final String? callerName;
  final String? callActionToken;
  final bool accepted;

  const CallKitCallRef({
    required this.callUuid,
    required this.threadId,
    required this.sessionId,
    this.callerName,
    this.callActionToken,
    this.accepted = false,
  });

  static CallKitCallRef? fromParams(CallKitParams params) {
    final extra = params.extra ?? const <String, dynamic>{};
    final threadId = _int(extra['threadId']);
    final sessionId =
        _int(extra['sessionId']) ?? sessionIdFromCallUuid(params.id);
    if (threadId == null || sessionId == null) return null;
    return CallKitCallRef(
      callUuid: params.id,
      threadId: threadId,
      sessionId: sessionId,
      callerName: _text(extra['callerName']) ?? params.nameCaller,
      callActionToken: _text(extra['callActionToken']),
      accepted: params.isAccepted,
    );
  }
}

/// Native incoming-call UI: Android full-screen CallStyle activity
/// (self-managed ConnectionService) and iOS CallKit, via
/// flutter_callkit_incoming. Works from the FCM background isolate too.
class IncomingCallService {
  IncomingCallService._();

  static String get declineUrl {
    final base = Api.fallbackBaseUrls.first.trim();
    final normalized = base.endsWith('/')
        ? base.substring(0, base.length - 1)
        : base;
    return '$normalized$kSocialCallDeclinePath';
  }

  static bool get supported =>
      appInAppCallsEnabled &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static bool isCallInvite(Map<String, dynamic> data) =>
      _text(data['type']) == kSocialCallInviteType;

  static bool isCallEnded(Map<String, dynamic> data) {
    final type = _text(data['type']);
    return type == kSocialCallEndedType || type == 'social.call.cancelled';
  }

  static CallKitParams buildParams(
    IncomingCallInvite invite, {
    bool english = false,
  }) {
    final remaining = invite.expiresAt == null
        ? const Duration(seconds: 35)
        : invite.expiresAt!.difference(DateTime.now());
    final durationMs = remaining.inMilliseconds.clamp(5000, 45000);
    final name = invite.callerName.trim().isEmpty
        ? (english ? 'Maslaki call' : 'مكالمة مسلكي')
        : invite.callerName.trim();
    return CallKitParams(
      id: invite.callUuid,
      nameCaller: name,
      appName: english ? 'Maslaki' : 'مسلكي',
      avatar: invite.callerAvatarUrl,
      handle: english ? 'Maslaki voice call' : 'مكالمة صوتية - مسلكي',
      type: 0,
      duration: durationMs,
      // Missed calls are stored server-side ("missed call from X").
      missedCallNotification: const NotificationParams(
        showNotification: false,
        isShowCallback: false,
      ),
      extra: invite.toExtra(declineUrl: declineUrl),
      android: AndroidParams(
        isCustomNotification: true,
        isShowLogo: false,
        isShowCallID: false,
        isShowFullLockedScreen: true,
        isImportant: true,
        ringtonePath: 'system_ringtone_default',
        backgroundColor: '#0F1B2D',
        actionColor: '#2BB673',
        textColor: '#FFFFFF',
        incomingCallNotificationChannelName: english
            ? 'Incoming calls'
            : 'المكالمات الواردة',
        missedCallNotificationChannelName: english
            ? 'Missed calls'
            : 'المكالمات الفائتة',
        textAccept: english ? 'Answer' : 'رد',
        textDecline: english ? 'Decline' : 'رفض',
      ),
      ios: const IOSParams(
        handleType: 'generic',
        supportsVideo: false,
        maximumCallGroups: 1,
        maximumCallsPerCallGroup: 1,
        supportsDTMF: false,
        supportsHolding: false,
        supportsGrouping: false,
        supportsUngrouping: false,
        includesCallsInRecents: true,
        configureAudioSession: true,
        audioSessionMode: 'voiceChat',
        audioSessionActive: true,
        ringtonePath: 'system_ringtone_default',
      ),
    );
  }

  /// Rings the phone with the native Answer / Decline UI.
  static Future<bool> showIncoming(
    IncomingCallInvite invite, {
    bool english = false,
  }) async {
    if (!supported || invite.isExpired()) return false;
    try {
      await FlutterCallkitIncoming.showCallkitIncoming(
        buildParams(invite, english: english),
      );
      return true;
    } catch (error) {
      debugPrint('[calls] showCallkitIncoming failed: $error');
      return false;
    }
  }

  /// Stops ringing / clears the native call UI for [callUuid].
  static Future<void> endCall(String callUuid) async {
    if (!supported || callUuid.trim().isEmpty) return;
    try {
      await FlutterCallkitIncoming.endCall(callUuid);
    } catch (error) {
      debugPrint('[calls] endCall failed: $error');
    }
  }

  static Future<void> endCallForSession(int? sessionId) async {
    if (sessionId == null || sessionId <= 0) return;
    await endCall(callUuidForSession(sessionId));
  }

  static Future<List<CallKitCallRef>> activeCalls() async {
    if (!supported) return const <CallKitCallRef>[];
    try {
      final calls = await FlutterCallkitIncoming.activeCalls();
      return calls
          .map(CallKitCallRef.fromParams)
          .whereType<CallKitCallRef>()
          .toList(growable: false);
    } catch (_) {
      return const <CallKitCallRef>[];
    }
  }

  /// Server-side decline with the signed push token (idempotent; the native
  /// layers send the same request when the app is not running).
  static Future<void> declineWithToken(String? callActionToken) async {
    final token = (callActionToken ?? '').trim();
    if (token.isEmpty) return;
    try {
      await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 8),
          receiveTimeout: const Duration(seconds: 8),
        ),
      ).post<void>(declineUrl, data: {'token': token});
    } catch (error) {
      debugPrint('[calls] decline request failed: $error');
    }
  }

  static Future<String?> voipPushToken() async {
    if (!supported || defaultTargetPlatform != TargetPlatform.iOS) return null;
    try {
      final token = await FlutterCallkitIncoming.getDevicePushTokenVoIP();
      final clean = (token ?? '').trim();
      return clean.isEmpty ? null : clean;
    } catch (_) {
      return null;
    }
  }

  /// Android 14+: incoming calls need the full-screen-intent grant to pop over
  /// the lock screen. No-op elsewhere.
  static Future<void> ensureAndroidCallPermissions() async {
    if (!supported || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      final allowed = await FlutterCallkitIncoming.canUseFullScreenIntent();
      if (!allowed) await FlutterCallkitIncoming.requestFullIntentPermission();
    } catch (_) {
      // Older Android / plugin without the API.
    }
  }
}

int? _int(dynamic value) {
  final parsed = int.tryParse('${value ?? ''}'.trim());
  return parsed != null && parsed > 0 ? parsed : null;
}

String? _text(dynamic value) {
  if (value == null) return null;
  final text = '$value'.trim();
  return text.isEmpty ? null : text;
}
