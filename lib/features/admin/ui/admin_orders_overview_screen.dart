import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../../orders/models/order_model.dart';
import '../models/admin_orders_overview_model.dart';
import '../state/admin_controller.dart';

class AdminOrdersOverviewScreen extends ConsumerStatefulWidget {
  final String initialStatus;
  final String? initialTitle;

  const AdminOrdersOverviewScreen({
    super.key,
    this.initialStatus = 'all',
    this.initialTitle,
  });

  @override
  ConsumerState<AdminOrdersOverviewScreen> createState() =>
      _AdminOrdersOverviewScreenState();
}

class _AdminOrdersOverviewScreenState
    extends ConsumerState<AdminOrdersOverviewScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  bool _loading = true;
  String? _error;
  String _status = 'all';
  String _period = 'all';
  DateTimeRange? _customRange;
  AdminOrdersOverviewSummary _summary = const AdminOrdersOverviewSummary(
    totalOrders: 0,
    completedOrders: 0,
    cancelledOrders: 0,
    inProgressOrders: 0,
  );
  List<AdminOrdersOverviewMerchant> _items = const [];

  @override
  void initState() {
    super.initState();
    _status = widget.initialStatus;
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
      locale: Localizations.localeOf(context),
    );
    if (range == null) return;
    setState(() {
      _period = 'custom';
      _customRange = range;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(adminApiProvider)
          .ordersOverview(
            status: _status,
            period: _period,
            from: _customRange?.start.toIso8601String(),
            to: _customRange?.end.toIso8601String(),
            search: _searchCtrl.text,
          );
      final summary = AdminOrdersOverviewSummary.fromJson(
        Map<String, dynamic>.from((raw['summary'] as Map?) ?? const {}),
      );
      final items = List<dynamic>.from(raw['items'] as List? ?? const [])
          .map(
            (item) => AdminOrdersOverviewMerchant.fromJson(
              Map<String, dynamic>.from(item as Map),
            ),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _items = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.adminOrdersOverviewLoadFailed,
        );
      });
    }
  }

  String _title(BuildContext context) {
    if ((widget.initialTitle ?? '').trim().isNotEmpty) {
      return widget.initialTitle!;
    }
    final l10n = context.l10n;
    return switch (_status) {
      'completed' => l10n.adminOrdersOverviewTitleCompletedOrders,
      'cancelled' => l10n.adminOrdersOverviewTitleCancelledOrders,
      'in_progress' => l10n.adminOrdersOverviewTitleInProgressOrders,
      _ => l10n.adminOrdersOverviewTitleAllOrders,
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title(context)),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const ['all', 'day', 'week', 'month', 'year'])
                  ChoiceChip(
                    label: Text(_periodFilterLabel(context, option)),
                    selected: _period == option,
                    onSelected: (_) async {
                      setState(() => _period = option);
                      await _load();
                    },
                  ),
                ActionChip(
                  label: Text(l10n.commonCustomRange),
                  onPressed: _pickCustomRange,
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _searchCtrl,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _load(),
              decoration: InputDecoration(
                labelText: l10n.adminOrdersOverviewSearchMerchants,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: IconButton(
                  onPressed: _load,
                  icon: const Icon(Icons.arrow_forward_rounded),
                ),
              ),
            ),
            const SizedBox(height: 16),
            _SummaryRow(summary: _summary),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _InfoCard(text: _error!, isError: true)
            else if (_items.isEmpty)
              _InfoCard(text: l10n.adminOrdersOverviewNoMerchantsMatch)
            else
              ..._items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: const CircleAvatar(
                      child: Icon(Icons.storefront_outlined),
                    ),
                    title: Text(
                      item.merchantName,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if ((item.ownerFullName ?? '').trim().isNotEmpty)
                            Text(
                              l10n.adminOrdersOverviewOwnerLabel(
                                item.ownerFullName!,
                              ),
                            ),
                          Text(
                            l10n.adminOrdersOverviewOrdersCount(
                              item.ordersCount,
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: FilledButton.tonal(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => AdminMerchantOrdersListScreen(
                              merchantId: item.merchantId,
                              merchantName: item.merchantName,
                              initialStatus: _status,
                              initialPeriod: _period,
                              initialRange: _customRange,
                            ),
                          ),
                        );
                      },
                      child: Text(l10n.commonOpen),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class AdminMerchantOrdersListScreen extends ConsumerStatefulWidget {
  final int merchantId;
  final String merchantName;
  final String initialStatus;
  final String initialPeriod;
  final DateTimeRange? initialRange;

  const AdminMerchantOrdersListScreen({
    super.key,
    required this.merchantId,
    required this.merchantName,
    required this.initialStatus,
    this.initialPeriod = 'all',
    this.initialRange,
  });

  @override
  ConsumerState<AdminMerchantOrdersListScreen> createState() =>
      _AdminMerchantOrdersListScreenState();
}

class _AdminMerchantOrdersListScreenState
    extends ConsumerState<AdminMerchantOrdersListScreen> {
  bool _loading = true;
  String? _error;
  late final String _status = widget.initialStatus;
  late String _period = widget.initialPeriod;
  late DateTimeRange? _customRange = widget.initialRange;
  List<OrderModel> _orders = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
      locale: Localizations.localeOf(context),
    );
    if (range == null) return;
    setState(() {
      _period = 'custom';
      _customRange = range;
    });
    await _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(adminApiProvider)
          .merchantOrdersOverview(
            widget.merchantId,
            status: _status,
            period: _period,
            from: _customRange?.start.toIso8601String(),
            to: _customRange?.end.toIso8601String(),
          );
      final items = List<dynamic>.from(raw['items'] as List? ?? const [])
          .map(
            (item) =>
                OrderModel.fromJson(Map<String, dynamic>.from(item as Map)),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _orders = items;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.adminOrdersOverviewMerchantOrdersLoadFailed,
        );
      });
    }
  }

  Future<void> _showOrderDetails(OrderModel order) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (bottomSheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.adminOrdersOverviewOrderDetailsTitle(order.id),
                  style: Theme.of(bottomSheetContext).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                _DetailRow(
                  label: l10n.commonStatus,
                  value: _statusLabel(context, order.status),
                ),
                _DetailRow(
                  label: l10n.commonCustomer,
                  value: order.customerFullName,
                ),
                _DetailRow(
                  label: l10n.commonTotal,
                  value: formatIqd(order.totalAmount),
                ),
                _DetailRow(
                  label: l10n.commonSubtotal,
                  value: formatIqd(order.subtotal),
                ),
                _DetailRow(
                  label: l10n.commonDeliveryFee,
                  value: formatIqd(order.deliveryFee),
                ),
                _DetailRow(
                  label: l10n.commonServiceFee,
                  value: formatIqd(order.serviceFee),
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.commonItems,
                  style: Theme.of(bottomSheetContext).textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                if (order.items.isEmpty)
                  Text(l10n.commonNoItems)
                else
                  ...order.items.map(
                    (item) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          Text(formatIqd(item.lineTotal)),
                          const Spacer(),
                          Text('${item.quantity}x ${item.productName}'),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(BuildContext context, String status) {
    final l10n = context.l10n;
    return switch (status.trim().toLowerCase()) {
      'delivered' || 'completed' || 'received' => l10n.commonCompleted,
      'cancelled' => l10n.commonCancelled,
      _ => l10n.commonInProgress,
    };
  }

  Color _statusColor(String status, BuildContext context) {
    final normalized = status.trim().toLowerCase();
    if (normalized == 'cancelled') return Theme.of(context).colorScheme.error;
    if (normalized == 'delivered' ||
        normalized == 'completed' ||
        normalized == 'received') {
      return Colors.greenAccent.shade400;
    }
    return Theme.of(context).colorScheme.primary;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.merchantName),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final option in const ['all', 'day', 'week', 'month', 'year'])
                  ChoiceChip(
                    label: Text(_periodFilterLabel(context, option)),
                    selected: _period == option,
                    onSelected: (_) async {
                      setState(() => _period = option);
                      await _load();
                    },
                  ),
                ActionChip(
                  label: Text(l10n.commonCustomRange),
                  onPressed: _pickCustomRange,
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_error != null)
              _InfoCard(text: _error!, isError: true)
            else if (_orders.isEmpty)
              _InfoCard(text: l10n.adminOrdersOverviewNoOrdersForFilter)
            else
              ..._orders.map(
                (order) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    onTap: () => _showOrderDetails(order),
                    title: Text(
                      l10n.adminOrdersOverviewOrderTitle(order.id),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    subtitle: Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(order.customerFullName),
                          const SizedBox(height: 4),
                          Text(
                            l10n.adminOrdersOverviewAmountsSummary(
                              formatIqd(order.subtotal),
                              formatIqd(order.totalAmount),
                            ),
                          ),
                        ],
                      ),
                    ),
                    trailing: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: _statusColor(
                          order.status,
                          context,
                        ).withValues(alpha: 0.14),
                      ),
                      child: Text(
                        _statusLabel(context, order.status),
                        style: TextStyle(
                          color: _statusColor(order.status, context),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _SummaryRow extends StatelessWidget {
  final AdminOrdersOverviewSummary summary;

  const _SummaryRow({required this.summary});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _SummaryCard(
          title: l10n.commonTotalOrders,
          value: '${summary.totalOrders}',
        ),
        _SummaryCard(
          title: l10n.commonCompleted,
          value: '${summary.completedOrders}',
        ),
        _SummaryCard(
          title: l10n.commonCancelled,
          value: '${summary.cancelledOrders}',
        ),
        _SummaryCard(
          title: l10n.commonInProgress,
          value: '${summary.inProgressOrders}',
        ),
      ],
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String value;

  const _SummaryCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  final String text;
  final bool isError;

  const _InfoCard({required this.text, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = isError ? scheme.error : scheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(text, style: TextStyle(color: color)),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final String label;
  final String value;

  const _DetailRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(child: Text(value)),
          const SizedBox(width: 12),
          Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

String _periodFilterLabel(BuildContext context, String period) {
  final l10n = context.l10n;
  return switch (period) {
    'day' => l10n.commonDay,
    'week' => l10n.commonWeek,
    'month' => l10n.commonMonth,
    'year' => l10n.commonYear,
    _ => l10n.commonAll,
  };
}
