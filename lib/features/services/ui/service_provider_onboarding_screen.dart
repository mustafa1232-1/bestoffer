// ignore_for_file: deprecated_member_use

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';

class ServiceProviderOnboardingScreen extends ConsumerStatefulWidget {
  const ServiceProviderOnboardingScreen({super.key});

  @override
  ConsumerState<ServiceProviderOnboardingScreen> createState() =>
      _ServiceProviderOnboardingScreenState();
}

class _ServiceProviderOnboardingScreenState
    extends ConsumerState<ServiceProviderOnboardingScreen> {
  final _fullNameCtrl = TextEditingController();
  final _businessNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _bioCtrl = TextEditingController();
  final _whatsappCtrl = TextEditingController();
  final _responseMinutesCtrl = TextEditingController();
  final _yearsExpCtrl = TextEditingController();
  final _teamSizeCtrl = TextEditingController();
  final _categorySearchCtrl = TextEditingController();
  final _newCategoryCtrl = TextEditingController();

  List<ServiceCategoryModel> _categories = const <ServiceCategoryModel>[];
  int? _mainCategoryId;
  bool _loadingCategories = true;
  bool _addingCategory = false;
  bool _submitting = false;
  bool _checkingStatus = false;
  bool _respondingOffer = false;
  bool _servesAtHome = true;
  bool _servesAtShop = false;
  bool _servesRemote = false;
  bool _hasEmergency = false;
  bool _hasTeam = false;
  bool _acceptsCash = true;
  bool _acceptsElectronic = false;
  bool _available247 = false;
  String _bookingPolicy = 'approval_required';
  String _pricingMode = 'mixed';
  String? _providerGender;
  String? _error;
  LocalImageFile? _logoFile;
  LocalImageFile? _coverFile;
  ServiceProviderSubscriptionProgressModel? _progress;

  @override
  void initState() {
    super.initState();
    _loadCategories();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _businessNameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _cityCtrl.dispose();
    _areaCtrl.dispose();
    _addressCtrl.dispose();
    _bioCtrl.dispose();
    _whatsappCtrl.dispose();
    _responseMinutesCtrl.dispose();
    _yearsExpCtrl.dispose();
    _teamSizeCtrl.dispose();
    _categorySearchCtrl.dispose();
    _newCategoryCtrl.dispose();
    super.dispose();
  }

  String _normalizeInput(String value) {
    final sb = StringBuffer();
    for (final rune in value.runes) {
      if (rune >= 0x0660 && rune <= 0x0669) {
        sb.writeCharCode(0x30 + (rune - 0x0660));
      } else if (rune >= 0x06F0 && rune <= 0x06F9) {
        sb.writeCharCode(0x30 + (rune - 0x06F0));
      } else {
        sb.writeCharCode(rune);
      }
    }
    return sb.toString().trim();
  }

  Future<void> _loadCategories() async {
    setState(() => _loadingCategories = true);
    try {
      final rows = await ref.read(servicesApiProvider).listPublicCategories();
      if (!mounted) return;
      setState(() {
        _categories = rows.map(ServiceCategoryModel.fromJson).toList();
        _loadingCategories = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapAnyError(e, fallback: 'تعذر تحميل فئات الخدمات.');
        _loadingCategories = false;
      });
    }
  }

  String _normalizedCategoryName(String value) {
    return value.replaceAll(RegExp(r'\s+'), '').toLowerCase().trim();
  }

  ServiceCategoryModel? _matchingRootCategory(String value) {
    final needle = _normalizedCategoryName(value);
    if (needle.isEmpty) return null;
    for (final root in _categories.where((item) => item.level == 1)) {
      if (_normalizedCategoryName(root.name) == needle) {
        return root;
      }
      for (final child in root.children) {
        if (_normalizedCategoryName(child.name) == needle) {
          return root;
        }
      }
    }
    return null;
  }

  List<ServiceCategoryModel> _visibleRootCategories() {
    final roots = _categories.where((item) => item.level == 1).toList();
    final query = _categorySearchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return roots;
    return roots.where((root) {
      if (root.name.toLowerCase().contains(query)) return true;
      return root.children.any(
        (child) => child.name.toLowerCase().contains(query),
      );
    }).toList();
  }

  Future<void> _addNewCategory() async {
    if (_addingCategory) return;
    final rawName = _newCategoryCtrl.text.trim();
    if (rawName.isEmpty) {
      setState(() => _error = 'يرجى إدخال اسم نوع الخدمة.');
      return;
    }

    final existing = _matchingRootCategory(rawName);
    if (existing != null) {
      setState(() {
        _mainCategoryId = existing.id;
        _newCategoryCtrl.clear();
        _categorySearchCtrl.clear();
        _error = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم اختيار نوع الخدمة الحالي: ${existing.name}'),
        ),
      );
      return;
    }

    setState(() {
      _addingCategory = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(servicesApiProvider)
          .createPublicCategory(name: rawName);
      final payload = raw['category'] is Map
          ? Map<String, dynamic>.from(raw['category'] as Map)
          : raw;
      final created = ServiceCategoryModel.fromJson(
        Map<String, dynamic>.from(payload),
      );
      if (!mounted) return;
      await _loadCategories();
      if (!mounted) return;
      setState(() {
        _mainCategoryId = created.id;
        _newCategoryCtrl.clear();
        _categorySearchCtrl.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'تمت إضافة نوع الخدمة "${created.name}" وتحديثه للجميع.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(
        () =>
            _error = mapAnyError(e, fallback: 'تعذر إضافة نوع الخدمة الجديد.'),
      );
    } finally {
      if (mounted) setState(() => _addingCategory = false);
    }
  }

  Future<void> _submitRequest() async {
    if (_submitting) return;
    if (_fullNameCtrl.text.trim().isEmpty ||
        _phoneCtrl.text.trim().isEmpty ||
        _pinCtrl.text.trim().isEmpty ||
        _cityCtrl.text.trim().isEmpty ||
        _mainCategoryId == null) {
      setState(() => _error = 'يرجى تعبئة الحقول الأساسية.');
      return;
    }
    if (!(_servesAtHome || _servesAtShop || _servesRemote)) {
      setState(() => _error = 'اختر نمط تنفيذ خدمة واحد على الأقل.');
      return;
    }

    setState(() {
      _error = null;
      _submitting = true;
    });

    try {
      final raw = await ref
          .read(servicesApiProvider)
          .createProviderSubscriptionRequest(
            {
              'fullName': _fullNameCtrl.text.trim(),
              'phone': _normalizeInput(_phoneCtrl.text),
              'pin': _normalizeInput(_pinCtrl.text),
              'businessName': _businessNameCtrl.text.trim().isEmpty
                  ? _fullNameCtrl.text.trim()
                  : _businessNameCtrl.text.trim(),
              'mainCategoryId': _mainCategoryId,
              'city': _cityCtrl.text.trim(),
              if (_areaCtrl.text.trim().isNotEmpty)
                'area': _areaCtrl.text.trim(),
              if (_addressCtrl.text.trim().isNotEmpty)
                'addressLine': _addressCtrl.text.trim(),
              if (_bioCtrl.text.trim().isNotEmpty) 'bio': _bioCtrl.text.trim(),
              if (_whatsappCtrl.text.trim().isNotEmpty)
                'whatsappPhone': _normalizeInput(_whatsappCtrl.text),
              'servesAtHome': _servesAtHome,
              'servesAtShop': _servesAtShop,
              'servesRemote': _servesRemote,
              'hasEmergencyService': _hasEmergency,
              'bookingPolicy': _bookingPolicy,
              'pricingMode': _pricingMode,
              if (_yearsExpCtrl.text.trim().isNotEmpty)
                'yearsExperience': int.tryParse(_yearsExpCtrl.text.trim()),
              'hasTeam': _hasTeam,
              if (_teamSizeCtrl.text.trim().isNotEmpty)
                'teamSize': int.tryParse(_teamSizeCtrl.text.trim()),
              'acceptsCash': _acceptsCash,
              'acceptsElectronic': _acceptsElectronic,
              if (_responseMinutesCtrl.text.trim().isNotEmpty)
                'averageResponseMinutes': int.tryParse(
                  _responseMinutesCtrl.text.trim(),
                ),
              'available247': _available247,
              if ((_providerGender ?? '').trim().isNotEmpty)
                'providerGender': _providerGender,
            },
            logoFile: _logoFile,
            coverFile: _coverFile,
          );
      if (!mounted) return;
      setState(() {
        _progress = ServiceProviderSubscriptionProgressModel.fromJson(raw);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب الاشتراك بنجاح.')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = mapAnyError(e, fallback: 'تعذر إرسال الطلب.'));
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _checkSubscriptionStatus() async {
    if (_checkingStatus) return;
    final phone = _normalizeInput(_phoneCtrl.text);
    final pin = _normalizeInput(_pinCtrl.text);
    if (phone.isEmpty || pin.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف و PIN للتحقق من الحالة.');
      return;
    }

    setState(() {
      _checkingStatus = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(servicesApiProvider)
          .getProviderSubscriptionStatus(phone: phone, pin: pin);
      if (!mounted) return;
      setState(() {
        _progress = ServiceProviderSubscriptionProgressModel.fromJson(raw);
      });
    } catch (e) {
      if (!mounted) return;
      setState(
        () => _error = mapAnyError(e, fallback: 'تعذر جلب حالة الاشتراك.'),
      );
    } finally {
      if (mounted) setState(() => _checkingStatus = false);
    }
  }

  Future<void> _respondOffer(String action) async {
    final progress = _progress;
    if (progress == null || _respondingOffer) return;
    final phone = _normalizeInput(_phoneCtrl.text);
    final pin = _normalizeInput(_pinCtrl.text);
    if (phone.isEmpty || pin.isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف و PIN للرد على العرض.');
      return;
    }

    setState(() {
      _respondingOffer = true;
      _error = null;
    });
    try {
      final raw = await ref
          .read(servicesApiProvider)
          .respondProviderSubscriptionOffer(
            requestId: progress.requestId,
            phone: phone,
            pin: pin,
            action: action,
            offerId: progress.activeOffer?.id,
          );
      if (!mounted) return;
      setState(() {
        _progress = ServiceProviderSubscriptionProgressModel.fromJson(raw);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            action == 'accept'
                ? 'تم قبول العرض. بانتظار تأكيد الاستلام النقدي.'
                : 'تم رفض العرض. بانتظار عرض جديد.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = mapAnyError(e, fallback: 'تعذر إرسال الرد.'));
    } finally {
      if (mounted) setState(() => _respondingOffer = false);
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending_offer':
        return 'بانتظار عرض الأدمن';
      case 'offer_sent':
        return 'تم إرسال عرض سعر';
      case 'offer_accepted':
        return 'العرض مقبول';
      case 'offer_rejected':
        return 'العرض مرفوض';
      case 'payment_pending_confirmation':
        return 'بانتظار تأكيد الاستلام';
      case 'payment_confirmed':
        return 'تم تأكيد الدفع';
      case 'account_created':
        return 'تم إنشاء الحساب';
      case 'rejected':
        return 'تم رفض الطلب';
      case 'cancelled':
        return 'تم إلغاء الطلب';
      default:
        return status;
    }
  }

  String _statusHint(String nextAction) {
    switch (nextAction) {
      case 'wait_admin_offer':
        return 'الخطوة التالية: انتظار تحديد سعر الاشتراك من الأدمن.';
      case 'provider_review_offer':
        return 'الخطوة التالية: راجع العرض ثم وافق أو ارفض.';
      case 'wait_admin_cash_confirmation':
        return 'الخطوة التالية: دفع نقدي خارج التطبيق ثم انتظار التأكيد.';
      case 'wait_account_creation':
        return 'الخطوة التالية: جاري إنشاء الحساب.';
      case 'login_available':
        return 'الخطوة التالية: يمكنك تسجيل الدخول الآن.';
      case 'wait_admin_new_offer':
        return 'الخطوة التالية: انتظار عرض جديد من الأدمن.';
      case 'request_closed':
        return 'الطلب مغلق.';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    if (servicesSection.isBlocked) {
      return SectionUnavailableScreen(entry: servicesSection);
    }
    final roots = _categories.where((item) => item.level == 1).toList();
    final visibleRoots = _visibleRootCategories();
    final progress = _progress;
    return Scaffold(
      appBar: AppBar(title: const Text('اشتراك صاحب خدمة')),
      body: Stack(
        children: [
          const SizedBox.expand(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 860),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          color: Colors.black.withValues(alpha: 0.08),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: ListView(
                          children: [
                            if (_error != null)
                              Card(
                                color: Colors.red.withValues(alpha: 0.12),
                                child: Padding(
                                  padding: const EdgeInsets.all(10),
                                  child: Text(
                                    _error!,
                                    style: const TextStyle(color: Colors.red),
                                  ),
                                ),
                              ),
                            if (progress != null)
                              _SubscriptionProgressCard(
                                progress: progress,
                                statusLabel: _statusLabel(progress.status),
                                statusHint: _statusHint(progress.nextAction),
                                onAccept: progress.requiresProviderAction
                                    ? () => _respondOffer('accept')
                                    : null,
                                onReject: progress.requiresProviderAction
                                    ? () => _respondOffer('reject')
                                    : null,
                                responding: _respondingOffer,
                              ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _fullNameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'الاسم الكامل',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _businessNameCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'الاسم التجاري (اختياري)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _phoneCtrl,
                                    keyboardType: TextInputType.phone,
                                    decoration: const InputDecoration(
                                      labelText: 'رقم الهاتف',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _pinCtrl,
                                    keyboardType: TextInputType.number,
                                    obscureText: true,
                                    decoration: const InputDecoration(
                                      labelText: 'PIN',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            if (_loadingCategories)
                              const LinearProgressIndicator(minHeight: 2),
                            const SizedBox(height: 10),
                            TextField(
                              key: const Key('service_category_search_field'),
                              controller: _categorySearchCtrl,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                labelText: 'ابحث عن اسم الخدمة',
                                prefixIcon: Icon(Icons.search_rounded),
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              key: const Key('service_category_new_field'),
                              controller: _newCategoryCtrl,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _addNewCategory(),
                              decoration: const InputDecoration(
                                labelText: 'إضافة نوع خدمة جديد',
                                hintText: 'مثال: تنظيف شقق',
                                prefixIcon: Icon(Icons.add_circle_outline),
                              ),
                            ),
                            const SizedBox(height: 8),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                key: const Key('service_category_add_button'),
                                onPressed: _addingCategory
                                    ? null
                                    : _addNewCategory,
                                icon: _addingCategory
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Icon(Icons.add_rounded),
                                label: const Text('إضافة نوع الخدمة'),
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (roots.isEmpty && !_loadingCategories)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('لا توجد فئات خدمات متاحة حالياً.'),
                              ),
                            if (roots.isNotEmpty && visibleRoots.isEmpty)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 8),
                                child: Text('لا توجد نتائج مطابقة لهذا الاسم.'),
                              ),
                            DropdownButtonFormField<int>(
                              key: const Key('service_category_dropdown'),
                              isExpanded: true,
                              value:
                                  visibleRoots.any(
                                    (item) => item.id == _mainCategoryId,
                                  )
                                  ? _mainCategoryId
                                  : null,
                              items: visibleRoots
                                  .map(
                                    (item) => DropdownMenuItem<int>(
                                      value: item.id,
                                      child: Text(item.name),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) => setState(() {
                                _mainCategoryId = value;
                                if (value != null) {
                                  _categorySearchCtrl.clear();
                                }
                              }),
                              decoration: const InputDecoration(
                                labelText: 'الفئة الرئيسية للخدمة',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _cityCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'المدينة',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _areaCtrl,
                                    decoration: const InputDecoration(
                                      labelText: 'المنطقة',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _addressCtrl,
                              decoration: const InputDecoration(
                                labelText: 'العنوان التفصيلي (اختياري)',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _bioCtrl,
                              maxLines: 3,
                              decoration: const InputDecoration(
                                labelText: 'نبذة تعريفية',
                              ),
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: _whatsappCtrl,
                              keyboardType: TextInputType.phone,
                              decoration: const InputDecoration(
                                labelText: 'واتساب (اختياري)',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilterChip(
                                  label: const Text('خدمة منزلية'),
                                  selected: _servesAtHome,
                                  onSelected: (v) =>
                                      setState(() => _servesAtHome = v),
                                ),
                                FilterChip(
                                  label: const Text('داخل المحل'),
                                  selected: _servesAtShop,
                                  onSelected: (v) =>
                                      setState(() => _servesAtShop = v),
                                ),
                                FilterChip(
                                  label: const Text('عن بُعد'),
                                  selected: _servesRemote,
                                  onSelected: (v) =>
                                      setState(() => _servesRemote = v),
                                ),
                                FilterChip(
                                  label: const Text('طوارئ'),
                                  selected: _hasEmergency,
                                  onSelected: (v) =>
                                      setState(() => _hasEmergency = v),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _bookingPolicy,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'approval_required',
                                        child: Text('موافقة مسبقة'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'instant',
                                        child: Text('حجز فوري'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() => _bookingPolicy = value);
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'سياسة الحجز',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    value: _pricingMode,
                                    isExpanded: true,
                                    items: const [
                                      DropdownMenuItem(
                                        value: 'mixed',
                                        child: Text('مرن / مختلط'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'fixed',
                                        child: Text('سعر ثابت'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'starting_from',
                                        child: Text('يبدأ من'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'inspection_required',
                                        child: Text('بعد المعاينة'),
                                      ),
                                      DropdownMenuItem(
                                        value: 'custom_quote',
                                        child: Text('تسعير مخصص'),
                                      ),
                                    ],
                                    onChanged: (value) {
                                      if (value == null) return;
                                      setState(() => _pricingMode = value);
                                    },
                                    decoration: const InputDecoration(
                                      labelText: 'نمط التسعير',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: TextField(
                                    controller: _yearsExpCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'سنوات الخبرة',
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _responseMinutesCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'متوسط الاستجابة (دقيقة)',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: Material(
                                    type: MaterialType.transparency,
                                    child: SwitchListTile(
                                      dense: true,
                                      value: _hasTeam,
                                      title: const Text('لدي فريق عمل'),
                                      onChanged: (v) =>
                                          setState(() => _hasTeam = v),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextField(
                                    controller: _teamSizeCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'عدد العمال',
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                FilterChip(
                                  label: const Text('دفع نقدي'),
                                  selected: _acceptsCash,
                                  onSelected: (v) =>
                                      setState(() => _acceptsCash = v),
                                ),
                                FilterChip(
                                  label: const Text('دفع إلكتروني'),
                                  selected: _acceptsElectronic,
                                  onSelected: (v) =>
                                      setState(() => _acceptsElectronic = v),
                                ),
                                FilterChip(
                                  label: const Text('متاح 24/7'),
                                  selected: _available247,
                                  onSelected: (v) =>
                                      setState(() => _available247 = v),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            DropdownButtonFormField<String?>(
                              value: _providerGender,
                              items: const [
                                DropdownMenuItem<String?>(
                                  value: null,
                                  child: Text('الجنس (اختياري)'),
                                ),
                                DropdownMenuItem(
                                  value: 'male',
                                  child: Text('ذكر'),
                                ),
                                DropdownMenuItem(
                                  value: 'female',
                                  child: Text('أنثى'),
                                ),
                                DropdownMenuItem(
                                  value: 'mixed',
                                  child: Text('مختلط'),
                                ),
                                DropdownMenuItem(
                                  value: 'not_applicable',
                                  child: Text('غير مهم'),
                                ),
                              ],
                              onChanged: (value) =>
                                  setState(() => _providerGender = value),
                              decoration: const InputDecoration(
                                labelText: 'جنس مقدم الخدمة',
                              ),
                            ),
                            const SizedBox(height: 10),
                            ImagePickerField(
                              title: 'الشعار / الصورة الشخصية',
                              selectedFile: _logoFile,
                              existingImageUrl: null,
                              onPick: () async {
                                final picked = await pickImageFromDevice();
                                if (picked == null || !mounted) return;
                                setState(() => _logoFile = picked);
                              },
                              onClear: _logoFile == null
                                  ? null
                                  : () => setState(() => _logoFile = null),
                            ),
                            const SizedBox(height: 8),
                            ImagePickerField(
                              title: 'صورة الغلاف',
                              selectedFile: _coverFile,
                              existingImageUrl: null,
                              onPick: () async {
                                final picked = await pickImageFromDevice();
                                if (picked == null || !mounted) return;
                                setState(() => _coverFile = picked);
                              },
                              onClear: _coverFile == null
                                  ? null
                                  : () => setState(() => _coverFile = null),
                            ),
                            const SizedBox(height: 16),
                            Wrap(
                              spacing: 10,
                              runSpacing: 10,
                              children: [
                                FilledButton.icon(
                                  onPressed: _submitting
                                      ? null
                                      : _submitRequest,
                                  icon: _submitting
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.verified_user_outlined,
                                        ),
                                  label: const Text('إرسال طلب الاشتراك'),
                                ),
                                OutlinedButton.icon(
                                  onPressed: _checkingStatus
                                      ? null
                                      : _checkSubscriptionStatus,
                                  icon: _checkingStatus
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(Icons.sync_rounded),
                                  label: const Text('التحقق من الحالة'),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            const Text(
                              'ملاحظة: العنوان التفصيلي اختياري. الاشتراك يتم بتسعير خاص من الأدمن، والاستلام نقدي خارج التطبيق.',
                              style: TextStyle(fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SubscriptionProgressCard extends StatelessWidget {
  final ServiceProviderSubscriptionProgressModel progress;
  final String statusLabel;
  final String statusHint;
  final VoidCallback? onAccept;
  final VoidCallback? onReject;
  final bool responding;

  const _SubscriptionProgressCard({
    required this.progress,
    required this.statusLabel,
    required this.statusHint,
    required this.onAccept,
    required this.onReject,
    required this.responding,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Colors.green.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'حالة الطلب: $statusLabel',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text('رقم الطلب: ${progress.requestCode}'),
            const SizedBox(height: 4),
            Text(statusHint),
            if (progress.activeOffer != null) ...[
              const Divider(height: 20),
              Text(
                'عرض الأدمن: ${progress.activeOffer!.amount?.toStringAsFixed(0) ?? '-'} ${progress.activeOffer!.currency}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              if ((progress.activeOffer!.title ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(progress.activeOffer!.title!),
                ),
              if ((progress.activeOffer!.description ?? '').trim().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(progress.activeOffer!.description!),
                ),
              if (progress.activeOffer!.validUntil != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    'صالح لغاية: ${progress.activeOffer!.validUntil}',
                  ),
                ),
            ],
            if (onAccept != null && onReject != null) ...[
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: responding ? null : onAccept,
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('موافقة على العرض'),
                  ),
                  OutlinedButton.icon(
                    onPressed: responding ? null : onReject,
                    icon: const Icon(Icons.close_rounded),
                    label: const Text('رفض العرض'),
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
