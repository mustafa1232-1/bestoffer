import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../merchants/models/store_activity_model.dart';
import '../../merchants/utils/catalog_taxonomy.dart';
import '../models/managed_merchant_model.dart';
import '../state/admin_controller.dart';
import 'admin_merchant_billing_profile_screen.dart';

class AdminMerchantStateManagementScreen extends ConsumerStatefulWidget {
  const AdminMerchantStateManagementScreen({super.key});

  @override
  ConsumerState<AdminMerchantStateManagementScreen> createState() =>
      _AdminMerchantStateManagementScreenState();
}

class _AdminMerchantStateManagementScreenState
    extends ConsumerState<AdminMerchantStateManagementScreen> {
  String _filter = 'all';
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<ManagedMerchantModel> _visible(List<ManagedMerchantModel> items) {
    Iterable<ManagedMerchantModel> out = items;
    switch (_filter) {
      case 'pending':
        out = out.where((item) => !item.isApproved);
        break;
      case 'disabled':
        out = out.where((item) => item.isDisabled);
        break;
      case 'active':
        out = out.where((item) => item.isApproved && !item.isDisabled);
        break;
    }
    final q = _query.trim().toLowerCase();
    if (q.isNotEmpty) {
      out = out.where((item) {
        return item.name.toLowerCase().contains(q) ||
            item.type.toLowerCase().contains(q) ||
            (item.activityType ?? '').toLowerCase().contains(q) ||
            (item.phone ?? '').toLowerCase().contains(q) ||
            (item.ownerFullName ?? '').toLowerCase().contains(q);
      });
    }
    return out.toList(growable: false);
  }

  String _t(BuildContext context, {required String ar, required String en}) {
    Localizations.localeOf(context);
    return en.isNotEmpty ? en : ar;
  }

  Future<List<StoreActivityModel>> _loadStoreActivities() async {
    final raw = await ref
        .read(adminControllerProvider.notifier)
        .adminStoreActivities();
    return raw
        .whereType<Map>()
        .map(
          (item) =>
              StoreActivityModel.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList(growable: false);
  }

  Future<void> _openStoreActivityEditor() async {
    final codeCtrl = TextEditingController();
    final arCtrl = TextEditingController();
    final enCtrl = TextEditingController();
    var baseType = 'market';
    var isActive = true;
    var saving = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              final code = codeCtrl.text.trim();
              final ar = arCtrl.text.trim();
              final en = enCtrl.text.trim();
              if (code.isEmpty || ar.isEmpty || en.isEmpty) return;
              setSheetState(() => saving = true);
              final saved = await ref
                  .read(adminControllerProvider.notifier)
                  .upsertStoreActivity(
                    activityType: code,
                    baseType: baseType,
                    displayNameAr: ar,
                    displayNameEn: en,
                    isActive: isActive,
                  );
              if (!context.mounted) return;
              setSheetState(() => saving = false);
              if (saved) Navigator.of(context).pop(true);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _t(
                      context,
                      ar: 'Add marketplace section',
                      en: 'Add marketplace section',
                    ),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: codeCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'activityType',
                      hintText: 'example: toys',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: arCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: _t(
                        context,
                        ar: 'Arabic name',
                        en: 'Arabic name',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: enCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: _t(
                        context,
                        ar: 'English name',
                        en: 'English name',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: baseType,
                    decoration: InputDecoration(
                      labelText: _t(
                        context,
                        ar: 'Surface type',
                        en: 'Surface type',
                      ),
                    ),
                    items: const [
                      DropdownMenuItem(value: 'market', child: Text('market')),
                      DropdownMenuItem(
                        value: 'restaurant',
                        child: Text('restaurant'),
                      ),
                    ],
                    onChanged: saving
                        ? null
                        : (value) =>
                              setSheetState(() => baseType = value ?? 'market'),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: isActive,
                    onChanged: saving
                        ? null
                        : (value) => setSheetState(() => isActive = value),
                    title: Text(_t(context, ar: 'Active', en: 'Active')),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: saving ? null : submit,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _t(context, ar: 'Save section', en: 'Save section'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    codeCtrl.dispose();
    arCtrl.dispose();
    enCtrl.dispose();

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              context,
              ar: 'Section saved and will appear when creating a store.',
              en: 'Section saved and will appear when creating a store.',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openCatalogTemplateManager() async {
    final activities = await _loadStoreActivities();
    if (!mounted || activities.isEmpty) return;
    var selectedActivity = activities.first.activityType;
    var templates = <Map<String, dynamic>>[];
    var loading = true;

    Future<List<Map<String, dynamic>>> loadTemplates(
      String activityType,
    ) async {
      final raw = await ref
          .read(adminControllerProvider.notifier)
          .adminStoreCatalogTemplates(activityType);
      return raw
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList(growable: false);
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> reload() async {
              setSheetState(() => loading = true);
              templates = await loadTemplates(selectedActivity);
              if (!context.mounted) return;
              setSheetState(() => loading = false);
            }

            Future<void> editTemplate([Map<String, dynamic>? template]) async {
              final saved = await _openCatalogTemplateEditor(
                activityType: selectedActivity,
                template: template,
              );
              if (saved == true) await reload();
            }

            if (loading && templates.isEmpty) {
              Future.microtask(reload);
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: SizedBox(
                  height: MediaQuery.of(context).size.height * 0.78,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'إدارة كاتالوگ الأقسام',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                          ),
                          IconButton(
                            tooltip: 'إضافة كاتالوگ',
                            onPressed: () => editTemplate(),
                            icon: const Icon(Icons.add_rounded),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: selectedActivity,
                        decoration: const InputDecoration(
                          labelText: 'قسم السوق',
                        ),
                        items: activities
                            .map(
                              (item) => DropdownMenuItem(
                                value: item.activityType,
                                child: Text(item.localizedLabel(true)),
                              ),
                            )
                            .toList(),
                        onChanged: (value) async {
                          selectedActivity = value ?? selectedActivity;
                          templates = const <Map<String, dynamic>>[];
                          await reload();
                        },
                      ),
                      const SizedBox(height: 12),
                      Expanded(
                        child: loading
                            ? const Center(child: CircularProgressIndicator())
                            : templates.isEmpty
                            ? const Center(
                                child: Text('لا توجد قوالب كاتالوگ.'),
                              )
                            : ListView.separated(
                                itemCount: templates.length,
                                separatorBuilder: (context, index) =>
                                    const Divider(height: 1),
                                itemBuilder: (context, index) {
                                  final item = templates[index];
                                  final id =
                                      int.tryParse('${item['id'] ?? ''}') ?? 0;
                                  final isActive = item['isActive'] != false;
                                  return ListTile(
                                    leading: Icon(
                                      isActive
                                          ? Icons.category_rounded
                                          : Icons.visibility_off_rounded,
                                    ),
                                    title: Text(
                                      '${item['nameAr'] ?? item['nameEn'] ?? ''}',
                                    ),
                                    subtitle: Text(
                                      '${item['code'] ?? ''} • ${catalogTypeLabel('${item['catalogType'] ?? 'generic'}')}',
                                    ),
                                    trailing: Wrap(
                                      spacing: 4,
                                      children: [
                                        IconButton(
                                          tooltip: 'تعديل',
                                          onPressed: () => editTemplate(item),
                                          icon: const Icon(Icons.edit_rounded),
                                        ),
                                        IconButton(
                                          tooltip: 'حذف',
                                          onPressed: id <= 0
                                              ? null
                                              : () async {
                                                  final ok = await ref
                                                      .read(
                                                        adminControllerProvider
                                                            .notifier,
                                                      )
                                                      .deleteStoreCatalogTemplate(
                                                        id,
                                                      );
                                                  if (ok) await reload();
                                                },
                                          icon: const Icon(
                                            Icons.delete_outline_rounded,
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<bool?> _openCatalogTemplateEditor({
    required String activityType,
    Map<String, dynamic>? template,
  }) async {
    final isEdit = template != null;
    final codeCtrl = TextEditingController(text: '${template?['code'] ?? ''}');
    final arCtrl = TextEditingController(text: '${template?['nameAr'] ?? ''}');
    final enCtrl = TextEditingController(text: '${template?['nameEn'] ?? ''}');
    final iconCtrl = TextEditingController(text: '${template?['icon'] ?? ''}');
    final orderCtrl = TextEditingController(
      text: '${template?['orderIndex'] ?? 0}',
    );
    final allowedTypes = allowedCatalogTypesForActivity(activityType);
    final catalogTypeOptions = allowedTypes.isEmpty
        ? const <String>['generic']
        : allowedTypes;
    var catalogType = normalizeCatalogType(
      '${template?['catalogType'] ?? ''}',
      fallback: catalogTypeOptions.first,
    );
    if (!catalogTypeOptions.contains(catalogType)) {
      catalogType = catalogTypeOptions.first;
    }
    var isActive = template?['isActive'] != false;
    var saving = false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> submit() async {
              final code = codeCtrl.text.trim();
              final ar = arCtrl.text.trim();
              final en = enCtrl.text.trim();
              if (code.isEmpty || ar.isEmpty || en.isEmpty) return;
              setSheetState(() => saving = true);
              final notifier = ref.read(adminControllerProvider.notifier);
              final saved = isEdit
                  ? await notifier.updateStoreCatalogTemplate(
                      templateId: int.parse('${template['id']}'),
                      code: code,
                      nameAr: ar,
                      nameEn: en,
                      catalogType: catalogType,
                      icon: iconCtrl.text.trim().isEmpty
                          ? null
                          : iconCtrl.text.trim(),
                      orderIndex: int.tryParse(orderCtrl.text.trim()) ?? 0,
                      isActive: isActive,
                    )
                  : await notifier.upsertStoreCatalogTemplate(
                      activityType: activityType,
                      code: code,
                      nameAr: ar,
                      nameEn: en,
                      catalogType: catalogType,
                      icon: iconCtrl.text.trim().isEmpty
                          ? null
                          : iconCtrl.text.trim(),
                      orderIndex: int.tryParse(orderCtrl.text.trim()) ?? 0,
                      isActive: isActive,
                    );
              if (!context.mounted) return;
              setSheetState(() => saving = false);
              if (saved) Navigator.of(context).pop(true);
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: 16,
                  right: 16,
                  top: 16,
                  bottom: MediaQuery.of(context).viewInsets.bottom + 16,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      isEdit ? 'تعديل كاتالوگ' : 'إضافة كاتالوگ',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: codeCtrl,
                      decoration: const InputDecoration(labelText: 'code'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: arCtrl,
                      decoration: const InputDecoration(labelText: 'الاسم'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: enCtrl,
                      decoration: const InputDecoration(labelText: 'English'),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: catalogType,
                      decoration: const InputDecoration(
                        labelText: 'نوع الكاتالوگ',
                      ),
                      items: catalogTypeOptions
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(catalogTypeLabel(type)),
                            ),
                          )
                          .toList(),
                      onChanged: saving
                          ? null
                          : (value) => setSheetState(
                              () => catalogType = value ?? catalogType,
                            ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: iconCtrl,
                      decoration: const InputDecoration(labelText: 'icon'),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: orderCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'الترتيب'),
                    ),
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      value: isActive,
                      onChanged: saving
                          ? null
                          : (value) => setSheetState(() => isActive = value),
                      title: const Text('فعّال'),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: saving ? null : submit,
                      icon: saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.save_rounded),
                      label: const Text('حفظ'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    codeCtrl.dispose();
    arCtrl.dispose();
    enCtrl.dispose();
    iconCtrl.dispose();
    orderCtrl.dispose();
    return result;
  }

  Future<void> _openMerchantProfileEditor(ManagedMerchantModel merchant) async {
    final activities = await _loadStoreActivities();
    if (!mounted) return;

    final nameCtrl = TextEditingController(text: merchant.name);
    final phoneCtrl = TextEditingController(text: merchant.phone ?? '');
    final descCtrl = TextEditingController(text: merchant.description ?? '');
    var selectedActivity =
        activities.any((item) => item.activityType == merchant.activityType)
        ? merchant.activityType
        : (activities.isNotEmpty ? activities.first.activityType : null);
    var saving = false;
    // القسم الفرعي (discovery subcategory) — يُحمّل حسب القسم المختار.
    String? selectedSubcategory = merchant.discoverySubcategory;
    var discoveryOptions = <Map<String, dynamic>>[];
    var optionsForActivity = '';
    var loadingOptions = false;

    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            StoreActivityModel? selected;
            for (final item in activities) {
              if (item.activityType == selectedActivity) {
                selected = item;
                break;
              }
            }

            // "جاهز" فقط بعد أن نعرف أقسام القسم المختار (حمّلناها فعلاً).
            final optionsReady = optionsForActivity == selectedActivity;

            Future<void> submit() async {
              if (nameCtrl.text.trim().isEmpty || selected == null) return;
              // بعض الأقسام لا تملك أقساماً فرعية: لا نرسل selectAll إطلاقاً
              // كي لا يرفضه الباك اند (DISCOVERY_SUBCATEGORY_NOT_SUPPORTED).
              final hasOptions = discoveryOptions.isNotEmpty;
              setSheetState(() => saving = true);
              final saved = await ref
                  .read(adminControllerProvider.notifier)
                  .updateMerchantProfile(
                    merchantId: merchant.id,
                    name: nameCtrl.text.trim(),
                    phone: phoneCtrl.text.trim().isEmpty
                        ? null
                        : phoneCtrl.text.trim(),
                    description: descCtrl.text.trim().isEmpty
                        ? null
                        : descCtrl.text.trim(),
                    type: selected.baseType,
                    activityType: selected.activityType,
                    storeDepartment: merchant.storeDepartment,
                    discoverySubcategory: hasOptions ? selectedSubcategory : null,
                    discoverySelectAll:
                        hasOptions ? (selectedSubcategory == null) : false,
                  );
              if (!context.mounted) return;
              setSheetState(() => saving = false);
              if (saved) Navigator.of(context).pop(true);
            }

            // يحمّل الأقسام الفرعية للقسم المختار (مرة واحدة لكل قسم).
            Future<void> loadOptionsFor(String? activityType) async {
              if (activityType == null || activityType.isEmpty) return;
              if (optionsForActivity == activityType) return;
              setSheetState(() => loadingOptions = true);
              try {
                final opts = await ref
                    .read(adminApiProvider)
                    .activityDiscoveryOptions(activityType);
                if (!context.mounted) return;
                setSheetState(() {
                  discoveryOptions = opts;
                  optionsForActivity = activityType;
                  loadingOptions = false;
                  final codes = opts.map((o) => '${o['code']}').toSet();
                  if (selectedSubcategory != null &&
                      !codes.contains(selectedSubcategory)) {
                    selectedSubcategory = null;
                  }
                });
              } catch (_) {
                if (context.mounted) {
                  setSheetState(() => loadingOptions = false);
                }
              }
            }

            if (!loadingOptions && optionsForActivity != selectedActivity) {
              Future.microtask(() => loadOptionsFor(selectedActivity));
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _t(context, ar: 'Edit merchant', en: 'Edit merchant'),
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: _t(
                        context,
                        ar: 'Store name',
                        en: 'Store name',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: phoneCtrl,
                    textInputAction: TextInputAction.next,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: _t(
                        context,
                        ar: 'Store phone',
                        en: 'Store phone',
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: selectedActivity,
                    decoration: InputDecoration(
                      labelText: _t(
                        context,
                        ar: 'Marketplace section',
                        en: 'Marketplace section',
                      ),
                    ),
                    items: activities
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.activityType,
                            child: Text(
                              item.localizedLabel(
                                Localizations.localeOf(context).languageCode ==
                                    'ar',
                              ),
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: saving
                        ? null
                        : (value) => setSheetState(() {
                            selectedActivity = value;
                            // القسم تغيّر: الأقسام الفرعية القديمة لم تعد صالحة.
                            selectedSubcategory = null;
                          }),
                  ),
                  const SizedBox(height: 10),
                  if (loadingOptions)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 8),
                      child: LinearProgressIndicator(),
                    )
                  else if (discoveryOptions.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue: selectedSubcategory,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t(
                          context,
                          ar: 'القسم الفرعي',
                          en: 'Subcategory',
                        ),
                        helperText: _t(
                          context,
                          ar: 'اترك (كل الأقسام) لعرض المتجر في كامل القسم',
                          en: 'Leave (All) to show the store across the section',
                        ),
                      ),
                      items: [
                        DropdownMenuItem<String?>(
                          value: null,
                          child: Text(
                            _t(context, ar: 'كل الأقسام', en: 'All'),
                          ),
                        ),
                        ...discoveryOptions.map((opt) {
                          final isAr =
                              Localizations.localeOf(context).languageCode ==
                              'ar';
                          final label = isAr
                              ? '${opt['labelAr'] ?? opt['labelEn'] ?? opt['code']}'
                              : '${opt['labelEn'] ?? opt['labelAr'] ?? opt['code']}';
                          return DropdownMenuItem<String?>(
                            value: '${opt['code']}',
                            child: Text(label),
                          );
                        }),
                      ],
                      onChanged: saving
                          ? null
                          : (value) => setSheetState(
                              () => selectedSubcategory = value,
                            ),
                    ),
                  if (loadingOptions || discoveryOptions.isNotEmpty)
                    const SizedBox(height: 10),
                  TextField(
                    controller: descCtrl,
                    maxLines: 3,
                    decoration: InputDecoration(
                      labelText: _t(
                        context,
                        ar: 'Description',
                        en: 'Description',
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: (saving || !optionsReady) ? null : submit,
                    icon: saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_rounded),
                    label: Text(
                      _t(context, ar: 'Save changes', en: 'Save changes'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    nameCtrl.dispose();
    phoneCtrl.dispose();
    descCtrl.dispose();

    if (ok == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(context, ar: 'Merchant updated.', en: 'Merchant updated.'),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final items = _visible(state.managedMerchants);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminMerchantStateManagementTitle),
        actions: [
          IconButton(
            tooltip: _t(
              context,
              ar: 'Add marketplace section',
              en: 'Add marketplace section',
            ),
            onPressed: _openStoreActivityEditor,
            icon: const Icon(Icons.add_business_rounded),
          ),
          IconButton(
            tooltip: 'إدارة كاتالوگ الأقسام',
            onPressed: _openCatalogTemplateManager,
            icon: const Icon(Icons.category_rounded),
          ),
          IconButton(
            onPressed: () =>
                ref.read(adminControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(adminControllerProvider.notifier).bootstrap(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            TextField(
              controller: _searchCtrl,
              onChanged: (value) => setState(() => _query = value),
              decoration: InputDecoration(
                labelText: l10n.adminMerchantStateSearch,
                prefixIcon: const Icon(Icons.search_rounded),
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _FilterChip(
                  label: l10n.commonAll,
                  selected: _filter == 'all',
                  onTap: () => setState(() => _filter = 'all'),
                ),
                _FilterChip(
                  label: l10n.commonPending,
                  selected: _filter == 'pending',
                  onTap: () => setState(() => _filter = 'pending'),
                ),
                _FilterChip(
                  label: l10n.adminMerchantStateActiveFilter,
                  selected: _filter == 'active',
                  onTap: () => setState(() => _filter = 'active'),
                ),
                _FilterChip(
                  label: l10n.adminMerchantStateDisabledFilter,
                  selected: _filter == 'disabled',
                  onTap: () => setState(() => _filter = 'disabled'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (items.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 28),
                child: Center(child: Text(l10n.adminMerchantStateNoMatches)),
              )
            else
              ...items.map(
                (item) => Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w800),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    l10n.adminMerchantStateTypeLine(item.type),
                                  ),
                                  if ((item.activityType ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      _t(
                                        context,
                                        ar: 'Marketplace section: ${item.activityType}',
                                        en: 'Marketplace section: ${item.activityType}',
                                      ),
                                    ),
                                  if ((item.ownerFullName ?? '')
                                      .trim()
                                      .isNotEmpty)
                                    Text(
                                      l10n.adminMerchantStateOwnerLine(
                                        item.ownerFullName!,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            Switch.adaptive(
                              value: !item.isDisabled,
                              onChanged: state.saving
                                  ? null
                                  : (value) {
                                      ref
                                          .read(
                                            adminControllerProvider.notifier,
                                          )
                                          .toggleMerchantDisabled(
                                            merchantId: item.id,
                                            isDisabled: !value,
                                          );
                                    },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            _StatusPill(
                              label: item.isApproved
                                  ? l10n.adminMerchantStateApproved
                                  : l10n.adminMerchantStatePendingApproval,
                              active: item.isApproved,
                            ),
                            _StatusPill(
                              label: item.isDisabled
                                  ? l10n.adminMerchantStateDisabled
                                  : l10n.adminMerchantStateEnabled,
                              active: !item.isDisabled,
                            ),
                            _StatusPill(
                              label: item.isOpen
                                  ? l10n.adminMerchantStateOpen
                                  : l10n.adminMerchantStateClosed,
                              active: item.isOpen,
                            ),
                            _StatusPill(
                              label: l10n.adminMerchantStateTodayOrders(
                                item.todayOrdersCount,
                              ),
                              active: item.todayOrdersCount > 0,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            OutlinedButton.icon(
                              onPressed: state.saving
                                  ? null
                                  : () => _openMerchantProfileEditor(item),
                              icon: const Icon(Icons.edit_rounded),
                              label: Text(
                                _t(
                                  context,
                                  ar: 'Edit merchant',
                                  en: 'Edit merchant',
                                ),
                              ),
                            ),
                            OutlinedButton.icon(
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        AdminMerchantBillingProfileScreen(
                                          merchantId: item.id,
                                          merchantName: item.name,
                                        ),
                                  ),
                                );
                              },
                              icon: const Icon(Icons.tune_rounded),
                              label: Text(
                                l10n.adminMerchantStateBillingProfile,
                              ),
                            ),
                          ],
                        ),
                      ],
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

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final bool active;

  const _StatusPill({required this.label, required this.active});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = active ? scheme.primary : scheme.outline;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w700),
      ),
    );
  }
}
