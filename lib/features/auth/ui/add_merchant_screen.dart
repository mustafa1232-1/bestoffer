// ignore_for_file: use_build_context_synchronously, unused_element

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/forms/backend_field_error_parser.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/network/api_error_mapper.dart'
    hide parseBackendFieldErrors;
import '../../../core/widgets/image_picker_field.dart';
import '../../admin/models/owner_account_model.dart';
import '../../merchants/models/store_activity_model.dart';
import '../../admin/state/admin_controller.dart';
import '../../merchants/state/merchants_controller.dart';

enum _OwnerMode { existing, createNew }

class AddMerchantScreen extends ConsumerStatefulWidget {
  const AddMerchantScreen({super.key});

  @override
  ConsumerState<AddMerchantScreen> createState() => _AddMerchantScreenState();
}

class _AddMerchantScreenState extends ConsumerState<AddMerchantScreen> {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();

  final ownerNameCtrl = TextEditingController();
  final ownerPhoneCtrl = TextEditingController();
  final ownerPinCtrl = TextEditingController();
  final ownerBlockCtrl = TextEditingController(text: 'A');
  final ownerBuildingCtrl = TextEditingController(text: '1');
  final ownerApartmentCtrl = TextEditingController(text: '1');

  String merchantType = 'restaurant';
  String? merchantActivityType;
  final Set<String> discoverySubcategories = <String>{};
  bool discoverySelectAll = false;
  List<StoreActivityModel> _activityOptions = const [];
  List<StoreDiscoveryOptionModel> _discoveryOptions = const [];
  bool _loadingActivityOptions = false;
  bool _loadingDiscoveryOptions = false;
  _OwnerMode ownerMode = _OwnerMode.existing;

  bool loadingOwners = false;
  bool saving = false;
  String? ownersError;
  List<OwnerAccountModel> owners = [];
  int? selectedOwnerId;

  LocalImageFile? merchantImageFile;
  LocalImageFile? ownerImageFile;
  final FormScrollCoordinator _scrollCoordinator = FormScrollCoordinator();
  final Map<String, String> _fieldErrors = <String, String>{};
  String? _formError;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await _loadOwners();
      await _loadActivityOptions();
    });
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    phoneCtrl.dispose();
    ownerNameCtrl.dispose();
    ownerPhoneCtrl.dispose();
    ownerPinCtrl.dispose();
    ownerBlockCtrl.dispose();
    ownerBuildingCtrl.dispose();
    ownerApartmentCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  bool _isValidPin(String pin) {
    final value = pin.trim();
    return RegExp(r'^\d{4,8}$').hasMatch(value);
  }

  Future<void> _loadOwners() async {
    setState(() {
      loadingOwners = true;
      ownersError = null;
    });

    try {
      final raw = await ref.read(adminApiProvider).availableOwners();
      final loaded = raw
          .map(
            (e) =>
                OwnerAccountModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        owners = loaded;
        if (loaded.isEmpty) {
          ownerMode = _OwnerMode.createNew;
          selectedOwnerId = null;
        } else {
          selectedOwnerId ??= loaded.first.id;
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(
        () => ownersError = mapDioErrorL10n(
          e,
          fallbackBuilder: (l10n) => l10n.addMerchantOwnersLoadFailed,
          appendRequestId: true,
        ),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => ownersError = context.l10n.addMerchantOwnersLoadFailed);
    } finally {
      if (mounted) {
        setState(() => loadingOwners = false);
      }
    }
  }

  String _activityLabel(StoreActivityModel activity) {
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';
    return activity.localizedLabel(isArabic);
  }

  void _applyFallbackActivityForType() {
    final matching = _activityOptions
        .where((item) => item.baseType == merchantType)
        .toList();
    // Never auto-pick a default category — the admin must choose explicitly.
    // Only clear the selection when it is no longer valid for the current type.
    if (matching.every((item) => item.activityType != merchantActivityType)) {
      merchantActivityType = null;
      _discoveryOptions = const [];
      discoverySubcategories.clear();
      discoverySelectAll = false;
    }
  }

  Future<void> _loadActivityOptions() async {
    setState(() => _loadingActivityOptions = true);
    try {
      final activities = await ref
          .read(merchantsControllerProvider.notifier)
          .listActivities();
      if (!mounted) return;
      setState(() {
        _activityOptions = activities;
        _applyFallbackActivityForType();
      });
      if (merchantActivityType != null) {
        await _loadDiscoveryOptions(merchantActivityType!);
      }
    } on DioException {
      if (!mounted) return;
      setState(() {
        _activityOptions = const [];
        _discoveryOptions = const [];
      });
    } finally {
      if (mounted) {
        setState(() => _loadingActivityOptions = false);
      }
    }
  }

  Future<void> _loadDiscoveryOptions(String activityType) async {
    setState(() => _loadingDiscoveryOptions = true);
    try {
      final options = await ref
          .read(merchantsControllerProvider.notifier)
          .listDiscoveryOptions(activityType: activityType);
      if (!mounted) return;
      setState(() {
        _discoveryOptions = options;
        final optionCodes = _discoveryOptions.map((item) => item.code).toSet();
        discoverySubcategories.removeWhere(
          (code) => !optionCodes.contains(code),
        );
        if (_discoveryOptions.isEmpty) {
          discoverySubcategories.clear();
          discoverySelectAll = false;
        }
      });
    } on DioException {
      if (!mounted) return;
      setState(() {
        _discoveryOptions = const [];
        discoverySubcategories.clear();
        discoverySelectAll = false;
      });
    } finally {
      if (mounted) {
        setState(() => _loadingDiscoveryOptions = false);
      }
    }
  }

  String _mapApiError(DioException e) {
    return mapDioError(
      e,
      fallback: 'Action failed. Please try again.',
      customMessages: const {
        'OWNER_NOT_FOUND': 'Owner account not found.',
        'OWNER_ALREADY_HAS_MERCHANT':
            'This owner account is already linked to a merchant.',
      },
      appendRequestId: true,
    );
  }

  String? _errorOf(String field) => _fieldErrors[field];

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) && _formError == null) {
      return;
    }
    setState(() {
      _fieldErrors.remove(field);
      if (_fieldErrors.isEmpty) {
        _formError = null;
      }
    });
  }

  String _fieldLabel(BuildContext context, String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'name':
        return l10n.addMerchantNameLabel;
      case 'phone':
        return l10n.addMerchantPhoneLabel;
      case 'activityType':
        return l10n.addMerchantActivityTypeLabel;
      case 'discoverySubcategory':
        return l10n.addMerchantDiscoverySubcategoryLabel;
      case 'ownerSelection':
        return l10n.addMerchantOwnerAccountLabel;
      case 'ownerFullName':
        return l10n.addMerchantOwnerNameLabel;
      case 'ownerPhone':
        return l10n.addMerchantOwnerPhoneLabel;
      case 'ownerPin':
        return l10n.authPinLabel;
      case 'ownerBlock':
        return l10n.authRegisterBlockLabel;
      case 'ownerBuildingNumber':
        return l10n.authRegisterBuildingNumberLabel;
      case 'ownerApartment':
        return l10n.authRegisterApartmentLabel;
      default:
        return field;
    }
  }

  String _normalizeBackendField(String rawField) {
    switch (rawField) {
      case 'owner':
      case 'ownerUserId':
        return 'ownerSelection';
      case 'owner.fullName':
        return 'ownerFullName';
      case 'owner.phone':
        return 'ownerPhone';
      case 'owner.pin':
      case 'owner.pin_format':
        return 'ownerPin';
      case 'owner.block':
        return 'ownerBlock';
      case 'owner.buildingNumber':
        return 'ownerBuildingNumber';
      case 'owner.apartment':
        return 'ownerApartment';
      case 'discoverySubcategories':
        return 'discoverySubcategory';
      default:
        return rawField;
    }
  }

  String? _merchantFieldCustomError(
    String field,
    String? code,
    BuildContext context,
  ) {
    final l10n = context.l10n;
    switch (code?.trim().toUpperCase()) {
      case 'OWNER_NOT_FOUND':
        return l10n.addMerchantOwnerNotFound;
      case 'OWNER_ALREADY_HAS_MERCHANT':
        return l10n.addMerchantOwnerAlreadyLinked;
      case 'OWNER_CONFLICT':
        return l10n.addMerchantOwnerConflict;
      case 'PIN_FORMAT':
        return l10n.validationInvalidPin;
      case 'PHONE_EXISTS':
        return l10n.apiPhoneExists;
    }
    if (field == 'ownerSelection' && ownerMode == _OwnerMode.existing) {
      return null;
    }
    return null;
  }

  String? _apiMessageCode(DioException error) {
    final data = error.response?.data;
    if (data is Map) {
      final message = data['message'];
      if (message == null) return null;
      final text = '$message'.trim();
      return text.isEmpty ? null : text;
    }
    return null;
  }

  Future<void> _focusFirstError(Iterable<String> fields) async {
    const ordered = <String>[
      'ownerSelection',
      'ownerFullName',
      'ownerPhone',
      'ownerPin',
      'ownerBlock',
      'ownerBuildingNumber',
      'ownerApartment',
      'name',
      'discoverySubcategory',
      'phone',
    ];
    final wanted = fields.toSet();
    await _scrollCoordinator.focusFirstError(ordered.where(wanted.contains));
  }

  String _mapApiErrorLegacy(DioException e) {
    return mapDioErrorL10n(
      e,
      fallbackBuilder: (l10n) => l10n.addMerchantCreateFailed,
      customMessages: {
        'OWNER_NOT_FOUND': resolveLocalizedText(
          (l10n) => l10n.addMerchantOwnerNotFound,
        ),
        'OWNER_ALREADY_HAS_MERCHANT': resolveLocalizedText(
          (l10n) => l10n.addMerchantOwnerAlreadyLinked,
        ),
        'OWNER_CONFLICT': resolveLocalizedText(
          (l10n) => l10n.addMerchantOwnerConflict,
        ),
      },
      appendRequestId: true,
    );
  }

  Future<void> _submit() async {
    if (saving) return;

    final l10n = context.l10n;
    final nextErrors = <String, String>{};
    final merchantName = nameCtrl.text.trim();

    if (merchantName.isEmpty) {
      nextErrors['name'] = resolveFormFieldError(
        l10n: l10n,
        field: 'name',
        fieldLabel: _fieldLabel(context, 'name'),
      );
    }

    if (ownerMode == _OwnerMode.existing) {
      if (selectedOwnerId == null) {
        nextErrors['ownerSelection'] = resolveFormFieldError(
          l10n: l10n,
          field: 'ownerSelection',
          fieldLabel: _fieldLabel(context, 'ownerSelection'),
        );
      }
    } else {
      if (ownerNameCtrl.text.trim().isEmpty) {
        nextErrors['ownerFullName'] = resolveFormFieldError(
          l10n: l10n,
          field: 'ownerFullName',
          fieldLabel: _fieldLabel(context, 'ownerFullName'),
        );
      }
      if (ownerPhoneCtrl.text.trim().isEmpty) {
        nextErrors['ownerPhone'] = resolveFormFieldError(
          l10n: l10n,
          field: 'ownerPhone',
          fieldLabel: _fieldLabel(context, 'ownerPhone'),
        );
      }
      if (!_isValidPin(ownerPinCtrl.text)) {
        nextErrors['ownerPin'] = resolveFormFieldError(
          l10n: l10n,
          field: 'ownerPin',
          code: 'INVALID_PIN',
          fieldLabel: _fieldLabel(context, 'ownerPin'),
        );
      }
      if (ownerBlockCtrl.text.trim().isEmpty) {
        nextErrors['ownerBlock'] = resolveFormFieldError(
          l10n: l10n,
          field: 'ownerBlock',
          fieldLabel: _fieldLabel(context, 'ownerBlock'),
        );
      }
      if (ownerBuildingCtrl.text.trim().isEmpty) {
        nextErrors['ownerBuildingNumber'] = resolveFormFieldError(
          l10n: l10n,
          field: 'ownerBuildingNumber',
          fieldLabel: _fieldLabel(context, 'ownerBuildingNumber'),
        );
      }
      if (ownerApartmentCtrl.text.trim().isEmpty) {
        nextErrors['ownerApartment'] = resolveFormFieldError(
          l10n: l10n,
          field: 'ownerApartment',
          fieldLabel: _fieldLabel(context, 'ownerApartment'),
        );
      }
    }

    StoreActivityModel? selectedActivity;
    for (final item in _activityOptions) {
      if (item.activityType == merchantActivityType) {
        selectedActivity = item;
        break;
      }
    }
    // Store category is mandatory — no silent fallback to market/restaurant.
    if (merchantActivityType == null ||
        merchantActivityType!.trim().isEmpty ||
        selectedActivity == null) {
      nextErrors['activityType'] = resolveFormFieldError(
        l10n: l10n,
        field: 'activityType',
        fieldLabel: _fieldLabel(context, 'activityType'),
      );
    }
    if ((selectedActivity?.hasDiscoverySubcategories ?? false) &&
        !discoverySelectAll &&
        discoverySubcategories.isEmpty) {
      nextErrors['discoverySubcategory'] = resolveFormFieldError(
        l10n: l10n,
        field: 'discoverySubcategory',
        fieldLabel: _fieldLabel(context, 'discoverySubcategory'),
      );
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _fieldErrors
          ..clear()
          ..addAll(nextErrors);
        _formError = l10n.validationReviewRequiredFields;
      });
      await _focusFirstError(nextErrors.keys);
      return;
    }

    setState(() {
      saving = true;
      _formError = null;
      _fieldErrors.clear();
    });

    try {
      await ref
          .read(merchantsControllerProvider.notifier)
          .addMerchant(
            name: merchantName,
            type: merchantType,
            // Guaranteed non-null: validation above blocks submit without it.
            activityType: merchantActivityType!,
            discoverySubcategory: discoverySubcategories.isEmpty
                ? null
                : discoverySubcategories.first,
            discoverySubcategories: discoverySubcategories.toList(
              growable: false,
            ),
            discoverySelectAll: discoverySelectAll,
            description: descCtrl.text.trim(),
            phone: phoneCtrl.text.trim(),
            imageUrl: '',
            serviceFlags: const <String, dynamic>{},
            badges: const <String>[],
            supportsChat: merchantActivityType == 'pharmacy',
            supportsAttachments: merchantActivityType == 'pharmacy',
            supportsPharmacyWorkflow: merchantActivityType == 'pharmacy',
            merchantImageFile: merchantImageFile,
            ownerImageFile: ownerMode == _OwnerMode.createNew
                ? ownerImageFile
                : null,
            ownerUserId: ownerMode == _OwnerMode.existing
                ? selectedOwnerId
                : null,
            ownerPayload: ownerMode == _OwnerMode.createNew
                ? {
                    'fullName': ownerNameCtrl.text.trim(),
                    'phone': ownerPhoneCtrl.text.trim(),
                    'pin': ownerPinCtrl.text.trim(),
                    'block': ownerBlockCtrl.text.trim(),
                    'buildingNumber': ownerBuildingCtrl.text.trim(),
                    'apartment': ownerApartmentCtrl.text.trim(),
                    'imageUrl': '',
                  }
                : null,
          );

      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final parsed = parseBackendFieldErrors(e);
      final backendErrors = <String, String>{};
      if (parsed.hasAnyErrors) {
        for (final entry in parsed.fieldCodes.entries) {
          final field = _normalizeBackendField(entry.key);
          backendErrors[field] = resolveFormFieldError(
            l10n: l10n,
            field: field,
            code: entry.value,
            fieldLabel: _fieldLabel(context, field),
            customResolver: (l10n, field, code) =>
                _merchantFieldCustomError(field, code, context),
          );
        }
      } else {
        final code = _apiMessageCode(e)?.toUpperCase();
        if (code == 'PHONE_EXISTS') {
          final field = ownerMode == _OwnerMode.createNew
              ? 'ownerPhone'
              : 'phone';
          backendErrors[field] = resolveFormFieldError(
            l10n: l10n,
            field: field,
            code: code,
            fieldLabel: _fieldLabel(context, field),
            customResolver: (l10n, field, code) =>
                _merchantFieldCustomError(field, code, context),
          );
        } else if (code == 'OWNER_ALREADY_HAS_MERCHANT' ||
            code == 'OWNER_NOT_FOUND') {
          final field = ownerMode == _OwnerMode.existing
              ? 'ownerSelection'
              : 'ownerPhone';
          backendErrors[field] = resolveFormFieldError(
            l10n: l10n,
            field: field,
            code: code,
            fieldLabel: _fieldLabel(context, field),
            customResolver: (l10n, field, code) =>
                _merchantFieldCustomError(field, code, context),
          );
        }
      }

      if (backendErrors.isNotEmpty) {
        setState(() {
          _fieldErrors
            ..clear()
            ..addAll(backendErrors);
          _formError = resolveFormLevelError(
            l10n,
            code: parsed.formCode,
            fallback: l10n.validationReviewRequiredFields,
          );
        });
        await _focusFirstError(backendErrors.keys);
      } else {
        setState(() => _formError = _mapApiError(e));
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _formError = l10n.addMerchantCreateFailed);
    } finally {
      if (mounted) {
        setState(() => saving = false);
      }
    }
  }

  Widget _buildOwnerSection() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FormErrorBanner(message: _formError),
            Text(
              l10n.addMerchantOwnerSectionTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_OwnerMode>(
              segments: [
                ButtonSegment<_OwnerMode>(
                  value: _OwnerMode.existing,
                  label: Text(l10n.addMerchantExistingOwnerOption),
                  icon: const Icon(Icons.link),
                ),
                ButtonSegment<_OwnerMode>(
                  value: _OwnerMode.createNew,
                  label: Text(l10n.addMerchantNewOwnerOption),
                  icon: const Icon(Icons.person_add_alt_1),
                ),
              ],
              selected: {ownerMode},
              onSelectionChanged: (selection) {
                if (selection.isEmpty) return;
                setState(() {
                  ownerMode = selection.first;
                  _fieldErrors.remove('ownerSelection');
                  _fieldErrors.remove('ownerFullName');
                  _fieldErrors.remove('ownerPhone');
                  _fieldErrors.remove('ownerPin');
                  _fieldErrors.remove('ownerBlock');
                  _fieldErrors.remove('ownerBuildingNumber');
                  _fieldErrors.remove('ownerApartment');
                  if (_fieldErrors.isEmpty) {
                    _formError = null;
                  }
                });
              },
            ),
            const SizedBox(height: 12),
            if (ownerMode == _OwnerMode.existing) ...[
              if (loadingOwners)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (ownersError != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      ownersError!,
                      style: const TextStyle(color: Colors.red),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loadOwners,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.commonRetry),
                    ),
                  ],
                )
              else if (owners.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(l10n.addMerchantNoOwnersAvailable),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () =>
                          setState(() => ownerMode = _OwnerMode.createNew),
                      child: Text(l10n.addMerchantCreateNewOwnerAction),
                    ),
                  ],
                )
              else
                _scrollCoordinator.anchor(
                  'ownerSelection',
                  DropdownButtonFormField<int>(
                    key: ValueKey(selectedOwnerId),
                    initialValue: selectedOwnerId,
                    items: owners
                        .map(
                          (o) => DropdownMenuItem<int>(
                            value: o.id,
                            child: Text('${o.fullName} - ${o.phone}'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) {
                      setState(() => selectedOwnerId = v);
                      _clearFieldError('ownerSelection');
                    },
                    decoration: InputDecoration(
                      labelText: l10n.addMerchantOwnerAccountLabel,
                      errorText: _errorOf('ownerSelection'),
                      suffixIcon: IconButton(
                        onPressed: _loadOwners,
                        icon: const Icon(Icons.refresh),
                        tooltip: l10n.commonRefresh,
                      ),
                    ),
                  ),
                ),
            ],
            if (ownerMode == _OwnerMode.createNew) ...[
              _scrollCoordinator.anchor(
                'ownerFullName',
                TextField(
                  controller: ownerNameCtrl,
                  focusNode: _scrollCoordinator.focusNodeFor('ownerFullName'),
                  onChanged: (_) => _clearFieldError('ownerFullName'),
                  decoration: InputDecoration(
                    labelText: l10n.addMerchantOwnerNameLabel,
                    errorText: _errorOf('ownerFullName'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              _scrollCoordinator.anchor(
                'ownerPhone',
                TextField(
                  controller: ownerPhoneCtrl,
                  focusNode: _scrollCoordinator.focusNodeFor('ownerPhone'),
                  keyboardType: TextInputType.phone,
                  onChanged: (_) => _clearFieldError('ownerPhone'),
                  decoration: InputDecoration(
                    labelText: l10n.addMerchantOwnerPhoneLabel,
                    errorText: _errorOf('ownerPhone'),
                  ),
                  textDirection: TextDirection.ltr,
                ),
              ),
              const SizedBox(height: 8),
              _scrollCoordinator.anchor(
                'ownerPin',
                TextField(
                  controller: ownerPinCtrl,
                  focusNode: _scrollCoordinator.focusNodeFor('ownerPin'),
                  keyboardType: TextInputType.number,
                  onChanged: (_) => _clearFieldError('ownerPin'),
                  decoration: InputDecoration(
                    labelText: l10n.authPinLabel,
                    errorText: _errorOf('ownerPin'),
                  ),
                  obscureText: true,
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _scrollCoordinator.anchor(
                      'ownerBlock',
                      TextField(
                        controller: ownerBlockCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor(
                          'ownerBlock',
                        ),
                        onChanged: (_) => _clearFieldError('ownerBlock'),
                        decoration: InputDecoration(
                          labelText: l10n.authRegisterBlockLabel,
                          errorText: _errorOf('ownerBlock'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _scrollCoordinator.anchor(
                      'ownerBuildingNumber',
                      TextField(
                        controller: ownerBuildingCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor(
                          'ownerBuildingNumber',
                        ),
                        onChanged: (_) =>
                            _clearFieldError('ownerBuildingNumber'),
                        decoration: InputDecoration(
                          labelText: l10n.authRegisterBuildingNumberLabel,
                          errorText: _errorOf('ownerBuildingNumber'),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _scrollCoordinator.anchor(
                      'ownerApartment',
                      TextField(
                        controller: ownerApartmentCtrl,
                        focusNode: _scrollCoordinator.focusNodeFor(
                          'ownerApartment',
                        ),
                        onChanged: (_) => _clearFieldError('ownerApartment'),
                        decoration: InputDecoration(
                          labelText: l10n.authRegisterApartmentLabel,
                          errorText: _errorOf('ownerApartment'),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ImagePickerField(
                title: l10n.addMerchantOwnerImageTitle,
                selectedFile: ownerImageFile,
                existingImageUrl: null,
                onPick: () async {
                  final picked = await pickImageFromDevice();
                  if (!mounted || picked == null) return;
                  setState(() => ownerImageFile = picked);
                },
                onClear: ownerImageFile == null
                    ? null
                    : () => setState(() => ownerImageFile = null),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantSection() {
    final l10n = context.l10n;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              l10n.addMerchantSectionTitle,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            _scrollCoordinator.anchor(
              'name',
              TextField(
                controller: nameCtrl,
                focusNode: _scrollCoordinator.focusNodeFor('name'),
                onChanged: (_) => _clearFieldError('name'),
                decoration: InputDecoration(
                  labelText: l10n.addMerchantNameLabel,
                  errorText: _errorOf('name'),
                ),
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: merchantType,
              items: [
                DropdownMenuItem(
                  value: 'restaurant',
                  child: Text(l10n.addMerchantTypeRestaurant),
                ),
                DropdownMenuItem(
                  value: 'market',
                  child: Text(l10n.addMerchantTypeMarket),
                ),
              ],
              onChanged: (v) async {
                if (v == null) return;
                setState(() {
                  merchantType = v;
                  _applyFallbackActivityForType();
                  _fieldErrors.remove('discoverySubcategory');
                });
                if (merchantActivityType != null) {
                  await _loadDiscoveryOptions(merchantActivityType!);
                }
              },
              decoration: InputDecoration(labelText: l10n.addMerchantTypeLabel),
            ),
            if (_loadingActivityOptions) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_activityOptions
                .where((item) => item.baseType == merchantType)
                .isNotEmpty) ...[
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                initialValue: merchantActivityType,
                items: _activityOptions
                    .where((item) => item.baseType == merchantType)
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item.activityType,
                        child: Text(_activityLabel(item)),
                      ),
                    )
                    .toList(),
                onChanged: (value) async {
                  if (value == null) return;
                  setState(() {
                    merchantActivityType = value;
                    discoverySubcategories.clear();
                    discoverySelectAll = false;
                    _fieldErrors.remove('discoverySubcategory');
                    _fieldErrors.remove('activityType');
                  });
                  await _loadDiscoveryOptions(value);
                },
                decoration: InputDecoration(
                  labelText: l10n.addMerchantActivityTypeLabel,
                  helperText: context.lt(
                    ar: 'اختر التصنيف الذي سيظهر فيه المتجر للمستخدمين',
                    en: 'Choose the category the store appears under for users',
                  ),
                  errorText: _fieldErrors['activityType'],
                ),
              ),
            ],
            if (_loadingDiscoveryOptions) ...[
              const SizedBox(height: 8),
              const LinearProgressIndicator(minHeight: 2),
            ],
            if (_discoveryOptions.isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                l10n.addMerchantDiscoverySubcategoriesLabel,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              CheckboxListTile(
                value: discoverySelectAll,
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                title: Text(l10n.addMerchantDiscoverySelectAllLabel),
                subtitle: Text(l10n.addMerchantDiscoverySelectAllHint),
                onChanged: (value) {
                  setState(() {
                    discoverySelectAll = value == true;
                    if (discoverySelectAll) discoverySubcategories.clear();
                    _fieldErrors.remove('discoverySubcategory');
                    if (_fieldErrors.isEmpty) _formError = null;
                  });
                },
              ),
              if (!discoverySelectAll)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _discoveryOptions
                      .map(
                        (item) => FilterChip(
                          label: Text(
                            item.localizedLabel(
                              Localizations.localeOf(context).languageCode ==
                                  'ar',
                            ),
                          ),
                          selected: discoverySubcategories.contains(item.code),
                          onSelected: (selected) {
                            setState(() {
                              if (selected) {
                                discoverySubcategories.add(item.code);
                              } else {
                                discoverySubcategories.remove(item.code);
                              }
                              _fieldErrors.remove('discoverySubcategory');
                              if (_fieldErrors.isEmpty) _formError = null;
                            });
                          },
                        ),
                      )
                      .toList(growable: false),
                ),
              if (_errorOf('discoverySubcategory') != null) ...[
                const SizedBox(height: 6),
                Text(
                  _errorOf('discoverySubcategory')!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              onChanged: (_) => _clearFieldError('description'),
              decoration: InputDecoration(
                labelText: l10n.addMerchantDescriptionLabel,
                errorText: _errorOf('description'),
              ),
              textDirection: Directionality.of(context),
            ),
            const SizedBox(height: 10),
            _scrollCoordinator.anchor(
              'phone',
              TextField(
                controller: phoneCtrl,
                focusNode: _scrollCoordinator.focusNodeFor('phone'),
                keyboardType: TextInputType.phone,
                onChanged: (_) => _clearFieldError('phone'),
                decoration: InputDecoration(
                  labelText: l10n.addMerchantPhoneLabel,
                  hintText: l10n.addMerchantPhoneHint,
                  errorText: _errorOf('phone'),
                ),
                textDirection: TextDirection.ltr,
              ),
            ),
            const SizedBox(height: 10),
            ImagePickerField(
              title: l10n.addMerchantImageTitle,
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
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.drawerCreateMerchant)),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _buildOwnerSection(),
              const SizedBox(height: 14),
              _buildMerchantSection(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving ? null : _submit,
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.commonSave),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
