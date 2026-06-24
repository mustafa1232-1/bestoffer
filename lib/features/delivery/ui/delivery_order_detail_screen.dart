import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../orders/models/order_model.dart';
import '../../orders/ui/order_chat_screen.dart';
import '../../tracking/ui/delivery_live_tracking_screen.dart';
import '../state/delivery_controller.dart';

class DeliveryOrderDetailScreen extends ConsumerStatefulWidget {
  const DeliveryOrderDetailScreen({super.key, required this.orderId});

  final int orderId;

  @override
  ConsumerState<DeliveryOrderDetailScreen> createState() =>
      _DeliveryOrderDetailScreenState();
}

class _DeliveryOrderDetailScreenState
    extends ConsumerState<DeliveryOrderDetailScreen> {
  Map<String, dynamic>? _detail;
  bool _loading = true;
  bool _actionInFlight = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final detail = await ref
          .read(deliveryApiProvider)
          .orderDetailV2(widget.orderId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _loading = false;
      });
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error =
            '${error.response?.data is Map ? (error.response?.data['message'] ?? '') : ''}'
                .trim();
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'تعذر تحميل تفاصيل الطلب.',
          en: 'Failed to load order details.',
        );
      });
    }
  }

  Map<String, dynamic> get _orderMap {
    final raw = _detail?['order'];
    final out = raw is Map
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    final items = _detail?['items'];
    if (!out.containsKey('items') && items is List) {
      out['items'] = items;
    }
    return out;
  }

  Map<String, dynamic> get _merchant =>
      Map<String, dynamic>.from(_detail?['merchant'] as Map? ?? const {});

  Map<String, dynamic> get _customer =>
      Map<String, dynamic>.from(_detail?['customer'] as Map? ?? const {});

  Map<String, dynamic> get _invoice =>
      Map<String, dynamic>.from(_detail?['invoice'] as Map? ?? const {});

  List<Map<String, dynamic>> get _timeline {
    final raw = _detail?['timeline'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((entry) => Map<String, dynamic>.from(entry))
        .toList(growable: false);
  }

  List<String> get _allowedActions {
    final raw = _detail?['allowedActions'];
    if (raw is! List) return const [];
    return raw.map((entry) => '$entry').toList(growable: false);
  }

  OrderModel? get _order {
    final orderMap = _orderMap;
    if (orderMap.isEmpty) return null;
    try {
      return OrderModel.fromJson(orderMap);
    } catch (_) {
      return null;
    }
  }

  Future<void> _openTracking() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => DeliveryLiveTrackingScreen(orderId: widget.orderId),
      ),
    );
  }

  Future<void> _openChat() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => OrderChatScreen(orderId: widget.orderId),
      ),
    );
  }

  Future<void> _callPhone(String? phone) async {
    final value = (phone ?? '').trim();
    if (value.isEmpty) return;
    await launchUrl(
      Uri.parse('tel:$value'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _runAction(String action) async {
    if (_actionInFlight) return;
    setState(() => _actionInFlight = true);
    final controller = ref.read(deliveryControllerProvider.notifier);
    try {
      switch (action) {
        case 'accept':
          await controller.acceptRequest(widget.orderId);
          break;
        case 'reject':
          await controller.rejectRequest(widget.orderId);
          break;
        case 'picked_up':
          await controller.pickedUpOrder(widget.orderId);
          break;
        case 'arrived':
          await controller.arrivedOrder(widget.orderId);
          break;
        case 'delivered':
          await controller.deliveredOrder(widget.orderId);
          break;
        default:
          break;
      }
      await _load();
    } finally {
      if (mounted) {
        setState(() => _actionInFlight = false);
      }
    }
  }

  Future<void> _openCancelSheet() async {
    final api = ref.read(deliveryApiProvider);
    final reasons = await api.listOrderActionReasons(
      actorScope: 'courier',
      actionKind: 'cancel',
    );
    if (!mounted) return;
    if (reasons.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'لا توجد أسباب إلغاء متاحة حالياً.',
              en: 'No cancellation reasons are available right now.',
            ),
          ),
        ),
      );
      return;
    }

    final textController = TextEditingController();
    String selectedCode = reasons.first.reasonCode;
    bool submitting = false;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final selectedReason = reasons.firstWhere(
              (entry) => entry.reasonCode == selectedCode,
              orElse: () => reasons.first,
            );
            return Padding(
              padding: EdgeInsets.fromLTRB(
                16,
                16,
                16,
                MediaQuery.viewInsetsOf(context).bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    context.lt(
                      ar: 'طلب إلغاء من الدلفري',
                      en: 'Courier cancel request',
                    ),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: selectedCode,
                    items: reasons
                        .map(
                          (entry) => DropdownMenuItem<String>(
                            value: entry.reasonCode,
                            child: Text(entry.label),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: submitting
                        ? null
                        : (value) {
                            if (value == null) return;
                            setSheetState(() => selectedCode = value);
                          },
                    decoration: InputDecoration(
                      labelText: context.lt(ar: 'السبب', en: 'Reason'),
                    ),
                  ),
                  if (selectedReason.allowsOtherText) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: textController,
                      minLines: 2,
                      maxLines: 4,
                      decoration: InputDecoration(
                        labelText: context.lt(
                          ar: 'تفاصيل إضافية',
                          en: 'Details',
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: submitting
                        ? null
                        : () async {
                            setSheetState(() => submitting = true);
                            try {
                              await ref
                                  .read(deliveryControllerProvider.notifier)
                                  .requestCancelOrder(
                                    widget.orderId,
                                    reasonCode: selectedCode,
                                    reasonText: textController.text,
                                  );
                              if (sheetContext.mounted) {
                                Navigator.of(sheetContext).pop(true);
                              }
                            } finally {
                              if (sheetContext.mounted) {
                                setSheetState(() => submitting = false);
                              }
                            }
                          },
                    child: Text(
                      context.lt(ar: 'إرسال الطلب', en: 'Submit request'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    textController.dispose();
    if (submitted == true) {
      await _load();
    }
  }

  double _money(dynamic value) => (value is num)
      ? value.toDouble()
      : double.tryParse('${value ?? ''}') ?? 0;

  String? _string(dynamic value) {
    final output = '${value ?? ''}'.trim();
    return output.isEmpty ? null : output;
  }

  String _actionLabel(String action) {
    switch (action) {
      case 'accept':
        return context.lt(ar: 'قبول الطلب', en: 'Accept order');
      case 'reject':
        return context.lt(ar: 'رفض الطلب', en: 'Reject order');
      case 'picked_up':
        return context.lt(ar: 'تم الاستلام', en: 'Picked up');
      case 'arrived':
        return context.lt(ar: 'وصلت', en: 'Arrived');
      case 'delivered':
        return context.lt(ar: 'تم التسليم', en: 'Delivered');
      case 'request_cancel':
        return context.lt(ar: 'طلب إلغاء', en: 'Request cancel');
      default:
        return action;
    }
  }

  String _orderStateLabel(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'pending':
        return context.lt(ar: 'قيد الانتظار', en: 'Pending');
      case 'accepted':
        return context.lt(ar: 'مقبول', en: 'Accepted');
      case 'preparing':
        return context.lt(ar: 'قيد التحضير', en: 'Preparing');
      case 'ready':
        return context.lt(ar: 'جاهز', en: 'Ready');
      case 'cancelled':
        return context.lt(ar: 'ملغي', en: 'Cancelled');
      case 'returned':
        return context.lt(ar: 'راجع', en: 'Returned');
      default:
        return orderStatusLabel(_string(_orderMap['status']) ?? '');
    }
  }

  String _courierStateLabel(String? value) {
    switch ((value ?? '').trim().toLowerCase()) {
      case 'assigned':
        return context.lt(ar: 'مخصص', en: 'Assigned');
      case 'accepted':
        return context.lt(ar: 'مقبول من السائق', en: 'Accepted');
      case 'picked_up':
        return context.lt(ar: 'تم الاستلام', en: 'Picked up');
      case 'on_the_way':
        return context.lt(ar: 'في الطريق', en: 'On the way');
      case 'arrived':
        return context.lt(ar: 'وصل', en: 'Arrived');
      case 'delivered':
        return context.lt(ar: 'تم التسليم', en: 'Delivered');
      default:
        return context.lt(ar: 'غير محدد', en: 'Unknown');
    }
  }

  @override
  Widget build(BuildContext context) {
    final order = _order;
    final state = ref.watch(deliveryControllerProvider);
    final items = order?.items ?? const [];
    final orderStatus = _string(_orderMap['orderState']);
    final courierState = _string(_orderMap['courierState']);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          order == null
              ? context.lt(ar: 'تفاصيل الطلب', en: 'Order details')
              : '${context.lt(ar: 'طلب', en: 'Order')} #${order.id}',
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null || order == null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      (_error ?? '').isEmpty
                          ? context.lt(
                              ar: 'تعذر تحميل تفاصيل الطلب.',
                              en: 'Failed to load order details.',
                            )
                          : _error!,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _load,
                      child: Text(
                        context.lt(ar: 'إعادة المحاولة', en: 'Retry'),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusChip(
                              label:
                                  '${context.lt(ar: 'حالة الطلب', en: 'Order')}: ${_orderStateLabel(orderStatus)}',
                            ),
                            _StatusChip(
                              label:
                                  '${context.lt(ar: 'حالة السائق', en: 'Courier')}: ${_courierStateLabel(courierState)}',
                            ),
                            _StatusChip(
                              label:
                                  '${context.lt(ar: 'الإجمالي', en: 'Total')}: ${formatIqd(order.totalAmount)}',
                            ),
                          ],
                        ),
                        if ((state.error ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: 12),
                          Text(
                            state.error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _SectionCard(
                    title: context.lt(ar: 'الملخص', en: 'Summary'),
                    child: Column(
                      children: [
                        _InfoRow(
                          label: context.lt(ar: 'المتجر', en: 'Merchant'),
                          value:
                              _string(_merchant['name']) ?? order.merchantName,
                        ),
                        _InfoRow(
                          label: context.lt(ar: 'العميل', en: 'Customer'),
                          value:
                              _string(_customer['fullName']) ??
                              order.customerFullName,
                        ),
                        _InfoRow(
                          label: context.lt(ar: 'العنوان', en: 'Address'),
                          value:
                              '${order.customerCity} - ${order.customerBlock} - ${order.customerBuildingNumber} ${order.customerApartment}',
                        ),
                        if ((order.note ?? '').trim().isNotEmpty)
                          _InfoRow(
                            label: context.lt(ar: 'ملاحظات', en: 'Notes'),
                            value: order.note!,
                            multiline: true,
                          ),
                        _InfoRow(
                          label: context.lt(ar: 'الدفع', en: 'Payment'),
                          value:
                              _string(_invoice['paymentMethodOther']) ??
                              _string(_invoice['paymentMethod']) ??
                              context.lt(ar: 'غير محدد', en: 'Not set'),
                        ),
                      ],
                    ),
                  ),
                  _SectionCard(
                    title: context.lt(ar: 'أدوات سريعة', en: 'Quick actions'),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ActionButton(
                          icon: Icons.map_outlined,
                          label: context.lt(ar: 'التتبع', en: 'Tracking'),
                          onPressed: _openTracking,
                        ),
                        _ActionButton(
                          icon: Icons.chat_bubble_outline_rounded,
                          label: context.lt(
                            ar: 'محادثة الطلب',
                            en: 'Order chat',
                          ),
                          onPressed: _openChat,
                        ),
                        _ActionButton(
                          icon: Icons.call_outlined,
                          label: context.lt(
                            ar: 'اتصال بالعميل',
                            en: 'Call customer',
                          ),
                          onPressed: () => _callPhone(order.customerPhone),
                        ),
                        _ActionButton(
                          icon: Icons.storefront_outlined,
                          label: context.lt(
                            ar: 'اتصال بالمتجر',
                            en: 'Call merchant',
                          ),
                          onPressed: () =>
                              _callPhone(_string(_merchant['phone'])),
                        ),
                      ],
                    ),
                  ),
                  _SectionCard(
                    title: context.lt(ar: 'الفاتورة', en: 'Invoice'),
                    child: Column(
                      children: [
                        for (final item in items)
                          _InvoiceItemRow(
                            name: item.productName,
                            quantity: item.quantity,
                            lineTotal: item.lineTotal,
                          ),
                        const Divider(height: 24),
                        _MoneyRow(
                          label: context.lt(
                            ar: 'الإجمالي قبل الخصم',
                            en: 'Gross subtotal',
                          ),
                          amount: _money(_invoice['grossSubtotal']),
                        ),
                        _MoneyRow(
                          label: context.lt(
                            ar: 'خصم المنتجات',
                            en: 'Product discounts',
                          ),
                          amount: _money(_invoice['productDiscountTotal']),
                          negative: true,
                        ),
                        _MoneyRow(
                          label: context.lt(
                            ar: 'المجموع الفرعي',
                            en: 'Subtotal',
                          ),
                          amount: _money(_invoice['subtotal']),
                        ),
                        _MoneyRow(
                          label: context.lt(
                            ar: 'رسوم الخدمة',
                            en: 'Service fee',
                          ),
                          amount: _money(_invoice['serviceFee']),
                        ),
                        _MoneyRow(
                          label: context.lt(
                            ar: 'رسوم التوصيل',
                            en: 'Delivery fee',
                          ),
                          amount: _money(_invoice['deliveryFee']),
                        ),
                        _MoneyRow(
                          label: context.lt(
                            ar: 'خصم الكوبون',
                            en: 'Coupon discount',
                          ),
                          amount: _money(_invoice['couponDiscountTotal']),
                          negative: true,
                        ),
                        const Divider(height: 24),
                        _MoneyRow(
                          label: context.lt(
                            ar: 'الإجمالي النهائي',
                            en: 'Final total',
                          ),
                          amount: _money(_invoice['totalAmount']),
                          emphasized: true,
                        ),
                      ],
                    ),
                  ),
                  _SectionCard(
                    title: context.lt(ar: 'التسلسل الزمني', en: 'Timeline'),
                    child: Column(
                      children: _timeline
                          .map((entry) => _TimelineRow(entry: entry))
                          .toList(growable: false),
                    ),
                  ),
                  if (_allowedActions.isNotEmpty)
                    _SectionCard(
                      title: context.lt(
                        ar: 'إجراءات الحالة',
                        en: 'Status actions',
                      ),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _allowedActions
                            .map((action) {
                              final isCancel = action == 'request_cancel';
                              return FilledButton.tonal(
                                onPressed: _actionInFlight
                                    ? null
                                    : () => isCancel
                                          ? _openCancelSheet()
                                          : _runAction(action),
                                child: Text(_actionLabel(action)),
                              );
                            })
                            .toList(growable: false),
                      ),
                    ),
                ],
              ),
            ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({this.title, required this.child});

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if ((title ?? '').trim().isNotEmpty) ...[
              Text(
                title!,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
            ],
            child,
          ],
        ),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      ),
      child: Text(label),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.multiline = false,
  });

  final String label;
  final String value;
  final bool multiline;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: multiline
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).textTheme.bodySmall?.color,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 7,
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

class _InvoiceItemRow extends StatelessWidget {
  const _InvoiceItemRow({
    required this.name,
    required this.quantity,
    required this.lineTotal,
  });

  final String name;
  final int quantity;
  final double lineTotal;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$name x$quantity',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(width: 12),
          Text(formatIqd(lineTotal)),
        ],
      ),
    );
  }
}

class _MoneyRow extends StatelessWidget {
  const _MoneyRow({
    required this.label,
    required this.amount,
    this.negative = false,
    this.emphasized = false,
  });

  final String label;
  final double amount;
  final bool negative;
  final bool emphasized;

  @override
  Widget build(BuildContext context) {
    final signedValue = negative ? -amount : amount;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(label)),
          const SizedBox(width: 12),
          Text(
            formatIqd(signedValue),
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              fontWeight: emphasized ? FontWeight.w800 : FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _TimelineRow extends StatelessWidget {
  const _TimelineRow({required this.entry});

  final Map<String, dynamic> entry;

  @override
  Widget build(BuildContext context) {
    final label =
        '${entry['labelAr'] ?? entry['labelEn'] ?? entry['key'] ?? '-'}';
    final time = '${entry['time'] ?? ''}'.trim();
    final done = time.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 18,
            color: done ? Theme.of(context).colorScheme.primary : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(
                    context,
                  ).textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                if (time.isNotEmpty)
                  Text(time, style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
