import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/notifications/notification_navigation.dart';
import '../../../core/widgets/maslaki_back_button.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/models/app_notification_model.dart';
import '../../notifications/state/notifications_controller.dart';
import '../state/social_controller.dart';
import 'social_message_requests_screen.dart';
import 'social_relation_requests_screen.dart';
import 'widgets/basmaya_shell_bars.dart';

class SocialActivityScreen extends ConsumerStatefulWidget {
  final String? title;
  final String initialFilterKey;

  const SocialActivityScreen({
    super.key,
    this.title,
    this.initialFilterKey = 'all',
  });

  @override
  ConsumerState<SocialActivityScreen> createState() =>
      _SocialActivityScreenState();
}

class _SocialActivityScreenState extends ConsumerState<SocialActivityScreen> {
  bool _unreadOnly = false;
  late String _filter;
  bool _loadingRequests = true;
  int _incomingRelationRequests = 0;
  int _messageRequests = 0;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilterKey;
    Future.microtask(_bootstrap);
  }

  Future<void> _bootstrap() async {
    final controller = ref.read(notificationsControllerProvider.notifier);
    controller.startRealtime();
    await Future.wait([controller.loadNotifications(), _loadRequestsMeta()]);
  }

  Future<void> _refresh() async {
    await Future.wait([
      ref.read(notificationsControllerProvider.notifier).loadNotifications(),
      _loadRequestsMeta(),
    ]);
  }

  Future<void> _loadRequestsMeta() async {
    try {
      final api = ref.read(socialApiProvider);
      final incoming = await api.listIncomingRelationRequests(limit: 100);
      final messages = await api.listChatRequests();
      if (!mounted) return;
      final incomingRaw = List<dynamic>.from(
        incoming['requests'] as List? ?? const [],
      );
      final messageRaw = List<dynamic>.from(
        messages['threads'] as List? ?? const [],
      );
      setState(() {
        _incomingRelationRequests = incomingRaw.length;
        _messageRequests = messageRaw.length;
        _loadingRequests = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loadingRequests = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    ref.listen<NotificationsState>(notificationsControllerProvider, (
      previous,
      next,
    ) {
      if (!mounted) return;
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    final state = ref.watch(notificationsControllerProvider);
    final source = ref.watch(socialActivityNotificationsProvider);
    final filtered = _applyFilters(source);
    final grouped = _groupByAge(filtered);
    final stats = _SocialActivityStats.fromNotifications(source);

    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      drawer: const MaslakiBasmayaDrawer(),
      appBar: MaslakiTopBar(
        title: widget.title?.trim().isNotEmpty == true
            ? widget.title!.trim()
            : l10n.socialActivityTitle,
        subtitle: context.lt(
          ar: 'الإشعارات والتفاعلات وطلبات الرسائل في شاشة واحدة.',
          en: 'Notifications, interactions, and message requests in one screen.',
        ),
        leading: canPop
            ? const MaslakiBackButton(fallbackTabIndex: 2)
            : const MaslakiUserDrawerButton(openStartDrawer: true),
        actions: [
          if (canPop) const MaslakiUserDrawerButton(openStartDrawer: true),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
          TextButton(
            onPressed: state.marking
                ? null
                : () => ref
                      .read(notificationsControllerProvider.notifier)
                      .markAllRead(),
            child: Text(
              l10n.notificationsMarkAll,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          children: [
            _ActivitySummaryRow(
              likesCount: stats.likes,
              commentsCount: stats.comments,
              mentionsCount: stats.mentions,
              unreadCount: stats.unread,
              onOpenLikes: () => setState(() => _filter = 'likes'),
              onOpenComments: () => setState(() => _filter = 'comments'),
              onOpenMentions: () => setState(() => _filter = 'mentions'),
              onOpenUnread: () => setState(() => _unreadOnly = !_unreadOnly),
            ),
            const SizedBox(height: 12),
            _RequestsStrip(
              loading: _loadingRequests,
              relationCount: _incomingRelationRequests,
              messageCount: _messageRequests,
              onOpenRelations: _openRelationRequests,
              onOpenMessages: _openMessageRequests,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 42,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: _buildFilterChips(stats),
              ),
            ),
            const SizedBox(height: 14),
            if (state.loading && source.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 140),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (filtered.isEmpty)
              _EmptySocialActivityState(
                title: l10n.socialActivityEmptyTitle,
                body: l10n.socialActivityEmptyBody,
              )
            else
              ...grouped.expand(
                (section) => <Widget>[
                  _ActivitySectionHeader(label: section.label),
                  const SizedBox(height: 8),
                  ...section.items.map(
                    (notification) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SocialActivityTile(
                        notification: notification,
                        onTap: () => _openNotification(notification),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFilterChips(_SocialActivityStats stats) {
    final l10n = context.l10n;
    final specs = <_ActivityFilterSpec>[
      _ActivityFilterSpec('all', l10n.commonAll, stats.all, Icons.apps_rounded),
      _ActivityFilterSpec(
        'likes',
        l10n.socialActivityLikes,
        stats.likes,
        Icons.favorite_outline_rounded,
      ),
      _ActivityFilterSpec(
        'comments',
        l10n.commonComments,
        stats.comments,
        Icons.mode_comment_outlined,
      ),
      _ActivityFilterSpec(
        'mentions',
        l10n.socialActivityMentions,
        stats.mentions,
        Icons.alternate_email_rounded,
      ),
      _ActivityFilterSpec(
        'reels',
        l10n.socialActivityReels,
        stats.reels,
        Icons.play_circle_outline_rounded,
      ),
      _ActivityFilterSpec(
        'posts',
        l10n.socialActivityPosts,
        stats.posts,
        Icons.grid_view_rounded,
      ),
      _ActivityFilterSpec(
        'stories',
        l10n.socialActivityStories,
        stats.stories,
        Icons.auto_stories_rounded,
      ),
      _ActivityFilterSpec(
        'relations',
        l10n.socialActivityRelations,
        stats.relations,
        Icons.people_outline_rounded,
      ),
    ];
    return specs
        .map(
          (spec) => Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: FilterChip(
              selected: _filter == spec.key,
              showCheckmark: false,
              avatar: Icon(spec.icon, size: 16),
              label: Text('${spec.label} ${spec.count}'),
              onSelected: (_) => setState(() => _filter = spec.key),
            ),
          ),
        )
        .toList(growable: false);
  }

  List<AppNotificationModel> _applyFilters(List<AppNotificationModel> source) {
    return source
        .where((notification) {
          final type = notification.type.toLowerCase();
          if (_unreadOnly && notification.isRead) return false;
          switch (_filter) {
            case 'likes':
              return type.contains('.like');
            case 'comments':
              return type.contains('.comment');
            case 'mentions':
              return type.startsWith('social.mention.');
            case 'reels':
              return type.startsWith('social.reel.');
            case 'posts':
              return type.startsWith('social.post.');
            case 'stories':
              return type.startsWith('social.story.');
            case 'relations':
              return type.startsWith('social.relation.');
            default:
              return true;
          }
        })
        .toList(growable: false);
  }

  List<_ActivitySection> _groupByAge(List<AppNotificationModel> items) {
    final l10n = context.l10n;
    final now = DateTime.now();
    final today = <AppNotificationModel>[];
    final thisWeek = <AppNotificationModel>[];
    final earlier = <AppNotificationModel>[];
    for (final item in items) {
      final createdAt = item.createdAt?.toLocal();
      if (createdAt == null) {
        today.add(item);
        continue;
      }
      final diff = now.difference(createdAt);
      final isSameDay =
          createdAt.year == now.year &&
          createdAt.month == now.month &&
          createdAt.day == now.day;
      if (isSameDay || diff.inHours < 24) {
        today.add(item);
      } else if (diff.inDays < 7) {
        thisWeek.add(item);
      } else {
        earlier.add(item);
      }
    }
    final out = <_ActivitySection>[];
    if (today.isNotEmpty) {
      out.add(_ActivitySection(l10n.commonToday, today));
    }
    if (thisWeek.isNotEmpty) {
      out.add(_ActivitySection(l10n.commonThisWeek, thisWeek));
    }
    if (earlier.isNotEmpty) {
      out.add(_ActivitySection(l10n.socialActivityEarlier, earlier));
    }
    return out;
  }

  Future<void> _openNotification(AppNotificationModel notification) async {
    await SystemSound.play(SystemSoundType.click);
    await ref
        .read(notificationsControllerProvider.notifier)
        .markRead(notification.id);
    if (!mounted) return;

    final auth = ref.read(authControllerProvider);
    final navigator = Navigator.of(context);
    final payload = NotificationNavigation.payloadFromModel(notification);
    try {
      await NotificationNavigation.open(
        navigator: navigator,
        auth: auth,
        payload: payload,
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.socialActivityOpenLinkedContentFailed),
        ),
      );
    }
  }

  Future<void> _openRelationRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SocialRelationRequestsScreen(),
      ),
    );
    if (!mounted) return;
    await _loadRequestsMeta();
  }

  Future<void> _openMessageRequests() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const SocialMessageRequestsScreen(),
      ),
    );
    if (!mounted) return;
    await _loadRequestsMeta();
  }
}

class _SocialActivityStats {
  final int all;
  final int unread;
  final int likes;
  final int comments;
  final int mentions;
  final int reels;
  final int posts;
  final int stories;
  final int relations;

  const _SocialActivityStats({
    required this.all,
    required this.unread,
    required this.likes,
    required this.comments,
    required this.mentions,
    required this.reels,
    required this.posts,
    required this.stories,
    required this.relations,
  });

  factory _SocialActivityStats.fromNotifications(
    List<AppNotificationModel> items,
  ) {
    var unread = 0;
    var likes = 0;
    var comments = 0;
    var mentions = 0;
    var reels = 0;
    var posts = 0;
    var stories = 0;
    var relations = 0;
    for (final item in items) {
      final type = item.type.toLowerCase();
      if (!item.isRead) unread += 1;
      if (type.contains('.like')) likes += 1;
      if (type.contains('.comment')) comments += 1;
      if (type.startsWith('social.mention.')) mentions += 1;
      if (type.startsWith('social.reel.')) reels += 1;
      if (type.startsWith('social.post.')) posts += 1;
      if (type.startsWith('social.story.')) stories += 1;
      if (type.startsWith('social.relation.')) relations += 1;
    }
    return _SocialActivityStats(
      all: items.length,
      unread: unread,
      likes: likes,
      comments: comments,
      mentions: mentions,
      reels: reels,
      posts: posts,
      stories: stories,
      relations: relations,
    );
  }
}

class _ActivityFilterSpec {
  final String key;
  final String label;
  final int count;
  final IconData icon;

  const _ActivityFilterSpec(this.key, this.label, this.count, this.icon);
}

class _ActivitySection {
  final String label;
  final List<AppNotificationModel> items;

  const _ActivitySection(this.label, this.items);
}

class _ActivitySummaryRow extends StatelessWidget {
  final int likesCount;
  final int commentsCount;
  final int mentionsCount;
  final int unreadCount;
  final VoidCallback onOpenLikes;
  final VoidCallback onOpenComments;
  final VoidCallback onOpenMentions;
  final VoidCallback onOpenUnread;

  const _ActivitySummaryRow({
    required this.likesCount,
    required this.commentsCount,
    required this.mentionsCount,
    required this.unreadCount,
    required this.onOpenLikes,
    required this.onOpenComments,
    required this.onOpenMentions,
    required this.onOpenUnread,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _ActivitySummaryChip(
            icon: Icons.favorite_outline_rounded,
            label: l10n.socialActivityLikes,
            value: likesCount,
            onTap: onOpenLikes,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActivitySummaryChip(
            icon: Icons.mode_comment_outlined,
            label: l10n.commonComments,
            value: commentsCount,
            onTap: onOpenComments,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActivitySummaryChip(
            icon: Icons.alternate_email_rounded,
            label: l10n.socialActivityMentions,
            value: mentionsCount,
            onTap: onOpenMentions,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _ActivitySummaryChip(
            icon: Icons.mark_email_unread_outlined,
            label: l10n.socialActivityUnread,
            value: unreadCount,
            onTap: onOpenUnread,
          ),
        ),
      ],
    );
  }
}

class _ActivitySummaryChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final VoidCallback onTap;

  const _ActivitySummaryChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(height: 8),
            Text(
              '$value',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ],
        ),
      ),
    );
  }
}

class _RequestsStrip extends StatelessWidget {
  final bool loading;
  final int relationCount;
  final int messageCount;
  final VoidCallback onOpenRelations;
  final VoidCallback onOpenMessages;

  const _RequestsStrip({
    required this.loading,
    required this.relationCount,
    required this.messageCount,
    required this.onOpenRelations,
    required this.onOpenMessages,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _RequestShortcutTile(
            icon: Icons.person_add_alt_1_rounded,
            title: l10n.socialActivityConnectionRequests,
            count: relationCount,
            loading: loading,
            onTap: onOpenRelations,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _RequestShortcutTile(
            icon: Icons.mark_chat_unread_outlined,
            title: l10n.socialActivityMessageRequests,
            count: messageCount,
            loading: loading,
            onTap: onOpenMessages,
          ),
        ),
      ],
    );
  }
}

class _RequestShortcutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final bool loading;
  final VoidCallback onTap;

  const _RequestShortcutTile({
    required this.icon,
    required this.title,
    required this.count,
    required this.loading,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surfaceContainer,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: scheme.primary),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    loading
                        ? l10n.commonLoading
                        : l10n.socialActivityItemsCount(count),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}

class _ActivitySectionHeader extends StatelessWidget {
  final String label;

  const _ActivitySectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w900),
    );
  }
}

class _SocialActivityTile extends StatelessWidget {
  final AppNotificationModel notification;
  final VoidCallback onTap;

  const _SocialActivityTile({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final visual = _visualFor(notification, context, scheme);
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: notification.isRead
                ? scheme.outlineVariant.withValues(alpha: 0.35)
                : visual.color.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: visual.color.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(visual.icon, color: visual.color),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: visual.color,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if ((notification.body ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 5),
                    Text(
                      notification.body!.trim(),
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        _timeLabel(notification.createdAt, context),
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: scheme.onSurfaceVariant,
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        visual.label,
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(
                              color: visual.color,
                              fontWeight: FontWeight.w800,
                            ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _ActivityVisual _visualFor(
    AppNotificationModel notification,
    BuildContext context,
    ColorScheme scheme,
  ) {
    final l10n = context.l10n;
    final type = notification.type.toLowerCase();
    if (type.contains('.like')) {
      return _ActivityVisual(
        icon: Icons.favorite_rounded,
        label: l10n.socialActivityLike,
        color: const Color(0xFFE24E73),
      );
    }
    if (type.contains('.comment')) {
      return _ActivityVisual(
        icon: Icons.mode_comment_rounded,
        label: l10n.socialActivityComment,
        color: const Color(0xFF4B7CFF),
      );
    }
    if (type.startsWith('social.mention.')) {
      return _ActivityVisual(
        icon: Icons.alternate_email_rounded,
        label: l10n.socialActivityMention,
        color: const Color(0xFF8B5CF6),
      );
    }
    if (type.startsWith('social.reel.')) {
      return _ActivityVisual(
        icon: Icons.play_circle_fill_rounded,
        label: l10n.socialActivityReel,
        color: const Color(0xFFF59E0B),
      );
    }
    if (type.startsWith('social.story.')) {
      return _ActivityVisual(
        icon: Icons.auto_stories_rounded,
        label: l10n.socialActivityStory,
        color: const Color(0xFF10B981),
      );
    }
    if (type.startsWith('social.relation.')) {
      return _ActivityVisual(
        icon: Icons.people_alt_rounded,
        label: l10n.socialActivityRelation,
        color: scheme.primary,
      );
    }
    return _ActivityVisual(
      icon: Icons.notifications_active_outlined,
      label: l10n.socialActivityActivity,
      color: scheme.primary,
    );
  }

  String _timeLabel(DateTime? dateTime, BuildContext context) {
    final l10n = context.l10n;
    if (dateTime == null) return l10n.commonNow;
    final diff = DateTime.now().difference(dateTime.toLocal());
    if (diff.inMinutes < 1) return l10n.commonNow;
    if (diff.inHours < 1) {
      return l10n.socialActivityMinutesAgo(diff.inMinutes);
    }
    if (diff.inDays < 1) {
      return l10n.socialActivityHoursAgo(diff.inHours);
    }
    return l10n.socialActivityDaysAgo(diff.inDays);
  }
}

class _ActivityVisual {
  final IconData icon;
  final String label;
  final Color color;

  const _ActivityVisual({
    required this.icon,
    required this.label,
    required this.color,
  });
}

class _EmptySocialActivityState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptySocialActivityState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 110),
      child: Column(
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.favorite_border_rounded,
              size: 34,
              color: scheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
              height: 1.45,
            ),
          ),
        ],
      ),
    );
  }
}
