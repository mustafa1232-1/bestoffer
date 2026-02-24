// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../core/utils/currency.dart';
import '../../../core/utils/order_status.dart';
import '../../../core/utils/report_printing.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../auth/state/auth_controller.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/models/order_model.dart';
import '../../products/models/product_category_model.dart';
import '../../products/models/product_model.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../settings/ui/pages/settings_support_screen.dart';
import '../models/owner_merchant_model.dart';
import '../state/owner_controller.dart';

enum _OwnerTab { dashboard, profile, store, orders, catalog }

class OwnerDashboardScreen extends ConsumerStatefulWidget {
  const OwnerDashboardScreen({super.key});

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final imageCtrl = TextEditingController();
  LocalImageFile? merchantImageFile;
  _OwnerTab activeTab = _OwnerTab.dashboard;

  String merchantType = 'restaurant';
  bool isOpen = true;
  int? merchantId;

  final Map<int, int> selectedDeliveryByOrder = {};

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(ownerControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    phoneCtrl.dispose();
    imageCtrl.dispose();
    super.dispose();
  }

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
                  } catch (e) {
                    try {
                      await printSimpleReport(title: title, lines: lines);
                    } catch (_) {}
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'تعذر فتح واجهة الطباعة على هذا الجهاز. تم فتح تقرير بديل. ($e)',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.print_outlined),
                label: const Text('طباعة الوصل'),
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
                  } catch (e) {
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('فشل تصدير Excel. ($e)')),
                    );
                  }
                },
                icon: const Icon(Icons.table_chart_outlined),
                label: const Text('تصدير Excel مفصل'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _bindMerchant(OwnerState state) {
    final merchant = state.merchant;
    if (merchant == null) return;
    if (merchantId == merchant.id) return;

    merchantId = merchant.id;
    nameCtrl.text = merchant.name;
    descCtrl.text = merchant.description ?? '';
    phoneCtrl.text = merchant.phone ?? '';
    imageCtrl.text = merchant.imageUrl ?? '';
    merchantImageFile = null;
    merchantType = merchant.type;
    isOpen = merchant.isOpen;
  }

  Future<void> _openCreateProduct(OwnerState ownerState) async {
    final data = await _openProductSheet(
      context,
      categories: ownerState.categories,
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
          sortOrder: data.sortOrder,
        );
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

  String _ownerTabTitle(AppStrings strings) {
    switch (activeTab) {
      case _OwnerTab.dashboard:
        return strings.t('ownerDashboard');
      case _OwnerTab.profile:
        return 'الملف الشخصي';
      case _OwnerTab.store:
        return 'إعدادات المتجر';
      case _OwnerTab.orders:
        return 'إدارة الطلبات';
      case _OwnerTab.catalog:
        return 'المنتجات والأصناف';
    }
  }

  @override
  Widget build(BuildContext context) {
    final ownerState = ref.watch(ownerControllerProvider);
    final auth = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final merchant = ownerState.merchant;
    final drawerItems = <AppUserDrawerItem>[
      AppUserDrawerItem(
        icon: Icons.dashboard_outlined,
        label: 'لوحة التحكم',
        onTap: (_) async => setState(() => activeTab = _OwnerTab.dashboard),
      ),
      AppUserDrawerItem(
        icon: Icons.person_outline_rounded,
        label: 'الملف الشخصي',
        onTap: (_) async => setState(() => activeTab = _OwnerTab.profile),
      ),
      AppUserDrawerItem(
        icon: Icons.storefront_outlined,
        label: 'إدارة المتجر',
        onTap: (_) async => setState(() => activeTab = _OwnerTab.store),
      ),
      AppUserDrawerItem(
        icon: Icons.receipt_long_outlined,
        label: 'إدارة الطلبات',
        onTap: (_) async => setState(() => activeTab = _OwnerTab.orders),
      ),
      AppUserDrawerItem(
        icon: Icons.inventory_2_outlined,
        label: 'الأصناف والمنتجات',
        onTap: (_) async => setState(() => activeTab = _OwnerTab.catalog),
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: strings.t('drawerRefresh'),
        onTap: (_) async =>
            ref.read(ownerControllerProvider.notifier).bootstrap(),
      ),
      AppUserDrawerItem(
        icon: Icons.add_box_outlined,
        label: strings.t('drawerAddProduct'),
        onTap: (_) async => _openCreateProduct(ownerState),
      ),
    ];

    ref.listen<OwnerState>(ownerControllerProvider, (prev, next) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    _bindMerchant(ownerState);

    if (ownerState.loading && merchant == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (merchant != null && !merchant.isApproved) {
      return _OwnerPendingApprovalView(
        merchant: merchant,
        loading: ownerState.loading,
      );
    }

    return Scaffold(
      drawer: AppUserDrawer(
        title: _ownerTabTitle(strings),
        subtitle: strings.t('drawerOwnerSub'),
        items: drawerItems,
      ),
      appBar: AppBar(
        title: Text(_ownerTabTitle(strings)),
        actions: const [NotificationsBellButton()],
      ),
      floatingActionButton: activeTab == _OwnerTab.catalog
          ? FloatingActionButton.extended(
              onPressed: ownerState.savingProduct
                  ? null
                  : () => _openCreateProduct(ownerState),
              icon: const Icon(Icons.add),
              label: const Text('إضافة منتج'),
            )
          : null,
      body: RefreshIndicator(
        onRefresh: () => ref.read(ownerControllerProvider.notifier).bootstrap(),
        child: ListView(
          padding: const EdgeInsets.all(14),
          children: [
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
                        backgroundImage: auth.user?.imageUrl?.isNotEmpty == true
                            ? NetworkImage(auth.user!.imageUrl!)
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
                      'العنوان: بلوك ${auth.user?.block ?? '-'} - عمارة ${auth.user?.buildingNumber ?? '-'} - شقة ${auth.user?.apartment ?? '-'}',
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
                        label: const Text('تعديل الحساب والأمان'),
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
                        DropdownMenuItem(value: 'market', child: Text('سوق')),
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
                      controller: phoneCtrl,
                      decoration: const InputDecoration(
                        labelText: 'هاتف المتجر',
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
            if (activeTab == _OwnerTab.dashboard) const SizedBox(height: 14),
            if (activeTab == _OwnerTab.dashboard)
              _SectionCard(
                title: 'ملخص اليوم',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _OwnerMetricTile(
                      icon: Icons.receipt_long_outlined,
                      label: 'الطلبات الحالية',
                      value: '${ownerState.currentOrders.length}',
                    ),
                    _OwnerMetricTile(
                      icon: Icons.history_toggle_off_rounded,
                      label: 'طلبات مؤرشفة',
                      value: '${ownerState.historyOrders.length}',
                    ),
                    _OwnerMetricTile(
                      icon: Icons.delivery_dining_rounded,
                      label: 'الدلفري المتاح',
                      value: '${ownerState.deliveryAgents.length}',
                    ),
                    _OwnerMetricTile(
                      icon: Icons.grid_view_rounded,
                      label: 'الأصناف',
                      value: '${ownerState.categories.length}',
                    ),
                    _OwnerMetricTile(
                      icon: Icons.inventory_2_outlined,
                      label: 'المنتجات',
                      value: '${ownerState.products.length}',
                    ),
                  ],
                ),
              ),
            if (activeTab == _OwnerTab.dashboard) const SizedBox(height: 14),
            if (activeTab == _OwnerTab.dashboard)
              _SectionCard(
                title: 'تحليلات سريعة',
                child: _OwnerInsights(
                  analytics: ownerState.analytics,
                  settlementSummary: ownerState.settlementSummary,
                  saving: ownerState.savingOrder,
                  onOpenDetails:
                      ({
                        required title,
                        required lines,
                        required reportPeriod,
                      }) {
                        return _openAnalyticsDetails(
                          title: title,
                          lines: lines,
                          reportPeriod: reportPeriod,
                        );
                      },
                  onRequestSettlement: () async {
                    await ref
                        .read(ownerControllerProvider.notifier)
                        .requestSettlement();
                  },
                ),
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
                title: 'الطلبات المؤرشفة',
                child: ownerState.historyOrders.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('لا توجد طلبات مؤرشفة'),
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
                                  'المجموع: ${formatIqd(o.totalAmount)} - التقييم: ${o.deliveryRating ?? '-'}',
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            )
                            .toList(),
                      ),
              ),
            if (activeTab == _OwnerTab.catalog) const SizedBox(height: 14),
            if (activeTab == _OwnerTab.catalog)
              _SectionCard(
                title: 'أصناف المتجر',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: OutlinedButton.icon(
                        onPressed: ownerState.savingProduct
                            ? null
                            : () async {
                                final data = await _openCategorySheet(context);
                                if (data == null) return;
                                await ref
                                    .read(ownerControllerProvider.notifier)
                                    .createCategory(
                                      name: data.name,
                                      sortOrder: data.sortOrder,
                                    );
                              },
                        icon: const Icon(Icons.add),
                        label: const Text('إضافة صنف'),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (ownerState.categories.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('لا توجد أصناف بعد'),
                      )
                    else
                      ...ownerState.categories.map(
                        (category) => _CategoryTile(
                          category: category,
                          onEdit: () async {
                            final data = await _openCategorySheet(
                              context,
                              category: category,
                            );
                            if (data == null) return;
                            await ref
                                .read(ownerControllerProvider.notifier)
                                .updateCategory(
                                  categoryId: category.id,
                                  name: data.name,
                                  sortOrder: data.sortOrder,
                                );
                          },
                          onDelete: () async {
                            final confirm = await showDialog<bool>(
                              context: context,
                              builder: (_) => AlertDialog(
                                title: const Text('حذف الصنف'),
                                content: const Text(
                                  'عند الحذف سيتم إبقاء المنتجات بدون صنف. هل تريد المتابعة؟',
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
                title: 'المنتجات',
                child: ownerState.products.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.symmetric(vertical: 20),
                        child: Text('لا توجد منتجات بعد'),
                      )
                    : Column(
                        children: ownerState.products
                            .map(
                              (product) => _ProductTile(
                                product: product,
                                onEdit: () async {
                                  final data = await _openProductSheet(
                                    context,
                                    product: product,
                                    categories: ownerState.categories,
                                  );
                                  if (data == null) return;
                                  await ref
                                      .read(ownerControllerProvider.notifier)
                                      .updateProduct(
                                        productId: product.id,
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
                                        sortOrder: data.sortOrder,
                                      );
                                },
                                onDelete: () async {
                                  final confirm = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => AlertDialog(
                                      title: const Text('حذف المنتج'),
                                      content: const Text(
                                        'هل تريد حذف هذا المنتج؟',
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
                                        .deleteProduct(product.id);
                                  }
                                },
                              ),
                            )
                            .toList(),
                      ),
              ),
            const SizedBox(height: 90),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentOrderCard(OrderModel order, OwnerState ownerState) {
    final selectedDelivery =
        selectedDeliveryByOrder[order.id] ?? order.deliveryUserId;
    final controller = ref.read(ownerControllerProvider.notifier);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'طلب #${order.id} - ${orderStatusLabel(order.status)}',
              textDirection: TextDirection.rtl,
            ),
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (order.customerImageUrl?.trim().isNotEmpty == true)
                  CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(order.customerImageUrl!),
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
                        'الموقع: ${order.customerCity} - بلوك ${order.customerBlock} - عمارة ${order.customerBuildingNumber} - شقة ${order.customerApartment}',
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
                  child: Image.network(
                    order.imageUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return const Center(child: Icon(Icons.broken_image));
                    },
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            ...order.items.map(
              (i) => Text(
                '- ${i.productName} - ${i.quantity}',
                textDirection: TextDirection.rtl,
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<int>(
              initialValue: selectedDelivery,
              items: ownerState.deliveryAgents
                  .map(
                    (d) => DropdownMenuItem<int>(
                      value: d.id,
                      child: Text('${d.fullName} - ${d.phone}'),
                    ),
                  )
                  .toList(),
              onChanged: (v) => setState(() {
                if (v == null) {
                  selectedDeliveryByOrder.remove(order.id);
                } else {
                  selectedDeliveryByOrder[order.id] = v;
                }
              }),
              decoration: const InputDecoration(
                labelText: 'إسناد دلفري (اختياري)',
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  onPressed: ownerState.savingOrder || selectedDelivery == null
                      ? null
                      : () => controller.assignDelivery(
                          orderId: order.id,
                          deliveryUserId: selectedDelivery,
                        ),
                  child: const Text('إسناد'),
                ),
                if (order.status == 'pending')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.updateOrderStatus(
                            orderId: order.id,
                            status: 'preparing',
                            estimatedPrepMinutes: 20,
                          ),
                    child: const Text('بدء التحضير'),
                  ),
                if (order.status == 'preparing')
                  ElevatedButton(
                    onPressed: ownerState.savingOrder
                        ? null
                        : () => controller.updateOrderStatus(
                            orderId: order.id,
                            status: 'ready_for_delivery',
                            estimatedDeliveryMinutes: 30,
                          ),
                    child: const Text('جاهز للتوصيل'),
                  ),
                if (order.status != 'delivered' && order.status != 'cancelled')
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

  Future<_ProductFormData?> _openProductSheet(
    BuildContext context, {
    ProductModel? product,
    required List<ProductCategoryModel> categories,
  }) {
    return showModalBottomSheet<_ProductFormData>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          _ProductFormSheet(product: product, categories: categories),
    );
  }

  Future<_CategoryFormData?> _openCategorySheet(
    BuildContext context, {
    ProductCategoryModel? category,
  }) {
    return showModalBottomSheet<_CategoryFormData>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CategoryFormSheet(category: category),
    );
  }
}

class _OwnerMetricTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _OwnerMetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 148,
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
      merchant.type == 'restaurant' ? 'مطعم' : 'سوق';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = ref.watch(appStringsProvider);
    return Scaffold(
      drawer: AppUserDrawer(
        title: strings.t('ownerDashboard'),
        subtitle: strings.t('drawerOwnerPendingSub'),
        items: [
          AppUserDrawerItem(
            icon: Icons.info_outline_rounded,
            label: strings.t('drawerOwnerPendingStatus'),
          ),
          AppUserDrawerItem(
            icon: Icons.refresh_rounded,
            label: strings.t('drawerRefresh'),
            onTap: (_) =>
                ref.read(ownerControllerProvider.notifier).bootstrap(),
          ),
        ],
      ),
      appBar: AppBar(title: Text(strings.t('ownerApprovalPendingTitle'))),
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
                        'تم استلام طلب إنشاء المتجر بنجاح',
                        textAlign: TextAlign.center,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'فريق الإدارة يراجع بيانات المتجر الآن. سيتم إشعارك فور الموافقة.',
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
                                'هاتف المتجر: ${merchant.phone}',
                                textDirection: TextDirection.rtl,
                              ),
                            if (merchant.createdAt != null)
                              Text(
                                'تاريخ الإرسال: ${merchant.createdAt!.toLocal()}',
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
                      Text(
                        'اتصال: $_supportPhone\nواتساب: $_supportWhatsApp',
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
                                const SnackBar(
                                  content: Text('تم نسخ رقم الدعم'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('نسخ رقم الدعم'),
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
    final year = _readPeriod(analytics['year']);

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
              ...detailsForPeriod('ملخص اليوم', day),
              '',
              'حسب الحالة:',
              if (statusToday.isEmpty) 'لا توجد بيانات حالات',
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
              'أكثر المنتجات مبيعًا:',
              if (topProductsToday.isEmpty) 'لا توجد بيانات منتجات',
              ...topProductsToday.take(5).map((row) {
                final name = '${row['product_name'] ?? '-'}';
                final qty = _readNum(row['total_qty']).toInt();
                return '- $name: $qty';
              }),
            ];
            onOpenDetails(
              title: 'تفاصيل إحصائيات اليوم',
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
              title: 'تفاصيل إحصائيات الشهر',
              lines: detailsForPeriod('ملخص الشهر', month),
              reportPeriod: 'month',
            );
          },
        ),
        _InsightLine(
          'السنة',
          '${year.ordersCount} طلب | التوصيل ${formatIqd(year.deliveryFees)}',
          onTap: () {
            onOpenDetails(
              title: 'تفاصيل إحصائيات السنة',
              lines: detailsForPeriod('ملخص السنة', year),
              reportPeriod: 'year',
            );
          },
        ),
        const SizedBox(height: 6),
        _InsightLine(
          'المستحقات الحالية',
          '${formatIqd(outstanding)} (من $ordersCount طلب)',
          onTap: () {
            onOpenDetails(
              title: 'تفاصيل المستحقات',
              lines: [
                'المبلغ الحالي المستحق: ${formatIqd(outstanding)}',
                'عدد الطلبات الداخلة في المستحقات: $ordersCount',
                if (hasPendingSettlement)
                  'يوجد طلب تسديد قيد المراجعة لدى الإدارة'
                else
                  'لا يوجد طلب تسديد قيد المراجعة',
              ],
              reportPeriod: 'year',
            );
          },
        ),
        const Text(
          'اضغط على أي سطر لعرض التفاصيل والطباعة',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
        ),
        if (hasPendingSettlement)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'يوجد طلب تسديد قيد المراجعة لدى الإدارة',
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
      title: Text(category.name, textDirection: TextDirection.rtl),
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

  const _ProductTile({
    required this.product,
    required this.onEdit,
    required this.onDelete,
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
              ? Image.network(
                  product.imageUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
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
              'الصنف: ${product.categoryName}',
              textDirection: TextDirection.rtl,
            ),
          Text(
            product.hasDiscount
                ? 'السعر: ${formatIqd(product.price)} - بعد الخصم: ${formatIqd(effectivePrice)}'
                : 'السعر: ${formatIqd(effectivePrice)}',
            textDirection: TextDirection.rtl,
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

class _ProductFormSheet extends StatefulWidget {
  final ProductModel? product;
  final List<ProductCategoryModel> categories;

  const _ProductFormSheet({this.product, required this.categories});

  @override
  State<_ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<_ProductFormSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController discountCtrl;
  late final TextEditingController imageCtrl;
  late final TextEditingController sortCtrl;
  late final TextEditingController offerCtrl;
  late bool isAvailable;
  late bool freeDelivery;
  int? categoryId;
  LocalImageFile? imageFile;

  @override
  void initState() {
    super.initState();
    final product = widget.product;
    nameCtrl = TextEditingController(text: product?.name ?? '');
    descCtrl = TextEditingController(text: product?.description ?? '');
    priceCtrl = TextEditingController(text: product?.price.toString() ?? '');
    discountCtrl = TextEditingController(
      text: product?.discountedPrice?.toString() ?? '',
    );
    imageCtrl = TextEditingController(text: product?.imageUrl ?? '');
    sortCtrl = TextEditingController(
      text: product?.sortOrder.toString() ?? '0',
    );
    offerCtrl = TextEditingController(text: product?.offerLabel ?? '');
    isAvailable = product?.isAvailable ?? true;
    freeDelivery = product?.freeDelivery ?? false;
    categoryId = product?.categoryId;
    imageFile = null;
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    priceCtrl.dispose();
    discountCtrl.dispose();
    imageCtrl.dispose();
    sortCtrl.dispose();
    offerCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
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
            children: [
              Text(
                isEdit ? 'تعديل المنتج' : 'إضافة منتج',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'اسم المنتج'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<int?>(
                initialValue: categoryId,
                items: [
                  const DropdownMenuItem<int?>(
                    value: null,
                    child: Text('بدون صنف'),
                  ),
                  ...widget.categories.map(
                    (category) => DropdownMenuItem<int?>(
                      value: category.id,
                      child: Text(category.name),
                    ),
                  ),
                ],
                onChanged: (value) => setState(() => categoryId = value),
                decoration: const InputDecoration(labelText: 'الصنف'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: descCtrl,
                decoration: const InputDecoration(labelText: 'الوصف'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(labelText: 'السعر'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: discountCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: const InputDecoration(
                  labelText: 'سعر بعد الخصم (اختياري)',
                ),
              ),
              const SizedBox(height: 10),
              ImagePickerField(
                title: 'صورة المنتج (اختياري)',
                selectedFile: imageFile,
                existingImageUrl: imageCtrl.text.trim().isEmpty
                    ? null
                    : imageCtrl.text.trim(),
                onPick: () async {
                  final picked = await pickImageFromDevice();
                  if (!mounted || picked == null) return;
                  setState(() => imageFile = picked);
                },
                onClear: imageFile == null && imageCtrl.text.trim().isEmpty
                    ? null
                    : () => setState(() {
                        imageFile = null;
                        imageCtrl.text = '';
                      }),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: offerCtrl,
                decoration: const InputDecoration(
                  labelText: 'نص العرض (مثال: خصم نهاية الأسبوع)',
                ),
              ),
              SwitchListTile(
                title: const Text('توصيل مجاني لهذا المنتج'),
                value: freeDelivery,
                onChanged: (v) => setState(() => freeDelivery = v),
              ),
              const SizedBox(height: 4),
              TextField(
                controller: sortCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'ترتيب العرض'),
              ),
              SwitchListTile(
                title: const Text('متاح للطلب'),
                value: isAvailable,
                onChanged: (v) => setState(() => isAvailable = v),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (nameCtrl.text.trim().isEmpty ||
                        priceCtrl.text.trim().isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('اسم المنتج والسعر مطلوبان'),
                        ),
                      );
                      return;
                    }

                    Navigator.pop(
                      context,
                      _ProductFormData(
                        name: nameCtrl.text,
                        description: descCtrl.text,
                        categoryId: categoryId,
                        price: priceCtrl.text,
                        discountedPrice: discountCtrl.text,
                        imageUrl: imageCtrl.text,
                        imageFile: imageFile,
                        freeDelivery: freeDelivery,
                        offerLabel: offerCtrl.text,
                        isAvailable: isAvailable,
                        sortOrder: int.tryParse(sortCtrl.text.trim()) ?? 0,
                      ),
                    );
                  },
                  child: Text(isEdit ? 'حفظ التعديل' : 'إضافة المنتج'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CategoryFormSheet extends StatefulWidget {
  final ProductCategoryModel? category;

  const _CategoryFormSheet({this.category});

  @override
  State<_CategoryFormSheet> createState() => _CategoryFormSheetState();
}

class _CategoryFormSheetState extends State<_CategoryFormSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController sortCtrl;

  @override
  void initState() {
    super.initState();
    nameCtrl = TextEditingController(text: widget.category?.name ?? '');
    sortCtrl = TextEditingController(
      text: widget.category?.sortOrder.toString() ?? '0',
    );
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
              isEdit ? 'تعديل الصنف' : 'إضافة صنف',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم الصنف'),
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
                      const SnackBar(content: Text('اسم الصنف مطلوب')),
                    );
                    return;
                  }
                  Navigator.pop(
                    context,
                    _CategoryFormData(
                      name: nameCtrl.text,
                      sortOrder: int.tryParse(sortCtrl.text.trim()) ?? 0,
                    ),
                  );
                },
                child: Text(isEdit ? 'حفظ التعديل' : 'إضافة الصنف'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ProductFormData {
  final String name;
  final String description;
  final int? categoryId;
  final String price;
  final String discountedPrice;
  final String imageUrl;
  final LocalImageFile? imageFile;
  final bool freeDelivery;
  final String offerLabel;
  final bool isAvailable;
  final int sortOrder;

  const _ProductFormData({
    required this.name,
    required this.description,
    required this.categoryId,
    required this.price,
    required this.discountedPrice,
    required this.imageUrl,
    required this.imageFile,
    required this.freeDelivery,
    required this.offerLabel,
    required this.isAvailable,
    required this.sortOrder,
  });
}

class _CategoryFormData {
  final String name;
  final int sortOrder;

  const _CategoryFormData({required this.name, required this.sortOrder});
}
