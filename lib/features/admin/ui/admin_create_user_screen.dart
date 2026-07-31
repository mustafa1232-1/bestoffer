import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../auth/presentation/widgets/basmaya_address_selector.dart';
import '../../merchants/models/store_activity_model.dart';
import '../state/admin_controller.dart';

enum _AdminCreateKind { user, store, taxiCaptain }

class AdminCreateUserScreen extends ConsumerStatefulWidget {
  const AdminCreateUserScreen({super.key});

  @override
  ConsumerState<AdminCreateUserScreen> createState() =>
      _AdminCreateUserScreenState();
}

class _AdminCreateUserScreenState extends ConsumerState<AdminCreateUserScreen> {
  final _formKey = GlobalKey<FormState>();

  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();

  final _merchantNameCtrl = TextEditingController();
  final _merchantPhoneCtrl = TextEditingController();
  final _merchantDescCtrl = TextEditingController();
  final _merchantServiceAreaCtrl = TextEditingController(text: 'Basmaya');
  final _commissionValueCtrl = TextEditingController(text: '10');
  final _monthlySubscriptionCtrl = TextEditingController(text: '0');
  final _serviceFeeValueCtrl = TextEditingController(text: '500');
  final _appDeliveryFeeCtrl = TextEditingController(text: '1000');
  final _storeDeliveryFeeCtrl = TextEditingController(text: '1000');

  final _vehicleTypeCtrl = TextEditingController(text: 'car');
  final _carMakeCtrl = TextEditingController();
  final _carModelCtrl = TextEditingController();
  final _carYearCtrl = TextEditingController();
  final _carColorCtrl = TextEditingController();
  final _plateNumberCtrl = TextEditingController();
  final _plateLetterCtrl = TextEditingController();
  final _plateGovernorateCtrl = TextEditingController(text: 'بغداد');
  final _plateCategoryCtrl = TextEditingController(text: 'خصوصي');

  _AdminCreateKind _kind = _AdminCreateKind.user;
  String _role = 'user';
  String _driverType = 'app_driver';
  int? _merchantId;
  bool _createReferralCoupon = false;
  bool _enableEmployeeManagement = false;

  String? _block = 'A1';
  String? _building;
  String? _apartment;
  String? _addressError;

  LocalImageFile? _profileImageFile;
  LocalImageFile? _merchantImageFile;
  LocalImageFile? _taxiProfileImageFile;
  LocalImageFile? _taxiCarImageFile;

  List<StoreActivityModel> _activities = const <StoreActivityModel>[];
  List<StoreDiscoveryOptionModel> _discoveryOptions =
      const <StoreDiscoveryOptionModel>[];
  String? _selectedActivityType;
  String? _selectedDiscoverySubcategory;
  bool _loadingActivities = false;
  bool _loadingDiscovery = false;

  String _commissionType = 'percentage';
  String _commissionModel = 'percentage';
  String _serviceFeeType = 'fixed';
  String _deliveryFeeMode = 'dynamic';

  bool get _showMerchantField =>
      _kind == _AdminCreateKind.user &&
      (_role == 'delivery' || _role == 'accountant' || _role == 'hr');

  bool get _merchantRequired =>
      _role == 'accountant' ||
      _role == 'hr' ||
      (_role == 'delivery' && _driverType == 'store_driver');

  StoreActivityModel? get _selectedActivity {
    for (final item in _activities) {
      if (item.activityType == _selectedActivityType) return item;
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _loadActivities();
  }

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _merchantNameCtrl.dispose();
    _merchantPhoneCtrl.dispose();
    _merchantDescCtrl.dispose();
    _merchantServiceAreaCtrl.dispose();
    _commissionValueCtrl.dispose();
    _monthlySubscriptionCtrl.dispose();
    _serviceFeeValueCtrl.dispose();
    _appDeliveryFeeCtrl.dispose();
    _storeDeliveryFeeCtrl.dispose();
    _vehicleTypeCtrl.dispose();
    _carMakeCtrl.dispose();
    _carModelCtrl.dispose();
    _carYearCtrl.dispose();
    _carColorCtrl.dispose();
    _plateNumberCtrl.dispose();
    _plateLetterCtrl.dispose();
    _plateGovernorateCtrl.dispose();
    _plateCategoryCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadActivities() async {
    setState(() => _loadingActivities = true);
    try {
      final raw = await ref
          .read(adminControllerProvider.notifier)
          .adminStoreActivities();
      final items = raw
          .whereType<Map>()
          .map(
            (item) =>
                StoreActivityModel.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _activities = items;
        _selectedActivityType ??= items.isNotEmpty
            ? items.first.activityType
            : null;
      });
      await _loadDiscoveryOptions(_selectedActivityType);
    } finally {
      if (mounted) setState(() => _loadingActivities = false);
    }
  }

  Future<void> _loadDiscoveryOptions(String? activityType) async {
    if (activityType == null || activityType.isEmpty) return;
    setState(() {
      _loadingDiscovery = true;
      _discoveryOptions = const <StoreDiscoveryOptionModel>[];
      _selectedDiscoverySubcategory = null;
    });
    try {
      final raw = await ref
          .read(adminApiProvider)
          .activityDiscoveryOptions(activityType);
      if (!mounted) return;
      setState(() {
        _discoveryOptions = raw
            .map(StoreDiscoveryOptionModel.fromJson)
            .toList(growable: false);
      });
    } finally {
      if (mounted) setState(() => _loadingDiscovery = false);
    }
  }

  bool _validateAddress() {
    final error = BasmayaAddressCatalog.validateSelection(
      block: _block,
      buildingNumber: _building,
      apartment: _apartment,
      l10n: context.l10n,
    );
    setState(() => _addressError = error);
    return error == null;
  }

  num _numberValue(TextEditingController controller) {
    return num.tryParse(controller.text.trim()) ?? 0;
  }

  Future<void> _pickImage(ValueChanged<LocalImageFile?> apply) async {
    final file = await pickImageFromDevice();
    if (!mounted || file == null) return;
    setState(() => apply(file));
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (!_validateAddress()) return;

    final controller = ref.read(adminControllerProvider.notifier);
    switch (_kind) {
      case _AdminCreateKind.user:
        await controller.createUser({
          'fullName': _fullNameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'pin': _pinCtrl.text.trim(),
          'block': _block,
          'buildingNumber': _building,
          'apartment': _apartment,
          'role': _role,
          if (_role == 'delivery') 'driverType': _driverType,
          if (_showMerchantField && _merchantId != null)
            'merchantId': _merchantId,
          if (_role != 'user') 'createReferralCoupon': _createReferralCoupon,
          if (_role == 'admin' || _role == 'deputy_admin')
            'enableEmployeeManagement': _enableEmployeeManagement,
        }, imageFile: _profileImageFile);
        break;
      case _AdminCreateKind.store:
        final activity = _selectedActivity;
        if (activity == null) return;
        final hasDiscovery = _discoveryOptions.isNotEmpty;
        final selectedDiscovery = _selectedDiscoverySubcategory?.trim();
        await controller.createStoreAccount({
          'fullName': _fullNameCtrl.text.trim().isEmpty
              ? _merchantNameCtrl.text.trim()
              : _fullNameCtrl.text.trim(),
          'phone': _phoneCtrl.text.trim(),
          'pin': _pinCtrl.text.trim(),
          'block': _block,
          'buildingNumber': _building,
          'apartment': _apartment,
          'merchantName': _merchantNameCtrl.text.trim(),
          'merchantPhone': _merchantPhoneCtrl.text.trim().isEmpty
              ? _phoneCtrl.text.trim()
              : _merchantPhoneCtrl.text.trim(),
          'merchantType': activity.baseType,
          'merchantActivityType': activity.activityType,
          'merchantDescription': _merchantDescCtrl.text.trim(),
          'merchantServiceAreaNote': _merchantServiceAreaCtrl.text.trim(),
          if (hasDiscovery && selectedDiscovery != null)
            'merchantDiscoverySubcategory': selectedDiscovery,
          if (hasDiscovery && selectedDiscovery != null)
            'merchantDiscoverySubcategories': <String>[selectedDiscovery],
          if (hasDiscovery)
            'merchantDiscoverySelectAll': selectedDiscovery == null,
          'merchantServiceFlags': activity.defaultServiceFlags,
          'merchantBadges': activity.defaultBadges,
          'merchantSupportsChat': activity.supportsChat,
          'merchantSupportsAttachments': activity.supportsAttachments,
          'merchantSupportsPharmacyWorkflow': activity.supportsPharmacyWorkflow,
          'financialTerms': {
            'commissionType': _commissionType,
            'commissionValue': _numberValue(_commissionValueCtrl),
            'commissionModel': _commissionModel,
            'monthlySubscriptionAmount': _numberValue(_monthlySubscriptionCtrl),
            'serviceFeeType': _serviceFeeType,
            'serviceFeeValue': _numberValue(_serviceFeeValueCtrl),
            'deliveryFeeMode': _deliveryFeeMode,
            'appDeliveryFeeValue': _numberValue(_appDeliveryFeeCtrl),
            'storeDeliveryFeeValue': _numberValue(_storeDeliveryFeeCtrl),
            'effectiveFrom': DateTime.now().toUtc().toIso8601String(),
          },
        }, merchantImageFile: _merchantImageFile);
        break;
      case _AdminCreateKind.taxiCaptain:
        await controller.createTaxiCaptainAccount(
          {
            'fullName': _fullNameCtrl.text.trim(),
            'phone': _phoneCtrl.text.trim(),
            'pin': _pinCtrl.text.trim(),
            'block': _block,
            'buildingNumber': _building,
            'apartment': _apartment,
            'vehicleType': _vehicleTypeCtrl.text.trim(),
            'carMake': _carMakeCtrl.text.trim(),
            'carModel': _carModelCtrl.text.trim(),
            'carYear': int.tryParse(_carYearCtrl.text.trim()),
            'carColor': _carColorCtrl.text.trim(),
            'plateNumber': _plateNumberCtrl.text.trim(),
            'plateLetter': _plateLetterCtrl.text.trim(),
            'plateGovernorate': _plateGovernorateCtrl.text.trim(),
            'plateCategory': _plateCategoryCtrl.text.trim(),
          },
          profileImageFile: _taxiProfileImageFile,
          carImageFile: _taxiCarImageFile,
        );
        break;
    }

    final next = ref.read(adminControllerProvider);
    if (!mounted) return;
    if (next.error == null) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final merchants = state.managedMerchants;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.adminCreateUserTitle)),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SegmentedButton<_AdminCreateKind>(
                segments: const [
                  ButtonSegment(
                    value: _AdminCreateKind.user,
                    icon: Icon(Icons.person_add_alt_1_rounded),
                    label: Text('مستخدم / موظف'),
                  ),
                  ButtonSegment(
                    value: _AdminCreateKind.store,
                    icon: Icon(Icons.storefront_rounded),
                    label: Text('متجر'),
                  ),
                  ButtonSegment(
                    value: _AdminCreateKind.taxiCaptain,
                    icon: Icon(Icons.local_taxi_rounded),
                    label: Text('كابتن'),
                  ),
                ],
                selected: {_kind},
                onSelectionChanged: (value) =>
                    setState(() => _kind = value.first),
              ),
              const SizedBox(height: 16),
              if (state.error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(state.error!),
                ),
              _SectionTitle(
                icon: Icons.badge_outlined,
                title: _kind == _AdminCreateKind.store
                    ? 'بيانات صاحب المتجر'
                    : 'بيانات الحساب',
                subtitle:
                    'هذه البيانات تطابق حقول التسجيل العادية، لكن الاعتماد يتم من الأدمن مباشرة.',
              ),
              _requiredTextField(
                controller: _fullNameCtrl,
                label: l10n.adminCreateUserFullName,
                error: l10n.adminCreateUserNameRequired,
              ),
              const SizedBox(height: 12),
              _requiredTextField(
                controller: _phoneCtrl,
                label: l10n.authPhoneLabel,
                error: l10n.adminCreateUserPhoneRequired,
                keyboardType: TextInputType.phone,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: InputDecoration(labelText: l10n.authPinLabel),
                validator: (value) {
                  final pin = (value ?? '').trim();
                  if (pin.isEmpty) return l10n.adminCreateUserPinRequired;
                  if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
                    return l10n.authPinInvalidFormat;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              if (_kind == _AdminCreateKind.user) ...[
                ImagePickerField(
                  title: 'صورة الحساب',
                  selectedFile: _profileImageFile,
                  existingImageUrl: null,
                  onPick: () => _pickImage((file) => _profileImageFile = file),
                  onClear: _profileImageFile == null
                      ? null
                      : () => setState(() => _profileImageFile = null),
                  helperText: 'اختياري، مثل صورة المستخدم في التسجيل العادي.',
                ),
                const SizedBox(height: 12),
                _buildRoleFields(l10n, merchants),
              ],
              BasmayaAddressSelector(
                selectedBlock: _block,
                selectedBuilding: _building,
                selectedApartment: _apartment,
                onBlockChanged: (value) => setState(() {
                  _block = value;
                  _building = null;
                  _apartment = null;
                  _addressError = null;
                }),
                onBuildingChanged: (value) => setState(() {
                  _building = value;
                  _apartment = null;
                  _addressError = null;
                }),
                onApartmentChanged: (value) => setState(() {
                  _apartment = value;
                  _addressError = null;
                }),
                generalError: _addressError,
              ),
              if (_kind == _AdminCreateKind.store) _buildStoreFields(),
              if (_kind == _AdminCreateKind.taxiCaptain) _buildTaxiFields(),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: state.saving ? null : _submit,
                icon: state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(_submitLabel(l10n.adminCreateUserCreateButton)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRoleFields(dynamic l10n, List<dynamic> merchants) {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _role,
          decoration: InputDecoration(labelText: l10n.adminCreateUserRole),
          items: [
            DropdownMenuItem(
              value: 'user',
              child: Text(l10n.adminCreateUserCustomerRole),
            ),
            DropdownMenuItem(
              value: 'owner',
              child: Text(l10n.adminCreateUserOwnerRole),
            ),
            DropdownMenuItem(
              value: 'delivery',
              child: Text(l10n.adminCreateUserDeliveryRole),
            ),
            DropdownMenuItem(
              value: 'accountant',
              child: Text(l10n.adminCreateUserAccountantRole),
            ),
            DropdownMenuItem(
              value: 'hr',
              child: Text(l10n.adminCreateUserHrRole),
            ),
            DropdownMenuItem(
              value: 'deputy_admin',
              child: Text(l10n.adminCreateUserDeputyAdminRole),
            ),
            DropdownMenuItem(
              value: 'call_center',
              child: Text(l10n.adminCreateUserCallCenterRole),
            ),
            DropdownMenuItem(
              value: 'admin',
              child: Text(l10n.adminCreateUserAdminRole),
            ),
          ],
          onChanged: (value) {
            setState(() {
              _role = value ?? 'user';
              if (_role != 'delivery') _driverType = 'app_driver';
              if (!_showMerchantField) _merchantId = null;
            });
          },
        ),
        if (_role != 'user') ...[
          const SizedBox(height: 8),
          SwitchListTile.adaptive(
            contentPadding: EdgeInsets.zero,
            value: _createReferralCoupon,
            onChanged: (value) =>
                setState(() => _createReferralCoupon = value),
            title: const Text('أنشئ كوبون إحالة لهذا الموظف'),
            subtitle: const Text(
              'كوبون عام باسم الموظف لتتبّع الزبائن الذين يأتون عبره. بلا خصم افتراضيًا، ويمكنك إضافة خصم لاحقًا من شاشة المراقبة. يصل الموظف إشعار بكوبونه.',
            ),
          ),
        ],
        if (_role == 'admin' || _role == 'deputy_admin') ...[
          const SizedBox(height: 8),
          Card(
            color: Theme.of(context).colorScheme.primaryContainer.withValues(
              alpha: 0.35,
            ),
            child: SwitchListTile.adaptive(
              value: _enableEmployeeManagement,
              onChanged: (value) =>
                  setState(() => _enableEmployeeManagement = value),
              title: const Text(
                'تفعيل إنشاء حسابات الموظفين وصلاحياتهم',
                style: TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text(
                'يمنح هذا الأدمن القدرة على إنشاء حسابات موظفين جدد وتعديل صلاحياتهم مباشرةً. (متاح للسوبر أدمن فقط عند الإنشاء.)',
              ),
            ),
          ),
        ],
        if (_role == 'delivery') ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _driverType,
            decoration: InputDecoration(
              labelText: l10n.adminCreateUserDriverType,
              helperText: _driverType == 'store_driver'
                  ? l10n.adminCreateUserStoreDriverHelper
                  : l10n.adminCreateUserAppDriverHelper,
            ),
            items: [
              DropdownMenuItem(
                value: 'app_driver',
                child: Text(l10n.adminCreateUserAppDriver),
              ),
              DropdownMenuItem(
                value: 'store_driver',
                child: Text(l10n.adminCreateUserStoreDriver),
              ),
            ],
            onChanged: (value) {
              setState(() => _driverType = value ?? 'app_driver');
            },
          ),
        ],
        if (_showMerchantField) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<int>(
            initialValue: _merchantId,
            decoration: InputDecoration(
              labelText: _merchantRequired
                  ? l10n.adminCreateUserAssignedMerchant
                  : l10n.adminCreateUserAssignedMerchantOptional,
            ),
            items: merchants
                .map(
                  (item) => DropdownMenuItem<int>(
                    value: item.id as int,
                    child: Text('${item.name}'),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) => setState(() => _merchantId = value),
            validator: (value) {
              if (_merchantRequired && value == null) {
                return l10n.adminCreateUserMerchantRequired;
              }
              return null;
            },
          ),
        ],
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildStoreFields() {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    final activity = _selectedActivity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const _SectionTitle(
          icon: Icons.storefront_rounded,
          title: 'بيانات المتجر والقسم',
          subtitle:
              'اختر القسم الصحيح حتى يظهر المتجر في السوق وداخل فلاتر القسم مباشرة.',
        ),
        _requiredTextField(
          controller: _merchantNameCtrl,
          label: 'اسم المتجر',
          error: 'أدخل اسم المتجر.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _merchantPhoneCtrl,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            labelText: 'هاتف المتجر',
            helperText: 'اتركه فارغاً لاستخدام هاتف صاحب المتجر.',
          ),
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _merchantDescCtrl,
          minLines: 2,
          maxLines: 4,
          decoration: const InputDecoration(labelText: 'وصف المتجر'),
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'أدخل وصفاً واضحاً للمتجر.' : null,
        ),
        const SizedBox(height: 12),
        if (_loadingActivities)
          const LinearProgressIndicator()
        else
          DropdownButtonFormField<String>(
            initialValue: _selectedActivityType,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'قسم السوق'),
            items: _activities
                .map(
                  (item) => DropdownMenuItem(
                    value: item.activityType,
                    child: Text(item.localizedLabel(isArabic)),
                  ),
                )
                .toList(growable: false),
            onChanged: (value) {
              setState(() => _selectedActivityType = value);
              _loadDiscoveryOptions(value);
            },
            validator: (value) =>
                value == null || value.isEmpty ? 'اختر قسم السوق.' : null,
          ),
        if (_loadingDiscovery) ...[
          const SizedBox(height: 12),
          const LinearProgressIndicator(),
        ] else if (_discoveryOptions.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedDiscoverySubcategory,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'القسم الفرعي',
              helperText:
                  'اتركه على الكل إذا كان المتجر يجب أن يظهر في كامل القسم.',
            ),
            items: [
              const DropdownMenuItem<String>(
                value: null,
                child: Text('كل الأقسام الفرعية'),
              ),
              ..._discoveryOptions.map(
                (item) => DropdownMenuItem<String>(
                  value: item.code,
                  child: Text(item.localizedLabel(isArabic)),
                ),
              ),
            ],
            onChanged: (value) =>
                setState(() => _selectedDiscoverySubcategory = value),
          ),
        ],
        const SizedBox(height: 12),
        TextFormField(
          controller: _merchantServiceAreaCtrl,
          decoration: const InputDecoration(labelText: 'منطقة خدمة المتجر'),
        ),
        const SizedBox(height: 12),
        ImagePickerField(
          title: 'صورة المتجر',
          selectedFile: _merchantImageFile,
          existingImageUrl: null,
          onPick: () => _pickImage((file) => _merchantImageFile = file),
          onClear: _merchantImageFile == null
              ? null
              : () => setState(() => _merchantImageFile = null),
          helperText: activity == null
              ? null
              : 'سيظهر كمتجر ${activity.localizedLabel(isArabic)} بعد الإنشاء مباشرة.',
        ),
        const SizedBox(height: 18),
        const _SectionTitle(
          icon: Icons.payments_outlined,
          title: 'الاتفاق المالي المباشر',
          subtitle:
              'هذه الشروط يحددها الأدمن الآن، ولا ينتظر المتجر موافقة لاحقة.',
        ),
        _buildFinancialTermsFields(),
      ],
    );
  }

  Widget _buildFinancialTermsFields() {
    return Column(
      children: [
        DropdownButtonFormField<String>(
          initialValue: _commissionModel,
          decoration: const InputDecoration(labelText: 'نموذج العمولة'),
          items: const [
            DropdownMenuItem(
              value: 'percentage',
              child: Text('نسبة من المبيعات'),
            ),
            DropdownMenuItem(
              value: 'monthly_subscription',
              child: Text('اشتراك شهري'),
            ),
          ],
          onChanged: (value) => setState(() {
            _commissionModel = value ?? 'percentage';
            if (_commissionModel == 'monthly_subscription') {
              _commissionType = 'fixed';
            }
          }),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _commissionType,
          decoration: const InputDecoration(labelText: 'نوع قيمة العمولة'),
          items: const [
            DropdownMenuItem(value: 'percentage', child: Text('نسبة مئوية')),
            DropdownMenuItem(value: 'fixed', child: Text('مبلغ ثابت')),
          ],
          onChanged: (value) =>
              setState(() => _commissionType = value ?? 'percentage'),
        ),
        const SizedBox(height: 12),
        _requiredNumberField(
          controller: _commissionValueCtrl,
          label: 'قيمة العمولة',
        ),
        const SizedBox(height: 12),
        _requiredNumberField(
          controller: _monthlySubscriptionCtrl,
          label: 'قيمة الاشتراك الشهري',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _serviceFeeType,
          decoration: const InputDecoration(labelText: 'نوع رسوم الخدمة'),
          items: const [
            DropdownMenuItem(value: 'fixed', child: Text('مبلغ ثابت')),
            DropdownMenuItem(value: 'percentage', child: Text('نسبة مئوية')),
          ],
          onChanged: (value) =>
              setState(() => _serviceFeeType = value ?? 'fixed'),
        ),
        const SizedBox(height: 12),
        _requiredNumberField(
          controller: _serviceFeeValueCtrl,
          label: 'قيمة رسوم الخدمة',
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          initialValue: _deliveryFeeMode,
          decoration: const InputDecoration(labelText: 'نظام رسوم التوصيل'),
          items: const [
            DropdownMenuItem(value: 'dynamic', child: Text('توصيل ديناميكي')),
            DropdownMenuItem(value: 'fixed', child: Text('توصيل ثابت')),
          ],
          onChanged: (value) =>
              setState(() => _deliveryFeeMode = value ?? 'dynamic'),
        ),
        const SizedBox(height: 12),
        _requiredNumberField(
          controller: _appDeliveryFeeCtrl,
          label: 'رسوم توصيل التطبيق',
        ),
        const SizedBox(height: 12),
        _requiredNumberField(
          controller: _storeDeliveryFeeCtrl,
          label: 'رسوم توصيل المتجر',
        ),
      ],
    );
  }

  Widget _buildTaxiFields() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: 18),
        const _SectionTitle(
          icon: Icons.local_taxi_rounded,
          title: 'بيانات الكابتن والمركبة',
          subtitle:
              'الحساب يعتمد مباشرة بعد الإنشاء من الأدمن بدون انتظار موافقة.',
        ),
        ImagePickerField(
          title: 'صورة الكابتن',
          selectedFile: _taxiProfileImageFile,
          existingImageUrl: null,
          onPick: () => _pickImage((file) => _taxiProfileImageFile = file),
          onClear: _taxiProfileImageFile == null
              ? null
              : () => setState(() => _taxiProfileImageFile = null),
        ),
        const SizedBox(height: 12),
        ImagePickerField(
          title: 'صورة السيارة',
          selectedFile: _taxiCarImageFile,
          existingImageUrl: null,
          onPick: () => _pickImage((file) => _taxiCarImageFile = file),
          onClear: _taxiCarImageFile == null
              ? null
              : () => setState(() => _taxiCarImageFile = null),
        ),
        const SizedBox(height: 12),
        _requiredTextField(
          controller: _vehicleTypeCtrl,
          label: 'نوع المركبة',
          error: 'أدخل نوع المركبة.',
        ),
        const SizedBox(height: 12),
        _requiredTextField(
          controller: _carMakeCtrl,
          label: 'الشركة المصنعة',
          error: 'أدخل الشركة المصنعة.',
        ),
        const SizedBox(height: 12),
        _requiredTextField(
          controller: _carModelCtrl,
          label: 'الموديل',
          error: 'أدخل موديل السيارة.',
        ),
        const SizedBox(height: 12),
        _requiredNumberField(controller: _carYearCtrl, label: 'سنة الصنع'),
        const SizedBox(height: 12),
        _requiredTextField(
          controller: _carColorCtrl,
          label: 'لون السيارة',
          error: 'أدخل لون السيارة.',
        ),
        const SizedBox(height: 12),
        _requiredTextField(
          controller: _plateNumberCtrl,
          label: 'رقم اللوحة',
          error: 'أدخل رقم اللوحة.',
        ),
        const SizedBox(height: 12),
        TextFormField(
          controller: _plateLetterCtrl,
          decoration: const InputDecoration(labelText: 'حرف اللوحة'),
        ),
        const SizedBox(height: 12),
        _requiredTextField(
          controller: _plateGovernorateCtrl,
          label: 'مدينة اللوحة',
          error: 'أدخل مدينة اللوحة.',
        ),
        const SizedBox(height: 12),
        _requiredTextField(
          controller: _plateCategoryCtrl,
          label: 'نوع اللوحة',
          error: 'أدخل نوع اللوحة.',
        ),
      ],
    );
  }

  Widget _requiredTextField({
    required TextEditingController controller,
    required String label,
    required String error,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(labelText: label),
      validator: (value) => (value ?? '').trim().isEmpty ? error : null,
    );
  }

  Widget _requiredNumberField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label),
      validator: (value) {
        final text = (value ?? '').trim();
        if (text.isEmpty) return 'أدخل $label.';
        if (num.tryParse(text) == null) return 'أدخل رقماً صحيحاً.';
        return null;
      },
    );
  }

  String _submitLabel(String fallback) {
    return switch (_kind) {
      _AdminCreateKind.user => fallback,
      _AdminCreateKind.store => 'إنشاء المتجر واعتماده',
      _AdminCreateKind.taxiCaptain => 'إنشاء الكابتن واعتماده',
    };
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(
            alpha: 0.45,
          ),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
