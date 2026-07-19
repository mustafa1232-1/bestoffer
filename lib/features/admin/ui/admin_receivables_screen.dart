import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/parsers.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../models/admin_financial_request_model.dart';
import '../state/admin_controller.dart';
import 'widgets/admin_financial_request_actions_sheet.dart';
import 'admin_approvals_hub_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_services_hub_screen.dart';
import 'admin_service_provider_subscription_requests_screen.dart';

class AdminReceivablesScreen extends ConsumerStatefulWidget {
  const AdminReceivablesScreen({super.key});

  @override
  ConsumerState<AdminReceivablesScreen> createState() =>
      _AdminReceivablesScreenState();
}

class _AdminReceivablesScreenState extends ConsumerState<AdminReceivablesScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  Map<String, dynamic> _asMapSafe(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  List<dynamic> _asListSafe(dynamic raw) {
    if (raw is List) return List<dynamic>.from(raw);
    return const <dynamic>[];
  }

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 6, vsync: this);
    Future.microtask(_reload);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  Future<void> _reload() {
    return ref
        .read(adminControllerProvider.notifier)
        .refreshMerchantsReceivablesV2();
  }

  Widget _buildAdminDrawer(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    return AppUserDrawer(
      title: 'لوحة الإدارة',
      subtitle: auth.user?.fullName,
      showCommunitySection: false,
      showSettings: false,
      enableItemSearch: false,
      items: [
        AppUserDrawerItem(
          icon: Icons.space_dashboard_rounded,
          label: 'لوحة التحكم',
          subtitle: 'الصفحة الرئيسية للأدمن',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDashboardScreen(),
              ),
              (route) => false,
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.verified_user_outlined,
          label: 'حوض الموافقات',
          subtitle: 'مراجعة الطلبات المعلقة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminApprovalsHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.home_repair_service_outlined,
          label: 'إدارة الخدمات',
          subtitle: 'ملخص الخدمات والطلبات',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminServicesHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.description_outlined,
          label: 'طلبات الاشتراك',
          subtitle: 'عرض طلبات أصحاب الخدمة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const AdminServiceProviderSubscriptionRequestsScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.refresh_rounded,
          label: 'تحديث الصفحة',
          subtitle: 'إعادة تحميل المستحقات',
          group: 'الإجراءات',
          onTap: (_) async {
            await _reload();
          },
        ),
      ],
    );
  }

  Future<void> _runAction(
    AdminFinancialRequestModel request,
    AdminFinancialActionResult result,
  ) async {
    final controller = ref.read(adminControllerProvider.notifier);
    bool ok = false;
    switch (result.action) {
      case AdminFinancialActionType.approve:
        ok = await controller.approvePaymentRequestV2(
          request.id,
          reviewNote: result.payload['reviewNote']?.toString(),
          internalAdminNote: result.payload['internalAdminNote']?.toString(),
        );
        break;
      case AdminFinancialActionType.reject:
        ok = await controller.rejectPaymentRequestV2(
          request.id,
          reviewNote: result.payload['reviewNote']?.toString(),
        );
        break;
      case AdminFinancialActionType.assign:
        ok = await controller.assignPaymentRequestV2(
          paymentRequestId: request.id,
          assignedToName: result.payload['assignedToName']?.toString(),
          reviewNote: result.payload['reviewNote']?.toString(),
          internalAdminNote: result.payload['internalAdminNote']?.toString(),
        );
        break;
      case AdminFinancialActionType.markPaid:
        ok = await controller.markPaymentRequestPaidV2(
          paymentRequestId: request.id,
          paidAmount: result.payload['paidAmount'] as double?,
          paymentMethod: result.payload['paymentMethod']?.toString(),
          paymentDate: result.payload['paymentDate']?.toString(),
          referenceCode: result.payload['referenceCode']?.toString(),
          paymentActorName: result.payload['paymentActorName']?.toString(),
          assignedToName: result.payload['assignedToName']?.toString(),
          reviewNote: result.payload['reviewNote']?.toString(),
          internalAdminNote: result.payload['internalAdminNote']?.toString(),
        );
        break;
      case AdminFinancialActionType.returnForRevision:
        ok = await controller.returnPaymentRequestForRevisionV2(
          request.id,
          reviewNote: result.payload['reviewNote']?.toString(),
          internalAdminNote: result.payload['internalAdminNote']?.toString(),
        );
        break;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          ok
              ? context.l10n.adminReceivablesActionCompleted
              : context.l10n.adminReceivablesActionFailed,
        ),
      ),
    );
  }

  Future<void> _addAdjustment(int merchantId) async {
    final l10n = context.l10n;
    final amountCtrl = TextEditingController();
    String direction = 'debit';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: Text(l10n.adminReceivablesAddAdjustmentTitle),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: amountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(labelText: l10n.commonAmount),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<String>(
                initialValue: direction,
                items: [
                  DropdownMenuItem(
                    value: 'debit',
                    child: Text(l10n.adminReceivablesDebit),
                  ),
                  DropdownMenuItem(
                    value: 'credit',
                    child: Text(l10n.adminReceivablesCredit),
                  ),
                ],
                onChanged: (value) =>
                    setState(() => direction = value ?? 'debit'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(l10n.commonCancel),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(l10n.commonSave),
            ),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final amount = tryParseLocalizedDouble(amountCtrl.text.trim()) ?? 0;
    if (amount <= 0) return;
    final success = await ref
        .read(adminControllerProvider.notifier)
        .createAppPayablesAdjustmentV2(
          merchantId: merchantId,
          amount: amount,
          direction: direction,
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          success
              ? l10n.adminReceivablesAdjustmentAdded
              : l10n.adminReceivablesAdjustmentFailed,
        ),
      ),
    );
  }

  List<AdminFinancialRequestModel> _filteredRequests(
    List<AdminFinancialRequestModel> all,
    int tabIndex,
  ) {
    bool pending(AdminFinancialRequestModel request) =>
        request.status == 'pending_admin_confirmation' ||
        request.status == 'pending_admin_review' ||
        request.status == 'returned_for_revision' ||
        request.status == 'issue_reported_by_store';
    bool awaitingStore(AdminFinancialRequestModel request) =>
        request.status == 'awaiting_store_confirmation';
    bool completed(AdminFinancialRequestModel request) =>
        request.status == 'confirmed_by_admin' ||
        request.status == 'confirmed_received_by_store';
    bool rejected(AdminFinancialRequestModel request) =>
        request.status == 'rejected_by_admin' || request.status == 'cancelled';

    switch (tabIndex) {
      case 0:
        return all
            .where((item) => item.requestType == 'store_pays_app')
            .toList();
      case 1:
        return all
            .where((item) => item.requestType == 'app_pays_store')
            .toList();
      case 2:
        return all.where(pending).toList();
      case 3:
        return all.where(awaitingStore).toList();
      case 4:
        return all.where(completed).toList();
      case 5:
        return all.where(rejected).toList();
      default:
        return all;
    }
  }

  Future<void> _openMerchantDetails(Map<String, dynamic> merchantRow) async {
    final merchantId = tryParseLocalizedInt(merchantRow['merchant_id']) ?? 0;
    if (merchantId <= 0) return;
    final details = await ref
        .read(adminControllerProvider.notifier)
        .fetchMerchantReceivablesDetailsV2(merchantId);
    if (!mounted || details == null) return;

    final merchant = _asMapSafe(details['merchant']);
    final paymentRequestsRaw = _asListSafe(details['paymentRequests']);
    final paymentRequests = paymentRequestsRaw
        .whereType<Map>()
        .map(
          (row) => AdminFinancialRequestModel.fromJson(
            _asMapSafe(row),
            merchantId: merchantId,
            merchantName: '${merchant['name'] ?? ''}',
          ),
        )
        .toList(growable: false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (context, setState) {
          final l10n = context.l10n;
          final filtered = _filteredRequests(paymentRequests, _tabs.index);
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    '${merchant['name'] ?? '-'}',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '${l10n.adminReceivablesOutstandingToApp}: ${formatIqd(_toNum(merchantRow['outstanding']))}',
                  ),
                  Text(
                    '${l10n.adminReceivablesOutstandingToStore}: ${formatIqd(_toNum(merchantRow['app_payables_outstanding']))}',
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () => _addAdjustment(merchantId),
                        icon: const Icon(Icons.balance),
                        label: Text(l10n.adminReceivablesAdjustment),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Flexible(
                    child: filtered.isEmpty
                        ? Center(child: Text(l10n.adminReceivablesNoRequests))
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final request = filtered[index];
                              return Card(
                                margin: const EdgeInsets.only(bottom: 8),
                                child: ListTile(
                                  title: Text(
                                    '#${request.id} - ${formatIqd(request.requestedAmount)}',
                                  ),
                                  subtitle: Text(
                                    '${request.requestType} - ${request.status}',
                                  ),
                                  trailing: IconButton(
                                    icon: const Icon(Icons.more_horiz_rounded),
                                    onPressed: () async {
                                      final result =
                                          await showModalBottomSheet<
                                            AdminFinancialActionResult
                                          >(
                                            context: context,
                                            isScrollControlled: true,
                                            builder: (_) =>
                                                AdminFinancialRequestActionsSheet(
                                                  request: request,
                                                ),
                                          );
                                      if (result == null) return;
                                      await _runAction(request, result);
                                      if (!mounted) return;
                                      Navigator.of(this.context).pop();
                                      await _reload();
                                      if (!mounted) return;
                                      _openMerchantDetails(merchantRow);
                                    },
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  double _toNum(dynamic value) =>
      value is num ? value.toDouble() : (tryParseLocalizedDouble(value) ?? 0);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final raw = state.merchantsReceivablesV2;
    final merchants = _asListSafe(
      raw['merchants'],
    ).whereType<Map>().map(_asMapSafe).toList(growable: false);

    return Scaffold(
      drawer: Drawer(child: _buildAdminDrawer(context)),
      appBar: AppBar(
        title: Text(l10n.adminReceivablesTitle),
        actions: [
          IconButton(
            onPressed: _reload,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
        bottom: TabBar(
          controller: _tabs,
          isScrollable: true,
          onTap: (_) => setState(() {}),
          tabs: [
            Tab(text: l10n.adminReceivablesTabStorePaysApp),
            Tab(text: l10n.adminReceivablesTabAppPaysStore),
            Tab(text: l10n.commonPending),
            Tab(text: l10n.adminReceivablesTabAwaitingStore),
            Tab(text: l10n.commonCompleted),
            Tab(text: l10n.commonRejected),
          ],
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(12),
          children: [
            if (merchants.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 40),
                child: Center(child: Text(l10n.adminReceivablesNoData)),
              )
            else
              ...merchants.map((row) {
                final merchantName = '${row['merchant_name'] ?? '-'}';
                final outstanding = _toNum(row['outstanding']);
                final appOutstanding = _toNum(row['app_payables_outstanding']);
                final pending =
                    tryParseLocalizedInt(row['pending_payment_requests']) ?? 0;
                final pendingOutgoing =
                    tryParseLocalizedInt(row['pending_outgoing_requests']) ?? 0;
                return Card(
                  margin: const EdgeInsets.only(bottom: 10),
                  child: ListTile(
                    title: Text(merchantName),
                    subtitle: Text(
                      '${l10n.adminReceivablesStoreOwesApp}: ${formatIqd(outstanding)}\n'
                      '${l10n.adminReceivablesAppOwesStore}: ${formatIqd(appOutstanding)}\n'
                      '${l10n.adminReceivablesPendingIncoming}: $pending - '
                      '${l10n.adminReceivablesPendingOutgoing}: $pendingOutgoing',
                    ),
                    trailing: const Icon(Icons.chevron_right_rounded),
                    onTap: () => _openMerchantDetails(row),
                  ),
                );
              }),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}
