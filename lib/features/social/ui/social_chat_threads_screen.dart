import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_chat_thread_screen.dart';
import 'social_profile_screen.dart';
import 'social_story_quick_viewer.dart';

class SocialChatThreadsScreen extends ConsumerWidget {
  const SocialChatThreadsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(socialControllerProvider);
    final dateFormat = intl.DateFormat('d/M hh:mm a', 'ar');

    Future<void> refresh() async {
      await ref.read(socialControllerProvider.notifier).loadThreads();
    }

    Future<void> openProfile(SocialAuthor author) async {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SocialProfileScreen(
            userId: author.id,
            initialName: author.fullName,
          ),
        ),
      );
    }

    Future<void> openAvatar(SocialAuthor author) async {
      var stories = ref.read(socialControllerProvider).stories;
      if (stories.isEmpty) {
        await ref
            .read(socialControllerProvider.notifier)
            .loadStories(silent: true);
        stories = ref.read(socialControllerProvider).stories;
      }
      SocialStoryGroup? group;
      for (final item in stories) {
        if (item.userId == author.id && item.stories.isNotEmpty) {
          group = item;
          break;
        }
      }
      if (group != null) {
        await showSocialStoryQuickViewer(
          context: context,
          group: group,
          onStoryViewed: (storyId) => ref
              .read(socialControllerProvider.notifier)
              .markStoryViewed(storyId),
        );
        return;
      }
      await openProfile(author);
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
                    'لا توجد محادثات حالياً. ابدأ محادثة من أي منشور.',
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
                    leading: InkWell(
                      onTap: () => openAvatar(thread.peer),
                      borderRadius: BorderRadius.circular(999),
                      child: CircleAvatar(
                        backgroundImage:
                            (thread.peer.imageUrl ?? '').trim().isNotEmpty
                            ? NetworkImage(thread.peer.imageUrl!)
                            : null,
                        child: (thread.peer.imageUrl ?? '').trim().isEmpty
                            ? const Icon(Icons.person_outline)
                            : null,
                      ),
                    ),
                    title: InkWell(
                      onTap: () => openProfile(thread.peer),
                      borderRadius: BorderRadius.circular(8),
                      child: Text(
                        thread.peer.fullName,
                        textDirection: TextDirection.rtl,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
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
                            peerUserId: thread.peer.id,
                            peerImageUrl: thread.peer.imageUrl,
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
