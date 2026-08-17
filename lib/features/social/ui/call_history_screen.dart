import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'social_call_screen.dart' show SocialCallScreen, socialCallApiProvider;
import 'social_chat_thread_screen.dart' show SocialChatThreadScreen;

final _callHistoryProvider =
    FutureProvider.autoDispose<List<Map<String, dynamic>>>((ref) async {
  final api = ref.read(socialCallApiProvider);
  return api.listCallHistory(limit: 100);
});

/// سجل المكالمات: الفائتة والصادرة والواردة والسابقة.
class CallHistoryScreen extends ConsumerWidget {
  const CallHistoryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_callHistoryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المكالمات')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => const Center(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Text(
              'تعذّر تحميل سجل المكالمات.',
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (calls) {
          if (calls.isEmpty) {
            return const Center(child: Text('لا توجد مكالمات بعد'));
          }
          return RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(_callHistoryProvider);
              await ref.read(_callHistoryProvider.future);
            },
            child: ListView.separated(
              itemCount: calls.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) =>
                  _CallHistoryTile(call: calls[index], allCalls: calls),
            ),
          );
        },
      ),
    );
  }
}

IconData _directionIcon(String direction, bool missed) {
  if (missed) return Icons.call_missed_rounded;
  if (direction == 'outgoing') return Icons.call_made_rounded;
  return Icons.call_received_rounded;
}

Color _directionColor(String direction, bool missed) {
  if (missed) return Colors.redAccent;
  if (direction == 'outgoing') return Colors.green;
  return Colors.blueAccent;
}

String _callMeta(Map<String, dynamic> call) {
  final createdAt = DateTime.tryParse((call['createdAt'] ?? '').toString());
  final durationSec = (call['durationSec'] as num?)?.toInt();
  final parts = <String>[];
  if (createdAt != null) {
    parts.add(DateFormat('yyyy/MM/dd  HH:mm').format(createdAt.toLocal()));
  }
  if (durationSec != null && durationSec > 0) {
    final m = durationSec ~/ 60;
    final s = durationSec % 60;
    parts.add('$m:${s.toString().padLeft(2, '0')}');
  }
  return parts.join('  •  ');
}

String _peerNameOf(Map<String, dynamic> call) {
  final raw = (call['peerName'] ?? '').toString().trim();
  return raw.isNotEmpty ? raw : 'مستخدم';
}

class _CallHistoryTile extends StatelessWidget {
  final Map<String, dynamic> call;
  final List<Map<String, dynamic>> allCalls;
  const _CallHistoryTile({required this.call, required this.allCalls});

  void _redial(BuildContext context) {
    final threadId = (call['threadId'] as num?)?.toInt();
    if (threadId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialCallScreen(
          threadId: threadId,
          isCaller: true,
          remoteDisplayName: _peerNameOf(call),
        ),
      ),
    );
  }

  void _openChat(BuildContext context) {
    final threadId = (call['threadId'] as num?)?.toInt();
    if (threadId == null) return;
    final imageUrl = (call['peerImageUrl'] ?? '').toString();
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialChatThreadScreen(
          threadId: threadId,
          peerName: _peerNameOf(call),
          peerUserId: (call['peerUserId'] as num?)?.toInt(),
          peerImageUrl: imageUrl.isNotEmpty ? imageUrl : null,
        ),
      ),
    );
  }

  void _showPeerHistory(BuildContext context) {
    final peerUserId = (call['peerUserId'] as num?)?.toInt();
    final peerName = _peerNameOf(call);
    final threadId = (call['threadId'] as num?)?.toInt();
    final entries = allCalls.where((c) {
      final cid = (c['peerUserId'] as num?)?.toInt();
      final tid = (c['threadId'] as num?)?.toInt();
      if (peerUserId != null && cid != null) return cid == peerUserId;
      return tid != null && tid == threadId;
    }).toList(growable: false);

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(sheetContext).size.height * 0.6,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: Text(
                  'سجل المكالمات مع $peerName',
                  style: Theme.of(sheetContext).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: entries.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final direction = (entry['direction'] ?? '').toString();
                    final missed = entry['missed'] == true;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        _directionIcon(direction, missed),
                        color: _directionColor(direction, missed),
                        size: 20,
                      ),
                      title: Text(_callMeta(entry)),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openOptions(BuildContext context) {
    final threadId = (call['threadId'] as num?)?.toInt();
    final peerName = _peerNameOf(call);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      peerName,
                      style: Theme.of(sheetContext).textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w800),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            if (threadId != null)
              ListTile(
                leading: const Icon(Icons.call_rounded, color: Colors.green),
                title: const Text('إعادة الاتصال'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _redial(context);
                },
              ),
            if (threadId != null)
              ListTile(
                leading: const Icon(Icons.chat_bubble_outline_rounded),
                title: const Text('فتح المحادثة'),
                onTap: () {
                  Navigator.of(sheetContext).pop();
                  _openChat(context);
                },
              ),
            ListTile(
              leading: const Icon(Icons.history_rounded),
              title: Text('سجل المكالمات مع $peerName'),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _showPeerHistory(context);
              },
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final direction = (call['direction'] ?? '').toString();
    final missed = call['missed'] == true;
    final peerName = _peerNameOf(call);
    final imageUrl = (call['peerImageUrl'] ?? '').toString();
    final threadId = (call['threadId'] as num?)?.toInt();

    return ListTile(
      onTap: () => _openOptions(context),
      leading: CircleAvatar(
        backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
        child: imageUrl.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(peerName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Icon(
            _directionIcon(direction, missed),
            size: 16,
            color: _directionColor(direction, missed),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _callMeta(call),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      trailing: threadId == null
          ? null
          : IconButton(
              icon: const Icon(Icons.call_rounded),
              tooltip: 'اتصال',
              onPressed: () => _redial(context),
            ),
    );
  }
}
