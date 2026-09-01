import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../data/admin_api.dart';
import '../state/admin_controller.dart';

class AdminTaxiCenterScreen extends ConsumerStatefulWidget {
  const AdminTaxiCenterScreen({super.key});

  @override
  ConsumerState<AdminTaxiCenterScreen> createState() =>
      _AdminTaxiCenterScreenState();
}

class _AdminTaxiCenterScreenState extends ConsumerState<AdminTaxiCenterScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _searchController = TextEditingController();
  Map<String, dynamic>? _data;
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _rideStatus = '';
  String _captainStatus = '';

  AdminApi get _api => ref.read(adminApiProvider);

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 3, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabs.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await _api.taxiOverview(
        status: _rideStatus,
        captainStatus: _captainStatus,
        search: _searchController.text,
      );
      if (!mounted) return;
      setState(() => _data = data);
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = _errorMessage(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحميل مركز التكسي');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  String _errorMessage(DioException error) {
    final body = error.response?.data;
    if (body is Map && body['message'] != null) return '${body['message']}';
    return 'تعذر الاتصال بالخادم (${error.response?.statusCode ?? '-'})';
  }

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  List<Map<String, dynamic>> _list(dynamic value) => value is List
      ? value.whereType<Map>().map(Map<String, dynamic>.from).toList()
      : <Map<String, dynamic>>[];

  int _integer(dynamic value) => value is num
      ? value.toInt()
      : int.tryParse(value?.toString() ?? '') ?? 0;

  Future<void> _cancelRide(Map<String, dynamic> ride) async {
    final controller = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('إلغاء الرحلة #${ride['id']}'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 2,
          maxLines: 4,
          textDirection: TextDirection.rtl,
          decoration: const InputDecoration(
            labelText: 'سبب الإلغاء (إلزامي)',
            hintText: 'مثال: عطل بالمركبة أو حالة طارئة',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('رجوع'),
          ),
          FilledButton(
            onPressed: () {
              final value = controller.text.trim();
              if (value.length < 3) return;
              Navigator.pop(dialogContext, value);
            },
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null) return;
    await _runAction(
      () => _api.cancelTaxiRide(rideId: _integer(ride['id']), reason: reason),
      'تم إلغاء الرحلة وتسجيل السبب',
    );
  }

  Future<void> _confirmPayment(Map<String, dynamic> captain) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('تأكيد تسديد باقة الرحلات'),
        content: Text(
          'سيضاف رصيد 15 رحلة للكابتن ${captain['fullName'] ?? ''} مقابل 10,000 دينار. هل استلمت المبلغ؟',
          textDirection: TextDirection.rtl,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('لا'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('نعم، تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _runAction(
      () => _api.confirmTaxiCreditsPayment(
        captainUserId: _integer(captain['id']),
      ),
      'تم تأكيد التسديد وإضافة 15 رحلة',
    );
  }

  Future<void> _runAction(
    Future<void> Function() action,
    String success,
  ) async {
    setState(() => _saving = true);
    try {
      await action();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success)),
      );
      await _load();
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_errorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('مركز إدارة التكسي'),
        actions: [
          IconButton(onPressed: _loading ? null : _load, icon: const Icon(Icons.refresh)),
          const NotificationsBellButton(),
        ],
        bottom: TabBar(
          controller: _tabs,
          tabs: const [
            Tab(text: 'نظرة عامة', icon: Icon(Icons.monitor_heart_outlined)),
            Tab(text: 'الرحلات', icon: Icon(Icons.route_outlined)),
            Tab(text: 'الكباتن والمستحقات', icon: Icon(Icons.badge_outlined)),
          ],
        ),
      ),
      drawer: AppUserDrawer(
        title: 'إدارة مسلكي',
        subtitle: 'قسم التكسي',
        showCommunitySection: false,
        items: [
          AppUserDrawerItem(
            icon: Icons.dashboard_outlined,
            label: 'لوحة الإدارة الرئيسية',
            section: 'عام',
            onTap: (context) async => Navigator.of(context).pop(),
          ),
          AppUserDrawerItem(
            icon: Icons.local_taxi_rounded,
            label: 'ملخص التكسي',
            section: 'التكسي',
            onTap: (_) async => _tabs.animateTo(0),
          ),
          AppUserDrawerItem(
            icon: Icons.route_outlined,
            label: 'الرحلات',
            section: 'التكسي',
            onTap: (_) async => _tabs.animateTo(1),
          ),
          AppUserDrawerItem(
            icon: Icons.account_balance_wallet_outlined,
            label: 'الكباتن والمستحقات',
            section: 'التكسي',
            onTap: (_) async => _tabs.animateTo(2),
          ),
        ],
      ),
      body: Stack(
        children: [
          if (_loading && _data == null)
            const Center(child: CircularProgressIndicator())
          else if (_error != null && _data == null)
            _ErrorState(message: _error!, onRetry: _load)
          else
            TabBarView(
              controller: _tabs,
              children: [
                _OverviewTab(data: _data ?? const {}, onRefresh: _load),
                _RidesTab(
                  rides: _list(_data?['rides']),
                  status: _rideStatus,
                  searchController: _searchController,
                  onStatusChanged: (value) {
                    _rideStatus = value;
                    _load();
                  },
                  onSearch: _load,
                  onCancel: _cancelRide,
                ),
                _CaptainsTab(
                  captains: _list(_data?['captains']),
                  status: _captainStatus,
                  searchController: _searchController,
                  onStatusChanged: (value) {
                    _captainStatus = value;
                    _load();
                  },
                  onSearch: _load,
                  onConfirmPayment: _confirmPayment,
                ),
              ],
            ),
          if (_saving)
            const Positioned.fill(
              child: ColoredBox(
                color: Color(0x33000000),
                child: Center(child: CircularProgressIndicator()),
              ),
            ),
        ],
      ),
    );
  }
}

class _OverviewTab extends StatelessWidget {
  final Map<String, dynamic> data;
  final Future<void> Function() onRefresh;
  const _OverviewTab({required this.data, required this.onRefresh});

  Map<String, dynamic> _map(dynamic value) => value is Map
      ? Map<String, dynamic>.from(value)
      : <String, dynamic>{};

  int _int(dynamic value) => value is num ? value.toInt() : 0;

  @override
  Widget build(BuildContext context) {
    final summary = _map(data['summary']);
    final rides = _map(summary['rides']);
    final captains = _map(summary['captains']);
    final credits = _map(summary['credits']);
    final cards = [
      ('الرحلات النشطة', _int(rides['active']), Icons.route, Colors.blue),
      ('المكتملة', _int(rides['completed']), Icons.check_circle, Colors.green),
      ('الملغاة', _int(rides['cancelled']), Icons.cancel, Colors.red),
      ('قيد البحث', _int(rides['searching']), Icons.search, Colors.orange),
      ('كباتن مسجلون', _int(captains['total']), Icons.badge, Colors.indigo),
      ('متصلون الآن', _int(captains['online']), Icons.online_prediction, Colors.teal),
      ('قرب نفاد الرصيد', _int(captains['nearExhaustion']), Icons.warning, Colors.amber),
      ('الرصيد منتهٍ', _int(captains['exhausted']), Icons.block, Colors.red),
      ('بانتظار التسديد', _int(captains['paymentPending']), Icons.payments, Colors.deepOrange),
    ];
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: ListTile(
              leading: const CircleAvatar(child: Icon(Icons.local_taxi)),
              title: const Text('نظام باقات الرحلات', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(
                '${formatIqd(_int(credits['packagePriceIqd']))} = ${_int(credits['packageRideCount'])} رحلة لكل كابتن',
              ),
            ),
          ),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 230,
              childAspectRatio: 1.65,
            ),
            itemCount: cards.length,
            itemBuilder: (_, index) {
              final card = cards[index];
              return Card(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(card.$3, color: card.$4),
                      const SizedBox(height: 6),
                      Text('${card.$2}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                      Text(card.$1, maxLines: 1, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _RidesTab extends StatelessWidget {
  final List<Map<String, dynamic>> rides;
  final String status;
  final TextEditingController searchController;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onSearch;
  final Future<void> Function(Map<String, dynamic>) onCancel;

  const _RidesTab({required this.rides, required this.status, required this.searchController, required this.onStatusChanged, required this.onSearch, required this.onCancel});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _Filters(
          controller: searchController,
          value: status,
          items: const {
            '': 'كل الحالات', 'searching': 'بحث', 'captain_assigned': 'تم التعيين',
            'captain_arriving': 'الكابتن قادم', 'ride_started': 'بدأت',
            'completed': 'مكتملة', 'cancelled': 'ملغاة', 'expired': 'منتهية',
          },
          onChanged: onStatusChanged,
          onSearch: onSearch,
        ),
        Expanded(
          child: rides.isEmpty
              ? const Center(child: Text('لا توجد رحلات مطابقة'))
              : RefreshIndicator(
                  onRefresh: () async => onSearch(),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(10),
                    itemCount: rides.length,
                    itemBuilder: (_, index) => _RideCard(ride: rides[index], onCancel: onCancel),
                  ),
                ),
        ),
      ],
    );
  }
}

class _RideCard extends StatelessWidget {
  final Map<String, dynamic> ride;
  final Future<void> Function(Map<String, dynamic>) onCancel;
  const _RideCard({required this.ride, required this.onCancel});

  Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : {};

  @override
  Widget build(BuildContext context) {
    final customer = _map(ride['customer']);
    final captain = _map(ride['captain']);
    final pickup = _map(ride['pickup']);
    final dropoff = _map(ride['dropoff']);
    final status = '${ride['status'] ?? ''}';
    final cancellable = !{'completed', 'cancelled', 'expired'}.contains(status);
    return Card(
      child: ExpansionTile(
        leading: CircleAvatar(child: Text('#${ride['id']}')),
        title: Text('${customer['fullName'] ?? 'زبون'} ← ${captain['fullName'] ?? 'لم يعيّن كابتن'}'),
        subtitle: Text('${_statusLabel(status)} • ${_date(ride['createdAt'])}'),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          _line(Icons.trip_origin, 'الانطلاق', '${pickup['label'] ?? '-'}'),
          _line(Icons.location_on, 'الوصول', '${dropoff['label'] ?? '-'}'),
          _line(
            Icons.payments_outlined,
            'الأجرة',
            formatIqd(
              num.tryParse(
                    '${ride['agreedFareIqd'] ?? ride['proposedFareIqd'] ?? 0}',
                  ) ??
                  0,
            ),
          ),
          if (cancellable)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton.icon(
                onPressed: () => onCancel(ride),
                icon: const Icon(Icons.cancel_outlined),
                label: const Text('إلغاء إداري'),
              ),
            ),
        ],
      ),
    );
  }
}

class _CaptainsTab extends StatelessWidget {
  final List<Map<String, dynamic>> captains;
  final String status;
  final TextEditingController searchController;
  final ValueChanged<String> onStatusChanged;
  final VoidCallback onSearch;
  final Future<void> Function(Map<String, dynamic>) onConfirmPayment;
  const _CaptainsTab({required this.captains, required this.status, required this.searchController, required this.onStatusChanged, required this.onSearch, required this.onConfirmPayment});

  Map<String, dynamic> _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : {};

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      _Filters(
        controller: searchController,
        value: status,
        items: const {'': 'كل الكباتن', 'active': 'الرصيد فعال', 'near_exhaustion': 'قرب النفاد', 'exhausted': 'منتهٍ', 'payment_pending': 'بانتظار التسديد'},
        onChanged: onStatusChanged,
        onSearch: onSearch,
      ),
      Expanded(
        child: captains.isEmpty
            ? const Center(child: Text('لا يوجد كباتن مطابقون'))
            : ListView.builder(
                padding: const EdgeInsets.all(10),
                itemCount: captains.length,
                itemBuilder: (_, index) {
                  final captain = captains[index];
                  final credits = _map(captain['credits']);
                  final vehicle = _map(captain['vehicle']);
                  final remaining = (credits['remaining'] as num?)?.toInt() ?? 0;
                  final creditStatus = '${credits['status'] ?? ''}';
                  final pending = credits['cashPaymentPending'] == true;
                  return Card(
                    child: ExpansionTile(
                      leading: Stack(children: [
                        const CircleAvatar(child: Icon(Icons.person)),
                        if (captain['online'] == true) const Positioned(bottom: 0, right: 0, child: CircleAvatar(radius: 5, backgroundColor: Colors.green)),
                      ]),
                      title: Text('${captain['fullName'] ?? '-'}'),
                      subtitle: Text('الرصيد: $remaining رحلة • ${_creditLabel(creditStatus)}'),
                      childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      children: [
                        _line(Icons.phone_outlined, 'الهاتف', '${captain['phone'] ?? '-'}'),
                        _line(Icons.directions_car_outlined, 'المركبة', '${vehicle['make'] ?? ''} ${vehicle['model'] ?? ''} • ${vehicle['plateNumber'] ?? '-'}'),
                        _line(Icons.receipt_long_outlined, 'الاستخدام', '${credits['used'] ?? 0} مستخدمة من ${credits['purchased'] ?? 0} مشتراة'),
                        if (pending || remaining <= 1)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: FilledButton.icon(
                              onPressed: () => onConfirmPayment(captain),
                              icon: const Icon(Icons.price_check),
                              label: const Text('تأكيد تسديد 10,000 وإضافة 15 رحلة'),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
      ),
    ]);
  }
}

class _Filters extends StatelessWidget {
  final TextEditingController controller;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  final VoidCallback onSearch;
  const _Filters({required this.controller, required this.value, required this.items, required this.onChanged, required this.onSearch});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(10),
    child: LayoutBuilder(
      builder: (context, constraints) {
        final search = TextField(
          controller: controller,
          onSubmitted: (_) => onSearch(),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'بحث بالاسم أو الهاتف أو الرقم',
            suffixIcon: IconButton(
              onPressed: onSearch,
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        );
        final filter = DropdownButton<String>(
          value: value,
          isExpanded: true,
          items: items.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (next) => onChanged(next ?? ''),
        );
        if (constraints.maxWidth < 560) {
          return Column(
            children: [search, const SizedBox(height: 6), filter],
          );
        }
        return Row(
          children: [
            Expanded(flex: 2, child: search),
            const SizedBox(width: 10),
            Expanded(child: filter),
          ],
        );
      },
    ),
  );
}

class _ErrorState extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;
  const _ErrorState({required this.message, required this.onRetry});
  @override
  Widget build(BuildContext context) => Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Text(message), const SizedBox(height: 8), FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('إعادة المحاولة'))]));
}

Widget _line(IconData icon, String label, String value) => Padding(
  padding: const EdgeInsets.symmetric(vertical: 4),
  child: Row(children: [Icon(icon, size: 18), const SizedBox(width: 8), Text('$label: ', style: const TextStyle(fontWeight: FontWeight.bold)), Expanded(child: Text(value))]),
);

String _date(dynamic value) {
  final date = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
  return date == null ? '-' : DateFormat('yyyy/MM/dd HH:mm').format(date);
}

String _statusLabel(String status) => const {
  'searching': 'قيد البحث', 'captain_assigned': 'تم تعيين الكابتن',
  'captain_arriving': 'الكابتن قادم', 'ride_started': 'الرحلة بدأت',
  'completed': 'مكتملة', 'cancelled': 'ملغاة', 'expired': 'منتهية',
}[status] ?? status;

String _creditLabel(String status) => const {
  'active': 'فعال', 'near_exhaustion': 'قرب النفاد', 'exhausted': 'منتهٍ',
  'payment_pending': 'بانتظار التسديد',
}[status] ?? status;
