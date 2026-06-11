// Purpose: شاشة صندوق الإشعارات العامة/الاجتماعية مع فلاتر، حالة realtime، وفتح الهدف المرتبط بالإشعار.
// Used by: الجرس العام، نشاط السوشال، ومسارات التنقل القادمة من الإشعارات المحلية أو الحية.
// Depends on: `notificationsControllerProvider`, `NotificationNavigation`, و`notification_localizer.dart`.
// Critical notes: الشاشة تعيد تشغيل realtime عند الفتح وتحوّل الأخطاء إلى `SnackBar` بدلاً من كسر الواجهة.
// Maintenance notes: إذا لم تُفتح الأهداف الصحيحة افحص `NotificationNavigation.resolveTarget/open` ثم payload القادم من الباكند ثم `markRead`.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/notification_localizer.dart';
import '../../../core/notifications/notification_navigation.dart';
import '../../../core/theme/app_theme.dart';
import '../../auth/state/auth_controller.dart';
import '../../../l10n/app_localizations.dart';
import '../models/app_notification_model.dart';
import '../state/notifications_controller.dart';

/// واجهة العرض الرئيسية للإشعارات مع دعم ثلاثة أنماط inbox:
/// عام، نشاط اجتماعي، أو صندوق موحد.
class NotificationsScreen extends ConsumerStatefulWidget {
  final NotificationInboxMode mode;
  final String? title;
  final String initialFilterKey;

  const NotificationsScreen({
    super.key,
    this.mode = NotificationInboxMode.all,
    this.title,
    this.initialFilterKey = 'all',
  });

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  bool _unreadOnly = false;
  late String _filter;

  /// يهيئ الفلتر الأولي ويضمن أن قناة realtime بدأت قبل أول تحميل.
  ///
  /// وجود هذا bootstrap هنا يمنع حالة ظهور الشاشة ببيانات قديمة بعد العودة
  /// من notification tap أو بعد reconnect.
  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilterKey;
    Future.microtask(() {
      final controller = ref.read(notificationsControllerProvider.notifier);
      controller.startRealtime();
      return controller.loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final tokens = context.maslakiTokens;
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
    final source = _sourceNotifications(state);
    final filtered = _applyFilters(source);
    final stats = _buildStats(source);

    return Scaffold(
      appBar: MaslakiTopBar(
        title: _titleForMode(l10n),
        subtitle: 'تحديث مباشر وفلاتر ذكية حسب نوع التنبيه',
        actions: [
          IconButton(
            tooltip: l10n.notificationsReconnect,
            onPressed: () async {
              final notifier = ref.read(
                notificationsControllerProvider.notifier,
              );
              notifier.stopRealtime();
              notifier.startRealtime();
              await notifier.loadNotifications(silent: true);
              await notifier.refreshUnreadCount();
            },
            icon: const Icon(Icons.wifi_tethering_rounded),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: TextButton(
              onPressed: state.marking
                  ? null
                  : () => ref
                        .read(notificationsControllerProvider.notifier)
                        .markAllRead(),
              child: Text(
                l10n.notificationsMarkAll,
                style: TextStyle(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: MaslakiCard(
              elevated: false,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    reverse: true,
                    child: Row(
                      children: [
                        ..._filterSpecs(stats, l10n).map(
                          (spec) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 8),
                            child: MaslakiChip(
                              label: '${spec.label} ${spec.count}',
                              icon: spec.icon,
                              selected: _filter == spec.key,
                              onTap: () {
                                setState(() => _filter = spec.key);
                              },
                            ),
                          ),
                        ),
                        MaslakiChip(
                          label: l10n.notificationsUnread,
                          icon: Icons.mark_email_unread_outlined,
                          selected: _unreadOnly,
                          onTap: () {
                            setState(() => _unreadOnly = !_unreadOnly);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: _RealtimeBadge(
                      label: _realtimeLabel(state.realtimeStatus, l10n),
                      icon: _realtimeIcon(state.realtimeStatus),
                      color: _realtimeColor(state.realtimeStatus),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref
                  .read(notificationsControllerProvider.notifier)
                  .loadNotifications(),
              child: state.loading
                  ? ListView(
                      padding: const EdgeInsets.only(top: 120),
                      children: const [
                        Center(child: CircularProgressIndicator()),
                      ],
                    )
                  : filtered.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(20, 80, 20, 20),
                      children: [
                        _EmptyNotificationsState(
                          title: _emptyTitle(l10n),
                          body: _emptyBody(l10n),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                      itemBuilder: (context, index) {
                        final notification = filtered[index];
                        return _NotificationCard(
                          notification: notification,
                          onTap: () => _openNotification(notification),
                        );
                      },
                      separatorBuilder: (context, index) =>
                          const SizedBox(height: 10),
                      itemCount: filtered.length,
                    ),
            ),
          ),
        ],
      ),
    );
  }

  List<AppNotificationModel> _sourceNotifications(NotificationsState state) {
    switch (widget.mode) {
      case NotificationInboxMode.general:
        return ref.watch(generalNotificationsProvider);
      case NotificationInboxMode.socialActivity:
        return ref.watch(socialActivityNotificationsProvider);
      case NotificationInboxMode.all:
        return state.notifications;
    }
  }

  /// يطبّق فلاتر الواجهة المحلية على القائمة المصدرية بدون تعديل الحالة العالمية.
  ///
  /// التشخيص: إذا اختلفت العدادات عن المعروض افحص أولاً هذا الفرع ثم `_buildStats`
  /// ثم predicate helpers مثل `isSocialActivityNotification`.
  List<AppNotificationModel> _applyFilters(List<AppNotificationModel> source) {
    return source.where((notification) {
      if (_unreadOnly && notification.isRead) return false;
      switch (_filter) {
        case 'general':
          return isGeneralAppNotification(notification);
        case 'social':
          return isSocialActivityNotification(notification);
        case 'messages':
          return isSocialMessageNotification(notification);
        case 'orders':
          return notification.type.toLowerCase().contains('order') ||
              NotificationNavigation.resolveTarget(
                    rawTarget: notification.target,
                    type: notification.type,
                    orderId: notification.orderId,
                  ) ==
                  'order_tracking';
        case 'mobility':
          final type = notification.type.toLowerCase();
          return type.startsWith('taxi.') || type.startsWith('delivery.');
        case 'jobs':
          return notification.type.toLowerCase().startsWith('jobs.');
        case 'posts':
          return notification.type.toLowerCase().startsWith('social.post.');
        case 'stories':
          return notification.type.toLowerCase().startsWith('social.story.');
        case 'relations':
          return notification.type.toLowerCase().startsWith('social.relation.');
        case 'mentions':
          return notification.type.toLowerCase().startsWith('social.mention.');
        case 'likes':
          return notification.type.toLowerCase().contains('.like');
        case 'comments':
          return notification.type.toLowerCase().contains('.comment');
        case 'reels':
          return notification.type.toLowerCase().startsWith('social.reel.');
        default:
          return true;
      }
    }).toList(growable: false);
  }

  /// يحسب العدادات الظاهرة في شريط الفلاتر من نفس المصدر الخام للإشعارات.
  ///
  /// يستخدم نفس منطق التصنيف تقريباً الخاص بالتنقل حتى لا يظهر تناقض بين
  /// badge counts وبين نوع الهدف الذي سيفتحه الإشعار.
  _NotificationStats _buildStats(List<AppNotificationModel> source) {
    var unread = 0;
    var general = 0;
    var social = 0;
    var messages = 0;
    var orders = 0;
    var mobility = 0;
    var jobs = 0;
    var posts = 0;
    var reels = 0;
    var stories = 0;
    var relations = 0;
    var mentions = 0;
    var likes = 0;
    var comments = 0;
    for (final notification in source) {
      if (!notification.isRead) unread += 1;
      if (isGeneralAppNotification(notification)) general += 1;
      if (isSocialActivityNotification(notification)) social += 1;
      if (isSocialMessageNotification(notification)) messages += 1;
      final type = notification.type.toLowerCase();
      final target = NotificationNavigation.resolveTarget(
        rawTarget: notification.target,
        type: notification.type,
        orderId: notification.orderId,
      );
      if (type.contains('order') || target == 'order_tracking') orders += 1;
      if (type.startsWith('taxi.') || type.startsWith('delivery.')) {
        mobility += 1;
      }
      if (type.startsWith('jobs.')) jobs += 1;
      if (type.startsWith('social.post.')) posts += 1;
      if (type.startsWith('social.reel.')) reels += 1;
      if (type.startsWith('social.story.')) stories += 1;
      if (type.startsWith('social.relation.')) relations += 1;
      if (type.startsWith('social.mention.')) mentions += 1;
      if (type.contains('.like')) likes += 1;
      if (type.contains('.comment')) comments += 1;
    }
    return _NotificationStats(
      all: source.length,
      unread: unread,
      general: general,
      social: social,
      messages: messages,
      orders: orders,
      mobility: mobility,
      jobs: jobs,
      posts: posts,
      reels: reels,
      stories: stories,
      relations: relations,
      mentions: mentions,
      likes: likes,
      comments: comments,
    );
  }

  List<_NotificationFilterSpec> _filterSpecs(
    _NotificationStats stats,
    AppLocalizations l10n,
  ) {
    switch (widget.mode) {
      case NotificationInboxMode.general:
        return [
          _NotificationFilterSpec(
            'all',
            l10n.commonAll,
            stats.all,
            Icons.apps_rounded,
          ),
          _NotificationFilterSpec(
            'orders',
            l10n.notificationsOrders,
            stats.orders,
            Icons.receipt_long_rounded,
          ),
          _NotificationFilterSpec(
            'mobility',
            l10n.notificationsMobility,
            stats.mobility,
            Icons.local_taxi_rounded,
          ),
          _NotificationFilterSpec(
            'jobs',
            l10n.notificationsJobs,
            stats.jobs,
            Icons.work_outline_rounded,
          ),
        ];
      case NotificationInboxMode.socialActivity:
        return [
          _NotificationFilterSpec(
            'all',
            l10n.commonAll,
            stats.all,
            Icons.favorite_border_rounded,
          ),
          _NotificationFilterSpec(
            'posts',
            l10n.notificationsPosts,
            stats.posts,
            Icons.grid_view_rounded,
          ),
          _NotificationFilterSpec(
            'reels',
            l10n.notificationsReels,
            stats.reels,
            Icons.ondemand_video_rounded,
          ),
          _NotificationFilterSpec(
            'likes',
            l10n.notificationsLikes,
            stats.likes,
            Icons.favorite_outline_rounded,
          ),
          _NotificationFilterSpec(
            'comments',
            l10n.notificationsComments,
            stats.comments,
            Icons.mode_comment_outlined,
          ),
          _NotificationFilterSpec(
            'stories',
            l10n.notificationsStories,
            stats.stories,
            Icons.auto_stories_rounded,
          ),
          _NotificationFilterSpec(
            'relations',
            l10n.notificationsRelations,
            stats.relations,
            Icons.people_outline_rounded,
          ),
          _NotificationFilterSpec(
            'mentions',
            l10n.notificationsMentions,
            stats.mentions,
            Icons.alternate_email_rounded,
          ),
        ];
      case NotificationInboxMode.all:
        return [
          _NotificationFilterSpec(
            'all',
            l10n.commonAll,
            stats.all,
            Icons.apps_rounded,
          ),
          _NotificationFilterSpec(
            'general',
            l10n.notificationsGeneral,
            stats.general,
            Icons.notifications_none_rounded,
          ),
          _NotificationFilterSpec(
            'social',
            l10n.notificationsSocial,
            stats.social,
            Icons.favorite_border_rounded,
          ),
          _NotificationFilterSpec(
            'messages',
            l10n.notificationsMessages,
            stats.messages,
            Icons.chat_bubble_outline_rounded,
          ),
        ];
    }
  }

  String _titleForMode(AppLocalizations l10n) {
    if ((widget.title ?? '').trim().isNotEmpty) {
      return widget.title!.trim();
    }
    switch (widget.mode) {
      case NotificationInboxMode.general:
        return l10n.notificationsApp;
      case NotificationInboxMode.socialActivity:
        return l10n.notificationsSocialActivity;
      case NotificationInboxMode.all:
        return l10n.notificationsTitle;
    }
  }

  String _emptyTitle(AppLocalizations l10n) {
    switch (widget.mode) {
      case NotificationInboxMode.general:
        return l10n.notificationsNoGeneral;
      case NotificationInboxMode.socialActivity:
        return l10n.notificationsNoSocial;
      case NotificationInboxMode.all:
        return l10n.notificationsNoNotifications;
    }
  }

  String _emptyBody(AppLocalizations l10n) {
    switch (widget.mode) {
      case NotificationInboxMode.general:
        return l10n.notificationsGeneralEmptyBody;
      case NotificationInboxMode.socialActivity:
        return l10n.notificationsSocialEmptyBody;
      case NotificationInboxMode.all:
        return l10n.notificationsAllEmptyBody;
    }
  }

  String _realtimeLabel(
    NotificationsRealtimeStatus status,
    AppLocalizations l10n,
  ) {
    switch (status) {
      case NotificationsRealtimeStatus.connected:
        return l10n.notificationsConnected;
      case NotificationsRealtimeStatus.reconnecting:
        return l10n.notificationsReconnecting;
      case NotificationsRealtimeStatus.connecting:
        return l10n.notificationsConnecting;
      case NotificationsRealtimeStatus.offline:
        return l10n.notificationsOffline;
    }
  }

  IconData _realtimeIcon(NotificationsRealtimeStatus status) {
    switch (status) {
      case NotificationsRealtimeStatus.connected:
        return Icons.bolt_rounded;
      case NotificationsRealtimeStatus.reconnecting:
        return Icons.sync_rounded;
      case NotificationsRealtimeStatus.connecting:
        return Icons.wifi_tethering_rounded;
      case NotificationsRealtimeStatus.offline:
        return Icons.wifi_off_rounded;
    }
  }

  Color _realtimeColor(NotificationsRealtimeStatus status) {
    switch (status) {
      case NotificationsRealtimeStatus.connected:
        return const Color(0xFF4ADE80);
      case NotificationsRealtimeStatus.reconnecting:
        return const Color(0xFFF59E0B);
      case NotificationsRealtimeStatus.connecting:
        return const Color(0xFF60A5FA);
      case NotificationsRealtimeStatus.offline:
        return const Color(0xFF94A3B8);
    }
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
        SnackBar(content: Text(context.l10n.notificationsUnableToOpenTarget)),
      );
    }
  }
}

class _NotificationStats {
  final int all;
  final int unread;
  final int general;
  final int social;
  final int messages;
  final int orders;
  final int mobility;
  final int jobs;
  final int posts;
  final int reels;
  final int stories;
  final int relations;
  final int mentions;
  final int likes;
  final int comments;

  const _NotificationStats({
    required this.all,
    required this.unread,
    required this.general,
    required this.social,
    required this.messages,
    required this.orders,
    required this.mobility,
    required this.jobs,
    required this.posts,
    required this.reels,
    required this.stories,
    required this.relations,
    required this.mentions,
    required this.likes,
    required this.comments,
  });
}

class _NotificationFilterSpec {
  final String key;
  final String label;
  final int count;
  final IconData icon;

  const _NotificationFilterSpec(this.key, this.label, this.count, this.icon);
}

class _NotificationCard extends StatelessWidget {
  final AppNotificationModel notification;
  final VoidCallback onTap;

  const _NotificationCard({
    required this.notification,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final resolved = resolveNotificationText(
      l10n: context.l10n,
      notification: notification,
    );
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    final bucket = resolveNotificationBucket(notification);
    final accent = switch (bucket) {
      NotificationBucket.general => visual.accentGold,
      NotificationBucket.socialActivity => visual.accentCyan,
      NotificationBucket.socialMessages => visual.accentBlue,
    };
    final icon = switch (bucket) {
      NotificationBucket.general => Icons.notifications_none_rounded,
      NotificationBucket.socialActivity => Icons.favorite_border_rounded,
      NotificationBucket.socialMessages => Icons.chat_bubble_outline_rounded,
    };

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: MaslakiCard(
        padding: const EdgeInsets.all(14),
        elevated: !notification.isRead,
        backgroundColor: notification.isRead
            ? tokens.cardPrimary.withValues(alpha: 0.84)
            : tokens.cardElevated.withValues(alpha: 0.94),
        borderColor: notification.isRead
            ? tokens.borderSubtle.withValues(alpha: 0.48)
            : accent.withValues(alpha: 0.44),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          resolved.title,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      if (!notification.isRead)
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                        ),
                    ],
                  ),
                  if ((resolved.body ?? '').trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      resolved.body!.trim(),
                      textDirection: TextDirection.rtl,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: tokens.textSecondary,
                        height: 1.35,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Text(
                    _timeLabel(notification.createdAt, context),
                    textDirection: TextDirection.rtl,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: tokens.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeLabel(DateTime? dateTime, BuildContext context) {
    final l10n = context.l10n;
    if (dateTime == null) {
      return l10n.commonNow;
    }
    final local = dateTime.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 1) return l10n.commonNow;
    if (diff.inHours < 1) {
      return l10n.notificationsMinutesAgo(diff.inMinutes);
    }
    if (diff.inDays < 1) {
      return l10n.notificationsHoursAgo(diff.inHours);
    }
    return l10n.notificationsDaysAgo(diff.inDays);
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  final String title;
  final String body;

  const _EmptyNotificationsState({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return MaslakiEmptyState(
      icon: Icons.notifications_none_rounded,
      title: title,
      body: body,
    );
  }
}

class _RealtimeBadge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;

  const _RealtimeBadge({
    required this.label,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return MaslakiStatusPill(
      label: label,
      icon: icon,
      color: color,
    );
  }
}
