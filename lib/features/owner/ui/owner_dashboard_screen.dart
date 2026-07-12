// ignore_for_file: use_build_context_synchronously, unused_element, unused_element_parameter

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/notifications/attention_alert_service.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../../core/utils/order_receipt_printing.dart';
import '../../../core/utils/report_printing.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../../core/widgets/desktop_dashboard_frame.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../auth/state/auth_controller.dart';
import '../../accountant/ui/accountant_dashboard_screen.dart';
import '../../coupons/ui/coupon_management_screen.dart';
import '../../hr/ui/hr_dashboard_screen.dart';
import '../../jobs/ui/jobs_hub_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/models/order_model.dart';
import '../../orders/ui/widgets/order_item_widgets.dart';
import '../../orders/ui/widgets/order_delivery_assignment_card.dart';
import '../../pharmacy/ui/pharmacy_conversation_screen.dart';
import '../../products/models/product_category_model.dart';
import '../../products/models/product_model.dart';
import '../../merchants/utils/catalog_taxonomy.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../settings/ui/pages/settings_support_screen.dart';
import 'store_owner_couriers_screen.dart';
import 'store_owner_kpis_screen.dart';
import 'store_owner_receivables_screen.dart';
import 'store_printer_settings_screen.dart';
import 'store_owner_offers_screen.dart';
import 'widgets/owner_dashboard_overview_panel.dart';
import '../models/owner_merchant_model.dart';
import '../state/owner_controller.dart';
import 'owner_product_form_sheet.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

/// Purpose: مساحة صاحب المتجر متعددة التبويبات لإدارة المتجر والطلبات والمنتجات وفريق العمل.
/// Used by: login routing الخاص بالـ owner، وروابط التنقل الداخلية من الموافقات والإشعارات.
/// Depends on: `ownerControllerProvider`, الشاشات الفرعية للإعدادات والطباعة والكوپونات والموارد البشرية والمحاسبة.
/// Critical notes: الشاشة تحمل منطق UI كثيفاً وبعضه legacy؛ لذلك يجب إبقاء source of truth في `OwnerController` وليس داخل عناصر الواجهة.
/// Maintenance notes: إذا علقت الواجهة أو ظهرت تنبيهات طلبات متكررة افحص `bootstrap/startLiveOrders` في controller ثم `_syncPendingOrderAlerts`.
enum OwnerProductAvailabilityFilter { all, available, unavailable }

List<ProductModel> filterOwnerProductsByAvailability(
  List<ProductModel> products,
  OwnerProductAvailabilityFilter filter,
) {
  switch (filter) {
    case OwnerProductAvailabilityFilter.available:
      return products.where((product) => product.isAvailable).toList();
    case OwnerProductAvailabilityFilter.unavailable:
      return products.where((product) => !product.isAvailable).toList();
    case OwnerProductAvailabilityFilter.all:
      return products.toList();
  }
}

enum OwnerDashboardTab { dashboard, profile, store, orders, catalog }

enum _OwnerTab { dashboard, profile, store, orders, catalog }

/// الواجهة الرئيسية لصاحب المتجر بعد تسجيل الدخول.
class OwnerDashboardScreen extends ConsumerStatefulWidget {
  final OwnerDashboardTab initialTab;

  const OwnerDashboardScreen({
    super.key,
    this.initialTab = OwnerDashboardTab.dashboard,
  });

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

/// حالة الشاشة التي تربط التبويبات ونوافذ الإدخال مع controller المركزي.
class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final imageCtrl = TextEditingController();
  final taglineCtrl = TextEditingController();
  final workingHoursCtrl = TextEditingController();
  final serviceAreaCtrl = TextEditingController();
  LocalImageFile? merchantImageFile;
  _OwnerTab activeTab = _OwnerTab.dashboard;
  OwnerProductAvailabilityFilter _productAvailabilityFilter =
      OwnerProductAvailabilityFilter.all;

  String merchantType = 'restaurant';
  bool isOpen = true;
  int? merchantId;
  Timer? _pendingOrdersAlertTimer;
  int _pendingOrdersAlertSignature = 0;
  late final OwnerController _ownerController;

  /// يغيّر التبويب النشط بعد التأكد من بقاء الشاشة مركبة.
  void _setOwnerTab(_OwnerTab tab) {
    if (!mounted) return;
    setState(() => activeTab = tab);
  }

  /// يحمّل snapshot owner الأساسي ثم يبدأ polling الطلبات الحالي.
  @override
  void initState() {
    super.initState();
    _ownerController = ref.read(ownerControllerProvider.notifier);
    activeTab = _toPrivateTab(widget.initialTab);
    Future.microtask(() async {
      if (!mounted) return;
      await _ownerController.bootstrap();
      if (!mounted) return;
      _ownerController.startLiveOrders();
    });
  }

  /// ينظف controllers والمؤقتات المرتبطة بالتنبيهات والطلبات الحية.
  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    phoneCtrl.dispose();
    imageCtrl.dispose();
    taglineCtrl.dispose();
    workingHoursCtrl.dispose();
    serviceAreaCtrl.dispose();
    _ownerController.stopLiveOrders();
    _stopPendingOrderAlerts();
    super.dispose();
  }

  /// يعرض تفاصيل analytics داخل bottom sheet مع مسارات طباعة وتصدير fallback.
  ///
  /// إذا فشل التصدير على جهاز معين يبدأ التشخيص من helpers الطباعة قبل الـ API،
  /// لأن الشاشة تملك مسار fallback نصي متعمد.
  Future<void> _openAnalyticsDetails({
    required String title,
    required List<String> lines,
    required String reportPeriod,
  }) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                textDirection: TextDirection.rtl,
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              ...lines.map(
                (line) => Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(line, textDirection: TextDirection.rtl),
                ),
              ),
              const SizedBox(height: 10),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    final raw = await ref
                        .read(ownerApiProvider)
                        .ordersPrintReport(period: reportPeriod);
                    final orders = raw
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    await printOrdersReceiptReport(
                      title: title,
                      summaryLines: lines,
                      orders: orders,
                    );
                  } catch (_) {
                    try {
                      await printSimpleReport(title: title, lines: lines);
                    } catch (_) {}
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تعذر فتح تقرير الطباعة على هذا الجهاز. تمت طباعة نسخة نصية بديلة. / Unable to open the print report on this device. A text fallback was printed.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة التقرير'),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    final raw = await ref
                        .read(ownerApiProvider)
                        .ordersPrintReport(period: reportPeriod);
                    final orders = raw
                        .map((e) => Map<String, dynamic>.from(e as Map))
                        .toList();
                    await exportOrdersExcelReport(
                      title: title,
                      summaryLines: lines,
                      orders: orders,
                    );
                  } catch (_) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تعذر تصدير ملف Excel في الوقت الحالي. حاول مرة أخرى. / Unable to export the Excel file right now. Please try again.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('تصدير Excel'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _OwnerTab _toPrivateTab(OwnerDashboardTab tab) {
    switch (tab) {
      case OwnerDashboardTab.dashboard:
        return _OwnerTab.dashboard;
      case OwnerDashboardTab.profile:
        return _OwnerTab.profile;
      case OwnerDashboardTab.store:
        return _OwnerTab.store;
      case OwnerDashboardTab.orders:
        return _OwnerTab.orders;
      case OwnerDashboardTab.catalog:
        return _OwnerTab.catalog;
    }
  }

  /// يربط state القادمة من controller بحقول الإدخال المحلية مرة واحدة لكل merchant id.
  ///
  /// هذا يمنع الكتابة فوق تعديلات المستخدم أثناء التحرير إذا وصلت rebuilds لاحقة.
  void _bindMerchant(OwnerState state) {
    final merchant = state.merchant;
    if (merchant == null) return;
    if (merchantId == merchant.id) return;

    merchantId = merchant.id;
    nameCtrl.text = merchant.name;
    descCtrl.text = merchant.description ?? '';
    phoneCtrl.text = merchant.phone ?? '';
    imageCtrl.text = merchant.imageUrl ?? '';
    taglineCtrl.text = merchant.tagline ?? '';
    workingHoursCtrl.text = merchant.workingHours ?? '';
    serviceAreaCtrl.text = merchant.serviceAreaNote ?? '';
    merchantImageFile = null;
    merchantType = merchant.type;
    isOpen = merchant.isOpen;
  }

  /// يفتح شيت إنشاء منتج بعد التأكد من وجود تصنيف واحد على الأقل.
  Future<void> _openCreateProduct(OwnerState ownerState) async {
    if (ownerState.categories.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('يجب إنشاء قسم واحد على الأقل قبل إضافة منتج.'),
        ),
      );
      return;
    }

    final data = await _openProductSheet(
      context,
      categories: ownerState.categories,
      merchantActivityType:
          ownerState.merchant?.activityType ??
          ownerState.merchant?.type ??
          'market',
      supportsPharmacyWorkflow:
          ownerState.merchant?.supportsPharmacyWorkflow == true,
    );
    if (data == null) return;
    await ref
        .read(ownerControllerProvider.notifier)
        .createProduct(
          name: data.name,
          description: data.description,
          categoryId: data.categoryId,
          price: data.price,
          discountedPrice: data.discountedPrice,
          imageUrl: data.imageUrl,
          imageFile: data.imageFile,
          freeDelivery: data.freeDelivery,
          offerLabel: data.offerLabel,
          isAvailable: data.isAvailable,
          unavailableReason: data.unavailableReason,
          unavailableUntil: data.unavailableUntil,
          requiresPrescription: data.requiresPrescription,
          requiresReview: data.requiresReview,
          sortOrder: data.sortOrder,
          stockQuantity: data.stockQuantity,
          attributes: data.attributes,
          variantGroups: data.variantGroups,
          variants: data.variants,
          media: data.media,
          galleryFiles: data.galleryFiles,
          variantFiles: data.variantFiles,
        );
  }

  Future<void> _openCreateDeliveryAgentSheet() async {
    final data = await _openDeliveryAgentSheet(context);
    if (data == null || !mounted) return;
    final ok = await ref
        .read(ownerControllerProvider.notifier)
        .createDeliveryAgent(
          fullName: data.fullName,
          phone: data.phone,
          pin: data.pin,
          imageFile: data.imageFile,
        );
    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('تم إنشاء مندوب التوصيل وربطه بالمتجر.')),
    );
  }

  Future<void> _openAddStaffUserSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _AddStaffUserSheet(),
    );
  }

  /// يطلق تنبيه الاهتمام عندما توجد طلبات pending ويمنع تكرار الصوت لنفس snapshot.
  void _syncPendingOrderAlerts(OwnerState state) {
    final pendingIds =
        state.currentOrders
            .where((order) => order.status == 'pending')
            .map((order) => order.id)
            .toList()
          ..sort();

    if (pendingIds.isEmpty) {
      _stopPendingOrderAlerts();
      return;
    }

    final nextSignature = Object.hashAll(pendingIds);
    if (nextSignature != _pendingOrdersAlertSignature) {
      _pendingOrdersAlertSignature = nextSignature;
      _playPendingOrderAlert();
    }

    _pendingOrdersAlertTimer ??= Timer.periodic(
      const Duration(seconds: 30),
      (_) => _playPendingOrderAlert(),
    );
  }

  void _playPendingOrderAlert() {
    ref.read(attentionAlertServiceProvider).play();
  }

  void _stopPendingOrderAlerts() {
    _pendingOrdersAlertTimer?.cancel();
    _pendingOrdersAlertTimer = null;
    _pendingOrdersAlertSignature = 0;
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

  Future<void> _openStorePrinterSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StorePrinterSettingsScreen()),
    );
  }

  Future<void> _openHrWorkspace() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const HrDashboardScreen()));
  }

  Future<void> _openAccountantWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AccountantDashboardScreen()),
    );
  }

  Future<void> _openKpisWorkspace() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StoreOwnerKpisScreen()));
  }

  Future<void> _openReceivablesWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const StoreOwnerReceivablesScreen()),
    );
  }

  Future<void> _openCouriersWorkspace() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const StoreOwnerCouriersScreen()));
  }

  String _periodTitleLabel(String period) {
    switch (period) {
      case 'day':
        return 'تفاصيل اليوم';
      case 'week':
        return 'تفاصيل الأسبوع';
      case 'month':
        return 'تفاصيل الشهر';
      case 'all':
        return 'الإجمالي';
      default:
        return 'تفاصيل التقرير';
    }
  }

  Future<void> _openPeriodReportDetails({
    required String period,
    required String title,
  }) async {
    try {
      final raw = await ref
          .read(ownerApiProvider)
          .ordersPrintReport(period: period);
      final orders = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      final summary = buildOwnerPeriodReportSummary(
        orders.map((row) => OrderModel.fromJson(row)).toList(growable: false),
      );
      if (!mounted) return;

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                            textAlign: TextAlign.right,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final cardWidth = constraints.maxWidth > 700
                            ? (constraints.maxWidth - 12) / 2
                            : constraints.maxWidth;
                        final items = <_ReportStatItem>[
                          _ReportStatItem(
                            label: 'عدد الطلبات',
                            value: '${summary.ordersCount}',
                            accent: const Color(0xFF3E7BFA),
                          ),
                          _ReportStatItem(
                            label: 'إجمالي المبيعات',
                            value: formatIqd(summary.grossSales),
                            accent: const Color(0xFF2AA876),
                          ),
                          _ReportStatItem(
                            label: 'المجموع الفرعي',
                            value: formatIqd(summary.subtotal),
                            accent: const Color(0xFFE97A2E),
                          ),
                          _ReportStatItem(
                            label: 'رسوم الخدمة المخزنة',
                            value: formatIqd(summary.serviceFee),
                            accent: const Color(0xFF9C4DCC),
                          ),
                          _ReportStatItem(
                            label: 'أجور التوصيل',
                            value: formatIqd(summary.deliveryFee),
                            accent: const Color(0xFFCC6B8E),
                          ),
                          _ReportStatItem(
                            label: 'متوسط الطلب',
                            value: formatIqd(summary.avgOrderValue),
                            accent: const Color(0xFF6C8FF5),
                          ),
                          _ReportStatItem(
                            label: 'الطلبات المكتملة',
                            value: '${summary.completedOrders}',
                            accent: const Color(0xFF4C78DD),
                          ),
                          _ReportStatItem(
                            label: 'الطلبات الملغاة',
                            value: '${summary.cancelledOrders}',
                            accent: const Color(0xFFD05A5A),
                          ),
                        ];
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: items
                              .map(
                                (item) => SizedBox(
                                  width: cardWidth,
                                  child: _ReportStatCard(item: item),
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    ),
                    const SizedBox(height: 14),
                    _SectionCard(
                      title: 'ملخص الفترة',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: summary.summaryLines
                            .map(
                              (line) => Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  line,
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            )
                            .toList(growable: false),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            try {
                              await printOrdersReceiptReport(
                                title: title,
                                summaryLines: summary.summaryLines,
                                orders: orders,
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تعذر طباعة التقرير. / Unable to print the report right now.',
                                    textDirection: TextDirection.rtl,
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.print_outlined),
                          label: const Text('طباعة التقرير'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () async {
                            try {
                              await exportOrdersExcelReport(
                                title: title,
                                summaryLines: summary.summaryLines,
                                orders: orders,
                              );
                            } catch (e) {
                              if (!mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'تعذر تصدير ملف Excel. / Unable to export the Excel report right now.',
                                    textDirection: TextDirection.rtl,
                                  ),
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.table_chart_outlined),
                          label: const Text('تصدير Excel'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SectionCard(
                      title: 'أحدث الطلبات',
                      child: orders.isEmpty
                          ? const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Text(
                                'لا توجد طلبات ضمن هذه الفترة.',
                                textAlign: TextAlign.center,
                              ),
                            )
                          : Column(
                              children: orders
                                  .take(6)
                                  .map((row) {
                                    final order = OrderModel.fromJson(row);
                                    return ListTile(
                                      contentPadding: EdgeInsets.zero,
                                      title: Text(
                                        'طلب #${order.id} - ${order.customerFullName}',
                                        textDirection: TextDirection.rtl,
                                      ),
                                      subtitle: Text(
                                        '${order.status} • ${formatIqd(order.totalAmount)}',
                                        textDirection: TextDirection.rtl,
                                      ),
                                      trailing: const Icon(
                                        Icons.chevron_left_rounded,
                                      ),
                                    );
                                  })
                                  .toList(growable: false),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تعذر فتح ${_periodTitleLabel(period)}. / Unable to open the selected report period right now.',
            textDirection: TextDirection.rtl,
          ),
        ),
      );
    }
  }

  String _ownerTabTitle() {
    switch (activeTab) {
      case _OwnerTab.dashboard:
        return context.l10n.ownerDashboardTitle;
      case _OwnerTab.profile:
        return 'الملف الشخصي';
      case _OwnerTab.store:
        return 'بيانات المتجر';
      case _OwnerTab.orders:
        return 'إدارة الطلبات';
      case _OwnerTab.catalog:
        return 'إدارة المنتجات';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerState = ref.watch(ownerControllerProvider);
    final auth = ref.watch(authControllerProvider);
    String lt(String ar, String en) => context.localizedText(ar: ar, en: en);
    final merchant = ownerState.merchant;
    final catalogProducts = filterOwnerProductsByAvailability(
      ownerState.products,
      _productAvailabilityFilter,
    );
    final drawerItems = <AppUserDrawerItem>[
      AppUserDrawerItem(
        icon: Icons.dashboard_outlined,
        label: 'لوحة المتجر',
        onTap: (_) async => _setOwnerTab(_OwnerTab.dashboard),
      ),
      AppUserDrawerItem(
        icon: Icons.person_outline_rounded,
        label: 'الملف الشخصي',
        onTap: (_) async => _setOwnerTab(_OwnerTab.profile),
      ),
      AppUserDrawerItem(
        icon: Icons.storefront_outlined,
        label: lt('إدارة المتجر', 'Store management'),
        onTap: (_) async => _setOwnerTab(_OwnerTab.store),
      ),
      AppUserDrawerItem(
        icon: Icons.print_rounded,
        label: lt('إعدادات الطباعة', 'Printer settings'),
        subtitle: lt(
          'اضبط وضع الطباعة والطابعة الحرارية بعرض 58 مم',
          'Configure print mode and 58mm thermal printer',
        ),
        onTap: (_) async => _openStorePrinterSettings(),
      ),
      AppUserDrawerItem(
        icon: Icons.receipt_long_outlined,
        label: lt('إدارة الطلبات', 'Order management'),
        onTap: (_) async => _setOwnerTab(_OwnerTab.orders),
      ),
      AppUserDrawerItem(
        icon: Icons.inventory_2_outlined,
        label: 'إدارة المنتجات',
        onTap: (_) async => _setOwnerTab(_OwnerTab.catalog),
      ),
      AppUserDrawerItem(
        icon: Icons.person_add_alt_1_rounded,
        label: 'إضافة عضو فريق',
        subtitle: 'متاح فقط لأدوار الدلفري / المحاسب / HR',
        onTap: (_) async => _openAddStaffUserSheet(),
      ),
      AppUserDrawerItem(
        icon: Icons.badge_outlined,
        label: lt('HR', 'HR'),
        subtitle: lt(
          'افتح مساحة عمل الموارد البشرية بحساب المالك',
          'Open HR workspace using owner account',
        ),
        onTap: (_) async => _openHrWorkspace(),
      ),
      AppUserDrawerItem(
        icon: Icons.account_balance_wallet_outlined,
        label: lt('ACCOUNTANT', 'ACCOUNTANT'),
        subtitle: lt(
          'افتح مساحة عمل المحاسب بحساب المالك',
          'Open accountant workspace using owner account',
        ),
        onTap: (_) async => _openAccountantWorkspace(),
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: context.l10n.drawerRefresh,
        onTap: (_) async =>
            ref.read(ownerControllerProvider.notifier).bootstrap(),
      ),
      AppUserDrawerItem(
        icon: Icons.confirmation_number_outlined,
        label: 'إدارة الكوبونات',
        subtitle: 'إدارة كوبونات المتجر وتقارير الاستخدام',
        onTap: (_) async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) =>
                  const CouponManagementScreen(mode: CouponManagerMode.owner),
            ),
          );
        },
      ),
      AppUserDrawerItem(
        icon: Icons.local_offer_outlined,
        label: '\u0639\u0631\u0648\u0636 \u0627\u0644\u0645\u062a\u062c\u0631',
        subtitle:
            '\u0625\u062f\u0627\u0631\u0629 \u062e\u0635\u0648\u0645 \u0627\u0644\u0645\u0646\u062a\u062c\u0627\u062a \u0648\u0627\u0644\u0639\u0631\u0648\u0636 \u0627\u0644\u0645\u062c\u062f\u0648\u0644\u0629',
        onTap: (_) async {
          await Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const StoreOwnerOffersScreen()),
          );
        },
      ),
      AppUserDrawerItem(
        icon: Icons.work_history_outlined,
        label: 'إدارة الوظائف',
        subtitle: 'أنشئ وظائف المتجر وراجع المتقدمين',
        onTap: (_) async {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => const JobsHubScreen(startInManageMode: true),
            ),
          );
        },
      ),
      if (merchant?.supportsPharmacyWorkflow == true)
        AppUserDrawerItem(
          icon: Icons.local_hospital_outlined,
          label: context.l10n.pharmacyConversationsTitle,
          subtitle: context.l10n.pharmacyConversationsDrawerSubtitle,
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => const OwnerPharmacyConversationsScreen(),
              ),
            );
          },
        ),
      AppUserDrawerItem(
        icon: Icons.add_box_outlined,
        label: context.l10n.drawerAddProduct,
        onTap: (_) async => _openCreateProduct(ownerState),
      ),
    ];

    ref.listen<OwnerState>(ownerControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      _syncPendingOrderAlerts(next);
    });

    _bindMerchant(ownerState);

    if (ownerState.loading && merchant == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (merchant != null &&
        merchant.approvalStatus == 'awaiting_store_financial_acceptance') {
      return _OwnerFinancialTermsReviewView(
        merchant: merchant,
        loading: ownerState.loading,
      );
    }

    if (merchant != null && !merchant.isApproved) {
      return _OwnerPendingApprovalView(
        merchant: merchant,
        loading: ownerState.loading,
      );
    }

    final useDesktop = DesktopDashboardFrame.shouldUse(context);
    final drawerWidget = AppUserDrawer(
      title: _ownerTabTitle(),
      subtitle: context.l10n.drawerOwnerSub,
      items: drawerItems,
      embedded: useDesktop,
    );

    final bodyContent = ownerState.loading
        ? const Center(child: CircularProgressIndicator())
        : RefreshIndicator(
            onRefresh: () =>
                ref.read(ownerControllerProvider.notifier).bootstrap(),
            child: ListView(
              padding: const EdgeInsets.all(14),
              children: [
                _OwnerQuickTabs(
                  activeTab: activeTab,
                  onSelectTab: _setOwnerTab,
                ),
                const SizedBox(height: 12),
                if (activeTab == _OwnerTab.profile)
                  _SectionCard(
                    title: 'الملف الشخصي',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: CircleAvatar(
                            radius: 20,
                            backgroundImage:
                                auth.user?.imageUrl?.isNotEmpty == true
                                ? AppCachedImageProvider(auth.user!.imageUrl!)
                                : null,
                            child: auth.user?.imageUrl?.isNotEmpty == true
                                ? null
                                : const Icon(Icons.person_outline),
                          ),
                          title: Text(auth.user?.fullName ?? '-'),
                          subtitle: Text(auth.user?.phone ?? '-'),
                        ),
                        Text(
                          'الدور: ${auth.user?.role ?? 'owner'}',
                          textDirection: TextDirection.rtl,
                        ),
                        Text(
                          'السكن: بلوك ${auth.user?.block ?? '-'} - بناية ${auth.user?.buildingNumber ?? '-'} - شقة ${auth.user?.apartment ?? '-'}',
                          textDirection: TextDirection.rtl,
                        ),
                        const SizedBox(height: 8),
                        if (ownerState.merchant != null)
                          Text(
                            'المتجر المرتبط: ${ownerState.merchant!.name}',
                            textDirection: TextDirection.rtl,
                          ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            onPressed: _openAccountSettings,
                            icon: const Icon(Icons.security_outlined),
                            label: const Text('إعدادات الحساب والأمان'),
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
                if (activeTab == _OwnerTab.profile) const SizedBox(height: 14),
                if (activeTab == _OwnerTab.store)
                  _SectionCard(
                    title: 'بيانات المتجر',
                    child: Column(
                      children: [
                        TextField(
                          controller: nameCtrl,
                          decoration: const InputDecoration(
                            labelText: 'اسم المتجر',
                          ),
                        ),
                        const SizedBox(height: 10),
                        DropdownButtonFormField<String>(
                          initialValue: merchantType,
                          items: const [
                            DropdownMenuItem(
                              value: 'restaurant',
                              child: Text('مطعم'),
                            ),
                            DropdownMenuItem(
                              value: 'market',
                              child: Text('متجر'),
                            ),
                          ],
                          onChanged: (v) =>
                              setState(() => merchantType = v ?? 'restaurant'),
                          decoration: const InputDecoration(
                            labelText: 'نوع المتجر',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: descCtrl,
                          decoration: const InputDecoration(labelText: 'الوصف'),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: taglineCtrl,
                          decoration: const InputDecoration(
                            labelText: 'الشعار / عبارة المتجر',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: workingHoursCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ساعات العمل',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: serviceAreaCtrl,
                          decoration: const InputDecoration(
                            labelText: 'نطاق التوصيل',
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextField(
                          controller: phoneCtrl,
                          decoration: const InputDecoration(
                            labelText: 'رقم الهاتف',
                          ),
                        ),
                        const SizedBox(height: 10),
                        ImagePickerField(
                          title: 'صورة المتجر',
                          selectedFile: merchantImageFile,
                          existingImageUrl: imageCtrl.text.trim().isEmpty
                              ? null
                              : imageCtrl.text.trim(),
                          onPick: () async {
                            final picked = await pickImageFromDevice();
                            if (!mounted || picked == null) return;
                            setState(() => merchantImageFile = picked);
                          },
                          onClear:
                              merchantImageFile == null &&
                                  imageCtrl.text.trim().isEmpty
                              ? null
                              : () => setState(() {
                                  merchantImageFile = null;
                                  imageCtrl.text = '';
                                }),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile(
                          title: const Text('المتجر مفتوح الآن'),
                          value: isOpen,
                          onChanged: (v) => setState(() => isOpen = v),
                        ),
                        const SizedBox(height: 10),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: ownerState.savingMerchant
                                ? null
                                : () async {
                                    await ref
                                        .read(ownerControllerProvider.notifier)
                                        .updateMerchant(
                                          name: nameCtrl.text,
                                          type: merchantType,
                                          description: descCtrl.text,
                                          phone: phoneCtrl.text,
                                          imageUrl: imageCtrl.text,
                                          tagline: taglineCtrl.text,
                                          workingHours: workingHoursCtrl.text,
                                          serviceAreaNote: serviceAreaCtrl.text,
                                          imageFile: merchantImageFile,
                                          isOpen: isOpen,
                                        );
                                  },
                            child: ownerState.savingMerchant
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('حفظ بيانات المتجر'),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (activeTab == _OwnerTab.dashboard)
                  const SizedBox(height: 14),
                if (activeTab == _OwnerTab.dashboard)
                  OwnerDashboardOverviewPanel(
                    state: ownerState,
                    saving: ownerState.savingOrder,
                    onOpenPeriodReport: ({required period, required title}) {
                      return _openPeriodReportDetails(
                        period: period,
                        title: title,
                      );
                    },
                    onOpenCurrentOrders: () => _setOwnerTab(_OwnerTab.orders),
                    onOpenCatalog: () => _setOwnerTab(_OwnerTab.catalog),
                    onOpenAddProduct: () => _openCreateProduct(ownerState),
                    onOpenKpis: _openKpisWorkspace,
                    onOpenReceivables: _openReceivablesWorkspace,
                    onOpenCouriers: _openCouriersWorkspace,
                    onOpenHr: _openHrWorkspace,
                    onOpenPrinterSettings: _openStorePrinterSettings,
                    onRequestSettlement: () async {
                      await ref
                          .read(ownerControllerProvider.notifier)
                          .requestSettlement();
                    },
                  ),
                if (activeTab == _OwnerTab.orders) const SizedBox(height: 14),
                if (activeTab == _OwnerTab.orders)
                  _SectionCard(
                    title: 'الطلبات الحالية',
                    child: ownerState.currentOrders.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('لا توجد طلبات حالية'),
                          )
                        : Column(
                            children: ownerState.currentOrders
                                .map(
                                  (order) =>
                                      _buildCurrentOrderCard(order, ownerState),
                                )
                                .toList(),
                          ),
                  ),
                if (activeTab == _OwnerTab.orders) const SizedBox(height: 14),
                if (activeTab == _OwnerTab.orders)
                  _SectionCard(
                    title: 'الطلبات السابقة',
                    child: ownerState.historyOrders.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('لا توجد طلبات سابقة'),
                          )
                        : Column(
                            children: ownerState.historyOrders
                                .map(
                                  (o) => ListTile(
                                    title: Text(
                                      'طلب #${o.id} - ${o.customerFullName}',
                                      textDirection: TextDirection.rtl,
                                    ),
                                    subtitle: Text(
                                      'الإجمالي: ${formatIqd(o.totalAmount)} - التقييم: ${o.deliveryRating ?? '-'}',
                                      textDirection: TextDirection.rtl,
                                    ),
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                if (activeTab == _OwnerTab.catalog) const SizedBox(height: 14),
                if (activeTab == _OwnerTab.catalog)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        FilterChip(
                          label: const Text('الكل / All'),
                          selected:
                              _productAvailabilityFilter ==
                              OwnerProductAvailabilityFilter.all,
                          onSelected: (_) => setState(
                            () => _productAvailabilityFilter =
                                OwnerProductAvailabilityFilter.all,
                          ),
                        ),
                        FilterChip(
                          label: const Text('متاح / Available'),
                          selected:
                              _productAvailabilityFilter ==
                              OwnerProductAvailabilityFilter.available,
                          onSelected: (_) => setState(
                            () => _productAvailabilityFilter =
                                OwnerProductAvailabilityFilter.available,
                          ),
                        ),
                        FilterChip(
                          label: const Text('غير متاح / Unavailable'),
                          selected:
                              _productAvailabilityFilter ==
                              OwnerProductAvailabilityFilter.unavailable,
                          onSelected: (_) => setState(
                            () => _productAvailabilityFilter =
                                OwnerProductAvailabilityFilter.unavailable,
                          ),
                        ),
                      ],
                    ),
                  ),
                if (activeTab == _OwnerTab.catalog) const SizedBox(height: 10),
                if (activeTab == _OwnerTab.catalog)
                  _SectionCard(
                    title: 'إدارة التصنيفات',
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerRight,
                          child: OutlinedButton.icon(
                            onPressed: ownerState.savingProduct
                                ? null
                                : () async {
                                    final data = await _openCategorySheet(
                                      context,
                                      merchantActivityType:
                                          ownerState.merchant?.activityType ??
                                          ownerState.merchant?.type ??
                                          'market',
                                    );
                                    if (data == null) return;
                                    await ref
                                        .read(ownerControllerProvider.notifier)
                                        .createCategory(
                                          name: data.name,
                                          sortOrder: data.sortOrder,
                                          catalogType: data.catalogType,
                                        );
                                  },
                            icon: const Icon(Icons.add),
                            label: const Text('إضافة قسم'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        if (ownerState.categories.isEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 8),
                            child: Text('لا توجد أقسام بعد'),
                          )
                        else
                          ...ownerState.categories.map(
                            (category) => _CategoryTile(
                              category: category,
                              onEdit: () async {
                                final data = await _openCategorySheet(
                                  context,
                                  category: category,
                                  merchantActivityType:
                                      ownerState.merchant?.activityType ??
                                      ownerState.merchant?.type ??
                                      'market',
                                );
                                if (data == null) return;
                                await ref
                                    .read(ownerControllerProvider.notifier)
                                    .updateCategory(
                                      categoryId: category.id,
                                      name: data.name,
                                      sortOrder: data.sortOrder,
                                      catalogType: data.catalogType,
                                    );
                              },
                              onDelete: () async {
                                final confirm = await showDialog<bool>(
                                  context: context,
                                  builder: (_) => AlertDialog(
                                    title: const Text('حذف القسم'),
                                    content: const Text(
                                      'سيؤدي حذف هذا القسم إلى فقدان ربط المنتجات به. هل تريد المتابعة؟',
                                      textDirection: TextDirection.rtl,
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('إلغاء'),
                                      ),
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: const Text('حذف'),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirm == true) {
                                  await ref
                                      .read(ownerControllerProvider.notifier)
                                      .deleteCategory(category.id);
                                }
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                if (activeTab == _OwnerTab.catalog) const SizedBox(height: 14),
                if (activeTab == _OwnerTab.catalog)
                  _SectionCard(
                    title: 'إدارة المنتجات',
                    child: catalogProducts.isEmpty
                        ? const Padding(
                            padding: EdgeInsets.symmetric(vertical: 20),
                            child: Text('لا توجد منتجات بعد'),
                          )
                        : Column(
                            children: catalogProducts
                                .map(
                                  (product) => _ProductTile(
                                    product: product,
                                    onEdit: () async {
                                      final data = await _openProductSheet(
                                        context,
                                        product: product,
                                        categories: ownerState.categories,
                                        merchantActivityType:
                                            ownerState.merchant?.activityType ??
                                            ownerState.merchant?.type ??
                                            'market',
                                        supportsPharmacyWorkflow:
                                            ownerState
                                                .merchant
                                                ?.supportsPharmacyWorkflow ==
                                            true,
                                      );
                                      if (data == null) return;
                                      await ref
                                          .read(
                                            ownerControllerProvider.notifier,
                                          )
                                          .updateProduct(
                                            productId: product.id,
                                            name: data.name,
                                            description: data.description,
                                            categoryId: data.categoryId,
                                            price: data.price,
                                            discountedPrice:
                                                data.discountedPrice,
                                            imageUrl: data.imageUrl,
                                            imageFile: data.imageFile,
                                            freeDelivery: data.freeDelivery,
                                            offerLabel: data.offerLabel,
                                            isAvailable: data.isAvailable,
                                            unavailableReason:
                                                data.unavailableReason,
                                            unavailableUntil:
                                                data.unavailableUntil,
                                            requiresPrescription:
                                                data.requiresPrescription,
                                            requiresReview: data.requiresReview,
                                            sortOrder: data.sortOrder,
                                            stockQuantity: data.stockQuantity,
                                            attributes: data.attributes,
                                            variantGroups: data.variantGroups,
                                            variants: data.variants,
                                            media: data.media,
                                            galleryFiles: data.galleryFiles,
                                            variantFiles: data.variantFiles,
                                          );
                                    },
                                    onDelete: () async {
                                      final confirm = await showDialog<bool>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: const Text('حذف المنتج'),
                                          content: const Text(
                                            'هل تريد حذف هذا المنتج نهائيًا؟',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('إلغاء'),
                                            ),
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('حذف'),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (confirm == true) {
                                        await ref
                                            .read(
                                              ownerControllerProvider.notifier,
                                            )
                                            .deleteProduct(product.id);
                                      }
                                    },
                                    onRestoreAvailability:
                                        ownerState.savingProduct ||
                                            product.isAvailable
                                        ? null
                                        : () async {
                                            await ref
                                                .read(
                                                  ownerControllerProvider
                                                      .notifier,
                                                )
                                                .updateProductAvailability(
                                                  productId: product.id,
                                                  isAvailable: true,
                                                  unavailableReason: null,
                                                  unavailableUntil: null,
                                                );
                                          },
                                  ),
                                )
                                .toList(),
                          ),
                  ),
                const SizedBox(height: 90),
              ],
            ),
          );

    return Scaffold(
      drawer: useDesktop ? null : drawerWidget,
      appBar: AppBar(
        title: Text(_ownerTabTitle()),
        actions: [
          if (useDesktop)
            IconButton(
              tooltip: lt('الحساب', 'Account'),
              onPressed: _openAccountSettings,
              icon: const Icon(Icons.manage_accounts_outlined),
            ),
          const NotificationsBellButton(),
        ],
      ),
      floatingActionButton: !useDesktop && activeTab == _OwnerTab.catalog
          ? FloatingActionButton.extended(
              heroTag: null,
              onPressed: ownerState.savingProduct
                  ? null
                  : () => _openCreateProduct(ownerState),
              icon: const Icon(Icons.add),
              label: const Text('إضافة منتج'),
            )
          : null,
      body: useDesktop
          ? Padding(
              padding: const EdgeInsets.all(14),
              child: DesktopDashboardFrame(
                sidebar: drawerWidget,
                title: _ownerTabTitle(),
                subtitle: lt(
                  'مساحة عمل المتجر على سطح المكتب: تحكم أسرع بالطلبات والمنتجات والتحديثات.',
                  'Desktop store workspace: faster orders, catalog, and updates control.',
                ),
                statusLabel: lt('المتجر والطلبات', 'Store & Orders'),
                statusIcon: Icons.storefront_outlined,
                quickActions: [
                  DesktopQuickActionButton(
                    icon: Icons.dashboard_outlined,
                    label: lt('لوحة المتجر', 'Dashboard'),
                    selected: activeTab == _OwnerTab.dashboard,
                    onPressed: () => _setOwnerTab(_OwnerTab.dashboard),
                  ),
                  DesktopQuickActionButton(
                    icon: Icons.person_outline_rounded,
                    label: lt('الملف الشخصي', 'Profile'),
                    selected: activeTab == _OwnerTab.profile,
                    onPressed: () => _setOwnerTab(_OwnerTab.profile),
                  ),
                  DesktopQuickActionButton(
                    icon: Icons.storefront_outlined,
                    label: lt('المتجر', 'Store'),
                    selected: activeTab == _OwnerTab.store,
                    onPressed: () => _setOwnerTab(_OwnerTab.store),
                  ),
                  DesktopQuickActionButton(
                    icon: Icons.receipt_long_outlined,
                    label: lt('الطلبات', 'Orders'),
                    selected: activeTab == _OwnerTab.orders,
                    onPressed: () => _setOwnerTab(_OwnerTab.orders),
                  ),
                  DesktopQuickActionButton(
                    icon: Icons.inventory_2_outlined,
                    label: lt('المنتجات', 'Catalog'),
                    selected: activeTab == _OwnerTab.catalog,
                    onPressed: () => _setOwnerTab(_OwnerTab.catalog),
                  ),
                  if (activeTab == _OwnerTab.catalog)
                    DesktopQuickActionButton(
                      icon: Icons.add_box_outlined,
                      label: lt('إضافة منتج', 'Add Product'),
                      onPressed: ownerState.savingProduct
                          ? null
                          : () => _openCreateProduct(ownerState),
                    ),
                ],
                child: bodyContent,
              ),
            )
          : bodyContent,
    );
  }

  Widget _buildCurrentOrderCard(OrderModel order, OwnerState ownerState) {
    final controller = ref.read(ownerControllerProvider.notifier);
    final isPending = order.status == 'pending';
    final hasDeliveryAssigned = order.hasAssignedDelivery;
    final statusInfoText = ownerOrderStatusHint(
      order.status,
      hasDeliveryAssigned: hasDeliveryAssigned,
      customerConfirmed: order.customerConfirmedAt != null,
      isMerchantDelivery: order.isMerchantDelivery,
    );
    final messenger = ScaffoldMessenger.of(context);
    final assignmentMode = order.isMerchantDelivery
        ? 'merchant_delivery'
        : 'platform_delivery';

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      color: isPending
          ? Colors.amber.withValues(alpha: 0.12)
          : Colors.white.withValues(alpha: 0.04),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isPending
              ? Colors.amber.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.08),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'الطلب #${order.id} - ${orderStatusLabel(order.status)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.customerImageUrl?.trim().isNotEmpty == true)
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: AppCachedImageProvider(
                      order.customerImageUrl!,
                    ),
                  )
                else
                  const CircleAvatar(
                    radius: 18,
                    child: Icon(Icons.person_outline),
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'الزبون: ${order.customerFullName} - ${order.customerPhone}',
                        textDirection: TextDirection.rtl,
                      ),
                      Text(
                        'العنوان: ${order.customerCity} - بلوك ${order.customerBlock} - بناية ${order.customerBuildingNumber} - شقة ${order.customerApartment}',
                        textDirection: TextDirection.rtl,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (order.imageUrl?.trim().isNotEmpty == true) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 110,
                  width: double.infinity,
                  child: CachedAppImage(
                    imageUrl: order.imageUrl!,
                    fit: BoxFit.cover,
                    errorWidget: (context, error, stackTrace) {
                      return const Center(child: Icon(Icons.broken_image));
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
            OrderDeliveryAssignmentCard(
              assignment: order.deliveryAssignment,
              waitingCopy: context.lt(
                ar: 'لا يوجد دلفري متاح حالياً',
                en: 'No courier is available right now',
              ),
              helperText: context.lt(
                ar: 'سيتم تعيين أول دلفري متاح تلقائياً، ويمكنك متابعة تجهيز الطلب.',
                en: 'The first available courier will be assigned automatically while you prepare the order.',
              ),
              visibleWhenNoAssignment: true,
              onCall: (order.deliveryAssignment?.driver?.phone ??
                          order.deliveryPhone)
                      ?.trim()
                      .isNotEmpty ==
                  true
                  ? () async {
                      final phone =
                          (order.deliveryAssignment?.driver?.phone ??
                                  order.deliveryPhone)
                              ?.trim();
                      if (phone == null || phone.isEmpty) return;
                      await launchUrl(
                        Uri.parse('tel:$phone'),
                        mode: LaunchMode.externalApplication,
                      );
                    }
                  : null,
            ),
            const SizedBox(height: 6),
            ...order.items.asMap().entries.map((entry) {
              final item = entry.value;
              final presentation = order.presentationItems[entry.key];
              ProductModel? linkedProduct;
              if (item.productId != null) {
                for (final product in ownerState.products) {
                  if (product.id == item.productId) {
                    linkedProduct = product;
                    break;
                  }
                }
              }
              final canMarkUnavailable =
                  item.productId != null &&
                  (linkedProduct?.isAvailable ?? true);

              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withValues(alpha: 0.05),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    OrderItemMiniCard(
                      item: presentation,
                      compact: false,
                      showStoreName: false,
                      showSections: true,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        if (item.productId != null)
                          TextButton.icon(
                            onPressed:
                                ownerState.savingOrder || !canMarkUnavailable
                                ? null
                                : () async {
                                    final confirm = await showDialog<bool>(
                                      context: context,
                                      builder: (_) => AlertDialog(
                                        title: const Text(
                                          'تعليم المنتج كغير متاح',
                                        ),
                                        content: Text(
                                          'سيتم تعليم المنتج ${item.productName} كغير متاح حتى لا يستقبل المتجر طلبات جديدة له. هل تريد المتابعة؟',
                                          textDirection: TextDirection.rtl,
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, false),
                                            child: const Text('إلغاء'),
                                          ),
                                          TextButton(
                                            onPressed: () =>
                                                Navigator.pop(context, true),
                                            child: const Text('تأكيد'),
                                          ),
                                        ],
                                      ),
                                    );
                                    if (confirm != true) return;
                                    await controller.markOrderItemUnavailable(
                                      orderId: order.id,
                                      productId: item.productId!,
                                    );
                                  },
                            icon: const Icon(Icons.remove_circle_outline),
                            label: const Text('غير متاح'),
                          ),
                        const Spacer(),
                        _InlineStateChip(
                          text: linkedProduct?.isAvailable == false
                              ? 'غير متاح'
                              : 'متاح',
                          color: linkedProduct?.isAvailable == false
                              ? Colors.redAccent.withValues(alpha: 0.18)
                              : Colors.green.withValues(alpha: 0.18),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }),
            if (statusInfoText != null) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.cyan.withValues(alpha: 0.1),
                  border: Border.all(
                    color: Colors.cyan.withValues(alpha: 0.24),
                  ),
                ),
                child: Text(
                  statusInfoText,
                  textDirection: TextDirection.rtl,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () async {
                    final printed = await printOwnerOrderReceipt58mm(
                      order: order,
                      assignmentMode: assignmentMode,
                      appTitle: 'MASLAKI',
                      statusOverride: order.status,
                    );
                    if (!mounted) return;
                    messenger.showSnackBar(
                      SnackBar(
                        content: Text(
                          printed
                              ? 'تمت طباعة الطلب بنجاح.'
                              : 'تعذر إرسال أمر الطباعة. تحقق من إعدادات الطابعة.',
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.print_outlined),
                  label: const Text('طباعة الطلب'),
                ),
                if (order.status == 'pending')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.updateOrderStatus(
                            orderId: order.id,
                            status: 'approved',
                          ),
                    child: const Text('اعتماد الطلب'),
                  ),
                if (order.status == 'approved')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () async {
                            // Delivery is auto-assigned by the backend once
                            // preparation starts; no store-side courier pick.
                            final updated = await controller
                                .startPreparingFlowV2(
                                  orderId: order.id,
                                  estimatedPrepMinutes: 20,
                                );
                            if (!updated) return;
                            if (!mounted) return;
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'تم بدء التحضير. يمكنك تعديل وقت التجهيز لاحقًا إذا لزم.',
                                ),
                              ),
                            );
                          },
                    child: const Text('بدء التحضير'),
                  ),
                if (order.status == 'preparing')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.readyForPickupFlowV2(
                            orderId: order.id,
                            estimatedDeliveryMinutes: 30,
                          ),
                    child: const Text('جاهز للتوصيل'),
                  ),
                if (order.isMerchantDelivery &&
                    order.status == 'ready_for_delivery')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.updateOrderStatus(
                            orderId: order.id,
                            status: 'on_the_way',
                          ),
                    child: const Text('بدء التوصيل'),
                  ),
                if (order.isMerchantDelivery && order.status == 'on_the_way')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.updateOrderStatus(
                            orderId: order.id,
                            status: 'arrived',
                          ),
                    child: const Text('تم الوصول'),
                  ),
                if (order.isMerchantDelivery && order.status == 'arrived')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.updateOrderStatus(
                            orderId: order.id,
                            status: 'delivered',
                          ),
                    child: const Text('تم التسليم'),
                  ),
                if (const {
                  'pending',
                  'approved',
                  'preparing',
                  'ready_for_delivery',
                }.contains(order.status))
                  TextButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.updateOrderStatus(
                            orderId: order.id,
                            status: 'cancelled',
                          ),
                    child: const Text('إلغاء الطلب'),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<ProductFormData?> _openProductSheet(
    BuildContext context, {
    ProductModel? product,
    required List<ProductCategoryModel> categories,
    bool supportsPharmacyWorkflow = false,
    required String merchantActivityType,
  }) {
    return showModalBottomSheet<ProductFormData>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ProductFormSheet(
        product: product,
        categories: categories,
        merchantActivityType: merchantActivityType,
        supportsPharmacyWorkflow: supportsPharmacyWorkflow,
      ),
    );
  }

  Future<_CategoryFormData?> _openCategorySheet(
    BuildContext context, {
    ProductCategoryModel? category,
    required String merchantActivityType,
  }) {
    return showModalBottomSheet<_CategoryFormData>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryFormSheet(
        category: category,
        merchantActivityType: merchantActivityType,
      ),
    );
  }

  Future<_DeliveryAgentFormData?> _openDeliveryAgentSheet(
    BuildContext context,
  ) {
    return showModalBottomSheet<_DeliveryAgentFormData>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _DeliveryAgentFormSheet(),
    );
  }
}

class _OwnerQuickTabs extends StatelessWidget {
  final _OwnerTab activeTab;
  final ValueChanged<_OwnerTab> onSelectTab;

  const _OwnerQuickTabs({required this.activeTab, required this.onSelectTab});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _OwnerTabChip(
            label: 'لوحة المتجر',
            selected: activeTab == _OwnerTab.dashboard,
            onTap: () => onSelectTab(_OwnerTab.dashboard),
          ),
          _OwnerTabChip(
            label: 'بيانات المتجر',
            selected: activeTab == _OwnerTab.store,
            onTap: () => onSelectTab(_OwnerTab.store),
          ),
          _OwnerTabChip(
            label: 'الطلبات',
            selected: activeTab == _OwnerTab.orders,
            onTap: () => onSelectTab(_OwnerTab.orders),
          ),
          _OwnerTabChip(
            label: 'المنتجات',
            selected: activeTab == _OwnerTab.catalog,
            onTap: () => onSelectTab(_OwnerTab.catalog),
          ),
          _OwnerTabChip(
            label: 'الملف الشخصي',
            selected: activeTab == _OwnerTab.profile,
            onTap: () => onSelectTab(_OwnerTab.profile),
          ),
        ],
      ),
    );
  }
}

class _OwnerTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _OwnerTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 8),
      child: Material(
        color: selected
            ? scheme.primary.withValues(alpha: 0.18)
            : Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: selected ? scheme.primary : Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OwnerMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _OwnerMetricTile({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 148,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.08),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(icon, size: 18),
                  const Spacer(),
                  if (onTap != null)
                    const Icon(Icons.chevron_right_rounded, size: 16),
                ],
              ),
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
        ),
      ),
    );
  }
}

class _OwnerPendingApprovalView extends ConsumerWidget {
  final OwnerMerchantModel merchant;
  final bool loading;

  const _OwnerPendingApprovalView({
    required this.merchant,
    required this.loading,
  });

  static const _supportPhone = '0780 000 0000';
  static const _supportWhatsApp = '0780 000 0000';

  String get _merchantTypeLabel =>
      merchant.type == 'restaurant' ? 'مطعم' : 'متجر';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    return Scaffold(
      drawer: AppUserDrawer(
        title: l10n.ownerDashboardTitle,
        subtitle: l10n.drawerOwnerPendingSub,
        showSettings: false,
        showProfileButton: false,
        showCommunitySection: false,
        items: [
          AppUserDrawerItem(
            icon: Icons.info_outline_rounded,
            label: l10n.drawerOwnerPendingStatus,
          ),
          AppUserDrawerItem(
            icon: Icons.refresh_rounded,
            label: l10n.drawerRefresh,
            onTap: (_) =>
                ref.read(ownerControllerProvider.notifier).bootstrap(),
          ),
        ],
      ),
      appBar: AppBar(title: Text(l10n.ownerApprovalPendingTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Icon(Icons.hourglass_top, size: 48),
                      const SizedBox(height: 12),
                      const Text(
                        'هذا المتجر بانتظار موافقة الأدمن',
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'سيصبح المتجر جاهزًا للعمل فور اعتماد الطلب. راجع البيانات التالية لحين الموافقة.',
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: Theme.of(context).colorScheme.surfaceContainer,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Text(
                              'اسم المتجر: ${merchant.name}',
                              textDirection: TextDirection.rtl,
                            ),
                            Text(
                              'النوع: $_merchantTypeLabel',
                              textDirection: TextDirection.rtl,
                            ),
                            if (merchant.phone?.isNotEmpty == true)
                              Text(
                                'رقم الهاتف: ${merchant.phone}',
                                textDirection: TextDirection.rtl,
                              ),
                            if (merchant.createdAt != null)
                              Text(
                                'تاريخ الإنشاء: ${merchant.createdAt!.toLocal()}',
                                textDirection: TextDirection.rtl,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'الدعم الفني',
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'الهاتف: $_supportPhone\nواتساب: $_supportWhatsApp',
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        alignment: WrapAlignment.center,
                        children: [
                          ElevatedButton.icon(
                            onPressed: loading
                                ? null
                                : () => ref
                                      .read(ownerControllerProvider.notifier)
                                      .bootstrap(),
                            icon: loading
                                ? const SizedBox(
                                    height: 16,
                                    width: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Icon(Icons.refresh),
                            label: const Text('تحديث الحالة'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                const ClipboardData(text: _supportPhone),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('تم نسخ الرقم')),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('نسخ الرقم'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OwnerFinancialTermsReviewView extends ConsumerWidget {
  final OwnerMerchantModel merchant;
  final bool loading;

  const _OwnerFinancialTermsReviewView({
    required this.merchant,
    required this.loading,
  });

  String _formatMoney(dynamic value) {
    final amount = value is num ? value : num.tryParse('${value ?? ''}') ?? 0;
    return formatIqd(amount);
  }

  String _deliveryModeLabel(String value) {
    switch (value) {
      case 'app_defined':
        return 'رسوم يحددها التطبيق لكل طلب';
      case 'store_defined':
        return 'رسوم ثابتة يحددها المتجر';
      default:
        return 'احتساب مرن حسب الإعدادات الحالية';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final terms = merchant.financialTermsSnapshot ?? const <String, dynamic>{};
    final commissionType = '${terms['commissionType'] ?? 'percentage'}';
    final commissionValue = terms['commissionValue'];
    final serviceFeeType = '${terms['serviceFeeType'] ?? 'fixed'}';
    final serviceFeeValue = terms['serviceFeeValue'];
    final deliveryFeeMode = '${terms['deliveryFeeMode'] ?? 'dynamic'}';
    final appDeliveryFeeValue = terms['appDeliveryFeeValue'];
    final storeDeliveryFeeValue = terms['storeDeliveryFeeValue'];

    return Scaffold(
      appBar: AppBar(title: const Text('الشروط المالية للمتجر')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: RefreshIndicator(
              onRefresh: () =>
                  ref.read(ownerControllerProvider.notifier).bootstrap(),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Icon(Icons.fact_check_outlined, size: 48),
                          const SizedBox(height: 12),
                          const Text(
                            'يرجى مراجعة الشروط المالية بعناية',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'هذه الشروط تضبط العمولة ورسوم الخدمة والتوصيل الخاصة بالمتجر. يجب اعتمادها قبل المتابعة.',
                            textAlign: TextAlign.center,
                            textDirection: TextDirection.rtl,
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 16),
                          _FinancialTermsTile(
                            title: 'نوع العمولة',
                            value: commissionType == 'fixed'
                                ? 'مبلغ ثابت'
                                : 'نسبة مئوية',
                          ),
                          _FinancialTermsTile(
                            title: 'قيمة العمولة',
                            value: commissionType == 'fixed'
                                ? _formatMoney(commissionValue)
                                : '${(commissionValue is num ? commissionValue : num.tryParse('${commissionValue ?? ''}') ?? 0).toStringAsFixed(2)}%',
                          ),
                          _FinancialTermsTile(
                            title: 'نوع رسم الخدمة',
                            value: serviceFeeType,
                          ),
                          _FinancialTermsTile(
                            title: 'قيمة رسم الخدمة',
                            value: _formatMoney(serviceFeeValue),
                          ),
                          _FinancialTermsTile(
                            title: 'وضع رسوم التوصيل',
                            value: _deliveryModeLabel(deliveryFeeMode),
                          ),
                          _FinancialTermsTile(
                            title: 'رسوم توصيل التطبيق',
                            value: _formatMoney(appDeliveryFeeValue),
                          ),
                          _FinancialTermsTile(
                            title: 'رسوم توصيل المتجر',
                            value: _formatMoney(storeDeliveryFeeValue),
                          ),
                          if (merchant.financialTermsSentAt != null)
                            _FinancialTermsTile(
                              title: 'أُرسلت في',
                              value: merchant.financialTermsSentAt!
                                  .toLocal()
                                  .toString(),
                            ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 10,
                            runSpacing: 10,
                            alignment: WrapAlignment.center,
                            children: [
                              ElevatedButton.icon(
                                onPressed: loading
                                    ? null
                                    : () async {
                                        final ok = await ref
                                            .read(
                                              ownerControllerProvider.notifier,
                                            )
                                            .acceptFinancialTerms();
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ok
                                                  ? 'تم اعتماد الشروط المالية بنجاح.'
                                                  : 'تعذر اعتماد الشروط المالية.',
                                            ),
                                          ),
                                        );
                                      },
                                icon: loading
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle_outline),
                                label: const Text('الموافقة على الشروط'),
                              ),
                              OutlinedButton.icon(
                                onPressed: loading
                                    ? null
                                    : () async {
                                        final ok = await ref
                                            .read(
                                              ownerControllerProvider.notifier,
                                            )
                                            .rejectFinancialTerms();
                                        if (!context.mounted) return;
                                        ScaffoldMessenger.of(
                                          context,
                                        ).showSnackBar(
                                          SnackBar(
                                            content: Text(
                                              ok
                                                  ? 'تم إرسال رفض الشروط المالية للمراجعة.'
                                                  : 'تعذر إرسال الرفض حاليًا.',
                                            ),
                                          ),
                                        );
                                      },
                                icon: const Icon(Icons.close),
                                label: const Text('رفض الشروط'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FinancialTermsTile extends StatelessWidget {
  final String title;
  final String value;

  const _FinancialTermsTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(
            context,
          ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                value,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReportStatItem {
  final String label;
  final String value;
  final Color accent;

  const _ReportStatItem({
    required this.label,
    required this.value,
    required this.accent,
  });
}

class _ReportStatCard extends StatelessWidget {
  final _ReportStatItem item;

  const _ReportStatCard({required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: item.accent.withValues(alpha: 0.12),
        border: Border.all(color: item.accent.withValues(alpha: 0.24)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.analytics_outlined, color: item.accent),
          const SizedBox(height: 10),
          Text(
            item.label,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            item.value,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
        ],
      ),
    );
  }
}

class _OwnerInsights extends StatelessWidget {
  final Map<String, dynamic> analytics;
  final Map<String, dynamic>? settlementSummary;
  final bool saving;
  final Future<void> Function({
    required String title,
    required List<String> lines,
    required String reportPeriod,
  })
  onOpenDetails;
  final Future<void> Function() onRequestSettlement;

  const _OwnerInsights({
    required this.analytics,
    required this.settlementSummary,
    required this.saving,
    required this.onOpenDetails,
    required this.onRequestSettlement,
  });

  @override
  Widget build(BuildContext context) {
    final day = _readPeriod(analytics['day']);
    final month = _readPeriod(analytics['month']);
    final allTime = _readPeriod(analytics['all']);
    final year = _readPeriod(analytics['year']);
    final reportAllTime = allTime.ordersCount > 0 ? allTime : year;

    final outstanding = _readNum(settlementSummary?['outstandingAmount']);
    final ordersCount = _readNum(settlementSummary?['ordersCount']).toInt();
    final pendingSettlement = settlementSummary?['pendingSettlement'];
    final hasPendingSettlement = pendingSettlement is Map;
    final blocksToday =
        (analytics['blocksToday'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    final topProductsToday =
        (analytics['topProductsToday'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];
    final statusToday =
        (analytics['statusToday'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .toList() ??
        const <Map<String, dynamic>>[];

    List<String> detailsForPeriod(String label, _Period period) {
      return [
        '$label:',
        'عدد الطلبات: ${period.ordersCount}',
        'رسوم التوصيل: ${formatIqd(period.deliveryFees)}',
      ];
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsightLine(
          'اليوم',
          '${day.ordersCount} طلب | التوصيل ${formatIqd(day.deliveryFees)}',
          onTap: () {
            final lines = [
              ...detailsForPeriod('تفاصيل اليوم', day),
              '',
              'حسب الحالة:',
              if (statusToday.isEmpty) 'لا توجد بيانات حالة اليوم',
              ...statusToday.map((row) {
                final status = '${row['status'] ?? '-'}';
                final count = _readNum(row['orders_count']).toInt();
                return '- $status: $count';
              }),
              '',
              'أكثر البلوكات طلبًا:',
              if (blocksToday.isEmpty) 'لا توجد بيانات بلوكات',
              ...blocksToday.take(5).map((row) {
                final block = '${row['customer_block'] ?? '-'}';
                final count = _readNum(row['orders_count']).toInt();
                return '- بلوك $block: $count طلب';
              }),
              '',
              'أكثر المنتجات طلبًا:',
              if (topProductsToday.isEmpty) 'لا توجد بيانات منتجات',
              ...topProductsToday.take(5).map((row) {
                final name = '${row['product_name'] ?? '-'}';
                final qty = _readNum(row['total_qty']).toInt();
                return '- $name: $qty';
              }),
            ];
            onOpenDetails(
              title: 'تفاصيل مؤشرات اليوم',
              lines: lines,
              reportPeriod: 'day',
            );
          },
        ),
        _InsightLine(
          'الشهر',
          '${month.ordersCount} طلب | التوصيل ${formatIqd(month.deliveryFees)}',
          onTap: () {
            onOpenDetails(
              title: 'تفاصيل مؤشرات الشهر',
              lines: detailsForPeriod('تفاصيل الشهر', month),
              reportPeriod: 'month',
            );
          },
        ),
        _InsightLine(
          'الإجمالي',
          '${reportAllTime.ordersCount} طلب | التوصيل ${formatIqd(reportAllTime.deliveryFees)}',
          onTap: () {
            onOpenDetails(
              title: 'تفاصيل المؤشرات الإجمالية',
              lines: detailsForPeriod('تفاصيل الإجمالي', reportAllTime),
              reportPeriod: 'all',
            );
          },
        ),
        const SizedBox(height: 6),
        _InsightLine(
          'المستحقات الحالية',
          '${formatIqd(outstanding)} ($ordersCount طلب)',
          onTap: () {
            onOpenDetails(
              title: 'تفاصيل المستحقات',
              lines: [
                'إجمالي المستحق الحالي: ${formatIqd(outstanding)}',
                'عدد الطلبات الداخلة في المستحقات: $ordersCount',
                if (hasPendingSettlement)
                  'يوجد طلب تسديد قيد المراجعة الآن'
                else
                  'لا يوجد طلب تسديد نشط',
              ],
              reportPeriod: 'all',
            );
          },
        ),
        const Text(
          'يمكنك إرسال طلب تسديد عندما يكون لديك رصيد مستحق قابل للصرف.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
        ),
        if (hasPendingSettlement)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'يوجد طلب تسديد مفتوح بالفعل.',
              textDirection: TextDirection.rtl,
            ),
          ),
        const SizedBox(height: 10),
        ElevatedButton(
          onPressed: saving || hasPendingSettlement || outstanding <= 0
              ? null
              : onRequestSettlement,
          child: saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('طلب تسديد المستحقات'),
        ),
      ],
    );
  }
}

class _InsightLine extends StatelessWidget {
  final String title;
  final String value;
  final VoidCallback? onTap;

  const _InsightLine(this.title, this.value, {this.onTap});

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(child: Text(value, textAlign: TextAlign.left)),
          Expanded(
            child: Row(
              children: [
                if (onTap != null)
                  const Icon(Icons.open_in_new_rounded, size: 14),
                if (onTap != null) const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    title,
                    textDirection: TextDirection.rtl,
                    textAlign: TextAlign.right,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onTap == null) return row;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: row,
    );
  }
}

_Period _readPeriod(dynamic raw) {
  if (raw is! Map) return const _Period();
  final map = Map<String, dynamic>.from(raw);
  return _Period(
    ordersCount: _readNum(map['orders_count']).toInt(),
    deliveryFees: _readNum(map['delivery_fees']),
  );
}

double _readNum(dynamic raw) {
  if (raw == null) return 0;
  if (raw is num) return raw.toDouble();
  return double.tryParse('$raw') ?? 0;
}

class _Period {
  final int ordersCount;
  final double deliveryFees;

  const _Period({this.ordersCount = 0, this.deliveryFees = 0});
}

class _SectionCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _SectionCard({required this.title, required this.child});

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
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              textAlign: TextAlign.right,
            ),
            const SizedBox(height: 10),
            Directionality(textDirection: TextDirection.rtl, child: child),
          ],
        ),
      ),
    );
  }
}

class _CategoryTile extends StatelessWidget {
  final ProductCategoryModel category;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const _CategoryTile({
    required this.category,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      title: Text(category.displayName, textDirection: TextDirection.rtl),
      subtitle: Text(
        'ترتيب العرض: ${category.sortOrder}',
        textDirection: TextDirection.rtl,
      ),
      trailing: Wrap(
        spacing: 4,
        children: [
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete)),
        ],
      ),
    );
  }
}

class _ProductTile extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback? onRestoreAvailability;

  const _ProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
    this.onRestoreAvailability,
  });

  @override
  Widget build(BuildContext context) {
    final effectivePrice = product.discountedPrice ?? product.price;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 6),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox(
          width: 52,
          height: 52,
          child: product.imageUrl?.isNotEmpty == true
              ? CachedAppImage(
                  imageUrl: product.imageUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (context, error, stackTrace) => Container(
                    color: Colors.white.withValues(alpha: 0.10),
                    alignment: Alignment.center,
                    child: const Icon(Icons.broken_image, size: 18),
                  ),
                )
              : Container(
                  color: Colors.white.withValues(alpha: 0.10),
                  alignment: Alignment.center,
                  child: const Icon(Icons.image, size: 18),
                ),
        ),
      ),
      title: Text(product.name, textDirection: TextDirection.rtl),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (product.categoryName?.isNotEmpty == true)
            Text(
              'القسم: ${product.categoryName}',
              textDirection: TextDirection.rtl,
            ),
          Text(
            product.hasDiscount
                ? 'السعر: ${formatIqd(product.price)} - بعد الخصم: ${formatIqd(effectivePrice)}'
                : 'السعر: ${formatIqd(effectivePrice)}',
            textDirection: TextDirection.rtl,
          ),
          if (!product.isAvailable &&
              product.unavailableReason?.trim().isNotEmpty == true)
            Text(
              product.unavailableReason!.trim(),
              textDirection: TextDirection.rtl,
              style: const TextStyle(fontSize: 12),
            ),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              if (product.freeDelivery)
                const _OfferChip(
                  icon: Icons.local_shipping_rounded,
                  text: 'توصيل مجاني',
                ),
              if (product.requiresPrescription)
                _OfferChip(
                  icon: Icons.receipt_long_outlined,
                  text: context.lt(
                    ar: 'وصفة مطلوبة',
                    en: 'Prescription required',
                  ),
                ),
              if (product.requiresReview)
                _OfferChip(
                  icon: Icons.medical_information_outlined,
                  text: context.lt(
                    ar: 'مراجعة صيدلانية',
                    en: 'Pharmacist review',
                  ),
                ),
              if (product.offerLabel?.trim().isNotEmpty == true)
                _OfferChip(
                  icon: Icons.local_offer_rounded,
                  text: product.offerLabel!.trim(),
                ),
            ],
          ),
        ],
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            product.isAvailable ? Icons.check_circle : Icons.remove_circle,
            color: product.isAvailable ? Colors.green : Colors.redAccent,
            size: 18,
          ),
          if (!product.isAvailable && onRestoreAvailability != null)
            IconButton(
              onPressed: onRestoreAvailability,
              tooltip: 'استعادة التوفر',
              icon: const Icon(Icons.restore),
            ),
          IconButton(onPressed: onEdit, icon: const Icon(Icons.edit)),
          IconButton(onPressed: onDelete, icon: const Icon(Icons.delete)),
        ],
      ),
    );
  }
}

class _OfferChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _OfferChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 12)),
        ],
      ),
    );
  }
}

class _InlineStateChip extends StatelessWidget {
  final String text;
  final Color color;

  const _InlineStateChip({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _CategoryFormSheet extends StatefulWidget {
  final ProductCategoryModel? category;
  final String merchantActivityType;

  const _CategoryFormSheet({this.category, required this.merchantActivityType});

  @override
  State<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends State<_CategoryFormSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController sortCtrl;
  late String catalogType;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.category?.name ?? '');
    sortCtrl = TextEditingController(
      text: widget.category?.sortOrder.toString() ?? '0',
    );
    final allowedTypes = allowedCatalogTypesForActivity(
      widget.merchantActivityType,
    );
    catalogType =
        widget.category?.catalogType ??
        (allowedTypes.isEmpty ? 'generic' : allowedTypes.first);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    sortCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.category != null;
    final allowedTypes = allowedCatalogTypesForActivity(
      widget.merchantActivityType,
    );
    final currentIsAllowed = isCatalogTypeAllowedForActivity(
      widget.merchantActivityType,
      catalogType,
    );
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              isEdit ? 'تعديل القسم' : 'إضافة قسم',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم القسم'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: currentIsAllowed ? catalogType : null,
              decoration: const InputDecoration(labelText: 'نوع كاتالوج القسم'),
              items: allowedTypes
                  .map(
                    (type) => DropdownMenuItem(
                      value: type,
                      child: Text(catalogTypeLabel(type)),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(
                () => catalogType =
                    value ??
                    (allowedTypes.isEmpty ? 'generic' : allowedTypes.first),
              ),
            ),
            if (!currentIsAllowed)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'نوع القسم الحالي لا يطابق نوع المتجر / Current section type does not match this store type.',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            const SizedBox(height: 10),
            TextField(
              controller: sortCtrl,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'ترتيب العرض'),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  if (nameCtrl.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('اسم القسم مطلوب')),
                    );
                    return;
                  }
                  if (!isCatalogTypeAllowedForActivity(
                    widget.merchantActivityType,
                    catalogType,
                  )) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'نوع القسم المختار لا يتوافق مع نوع المتجر / Selected section type does not match this store type.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    _CategoryFormData(
                      name: nameCtrl.text,
                      sortOrder: int.tryParse(sortCtrl.text.trim()) ?? 0,
                      catalogType: catalogType,
                    ),
                  );
                },
                child: Text(isEdit ? 'حفظ التعديلات' : 'إضافة القسم'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryFormData {
  final String name;
  final int sortOrder;
  final String catalogType;

  const _CategoryFormData({
    required this.name,
    required this.sortOrder,
    required this.catalogType,
  });
}

class _DeliveryAgentFormData {
  final String fullName;
  final String phone;
  final String pin;
  final LocalImageFile? imageFile;

  const _DeliveryAgentFormData({
    required this.fullName,
    required this.phone,
    required this.pin,
    required this.imageFile,
  });
}

class _DeliveryAgentFormSheet extends StatefulWidget {
  const _DeliveryAgentFormSheet();

  @override
  State<_DeliveryAgentFormSheet> createState() =>
      _DeliveryAgentFormSheetState();
}

class _DeliveryAgentFormSheetState extends State<_DeliveryAgentFormSheet> {
  late final TextEditingController _fullNameCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _pinCtrl;
  LocalImageFile? _imageFile;

  @override
  void initState() {
    super.initState();
    _fullNameCtrl = TextEditingController();
    _phoneCtrl = TextEditingController();
    _pinCtrl = TextEditingController();
    _imageFile = null;
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'إضافة مندوب توصيل',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _fullNameCtrl,
                decoration: const InputDecoration(labelText: 'الاسم الكامل'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'رقم الهاتف'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: context.localizedText(
                    ar: 'الرمز السري',
                    en: 'PIN',
                  ),
                ),
              ),
              const SizedBox(height: 10),
              ImagePickerField(
                title: 'صورة الملف (اختيارية)',
                selectedFile: _imageFile,
                existingImageUrl: null,
                onPick: () async {
                  final picked = await pickImageFromDevice();
                  if (!mounted || picked == null) return;
                  setState(() => _imageFile = picked);
                },
                onClear: _imageFile == null
                    ? null
                    : () => setState(() => _imageFile = null),
              ),
              const SizedBox(height: 12),
              ElevatedButton(
                onPressed: () {
                  final fullName = _fullNameCtrl.text.trim();
                  final phone = _phoneCtrl.text.trim();
                  final pin = _pinCtrl.text.trim();
                  if (fullName.isEmpty || phone.isEmpty || pin.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'الاسم الكامل ورقم الهاتف والرمز السري مطلوبة.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    _DeliveryAgentFormData(
                      fullName: fullName,
                      phone: phone,
                      pin: pin,
                      imageFile: _imageFile,
                    ),
                  );
                },
                child: const Text('إنشاء المندوب'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _OwnerStaffRole { delivery, accountant, hr }

class _AddStaffUserSheet extends ConsumerStatefulWidget {
  const _AddStaffUserSheet();

  @override
  ConsumerState<_AddStaffUserSheet> createState() => _AddStaffUserSheetState();
}

class _AddStaffUserSheetState extends ConsumerState<_AddStaffUserSheet> {
  final TextEditingController _fullNameCtrl = TextEditingController();
  final TextEditingController _phoneCtrl = TextEditingController();
  final TextEditingController _pinCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();

  _OwnerStaffRole _role = _OwnerStaffRole.delivery;
  bool _createNewUser = true;
  LocalImageFile? _imageFile;
  bool _searching = false;
  int? _selectedUserId;
  List<Map<String, dynamic>> _searchResults = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_searchUsers);
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _tr(String ar, String en) => context.localizedText(ar: ar, en: en);

  String _roleLabel() => _role == _OwnerStaffRole.delivery
      ? _tr('مندوب توصيل', 'Delivery Agent')
      : _role == _OwnerStaffRole.accountant
      ? _tr('محاسب', 'Accountant')
      : _tr('موظف موارد بشرية', 'HR Staff');

  String _roleLabelFromCode(String roleCode) {
    switch (roleCode.trim().toLowerCase()) {
      case 'delivery':
        return _tr('مندوب توصيل', 'Delivery Agent');
      case 'accountant':
        return _tr('محاسب', 'Accountant');
      case 'hr':
        return _tr('موظف موارد بشرية', 'HR Staff');
      case 'owner':
        return _tr('مالك المتجر', 'Store Owner');
      case 'admin':
        return _tr('أدمن', 'Admin');
      case 'deputy_admin':
        return _tr('نائب الأدمن', 'Deputy Admin');
      case 'call_center':
        return _tr('خدمة العملاء', 'Call Center');
      case 'user':
        return _tr('مستخدم', 'User');
      default:
        return roleCode;
    }
  }

  bool _isEligibleCandidate(Map<String, dynamic> row) {
    if (row['isTaxiCaptain'] == true) return false;
    final role = '${row['role'] ?? ''}'.toLowerCase();
    if (role == 'owner' ||
        role == 'admin' ||
        role == 'deputy_admin' ||
        role == 'call_center') {
      return false;
    }
    if (_role == _OwnerStaffRole.delivery && role == 'accountant') {
      return false;
    }
    if (_role == _OwnerStaffRole.delivery && role == 'hr') {
      return false;
    }
    return true;
  }

  Future<void> _searchUsers() async {
    setState(() => _searching = true);
    try {
      final rows = await ref
          .read(ownerControllerProvider.notifier)
          .searchStaffUsers(search: _searchCtrl.text.trim(), limit: 100);
      if (!mounted) return;
      setState(() {
        _searchResults = rows;
        _searching = false;
        if (_selectedUserId != null &&
            !_searchResults.any((row) => row['id'] == _selectedUserId)) {
          _selectedUserId = null;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _searching = false);
    }
  }

  Future<void> _submit() async {
    final owner = ref.read(ownerControllerProvider.notifier);
    var ok = false;

    if (_createNewUser) {
      final fullName = _fullNameCtrl.text.trim();
      final phone = _phoneCtrl.text.trim();
      final pin = _pinCtrl.text.trim();
      if (fullName.isEmpty || phone.isEmpty || pin.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'الاسم الكامل ورقم الهاتف والرمز السري مطلوبة.',
                'Full name, phone number, and PIN are required.',
              ),
            ),
          ),
        );
        return;
      }
      if (_role == _OwnerStaffRole.delivery) {
        ok = await owner.createDeliveryAgent(
          fullName: fullName,
          phone: phone,
          pin: pin,
          imageFile: _imageFile,
        );
      } else if (_role == _OwnerStaffRole.accountant) {
        ok = await owner.createAccountant(
          fullName: fullName,
          phone: phone,
          pin: pin,
          imageFile: _imageFile,
        );
      } else {
        ok = await owner.createHrStaff(
          fullName: fullName,
          phone: phone,
          pin: pin,
          imageFile: _imageFile,
        );
      }
    } else {
      final userId = _selectedUserId;
      if (userId == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _tr(
                'اختر مستخدمًا موجودًا أولًا.',
                'Select an existing user first.',
              ),
            ),
          ),
        );
        return;
      }
      if (_role == _OwnerStaffRole.delivery) {
        ok = await owner.assignExistingDeliveryAgent(userId: userId);
      } else if (_role == _OwnerStaffRole.accountant) {
        ok = await owner.assignExistingAccountant(userId: userId);
      } else {
        ok = await owner.assignExistingHrStaff(userId: userId);
      }
    }

    if (!mounted || !ok) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _createNewUser
              ? _tr(
                  'تم إنشاء حساب ${_roleLabel()} وربطه بالمتجر.',
                  '${_roleLabel()} account created and linked to store.',
                )
              : _tr(
                  'تم ربط المستخدم الحالي كـ ${_roleLabel()}.',
                  'Existing user linked as ${_roleLabel()}.',
                ),
        ),
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final ownerState = ref.watch(ownerControllerProvider);

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: SafeArea(
        child: Directionality(
          textDirection: context.appTextDirection,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  _tr('إدارة فريق المتجر', 'Store Staff Management'),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _tr(
                    'دور كابتن التكسي مستقل ولا يمكن تعيينه من هذه الشاشة.',
                    'Taxi captain role is separate and cannot be assigned here.',
                  ),
                  style: const TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<_OwnerStaffRole>(
                  initialValue: _role,
                  decoration: InputDecoration(labelText: _tr('الدور', 'Role')),
                  items: [
                    DropdownMenuItem(
                      value: _OwnerStaffRole.delivery,
                      child: Text(_tr('مندوب توصيل', 'Delivery Agent')),
                    ),
                    DropdownMenuItem(
                      value: _OwnerStaffRole.accountant,
                      child: Text(_tr('محاسب', 'Accountant')),
                    ),
                    DropdownMenuItem(
                      value: _OwnerStaffRole.hr,
                      child: Text(_tr('موظف موارد بشرية', 'HR Staff')),
                    ),
                  ],
                  onChanged: ownerState.savingOrder
                      ? null
                      : (value) {
                          if (value == null) return;
                          setState(() {
                            _role = value;
                            _selectedUserId = null;
                          });
                        },
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(_tr('إنشاء مستخدم جديد', 'Create New User')),
                      selected: _createNewUser,
                      onSelected: ownerState.savingOrder
                          ? null
                          : (_) => setState(() => _createNewUser = true),
                    ),
                    ChoiceChip(
                      label: Text(
                        _tr('ربط مستخدم موجود', 'Assign Existing User'),
                      ),
                      selected: !_createNewUser,
                      onSelected: ownerState.savingOrder
                          ? null
                          : (_) => setState(() => _createNewUser = false),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                if (_createNewUser) ...[
                  TextField(
                    controller: _fullNameCtrl,
                    decoration: InputDecoration(
                      labelText: _tr('الاسم الكامل', 'Full Name'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: _tr('رقم الهاتف', 'Phone Number'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _pinCtrl,
                    keyboardType: TextInputType.number,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: _tr('الرمز السري', 'PIN'),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ImagePickerField(
                    title: _tr(
                      'صورة الملف (اختيارية)',
                      'Profile image (optional)',
                    ),
                    selectedFile: _imageFile,
                    existingImageUrl: null,
                    onPick: () async {
                      final picked = await pickImageFromDevice();
                      if (!mounted || picked == null) return;
                      setState(() => _imageFile = picked);
                    },
                    onClear: _imageFile == null
                        ? null
                        : () => setState(() => _imageFile = null),
                  ),
                ] else ...[
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          onSubmitted: (_) => _searchUsers(),
                          decoration: InputDecoration(
                            labelText: _tr(
                              'بحث بالاسم أو الهاتف',
                              'Search by name or phone',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: ownerState.savingOrder || _searching
                            ? null
                            : _searchUsers,
                        child: _searching
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : Text(_tr('بحث', 'Search')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 260),
                    child: _searching
                        ? const Center(child: CircularProgressIndicator())
                        : _searchResults.isEmpty
                        ? Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              _tr('لا توجد نتائج.', 'No users found.'),
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            itemCount: _searchResults.length,
                            separatorBuilder: (_, _) =>
                                const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final row = _searchResults[index];
                              final userId = int.tryParse('${row['id']}') ?? 0;
                              final eligible = _isEligibleCandidate(row);
                              final isSelected = _selectedUserId == userId;
                              final subtitleParts = <String>[
                                '${row['phone'] ?? ''}',
                                '${_tr('\u0627\u0644\u062f\u0648\u0631', 'Role')}: ${_roleLabelFromCode('${row['role'] ?? ''}')}',
                                if (row['isTaxiCaptain'] == true)
                                  _tr('كابتن تكسي', 'Taxi Captain'),
                              ]..removeWhere((value) => value.trim().isEmpty);
                              return ListTile(
                                enabled: eligible && !ownerState.savingOrder,
                                onTap: !eligible || ownerState.savingOrder
                                    ? null
                                    : () => setState(
                                        () => _selectedUserId = userId,
                                      ),
                                title: Text('${row['fullName'] ?? '-'}'),
                                subtitle: Text(subtitleParts.join(' | ')),
                                dense: true,
                                trailing: Icon(
                                  !eligible
                                      ? Icons.block_rounded
                                      : isSelected
                                      ? Icons.radio_button_checked_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  color: !eligible
                                      ? Colors.redAccent
                                      : isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                ],
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: ownerState.savingOrder ? null : _submit,
                  icon: ownerState.savingOrder
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(
                    _createNewUser
                        ? _tr('إنشاء ${_roleLabel()}', 'Create ${_roleLabel()}')
                        : _tr(
                            'ربط المستخدم الحالي كـ ${_roleLabel()}',
                            'Assign existing as ${_roleLabel()}',
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
}
