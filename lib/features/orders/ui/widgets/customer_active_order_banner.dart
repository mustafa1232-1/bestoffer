import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/locale_text.dart';
import '../../../../core/utils/order_status.dart';
import '../../../auth/state/auth_controller.dart';
import '../../models/order_model.dart';
import '../../state/orders_controller.dart';
import 'customer_active_order_banner_logic.dart';

class CustomerActiveOrderBannerHost extends ConsumerStatefulWidget {
  final Widget child;
  final ValueChanged<OrderModel> onOpenOrder;

  const CustomerActiveOrderBannerHost({
    required this.child,
    required this.onOpenOrder,
    super.key,
  });

  @override
  ConsumerState<CustomerActiveOrderBannerHost> createState() =>
      _CustomerActiveOrderBannerHostState();
}

class _CustomerActiveOrderBannerHostState
    extends ConsumerState<CustomerActiveOrderBannerHost>
    with WidgetsBindingObserver {
  int? _sessionUserId;
  int? _ordersLoadedForUserId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _syncCustomerSession(AuthState auth) {
    final userId = auth.isCustomer ? auth.user?.id : null;
    if (_sessionUserId == userId) return;
    _sessionUserId = userId;
    _ordersLoadedForUserId = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = ref.read(ordersControllerProvider.notifier);
      if (userId == null) {
        controller.stopLiveOrders();
        return;
      }
      controller.resetForCustomerSession();
      controller.startLiveOrders();
      unawaited(
        controller.loadMyOrders(silent: true).whenComplete(() {
          if (!mounted || _sessionUserId != userId) return;
          setState(() => _ordersLoadedForUserId = userId);
        }),
      );
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || _sessionUserId == null) return;
    unawaited(
      ref.read(ordersControllerProvider.notifier).refreshLiveOrdersNow(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    _syncCustomerSession(auth);
    final ordersState = ref.watch(ordersControllerProvider);
    final activeOrder =
        auth.isCustomer && _ordersLoadedForUserId == auth.user?.id
        ? _activeOrder(ordersState.orders)
        : null;

    return Column(
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: activeOrder == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: EdgeInsets.fromLTRB(
                    12,
                    MediaQuery.paddingOf(context).top + 6,
                    12,
                    8,
                  ),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: const Offset(0, -0.12),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    ),
                    child: _ActiveOrderBanner(
                      key: ValueKey('${activeOrder.id}:${activeOrder.status}'),
                      order: activeOrder,
                      onTap: () => widget.onOpenOrder(activeOrder),
                    ),
                  ),
                ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }

  OrderModel? _activeOrder(List<OrderModel> orders) {
    final active = orders
        .where((order) {
          return shouldShowCustomerActiveOrderBanner(status: order.status);
        })
        .toList(growable: false);
    if (active.isEmpty) return null;
    active.sort((a, b) {
      final aTime = a.createdAt?.millisecondsSinceEpoch ?? a.id;
      final bTime = b.createdAt?.millisecondsSinceEpoch ?? b.id;
      return bTime.compareTo(aTime);
    });
    return active.first;
  }
}

class _ActiveOrderBanner extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onTap;

  const _ActiveOrderBanner({
    required this.order,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final status = normalizeOrderStatusForUi(order.status);
    final isDelivered = status == 'delivered';
    final color = isDelivered ? Colors.teal.shade800 : const Color(0xFF18543F);
    final foreground = Theme.of(context).colorScheme.onSurface;
    final label = _statusLabel(context, status);
    final subtitle = isDelivered
        ? context.lt(
            ar: 'تأكد من استلام طلبك لإكماله',
            en: 'Confirm receipt to complete your order',
          )
        : context.lt(
            ar: 'من ${order.merchantName}',
            en: 'From ${order.merchantName}',
          );
    final step = switch (status) {
      'pending' => 0,
      'approved' || 'preparing' || 'ready_for_delivery' => 1,
      'on_the_way' || 'arrived' => 2,
      'delivered' => 3,
      _ => 0,
    };

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: color.withValues(alpha: 0.55)),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.12),
                blurRadius: 16,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isDelivered
                      ? Icons.inventory_2_outlined
                      : Icons.delivery_dining,
                  color: color,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            context.lt(
                              ar: 'طلبك #${order.id} · $label',
                              en: 'Order #${order.id} · $label',
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: foreground,
                              fontWeight: FontWeight.w800,
                              fontSize: 13,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const _LiveDot(),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 7),
                    _OrderProgressTrack(activeStep: step, color: color),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.chevron_right_rounded, color: color),
            ],
          ),
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, String status) => switch (status) {
    'pending' => context.lt(ar: 'بانتظار المتجر', en: 'Waiting for store'),
    'approved' => context.lt(ar: 'تم قبول الطلب', en: 'Order accepted'),
    'preparing' => context.lt(ar: 'قيد التحضير', en: 'Being prepared'),
    'ready_for_delivery' => context.lt(
      ar: 'جاهز للتوصيل',
      en: 'Ready for delivery',
    ),
    'on_the_way' => context.lt(ar: 'في الطريق إليك', en: 'On the way'),
    'arrived' => context.lt(ar: 'وصل الدلفري', en: 'Courier has arrived'),
    'delivered' => context.lt(ar: 'تم التسليم', en: 'Delivered'),
    _ => orderStatusLabelForCustomer(
      status,
      customerConfirmed: order.customerConfirmedAt != null,
    ),
  };
}

class _OrderProgressTrack extends StatelessWidget {
  final int activeStep;
  final Color color;

  const _OrderProgressTrack({required this.activeStep, required this.color});

  @override
  Widget build(BuildContext context) => Row(
    children: List<Widget>.generate(4, (index) {
      final active = index <= activeStep;
      return Expanded(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 450),
          curve: Curves.easeOut,
          height: 4,
          margin: EdgeInsetsDirectional.only(end: index == 3 ? 0 : 4),
          decoration: BoxDecoration(
            color: active ? color : color.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(3),
          ),
        ),
      );
    }),
  );
}

class _LiveDot extends StatefulWidget {
  const _LiveDot();

  @override
  State<_LiveDot> createState() => _LiveDotState();
}

class _LiveDotState extends State<_LiveDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1000),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: Tween<double>(begin: 0.35, end: 1).animate(_controller),
    child: Container(
      width: 8,
      height: 8,
      decoration: const BoxDecoration(
        color: Color(0xFF2BA66A),
        shape: BoxShape.circle,
      ),
    ),
  );
}
