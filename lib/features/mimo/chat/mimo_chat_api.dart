import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';

final mimoChatApiProvider = Provider<MimoChatApi>((ref) {
  return MimoChatApi(ref.read(dioClientProvider).dio);
});

/// Picks a photo for Mimo (camera or gallery). Overridable in tests.
final mimoPhotoPickerProvider =
    Provider<Future<LocalImageFile?> Function({required bool camera})>(
      (ref) =>
          ({required bool camera}) =>
              camera ? captureImageFromCamera() : pickImageFromDevice(),
    );

/// One server-sent event from Mimo's brain.
class MimoStreamEvent {
  const MimoStreamEvent(this.event, this.data);

  /// status | delta | ui | done | error
  final String event;
  final Map<String, dynamic> data;
}

class MimoChatApi {
  MimoChatApi(this.dio);

  final Dio dio;

  /// 👍/👎 on an answer — Mimo learns which answers helped. Never throws.
  Future<void> feedback({
    required bool up,
    required String question,
    required String answer,
    String? refs,
  }) async {
    try {
      await dio.post(
        '/api/mimo/feedback',
        data: {
          'rating': up ? 'up' : 'down',
          'question': question,
          'answer': answer,
          'refs': ?refs,
        },
      );
    } catch (_) {}
  }

  /// The user confirmed one of Mimo's cart proposals. Never throws.
  Future<void> cartAdded(List<Map<String, dynamic>> items) async {
    try {
      await dio.post('/api/mimo/cart-added', data: {'items': items});
    } catch (_) {}
  }

  /// Uploads a chat photo to our own server (same storage as support
  /// attachments) and returns {fileUrl, storageKey, fileName, mimeType, ...}.
  Future<Map<String, dynamic>> uploadPhoto(LocalImageFile file) async {
    final data = FormData.fromMap({'file': await file.toMultipartFile()});
    final response = await dio.post('/api/support/attachments', data: data);
    final map = Map<String, dynamic>.from(response.data as Map);
    return Map<String, dynamic>.from(map['attachment'] as Map);
  }

  /// Today's proactive suggestion, or null. Never throws.
  Future<Map<String, dynamic>?> nudge(String lang) async {
    try {
      final r = await dio.get(
        '/api/mimo/nudge',
        queryParameters: {'lang': lang},
      );
      final n = (r.data is Map) ? (r.data as Map)['nudge'] : null;
      return n is Map ? Map<String, dynamic>.from(n) : null;
    } catch (_) {
      return null;
    }
  }

  /// shown | tapped — so the admin dashboard knows if nudges help. Never throws.
  Future<void> proactiveEvent({
    required String nudgeId,
    required String event,
    String? kind,
  }) async {
    try {
      await dio.post(
        '/api/mimo/proactive',
        data: {'nudgeId': nudgeId, 'event': event, 'kind': ?kind},
      );
    } catch (_) {}
  }

  /// Streams Mimo's answer: what he's doing, his words as they are written,
  /// cards/buttons, then `done`.
  Stream<MimoStreamEvent> chat({
    required List<Map<String, dynamic>> messages,
    required String lang,
    Map<String, dynamic> context = const {},
    String summary = '',
    List<Map<String, dynamic>> attachments = const [],
    CancelToken? cancelToken,
  }) async* {
    final response = await dio.post<ResponseBody>(
      '/api/mimo/chat',
      data: {
        'messages': messages,
        'lang': lang,
        'context': context,
        if (summary.isNotEmpty) 'summary': summary,
        if (attachments.isNotEmpty) 'attachments': attachments,
      },
      cancelToken: cancelToken,
      options: Options(
        responseType: ResponseType.stream,
        sendTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 90),
        headers: const {'Accept': 'text/event-stream'},
      ),
    );
    final body = response.data;
    if (body == null) return;

    final lines = body.stream
        .cast<List<int>>()
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    var eventName = 'message';
    var data = '';
    await for (final line in lines) {
      if (line.startsWith(':')) continue; // heartbeat
      if (line.startsWith('event:')) {
        eventName = line.substring(6).trim();
        continue;
      }
      if (line.startsWith('data:')) {
        final chunk = line.substring(5).trimLeft();
        data = data.isEmpty ? chunk : '$data\n$chunk';
        continue;
      }
      if (line.isNotEmpty || data.isEmpty) continue;
      Map<String, dynamic> decoded;
      try {
        final raw = jsonDecode(data);
        decoded = raw is Map ? Map<String, dynamic>.from(raw) : {'value': raw};
      } catch (_) {
        decoded = const {};
      }
      yield MimoStreamEvent(eventName, decoded);
      eventName = 'message';
      data = '';
    }
  }
}
