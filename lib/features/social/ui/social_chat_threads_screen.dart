import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../state/social_controller.dart';
import 'social_chat_thread_screen.dart';

class SocialChatThreadsScreen extends ConsumerWidget {
  const SocialChatThreadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(socialControllerProvider);
    final dateFormat = intl.DateFormat('d/M hh:mm a', 'ar');

    Future<void> refresh() async {
      await ref.read(socialControllerProvider.notifier).loadThreads();
    }

    return Scaffold(
      appBar: AppBar(title: const Text('محادثات بسماية')),
      body: RefreshIndicator(
        onRefresh: refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
          children: [
            if (state.loadingThreads)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (state.threads.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 80),
                child: Center(
                  child: Text(
                    'لا توجد محادثات حاليًا. ابدأ محادثة من أي منشور.',
                    textDirection: TextDirection.rtl,
                  ),
                ),
              )
            else
              ...state.threads.map((thread) {
                final lastBody = thread.lastMessage?.body.trim() ?? '';
                final time = thread.lastMessageAt;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    contentPadding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                    leading: CircleAvatar(
                      backgroundImage:
                          (thread.peer.imageUrl ?? '').trim().isNotEmpty
                          ? NetworkImage(thread.peer.imageUrl!)
                          : null,
                      child: (thread.peer.imageUrl ?? '').trim().isEmpty
                          ? const Icon(Icons.person_outline)
                          : null,
                    ),
                    title: Text(
                      thread.peer.fullName,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (lastBody.isNotEmpty)
                          Text(
                            lastBody,
                            textDirection: TextDirection.rtl,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          )
                        else
                          const Text(
                            'لا توجد رسالة بعد',
                            textDirection: TextDirection.rtl,
                          ),
                        if (time != null)
                          Text(
                            dateFormat.format(time.toLocal()),
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurface.withValues(alpha: 0.65),
                            ),
                          ),
                      ],
                    ),
                    trailing: IconButton(
                      tooltip: 'اتصال',
                      onPressed: () async {
                        final phone = thread.peerPhone.trim();
                        if (phone.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'رقم الهاتف غير متوفر لهذا المستخدم.',
                              ),
                            ),
                          );
                          return;
                        }
                        final ok = await launchUrl(Uri.parse('tel:$phone'));
                        if (!ok && context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('تعذر فتح الاتصال.')),
                          );
                        }
                      },
                      icon: const Icon(Icons.call_outlined),
                    ),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SocialChatThreadScreen(
                            threadId: thread.id,
                            peerName: thread.peer.fullName,
                            peerPhone: thread.peerPhone,
                          ),
                        ),
                      );
                    },
                  ),
                );
              }),
          ],
        ),
      ),
    );
  }
}
