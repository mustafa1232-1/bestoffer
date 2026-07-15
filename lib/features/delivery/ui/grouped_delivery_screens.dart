import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/grouped_delivery_job.dart';
import '../state/grouped_delivery_controller.dart';

Future<void> _safeLaunch(Uri uri) async {
  try {
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  } catch (_) {
    // Navigation/dial is best-effort; never crash the delivery flow.
  }
}

Future<void> _dial(String? phone) async {
  final p = (phone ?? '').trim();
  if (p.isEmpty) return;
  await _safeLaunch(Uri(scheme: 'tel', path: p));
}

Future<void> _navigateTo(double? lat, double? lng, String? label) async {
  if (lat == null || lng == null) return;
  await _safeLaunch(Uri.parse('geo:$lat,$lng?q=$lat,$lng(${Uri.encodeComponent(label ?? '')})'));
}

/// Grouped multi-store delivery UI (delivery closure client §3/§4).
///
/// A self-contained section embedded at the top of the Delivery dashboard plus a
/// full details screen and a history list. All state comes from
/// [groupedDeliveryControllerProvider]; a completed job leaves Current and moves
/// to History (the controller enforces this).

String _statusAr(String pickupStatus) {
  switch (pickupStatus.toUpperCase()) {
    case 'WAITING_STORE_ACCEPTANCE':
      return 'بانتظار قبول المتجر';
    case 'PREPARING':
      return 'قيد التحضير';
    case 'READY':
      return 'جاهز للاستلام';
    case 'COURIER_ARRIVED':
      return 'وصل المندوب';
    case 'COLLECTED':
      return 'تم الاستلام';
    case 'CANCELLED':
      return 'ملغي';
    default:
      return pickupStatus;
  }
}

/// Dashboard entry point: shows the active grouped job card (or nothing).
class GroupedDeliveryDashboardSection extends ConsumerWidget {
  const GroupedDeliveryDashboardSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupedDeliveryControllerProvider);
    final controller = ref.read(groupedDeliveryControllerProvider.notifier);

    if (state.loading && state.job == null) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    // §4: an error with no job must NOT read as "no active job".
    if (state.isErrorWithoutJob) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Card(
          key: const Key('grouped_error_card'),
          color: Colors.red.withValues(alpha: 0.06),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(state.error ?? 'تعذّر تحميل المهمة',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: OutlinedButton.icon(
                    key: const Key('grouped_retry'),
                    onPressed: controller.resync,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة المحاولة'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    final job = state.job;
    if (job == null || job.isTerminal) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: _GroupedJobCard(job: job, cached: state.cachedOffline),
    );
  }
}

class _GroupedJobCard extends ConsumerWidget {
  final GroupedDeliveryJob job;
  final bool cached;
  const _GroupedJobCard({required this.job, this.cached = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('grouped_job_card'),
      elevation: 2,
      child: InkWell(
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const GroupedDeliveryDetailsScreen()),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cached)
                Container(
                  key: const Key('grouped_cached_banner'),
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  color: Colors.orange.withValues(alpha: 0.15),
                  child: const Text('نسخة مخزّنة — بانتظار المزامنة',
                      style: TextStyle(fontSize: 12)),
                ),
              Row(
                children: [
                  const Icon(Icons.storefront_outlined),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      job.storesLabel,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ),
                  const Icon(Icons.chevron_left),
                ],
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: job.numberOfStores == 0
                    ? 0
                    : job.collectedCount / job.numberOfStores,
              ),
              const SizedBox(height: 6),
              Text(
                'تم استلام ${job.collectedCount} من ${job.numberOfStores} متاجر',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (job.paymentMethod != null)
                    _chip(Icons.payments_outlined, 'الدفع: ${job.paymentMethod}'),
                  _chip(Icons.account_balance_wallet_outlined,
                      'أرباحك: ${job.courierEarning.toStringAsFixed(0)}'),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [Icon(icon, size: 16), const SizedBox(width: 4), Text(label)],
      );
}

/// Full grouped-job details with per-stop cards and lifecycle actions.
class GroupedDeliveryDetailsScreen extends ConsumerWidget {
  const GroupedDeliveryDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(groupedDeliveryControllerProvider);
    final controller = ref.read(groupedDeliveryControllerProvider.notifier);
    final job = state.job;

    return Scaffold(
      appBar: AppBar(
        title: const Text('تفاصيل المهمة'),
        actions: [
          IconButton(
            key: const Key('open_history_from_details'),
            icon: const Icon(Icons.history),
            tooltip: 'السجل',
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const GroupedDeliveryHistoryScreen())),
          ),
        ],
      ),
      body: job == null
          ? const Center(child: Text('لا توجد مهمة نشطة'))
          : RefreshIndicator(
              onRefresh: controller.refresh,
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  Text(job.storesLabel,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  if (state.cachedOffline)
                    Container(
                      key: const Key('grouped_details_cached_banner'),
                      padding: const EdgeInsets.all(8),
                      color: Colors.orange.withValues(alpha: 0.15),
                      child: const Text('نسخة مخزّنة — الإجراءات معطّلة حتى المزامنة'),
                    ),
                  if (state.error != null)
                    Container(
                      key: const Key('grouped_error_banner'),
                      padding: const EdgeInsets.all(8),
                      color: Colors.red.withValues(alpha: 0.1),
                      child: Text(state.error!,
                          style: const TextStyle(color: Colors.red)),
                    ),
                  const SizedBox(height: 8),
                  ...job.activeStops.map((s) => _StopCard(
                      stop: s,
                      controller: controller,
                      saving: state.saving || state.mutationsBlocked)),
                  const SizedBox(height: 12),
                  if (job.customer != null) _CustomerDestinationCard(job: job),
                  const SizedBox(height: 24),
                ],
              ),
            ),
      // Lifecycle actions live in a persistent bottom bar so they are always
      // visible and reachable regardless of scroll position.
      bottomNavigationBar: job == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: _lifecycleActions(
                    context, job, controller, state.saving || state.mutationsBlocked),
              ),
            ),
    );
  }

  Widget _lifecycleActions(
    BuildContext context,
    GroupedDeliveryJob job,
    GroupedDeliveryController controller,
    bool saving,
  ) {
    final buttons = <Widget>[];
    if (job.lifecycle == GroupedJobLifecycle.assigned) {
      buttons.add(_action('قبول المهمة', const Key('act_acknowledge'),
          saving ? null : controller.acknowledge));
    }
    if (job.lifecycle == GroupedJobLifecycle.acknowledged ||
        job.lifecycle == GroupedJobLifecycle.assigned) {
      buttons.add(_action('التوجه إلى المتاجر', const Key('act_heading_pickups'),
          saving ? null : controller.headingToPickups));
    }
    buttons.add(_action(
      'التوجه إلى الزبون',
      const Key('act_heading_customer'),
      (saving || !job.canHeadToCustomer) ? null : controller.headingToCustomer,
    ));
    buttons.add(_action(
      'تم التسليم',
      const Key('act_delivered'),
      (saving || !job.canDeliver) ? null : controller.markDelivered,
    ));
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in buttons) Padding(padding: const EdgeInsets.only(bottom: 8), child: b),
      ],
    );
  }

  Widget _action(String label, Key key, VoidCallback? onPressed) =>
      ElevatedButton(key: key, onPressed: onPressed, child: Text(label));
}

class _StopCard extends StatelessWidget {
  final DeliveryPickupStop stop;
  final GroupedDeliveryController controller;
  final bool saving;
  const _StopCard({required this.stop, required this.controller, required this.saving});

  @override
  Widget build(BuildContext context) {
    return Card(
      key: Key('stop_card_${stop.stopId}'),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(radius: 14, child: Text('${stop.sequence}')),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(stop.storeName,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
                Text(_statusAr(stop.pickupStatus),
                    key: Key('stop_status_${stop.stopId}')),
              ],
            ),
            const SizedBox(height: 4),
            Text('طلب رقم #${stop.childOrderId}',
                style: Theme.of(context).textTheme.bodySmall),
            if (stop.storeAddress != null && '${stop.storeAddress}'.trim().isNotEmpty)
              Text('العنوان: ${stop.storeAddress}'),
            if (stop.arrivedAt != null)
              Text('وقت الوصول: ${_time(stop.arrivedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall),
            if (stop.collectedAt != null)
              Text('وقت الاستلام: ${_time(stop.collectedAt!)}',
                  style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 6),
            Row(
              children: [
                IconButton(
                  key: Key('stop_call_${stop.stopId}'),
                  icon: const Icon(Icons.call, size: 20),
                  tooltip: 'اتصال بالمتجر',
                  onPressed: stop.storePhone == null ? null : () => _dial(stop.storePhone),
                ),
                IconButton(
                  key: Key('stop_navigate_${stop.stopId}'),
                  icon: const Icon(Icons.navigation_outlined, size: 20),
                  tooltip: 'الملاحة إلى المتجر',
                  onPressed: (stop.latitude == null || stop.longitude == null)
                      ? null
                      : () => _navigateTo(stop.latitude, stop.longitude, stop.storeName),
                ),
              ],
            ),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: Key('stop_arrived_${stop.stopId}'),
                    onPressed: (saving || stop.hasArrived)
                        ? null
                        : () => controller.arrivedAtStore(stop.stopId),
                    child: const Text('وصلت'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    key: Key('stop_collected_${stop.stopId}'),
                    onPressed: (saving || stop.isCollected)
                        ? null
                        : () => controller.collectStore(stop.stopId),
                    child: const Text('تم الاستلام'),
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

String _time(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

/// One customer drop-off section for the whole grouped job.
class _CustomerDestinationCard extends StatelessWidget {
  final GroupedDeliveryJob job;
  const _CustomerDestinationCard({required this.job});

  @override
  Widget build(BuildContext context) {
    final d = job.customer!;
    return Card(
      key: const Key('customer_destination_card'),
      color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.25),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.person_pin_circle_outlined),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('وجهة الزبون: ${d.displayName ?? 'الزبون'}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (d.address != null) Text('العنوان: ${d.address}'),
            if (d.deliveryNotes != null && d.deliveryNotes!.trim().isNotEmpty)
              Text('ملاحظات: ${d.deliveryNotes}'),
            const SizedBox(height: 4),
            Row(
              children: [
                _kv('طريقة الدفع', job.paymentMethod ?? '-'),
                const SizedBox(width: 16),
                _kv('المبلغ المطلوب', job.amountToCollect.toStringAsFixed(0)),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    key: const Key('customer_call'),
                    icon: const Icon(Icons.call, size: 18),
                    label: const Text('اتصال'),
                    onPressed: d.phone == null ? null : () => _dial(d.phone),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    key: const Key('customer_navigate'),
                    icon: const Icon(Icons.navigation, size: 18),
                    label: const Text('الملاحة'),
                    onPressed: d.hasCoordinates
                        ? () => _navigateTo(d.latitude, d.longitude, d.displayName)
                        : null,
                  ),
                ),
              ],
            ),
            if (!d.hasCoordinates)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: Text('لا تتوفر إحداثيات دقيقة للوجهة',
                    style: TextStyle(fontSize: 11, color: Colors.grey)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(k, style: const TextStyle(fontSize: 11, color: Colors.grey)),
          Text(v, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      );
}

/// Grouped-job history (delivery closure client §4). Shows completed and
/// reassigned-away assignments from the typed history model.
class GroupedDeliveryHistoryScreen extends ConsumerStatefulWidget {
  const GroupedDeliveryHistoryScreen({super.key});

  @override
  ConsumerState<GroupedDeliveryHistoryScreen> createState() =>
      _GroupedDeliveryHistoryScreenState();
}

class _GroupedDeliveryHistoryScreenState
    extends ConsumerState<GroupedDeliveryHistoryScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
        () => ref.read(groupedDeliveryControllerProvider.notifier).loadHistory());
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(groupedDeliveryControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('سجل المهام المجمّعة')),
      body: state.historyLoading
          ? const Center(child: CircularProgressIndicator())
          : state.history.isEmpty
              ? const Center(
                  key: Key('grouped_history_empty'),
                  child: Text('لا يوجد سجل بعد'))
              : RefreshIndicator(
                  onRefresh: ref
                      .read(groupedDeliveryControllerProvider.notifier)
                      .loadHistory,
                  child: ListView.builder(
                    itemCount: state.history.length,
                    itemBuilder: (_, i) => _HistoryTile(row: state.history[i]),
                  ),
                ),
    );
  }
}

class _HistoryTile extends StatelessWidget {
  final GroupedDeliveryAssignmentHistory row;
  const _HistoryTile({required this.row});

  @override
  Widget build(BuildContext context) {
    final subtitle = row.wasReassignedAway
        ? 'أُعيد تعيينها (${row.endedReason})'
        : row.isCompleted
            ? 'مكتملة'
            : row.lifecycleStatus;
    return ListTile(
      key: Key('history_row_${row.assignmentId}'),
      leading: Icon(row.isCompleted ? Icons.check_circle : Icons.swap_horiz),
      title: Text('طلب من ${row.storeCount} متاجر'),
      subtitle: Text(subtitle),
      trailing: Text('#${row.deliveryJobId}'),
    );
  }
}
