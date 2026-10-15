import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../orders/models/order_model.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'widgets/company_ui.dart';

class CompanyOrdersScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;
  final int? initialOrderId;

  const CompanyOrdersScreen({
    super.key,
    required this.api,
    required this.companyId,
    this.initialOrderId,
  });

  @override
  State<CompanyOrdersScreen> createState() => _CompanyOrdersScreenState();
}

class _CompanyOrdersScreenState extends State<CompanyOrdersScreen> {
  Future<_CompanyOrdersPayload>? _future;
  int? _selectedMerchantId;
  int? _busyOrderId;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  @override
  void didUpdateWidget(covariant CompanyOrdersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _selectedMerchantId = null;
      _future = _load();
    }
  }

  Future<_CompanyOrdersPayload> _load() async {
    final results = await Future.wait<dynamic>([
      widget.api.branches(widget.companyId),
      widget.api.currentOrders(
        widget.companyId,
        merchantId: _selectedMerchantId,
      ),
    ]);
    return _CompanyOrdersPayload(
      branches: results[0] as List<CompanyBranch>,
      orders: results[1] as List<OrderModel>,
    );
  }

  Future<void> _refresh() async {
    setState(() {
      _future = _load();
    });
    await _future;
  }

  void _selectBranch(int? merchantId) {
    setState(() {
      _selectedMerchantId = merchantId;
      _future = _load();
    });
  }

  Future<void> _updateStatus(OrderModel order, String status) async {
    final normalized = normalizeOrderStatusForUi(status);
    if (normalized == 'cancelled') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(context.lt(ar: 'رفض الطلب', en: 'Reject order')),
          content: Text(
            context.lt(ar: 'هل تريد رفض هذا الطلب؟', en: 'Reject this order?'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.lt(ar: 'رجوع', en: 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.lt(ar: 'رفض', en: 'Reject')),
            ),
          ],
        ),
      );
      if (ok != true) return;
    }

    setState(() => _busyOrderId = order.id);
    try {
      await widget.api.updateOrderStatus(
        widget.companyId,
        order.id,
        status: status,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(ar: 'تم تحديث الطلب.', en: 'Order updated.'),
          ),
        ),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تعذر تحديث الطلب: $error',
              en: 'Could not update order: $error',
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busyOrderId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_CompanyOrdersPayload>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting &&
            !snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError && !snapshot.hasData) {
          return CompanyEmptyState(
            icon: Icons.receipt_long_outlined,
            title: context.lt(ar: 'تعذر تحميل الطلبات', en: 'Orders failed'),
            description: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(context.lt(ar: 'إعادة المحاولة', en: 'Retry')),
            ),
          );
        }

        final payload = snapshot.data ?? _CompanyOrdersPayload.empty();
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: context.lt(
                        ar: 'طلبات الفروع',
                        en: 'Branch orders',
                      ),
                      subtitle: context.lt(
                        ar: 'طلبات كل المتاجر المرتبطة بهذه الشركة',
                        en: 'Orders across the company branches',
                      ),
                      actions: [
                        IconButton.filledTonal(
                          onPressed: _refresh,
                          icon: const Icon(Icons.refresh_rounded),
                          tooltip: context.lt(ar: 'تحديث', en: 'Refresh'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<int?>(
                      initialValue: _selectedMerchantId,
                      decoration: InputDecoration(
                        labelText: context.lt(ar: 'الفرع', en: 'Branch'),
                        prefixIcon: const Icon(Icons.store_rounded),
                      ),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text(
                            context.lt(ar: 'كل الفروع', en: 'All branches'),
                          ),
                        ),
                        ...payload.branches.map(
                          (branch) => DropdownMenuItem<int?>(
                            value: branch.id,
                            child: Text(branch.name),
                          ),
                        ),
                      ],
                      onChanged: _selectBranch,
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        _SummaryTile(
                          icon: Icons.pending_actions_rounded,
                          label: context.lt(
                            ar: 'بانتظار القرار',
                            en: 'Waiting',
                          ),
                          value: _countStatus(payload.orders, {'pending'}),
                          color: Colors.orangeAccent,
                        ),
                        _SummaryTile(
                          icon: Icons.restaurant_menu_rounded,
                          label: context.lt(ar: 'قيد التجهيز', en: 'Preparing'),
                          value: _countStatus(payload.orders, {'preparing'}),
                          color: Colors.amberAccent,
                        ),
                        _SummaryTile(
                          icon: Icons.delivery_dining_rounded,
                          label: context.lt(
                            ar: 'جاهزة أو بالطريق',
                            en: 'Ready',
                          ),
                          value: _countStatus(payload.orders, {
                            'ready_for_delivery',
                            'on_the_way',
                            'arrived',
                          }),
                          color: Colors.lightBlueAccent,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (payload.orders.isEmpty)
                CompanyEmptyState(
                  icon: Icons.inbox_outlined,
                  title: context.lt(ar: 'لا توجد طلبات حالية', en: 'No orders'),
                  description: context.lt(
                    ar: 'ستظهر هنا طلبات فروع الشركة عند وصولها.',
                    en: 'New branch orders will appear here.',
                  ),
                )
              else
                ...payload.orders.map(
                  (order) => Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _CompanyOrderCard(
                      order: order,
                      busy: _busyOrderId == order.id,
                      highlighted: widget.initialOrderId == order.id,
                      onAction: (status) => _updateStatus(order, status),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  int _countStatus(List<OrderModel> orders, Set<String> statuses) {
    return orders
        .where(
          (order) => statuses.contains(normalizeOrderStatusForUi(order.status)),
        )
        .length;
  }
}

class _CompanyOrdersPayload {
  final List<CompanyBranch> branches;
  final List<OrderModel> orders;

  const _CompanyOrdersPayload({required this.branches, required this.orders});

  factory _CompanyOrdersPayload.empty() =>
      const _CompanyOrdersPayload(branches: [], orders: []);
}

class _SummaryTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final int value;
  final Color color;

  const _SummaryTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 190,
      child: CompanyMetricTile(
        label: label,
        value: value.toString(),
        icon: icon,
        color: color,
      ),
    );
  }
}

class _CompanyOrderCard extends StatelessWidget {
  final OrderModel order;
  final bool busy;
  final bool highlighted;
  final ValueChanged<String> onAction;

  const _CompanyOrderCard({
    required this.order,
    required this.busy,
    required this.highlighted,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = normalizeOrderStatusForUi(order.status);
    final statusColor = orderStatusColor(status);
    final createdAt = order.createdAt == null
        ? null
        : DateFormat('yyyy/MM/dd HH:mm').format(order.createdAt!.toLocal());
    return Card(
      color: highlighted
          ? scheme.primaryContainer.withValues(alpha: 0.22)
          : null,
      shape: highlighted
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 1.2),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.26),
                    ),
                  ),
                  child: Icon(Icons.receipt_long_rounded, color: statusColor),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${context.lt(ar: 'طلب', en: 'Order')} #${order.id}',
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        order.merchantName,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: scheme.primary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (createdAt != null) ...[
                        const SizedBox(height: 2),
                        Text(
                          createdAt,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ],
                  ),
                ),
                CompanyStatusChip(
                  label: orderStatusLabel(status),
                  color: statusColor,
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _InfoPill(
                  icon: Icons.person_rounded,
                  text: order.customerFullName.isEmpty
                      ? context.lt(ar: 'زبون', en: 'Customer')
                      : order.customerFullName,
                ),
                if (order.customerPhone.isNotEmpty)
                  _InfoPill(
                    icon: Icons.phone_rounded,
                    text: order.customerPhone,
                  ),
                _InfoPill(
                  icon: Icons.payments_rounded,
                  text: formatIqd(order.totalAmount),
                ),
                _InfoPill(
                  icon: order.isMerchantDelivery
                      ? Icons.storefront_rounded
                      : Icons.delivery_dining_rounded,
                  text: order.isMerchantDelivery
                      ? context.lt(ar: 'توصيل الفرع', en: 'Branch delivery')
                      : context.lt(ar: 'توصيل التطبيق', en: 'App delivery'),
                ),
              ],
            ),
            if (order.items.isNotEmpty) ...[
              const SizedBox(height: 12),
              ...order.items
                  .take(4)
                  .map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.productName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${item.quantity} x ${formatIqd(item.unitPrice)}',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
              if (order.items.length > 4)
                Text(
                  context.lt(
                    ar: '+${order.items.length - 4} عناصر أخرى',
                    en: '+${order.items.length - 4} more items',
                  ),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
            ],
            if (order.note?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Text(
                order.note!.trim(),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.74),
                ),
              ),
            ],
            const SizedBox(height: 12),
            if (busy)
              const LinearProgressIndicator(minHeight: 2)
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _actionsFor(order)
                    .map(
                      (action) => action.destructive
                          ? OutlinedButton.icon(
                              onPressed: () => onAction(action.status),
                              icon: Icon(action.icon),
                              label: Text(action.label(context)),
                            )
                          : FilledButton.icon(
                              onPressed: () => onAction(action.status),
                              icon: Icon(action.icon),
                              label: Text(action.label(context)),
                            ),
                    )
                    .toList(),
              ),
          ],
        ),
      ),
    );
  }

  List<_OrderAction> _actionsFor(OrderModel order) {
    switch (normalizeOrderStatusForUi(order.status)) {
      case 'pending':
        return const [
          _OrderAction('approved', Icons.check_rounded, 'approve'),
          _OrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'approved':
        return const [
          _OrderAction('preparing', Icons.restaurant_menu_rounded, 'prepare'),
          _OrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'preparing':
        return const [
          _OrderAction('ready_for_delivery', Icons.done_all_rounded, 'ready'),
          _OrderAction('cancelled', Icons.close_rounded, 'reject', true),
        ];
      case 'ready_for_delivery':
        if (!order.isMerchantDelivery) return const [];
        return const [
          _OrderAction('on_the_way', Icons.delivery_dining_rounded, 'way'),
        ];
      case 'on_the_way':
        if (!order.isMerchantDelivery) return const [];
        return const [
          _OrderAction('arrived', Icons.location_on_rounded, 'arrived'),
        ];
      case 'arrived':
        if (!order.isMerchantDelivery) return const [];
        return const [
          _OrderAction('delivered', Icons.task_alt_rounded, 'delivered'),
        ];
      default:
        return const [];
    }
  }
}

class _InfoPill extends StatelessWidget {
  final IconData icon;
  final String text;

  const _InfoPill({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _OrderAction {
  final String status;
  final IconData icon;
  final String key;
  final bool destructive;

  const _OrderAction(
    this.status,
    this.icon,
    this.key, [
    this.destructive = false,
  ]);

  String label(BuildContext context) {
    switch (key) {
      case 'approve':
        return context.lt(ar: 'قبول', en: 'Approve');
      case 'reject':
        return context.lt(ar: 'رفض', en: 'Reject');
      case 'prepare':
        return context.lt(ar: 'تجهيز', en: 'Prepare');
      case 'ready':
        return context.lt(ar: 'جاهز', en: 'Ready');
      case 'way':
        return context.lt(ar: 'بالطريق', en: 'On the way');
      case 'arrived':
        return context.lt(ar: 'وصل', en: 'Arrived');
      case 'delivered':
        return context.lt(ar: 'تم التسليم', en: 'Delivered');
      default:
        return status;
    }
  }
}
