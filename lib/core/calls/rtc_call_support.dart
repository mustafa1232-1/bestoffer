import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

DateTime? _rtcConfigExpiresAt;
List<Map<String, dynamic>>? _cachedRuntimeIceServers;

Map<String, dynamic> buildRtcCallConfig({
  List<Map<String, dynamic>> extraIceServers = const [],
}) {
  final servers = <Map<String, dynamic>>[
    {
      'urls': <String>[
        'stun:stun.l.google.com:19302',
        'stun:stun1.l.google.com:19302',
      ],
    },
  ];

  const turnUrl = String.fromEnvironment('RTC_TURN_URL', defaultValue: '');
  const turnUrls = String.fromEnvironment('RTC_TURN_URLS', defaultValue: '');
  const turnUsername = String.fromEnvironment(
    'RTC_TURN_USERNAME',
    defaultValue: '',
  );
  const turnCredential = String.fromEnvironment(
    'RTC_TURN_CREDENTIAL',
    defaultValue: '',
  );

  final relayUrls = <String>{
    ...turnUrl
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty),
    ...turnUrls
        .split(',')
        .map((item) => item.trim())
        .where((item) => item.isNotEmpty),
  }.toList(growable: false);

  if (relayUrls.isNotEmpty) {
    servers.add({
      'urls': relayUrls.length == 1 ? relayUrls.first : relayUrls,
      if (turnUsername.trim().isNotEmpty) 'username': turnUsername.trim(),
      if (turnCredential.trim().isNotEmpty) 'credential': turnCredential,
    });
  }

  servers.addAll(extraIceServers);
  servers.addAll(_parseExtraIceServers());

  return {
    'iceServers': servers,
    'iceTransportPolicy': 'all',
    'bundlePolicy': 'max-bundle',
    'rtcpMuxPolicy': 'require',
    'sdpSemantics': 'unified-plan',
    'iceCandidatePoolSize': 12,
  };
}

Future<Map<String, dynamic>> resolveRtcCallConfig(Dio dio) async {
  final runtimeServers = await _loadRuntimeIceServers(dio);
  return buildRtcCallConfig(extraIceServers: runtimeServers);
}

Future<List<Map<String, dynamic>>> _loadRuntimeIceServers(Dio dio) async {
  final now = DateTime.now();
  final expiresAt = _rtcConfigExpiresAt;
  final cached = _cachedRuntimeIceServers;
  if (cached != null &&
      expiresAt != null &&
      expiresAt.isAfter(now.add(const Duration(minutes: 1)))) {
    return cached;
  }

  try {
    final response = await dio.get('/api/system/rtc-config');
    final data = response.data;
    if (data is! Map) return cached ?? const [];

    final rawServers = List<dynamic>.from(
      data['iceServers'] as List? ?? const [],
    );
    final parsed = rawServers
        .whereType<Map>()
        .map((row) => Map<String, dynamic>.from(row))
        .where((row) {
          final urls = row['urls'];
          return (urls is String && urls.trim().isNotEmpty) ||
              (urls is List && urls.any((item) => '$item'.trim().isNotEmpty));
        })
        .toList(growable: false);

    final expiresText = '${data['expiresAt'] ?? ''}'.trim();
    final nextExpiry =
        DateTime.tryParse(expiresText)?.toLocal() ??
        now.add(const Duration(minutes: 30));

    _cachedRuntimeIceServers = parsed;
    _rtcConfigExpiresAt = nextExpiry;
    return parsed;
  } catch (_) {
    return cached ?? const [];
  }
}

Map<String, dynamic> buildHighQualityAudioConstraints() {
  // Keep this SIMPLE. Native (Android/iOS) WebRTC ignores/rejects strict + legacy
  // constraints (sampleRate/latency/channelCount + the goog* web flags), which can
  // yield a SILENT capture track — the exact "call connects but no audio (both
  // ends, even on same Wi-Fi)" symptom. Native WebRTC enables echo cancellation,
  // noise suppression and auto gain by default, so a plain `audio: true` is the
  // reliable choice for mobile voice calls.
  return {
    'audio': true,
    'video': false,
  };
}

RTCSessionDescription optimizeVoiceDescription(RTCSessionDescription source) {
  // SDP munging DISABLED (2026-08-15). The custom Opus payload reordering + fmtp
  // rewriting below was a likely cause of "call connects but NO audio" (verified
  // symptom: no audio even on the same Wi-Fi, which rules out TURN/connectivity).
  // Rewriting the audio m-line can corrupt codec negotiation and break media while
  // ICE/DTLS still connect. Standard WebRTC negotiates Opus correctly on its own,
  // so return the SDP unchanged. `_optimizeOpusSdp` is kept for reference only.
  return source;
}

List<Map<String, dynamic>> _parseExtraIceServers() {
  const raw = String.fromEnvironment('RTC_ICE_SERVERS_JSON', defaultValue: '');
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

// ignore: unused_element
String _optimizeOpusSdp(String? rawSdp) {
  final sdp = rawSdp ?? '';
  if (sdp.isEmpty) return sdp;

  final opusMatch = RegExp(
    r'a=rtpmap:(\d+) opus/48000/2',
    multiLine: true,
  ).firstMatch(sdp);
  if (opusMatch == null) return sdp;

  final payloadId = opusMatch.group(1)!;
  var optimized = sdp;

  optimized = optimized.replaceFirstMapped(
    RegExp(r'm=audio\s+\d+\s+[A-Z/]+\s+(.+)', multiLine: true),
    (match) {
      final line = match.group(0)!;
      final parts = line.split(' ');
      if (parts.length <= 3) return line;
      final header = parts.sublist(0, 3);
      final payloads = parts.sublist(3);
      payloads.remove(payloadId);
      payloads.insert(0, payloadId);
      return [...header, ...payloads].join(' ');
    },
  );

  final fmtpPattern = RegExp(r'a=fmtp:' + payloadId + r'\s+([^\r\n]*)');
  final additions = <String>[
    'minptime=10',
    'useinbandfec=1',
    'usedtx=0',
    'maxaveragebitrate=64000',
  ];

  if (fmtpPattern.hasMatch(optimized)) {
    optimized = optimized.replaceFirstMapped(fmtpPattern, (match) {
      final existing = match.group(1) ?? '';
      final params = existing
          .split(';')
          .map((item) => item.trim())
          .where((item) => item.isNotEmpty)
          .toList();
      for (final addition in additions) {
        final key = addition.split('=').first;
        if (params.any((item) => item.split('=').first == key)) continue;
        params.add(addition);
      }
      return 'a=fmtp:$payloadId ${params.join(';')}';
    });
  } else {
    optimized = optimized.replaceFirst(
      'a=rtpmap:$payloadId opus/48000/2',
      'a=rtpmap:$payloadId opus/48000/2\r\na=fmtp:$payloadId ${additions.join(';')}',
    );
  }

  return optimized;
}
