// Purpose: زر الجرس المختصر الذي يظهر عداد الإشعارات غير المقروءة في الـ AppBar.
// Used by: الشاشات العليا التي تحتاج وصولاً سريعاً إلى صندوق الإشعارات أو نشاط السوشال.
// Depends on: `notificationsControllerProvider` لتغذية العداد وتهيئة realtime، و`NotificationsScreen`/`SocialActivityScreen` للتنقل.
// Critical notes: يبدأ realtime و`refreshUnreadCount` عند التركيب حتى لا يبقى العداد قديماً بعد العودة من الخلفية.
// Maintenance notes: إذا توقف العداد عن التحديث افحص أولاً `notifications_controller.dart` ثم stream الإشعارات الحية ثم مزامنة `refreshUnreadCount`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../social/ui/social_activity_screen.dart';
import '../state/notifications_controller.dart';
import 'notifications_screen.dart';

/// عنصر واجهة صغير reusable يربط بين عداد unread والتنقل إلى inbox المناسب حسب السياق.
class NotificationsBellButton extends ConsumerStatefulWidget {
  final NotificationInboxMode mode;

  const NotificationsBellButton({
    super.key,
    this.mode = NotificationInboxMode.general,
  });

  @override
  ConsumerState<NotificationsBellButton> createState() =>
      _NotificationsBellButtonState();
}

class _NotificationsBellButtonState
    extends ConsumerState<NotificationsBellButton> {
  /// يفعّل realtime ويجلب العداد المختصر عند أول تركيب للزر.
  ///
  /// هذا السلوك مقصود لأن كثيراً من الشاشات التي تعرض الجرس لا تبني
  /// `NotificationsScreen` نفسها، وبالتالي تحتاج bootstrap خفيفاً هنا.
  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      final unread = switch (widget.mode) {
        NotificationInboxMode.general => ref.read(generalUnreadCountProvider),
        NotificationInboxMode.socialActivity => ref.read(
          socialActivityUnreadCountProvider,
        ),
        NotificationInboxMode.all => ref.read(
          notificationsControllerProvider.select((state) => state.unreadCount),
        ),
      };
      if (unread > 0) return;
      await ref
          .read(notificationsControllerProvider.notifier)
          .refreshUnreadCount();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final unread = switch (widget.mode) {
      NotificationInboxMode.general => ref.watch(generalUnreadCountProvider),
      NotificationInboxMode.socialActivity => ref.watch(
        socialActivityUnreadCountProvider,
      ),
      NotificationInboxMode.all => ref.watch(
        notificationsControllerProvider.select((state) => state.unreadCount),
      ),
    };
    final icon = widget.mode == NotificationInboxMode.socialActivity
        ? Icons.favorite_border_rounded
        : Icons.notifications_outlined;
    final tooltip = switch (widget.mode) {
      NotificationInboxMode.general => l10n.notificationsApp,
      NotificationInboxMode.socialActivity => l10n.notificationsSocialActivity,
      NotificationInboxMode.all => l10n.notificationsTitle,
    };

    return Stack(
      children: [
        IconButton(
          tooltip: tooltip,
          onPressed: () async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => widget.mode == NotificationInboxMode.socialActivity
                    ? const SocialActivityScreen()
                    : NotificationsScreen(mode: widget.mode),
              ),
            );
            if (!mounted) return;
            await ref
                .read(notificationsControllerProvider.notifier)
                .refreshUnreadCount();
          },
          icon: Icon(icon),
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
