import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/notifications_controller.dart';
import 'notifications_screen.dart';

class NotificationsBellButton extends ConsumerStatefulWidget {
  const NotificationsBellButton({super.key});

  @override
  ConsumerState<NotificationsBellButton> createState() =>
      _NotificationsBellButtonState();
}

class _NotificationsBellButtonState
    extends ConsumerState<NotificationsBellButton> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      final controller = ref.read(notificationsControllerProvider.notifier);
      controller.startRealtime();
      return controller.refreshUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(notificationsControllerProvider).unreadCount;

    return Stack(
      children: [
        IconButton(
          tooltip: 'الإشعارات',
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const NotificationsScreen()),
            );
            if (!mounted) return;
            await ref
                .read(notificationsControllerProvider.notifier)
                .refreshUnreadCount();
          },
          icon: const Icon(Icons.notifications_outlined),
        ),
        if (unread > 0)
          Positioned(
            right: 7,
            top: 7,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                unread > 99 ? '99+' : '$unread',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 10,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
