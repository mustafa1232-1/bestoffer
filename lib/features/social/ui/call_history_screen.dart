import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' show DateFormat;

import 'social_call_screen.dart' show SocialCallScreen, socialCallApiProvider;

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
                  _CallHistoryTile(call: calls[index]),
            ),
          );
        },
      ),
    );
  }
}

class _CallHistoryTile extends StatelessWidget {
  final Map<String, dynamic> call;
  const _CallHistoryTile({required this.call});

  @override
  Widget build(BuildContext context) {
    final direction = (call['direction'] ?? '').toString();
    final missed = call['missed'] == true;
    final rawName = (call['peerName'] ?? '').toString().trim();
    final peerName = rawName.isNotEmpty ? rawName : 'مستخدم';
    final imageUrl = (call['peerImageUrl'] ?? '').toString();
    final threadId = (call['threadId'] as num?)?.toInt();
    final createdAt = DateTime.tryParse((call['createdAt'] ?? '').toString());
    final durationSec = (call['durationSec'] as num?)?.toInt();

    final IconData icon;
    final Color color;
    if (missed) {
      icon = Icons.call_missed_rounded;
      color = Colors.redAccent;
    } else if (direction == 'outgoing') {
      icon = Icons.call_made_rounded;
      color = Colors.green;
    } else {
      icon = Icons.call_received_rounded;
      color = Colors.blueAccent;
    }

    final parts = <String>[];
    if (createdAt != null) {
      parts.add(DateFormat('yyyy/MM/dd  HH:mm').format(createdAt.toLocal()));
    }
    if (durationSec != null && durationSec > 0) {
      final m = durationSec ~/ 60;
      final s = durationSec % 60;
      parts.add('$m:${s.toString().padLeft(2, '0')}');
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundImage: imageUrl.isNotEmpty ? NetworkImage(imageUrl) : null,
        child: imageUrl.isEmpty ? const Icon(Icons.person) : null,
      ),
      title: Text(peerName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              parts.join('  •  '),
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
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SocialCallScreen(
                      threadId: threadId,
                      isCaller: true,
                      remoteDisplayName: peerName,
                    ),
                  ),
                );
              },
            ),
    );
  }
}
