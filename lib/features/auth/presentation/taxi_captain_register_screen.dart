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
import '../state/auth_controller.dart';
import 'widgets/basmaya_address_selector.dart';

class TaxiCaptainRegisterScreen extends ConsumerStatefulWidget {
  const TaxiCaptainRegisterScreen({super.key});

  @override
  ConsumerState<TaxiCaptainRegisterScreen> createState() =>
      _TaxiCaptainRegisterScreenState();
}

class _TaxiCaptainRegisterScreenState
    extends ConsumerState<TaxiCaptainRegisterScreen> {
  final _scrollCoordinator = FormScrollCoordinator();
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  String? selectedBlock;
  String? selectedBuilding;
  String? selectedApartment;

  final carMakeCtrl = TextEditingController();
  final carModelCtrl = TextEditingController();
  final carYearCtrl = TextEditingController();
  final carColorCtrl = TextEditingController();
  final plateNumberCtrl = TextEditingController();

  String vehicleType = 'sedan';
  LocalImageFile? profileImageFile;
  LocalImageFile? carImageFile;
  bool analyticsConsentAccepted = false;
  final Map<String, String?> _fieldErrors = <String, String?>{};
  String? _addressError;
  String? _consentError;
  String? _formError;

  @override
  void dispose() {
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    carMakeCtrl.dispose();
    carModelCtrl.dispose();
    carYearCtrl.dispose();
    carColorCtrl.dispose();
    plateNumberCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _errorOf(String key) => _fieldErrors[key];

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
      case 'fullName':
        return l10n.taxiCaptainFullNameLabel;
      case 'phone':
        return l10n.taxiCaptainPhoneLabel;
      case 'pin':
        return l10n.taxiCaptainPinLabel;
      case 'block':
        return l10n.basmayaSectorLabel;
      case 'buildingNumber':
        return l10n.basmayaBuildingLabel;
      case 'apartment':
        return l10n.basmayaApartmentLabel;
      case 'vehicleType':
        return l10n.taxiCaptainVehicleTypeLabel;
      case 'carMake':
        return l10n.taxiCaptainCarMakeLabel;
      case 'carModel':
        return l10n.taxiCaptainCarModelLabel;
      case 'carYear':
        return l10n.taxiCaptainCarYearLabel;
      case 'carColor':
        return l10n.taxiCaptainCarColorLabel;
      case 'plateNumber':
        return l10n.taxiCaptainPlateLabel;
      case 'profileImageUrl':
        return l10n.taxiCaptainProfileImageTitle;
      case 'carImageUrl':
        return l10n.taxiCaptainCarImageTitle;
      case 'analyticsConsentAccepted':
        return l10n.taxiCaptainConsentCheckbox;
      default:
        return field;
    }
  }

  String? _validatePhone(BuildContext context, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return context.l10n.taxiCaptainPhoneRequired;
    }
    if (digits.length < 10) {
      return context.l10n.taxiCaptainPhoneInvalid;
    }
    return null;
  }

  String? _validatePin(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return context.l10n.taxiCaptainPinRequired;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(trimmed)) {
      return context.l10n.taxiCaptainPinInvalid;
    }
    return null;
  }

  bool _validateForm(BuildContext context) {
    final nextErrors = <String, String?>{};
    if (fullNameCtrl.text.trim().isEmpty) {
      nextErrors['fullName'] = context.l10n.taxiCaptainFullNameRequired;
    }
    nextErrors['phone'] = _validatePhone(context, phoneCtrl.text.trim());
    nextErrors['pin'] = _validatePin(context, pinCtrl.text);

    if (carMakeCtrl.text.trim().isEmpty) {
      nextErrors['carMake'] = context.l10n.taxiCaptainCarMakeRequired;
    }
    if (carModelCtrl.text.trim().isEmpty) {
      nextErrors['carModel'] = context.l10n.taxiCaptainCarModelRequired;
    }
    if (carColorCtrl.text.trim().isEmpty) {
      nextErrors['carColor'] = context.l10n.taxiCaptainCarColorRequired;
    }
    if (plateNumberCtrl.text.trim().isEmpty) {
      nextErrors['plateNumber'] = context.l10n.taxiCaptainPlateRequired;
    }

    final currentYear = DateTime.now().year + 1;
    final carYear = int.tryParse(carYearCtrl.text.trim());
    if (carYear == null) {
      nextErrors['carYear'] = context.l10n.taxiCaptainCarYearInvalid;
    } else if (carYear < 1990 || carYear > currentYear) {
      nextErrors['carYear'] = context.l10n.taxiCaptainCarYearOutOfRange;
    }

    final nextAddressError = BasmayaAddressCatalog.validateSelection(
      block: selectedBlock,
      buildingNumber: selectedBuilding,
      apartment: selectedApartment,
    );
    final nextConsentError = analyticsConsentAccepted
        ? null
        : context.l10n.taxiCaptainConsentRequired;

    nextErrors.removeWhere((_, value) => value == null);
    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(nextErrors);
      _addressError = nextAddressError;
      _consentError = nextConsentError;
      _formError = nextErrors.isEmpty &&
              nextAddressError == null &&
              nextConsentError == null
          ? null
          : context.l10n.validationReviewRequiredFields;
    });
    return nextErrors.isEmpty &&
        nextAddressError == null &&
        nextConsentError == null;
  }

  Future<void> _focusFirstError() async {
    final hasAddressError = _errorOf('block') != null ||
        _errorOf('buildingNumber') != null ||
        _errorOf('apartment') != null ||
        _addressError != null;
    final ordered = <String>[
      if (_errorOf('fullName') != null) 'fullName',
      if (_errorOf('phone') != null) 'phone',
      if (_errorOf('pin') != null) 'pin',
      if (hasAddressError) 'block',
      if (_errorOf('vehicleType') != null) 'vehicleType',
      if (_errorOf('carMake') != null) 'carMake',
      if (_errorOf('carModel') != null) 'carModel',
      if (_errorOf('carYear') != null) 'carYear',
      if (_errorOf('carColor') != null) 'carColor',
      if (_errorOf('plateNumber') != null) 'plateNumber',
      if (_errorOf('profileImageUrl') != null) 'profileImageUrl',
      if (_errorOf('carImageUrl') != null) 'carImageUrl',
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
      nextErrors[entry.key] = resolveFormFieldError(
        l10n: context.l10n,
        field: entry.key,
        code: entry.value ?? topLevelCode,
        fieldLabel: _fieldLabel(context, entry.key),
      );
    }

    if (nextErrors.isEmpty &&
        (parsed.formCode == null || parsed.formCode!.isEmpty) &&
        topLevelCode != 'PHONE_EXISTS') {
      return false;
    }

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(nextErrors);
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
              constraints: const BoxConstraints(maxWidth: 620),
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
                                  onPressed: () => Navigator.of(context).pop(),
                                  icon: const Icon(
                                    Icons.arrow_back,
                                    color: Colors.white,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    l10n.authTaxiCaptainAccount,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Text(
                              l10n.taxiCaptainSectionCaptain,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            buildField(
                              field: 'fullName',
                              controller: fullNameCtrl,
                              label: l10n.taxiCaptainFullNameLabel,
                              hint: l10n.taxiCaptainFullNameHint,
                            ),
                            const SizedBox(height: 10),
                            buildField(
                              field: 'phone',
                              controller: phoneCtrl,
                              label: l10n.taxiCaptainPhoneLabel,
                              hint: '0770xxxxxxx',
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                            ),
                            const SizedBox(height: 10),
                            buildField(
                              field: 'pin',
                              controller: pinCtrl,
                              label: l10n.taxiCaptainPinLabel,
                              hint: l10n.taxiCaptainPinHint,
                              keyboardType: TextInputType.number,
                              obscure: true,
                              textDirection: TextDirection.ltr,
                            ),
                            const SizedBox(height: 10),
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
                                    final buildings =
                                        BasmayaAddressCatalog.buildingOptionsForBlock(
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
                            const SizedBox(height: 12),
                            Text(
                              l10n.taxiCaptainSectionCar,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 8),
                            _scrollCoordinator.anchor(
                              'vehicleType',
                              DropdownButtonFormField<String>(
                                initialValue: vehicleType,
                                items: [
                                  DropdownMenuItem(
                                    value: 'sedan',
                                    child: Text(l10n.taxiCaptainVehicleTypeSedan),
                                  ),
                                  DropdownMenuItem(
                                    value: 'suv',
                                    child: Text(l10n.taxiCaptainVehicleTypeSuv),
                                  ),
                                  DropdownMenuItem(
                                    value: 'hatchback',
                                    child: Text(
                                      l10n.taxiCaptainVehicleTypeHatchback,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'pickup',
                                    child: Text(
                                      l10n.taxiCaptainVehicleTypePickup,
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'van',
                                    child: Text(l10n.taxiCaptainVehicleTypeVan),
                                  ),
                                ],
                                onChanged: (value) {
                                  setState(() {
                                    vehicleType = value ?? 'sedan';
                                    _fieldErrors.remove('vehicleType');
                                    _formError = null;
                                  });
                                },
                                decoration: InputDecoration(
                                  labelText: l10n.taxiCaptainVehicleTypeLabel,
                                  errorText: _errorOf('vehicleType'),
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: buildField(
                                    field: 'carMake',
                                    controller: carMakeCtrl,
                                    label: l10n.taxiCaptainCarMakeLabel,
                                    hint: 'Toyota',
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: buildField(
                                    field: 'carModel',
                                    controller: carModelCtrl,
                                    label: l10n.taxiCaptainCarModelLabel,
                                    hint: 'Corolla',
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            Row(
                              children: [
                                Expanded(
                                  child: buildField(
                                    field: 'carYear',
                                    controller: carYearCtrl,
                                    label: l10n.taxiCaptainCarYearLabel,
                                    hint: '2020',
                                    keyboardType: TextInputType.number,
                                    textDirection: TextDirection.ltr,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: buildField(
                                    field: 'carColor',
                                    controller: carColorCtrl,
                                    label: l10n.taxiCaptainCarColorLabel,
                                    hint: l10n.taxiCaptainCarColorHint,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            buildField(
                              field: 'plateNumber',
                              controller: plateNumberCtrl,
                              label: l10n.taxiCaptainPlateLabel,
                              hint: l10n.taxiCaptainPlateHint,
                            ),
                            const SizedBox(height: 10),
                            _scrollCoordinator.anchor(
                              'profileImageUrl',
                              ImagePickerField(
                                title: l10n.taxiCaptainProfileImageTitle,
                                selectedFile: profileImageFile,
                                existingImageUrl: null,
                                errorText: _errorOf('profileImageUrl'),
                                onPick: () async {
                                  final picked = await pickImageFromDevice();
                                  if (!mounted || picked == null) return;
                                  setState(() {
                                    profileImageFile = picked;
                                    _fieldErrors.remove('profileImageUrl');
                                    _formError = null;
                                  });
                                },
                                onClear: profileImageFile == null
                                    ? null
                                    : () => setState(() {
                                          profileImageFile = null;
                                          _fieldErrors.remove('profileImageUrl');
                                          _formError = null;
                                        }),
                              ),
                            ),
                            const SizedBox(height: 10),
                            _scrollCoordinator.anchor(
                              'carImageUrl',
                              ImagePickerField(
                                title: l10n.taxiCaptainCarImageTitle,
                                selectedFile: carImageFile,
                                existingImageUrl: null,
                                errorText: _errorOf('carImageUrl'),
                                onPick: () async {
                                  final picked = await pickImageFromDevice();
                                  if (!mounted || picked == null) return;
                                  setState(() {
                                    carImageFile = picked;
                                    _fieldErrors.remove('carImageUrl');
                                    _formError = null;
                                  });
                                },
                                onClear: carImageFile == null
                                    ? null
                                    : () => setState(() {
                                          carImageFile = null;
                                          _fieldErrors.remove('carImageUrl');
                                          _formError = null;
                                        }),
                              ),
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
                              onPressed: auth.loading
                                  ? null
                                  : () async {
                                      if (!_validateForm(context)) {
                                        await _focusFirstError();
                                        return;
                                      }

                                      final carYear = int.parse(
                                        carYearCtrl.text.trim(),
                                      );

                                      FocusScope.of(context).unfocus();
                                      bool created = false;
                                      try {
                                        created = await ref
                                            .read(
                                              authControllerProvider.notifier,
                                            )
                                            .registerTaxiCaptain(
                                              {
                                                'fullName': fullNameCtrl.text,
                                                'phone': phoneCtrl.text,
                                                'pin': pinCtrl.text,
                                                'block': selectedBlock!,
                                                'buildingNumber':
                                                    selectedBuilding!,
                                                'apartment': selectedApartment!,
                                                'vehicleType': vehicleType,
                                                'carMake': carMakeCtrl.text,
                                                'carModel': carModelCtrl.text,
                                                'carYear': carYear,
                                                'carColor': carColorCtrl.text,
                                                'plateNumber':
                                                    plateNumberCtrl.text,
                                                'analyticsConsentAccepted':
                                                    true,
                                                'analyticsConsentVersion':
                                                    'analytics_v1',
                                              },
                                              profileImageFile:
                                                  profileImageFile,
                                              carImageFile: carImageFile,
                                            );
                                      } catch (error) {
                                        if (!mounted) return;
                                        setState(() {
                                          _formError = mapAnyError(
                                            error,
                                            fallback: l10n
                                                .taxiCaptainCreateFailed,
                                          );
                                        });
                                        return;
                                      }

                                      if (!mounted) return;
                                      if (!created) {
                                        final next =
                                            ref.read(authControllerProvider);
                                        if (await _applyBackendErrors(next)) {
                                          return;
                                        }
                                        if (next.error != null &&
                                            next.error!.trim().isNotEmpty) {
                                          setState(() {
                                            _formError = next.error!.trim();
                                          });
                                        }
                                        return;
                                      }

                                      await showDialog<void>(
                                        context: context,
                                        builder: (_) => AlertDialog(
                                          title: Text(
                                            l10n.taxiCaptainRequestSubmittedTitle,
                                          ),
                                          content: Text(
                                            l10n.taxiCaptainRequestSubmittedBody,
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.of(context).pop(),
                                              child: Text(l10n.commonDone),
                                            ),
                                          ],
                                        ),
                                      );
                                      if (mounted) {
                                        Navigator.of(context).pop();
                                      }
                                    },
                              child: auth.loading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(l10n.authTaxiCaptainAccount),
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
                  l10n.taxiCaptainConsentInfoTitle,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 10),
                Text(l10n.taxiCaptainConsentInfoBody1),
                const SizedBox(height: 8),
                Text(l10n.taxiCaptainConsentInfoBody2),
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
                  l10n.taxiCaptainConsentSummary,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: onDetailsTap,
                child: Text(l10n.taxiCaptainConsentDetails),
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
              l10n.taxiCaptainConsentCheckbox,
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
