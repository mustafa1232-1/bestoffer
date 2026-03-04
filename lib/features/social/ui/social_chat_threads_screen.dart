import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_call_screen.dart';
import 'social_chat_thread_screen.dart';
import 'social_profile_screen.dart';
import 'social_relation_requests_screen.dart';
import 'social_story_quick_viewer.dart';

class SocialChatThreadsScreen extends ConsumerStatefulWidget {
  final int? initialThreadId;

  const SocialChatThreadsScreen({super.key, this.initialThreadId});

  @override
  ConsumerState<SocialChatThreadsScreen> createState() =>
      _SocialChatThreadsScreenState();
}

class _SocialChatThreadsScreenState
    extends ConsumerState<SocialChatThreadsScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  final intl.DateFormat _dateFormat = intl.DateFormat('d/M hh:mm a', 'ar');
  Timer? _autoRefreshTimer;

  String _query = '';
  bool _didHandleInitialThread = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      final next = _searchCtrl.text.trim();
      if (next == _query) return;
      setState(() => _query = next);
    });
    Future.microtask(_refreshThreads);
    _autoRefreshTimer = Timer.periodic(const Duration(seconds: 8), (_) {
      if (!mounted) return;
      unawaited(_refreshThreads());
    });
  }

  @override
  void dispose() {
    _autoRefreshTimer?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshThreads() {
    return ref.read(socialControllerProvider.notifier).loadThreads();
  }

  Future<void> _openProfile(SocialAuthor author) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialProfileScreen(
          userId: author.id,
          initialName: author.fullName,
        ),
      ),
    );
  }

  Future<void> _openAvatar(SocialAuthor author) async {
    var stories = ref.read(socialControllerProvider).stories;
    if (stories.isEmpty) {
      await ref
          .read(socialControllerProvider.notifier)
          .loadStories(silent: true);
      if (!mounted) return;
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
      if (!mounted) return;
      return;
    }

    await _openProfile(author);
  }

  Future<void> _openThread(SocialChatThread thread) async {
    await Navigator.of(context).push(
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
  }

  void _tryOpenInitialThread(List<SocialChatThread> threads) {
    final targetId = widget.initialThreadId;
    if (_didHandleInitialThread || targetId == null || targetId <= 0) return;
    final matched = threads
        .where((t) => t.id == targetId)
        .cast<SocialChatThread?>()
        .firstWhere((t) => t != null, orElse: () => null);
    _didHandleInitialThread = true;
    if (matched == null) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_openThread(matched));
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialControllerProvider);

    ref.listen<SocialState>(socialControllerProvider, (previous, next) {
      if (!mounted) return;
      final error = next.error;
      if (error != null && error != previous?.error) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error, textDirection: TextDirection.rtl)),
        );
      }
    });

    final threads = state.threads;
    _tryOpenInitialThread(threads);

    final normalizedQuery = _query.toLowerCase();
    final filtered = normalizedQuery.isEmpty
        ? threads
        : threads
              .where((thread) {
                final name = thread.peer.fullName.toLowerCase();
                final phone = thread.peerPhone.toLowerCase();
                final body = (thread.lastMessage?.body ?? '').toLowerCase();
                return name.contains(normalizedQuery) ||
                    phone.contains(normalizedQuery) ||
                    body.contains(normalizedQuery);
              })
              .toList(growable: false);

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('المحادثات'),
          actions: [
            IconButton(
              tooltip: 'طلبات المتابعة',
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SocialRelationRequestsScreen(),
                  ),
                );
                if (!mounted) return;
                await _refreshThreads();
              },
              icon: const Icon(Icons.person_add_alt_1_rounded),
            ),
            IconButton(
              tooltip: 'تحديث',
              onPressed: _refreshThreads,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
              child: TextField(
                controller: _searchCtrl,
                textInputAction: TextInputAction.search,
                decoration: InputDecoration(
                  hintText: 'ابحث باسم المستخدم أو الرسالة',
                  prefixIcon: const Icon(Icons.search_rounded),
                  suffixIcon: _query.isEmpty
                      ? null
                      : IconButton(
                          tooltip: 'مسح',
                          onPressed: _searchCtrl.clear,
                          icon: const Icon(Icons.close_rounded),
                        ),
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _refreshThreads,
                child: state.loadingThreads && threads.isEmpty
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                    ? ListView(
                        padding: const EdgeInsets.only(top: 90),
                        children: [
                          Icon(
                            Icons.forum_outlined,
                            size: 54,
                            color: Colors.white.withValues(alpha: 0.75),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _query.trim().isEmpty
                                ? 'لا توجد محادثات حالياً.'
                                : 'لا توجد نتائج مطابقة لعبارة البحث.',
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _query.trim().isEmpty
                                ? 'ابدأ محادثة من منشور أو من الملف الشخصي لأي مستخدم.'
                                : 'جرّب اسمًا آخر أو امسح البحث.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.78),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      )
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                        itemCount: filtered.length,
                        separatorBuilder: (_, index) =>
                            const SizedBox(height: 10),
                        itemBuilder: (_, index) {
                          final thread = filtered[index];
                          final lastBody =
                              thread.lastMessage?.body.trim() ?? '';
                          final lastAt = thread.lastMessageAt;
                          final subtitle = lastBody.isNotEmpty
                              ? lastBody
                              : 'ابدأ المحادثة الآن';

                          return Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: () => _openThread(thread),
                              child: Ink(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(16),
                                  gradient: LinearGradient(
                                    begin: Alignment.topRight,
                                    end: Alignment.bottomLeft,
                                    colors: [
                                      Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.92),
                                      Theme.of(context)
                                          .colorScheme
                                          .surfaceContainerHighest
                                          .withValues(alpha: 0.55),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(
                                    10,
                                    9,
                                    8,
                                    9,
                                  ),
                                  child: Row(
                                    children: [
                                      InkWell(
                                        onTap: () => _openAvatar(thread.peer),
                                        borderRadius: BorderRadius.circular(
                                          999,
                                        ),
                                        child: CircleAvatar(
                                          radius: 24,
                                          backgroundImage:
                                              (thread.peer.imageUrl ?? '')
                                                  .trim()
                                                  .isNotEmpty
                                              ? NetworkImage(
                                                  thread.peer.imageUrl!,
                                                )
                                              : null,
                                          child:
                                              (thread.peer.imageUrl ?? '')
                                                  .trim()
                                                  .isEmpty
                                              ? const Icon(Icons.person_outline)
                                              : null,
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.end,
                                          children: [
                                            InkWell(
                                              onTap: () =>
                                                  _openProfile(thread.peer),
                                              borderRadius:
                                                  BorderRadius.circular(8),
                                              child: Text(
                                                thread.peer.fullName,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 15,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              subtitle,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontWeight: FontWeight.w600,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.88),
                                                height: 1.25,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Column(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          if (lastAt != null)
                                            Text(
                                              _dateFormat.format(
                                                lastAt.toLocal(),
                                              ),
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: Theme.of(context)
                                                    .colorScheme
                                                    .onSurface
                                                    .withValues(alpha: 0.7),
                                              ),
                                            )
                                          else
                                            const SizedBox(height: 16),
                                          IconButton(
                                            tooltip: 'اتصال',
                                            onPressed: () async {
                                              await Navigator.of(context).push(
                                                MaterialPageRoute<void>(
                                                  builder: (_) =>
                                                      SocialCallScreen(
                                                        threadId: thread.id,
                                                        isCaller: true,
                                                        remoteDisplayName:
                                                            thread
                                                                .peer
                                                                .fullName,
                                                      ),
                                                ),
                                              );
                                            },
                                            icon: const Icon(
                                              Icons.call_outlined,
                                            ),
                                            style: IconButton.styleFrom(
                                              minimumSize: const Size(36, 36),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
