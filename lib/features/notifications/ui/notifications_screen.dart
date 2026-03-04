import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_navigation.dart';
import '../../auth/state/auth_controller.dart';
import '../models/app_notification_model.dart';
import '../state/notifications_controller.dart';

class NotificationsScreen extends ConsumerStatefulWidget {
  const NotificationsScreen({super.key});

  @override
  ConsumerState<NotificationsScreen> createState() =>
      _NotificationsScreenState();
}

class _NotificationsScreenState extends ConsumerState<NotificationsScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final controller = ref.read(notificationsControllerProvider.notifier);
      controller.startRealtime();
      return controller.loadNotifications();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(notificationsControllerProvider);

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

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          '\u0627\u0644\u0625\u0634\u0639\u0627\u0631\u0627\u062A',
        ),
        actions: [
          TextButton(
            onPressed: state.marking
                ? null
                : () => ref
                      .read(notificationsControllerProvider.notifier)
                      .markAllRead(),
            child: Text(
              '\u062A\u0639\u0644\u064A\u0645 \u0627\u0644\u0643\u0644',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref
            .read(notificationsControllerProvider.notifier)
            .loadNotifications(),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.notifications.isEmpty
            ? ListView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                children: const [
                  SizedBox(height: 120),
                  _EmptyNotificationsState(),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                itemCount: state.notifications.length,
                separatorBuilder: (_, index) => const SizedBox(height: 10),
                itemBuilder: (_, index) {
                  final notification = state.notifications[index];
                  return _NotificationCard(
                    notification: notification,
                    onTap: () => _openNotification(notification),
                  );
                },
              ),
      ),
    );
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
    await NotificationNavigation.open(
      navigator: navigator,
      auth: auth,
      payload: payload,
    );
  }
}

class _EmptyNotificationsState extends StatelessWidget {
  const _EmptyNotificationsState();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(
          Icons.notifications_off_outlined,
          size: 54,
          color: Colors.white.withValues(alpha: 0.75),
        ),
        const SizedBox(height: 10),
        const Text(
          '\u0644\u0627 \u062A\u0648\u062C\u062F \u0625\u0634\u0639\u0627\u0631\u0627\u062A \u062D\u0627\u0644\u064A\u0627\u064B',
          textDirection: TextDirection.rtl,
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Text(
          '\u0639\u0646\u062F \u0648\u0635\u0648\u0644 \u062A\u062D\u062F\u064A\u062B\u0627\u062A \u062C\u062F\u064A\u062F\u0629 \u0633\u062A\u0638\u0647\u0631 \u0647\u0646\u0627.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.82),
            height: 1.3,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _NotificationCard extends StatelessWidget {
  final AppNotificationModel notification;
  final VoidCallback onTap;

  const _NotificationCard({required this.notification, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final target = NotificationNavigation.resolveTarget(
      rawTarget: notification.target,
      type: notification.type,
      orderId: notification.orderId,
    );
    final icon = _iconForTarget(target);
    final accent = _colorForTarget(target);
    final createdLabel = _formatRelativeTime(notification.createdAt);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                accent.withValues(alpha: 0.18),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(
              color: notification.isRead
                  ? Colors.white.withValues(alpha: 0.12)
                  : accent.withValues(alpha: 0.55),
            ),
            boxShadow: [
              BoxShadow(
                color: accent.withValues(
                  alpha: notification.isRead ? 0.04 : 0.1,
                ),
                blurRadius: notification.isRead ? 8 : 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: accent.withValues(alpha: 0.46)),
                  ),
                  child: Icon(icon, color: accent, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: Text(
                              notification.title,
                              textDirection: TextDirection.rtl,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: notification.isRead
                                    ? FontWeight.w700
                                    : FontWeight.w900,
                                fontSize: 15,
                                height: 1.2,
                              ),
                            ),
                          ),
                          if (!notification.isRead) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 3,
                              ),
                              decoration: BoxDecoration(
                                color: accent.withValues(alpha: 0.2),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: accent.withValues(alpha: 0.6),
                                ),
                              ),
                              child: Text(
                                '\u062C\u062F\u064A\u062F',
                                style: TextStyle(
                                  color: accent,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if ((notification.body ?? '').trim().isNotEmpty) ...[
                        const SizedBox(height: 5),
                        Text(
                          notification.body!,
                          textDirection: TextDirection.rtl,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            fontWeight: FontWeight.w500,
                            height: 1.28,
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                      Row(
                        textDirection: TextDirection.rtl,
                        children: [
                          Expanded(
                            child: Text(
                              _targetHint(target),
                              textDirection: TextDirection.rtl,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            createdLabel,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.72),
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
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
        ),
      ),
    );
  }

  IconData _iconForTarget(String target) {
    switch (target) {
      case 'social_chat':
        return Icons.chat_bubble_rounded;
      case 'social_call':
        return Icons.call_rounded;
      case 'social_feed':
        return Icons.newspaper_rounded;
      case 'order_tracking':
        return Icons.receipt_long_rounded;
      case 'taxi_call':
        return Icons.call_rounded;
      case 'taxi_live':
        return Icons.local_taxi_rounded;
      case 'owner_orders':
        return Icons.storefront_rounded;
      case 'admin_settlements':
        return Icons.account_balance_wallet_rounded;
      case 'admin_merchants_pending':
        return Icons.pending_actions_rounded;
      case 'delivery_orders':
        return Icons.local_shipping_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  Color _colorForTarget(String target) {
    switch (target) {
      case 'social_chat':
        return const Color(0xFF60A5FA);
      case 'social_call':
        return const Color(0xFFFB7185);
      case 'social_feed':
        return const Color(0xFFA78BFA);
      case 'order_tracking':
        return const Color(0xFF4CC9F0);
      case 'taxi_call':
        return const Color(0xFFF59E0B);
      case 'taxi_live':
        return const Color(0xFF60A5FA);
      case 'owner_orders':
        return const Color(0xFF10B981);
      case 'admin_settlements':
        return const Color(0xFF22C55E);
      case 'admin_merchants_pending':
        return const Color(0xFFA78BFA);
      case 'delivery_orders':
        return const Color(0xFFEAB308);
      default:
        return const Color(0xFF93C5FD);
    }
  }

  String _targetHint(String target) {
    switch (target) {
      case 'social_chat':
        return '\u0627\u0644\u0645\u062D\u0627\u062F\u062B\u0627\u062A';
      case 'social_call':
        return '\u0645\u0643\u0627\u0644\u0645\u0629 \u062F\u0627\u062E\u0644 \u0627\u0644\u062A\u0637\u0628\u064A\u0642';
      case 'social_feed':
        return '\u0634\u062F\u064A\u0635\u064A\u0631 \u0628\u0633\u0645\u0627\u064A\u0629';
      case 'order_tracking':
        return '\u062A\u062A\u0628\u0639 \u0627\u0644\u0637\u0644\u0628';
      case 'taxi_call':
        return '\u0645\u0643\u0627\u0644\u0645\u0629 \u062A\u0643\u0633\u064A';
      case 'taxi_live':
        return '\u0631\u062D\u0644\u0629 \u062A\u0643\u0633\u064A';
      case 'owner_orders':
        return '\u0637\u0644\u0628\u0627\u062A \u0627\u0644\u0645\u062A\u062C\u0631';
      case 'admin_settlements':
        return '\u0645\u0633\u062A\u062D\u0642\u0627\u062A \u0645\u0627\u0644\u064A\u0629';
      case 'admin_merchants_pending':
        return '\u0637\u0644\u0628\u0627\u062A \u0628\u0627\u0646\u062A\u0638\u0627\u0631 \u0627\u0644\u0645\u0648\u0627\u0641\u0642\u0629';
      case 'delivery_orders':
        return '\u0637\u0644\u0628\u0627\u062A \u062A\u0648\u0635\u064A\u0644';
      default:
        return '\u0625\u0634\u0639\u0627\u0631 \u0639\u0627\u0645';
    }
  }

  String _formatRelativeTime(DateTime? dateTime) {
    if (dateTime == null) return '\u0627\u0644\u0622\u0646';
    final now = DateTime.now();
    final local = dateTime.toLocal();
    final diff = now.difference(local);
    if (diff.inSeconds < 60) return '\u0627\u0644\u0622\u0646';
    if (diff.inMinutes < 60) {
      return '\u0642\u0628\u0644 ${diff.inMinutes} \u062F';
    }
    if (diff.inHours < 24) {
      return '\u0642\u0628\u0644 ${diff.inHours} \u0633';
    }
    if (diff.inDays < 7) {
      return '\u0642\u0628\u0644 ${diff.inDays} \u064A';
    }
    final month = local.month.toString().padLeft(2, '0');
    final day = local.day.toString().padLeft(2, '0');
    return '${local.year}/$month/$day';
  }
}
