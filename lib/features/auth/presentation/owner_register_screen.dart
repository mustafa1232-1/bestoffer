// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/forms/backend_field_error_parser.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../merchants/models/store_activity_model.dart';
import '../../merchants/state/merchants_controller.dart';
import '../state/auth_controller.dart';
import 'widgets/basmaya_address_selector.dart';

enum _OwnerRegisterStep { activitySelection, merchantDetails }

class OwnerRegisterScreen extends ConsumerStatefulWidget {
  const OwnerRegisterScreen({super.key});

  @override
  ConsumerState<OwnerRegisterScreen> createState() =>
      _OwnerRegisterScreenState();
}

class _OwnerRegisterScreenState extends ConsumerState<OwnerRegisterScreen> {
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final merchantNameCtrl = TextEditingController();
  final merchantDescCtrl = TextEditingController();
  final merchantPhoneCtrl = TextEditingController();
  final merchantServiceAreaNoteCtrl = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();

  _OwnerRegisterStep _step = _OwnerRegisterStep.activitySelection;
  List<StoreActivityModel> _activities = const <StoreActivityModel>[];
  List<StoreDiscoveryOptionModel> _discoveryOptions =
      const <StoreDiscoveryOptionModel>[];
  bool _loadingActivities = false;
  bool _loadingDiscoveryOptions = false;
  String? _selectedActivityType;
  final Set<String> _selectedDiscoverySubcategories = <String>{};
  bool _discoverySelectAll = false;
  String? selectedBlock;
  String? selectedBuilding;
  String? selectedApartment;
  LocalImageFile? merchantImageFile;
  bool analyticsConsentAccepted = false;
  final Map<String, String?> _fieldErrors = <String, String?>{};
  String? _addressError;
  String? _consentError;
  String? _formError;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadActivities);
  }

  StoreActivityModel? get _selectedActivity {
    final selected = _selectedActivityType;
    if (selected == null || selected.isEmpty) return null;
    for (final activity in _activities) {
      if (activity.activityType == selected) return activity;
    }
    return null;
  }

  String get _resolvedMerchantType => _selectedActivity?.baseType ?? 'market';

  Future<void> _loadActivities() async {
    if (_loadingActivities) return;
    setState(() => _loadingActivities = true);
    try {
      final items = await ref
          .read(merchantsControllerProvider.notifier)
          .listActivities();
      if (!mounted) return;
      final selected = _selectedActivityType;
      final hasSelected =
          selected != null &&
          items.any((item) => item.activityType == selected);
      setState(() {
        _activities = items;
        if (!hasSelected) _selectedActivityType = null;
      });
      if (_selectedActivityType != null) {
        await _loadDiscoveryOptions(_selectedActivityType!);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _activities = const <StoreActivityModel>[];
        _selectedActivityType = null;
        _selectedDiscoverySubcategories.clear();
        _discoverySelectAll = false;
        _discoveryOptions = const <StoreDiscoveryOptionModel>[];
      });
    } finally {
      if (mounted) {
        setState(() => _loadingActivities = false);
      }
    }
  }

  Future<void> _loadDiscoveryOptions(String activityType) async {
    StoreActivityModel? activity;
    for (final item in _activities) {
      if (item.activityType == activityType) {
        activity = item;
        break;
      }
    }
    if (activity == null || !activity.hasDiscoverySubcategories) {
      if (!mounted) return;
      setState(() {
        _discoveryOptions = const <StoreDiscoveryOptionModel>[];
        _selectedDiscoverySubcategories.clear();
        _discoverySelectAll = false;
      });
      return;
    }
    setState(() => _loadingDiscoveryOptions = true);
    try {
      final options = await ref
          .read(merchantsControllerProvider.notifier)
          .listDiscoveryOptions(activityType: activityType);
      if (!mounted) return;
      setState(() {
        _discoveryOptions = options;
        final optionCodes = options.map((option) => option.code).toSet();
        _selectedDiscoverySubcategories.removeWhere(
          (value) => !optionCodes.contains(value),
        );
        if (options.isEmpty) {
          _selectedDiscoverySubcategories.clear();
          _discoverySelectAll = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _discoveryOptions = const <StoreDiscoveryOptionModel>[];
        _selectedDiscoverySubcategories.clear();
        _discoverySelectAll = false;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingDiscoveryOptions = false);
      }
    }
  }

  void _moveToMerchantDetailsStep() {
    final l10n = context.l10n;
    final activity = _selectedActivity;
    final nextErrors = <String, String?>{};
    if (activity == null) {
      nextErrors['merchantActivityType'] = resolveFormFieldError(
        l10n: l10n,
        field: 'merchantActivityType',
        fieldLabel: _fieldLabel(context, 'merchantActivityType'),
      );
    } else if (activity.hasDiscoverySubcategories &&
        !_discoverySelectAll &&
        _selectedDiscoverySubcategories.isEmpty) {
      nextErrors['merchantDiscoverySubcategory'] = resolveFormFieldError(
        l10n: l10n,
        field: 'merchantDiscoverySubcategory',
        fieldLabel: _fieldLabel(context, 'merchantDiscoverySubcategory'),
      );
    }
    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(nextErrors);
        _formError = l10n.validationReviewRequiredFields;
      });
      _scrollCoordinator.focusFirstError(nextErrors.keys);
      return;
    }
    setState(() {
      _fieldErrors.remove('merchantActivityType');
      _fieldErrors.remove('merchantDiscoverySubcategory');
      _formError = null;
      _step = _OwnerRegisterStep.merchantDetails;
    });
  }

  void _backToActivityStep() {
    setState(() {
      _step = _OwnerRegisterStep.activitySelection;
      _formError = null;
      _fieldErrors.remove('merchantActivityType');
      _fieldErrors.remove('merchantDiscoverySubcategory');
    });
  }

  @override
  void dispose() {
    phoneCtrl.dispose();
    pinCtrl.dispose();
    merchantNameCtrl.dispose();
    merchantDescCtrl.dispose();
    merchantPhoneCtrl.dispose();
    merchantServiceAreaNoteCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _errorOf(String key) => _fieldErrors[key];

  String _mapBackendField(String field) {
    switch (field.trim()) {
      case 'activityType':
        return 'merchantActivityType';
      case 'discoverySubcategory':
      case 'discoverySubcategories':
        return 'merchantDiscoverySubcategory';
      default:
        return field.trim();
    }
  }

  void _clearFieldError(String key) {
    if (!_fieldErrors.containsKey(key) &&
        _addressError == null &&
        _consentError == null &&
        _formError == null) {
      return;
    }
    setState(() {
      _fieldErrors.remove(key);
      if (key == 'block' || key == 'buildingNumber' || key == 'apartment') {
        _addressError = null;
      }
      if (key == 'analyticsConsentAccepted') {
        _consentError = null;
      }
      _formError = null;
    });
  }

  String _fieldLabel(BuildContext context, String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'phone':
        return l10n.ownerRegisterLoginPhoneLabel;
      case 'pin':
        return l10n.ownerRegisterPinLabel;
      case 'merchantName':
        return l10n.ownerRegisterMerchantNameLabel;
      case 'merchantDescription':
        return l10n.ownerRegisterMerchantDescriptionLabel;
      case 'merchantPhone':
        return l10n.ownerRegisterContactPhoneLabel;
      case 'merchantServiceAreaNote':
        return l10n.ownerRegisterServiceAreaLabel;
      case 'merchantActivityType':
        return l10n.addMerchantActivityTypeLabel;
      case 'merchantDiscoverySubcategory':
        return l10n.addMerchantDiscoverySubcategoryLabel;
      case 'block':
        return l10n.basmayaSectorLabel;
      case 'buildingNumber':
        return l10n.basmayaBuildingLabel;
      case 'apartment':
        return l10n.basmayaApartmentLabel;
      case 'analyticsConsent':
      case 'analyticsConsentAccepted':
        return l10n.ownerRegisterConsentCheckbox;
      default:
        return field;
    }
  }

  String? _validatePhone(
    String value, {
    required String requiredMessage,
    required String invalidMessage,
    bool required = true,
  }) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      if (!required) return null;
      return requiredMessage;
    }
    if (digits.length < 10) {
      return invalidMessage;
    }
    return null;
  }

  String? _validatePin(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.ownerRegisterPinRequired;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(trimmed)) {
      return context.l10n.ownerRegisterPinInvalid;
    }
    return null;
  }

  bool _validateForm(BuildContext context) {
    final l10n = context.l10n;
    final nextErrors = <String, String?>{};
    final selectedActivity = _selectedActivity;

    if (selectedActivity == null) {
      nextErrors['merchantActivityType'] = resolveFormFieldError(
        l10n: l10n,
        field: 'merchantActivityType',
        fieldLabel: _fieldLabel(context, 'merchantActivityType'),
      );
    } else if (selectedActivity.hasDiscoverySubcategories &&
        !_discoverySelectAll &&
        _selectedDiscoverySubcategories.isEmpty) {
      nextErrors['merchantDiscoverySubcategory'] = resolveFormFieldError(
        l10n: l10n,
        field: 'merchantDiscoverySubcategory',
        fieldLabel: _fieldLabel(context, 'merchantDiscoverySubcategory'),
      );
    }

    if (merchantNameCtrl.text.trim().isEmpty) {
      nextErrors['merchantName'] = l10n.ownerRegisterMerchantNameRequired;
    }
    if (merchantDescCtrl.text.trim().isEmpty) {
      nextErrors['merchantDescription'] =
          l10n.ownerRegisterMerchantDescriptionRequired;
    }

    nextErrors['phone'] = _validatePhone(
      phoneCtrl.text.trim(),
      requiredMessage: l10n.ownerRegisterLoginPhoneRequired,
      invalidMessage: l10n.ownerRegisterLoginPhoneInvalid,
    );
    nextErrors['pin'] = _validatePin(context, pinCtrl.text);
    nextErrors['merchantPhone'] = _validatePhone(
      merchantPhoneCtrl.text.trim(),
      requiredMessage: l10n.ownerRegisterContactPhoneRequired,
      invalidMessage: l10n.ownerRegisterContactPhoneInvalid,
      required: merchantPhoneCtrl.text.trim().isNotEmpty,
    );

    final hasAnyAddress =
        ((selectedBlock ?? '').trim().isNotEmpty) ||
        ((selectedBuilding ?? '').trim().isNotEmpty) ||
        ((selectedApartment ?? '').trim().isNotEmpty);

    final nextAddressError = hasAnyAddress
        ? BasmayaAddressCatalog.validateSelection(
            block: selectedBlock,
            buildingNumber: selectedBuilding,
            apartment: selectedApartment,
            l10n: l10n,
          )
        : null;
    final nextConsentError = analyticsConsentAccepted
        ? null
        : l10n.ownerRegisterConsentRequired;

    nextErrors.removeWhere((_, value) => value == null);
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(nextErrors);
      _addressError = nextAddressError;
      _consentError = nextConsentError;
      _formError =
          nextErrors.isEmpty &&
              nextAddressError == null &&
              nextConsentError == null
          ? null
          : l10n.validationReviewRequiredFields;
    });
    return nextErrors.isEmpty &&
        nextAddressError == null &&
        nextConsentError == null;
  }

  Future<void> _focusFirstError() async {
    final hasAddressError =
        _errorOf('block') != null ||
        _errorOf('buildingNumber') != null ||
        _errorOf('apartment') != null ||
        _addressError != null;
    final ordered = <String>[
      if (_errorOf('merchantActivityType') != null) 'merchantActivityType',
      if (_errorOf('merchantDiscoverySubcategory') != null)
        'merchantDiscoverySubcategory',
      if (_errorOf('phone') != null) 'phone',
      if (_errorOf('pin') != null) 'pin',
      if (_errorOf('merchantName') != null) 'merchantName',
      if (_errorOf('merchantDescription') != null) 'merchantDescription',
      if (_errorOf('merchantPhone') != null) 'merchantPhone',
      if (_errorOf('merchantServiceAreaNote') != null)
        'merchantServiceAreaNote',
      if (hasAddressError) 'block',
      if (_consentError != null) 'analyticsConsentAccepted',
    ];
    await _scrollCoordinator.focusFirstError(ordered);
  }

  Future<bool> _applyBackendErrors(AuthState auth) async {
    final parsed = auth.validationError ?? const ParsedBackendFieldErrors();
    final fieldCodes = <String, String?>{...parsed.fieldCodes};
    final topLevelCode = auth.errorCode?.trim().toUpperCase();
    if (!fieldCodes.containsKey('phone') && topLevelCode == 'PHONE_EXISTS') {
      fieldCodes['phone'] = 'PHONE_EXISTS';
    }

    final nextErrors = <String, String?>{};
    for (final entry in fieldCodes.entries) {
      final field = _mapBackendField(entry.key);
      final code = entry.value ?? topLevelCode;
      if (field == 'analyticsConsentAccepted') {
        nextErrors[field] = resolveFormFieldError(
          l10n: context.l10n,
          field: field,
          code: code,
          fieldLabel: _fieldLabel(context, field),
        );
        continue;
      }

      nextErrors[field] = resolveFormFieldError(
        l10n: context.l10n,
        field: field,
        code: code,
        fieldLabel: _fieldLabel(context, field),
      );
    }

    if (nextErrors.isEmpty &&
        (parsed.formCode == null || parsed.formCode!.isEmpty) &&
        topLevelCode != 'PHONE_EXISTS') {
      return false;
    }

    final fieldErrors = <String, String?>{
      for (final entry in nextErrors.entries)
        if (entry.key != 'analyticsConsentAccepted') entry.key: entry.value,
    };

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(fieldErrors);
      _addressError = parsed.formCode == 'ADDRESS_INVALID'
          ? resolveFormLevelError(context.l10n, code: parsed.formCode)
          : null;
      _consentError = nextErrors['analyticsConsentAccepted'];
      _formError = nextErrors.isNotEmpty
          ? context.l10n.validationReviewRequiredFields
          : resolveFormLevelError(
              context.l10n,
              code: parsed.formCode ?? topLevelCode,
              fallback: auth.error,
            );
    });
    await _focusFirstError();
    return true;
  }

  String _activityLabel(StoreActivityModel activity) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return activity.localizedLabel(isArabic);
  }

  String _discoveryLabel(StoreDiscoveryOptionModel option) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return option.localizedLabel(isArabic);
  }

  Widget _buildActivityStep(BuildContext context) {
    final l10n = context.l10n;
    final selectedActivity = _selectedActivity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          l10n.addMerchantActivityTypeLabel,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 16,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.ownerRegisterDescription,
          style: TextStyle(
            color: Colors.white.withOpacity(0.78),
            fontSize: 12.5,
          ),
        ),
        const SizedBox(height: 12),
        if (_loadingActivities)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: LinearProgressIndicator(minHeight: 2),
          )
        else if (_activities.isEmpty)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.commonTryAgainLater,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _loadActivities,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonRetry),
              ),
            ],
          )
        else
          _scrollCoordinator.anchor(
            'merchantActivityType',
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _activities
                  .map((activity) {
                    return ChoiceChip(
                      label: Text(_activityLabel(activity)),
                      selected: _selectedActivityType == activity.activityType,
                      onSelected: (_) async {
                        setState(() {
                          _selectedActivityType = activity.activityType;
                          _selectedDiscoverySubcategories.clear();
                          _discoverySelectAll = false;
                          _fieldErrors.remove('merchantActivityType');
                          _fieldErrors.remove('merchantDiscoverySubcategory');
                          _formError = null;
                        });
                        await _loadDiscoveryOptions(activity.activityType);
                      },
                    );
                  })
                  .toList(growable: false),
            ),
          ),
        if (_errorOf('merchantActivityType') != null) ...[
          const SizedBox(height: 6),
          Text(
            _errorOf('merchantActivityType')!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ],
        if (selectedActivity != null &&
            selectedActivity.hasDiscoverySubcategories) ...[
          const SizedBox(height: 12),
          _scrollCoordinator.anchor(
            'merchantDiscoverySubcategory',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l10n.addMerchantDiscoverySubcategoriesLabel,
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  value: _discoverySelectAll,
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: Text(l10n.addMerchantDiscoverySelectAllLabel),
                  subtitle: Text(
                    l10n.addMerchantDiscoverySelectAllHint,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onChanged: (value) {
                    setState(() {
                      _discoverySelectAll = value == true;
                      if (_discoverySelectAll) {
                        _selectedDiscoverySubcategories.clear();
                      }
                      _fieldErrors.remove('merchantDiscoverySubcategory');
                      _formError = null;
                    });
                  },
                ),
                if (!_discoverySelectAll && _discoveryOptions.isNotEmpty)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _discoveryOptions
                        .map((option) {
                          final selected = _selectedDiscoverySubcategories
                              .contains(option.code);
                          return FilterChip(
                            label: Text(_discoveryLabel(option)),
                            selected: selected,
                            onSelected: (isSelected) {
                              setState(() {
                                if (isSelected) {
                                  _selectedDiscoverySubcategories.add(
                                    option.code,
                                  );
                                } else {
                                  _selectedDiscoverySubcategories.remove(
                                    option.code,
                                  );
                                }
                                _fieldErrors.remove(
                                  'merchantDiscoverySubcategory',
                                );
                                _formError = null;
                              });
                            },
                          );
                        })
                        .toList(growable: false),
                  ),
                if (_errorOf('merchantDiscoverySubcategory') != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _errorOf('merchantDiscoverySubcategory')!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (_loadingDiscoveryOptions)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(minHeight: 2),
            ),
        ],
        const SizedBox(height: 14),
        ElevatedButton.icon(
          onPressed: _moveToMerchantDetailsStep,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: Text(l10n.commonContinue),
        ),
      ],
    );
  }

  Future<void> _submitRegistration(AuthState auth) async {
    final l10n = context.l10n;
    if (!_validateForm(context)) {
      await _focusFirstError();
      return;
    }

    final selectedActivity = _selectedActivity;
    if (selectedActivity == null) {
      setState(() {
        _fieldErrors['merchantActivityType'] = resolveFormFieldError(
          l10n: l10n,
          field: 'merchantActivityType',
          fieldLabel: _fieldLabel(context, 'merchantActivityType'),
        );
        _formError = l10n.validationReviewRequiredFields;
      });
      await _focusFirstError();
      return;
    }

    final serviceAreaNote = merchantServiceAreaNoteCtrl.text.trim();
    final hasAnyAddress =
        ((selectedBlock ?? '').trim().isNotEmpty) ||
        ((selectedBuilding ?? '').trim().isNotEmpty) ||
        ((selectedApartment ?? '').trim().isNotEmpty);
    final merchantPhone = merchantPhoneCtrl.text.trim();
    final phone = phoneCtrl.text.trim();
    FocusScope.of(context).unfocus();

    try {
      await ref.read(authControllerProvider.notifier).registerOwner({
        'fullName': merchantNameCtrl.text.trim(),
        'phone': phone,
        'pin': pinCtrl.text,
        if (hasAnyAddress) 'block': selectedBlock,
        if (hasAnyAddress) 'buildingNumber': selectedBuilding,
        if (hasAnyAddress) 'apartment': selectedApartment,
        'merchantName': merchantNameCtrl.text,
        'merchantType': _resolvedMerchantType,
        'merchantActivityType': selectedActivity.activityType,
        if (selectedActivity.hasDiscoverySubcategories)
          'merchantDiscoverySubcategory':
              _selectedDiscoverySubcategories.isEmpty
              ? null
              : _selectedDiscoverySubcategories.first,
        if (selectedActivity.hasDiscoverySubcategories)
          'merchantDiscoverySubcategories': _selectedDiscoverySubcategories
              .toList(growable: false),
        if (selectedActivity.hasDiscoverySubcategories)
          'merchantDiscoverySelectAll': _discoverySelectAll,
        'merchantDescription': merchantDescCtrl.text,
        'merchantPhone': merchantPhone.isEmpty ? phone : merchantPhone,
        'merchantImageUrl': null,
        'merchantServiceFlags': selectedActivity.defaultServiceFlags,
        'merchantBadges': selectedActivity.defaultBadges,
        'merchantSupportsChat': selectedActivity.supportsChat,
        'merchantSupportsAttachments': selectedActivity.supportsAttachments,
        'merchantSupportsPharmacyWorkflow':
            selectedActivity.supportsPharmacyWorkflow,
        'merchantServiceAreaNote': serviceAreaNote,
        'analyticsConsentAccepted': true,
        'analyticsConsentVersion': 'analytics_v1',
      }, merchantImageFile: merchantImageFile);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _formError = mapAnyError(
          error,
          fallback: l10n.ownerRegisterCreateFailed,
        );
      });
      return;
    }

    if (!mounted) return;
    final next = ref.read(authControllerProvider);
    if (next.isAuthed) return;
    if (await _applyBackendErrors(next)) return;
    if (next.error != null && next.error!.trim().isNotEmpty) {
      setState(() {
        _formError = next.error!.trim();
      });
    }
  }

  Widget _buildMerchantDetailsStep(
    BuildContext context, {
    required AuthState auth,
    required Widget Function({
      required String field,
      required TextEditingController controller,
      required String label,
      required String hint,
      TextInputType keyboardType,
      bool obscure,
      TextDirection? textDirection,
    })
    buildField,
  }) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        buildField(
          field: 'phone',
          controller: phoneCtrl,
          label: l10n.ownerRegisterLoginPhoneLabel,
          hint: l10n.ownerRegisterPhoneHint,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 10),
        buildField(
          field: 'pin',
          controller: pinCtrl,
          label: l10n.ownerRegisterPinLabel,
          hint: l10n.ownerRegisterPinHint,
          keyboardType: TextInputType.number,
          obscure: true,
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 14),
        Text(
          l10n.ownerRegisterSectionMerchantData,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        buildField(
          field: 'merchantName',
          controller: merchantNameCtrl,
          label: l10n.ownerRegisterMerchantNameLabel,
          hint: l10n.ownerRegisterMerchantNameHint,
        ),
        const SizedBox(height: 10),
        buildField(
          field: 'merchantDescription',
          controller: merchantDescCtrl,
          label: l10n.ownerRegisterMerchantDescriptionLabel,
          hint: l10n.ownerRegisterMerchantDescriptionHint,
        ),
        const SizedBox(height: 10),
        buildField(
          field: 'merchantPhone',
          controller: merchantPhoneCtrl,
          label: l10n.ownerRegisterContactPhoneLabel,
          hint: l10n.ownerRegisterContactPhoneHint,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
        ),
        const SizedBox(height: 10),
        buildField(
          field: 'merchantServiceAreaNote',
          controller: merchantServiceAreaNoteCtrl,
          label: l10n.ownerRegisterServiceAreaLabel,
          hint: l10n.ownerRegisterServiceAreaHint,
        ),
        const SizedBox(height: 12),
        Text(
          l10n.ownerRegisterBasmayaLocationTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 8),
        _scrollCoordinator.anchor(
          'block',
          BasmayaAddressSelector(
            selectedBlock: selectedBlock,
            selectedBuilding: selectedBuilding,
            selectedApartment: selectedApartment,
            enabled: !auth.loading,
            blockError: _errorOf('block'),
            buildingError: _errorOf('buildingNumber'),
            apartmentError: _errorOf('apartment'),
            generalError: _addressError,
            onBlockChanged: (value) {
              setState(() {
                selectedBlock = value;
                final buildings = BasmayaAddressCatalog.buildingOptionsForBlock(
                  value,
                );
                if (!buildings.contains(selectedBuilding)) {
                  selectedBuilding = null;
                }
                selectedApartment = null;
                _fieldErrors.remove('block');
                _fieldErrors.remove('buildingNumber');
                _fieldErrors.remove('apartment');
                _addressError = null;
                _formError = null;
              });
            },
            onBuildingChanged: (value) {
              setState(() {
                selectedBuilding = value;
                selectedApartment = null;
                _fieldErrors.remove('buildingNumber');
                _fieldErrors.remove('apartment');
                _addressError = null;
                _formError = null;
              });
            },
            onApartmentChanged: (value) {
              setState(() {
                selectedApartment = value;
                _fieldErrors.remove('apartment');
                _addressError = null;
                _formError = null;
              });
            },
          ),
        ),
        const SizedBox(height: 10),
        ImagePickerField(
          title: l10n.ownerRegisterMerchantImageTitle,
          selectedFile: merchantImageFile,
          existingImageUrl: null,
          onPick: () async {
            final picked = await pickImageFromDevice();
            if (!mounted || picked == null) return;
            setState(() => merchantImageFile = picked);
          },
          onClear: merchantImageFile == null
              ? null
              : () => setState(() => merchantImageFile = null),
        ),
        const SizedBox(height: 10),
        _scrollCoordinator.anchor(
          'analyticsConsentAccepted',
          _ConsentCard(
            accepted: analyticsConsentAccepted,
            onChanged: (value) {
              setState(() {
                analyticsConsentAccepted = value;
                if (value) _consentError = null;
                _formError = null;
              });
            },
            onDetailsTap: () => _showConsentInfo(context),
            errorText: _consentError,
          ),
        ),
        const SizedBox(height: 14),
        ElevatedButton(
          onPressed: auth.loading ? null : () => _submitRegistration(auth),
          child: auth.loading
              ? const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.authOwnerAccount),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final l10n = context.l10n;

    Widget buildField({
      required String field,
      required TextEditingController controller,
      required String label,
      required String hint,
      TextInputType keyboardType = TextInputType.text,
      bool obscure = false,
      TextDirection? textDirection,
    }) {
      return _scrollCoordinator.anchor(
        field,
        _Field(
          controller: controller,
          label: label,
          hint: hint,
          keyboardType: keyboardType,
          obscure: obscure,
          textDirection: textDirection,
          focusNode: _scrollCoordinator.focusNodeFor(field),
          errorText: _errorOf(field),
          onChanged: (_) => _clearFieldError(field),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          const _MeshBackground(),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.18),
                        ),
                        color: Colors.white.withOpacity(0.08),
                      ),
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            FormErrorBanner(message: _formError),
                            Row(
                              children: [
                                IconButton(
                                  onPressed:
                                      _step ==
                                          _OwnerRegisterStep.activitySelection
                                      ? () => Navigator.of(context).pop()
                                      : _backToActivityStep,
                                  icon: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    l10n.authOwnerAccount,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              l10n.ownerRegisterAccountOnly,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.ownerRegisterDescription,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.78),
                                fontSize: 12.5,
                              ),
                            ),
                            const SizedBox(height: 10),
                            if (_step == _OwnerRegisterStep.activitySelection)
                              _buildActivityStep(context)
                            else
                              _buildMerchantDetailsStep(
                                context,
                                auth: auth,
                                buildField: buildField,
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

  Future<void> _showConsentInfo(BuildContext context) async {
    final l10n = context.l10n;
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: Directionality.of(context),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.ownerRegisterConsentInfoTitle,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 10),
                Text(l10n.ownerRegisterConsentInfoBody1),
                const SizedBox(height: 8),
                Text(l10n.ownerRegisterConsentInfoBody2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDetailsTap;
  final String? errorText;

  const _ConsentCard({
    required this.accepted,
    required this.onChanged,
    required this.onDetailsTap,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.privacy_tip_outlined,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.ownerRegisterConsentSummary,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: onDetailsTap,
                child: Text(l10n.ownerRegisterConsentDetails),
              ),
            ],
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            activeColor: Colors.cyanAccent.shade400,
            checkColor: Colors.black,
            onChanged: (value) => onChanged(value == true),
            title: Text(
              l10n.ownerRegisterConsentCheckbox,
              style: const TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
          if (errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                errorText!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontSize: 12,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final bool obscure;
  final String? errorText;
  final ValueChanged<String>? onChanged;
  final TextDirection? textDirection;
  final FocusNode? focusNode;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
    this.errorText,
    this.onChanged,
    this.textDirection,
    this.focusNode,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      focusNode: focusNode,
      onChanged: onChanged,
      keyboardType: keyboardType,
      obscureText: obscure,
      textDirection: textDirection,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        errorText: errorText,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.85)),
      ),
    );
  }
}

class _MeshBackground extends StatelessWidget {
  const _MeshBackground();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
