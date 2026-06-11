import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/order_chat_api.dart';
import '../models/order_chat_message_model.dart';

final orderChatApiProvider = Provider<OrderChatApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return OrderChatApi(dio);
});

class OrderChatScreen extends ConsumerStatefulWidget {
  final int orderId;
  final String? title;

  const OrderChatScreen({super.key, required this.orderId, this.title});

  @override
  ConsumerState<OrderChatScreen> createState() => _OrderChatScreenState();
}

class _OrderChatScreenState extends ConsumerState<OrderChatScreen> {
  final TextEditingController _messageCtrl = TextEditingController();
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();
  Timer? _pollTimer;

  bool _loading = true;
  bool _sending = false;
  bool _open = true;
  bool _canWrite = false;
  String? _error;
  final Map<String, String> _fieldErrors = <String, String>{};
  List<OrderChatMessageModel> _messages = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(() => _load());
    _pollTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_open) return;
      unawaited(_load(silent: true));
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _messageCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final payload = await ref
          .read(orderChatApiProvider)
          .listMessages(widget.orderId, limit: 200);
      final rawMessages = List<dynamic>.from(
        payload['messages'] as List? ?? const [],
      );
      final messages = rawMessages
          .map(
            (e) => OrderChatMessageModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .where((m) => m.id > 0 && m.message.isNotEmpty)
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _open = payload['open'] == true;
        _canWrite = payload['canWrite'] == true;
        _messages = messages;
      });
    } catch (e) {
      if (!mounted) return;
      final mapped = mapAnyError(
        e,
        fallback: 'تعذر تحميل محادثة الطلب.',
        appendRequestId: true,
      );
      setState(() {
        _loading = false;
        _error = mapped;
      });
    }
  }

  Future<void> _send() async {
    final text = _messageCtrl.text.trim();
    if (_sending || !_canWrite) return;
    if (text.isEmpty) {
      setState(() {
        _fieldErrors['messageText'] = context.l10n.validationMessageRequired;
      });
      await _scrollCoordinator.focusFirstError(const ['messageText']);
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
      _fieldErrors.clear();
    });

    try {
      await ref.read(orderChatApiProvider).sendMessage(widget.orderId, text);
      _messageCtrl.clear();
      await _load(silent: true);
      if (!mounted) return;
      setState(() => _sending = false);
    } catch (e) {
      if (!mounted) return;
      final mapped = mapAnyError(
        e,
        fallback: 'تعذر إرسال الرسالة.',
        appendRequestId: true,
      );
      final parsed = parseBackendFieldErrors(e);
      setState(() {
        _sending = false;
        if (parsed.fieldCodes.containsKey('messageText')) {
          _fieldErrors['messageText'] = resolveFormFieldError(
            l10n: context.l10n,
            field: 'messageText',
            code: parsed.codeFor('messageText'),
            fieldLabel: context.l10n.commonMessage,
          );
          _error = null;
        } else {
          _error = mapped;
        }
      });
      if (_fieldErrors.isNotEmpty) {
        await _scrollCoordinator.focusFirstError(_fieldErrors.keys);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final currentUserId = auth.user?.id;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? 'محادثة الطلب #${widget.orderId}'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _load(),
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
          ),
        ],
      ),
      body: Column(
        children: [
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.red.withValues(alpha: 0.14),
                border: Border.all(color: Colors.red.withValues(alpha: 0.42)),
              ),
              child: Text(_error!, textDirection: TextDirection.rtl),
            ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                ? Center(
                    child: Text(
                      _open
                          ? 'لا توجد رسائل بعد.'
                          : 'تم إغلاق هذه المحادثة بعد إكمال الطلب.',
                      textDirection: TextDirection.rtl,
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final item = _messages[index];
                      final mine =
                          currentUserId != null &&
                          item.senderUserId == currentUserId;
                      return _ChatBubble(message: item, isMine: mine);
                    },
                  ),
          ),
          if (_open && _canWrite)
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _messageCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor(
                          'messageText',
                        ),
                        minLines: 1,
                        maxLines: 4,
                        textDirection: TextDirection.rtl,
                        onChanged: (_) {
                          if (_fieldErrors.remove('messageText') != null) {
                            setState(() {});
                          }
                        },
                        decoration: const InputDecoration(
                          hintText: 'اكتب رسالتك...',
                          border: OutlineInputBorder(),
                        ).copyWith(errorText: _fieldErrors['messageText']),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.icon(
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: const Text('إرسال'),
                    ),
                  ],
                ),
              ),
            )
          else
            SafeArea(
              top: false,
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
                color: Colors.black.withValues(alpha: 0.08),
                child: const Text(
                  'تم إغلاق محادثة الطلب بعد الإنهاء النهائي.',
                  textDirection: TextDirection.rtl,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final OrderChatMessageModel message;
  final bool isMine;

  const _ChatBubble({required this.message, required this.isMine});

  @override
  Widget build(BuildContext context) {
    final time = message.createdAt == null
        ? '--:--'
        : DateFormat('HH:mm').format(message.createdAt!.toLocal());

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.78,
        ),
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: isMine
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.24)
              : Colors.white.withValues(alpha: 0.08),
          border: Border.all(
            color: isMine
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.46)
                : Colors.white.withValues(alpha: 0.18),
          ),
        ),
        child: Column(
          crossAxisAlignment: isMine
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(message.message, textDirection: TextDirection.rtl),
            const SizedBox(height: 4),
            Text(
              time,
              style: const TextStyle(fontSize: 11, color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }
}
