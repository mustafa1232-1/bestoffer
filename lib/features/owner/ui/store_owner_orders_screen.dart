// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../auth/state/auth_controller.dart';
import '../../coupons/ui/coupon_management_screen.dart';
import '../../orders/models/order_model.dart';
import '../../orders/ui/widgets/order_item_widgets.dart';
import '../printing/receipt_printer_service.dart';
import '../printing/ui/receipt_preview_dialog.dart';
import '../state/owner_controller.dart';
import 'owner_dashboard_screen.dart';
import 'store_owner_couriers_screen.dart';
import 'store_owner_kpis_screen.dart';
import 'store_owner_offers_screen.dart';
import 'store_owner_receivables_screen.dart';
import 'store_printer_settings_screen.dart';

enum StoreOwnerOrdersView { current, completed, cancelled, details }

class StoreOwnerOrdersScreen extends ConsumerStatefulWidget {
  const StoreOwnerOrdersScreen({
    super.key,
    this.view = StoreOwnerOrdersView.current,
    this.initialOrderId,
    this.customTitle,
    this.statusFilterNormalized,
  });

  final StoreOwnerOrdersView view;
  final int? initialOrderId;
  final String? customTitle;
  final Set<String>? statusFilterNormalized;

  bool get isReadOnlyView => view != StoreOwnerOrdersView.current;

  @override
  ConsumerState<StoreOwnerOrdersScreen> createState() =>
      _StoreOwnerOrdersScreenState();
}

class _StoreOwnerOrdersScreenState
    extends ConsumerState<StoreOwnerOrdersScreen> {
  final Map<int, int> _selectedDeliveryByOrder = {};
  final Map<int, bool> _printingByOrder = {};
  bool _printingSample = false;
  bool _printingTest = false;
  late final OwnerController _ownerController;

  bool get _useArabicLabels =>
      Localizations.localeOf(context).languageCode.toLowerCase() == 'ar';

  @override
  void initState() {
    super.initState();
    _ownerController = ref.read(ownerControllerProvider.notifier);
    Future.microtask(() async {
      if (!mounted) return;
      await _ownerController.bootstrap();
      if (!mounted) return;
      if (!widget.isReadOnlyView) {
        _ownerController.startLiveOrders();
      }
    });
  }

  @override
  void dispose() {
    if (!widget.isReadOnlyView) {
      _ownerController.stopLiveOrders();
    }
    super.dispose();
  }

  Future<void> _refresh() async {
    await _ownerController.refreshOrders();
  }

  Future<void> _openPrinterSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StorePrinterSettingsScreen()),
    );
  }

  Future<void> _openOwnerWorkspaceTab(OwnerDashboardTab tab) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OwnerDashboardScreen(initialTab: tab),
      ),
    );
  }

  Future<void> _openOffersWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StoreOwnerOffersScreen()),
    );
  }

  Future<void> _openCouponsWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const CouponManagementScreen(mode: CouponManagerMode.owner),
      ),
    );
  }

  Future<void> _openPrinterActionsHub() async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.print_rounded),
                title: Text(l10n.ownerPrinterSettingsTitle),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _openPrinterSettings();
                },
              ),
              ListTile(
                leading: const Icon(Icons.playlist_add_check_rounded),
                title: Text(l10n.ownerPrinterTestPrint),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _testPrint();
                },
              ),
              ListTile(
                leading: const Icon(Icons.description_outlined),
                title: Text(l10n.ownerOrdersPrintSampleInvoice),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _printSampleInvoice();
                },
              ),
              ListTile(
                leading: const Icon(Icons.bug_report_outlined),
                title: Text(l10n.ownerPrinterLogs),
                onTap: () async {
                  Navigator.of(context).pop();
                  await _showPrintLogs();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openPrinterActionsHubFromDrawer() async {
    Navigator.of(context).maybePop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _openPrinterActionsHub();
  }

  Future<void> _openVerifiedReviewsFromDrawer() async {
    Navigator.of(context).maybePop();
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    await _showVerifiedReviewsSheet();
  }

  bool _canPrintReceipt(String status) {
    return const {
      'preparing',
      'ready_for_delivery',
      'ready_for_pickup',
      'on_the_way',
      'arrived',
      'delivered',
      'delivered_by_courier',
      'received_by_customer',
      'completed',
      'cancelled',
    }.contains(status);
  }

  Future<void> _printReceipt(OrderModel order, String assignmentMode) async {
    if (_printingByOrder[order.id] == true) return;
    setState(() => _printingByOrder[order.id] = true);
    final l10n = context.l10n;
    try {
      final result = await ReceiptPrinterService.instance.printOrder(
        order: order,
        assignmentMode: assignmentMode,
        useArabicLabels: _useArabicLabels,
        appTitle: 'MASLAKI',
        cashierName: l10n.ownerOrdersCashierName,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.success
                ? l10n.ownerOrdersPrintSuccess(result.adapterId)
                : l10n.ownerOrdersPrintFailed(result.message),
          ),
          action: result.success
              ? null
              : SnackBarAction(
                  label: l10n.commonRetry,
                  onPressed: () => _printReceipt(order, assignmentMode),
                ),
        ),
      );
    } finally {
      if (mounted) setState(() => _printingByOrder[order.id] = false);
    }
  }

  Future<void> _previewReceipt(OrderModel order, String assignmentMode) async {
    final l10n = context.l10n;
    final doc = await ReceiptPrinterService.instance.buildOrderDocument(
      order: order,
      assignmentMode: assignmentMode,
      useArabicLabels: _useArabicLabels,
      appTitle: 'MASLAKI',
      cashierName: l10n.ownerOrdersCashierName,
    );
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => ReceiptPreviewDialog(
        title: l10n.ownerOrdersReceiptPreviewTitle,
        document: doc,
      ),
    );
  }

  Future<void> _testPrint() async {
    if (_printingTest) return;
    setState(() => _printingTest = true);
    final l10n = context.l10n;
    final result = await ReceiptPrinterService.instance.printTest(
      useArabicLabels: _useArabicLabels,
      appTitle: 'MASLAKI',
    );
    if (!mounted) return;
    setState(() => _printingTest = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? l10n.ownerPrinterTestReceiptSent
              : l10n.ownerPrinterTestFailed(result.message),
        ),
      ),
    );
  }

  Future<void> _printSampleInvoice() async {
    if (_printingSample) return;
    setState(() => _printingSample = true);
    final l10n = context.l10n;
    final result = await ReceiptPrinterService.instance.printSampleInvoice(
      useArabicLabels: _useArabicLabels,
      appTitle: 'MASLAKI',
    );
    if (!mounted) return;
    setState(() => _printingSample = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.success
              ? l10n.ownerPrinterSampleSent
              : l10n.ownerPrinterSampleFailed(result.message),
        ),
      ),
    );
  }

  Future<void> _showPrintLogs() async {
    final l10n = context.l10n;
    final jobs = ReceiptPrinterService.instance.history;
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: jobs.isEmpty
              ? Center(child: Text(l10n.ownerPrinterNoLogs))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: jobs.length,
                  itemBuilder: (_, i) {
                    final job = jobs[i];
                    return Card(
                      margin: const EdgeInsets.only(bottom: 10),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${job.adapterId} - ${job.createdAt.toLocal()}',
                            ),
                            const SizedBox(height: 6),
                            Text(job.message),
                            const SizedBox(height: 6),
                            ...job.logs
                                .take(8)
                                .map(
                                  (entry) => Text(
                                    '${entry.ok ? 'OK' : 'ERR'} ${entry.stage}: ${entry.message}',
                                  ),
                                ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ),
    );
  }

  String _viewTitle() {
    if (widget.customTitle != null && widget.customTitle!.trim().isNotEmpty) {
      return widget.customTitle!;
    }
    final l10n = context.l10n;
    switch (widget.view) {
      case StoreOwnerOrdersView.current:
        return l10n.ownerOrdersCurrentTitle;
      case StoreOwnerOrdersView.completed:
        return l10n.ownerOrdersCompletedTitle;
      case StoreOwnerOrdersView.cancelled:
        return l10n.ownerOrdersCancelledTitle;
      case StoreOwnerOrdersView.details:
        return l10n.ownerOrdersDetailsTitle;
    }
  }

  String _emptyMessage() {
    final l10n = context.l10n;
    switch (widget.view) {
      case StoreOwnerOrdersView.current:
        return l10n.ownerOrdersEmptyCurrent;
      case StoreOwnerOrdersView.completed:
        return l10n.ownerOrdersEmptyCompleted;
      case StoreOwnerOrdersView.cancelled:
        return l10n.ownerOrdersEmptyCancelled;
      case StoreOwnerOrdersView.details:
        return l10n.ownerOrdersEmptyDetails;
    }
  }

  String _statusLabel(String status) {
    final l10n = context.l10n;
    switch (normalizeOrderStatusForUi(status)) {
      case 'pending':
        return l10n.commonPending;
      case 'approved':
        return l10n.ownerOrdersStatusApproved;
      case 'preparing':
        return l10n.ownerOrdersStatusPreparing;
      case 'ready_for_delivery':
        return l10n.ownerOrdersStatusReadyForDelivery;
      case 'on_the_way':
        return l10n.ownerOrdersStatusOnTheWay;
      case 'arrived':
        return l10n.ownerOrdersStatusArrived;
      case 'delivered':
        return l10n.ownerOrdersStatusDelivered;
      case 'cancelled':
        return l10n.commonCancelled;
      case 'received':
        return l10n.ownerOrdersStatusReceived;
      case 'failed_delivery':
        return l10n.ownerOrdersStatusFailedDelivery;
      default:
        return normalizeOrderStatusForUi(status);
    }
  }

  String? _statusHint(OrderModel order, {required bool hasDeliveryAssigned}) {
    final l10n = context.l10n;
    switch (normalizeOrderStatusForUi(order.status)) {
      case 'approved':
        return hasDeliveryAssigned
            ? l10n.ownerOrdersHintApprovedAssigned
            : l10n.ownerOrdersHintApprovedPendingCourier;
      case 'preparing':
        return l10n.ownerOrdersHintPreparing;
      case 'ready_for_delivery':
        return order.isMerchantDelivery
            ? l10n.ownerOrdersHintReadyMerchantDelivery
            : l10n.ownerOrdersHintReadyPlatformDelivery;
      case 'on_the_way':
        return l10n.ownerOrdersHintOnTheWay;
      case 'arrived':
        return l10n.ownerOrdersHintArrived;
      case 'delivered':
        return order.customerConfirmedAt != null
            ? null
            : l10n.ownerOrdersHintDeliveredAwaitingConfirmation;
      case 'failed_delivery':
        return l10n.ownerOrdersHintFailedDelivery;
      default:
        return null;
    }
  }

  String _deliveryTypeText(OrderModel order) {
    final l10n = context.l10n;
    if (order.isStoreDriverDelivery) return l10n.ownerOrdersStoreDriver;
    if (order.isAppDriverDelivery) return l10n.ownerOrdersAppDriver;
    return l10n.ownerOrdersPendingAssignment;
  }

  String _summaryRouteTitle(String statusKey) {
    final l10n = context.l10n;
    switch (statusKey) {
      case 'pending':
        return l10n.ownerOrdersPendingFilterTitle;
      case 'preparing':
        return l10n.ownerOrdersPreparingFilterTitle;
      case 'ready':
        return l10n.ownerOrdersReadyFilterTitle;
      case 'delivering':
        return l10n.ownerOrdersDeliveringFilterTitle;
      default:
        return l10n.ownerOrdersAllCurrentFilterTitle;
    }
  }

  Set<String> _summaryRouteFilters(String statusKey) {
    switch (statusKey) {
      case 'pending':
        return <String>{'pending', 'approved'};
      case 'preparing':
        return <String>{'preparing'};
      case 'ready':
        return <String>{'ready_for_delivery'};
      case 'delivering':
        return <String>{'on_the_way', 'arrived'};
      default:
        return <String>{};
    }
  }

  Future<void> _showCustomerReliabilityDialog(OrderModel order) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await ref
          .read(ownerApiProvider)
          .merchantCustomerReliability(customerUserId: order.customerUserId);
      if (!mounted) return;
      final stats = Map<String, dynamic>.from(
        (data['stats'] as Map?) ?? const <String, dynamic>{},
      );
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('موثوقية العميل'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${order.customerFullName} (${order.customerPhone})',
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              _ReliabilityRow(
                label: 'التقييم',
                value: '${data['score'] ?? '-'} / 100',
              ),
              _ReliabilityRow(
                label: 'الحالة',
                value: '${data['tier'] ?? '-'}',
              ),
              _ReliabilityRow(
                label: 'طلبات مكتملة',
                value: '${stats['completedOrders'] ?? 0}',
              ),
              _ReliabilityRow(
                label: 'إلغاء من العميل',
                value: '${stats['cancelledByCustomer'] ?? 0}',
              ),
              _ReliabilityRow(
                label: 'تعذر التسليم',
                value: '${stats['failedDelivery'] ?? 0}',
              ),
              _ReliabilityRow(
                label: 'شكاوى مؤثرة',
                value: '${stats['complaints'] ?? 0}',
              ),
              if (data['warningRequired'] == true) ...[
                const SizedBox(height: 10),
                const Text(
                  'تنبيه: هذا العميل يحتاج تأكيدًا إضافيًا قبل قبول الطلب.',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Colors.orangeAccent,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('إغلاق'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('تعذر تحميل موثوقية العميل: $e'),
        ),
      );
    }
  }

  Future<void> _showVerifiedReviewsSheet() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final data = await ref.read(ownerApiProvider).merchantVerifiedReviews();
      if (!mounted) return;
      final reviews = List<Map<String, dynamic>>.from(
        (data['reviews'] as List? ?? const []).map(
          (entry) => Map<String, dynamic>.from(entry as Map),
        ),
      );
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.80,
            child: reviews.isEmpty
                ? const Center(child: Text('لا توجد تقييمات موثقة حاليًا.'))
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: reviews.length,
                    itemBuilder: (context, index) {
                      final review = reviews[index];
                      final customer = Map<String, dynamic>.from(
                        (review['customer'] as Map?) ??
                            const <String, dynamic>{},
                      );
                      final ctx = Map<String, dynamic>.from(
                        (review['customerOrderContext'] as Map?) ??
                            const <String, dynamic>{},
                      );
                      final stars = int.tryParse('${review['rating'] ?? 0}') ?? 0;
                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${customer['fullName'] ?? customer['username'] ?? 'عميل'}',
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${'⭐' * stars}  •  طلب #${review['orderId'] ?? '-'}',
                                textDirection: TextDirection.rtl,
                              ),
                              if ((review['reviewText']?.toString().trim().isNotEmpty ??
                                  false)) ...[
                                const SizedBox(height: 6),
                                Text(
                                  '${review['reviewText']}',
                                  textDirection: TextDirection.rtl,
                                ),
                              ],
                              const SizedBox(height: 6),
                              Text(
                                'سجل العميل مع المتجر: ${ctx['totalOrdersCount'] ?? 0} طلب',
                                textDirection: TextDirection.rtl,
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.72),
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تحميل التقييمات الموثقة: $e')),
      );
    }
  }

  Future<bool> _confirmReliabilityWarningIfNeeded(OrderModel order) async {
    try {
      final data = await ref
          .read(ownerApiProvider)
          .merchantCustomerReliability(customerUserId: order.customerUserId);
      if (!mounted) return false;
      if (data['warningRequired'] != true) return true;
      final score = data['score'] ?? '-';
      final tier = data['tier'] ?? '-';
      final decision = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تنبيه قبل قبول الطلب'),
          content: Text(
            'موثوقية العميل منخفضة (التقييم: $score، الحالة: $tier).\n'
            'هل تريد المتابعة ببدء التحضير؟',
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      return decision == true;
    } catch (_) {
      if (!mounted) return false;
      final decision = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('تعذر التحقق من موثوقية العميل'),
          content: const Text(
            'لم نتمكن من جلب مؤشر الموثوقية الآن. هل تريد المتابعة؟',
            textDirection: TextDirection.rtl,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      );
      return decision == true;
    }
  }

  bool _matchesView(OrderModel order) {
    final normalized = normalizeOrderStatusForUi(order.status);
    switch (widget.view) {
      case StoreOwnerOrdersView.current:
        if (widget.statusFilterNormalized == null ||
            widget.statusFilterNormalized!.isEmpty) {
          return true;
        }
        return widget.statusFilterNormalized!.contains(normalized);
      case StoreOwnerOrdersView.completed:
        return const {
          'delivered',
          'received',
          'completed',
        }.contains(normalized);
      case StoreOwnerOrdersView.cancelled:
        return const {
          'cancelled',
          'failed_delivery',
          'returned_if_needed',
        }.contains(normalized);
      case StoreOwnerOrdersView.details:
        return widget.initialOrderId != null &&
            order.id == widget.initialOrderId;
    }
  }

  List<OrderModel> _resolveVisibleOrders(OwnerState state) {
    final source = widget.view == StoreOwnerOrdersView.current
        ? state.currentOrders
        : [...state.currentOrders, ...state.historyOrders];
    return source.where(_matchesView).toList(growable: false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(ownerControllerProvider);
    final merchant = state.merchant;
    if (merchant != null &&
        (merchant.approvalStatus == 'awaiting_store_financial_acceptance' ||
            !merchant.isApproved)) {
      return const OwnerDashboardScreen();
    }
    final controller = ref.read(ownerControllerProvider.notifier);
    final visibleOrders = _resolveVisibleOrders(state);
    final pageTitle = _viewTitle();

    final pending = state.currentOrders
        .where((o) => o.status == 'pending')
        .length;
    final preparing = state.currentOrders
        .where((o) => o.status == 'preparing')
        .length;
    final ready = state.currentOrders
        .where(
          (o) =>
              o.status == 'ready_for_delivery' ||
              o.status == 'ready_for_pickup',
        )
        .length;
    final delivering = state.currentOrders
        .where((o) => const {'on_the_way', 'arrived'}.contains(o.status))
        .length;

    return Scaffold(
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              ListTile(title: Text(l10n.ownerOrdersMenuTitle)),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.dashboard_outlined),
                title: Text(l10n.ownerDashboardTitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await _openOwnerWorkspaceTab(OwnerDashboardTab.dashboard);
                },
              ),
              ListTile(
                leading: const Icon(Icons.storefront_outlined),
                title: Text(l10n.ownerMenuStoreSettingsTitle),
                subtitle: Text(l10n.ownerMenuStoreSettingsSubtitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await _openOwnerWorkspaceTab(OwnerDashboardTab.store);
                },
              ),
              ListTile(
                leading: const Icon(Icons.inventory_2_outlined),
                title: Text(l10n.ownerMenuCatalogTitle),
                subtitle: Text(l10n.ownerMenuCatalogSubtitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await _openOwnerWorkspaceTab(OwnerDashboardTab.catalog);
                },
              ),
              ListTile(
                leading: const Icon(Icons.add_box_outlined),
                title: Text(l10n.ownerMenuCreateProductTitle),
                subtitle: Text(l10n.ownerMenuCreateProductSubtitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await _openOwnerWorkspaceTab(OwnerDashboardTab.catalog);
                },
              ),
              ListTile(
                leading: const Icon(Icons.category_outlined),
                title: Text(l10n.ownerMenuCreateCategoryTitle),
                subtitle: Text(l10n.ownerMenuCreateCategorySubtitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await _openOwnerWorkspaceTab(OwnerDashboardTab.catalog);
                },
              ),
              ListTile(
                leading: const Icon(Icons.local_offer_outlined),
                title: Text(l10n.ownerMenuOffersTitle),
                subtitle: Text(l10n.ownerMenuOffersSubtitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await _openOffersWorkspace();
                },
              ),
              ListTile(
                leading: const Icon(Icons.discount_outlined),
                title: Text(l10n.ownerMenuCouponsTitle),
                subtitle: Text(l10n.ownerMenuCouponsSubtitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await _openCouponsWorkspace();
                },
              ),
              ListTile(
                leading: const Icon(Icons.analytics_outlined),
                title: Text(l10n.ownerStoreKpisTitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StoreOwnerKpisScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.verified_outlined),
                title: const Text('التقييمات الموثقة'),
                subtitle: const Text(
                  'عرض تقييمات العملاء المرتبطة بطلبات مكتملة',
                ),
                onTap: _openVerifiedReviewsFromDrawer,
              ),
              ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(l10n.ownerReceivablesTitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StoreOwnerReceivablesScreen(),
                    ),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.delivery_dining_rounded),
                title: Text(l10n.ownerCouriersTitle),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const StoreOwnerCouriersScreen(),
                    ),
                  );
                },
              ),
              Card(
                margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
                child: ListTile(
                  leading: const Icon(Icons.print_rounded),
                  title: Text(l10n.ownerPrinterSettingsTitle),
                  subtitle: Text(l10n.ownerMenuPrinterHubSubtitle),
                  onTap: _openPrinterActionsHubFromDrawer,
                ),
              ),
              const Spacer(),
              ListTile(
                leading: const Icon(Icons.logout_rounded),
                title: Text(l10n.commonLogout),
                onTap: () async {
                  Navigator.of(context).maybePop();
                  await ref.read(authControllerProvider.notifier).logout();
                },
              ),
            ],
          ),
        ),
      ),
      appBar: AppBar(
        title: Text(pageTitle),
        actions: [
          IconButton(
            onPressed: _openPrinterSettings,
            icon: const Icon(Icons.print_rounded),
          ),
          IconButton(
            onPressed: _showPrintLogs,
            icon: const Icon(Icons.bug_report_outlined),
          ),
          IconButton(
            onPressed: _showVerifiedReviewsSheet,
            icon: const Icon(Icons.verified_outlined),
          ),
          IconButton(
            onPressed: state.savingOrder ? null : _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: state.loading && visibleOrders.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                children: [
                  if (!widget.isReadOnlyView) ...[
                    _SummaryGrid(
                      pending: pending,
                      preparing: preparing,
                      ready: ready,
                      delivering: delivering,
                      total: state.currentOrders.length,
                      onCardTap: (statusKey) async {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => StoreOwnerOrdersScreen(
                              view: StoreOwnerOrdersView.current,
                              customTitle: _summaryRouteTitle(statusKey),
                              statusFilterNormalized: _summaryRouteFilters(
                                statusKey,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (state.error != null) ...[
                    _ErrorBanner(
                      message: state.error!,
                      onRetry: state.loading ? null : _refresh,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (visibleOrders.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: Colors.white.withValues(alpha: 0.04),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(_emptyMessage(), textAlign: TextAlign.center),
                    )
                  else
                    ...visibleOrders.map(
                      (order) => _buildOrderCard(
                        context: context,
                        order: order,
                        controller: controller,
                        state: state,
                        readOnly: widget.isReadOnlyView,
                      ),
                    ),
                ],
              ),
            ),
    );
  }

  Widget _buildOrderCard({
    required BuildContext context,
    required OrderModel order,
    required OwnerController controller,
    required OwnerState state,
    bool readOnly = false,
  }) {
    final l10n = context.l10n;
    final selectedDelivery =
        _selectedDeliveryByOrder[order.id] ?? order.deliveryUserId;
    final hasDeliveryAssigned =
        order.deliveryUserId != null || order.isMerchantDelivery;
    final hasAppDeliveryAgents = state.deliveryAgents.isNotEmpty;
    final canAssign =
        !readOnly &&
        const {
          'approved',
          'preparing',
          'ready_for_delivery',
          'ready_for_pickup',
        }.contains(order.status);
    final statusHint = _statusHint(
      order,
      hasDeliveryAssigned: hasDeliveryAssigned,
    );
    final messenger = ScaffoldMessenger.of(context);
    final assignmentMode = order.isMerchantDelivery
        ? 'merchant_delivery'
        : 'platform_delivery';
    final canPrint = !readOnly && _canPrintReceipt(order.status);
    final isPrinting = _printingByOrder[order.id] == true;
    final deliveryTypeText = _deliveryTypeText(order);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.ownerOrdersOrderNumber(order.id),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                _StatusPill(
                  text: _statusLabel(order.status),
                  color: orderStatusColor(order.status),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              '${l10n.commonCustomer}: ${order.customerFullName} - ${order.customerPhone}',
            ),
            const SizedBox(height: 4),
            Text(
              '${l10n.ownerOrdersAddressLabel}: ${order.customerCity} - ${l10n.commonBlock} ${order.customerBlock} - ${l10n.ownerOrdersBuildingLabel} ${order.customerBuildingNumber} - ${l10n.ownerOrdersApartmentLabel} ${order.customerApartment}',
            ),
            const SizedBox(height: 4),
            Text('${l10n.ownerOrdersDriverTypeLabel}: $deliveryTypeText'),
            if ((order.note ?? '').trim().isNotEmpty) ...[
              const SizedBox(height: 4),
              Text('${l10n.ownerOrdersNoteLabel}: ${order.note}'),
            ],
            const SizedBox(height: 10),
            Text(
              'راجع المنتجات والمواصفات قبل الموافقة',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.86),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            OrderItemsSummaryList(
              items: order.presentationItems,
              compact: false,
              groupByStore: order.presentationItems
                      .map((item) => '${item.storeId ?? item.storeName ?? 'store'}')
                      .toSet()
                      .length >
                  1,
            ),
            const Divider(height: 20),
            Row(
              children: [
                Text(
                  '${l10n.commonTotal}:',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                Text(
                  formatIqd(order.totalAmount),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            if (statusHint != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(10),
                  color: Colors.cyan.withValues(alpha: 0.10),
                  border: Border.all(
                    color: Colors.cyan.withValues(alpha: 0.22),
                  ),
                ),
                child: Text(statusHint),
              ),
            ],
            const SizedBox(height: 10),
            if (!readOnly && hasAppDeliveryAgents)
              DropdownButtonFormField<int>(
                value: selectedDelivery,
                decoration: InputDecoration(
                  labelText: l10n.ownerOrdersAssignAppCourier,
                ),
                items: state.deliveryAgents
                    .map(
                      (agent) => DropdownMenuItem<int>(
                        value: agent.id,
                        child: Text('${agent.fullName} - ${agent.phone}'),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  setState(() {
                    if (value == null) {
                      _selectedDeliveryByOrder.remove(order.id);
                    } else {
                      _selectedDeliveryByOrder[order.id] = value;
                    }
                  });
                },
              ),
            if (!readOnly) ...[
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (canPrint)
                    OutlinedButton.icon(
                      onPressed: isPrinting
                          ? null
                          : () => _printReceipt(order, assignmentMode),
                      icon: isPrinting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.print_outlined),
                      label: Text(
                        isPrinting
                            ? l10n.ownerOrdersPrinting
                            : l10n.ownerOrdersPrintReceipt,
                      ),
                    ),
                  if (canPrint)
                    OutlinedButton.icon(
                      onPressed: isPrinting
                          ? null
                          : () => _previewReceipt(order, assignmentMode),
                      icon: const Icon(Icons.visibility_outlined),
                      label: Text(l10n.commonPreview),
                    ),
                  OutlinedButton.icon(
                    onPressed: () => _showCustomerReliabilityDialog(order),
                    icon: const Icon(Icons.verified_user_outlined),
                    label: const Text('موثوقية العميل'),
                  ),
                  if (canAssign && hasAppDeliveryAgents)
                    OutlinedButton.icon(
                      onPressed: state.savingOrder || selectedDelivery == null
                          ? null
                          : () async {
                              final ok = await controller.assignCourierFlowV2(
                                orderId: order.id,
                                courierUserId: selectedDelivery,
                                // Keep the store-selected audit type aligned with the
                                // backend E2E flow for explicit owner dispatch.
                                assignmentMode: 'store_selected',
                              );
                              if (!ok || !mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.ownerOrdersCourierAssigned,
                                  ),
                                ),
                              );
                            },
                      icon: const Icon(Icons.local_shipping_outlined),
                      label: Text(
                        hasDeliveryAssigned && !order.isMerchantDelivery
                            ? l10n.ownerOrdersChangeCourier
                            : l10n.ownerOrdersAssignCourier,
                      ),
                    ),
                  if (order.status == 'pending' || order.status == 'approved')
                    ElevatedButton(
                      onPressed: state.savingOrder
                          ? null
                          : () async {
                              final allow = await _confirmReliabilityWarningIfNeeded(
                                order,
                              );
                              if (!allow || !mounted) return;
                              final updated = await controller
                                  .startPreparingFlowV2(
                                    orderId: order.id,
                                    preferredCourierUserId: selectedDelivery,
                                    estimatedPrepMinutes: 20,
                                  );
                              if (!updated || !mounted) return;
                              messenger.showSnackBar(
                                SnackBar(
                                  content: Text(
                                    l10n.ownerOrdersPreparationStarted,
                                  ),
                                ),
                              );
                            },
                      child: Text(l10n.ownerOrdersStartPreparing),
                    ),
                  if (order.status == 'preparing')
                    ElevatedButton(
                      onPressed: state.savingOrder
                          ? null
                          : () => controller.readyForPickupFlowV2(
                              orderId: order.id,
                              estimatedDeliveryMinutes: 30,
                            ),
                      child: Text(l10n.ownerOrdersReadyForPickup),
                    ),
                  if (order.isMerchantDelivery &&
                      (order.status == 'ready_for_delivery' ||
                          order.status == 'ready_for_pickup'))
                    ElevatedButton(
                      onPressed: state.savingOrder
                          ? null
                          : () => controller.updateOrderStatus(
                              orderId: order.id,
                              status: 'on_the_way',
                            ),
                      child: Text(l10n.ownerOrdersStatusOnTheWay),
                    ),
                  if (order.isMerchantDelivery && order.status == 'on_the_way')
                    ElevatedButton(
                      onPressed: state.savingOrder
                          ? null
                          : () => controller.updateOrderStatus(
                              orderId: order.id,
                              status: 'arrived',
                            ),
                      child: Text(l10n.ownerOrdersStatusArrived),
                    ),
                  if (order.isMerchantDelivery && order.status == 'arrived')
                    ElevatedButton(
                      onPressed: state.savingOrder
                          ? null
                          : () => controller.updateOrderStatus(
                              orderId: order.id,
                              status: 'delivered',
                            ),
                      child: Text(l10n.ownerOrdersStatusDelivered),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  final int pending;
  final int preparing;
  final int ready;
  final int delivering;
  final int total;
  final ValueChanged<String>? onCardTap;

  const _SummaryGrid({
    required this.pending,
    required this.preparing,
    required this.ready,
    required this.delivering,
    required this.total,
    this.onCardTap,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cards = [
      ('pending', l10n.commonPending, pending, Colors.orange),
      ('preparing', l10n.ownerOrdersStatusPreparing, preparing, Colors.cyan),
      ('ready', l10n.ownerOrdersSummaryReady, ready, Colors.green),
      (
        'delivering',
        l10n.ownerOrdersSummaryDelivering,
        delivering,
        Colors.blueAccent,
      ),
      ('total', l10n.commonTotal, total, Colors.purpleAccent),
    ];

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: cards
          .map(
            (card) => SizedBox(
              width: 140,
              child: InkWell(
                onTap: onCardTap == null ? null : () => onCardTap!(card.$1),
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withValues(alpha: 0.05),
                    border: Border.all(color: card.$4.withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        card.$2,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${card.$3}',
                        style: TextStyle(
                          color: card.$4,
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          )
          .toList(),
    );
  }
}

class _ReliabilityRow extends StatelessWidget {
  final String label;
  final String value;

  const _ReliabilityRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.left,
            ),
          ),
          Expanded(
            child: Text(
              label,
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String text;
  final Color color;

  const _StatusPill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;

  const _ErrorBanner({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.red.withValues(alpha: 0.12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.30)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.redAccent),
          const SizedBox(width: 8),
          Expanded(child: Text(message)),
          if (onRetry != null)
            TextButton(
              onPressed: onRetry,
              child: Text(context.l10n.commonRetry),
            ),
        ],
      ),
    );
  }
}
