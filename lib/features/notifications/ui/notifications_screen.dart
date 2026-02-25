import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../../orders/ui/customer_orders_screen.dart';
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
      prev,
      next,
    ) {
      if (next.error != null && next.error != prev?.error && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('الإشعارات'),
        actions: [
          TextButton(
            onPressed: state.marking
                ? null
                : () => ref
                      .read(notificationsControllerProvider.notifier)
                      .markAllRead(),
            child: const Text('تعليم الكل'),
          ),
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
                children: const [
                  SizedBox(height: 120),
                  Center(child: Text('لا توجد إشعارات')),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: state.notifications.length,
                separatorBuilder: (_, index) => const SizedBox(height: 8),
                itemBuilder: (_, index) {
                  final n = state.notifications[index];
                  return Card(
                    color: n.isRead
                        ? null
                        : Theme.of(context).colorScheme.primaryContainer,
                    child: ListTile(
                      onTap: () => _openNotification(n),
                      title: Text(n.title, textDirection: TextDirection.rtl),
                      subtitle: Text(
                        n.body ?? '',
                        textDirection: TextDirection.rtl,
                      ),
                      trailing: n.isRead
                          ? const Icon(Icons.done_all)
                          : const Icon(Icons.mark_email_unread_outlined),
                    ),
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
    final orderId = _extractOrderId(notification);

    // Customer notifications: open order tracking directly.
    if (!auth.isBackoffice && !auth.isOwner && !auth.isDelivery) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => CustomerOrdersScreen(initialOrderId: orderId),
        ),
      );
      return;
    }

    if (orderId != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('الإشعار مرتبط بالطلب #$orderId')),
      );
    }
  }

  int? _extractOrderId(AppNotificationModel notification) {
    if (notification.orderId != null) return notification.orderId;
    final payloadId = notification.payload?['orderId'];
    return int.tryParse('$payloadId');
  }
}
