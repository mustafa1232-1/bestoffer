import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';

import '../../../core/diagnostics/build_info.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../orders/state/cart_controller.dart';
import '../mimo_character.dart';
import 'mimo_chat_api.dart';

enum MimoSender { user, mimo }

/// A card/button block Mimo attached to his answer.
class MimoUiBlock {
  const MimoUiBlock(this.data);

  final Map<String, dynamic> data;

  String get type => '${data['type'] ?? ''}';

  List<Map<String, dynamic>> get items => [
    for (final e in (data['items'] as List? ?? const []))
      if (e is Map) Map<String, dynamic>.from(e),
  ];

  List<String> get options => [
    for (final e in (data['options'] as List? ?? const [])) '$e',
  ];

  String? get title {
    final t = '${data['title'] ?? ''}'.trim();
    return t.isEmpty ? null : t;
  }
}

class MimoChatMessage {
  const MimoChatMessage({
    required this.id,
    required this.sender,
    this.text = '',
    this.status,
    this.blocks = const [],
    this.streaming = false,
    this.refs,
    this.failed = false,
    this.feedback,
    this.photos = const [],
  });

  final int id;
  final MimoSender sender;

  /// Raw text (Mimo's lisp is applied when rendering).
  final String text;

  /// What Mimo is doing right now ("searching grills...").
  final String? status;
  final List<MimoUiBlock> blocks;
  final bool streaming;

  /// Compact memory of the cards shown, sent back so Mimo remembers them.
  final String? refs;
  final bool failed;

  /// true = 👍, false = 👎, null = not rated.
  final bool? feedback;

  /// Photos the user attached (shown as thumbnails in their bubble).
  final List<Uint8List> photos;

  MimoChatMessage copyWith({
    String? text,
    String? status,
    bool clearStatus = false,
    List<MimoUiBlock>? blocks,
    bool? streaming,
    String? refs,
    bool? failed,
    bool? feedback,
  }) {
    return MimoChatMessage(
      id: id,
      sender: sender,
      text: text ?? this.text,
      status: clearStatus ? null : (status ?? this.status),
      blocks: blocks ?? this.blocks,
      streaming: streaming ?? this.streaming,
      refs: refs ?? this.refs,
      failed: failed ?? this.failed,
      feedback: feedback ?? this.feedback,
      photos: photos,
    );
  }
}

class MimoChatState {
  const MimoChatState({
    this.messages = const [],
    this.sending = false,
    this.mood = MimoMood.happy,
    this.summary = '',
    this.summarizedThroughId = 0,
  });

  final List<MimoChatMessage> messages;
  final bool sending;
  final MimoMood mood;

  /// Mimo's running summary of the older part of a long conversation.
  final String summary;

  /// Messages up to this id are already inside [summary] (not re-sent).
  final int summarizedThroughId;

  MimoChatState copyWith({
    List<MimoChatMessage>? messages,
    bool? sending,
    MimoMood? mood,
    String? summary,
    int? summarizedThroughId,
  }) {
    return MimoChatState(
      messages: messages ?? this.messages,
      sending: sending ?? this.sending,
      mood: mood ?? this.mood,
      summary: summary ?? this.summary,
      summarizedThroughId: summarizedThroughId ?? this.summarizedThroughId,
    );
  }
}

MimoMood mimoMoodFromName(String? name) {
  for (final m in MimoMood.values) {
    if (m.name == name) return m;
  }
  return MimoMood.happy;
}

/// The conversation with Mimo. Kept alive for the app session so reopening
/// the chat continues where the user left off.
final mimoChatControllerProvider =
    StateNotifierProvider<MimoChatController, MimoChatState>(
      (ref) => MimoChatController(ref),
    );

class MimoChatController extends StateNotifier<MimoChatState> {
  MimoChatController(this.ref) : super(const MimoChatState());

  final Ref ref;
  int _nextId = 1;
  CancelToken? _cancel;
  StreamSubscription<MimoStreamEvent>? _sub;

  void _replaceMessage(int id, MimoChatMessage Function(MimoChatMessage) f) {
    state = state.copyWith(
      messages: [for (final m in state.messages) m.id == id ? f(m) : m],
    );
  }

  /// A local Mimo line (no server round-trip), e.g. after adding to cart.
  void sayLocally(String text, {MimoMood mood = MimoMood.happy}) {
    state = state.copyWith(
      mood: mood,
      messages: [
        ...state.messages,
        MimoChatMessage(id: _nextId++, sender: MimoSender.mimo, text: text),
      ],
    );
  }

  void setMood(MimoMood mood) => state = state.copyWith(mood: mood);

  /// 👍/👎 — sent to the server so Mimo learns what helps.
  void rate(int messageId, {required bool up}) {
    final index = state.messages.indexWhere((m) => m.id == messageId);
    if (index < 0) return;
    final answer = state.messages[index];
    if (answer.feedback != null) return;
    final question = state.messages
        .take(index)
        .lastWhere(
          (m) => m.sender == MimoSender.user,
          orElse: () => const MimoChatMessage(id: 0, sender: MimoSender.user),
        )
        .text;
    _replaceMessage(messageId, (m) => m.copyWith(feedback: up));
    state = state.copyWith(mood: up ? MimoMood.love : MimoMood.sad);
    ref
        .read(mimoChatApiProvider)
        .feedback(
          up: up,
          question: question,
          answer: answer.text,
          refs: answer.refs,
        );
  }

  /// Tells the server the user accepted Mimo's suggestion (learning signal).
  void reportCartAdded(List<Map<String, dynamic>> items) {
    ref.read(mimoChatApiProvider).cartAdded(items);
  }

  /// Messages sent to Mimo this turn (older ones live in the summary).
  List<MimoChatMessage> _sentForTurn = const [];

  List<Map<String, dynamic>> _history() {
    final out = <Map<String, dynamic>>[];
    final sent = <MimoChatMessage>[];
    for (final m in state.messages) {
      if (m.id <= state.summarizedThroughId) continue;
      if (m.streaming || m.failed || m.text.trim().isEmpty) continue;
      sent.add(m);
      out.add({
        'role': m.sender == MimoSender.user ? 'user' : 'assistant',
        'content': m.text,
        if (m.refs != null && m.refs!.isNotEmpty) 'refs': m.refs,
      });
    }
    const max = 40;
    _sentForTurn = sent.length > max ? sent.sublist(sent.length - max) : sent;
    return out.length > max ? out.sublist(out.length - max) : out;
  }

  Map<String, dynamic> _context() {
    final cart = ref.read(cartControllerProvider);
    return {
      'cart': {
        'items': cart.totalItems,
        'stores': cart.storeIds.length,
        'total': cart.total.round(),
      },
      // Helps Mimo diagnose app problems (no personal data).
      'client': {
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'appVersion': BuildInfo.compileTime.appVersion,
      },
    };
  }

  Future<void> send(
    String text, {
    List<LocalImageFile> photos = const [],
  }) async {
    var clean = text.trim();
    if ((clean.isEmpty && photos.isEmpty) || state.sending) return;
    final lang0 = ref.read(appSettingsControllerProvider).locale.languageCode;
    if (clean.isEmpty) clean = lang0 == 'en' ? '📷 A photo' : '📷 صورة';
    final userMsg = MimoChatMessage(
      id: _nextId++,
      sender: MimoSender.user,
      text: clean,
      photos: [
        for (final p in photos)
          if (p.hasBytes) p.bytes!,
      ],
    );
    final reply = MimoChatMessage(
      id: _nextId++,
      sender: MimoSender.mimo,
      streaming: true,
    );
    state = state.copyWith(
      messages: [...state.messages, userMsg, reply],
      sending: true,
      mood: MimoMood.thinking,
    );
    final history = _history();
    final lang = lang0;

    final attachments = <Map<String, dynamic>>[];
    if (photos.isNotEmpty) {
      _replaceMessage(
        reply.id,
        (m) => m.copyWith(
          status: lang == 'en' ? 'Uploading your photo…' : 'دا أرفع الصورة…',
        ),
      );
      try {
        for (final p in photos.take(4)) {
          attachments.add(await ref.read(mimoChatApiProvider).uploadPhoto(p));
        }
      } catch (_) {
        _replaceMessage(
          reply.id,
          (m) => m.copyWith(
            text: lang == 'en'
                ? "I couldn't upload the photo, try again"
                : 'ما گدرت أرفع الصورة، جرب مرة ثانية',
            streaming: false,
            clearStatus: true,
            failed: true,
          ),
        );
        state = state.copyWith(sending: false, mood: MimoMood.sad);
        return;
      }
    }

    _cancel = CancelToken();
    final done = Completer<void>();
    _sub = ref
        .read(mimoChatApiProvider)
        .chat(
          messages: history,
          lang: lang == 'en' ? 'en' : 'ar',
          context: _context(),
          summary: state.summary,
          attachments: attachments,
          cancelToken: _cancel,
        )
        .listen(
          (e) => _onEvent(reply.id, e),
          onError: (Object error) {
            _replaceMessage(
              reply.id,
              (m) => m.copyWith(
                text: m.text.isNotEmpty
                    ? m.text
                    : (lang == 'en'
                          ? "I couldn't reach my brain, try again"
                          : 'ما گدرت أوصل لدماغي، جرب مرة ثانية'),
                streaming: false,
                clearStatus: true,
                failed: m.text.isEmpty,
              ),
            );
            state = state.copyWith(sending: false, mood: MimoMood.sad);
            if (!done.isCompleted) done.complete();
          },
          onDone: () {
            _replaceMessage(
              reply.id,
              (m) => m.copyWith(streaming: false, clearStatus: true),
            );
            if (state.sending) state = state.copyWith(sending: false);
            if (!done.isCompleted) done.complete();
          },
          cancelOnError: true,
        );
    await done.future;
  }

  void _onEvent(int id, MimoStreamEvent e) {
    switch (e.event) {
      case 'status':
        _replaceMessage(id, (m) => m.copyWith(status: '${e.data['text']}'));
      case 'delta':
        _replaceMessage(
          id,
          (m) => m.copyWith(
            text: '${m.text}${e.data['text'] ?? ''}',
            clearStatus: true,
          ),
        );
        if (state.mood == MimoMood.thinking) {
          state = state.copyWith(mood: MimoMood.happy);
        }
      case 'ui':
        final block = MimoUiBlock(e.data);
        if (block.type == 'mood') {
          state = state.copyWith(mood: mimoMoodFromName('${e.data['mood']}'));
        } else {
          _replaceMessage(id, (m) => m.copyWith(blocks: [...m.blocks, block]));
        }
      case 'done':
        final refs = '${e.data['refs'] ?? ''}';
        final summarized = (e.data['summarized'] as num?)?.toInt() ?? 0;
        if (summarized > 0 && summarized <= _sentForTurn.length) {
          state = state.copyWith(
            summary: '${e.data['summary'] ?? state.summary}',
            summarizedThroughId: _sentForTurn[summarized - 1].id,
          );
        }
        _replaceMessage(
          id,
          (m) => m.copyWith(streaming: false, clearStatus: true, refs: refs),
        );
        state = state.copyWith(sending: false);
    }
  }

  /// Stops Mimo mid-answer.
  void stop() {
    _cancel?.cancel();
    _sub?.cancel();
    state = state.copyWith(
      sending: false,
      messages: [
        for (final m in state.messages)
          m.streaming ? m.copyWith(streaming: false, clearStatus: true) : m,
      ],
    );
  }

  void reset() {
    stop();
    state = const MimoChatState();
  }

  @override
  void dispose() {
    _cancel?.cancel();
    _sub?.cancel();
    super.dispose();
  }
}
