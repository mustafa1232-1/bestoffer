import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../../core/widgets/desktop_dashboard_frame.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../notifications/ui/notifications_screen.dart';
import '../models/admin_financial_kpi_model.dart';
import '../models/admin_orders_overview_model.dart';
import '../state/admin_controller.dart';
import 'admin_advanced_tools_hub_screen.dart';
import 'admin_create_employee_screen.dart';
import 'admin_referral_coupons_screen.dart';
import 'admin_audit_security_center_screen.dart';
import 'admin_approvals_hub_screen.dart';
import 'admin_ad_board_screen.dart';
import 'admin_audit_log_screen.dart';
import 'admin_support_settings_screen.dart';
import 'admin_employees_screen.dart';
import 'admin_payroll_screen.dart';
import 'command_center_screen.dart';
import '../../guides/ui/app_guide_screen.dart';
import 'admin_companies_screen.dart';
import 'admin_competitions_screen.dart';
import 'admin_crash_error_center_screen.dart';
import 'admin_customer_profiles_screen.dart';
import 'admin_customer_reliability_policy_screen.dart';
import 'admin_device_reliability_screen.dart';
import 'admin_feature_flags_center_screen.dart';
import 'admin_financial_reports_hub_screen.dart';
import 'admin_maintenance_screen.dart';
import 'admin_merchant_approvals_screen.dart';
import 'admin_merchant_state_management_screen.dart';
import 'admin_notification_center_screen.dart';
import 'admin_notifications_operations_screen.dart';
import 'admin_orders_overview_screen.dart';
import 'admin_permissions_matrix_screen.dart';
import 'admin_rbac_management_screen.dart';
import 'admin_receivables_screen.dart';
import 'admin_residence_change_requests_screen.dart';
import 'admin_service_provider_applications_screen.dart';
import 'admin_services_hub_screen.dart';
import 'admin_social_reports_screen.dart';
import 'admin_social_restrictions_screen.dart';
import 'admin_social_users_screen.dart';
import 'admin_section_availability_screen.dart';
import 'admin_support_tickets_screen.dart';
import 'admin_taxi_captain_requests_screen.dart';
import 'admin_taxi_cash_payments_screen.dart';
import 'admin_taxi_governance_screen.dart';
import '../../paid_upgrades/ui/admin_paid_upgrade_requests_screen.dart';
import '../../coupons/ui/coupon_management_screen.dart';
import '../../real_estate/ui/admin_real_estate_pending_screen.dart';
import '../../ai_dev_support/screens/ai_dev_support_dashboard_screen.dart';

/// Ù„ÙˆØ­Ø© Ø§Ù„Ø£Ø¯Ù…Ù† Ø§Ù„Ø±Ø¦ÙŠØ³ÙŠØ© Ø§Ù„ØªÙŠ ØªØ¬Ù…Ø¹ KPIs ÙˆØ§Ù„Ù…ÙˆØ§ÙÙ‚Ø§Øª ÙˆØ§Ù„ØªÙ†Ù‚Ù„ Ø¥Ù„Ù‰ Ø§Ù„Ø£Ø¯ÙˆØ§Øª
/// Ø§Ù„Ø«Ø§Ù†ÙˆÙŠØ© Ù…Ù† Ù†Ù‚Ø·Ø© Ø¯Ø®ÙˆÙ„ ÙˆØ§Ø­Ø¯Ø©.
class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() =>
      _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> {
  static const AdminOrdersOverviewSummary _emptyOrdersSummary =
      AdminOrdersOverviewSummary(
        totalOrders: 0,
        completedOrders: 0,
        cancelledOrders: 0,
        inProgressOrders: 0,
      );

  bool _headlineLoading = true;
  bool _periodLoading = true;
  String? _headlineError;
  String? _periodError;
  String _period = 'day';
  DateTimeRange? _customRange;
  AdminOrdersOverviewSummary _allTimeOrders = _emptyOrdersSummary;
  AdminOrdersOverviewSummary _periodOrders = _emptyOrdersSummary;
  AdminFinancialKpiModel _periodFinancial = const AdminFinancialKpiModel(
    window: AdminFinancialKpiWindow(period: 'day'),
    totals: AdminFinancialKpiTotals(
      totalSales: 0,
      totalCommission: 0,
      totalServiceFees: 0,
      totalAppDeliveryFees: 0,
      totalStoreDeliveryFees: 0,
      totalAppDue: 0,
      totalStoreNetSales: 0,
      totalCollected: 0,
      netReceivables: 0,
      outstandingToCollect: 0,
      totalSalesOrders: 0,
      totalCollectionOperations: 0,
      currency: 'IQD',
    ),
  );
  Set<String> _effectiveAdminPermissions = const <String>{};
  bool _effectiveAdminWildcard = false;

  /// ÙŠØ­Ù…Ù„ snapshot Ø§Ù„Ø¨Ø¯Ø§ÙŠØ© Ù…Ù† `AdminController` Ø«Ù… ÙŠØ·Ù„Ø¨ summaries Ø§Ù„Ø¥Ø¶Ø§ÙÙŠØ©
  /// Ø§Ù„Ø®Ø§ØµØ© Ø¨Ø§Ù„Ø¹Ù†Ø§ÙˆÙŠÙ† Ø§Ù„Ø¹Ù„ÙŠØ§ ÙˆØ§Ù„ÙØªØ±Ø© Ø§Ù„Ù…Ø®ØªØ§Ø±Ø©.
  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  /// bootstrap Ø§Ù„Ù…ÙˆØ­Ø¯ Ù„Ù„Ø´Ø§Ø´Ø©. ÙŠÙØµÙ„ Ø¨ÙŠÙ† state Ø§Ù„Ø£Ø¯Ù…Ù† Ø§Ù„Ø¹Ø§Ù…Ø© ÙˆØ¨ÙŠÙ† summaries
  /// Ø§Ù„Ù…Ø­Ù„ÙŠØ© Ø§Ù„Ù…Ø¹ØªÙ…Ø¯Ø© Ø¹Ù„Ù‰ ÙÙ„Ø§ØªØ± Ø§Ù„ÙØªØ±Ø©.
  Future<void> _bootstrap() async {
    await ref.read(adminControllerProvider.notifier).bootstrap();
    await Future.wait([
      _loadMyPermissions(),
      _loadHeadlineSummary(),
      _loadPeriodSummary(),
    ]);
  }

  Future<void> _loadMyPermissions() async {
    try {
      final raw = await ref.read(adminApiProvider).myPermissions();
      final permissions =
          List<dynamic>.from(raw['permissions'] as List? ?? const [])
              .whereType<Map>()
              .map((item) => '${item['key'] ?? ''}'.trim())
              .where((item) => item.isNotEmpty)
              .toSet();
      if (!mounted) return;
      setState(() {
        _effectiveAdminWildcard = raw['wildcard'] == true;
        _effectiveAdminPermissions = permissions;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _effectiveAdminWildcard = false;
        _effectiveAdminPermissions = const <String>{};
      });
    }
  }

  bool _isTransientSummaryError(Object error) {
    if (error is! DioException) return false;
    final statusCode = error.response?.statusCode;
    if (statusCode == 401 || statusCode == 403 || statusCode == 408) {
      return true;
    }
    final data = error.response?.data;
    if (data is Map) {
      final message = '${data['message'] ?? data['error'] ?? ''}'
          .trim()
          .toUpperCase();
      return message.contains('INVALID_TOKEN') ||
          message.contains('TOKEN_EXPIRED') ||
          message.contains('UNAUTHORIZED');
    }
    return false;
  }

  Future<Map<String, dynamic>?> _loadOrdersOverviewSnapshot({
    required String status,
    required String period,
    String? from,
    String? to,
  }) async {
    final api = ref.read(adminApiProvider);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await api.ordersOverview(
          status: status,
          period: period,
          from: from,
          to: to,
        );
      } on DioException catch (error) {
        if (attempt == 0 && _isTransientSummaryError(error)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<Map<String, dynamic>?> _loadFinancialSnapshot({
    required String period,
    String? from,
    String? to,
  }) async {
    final api = ref.read(adminApiProvider);
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        return await api.adminFinancialKpis(period: period, from: from, to: to);
      } on DioException catch (error) {
        if (attempt == 0 && _isTransientSummaryError(error)) {
          await Future<void>.delayed(const Duration(milliseconds: 250));
          continue;
        }
        return null;
      } catch (_) {
        return null;
      }
    }
    return null;
  }

  Future<void> _refreshAll() async {
    await _bootstrap();
  }

  /// ÙŠØ­Ù…Ù„ Ù…Ø¤Ø´Ø±Ø§Øª all-time Ø§Ù„Ø³Ø±ÙŠØ¹Ø© Ø§Ù„ØªÙŠ ØªØ¸Ù‡Ø± ÙÙŠ Ø£Ø¹Ù„Ù‰ Ø§Ù„Ø´Ø§Ø´Ø©.
  Future<void> _loadHeadlineSummary() async {
    setState(() {
      _headlineLoading = true;
      _headlineError = null;
    });
    try {
      final raw = await _loadOrdersOverviewSnapshot(
        status: 'all',
        period: 'all',
      );
      final summary = raw == null
          ? _emptyOrdersSummary
          : AdminOrdersOverviewSummary.fromJson(_asMap(raw['summary']));
      if (!mounted) return;
      setState(() {
        _allTimeOrders = summary;
        _headlineLoading = false;
        _headlineError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _headlineLoading = false;
        _allTimeOrders = _emptyOrdersSummary;
        _headlineError = null;
      });
    }
  }

  /// ÙŠØ­Ù…Ù„ Ù…Ø¤Ø´Ø±Ø§Øª Ø§Ù„ÙØªØ±Ø© Ø§Ù„Ø­Ø§Ù„ÙŠØ© Ø¨Ù…Ø§ ÙÙŠÙ‡Ø§ Ø§Ù„Ø£ÙˆØ§Ù…Ø± ÙˆØ§Ù„Ù…Ø§Ù„ÙŠØ§Øª.
  ///
  /// Maintenance notes:
  /// - Ø¹Ù†Ø¯ Ø§Ø®ØªÙ„Ø§Ù Ø£Ø±Ù‚Ø§Ù… period cards Ø¹Ù† Ø§Ù„ØªÙ‚Ø§Ø±ÙŠØ±ØŒ Ø§Ø¨Ø¯Ø£ Ù…Ù† Ù‡Ø°Ù‡ Ø§Ù„Ø¯Ø§Ù„Ø© Ø«Ù…
  ///   Ø±Ø§Ø¬Ø¹ endpointÙŠ `ordersOverview` Ùˆ`adminFinancialKpis`.
  Future<void> _loadPeriodSummary() async {
    setState(() {
      _periodLoading = true;
      _periodError = null;
    });
    try {
      final from = _customRange?.start.toIso8601String();
      final to = _customRange?.end.toIso8601String();
      final results = await Future.wait<dynamic>([
        _loadOrdersOverviewSnapshot(
          status: 'all',
          period: _period,
          from: from,
          to: to,
        ),
        _loadFinancialSnapshot(period: _period, from: from, to: to),
      ]);
      final orderSummary = results[0] == null
          ? _periodOrders
          : AdminOrdersOverviewSummary.fromJson(
              _asMap(_asMap(results[0])['summary']),
            );
      final financial = results[1] == null
          ? _periodFinancial
          : AdminFinancialKpiModel.fromJson(_asMap(results[1]));
      if (!mounted) return;
      setState(() {
        _periodOrders = orderSummary;
        _periodFinancial = financial;
        _periodLoading = false;
        _periodError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _periodLoading = false;
        _periodError = null;
      });
    }
  }

  Map<String, dynamic> _asMap(dynamic raw) {
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) {
      return raw.map(
        (key, value) => MapEntry<String, dynamic>(key.toString(), value),
      );
    }
    return const <String, dynamic>{};
  }

  AdminFinancialKpiModel _allTimeFinancial(AdminState state) {
    final raw = _asMap(state.adminFinancialKpisV3);
    if (raw.isNotEmpty) {
      return AdminFinancialKpiModel.fromJson(raw);
    }
    return const AdminFinancialKpiModel(
      window: AdminFinancialKpiWindow(period: 'all'),
      totals: AdminFinancialKpiTotals(
        totalSales: 0,
        totalCommission: 0,
        totalServiceFees: 0,
        totalAppDeliveryFees: 0,
        totalStoreDeliveryFees: 0,
        totalAppDue: 0,
        totalStoreNetSales: 0,
        totalCollected: 0,
        netReceivables: 0,
        outstandingToCollect: 0,
        totalSalesOrders: 0,
        totalCollectionOperations: 0,
        currency: 'IQD',
      ),
    );
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _customRange,
    );
    if (range == null) return;
    setState(() {
      _period = 'custom';
      _customRange = range;
    });
    await _loadPeriodSummary();
  }

  Future<void> _setPeriod(String value) async {
    setState(() {
      _period = value;
      if (value != 'custom') {
        _customRange = null;
      }
    });
    await _loadPeriodSummary();
  }

  Future<void> _openPage(Widget page) async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Future<void> _openOrders(String status, {String? title}) async {
    await _openPage(
      AdminOrdersOverviewScreen(initialStatus: status, initialTitle: title),
    );
  }

  String _count(int value) {
    final digits = value.abs().toString();
    final out = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      out.write(digits[i]);
      final remaining = digits.length - i - 1;
      if (remaining > 0 && remaining % 3 == 0) {
        out.write(',');
      }
    }
    return value < 0 ? '-${out.toString()}' : out.toString();
  }

  String _periodLabel() {
    final l10n = context.l10n;
    switch (_period) {
      case 'day':
        return l10n.adminDashboardToday;
      case 'week':
        return l10n.adminDashboardThisWeek;
      case 'month':
        return l10n.adminDashboardThisMonth;
      case 'year':
        return l10n.adminDashboardThisYear;
      case 'custom':
        if (_customRange == null) {
          return l10n.adminDashboardCustomRange;
        }
        return '${_customRange!.start.year}/${_customRange!.start.month}/${_customRange!.start.day} - ${_customRange!.end.year}/${_customRange!.end.month}/${_customRange!.end.day}';
      default:
        return l10n.adminDashboardCurrentWindow;
    }
  }

  @override
  /// ÙŠØ¨Ù†ÙŠ shell Ù„ÙˆØ­Ø© Ø§Ù„Ø£Ø¯Ù…Ù† ÙˆÙŠØµÙ„ drawer/cards/actions Ø¨Ø­Ø§Ù„Ø© Ø§Ù„Ø£Ø¯Ù…Ù† Ø§Ù„Ø­Ø§Ù„ÙŠØ©.
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final auth = ref.watch(authControllerProvider);
    bool canPermission(String permission) {
      return auth.isSuperAdmin ||
          _effectiveAdminWildcard ||
          _effectiveAdminPermissions.contains(permission);
    }

    bool canAny(List<String> permissions) => permissions.any(canPermission);

    final canManagePermissions = canPermission('employees.permissions.manage');
    final useDesktop = DesktopDashboardFrame.shouldUse(context);
    final allTimeFinancial = _allTimeFinancial(state);
    final isArabic = Localizations.localeOf(
      context,
    ).languageCode.toLowerCase().startsWith('ar');
    String navText({required String ar, required String en}) =>
        isArabic ? ar : en;
    final groupHome = l10n.adminDashboardGroupDashboard;
    final groupApprovals = l10n.adminDashboardGroupApprovals;
    final groupUsers = navText(ar: 'عمليات المستخدمين', en: 'User operations');
    final groupStores = navText(ar: 'عمليات المتاجر', en: 'Store operations');
    final groupCompanies = navText(
      ar: 'عمليات الشركات',
      en: 'Company operations',
    );
    final groupDeliveryTaxi = navText(
      ar: 'عمليات الدلفري والتكسي',
      en: 'Delivery & taxi',
    );
    final groupOrders = navText(
      ar: 'الطلبات والتشغيل',
      en: 'Orders & operations',
    );
    final groupFinance = l10n.adminDashboardGroupFinance;
    final groupReports = navText(
      ar: 'التقارير ومؤشرات الأداء',
      en: 'Reports & KPIs',
    );
    final groupMarketing = navText(
      ar: 'التسويق والحملات',
      en: 'Marketing & campaigns',
    );
    final groupSecurity = navText(
      ar: 'الصلاحيات والأمان',
      en: 'Permissions & security',
    );
    final groupAiOps = navText(ar: 'دعم الذكاء التشغيلي', en: 'AI DEV SUPPORT');
    final groupSystem = navText(
      ar: 'النظام والصيانة',
      en: 'System & maintenance',
    );

    ref.listen<AdminState>(adminControllerProvider, (previous, next) {
      if (!mounted) return;
      if (next.error != null && next.error != previous?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (next.success != null && next.success != previous?.success) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.success!)));
      }
    });

    final drawer = AppUserDrawer(
      embedded: useDesktop,
      title: l10n.adminDashboardControlPanelTitle,
      subtitle: auth.user?.fullName,
      showCommunitySection: false,
      enableItemSearch: true,
      enableGroupCollapse: true,
      searchHintText: navText(
        ar: 'ابحث في لوحة الإدارة',
        en: 'Search admin navigation',
      ),
      items: [
        if (canPermission('dashboard.command_center.view'))
          AppUserDrawerItem(
            icon: Icons.dashboard_customize_rounded,
            label: navText(ar: 'لوحة المتابعة', en: 'Command center'),
            subtitle: navText(
              ar: 'متابعة تشغيلية موحدة حسب صلاحياتك',
              en: 'Unified operational monitoring by your permissions',
            ),
            group: groupHome,
            onTap: (_) => _openPage(const CommandCenterScreen()),
          ),
        if (canPermission('employees.read'))
          AppUserDrawerItem(
            icon: Icons.badge_rounded,
            label: navText(ar: 'إدارة الموظفين', en: 'Employees'),
            subtitle: navText(
              ar: 'الموظفون والأقسام والرواتب والصلاحيات',
              en: 'Staff, departments, salaries and permissions',
            ),
            group: groupHome,
            onTap: (_) => _openPage(const AdminEmployeesScreen()),
          ),
        if (canPermission('employees.create'))
          AppUserDrawerItem(
            icon: Icons.person_add_alt_1_rounded,
            label: navText(ar: 'إنشاء حساب موظف', en: 'Create employee account'),
            subtitle: navText(
              ar: 'حساب موظف كامل بدوره وواجهته الخاصة',
              en: 'A full employee account with its own role and app',
            ),
            group: groupHome,
            onTap: (_) => _openPage(const AdminCreateEmployeeScreen()),
          ),
        if (canPermission('coupons.agents.manage'))
          AppUserDrawerItem(
            icon: Icons.badge_outlined,
            label: navText(ar: 'كوبونات الموظفين', en: 'Employee coupons'),
            subtitle: navText(
              ar: 'مراقبة كوبونات الإحالة حسب الموظفين وتعديل الخصم',
              en: 'Track referral coupons per employee and edit discounts',
            ),
            group: groupHome,
            onTap: (_) => _openPage(const AdminReferralCouponsScreen()),
          ),
        if (canAny(const [
          'payroll.prepare',
          'payroll.review',
          'payroll.approve',
          'payroll.release',
          'payroll.mark_paid',
        ]))
          AppUserDrawerItem(
            icon: Icons.payments_rounded,
            label: navText(ar: 'الرواتب', en: 'Payroll'),
            subtitle: navText(
              ar: 'دورات الرواتب: احتساب ومراجعة واعتماد وتسديد',
              en: 'Payroll runs: calculate, review, approve, pay',
            ),
            group: groupHome,
            onTap: (_) => _openPage(const AdminPayrollScreen()),
          ),
        if (auth.isSuperAdmin)
          AppUserDrawerItem(
            icon: Icons.space_dashboard_rounded,
            label: l10n.adminDashboardHome,
            subtitle: l10n.adminDashboardHomeDescription,
            group: groupHome,
            onTap: (_) async {},
          ),
        AppUserDrawerItem(
          icon: Icons.refresh_rounded,
          label: l10n.adminDashboardRefreshData,
          subtitle: l10n.adminDashboardRefreshDataDescription,
          group: groupHome,
          onTap: (_) => _refreshAll(),
        ),
        if (canPermission('orders.read'))
          AppUserDrawerItem(
            icon: Icons.receipt_long_rounded,
            label: l10n.adminOrdersOverviewTitleAllOrders,
            subtitle: l10n.adminDashboardAllOrdersHint,
            group: groupOrders,
            onTap: (_) => _openPage(const AdminOrdersOverviewScreen()),
          ),
        if (canAny(const [
          'merchants.approve',
          'taxi.captains.approve',
          'services.read',
        ]))
          AppUserDrawerItem(
            icon: Icons.verified_user_outlined,
            label: l10n.adminDashboardApprovalsHub,
            subtitle: l10n.adminDashboardApprovalsHubDescription,
            badgeCount:
                state.pendingMerchants.length +
                state.pendingDeliveryAccounts.length +
                state.pendingTaxiCaptainAccounts.length +
                state.pendingTaxiProfileEditRequests.length +
                state.pendingTaxiCashPayments.length +
                state.pendingServiceProviderApplications.length +
                state.pendingServiceOfferings.length,
            group: groupApprovals,
            onTap: (_) => _openPage(const AdminApprovalsHubScreen()),
          ),
        if (canPermission('merchants.approve'))
          AppUserDrawerItem(
            icon: Icons.storefront_outlined,
            label: l10n.adminDashboardMerchantApprovals,
            subtitle: l10n.adminDashboardMerchantApprovalsDescription,
            badgeCount: state.pendingMerchants.length,
            group: groupApprovals,
            onTap: (_) => _openPage(const AdminMerchantApprovalsScreen()),
          ),
        if (canPermission('residence.requests.manage'))
          AppUserDrawerItem(
            icon: Icons.home_work_outlined,
            label: l10n.adminDashboardResidenceChangeRequests,
            subtitle: l10n.adminDashboardResidenceChangeRequestsDescription,
            group: groupApprovals,
            onTap: (_) => _openPage(const AdminResidenceChangeRequestsScreen()),
          ),
        if (canPermission('services.read'))
          AppUserDrawerItem(
            icon: Icons.home_repair_service_outlined,
            label: 'إدارة الخدمات',
            subtitle: 'مراجعة مقدمي الخدمة والخدمات والتقارير والإعدادات',
            badgeCount: state.pendingServiceOfferings.length,
            group: groupApprovals,
            onTap: (_) => _openPage(const AdminServicesHubScreen()),
          ),
        if (canPermission('services.read'))
          AppUserDrawerItem(
            icon: Icons.home_repair_service_outlined,
            label: 'اشتراكات أصحاب الخدمة',
            subtitle: 'تسعير الاشتراك وتأكيد الاستلام النقدي',
            badgeCount: state.pendingServiceProviderApplications.length,
            group: groupApprovals,
            onTap: (_) =>
                _openPage(const AdminServiceProviderApplicationsScreen()),
          ),
        if (canPermission('taxi.captains.approve'))
          AppUserDrawerItem(
            icon: Icons.local_taxi_outlined,
            label: l10n.adminDashboardTaxiCaptainRequests,
            subtitle: l10n.adminDashboardTaxiCaptainRequestsDescription,
            badgeCount:
                state.pendingTaxiCaptainAccounts.length +
                state.pendingTaxiProfileEditRequests.length,
            group: groupDeliveryTaxi,
            onTap: (_) => _openPage(const AdminTaxiCaptainRequestsScreen()),
          ),
        if (canAny(const ['taxi.rides.read', 'taxi.captains.approve']))
          AppUserDrawerItem(
            icon: Icons.payments_outlined,
            label: l10n.adminDashboardCaptainSubscriptionPayments,
            subtitle: l10n.adminDashboardCaptainSubscriptionPaymentsDescription,
            badgeCount: state.pendingTaxiCashPayments.length,
            group: groupDeliveryTaxi,
            onTap: (_) => _openPage(const AdminTaxiCashPaymentsScreen()),
          ),
        if (canPermission('taxi.rides.read'))
          AppUserDrawerItem(
            icon: Icons.local_taxi_outlined,
            label: l10n.adminTaxiGovernanceTitle,
            subtitle: l10n.adminTaxiGovernanceSubtitle,
            group: groupDeliveryTaxi,
            onTap: (_) => _openPage(const AdminTaxiGovernanceScreen()),
          ),
        if (canPermission('paid_upgrades.manage'))
          AppUserDrawerItem(
            icon: Icons.workspace_premium_outlined,
            label: l10n.adminDashboardPaidUpgradeRequests,
            subtitle: l10n.adminDashboardPaidUpgradeRequestsDescription,
            group: groupApprovals,
            onTap: (_) => _openPage(const AdminPaidUpgradeRequestsScreen()),
          ),
        if (canAny(const ['real_estate.moderate', 'real_estate.read']))
          AppUserDrawerItem(
            icon: Icons.apartment_outlined,
            label: l10n.adminDashboardRealEstateModeration,
            subtitle: l10n.adminDashboardRealEstateModerationDescription,
            group: groupApprovals,
            onTap: (_) => _openPage(const AdminRealEstatePendingScreen()),
          ),
        if (canPermission('companies.manage'))
          AppUserDrawerItem(
            icon: Icons.business_outlined,
            label: l10n.adminCompaniesScreenTitle,
            subtitle: navText(
              ar: 'Companies, branches, and link requests',
              en: 'Companies, branches, and link requests',
            ),
            group: groupCompanies,
            onTap: (_) => _openPage(const AdminCompaniesScreen()),
          ),
        if (canPermission('merchants.approve'))
          AppUserDrawerItem(
            icon: Icons.manage_accounts_outlined,
            label: l10n.adminDashboardMerchantStatusManagement,
            subtitle: l10n.adminDashboardMerchantStatusManagementDescription,
            group: groupStores,
            onTap: (_) => _openPage(const AdminMerchantStateManagementScreen()),
          ),
        if (canAny(const ['community.users.read', 'accounts.suspend']))
          AppUserDrawerItem(
            icon: Icons.people_alt_outlined,
            label: l10n.adminDashboardCustomerProfiles,
            subtitle: l10n.adminDashboardCustomerProfilesDescription,
            group: groupUsers,
            onTap: (_) => _openPage(const AdminCustomerProfilesScreen()),
          ),
        if (canPermission('sections.availability.manage'))
          AppUserDrawerItem(
            icon: Icons.toggle_off_outlined,
            label: 'إتاحة الأقسام',
            subtitle: 'فتح وإغلاق الأقسام ورسائل الإتاحة للمستخدم',
            group: groupSystem,
            onTap: (_) => _openPage(const AdminSectionAvailabilityScreen()),
          ),
        if (canPermission('support.tickets.read'))
          AppUserDrawerItem(
            icon: Icons.support_agent_rounded,
            label: navText(ar: 'تذاكر الدعم', en: 'Support tickets'),
            subtitle: navText(
              ar: 'متابعة الشكاوى وتعديل الطلبات المرتبطة',
              en: 'Handle complaints and linked order amendments',
            ),
            group: groupOrders,
            onTap: (_) => _openPage(const AdminSupportTicketsScreen()),
          ),
        AppUserDrawerItem(
          icon: Icons.menu_book_rounded,
          label: navText(ar: 'دليل الاستخدام', en: 'Usage guide'),
          subtitle: navText(
            ar: 'دليل الإدارة حسب صلاحياتك',
            en: 'Admin guide filtered by your permissions',
          ),
          group: groupSystem,
          onTap: (_) => _openPage(const AppGuideScreen(appScope: 'admin')),
        ),
        if (canPermission('settings.support_phone.update'))
          AppUserDrawerItem(
            icon: Icons.support_agent_rounded,
            label: navText(ar: 'رقم الدعم المركزي', en: 'Central support number'),
            subtitle: navText(
              ar: 'رقم دعم واحد يصل كل التطبيقات دون تحديث',
              en: 'One support number reaching all apps without an update',
            ),
            group: groupSystem,
            onTap: (_) => _openPage(const AdminSupportSettingsScreen()),
          ),
        if (canPermission('audit.read'))
          AppUserDrawerItem(
            icon: Icons.rule_folder_outlined,
            label: l10n.adminDashboardAuditLog,
            subtitle: l10n.adminDashboardAuditLogDescription,
            group: groupSecurity,
            onTap: (_) => _openPage(const AdminAuditLogScreen()),
          ),
        if (canPermission('system.notifications.view'))
          AppUserDrawerItem(
            icon: Icons.notifications_active_outlined,
            label: l10n.adminOpsNotificationCenterTitle,
            subtitle: l10n.adminOpsNotificationCenterDescription,
            group: groupSystem,
            onTap: (_) => _openPage(const AdminNotificationCenterScreen()),
          ),
        if (canPermission('settings.guides.manage'))
          AppUserDrawerItem(
            icon: Icons.settings_input_antenna_outlined,
            label: l10n.adminOpsNotificationsOperationsTitle,
            subtitle: l10n.adminOpsNotificationsOperationsDescription,
            group: groupSystem,
            onTap: (_) => _openPage(const AdminNotificationsOperationsScreen()),
          ),
        if (canPermission('system.device_reliability.view'))
          AppUserDrawerItem(
            icon: Icons.devices_other_outlined,
            label: l10n.adminOpsDeviceReliabilityTitle,
            subtitle: l10n.adminOpsDeviceReliabilityDescription,
            group: groupSystem,
            onTap: (_) => _openPage(const AdminDeviceReliabilityScreen()),
          ),
        if (canPermission('system.crash_center.view'))
          AppUserDrawerItem(
            icon: Icons.bug_report_outlined,
            label: l10n.adminOpsCrashCenterTitle,
            subtitle: l10n.adminOpsCrashCenterDescription,
            group: groupSystem,
            onTap: (_) => _openPage(const AdminCrashErrorCenterScreen()),
          ),
        if (canPermission('audit.read'))
          AppUserDrawerItem(
            icon: Icons.shield_outlined,
            label: l10n.adminOpsAuditSecurityTitle,
            subtitle: l10n.adminOpsAuditSecurityDescription,
            group: groupSecurity,
            onTap: (_) => _openPage(const AdminAuditSecurityCenterScreen()),
          ),
        if (canPermission('system.feature_flags.manage'))
          AppUserDrawerItem(
            icon: Icons.toggle_on_outlined,
            label: l10n.adminOpsFeatureFlagsTitle,
            subtitle: l10n.adminOpsFeatureFlagsDescription,
            group: groupSecurity,
            onTap: (_) => _openPage(const AdminFeatureFlagsCenterScreen()),
          ),
        if (canManagePermissions)
          AppUserDrawerItem(
            icon: Icons.fact_check_outlined,
            label: l10n.adminOpsPermissionsMatrixTitle,
            subtitle: l10n.adminOpsPermissionsMatrixDescription,
            group: groupSecurity,
            onTap: (_) => _openPage(const AdminPermissionsMatrixScreen()),
          ),
        if (canManagePermissions)
          AppUserDrawerItem(
            icon: Icons.admin_panel_settings_outlined,
            label: navText(
              ar: 'إدارة الأدوار والصلاحيات',
              en: 'Roles & permissions',
            ),
            subtitle: navText(
              ar: 'أدوار مخصصة، صلاحيات فردية، وسجل تغييرات الصلاحيات',
              en: 'Custom roles, individual permissions, and change log',
            ),
            group: groupSecurity,
            onTap: (_) => _openPage(const AdminRbacManagementScreen()),
          ),
        if (auth.isSuperAdmin)
          AppUserDrawerItem(
            icon: Icons.memory_rounded,
            label: groupAiOps,
            subtitle: navText(
              ar: 'Incidents, approvals, code-fix requests, and observability',
              en: 'Incidents, approvals, code-fix requests, and observability',
            ),
            group: groupAiOps,
            onTap: (_) => _openPage(const AiDevSupportDashboardScreen()),
          ),
        if (canPermission('reports.export'))
          AppUserDrawerItem(
            icon: Icons.account_balance_wallet_outlined,
            label: l10n.adminDashboardMerchantReceivables,
            subtitle: l10n.adminDashboardMerchantReceivablesDescription,
            badgeCount: state.pendingSettlements.length,
            group: groupFinance,
            onTap: (_) => _openPage(const AdminReceivablesScreen()),
          ),
        if (canPermission('reports.export'))
          AppUserDrawerItem(
            icon: Icons.insert_chart_outlined_rounded,
            label: l10n.adminDashboardFinancialReports,
            subtitle: l10n.adminDashboardFinancialReportsDescription,
            group: groupReports,
            onTap: (_) => _openPage(const AdminFinancialReportsHubScreen()),
          ),
        if (canPermission('customer_reliability.manage'))
          AppUserDrawerItem(
            icon: Icons.verified_user_outlined,
            label: navText(
              ar: 'Customer reliability policy',
              en: 'Customer reliability policy',
            ),
            subtitle: navText(
              ar: 'Tune reliability risk scoring and warning thresholds',
              en: 'Tune reliability risk scoring and warning thresholds',
            ),
            group: groupUsers,
            onTap: (_) =>
                _openPage(const AdminCustomerReliabilityPolicyScreen()),
          ),
        if (canPermission('competitions.manage'))
          AppUserDrawerItem(
            icon: Icons.emoji_events_outlined,
            label: l10n.adminDashboardCourierCompetitions,
            group: groupMarketing,
            onTap: (_) => _openPage(const AdminCompetitionsScreen()),
          ),
        if (canPermission('community.posts.read'))
          AppUserDrawerItem(
            icon: Icons.report_gmailerrorred_outlined,
            label: l10n.adminDashboardReports,
            subtitle: l10n.adminDashboardReportsDescription,
            group: groupReports,
            onTap: (_) => _openPage(const AdminSocialReportsScreen()),
          ),
        if (canAny(const [
          'community.users.read',
          'accounts.suspend',
          'accounts.restrict',
        ]))
          AppUserDrawerItem(
            icon: Icons.manage_accounts_outlined,
            label: navText(
              ar: 'Social users moderation',
              en: 'Social users moderation',
            ),
            subtitle: navText(
              ar: 'Search, restrict, and disable user accounts',
              en: 'Search, restrict, and disable user accounts',
            ),
            group: groupUsers,
            onTap: (_) => _openPage(const AdminSocialUsersScreen()),
          ),
        if (canPermission('accounts.restrict'))
          AppUserDrawerItem(
            icon: Icons.gpp_bad_outlined,
            label: l10n.adminDashboardSocialRestrictions,
            subtitle: l10n.adminDashboardSocialRestrictionsDescription,
            group: groupUsers,
            onTap: (_) => _openPage(const AdminSocialRestrictionsScreen()),
          ),
        if (canPermission('ads.manage'))
          AppUserDrawerItem(
            icon: Icons.campaign_outlined,
            label: navText(ar: 'Ad board', en: 'Ad board'),
            subtitle: navText(
              ar: 'Manage in-app ad campaigns and placements',
              en: 'Manage in-app ad campaigns and placements',
            ),
            group: groupMarketing,
            onTap: (_) => _openPage(const AdminAdBoardScreen()),
          ),
        if (canPermission('coupons.manage'))
          AppUserDrawerItem(
            icon: Icons.confirmation_number_outlined,
            label: navText(ar: 'Coupons', en: 'Coupons'),
            subtitle: navText(
              ar: 'Create and manage platform coupons',
              en: 'Create and manage platform coupons',
            ),
            group: groupMarketing,
            onTap: (_) => _openPage(
              const CouponManagementScreen(mode: CouponManagerMode.superAdmin),
            ),
          ),
        if (canPermission('system.maintenance.manage'))
          AppUserDrawerItem(
            icon: Icons.home_repair_service_outlined,
            label: l10n.adminDashboardMaintenanceCenter,
            group: groupSystem,
            onTap: (_) => _openPage(const AdminMaintenanceScreen()),
          ),
        if (auth.isSuperAdmin)
          AppUserDrawerItem(
            icon: Icons.hub_outlined,
            label: l10n.adminDashboardAdvancedHub,
            subtitle: l10n.adminDashboardAdvancedHubDescription,
            group: groupSecurity,
            onTap: (_) => _openPage(const AdminAdvancedToolsHubScreen()),
          ),
      ],
    );

    final dashboardBody = _AdminDashboardBody(
      headlineLoading: _headlineLoading,
      headlineError: _headlineError,
      allTimeOrders: _allTimeOrders,
      allTimeFinancial: allTimeFinancial,
      periodLoading: _periodLoading,
      periodError: _periodError,
      periodOrders: _periodOrders,
      periodFinancial: _periodFinancial,
      period: _period,
      periodLabel: _periodLabel(),
      customRange: _customRange,
      pendingMerchantCount: state.pendingMerchants.length,
      pendingTaxiApprovalsCount: state.pendingTaxiCaptainAccounts.length,
      pendingTaxiEditsCount: state.pendingTaxiProfileEditRequests.length,
      pendingFinancialActionsCount:
          state.pendingSettlements.length +
          state.pendingTaxiCashPayments.length,
      countFormatter: _count,
      onRefresh: _refreshAll,
      onSelectPeriod: _setPeriod,
      onPickCustomRange: _pickCustomRange,
      onOpenAllOrders: () =>
          _openOrders('all', title: l10n.adminDashboardAllOrders),
      onOpenCompletedOrders: () =>
          _openOrders('completed', title: l10n.companyDashboardCompleted),
      onOpenCancelledOrders: () =>
          _openOrders('cancelled', title: l10n.companyDashboardCancelled),
      onOpenInProgressOrders: () => _openOrders(
        'in_progress',
        title: l10n.adminDashboardInProgressOrders,
      ),
      onOpenMerchantApprovals: () =>
          _openPage(const AdminMerchantApprovalsScreen()),
      onOpenTaxiApprovals: () =>
          _openPage(const AdminTaxiCaptainRequestsScreen(initialTabIndex: 0)),
      onOpenTaxiEdits: () =>
          _openPage(const AdminTaxiCaptainRequestsScreen(initialTabIndex: 1)),
      onOpenFinancialActions: () => _openPage(const AdminReceivablesScreen()),
      onOpenReceivables: () => _openPage(const AdminReceivablesScreen()),
      onOpenFinancialReports: () =>
          _openPage(const AdminFinancialReportsHubScreen()),
      onOpenNotifications: () => _openPage(const NotificationsScreen()),
      canOrders: canPermission('orders.read'),
      canFinance: canPermission('reports.export'),
      canMerchantApprovals: canPermission('merchants.approve'),
      canTaxiApprovals: canPermission('taxi.captains.approve'),
    );

    if (useDesktop) {
      return Scaffold(
        body: _AdminShellBackground(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: DesktopDashboardFrame(
                title: l10n.adminDashboardTitle,
                subtitle: l10n.adminDashboardDesktopSubtitle,
                statusLabel: l10n.adminDashboardLiveWorkspace,
                sidebar: drawer,
                quickActions: [
                  DesktopQuickActionButton(
                    icon: Icons.refresh_rounded,
                    label: l10n.commonRefresh,
                    onPressed: _refreshAll,
                  ),
                  if (canAny(const [
                    'merchants.approve',
                    'taxi.captains.approve',
                    'services.read',
                  ]))
                    DesktopQuickActionButton(
                      icon: Icons.verified_user_outlined,
                      label: l10n.adminDashboardApprovalsHub,
                      onPressed: () =>
                          _openPage(const AdminApprovalsHubScreen()),
                    ),
                  if (canPermission('reports.export'))
                    DesktopQuickActionButton(
                      icon: Icons.account_balance_wallet_outlined,
                      label: l10n.adminDashboardMerchantReceivables,
                      onPressed: () => _openPage(const AdminReceivablesScreen()),
                    ),
                  DesktopQuickActionButton(
                    icon: Icons.notifications_active_outlined,
                    label: l10n.notificationsTitle,
                    onPressed: () => _openPage(const NotificationsScreen()),
                  ),
                ],
                child: dashboardBody,
              ),
            ),
          ),
        ),
      );
    }

    return Scaffold(
      drawer: Drawer(child: drawer),
      appBar: AppBar(
        title: Text(l10n.adminDashboardTitle),
        actions: [
          const NotificationsBellButton(),
          IconButton(
            tooltip: l10n.commonRefresh,
            onPressed: _refreshAll,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _AdminShellBackground(child: dashboardBody),
    );
  }
}

class _AdminShellBackground extends StatelessWidget {
  final Widget child;

  const _AdminShellBackground({required this.child});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            scheme.surface,
            scheme.surfaceContainerHighest.withValues(alpha: 0.82),
            scheme.surface,
          ],
        ),
      ),
      child: Stack(
        children: [
          Positioned(
            top: -120,
            right: -80,
            child: _GlowOrb(
              size: 260,
              color: scheme.primary.withValues(alpha: 0.18),
            ),
          ),
          Positioned(
            bottom: -140,
            left: -90,
            child: _GlowOrb(
              size: 280,
              color: scheme.tertiary.withValues(alpha: 0.14),
            ),
          ),
          child,
        ],
      ),
    );
  }
}

class _AdminDashboardBody extends StatelessWidget {
  final bool headlineLoading;
  final String? headlineError;
  final AdminOrdersOverviewSummary allTimeOrders;
  final AdminFinancialKpiModel allTimeFinancial;
  final bool periodLoading;
  final String? periodError;
  final AdminOrdersOverviewSummary periodOrders;
  final AdminFinancialKpiModel periodFinancial;
  final String period;
  final String periodLabel;
  final DateTimeRange? customRange;
  final int pendingMerchantCount;
  final int pendingTaxiApprovalsCount;
  final int pendingTaxiEditsCount;
  final int pendingFinancialActionsCount;
  final String Function(int value) countFormatter;
  final Future<void> Function() onRefresh;
  final Future<void> Function(String period) onSelectPeriod;
  final Future<void> Function() onPickCustomRange;
  final VoidCallback onOpenAllOrders;
  final VoidCallback onOpenCompletedOrders;
  final VoidCallback onOpenCancelledOrders;
  final VoidCallback onOpenInProgressOrders;
  final VoidCallback onOpenMerchantApprovals;
  final VoidCallback onOpenTaxiApprovals;
  final VoidCallback onOpenTaxiEdits;
  final VoidCallback onOpenFinancialActions;
  final VoidCallback onOpenReceivables;
  final VoidCallback onOpenFinancialReports;
  final VoidCallback onOpenNotifications;
  // Permission gates — landing sections show only what the admin may act on.
  final bool canOrders;
  final bool canFinance;
  final bool canMerchantApprovals;
  final bool canTaxiApprovals;

  const _AdminDashboardBody({
    required this.headlineLoading,
    required this.headlineError,
    required this.allTimeOrders,
    required this.allTimeFinancial,
    required this.periodLoading,
    required this.periodError,
    required this.periodOrders,
    required this.periodFinancial,
    required this.period,
    required this.periodLabel,
    required this.customRange,
    required this.pendingMerchantCount,
    required this.pendingTaxiApprovalsCount,
    required this.pendingTaxiEditsCount,
    required this.pendingFinancialActionsCount,
    required this.countFormatter,
    required this.onRefresh,
    required this.onSelectPeriod,
    required this.onPickCustomRange,
    required this.onOpenAllOrders,
    required this.onOpenCompletedOrders,
    required this.onOpenCancelledOrders,
    required this.onOpenInProgressOrders,
    required this.onOpenMerchantApprovals,
    required this.onOpenTaxiApprovals,
    required this.onOpenTaxiEdits,
    required this.onOpenFinancialActions,
    required this.onOpenReceivables,
    required this.onOpenFinancialReports,
    required this.onOpenNotifications,
    required this.canOrders,
    required this.canFinance,
    required this.canMerchantApprovals,
    required this.canTaxiApprovals,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          _HeroPanel(
            title: l10n.adminDashboardDailyOperationsPulse,
            subtitle: l10n.adminDashboardDailyOperationsPulseDescription,
            chips: [
              _HeroChip(
                icon: Icons.notifications_active_outlined,
                label: l10n.notificationsTitle,
                value: l10n.adminDashboardLive,
                onTap: onOpenNotifications,
              ),
              if (canFinance)
                _HeroChip(
                  icon: Icons.account_balance_wallet_outlined,
                  label: l10n.adminDashboardMerchantReceivables,
                  value: formatIqd(allTimeFinancial.totals.totalAppDue),
                  onTap: onOpenReceivables,
                ),
              if (canFinance)
                _HeroChip(
                  icon: Icons.analytics_outlined,
                  label: l10n.adminDashboardReports,
                  value: periodLabel,
                  onTap: onOpenFinancialReports,
                ),
            ],
          ),
          const SizedBox(height: 18),
          _SectionHeader(
            title: l10n.adminDashboardOrdersPulse,
            subtitle: l10n.adminDashboardOrdersPulseDescription,
          ),
          const SizedBox(height: 12),
          if (headlineError != null)
            _StateBanner(message: headlineError!, isError: true)
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 760;
                final children = [
                  _ActionMetricCard(
                    icon: Icons.receipt_long_rounded,
                    title: l10n.adminDashboardAllOrders,
                    value: headlineLoading
                        ? '...'
                        : countFormatter(allTimeOrders.totalOrders),
                    hint: l10n.adminDashboardAllOrdersHint,
                    color: scheme.primary,
                    onTap: onOpenAllOrders,
                  ),
                  _ActionMetricCard(
                    icon: Icons.check_circle_outline_rounded,
                    title: l10n.companyDashboardCompleted,
                    value: headlineLoading
                        ? '...'
                        : countFormatter(allTimeOrders.completedOrders),
                    hint: l10n.adminDashboardCompletedOrdersHint,
                    color: const Color(0xFF34D399),
                    onTap: onOpenCompletedOrders,
                  ),
                  _ActionMetricCard(
                    icon: Icons.cancel_outlined,
                    title: l10n.companyDashboardCancelled,
                    value: headlineLoading
                        ? '...'
                        : countFormatter(allTimeOrders.cancelledOrders),
                    hint: l10n.adminDashboardCancelledOrdersHint,
                    color: const Color(0xFFFB7185),
                    onTap: onOpenCancelledOrders,
                  ),
                  _ActionMetricCard(
                    icon: Icons.delivery_dining_rounded,
                    title: l10n.adminDashboardInProgress,
                    value: headlineLoading
                        ? '...'
                        : countFormatter(allTimeOrders.inProgressOrders),
                    hint: l10n.adminDashboardInProgressHint,
                    color: const Color(0xFFFBBF24),
                    onTap: onOpenInProgressOrders,
                  ),
                ];
                if (compact) {
                  return Column(
                    children: [
                      for (final child in children) ...[
                        child,
                        const SizedBox(height: 12),
                      ],
                    ],
                  );
                }
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: children
                      .map(
                        (child) => SizedBox(
                          width: (constraints.maxWidth - 12) / 2,
                          child: child,
                        ),
                      )
                      .toList(growable: false),
                );
              },
            ),
          if (canMerchantApprovals || canTaxiApprovals) ...[
            const SizedBox(height: 22),
            _SectionHeader(
              title: l10n.adminDashboardCriticalApprovals,
              subtitle: l10n.adminDashboardCriticalApprovalsDescription,
              actionLabel: l10n.adminDashboardOpenApprovalsHub,
              onAction: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminApprovalsHubScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),
          ],
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 760;
              final items = [
                if (canMerchantApprovals)
                  _ApprovalCard(
                    icon: Icons.storefront_outlined,
                    title: l10n.adminDashboardPendingMerchants,
                    count: pendingMerchantCount,
                    description: l10n.adminDashboardPendingMerchantsDescription,
                    color: const Color(0xFFA78BFA),
                    onTap: onOpenMerchantApprovals,
                  ),
                if (canTaxiApprovals)
                  _ApprovalCard(
                    icon: Icons.local_taxi_outlined,
                    title: l10n.adminDashboardCaptainApprovals,
                    count: pendingTaxiApprovalsCount,
                    description: l10n.adminDashboardCaptainApprovalsDescription,
                    color: const Color(0xFF60A5FA),
                    onTap: onOpenTaxiApprovals,
                  ),
                if (canTaxiApprovals)
                  _ApprovalCard(
                    icon: Icons.edit_note_outlined,
                    title: l10n.adminDashboardProfileEdits,
                    count: pendingTaxiEditsCount,
                    description: l10n.adminDashboardProfileEditsDescription,
                    color: const Color(0xFF38BDF8),
                    onTap: onOpenTaxiEdits,
                  ),
                if (canMerchantApprovals || canTaxiApprovals)
                  _ApprovalCard(
                    icon: Icons.payments_outlined,
                    title: l10n.adminDashboardFinancialActions,
                    count: pendingFinancialActionsCount,
                    description: l10n.adminDashboardFinancialActionsDescription,
                    color: const Color(0xFFF59E0B),
                    onTap: onOpenFinancialActions,
                  ),
              ];
              if (compact) {
                return Column(
                  children: [
                    for (final item in items) ...[
                      item,
                      const SizedBox(height: 12),
                    ],
                  ],
                );
              }
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: items
                    .map(
                      (item) => SizedBox(
                        width: (constraints.maxWidth - 12) / 2,
                        child: item,
                      ),
                    )
                    .toList(growable: false),
              );
            },
          ),
          const SizedBox(height: 22),
          _SectionHeader(
            title: l10n.adminDashboardPeriodSummary,
            subtitle: l10n.adminDashboardPeriodSummaryDescription,
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final option in [
                        ('day', l10n.adminDashboardDay),
                        ('week', l10n.adminDashboardWeek),
                        ('month', l10n.adminDashboardMonth),
                        ('year', l10n.adminDashboardYear),
                      ])
                        ChoiceChip(
                          label: Text(option.$2),
                          selected: period == option.$1,
                          onSelected: (_) => onSelectPeriod(option.$1),
                        ),
                      ActionChip(
                        avatar: const Icon(Icons.date_range_rounded, size: 18),
                        label: Text(
                          customRange == null
                              ? l10n.adminDashboardCustomRange
                              : periodLabel,
                        ),
                        onPressed: onPickCustomRange,
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    l10n.adminDashboardSelectedWindow(periodLabel),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (periodError != null)
                    _StateBanner(message: periodError!, isError: true)
                  else if (periodLoading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 30),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final compact = constraints.maxWidth < 760;
                        final cards = [
                          _PeriodMetricCard(
                            icon: Icons.percent_rounded,
                            title: l10n.adminDashboardCommissions,
                            value: formatIqd(
                              periodFinancial.totals.totalCommission,
                            ),
                            note: l10n.adminDashboardCommissionsDescription,
                            color: scheme.primary,
                          ),
                          _PeriodMetricCard(
                            icon: Icons.receipt_rounded,
                            title: l10n.companyDashboardServiceFees,
                            value: formatIqd(
                              periodFinancial.totals.totalServiceFees,
                            ),
                            note: l10n.adminDashboardServiceFeesDescription,
                            color: const Color(0xFF8B5CF6),
                          ),
                          _PeriodMetricCard(
                            icon: Icons.local_shipping_outlined,
                            title: l10n.adminDashboardDelivery,
                            value: formatIqd(
                              periodFinancial.totals.totalAppDeliveryFees,
                            ),
                            note: l10n.adminDashboardDeliveryDescription,
                            color: const Color(0xFF22D3EE),
                          ),
                          _PeriodMetricCard(
                            icon: Icons.check_circle_outline_rounded,
                            title: l10n.companyDashboardCompleted,
                            value: countFormatter(periodOrders.completedOrders),
                            note: l10n.adminDashboardCompletedOrdersDescription,
                            color: const Color(0xFF34D399),
                          ),
                          _PeriodMetricCard(
                            icon: Icons.cancel_outlined,
                            title: l10n.companyDashboardCancelled,
                            value: countFormatter(periodOrders.cancelledOrders),
                            note: l10n.adminDashboardCancelledOrdersDescription,
                            color: const Color(0xFFFB7185),
                          ),
                          _PeriodMetricCard(
                            icon: Icons.timelapse_rounded,
                            title: l10n.adminDashboardInProgressOrders,
                            value: countFormatter(
                              periodOrders.inProgressOrders,
                            ),
                            note:
                                l10n.adminDashboardInProgressOrdersDescription,
                            color: const Color(0xFFFBBF24),
                          ),
                        ];
                        if (compact) {
                          return Column(
                            children: [
                              for (final card in cards) ...[
                                card,
                                const SizedBox(height: 12),
                              ],
                            ],
                          );
                        }
                        return Wrap(
                          spacing: 12,
                          runSpacing: 12,
                          children: cards
                              .map(
                                (card) => SizedBox(
                                  width: (constraints.maxWidth - 24) / 3,
                                  child: card,
                                ),
                              )
                              .toList(growable: false),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 22),
          _SectionHeader(
            title: l10n.adminDashboardFinancialShortcuts,
            subtitle: l10n.adminDashboardFinancialShortcutsDescription,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 320,
                child: _ShortcutTile(
                  icon: Icons.account_balance_wallet_outlined,
                  title: l10n.adminDashboardMerchantReceivables,
                  subtitle:
                      l10n.adminDashboardMerchantReceivablesShortcutDescription,
                  onTap: onOpenReceivables,
                ),
              ),
              SizedBox(
                width: 320,
                child: _ShortcutTile(
                  icon: Icons.insert_chart_outlined_rounded,
                  title: l10n.adminDashboardFinancialReports,
                  subtitle:
                      l10n.adminDashboardFinancialReportsShortcutDescription,
                  onTap: onOpenFinancialReports,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<_HeroChip> chips;

  const _HeroPanel({
    required this.title,
    required this.subtitle,
    required this.chips,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            scheme.primaryContainer.withValues(alpha: 0.84),
            scheme.secondaryContainer.withValues(alpha: 0.78),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(
                context,
              ).colorScheme.onSurface.withValues(alpha: 0.82),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          Wrap(spacing: 10, runSpacing: 10, children: chips),
        ],
      ),
    );
  }
}

class _HeroChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback onTap;

  const _HeroChip({
    required this.icon,
    required this.label,
    required this.value,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: Colors.white.withValues(alpha: 0.08),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      color: Theme.of(
                        context,
                      ).colorScheme.onSurface.withValues(alpha: 0.76),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _SectionHeader({
    required this.title,
    required this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
        if (actionLabel != null && onAction != null)
          TextButton(onPressed: onAction, child: Text(actionLabel!)),
      ],
    );
  }
}

class _ActionMetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String hint;
  final Color color;
  final VoidCallback onTap;

  const _ActionMetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.hint,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                color.withValues(alpha: 0.18),
                Theme.of(
                  context,
                ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 16),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                hint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ApprovalCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final int count;
  final String description;
  final Color color;
  final VoidCallback onTap;

  const _ApprovalCard({
    required this.icon,
    required this.title,
    required this.count,
    required this.description,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final hasItems = count > 0;
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(icon, color: color),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          (hasItems
                                  ? Theme.of(context).colorScheme.error
                                  : Theme.of(context).colorScheme.outline)
                              .withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      '$count',
                      style: TextStyle(
                        color: hasItems
                            ? Theme.of(context).colorScheme.error
                            : Theme.of(context).colorScheme.outline,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PeriodMetricCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final String note;
  final Color color;

  const _PeriodMetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.note,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.42),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 8),
          Text(
            note,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              height: 1.35,
            ),
          ),
        ],
      ),
    );
  }
}

class _ShortcutTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ShortcutTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.all(16),
        leading: CircleAvatar(child: Icon(icon)),
        title: Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(subtitle),
        ),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
        onTap: onTap,
      ),
    );
  }
}

class _StateBanner extends StatelessWidget {
  final String message;
  final bool isError;

  const _StateBanner({required this.message, this.isError = false});

  @override
  Widget build(BuildContext context) {
    final color = isError
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.primary;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: color.withValues(alpha: 0.14),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Text(
        message,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  final double size;
  final Color color;

  const _GlowOrb({required this.size, required this.color});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [color, color.withValues(alpha: 0.0)],
          ),
        ),
      ),
    );
  }
}
