import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart' as intl;

import '../../../core/i18n/app_strings.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/models/order_model.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../settings/ui/pages/settings_support_screen.dart';
import '../state/delivery_controller.dart';

enum _DeliveryTab { dashboard, current, history, profile }

class DeliveryDashboardScreen extends ConsumerStatefulWidget {
  const DeliveryDashboardScreen({super.key});

  @override
  ConsumerState<DeliveryDashboardScreen> createState() =>
      _DeliveryDashboardScreenState();
}

class _DeliveryDashboardScreenState
    extends ConsumerState<DeliveryDashboardScreen> {
  _DeliveryTab activeTab = _DeliveryTab.dashboard;
  DateTime? historyDateFilter;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(deliveryControllerProvider.notifier).bootstrap(),
    );
  }

  String _tabTitle(AppStrings strings) {
    switch (activeTab) {
      case _DeliveryTab.dashboard:
        return strings.t('deliveryDashboard');
      case _DeliveryTab.current:
        return 'الطلبات الحالية';
      case _DeliveryTab.history:
        return 'السجل المؤرشف';
      case _DeliveryTab.profile:
        return 'الملف الشخصي';
    }
  }

  Future<void> _openAccountSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsAccountScreen()));
  }

  Future<void> _openSupportSettings() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const SettingsSupportScreen()));
  }

  Future<void> _pickHistoryDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: historyDateFilter ?? DateTime.now(),
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      locale: const Locale('ar'),
    );
    if (picked == null) return;
    setState(() => historyDateFilter = picked);
    final date = intl.DateFormat('yyyy-MM-dd').format(picked);
    await ref
        .read(deliveryControllerProvider.notifier)
        .bootstrap(historyDate: date);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);

    ref.listen<DeliveryState>(deliveryControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (next.lastArchiveMessage != null &&
          next.lastArchiveMessage != prev?.lastArchiveMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.lastArchiveMessage!)));
      }
    });

    return Scaffold(
      drawer: AppUserDrawer(
        title: _tabTitle(strings),
        subtitle: strings.t('drawerDeliverySub'),
        items: [
          AppUserDrawerItem(
            icon: Icons.dashboard_outlined,
            label: 'لوحة التحكم',
            onTap: (_) async =>
                setState(() => activeTab = _DeliveryTab.dashboard),
          ),
          AppUserDrawerItem(
            icon: Icons.local_shipping_outlined,
            label: 'الطلبات الحالية',
            onTap: (_) async =>
                setState(() => activeTab = _DeliveryTab.current),
          ),
          AppUserDrawerItem(
            icon: Icons.history_rounded,
            label: 'السجل المؤرشف',
            onTap: (_) async =>
                setState(() => activeTab = _DeliveryTab.history),
          ),
          AppUserDrawerItem(
            icon: Icons.person_outline_rounded,
            label: 'الملف الشخصي',
            onTap: (_) async =>
                setState(() => activeTab = _DeliveryTab.profile),
          ),
          AppUserDrawerItem(
            icon: Icons.refresh_rounded,
            label: strings.t('drawerRefresh'),
            onTap: (_) async =>
                ref.read(deliveryControllerProvider.notifier).bootstrap(),
          ),
          AppUserDrawerItem(
            icon: Icons.archive_outlined,
            label: 'إنهاء اليوم',
            onTap: (_) async {
              await ref.read(deliveryControllerProvider.notifier).endDay();
            },
          ),
        ],
      ),
      appBar: AppBar(
        title: Text(_tabTitle(strings)),
        actions: [
          if (activeTab == _DeliveryTab.history)
            IconButton(
              onPressed: _pickHistoryDate,
              icon: const Icon(Icons.event_outlined),
              tooltip: 'تصفية حسب التاريخ',
            ),
          const NotificationsBellButton(),
        ],
      ),
      floatingActionButton:
          activeTab == _DeliveryTab.dashboard ||
              activeTab == _DeliveryTab.current
          ? FloatingActionButton.extended(
              onPressed: state.saving
                  ? null
                  : () async {
                      await ref
                          .read(deliveryControllerProvider.notifier)
                          .endDay();
                    },
              icon: const Icon(Icons.archive_outlined),
              label: const Text('إنهاء اليوم'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(deliveryControllerProvider.notifier).bootstrap(),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : _buildDeliveryTabBody(state: state, auth: auth),
      ),
    );
  }

  Widget _buildDeliveryTabBody({
    required DeliveryState state,
    required AuthState auth,
  }) {
    switch (activeTab) {
      case _DeliveryTab.dashboard:
        return _buildDashboardBody(state);
      case _DeliveryTab.current:
        return _buildCurrentOrdersBody(state);
      case _DeliveryTab.history:
        return _buildHistoryBody(state);
      case _DeliveryTab.profile:
        return _buildProfileBody(state: state, auth: auth);
    }
  }

  Widget _buildDashboardBody(DeliveryState state) {
    final day = _DeliveryPeriod.fromMap(state.analytics['day']);
    final onWayCount = state.currentOrders
        .where((o) => o.status == 'on_the_way')
        .length;
    final readyCount = state.currentOrders
        .where((o) => o.status == 'ready_for_delivery')
        .length;

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _DeliveryInsights(analytics: state.analytics),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _DeliveryMetricTile(
              icon: Icons.local_shipping_outlined,
              label: 'الطلبات الحالية',
              value: '${state.currentOrders.length}',
            ),
            _DeliveryMetricTile(
              icon: Icons.two_wheeler_outlined,
              label: 'قيد التوصيل',
              value: '$onWayCount',
            ),
            _DeliveryMetricTile(
              icon: Icons.store_mall_directory_outlined,
              label: 'بانتظار الاستلام',
              value: '$readyCount',
            ),
            _DeliveryMetricTile(
              icon: Icons.archive_outlined,
              label: 'طلبات اليوم المكتملة',
              value: '${day.deliveredOrdersCount}',
            ),
            _DeliveryMetricTile(
              icon: Icons.payments_outlined,
              label: 'أجور التوصيل اليوم',
              value: formatIqd(day.deliveryFees),
            ),
            _DeliveryMetricTile(
              icon: Icons.star_border_rounded,
              label: 'التقييم',
              value: day.avgRating.toStringAsFixed(1),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _ActionCard(
          title: 'وصول سريع',
          child: Column(
            children: [
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.local_shipping_outlined),
                title: const Text('فتح الطلبات الحالية'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => activeTab = _DeliveryTab.current),
              ),
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.history_rounded),
                title: const Text('فتح سجل الطلبات'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => setState(() => activeTab = _DeliveryTab.history),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildCurrentOrdersBody(DeliveryState state) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        const _SectionTitle('الطلبات الحالية'),
        if (state.currentOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('لا توجد طلبات حالية'),
          )
        else
          ...state.currentOrders.map((o) => _CurrentOrderCard(order: o)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildHistoryBody(DeliveryState state) {
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ActionCard(
          title: 'فلترة السجل',
          child: Row(
            children: [
              Expanded(
                child: Text(
                  historyDateFilter == null
                      ? 'كل الأيام'
                      : intl.DateFormat(
                          'yyyy-MM-dd',
                        ).format(historyDateFilter!),
                ),
              ),
              OutlinedButton.icon(
                onPressed: _pickHistoryDate,
                icon: const Icon(Icons.event_outlined),
                label: const Text('اختيار يوم'),
              ),
              const SizedBox(width: 8),
              if (historyDateFilter != null)
                TextButton(
                  onPressed: () async {
                    setState(() => historyDateFilter = null);
                    await ref
                        .read(deliveryControllerProvider.notifier)
                        .bootstrap();
                  },
                  child: const Text('مسح'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        const _SectionTitle('الطلبات المؤرشفة'),
        if (state.historyOrders.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text('لا توجد طلبات مؤرشفة'),
          )
        else
          ...state.historyOrders.map((o) => _HistoryOrderCard(order: o)),
        const SizedBox(height: 80),
      ],
    );
  }

  Widget _buildProfileBody({
    required DeliveryState state,
    required AuthState auth,
  }) {
    final user = auth.user;
    final day = _DeliveryPeriod.fromMap(state.analytics['day']);

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        _ActionCard(
          title: 'الملف الشخصي',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 20,
                  backgroundImage: user?.imageUrl?.isNotEmpty == true
                      ? NetworkImage(user!.imageUrl!)
                      : null,
                  child: user?.imageUrl?.isNotEmpty == true
                      ? null
                      : const Icon(Icons.person_outline),
                ),
                title: Text(user?.fullName ?? '-'),
                subtitle: Text(user?.phone ?? '-'),
              ),
              Text(
                'العنوان: بلوك ${user?.block ?? '-'} - عمارة ${user?.buildingNumber ?? '-'} - شقة ${user?.apartment ?? '-'}',
                textDirection: TextDirection.rtl,
              ),
              const SizedBox(height: 8),
              Text(
                'طلبات اليوم المكتملة: ${day.deliveredOrdersCount}',
                textDirection: TextDirection.rtl,
              ),
              Text(
                'أجور اليوم: ${formatIqd(day.deliveryFees)}',
                textDirection: TextDirection.rtl,
              ),
              Text(
                'تقييم اليوم: ${day.avgRating.toStringAsFixed(1)}',
                textDirection: TextDirection.rtl,
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        _ActionCard(
          title: 'إدارة الحساب',
          child: Column(
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _openAccountSettings,
                  icon: const Icon(Icons.security_outlined),
                  label: const Text('تعديل رقم الهاتف والـ PIN'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _openSupportSettings,
                  icon: const Icon(Icons.support_agent_rounded),
                  label: const Text('الدعم والمساعدة'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _DeliveryMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DeliveryMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 152,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.08),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _ActionCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 8),
            child,
          ],
        ),
      ),
    );
  }
}

class _DeliveryInsights extends StatelessWidget {
  final Map<String, dynamic> analytics;

  const _DeliveryInsights({required this.analytics});

  @override
  Widget build(BuildContext context) {
    final day = _DeliveryPeriod.fromMap(analytics['day']);
    final month = _DeliveryPeriod.fromMap(analytics['month']);
    final year = _DeliveryPeriod.fromMap(analytics['year']);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'تحليلات الدلفري',
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            _InsightTile('اليوم', day),
            _InsightTile('الشهر', month),
            _InsightTile('السنة', year),
          ],
        ),
      ),
    );
  }
}

class _InsightTile extends StatelessWidget {
  final String label;
  final _DeliveryPeriod period;

  const _InsightTile(this.label, this.period);

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      title: Text(
        '$label: ${period.deliveredOrdersCount} طلب مكتمل',
        textDirection: TextDirection.rtl,
      ),
      subtitle: Text(
        'رسوم التوصيل: ${formatIqd(period.deliveryFees)} | تقييم: ${period.avgRating.toStringAsFixed(1)}',
        textDirection: TextDirection.rtl,
      ),
    );
  }
}

class _DeliveryPeriod {
  final int deliveredOrdersCount;
  final double deliveryFees;
  final double avgRating;

  const _DeliveryPeriod({
    this.deliveredOrdersCount = 0,
    this.deliveryFees = 0,
    this.avgRating = 0,
  });

  factory _DeliveryPeriod.fromMap(dynamic raw) {
    if (raw is! Map) return const _DeliveryPeriod();
    final map = Map<String, dynamic>.from(raw);
    return _DeliveryPeriod(
      deliveredOrdersCount: _toNum(map['delivered_orders_count']).toInt(),
      deliveryFees: _toNum(map['delivery_fees']),
      avgRating: _toNum(map['avg_rating']),
    );
  }
}

double _toNum(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse('$raw') ?? 0;
}

class _SectionTitle extends StatelessWidget {
  final String text;

  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Text(
        text,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
      ),
    );
  }
}

class _CurrentOrderCard extends ConsumerWidget {
  final OrderModel order;

  const _CurrentOrderCard({required this.order});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assignedToMe = order.deliveryUserId != null;
    final waitingForMerchant =
        assignedToMe &&
        (order.status == 'pending' || order.status == 'preparing');
    final controller = ref.read(deliveryControllerProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'طلب #${order.id} - ${orderStatusLabel(order.status)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 6),
            Text(
              'المتجر: ${order.merchantName}',
              textDirection: TextDirection.rtl,
            ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'الزبون: ${order.customerFullName} - ${order.customerPhone}',
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                  ),
                ),
                if (order.customerImageUrl?.trim().isNotEmpty == true) ...[
                  const SizedBox(width: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: Image.network(
                      order.customerImageUrl!,
                      width: 38,
                      height: 38,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) =>
                          const Icon(Icons.person_outline),
                    ),
                  ),
                ],
              ],
            ),
            Text(
              'الموقع: ${order.customerCity} - بلوك ${order.customerBlock} - عمارة ${order.customerBuildingNumber} - شقة ${order.customerApartment}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 8),
            ...order.items.map(
              (i) => Text(
                '- ${i.productName} x ${i.quantity}',
                textDirection: TextDirection.rtl,
              ),
            ),
            if (order.imageUrl?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  'صورة الطلب',
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  order.imageUrl!,
                  height: 130,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    height: 90,
                    alignment: Alignment.center,
                    color: Colors.black12,
                    child: const Icon(Icons.image_not_supported_outlined),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (waitingForMerchant)
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'بانتظار تجهيز الطلب من المتجر',
                  textDirection: TextDirection.rtl,
                ),
              ),
            Row(
              children: [
                if (!assignedToMe)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => controller.claimOrder(order.id),
                      child: const Text('استلام الطلب'),
                    ),
                  ),
                if (assignedToMe && order.status == 'ready_for_delivery')
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => controller.startOrder(
                        order.id,
                        estimatedDeliveryMinutes:
                            order.estimatedDeliveryMinutes ?? 20,
                      ),
                      child: const Text('بدأت التوصيل'),
                    ),
                  ),
                if (assignedToMe && order.status == 'on_the_way')
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => controller.markDelivered(order.id),
                      child: const Text('تم توصيل الطلب'),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryOrderCard extends StatelessWidget {
  final OrderModel order;

  const _HistoryOrderCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ListTile(
        title: Text(
          'طلب #${order.id} - ${order.customerFullName}',
          textDirection: TextDirection.rtl,
        ),
        subtitle: Text(
          'المتجر: ${order.merchantName} - المجموع: ${formatIqd(order.totalAmount)}',
          textDirection: TextDirection.rtl,
        ),
      ),
    );
  }
}
