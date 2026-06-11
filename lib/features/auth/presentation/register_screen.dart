// ignore_for_file: use_build_context_synchronously

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
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../models/residence_card_extraction.dart';
import '../state/auth_controller.dart';
import 'widgets/basmaya_address_selector.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final workTitleCtrl = TextEditingController();
  final workCompanyCtrl = TextEditingController();

  final cardFullNameCtrl = TextEditingController();
  final cardTownCtrl = TextEditingController();
  final cardBuildingCtrl = TextEditingController();
  final cardIssueDateCtrl = TextEditingController();
  final cardContractCtrl = TextEditingController();
  final cardFloorCtrl = TextEditingController();
  final cardApartmentCtrl = TextEditingController();
  final cardVisibleIdCtrl = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();
  final Map<String, String> _fieldErrors = <String, String>{};

  String? selectedBlock;
  String? selectedBuilding;
  String? selectedApartment;
  String? _addressError;
  String? _consentError;
  String? _formError;

  bool analyticsConsentAccepted = false;
  bool extractingCard = false;

  LocalImageFile? profileImageFile;
  LocalImageFile? residenceCardImageFile;
  ResidenceCardExtraction? extractedCard;

  @override
  void dispose() {
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    workTitleCtrl.dispose();
    workCompanyCtrl.dispose();
    cardFullNameCtrl.dispose();
    cardTownCtrl.dispose();
    cardBuildingCtrl.dispose();
    cardIssueDateCtrl.dispose();
    cardContractCtrl.dispose();
    cardFloorCtrl.dispose();
    cardApartmentCtrl.dispose();
    cardVisibleIdCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  Future<void> _pickResidenceCardFromGallery() async {
    final picked = await pickImageFromDevice();
    if (!mounted || picked == null) return;
    setState(() {
      residenceCardImageFile = picked;
      extractedCard = null;
    });
  }

  Future<void> _captureResidenceCard() async {
    final picked = await captureImageFromCamera();
    if (!mounted || picked == null) return;
    setState(() {
      residenceCardImageFile = picked;
      extractedCard = null;
    });
  }

  Future<void> _extractResidenceCardData() async {
    final file = residenceCardImageFile;
    if (file == null || extractingCard) return;

    setState(() => extractingCard = true);
    try {
      final out = await ref
          .read(authControllerProvider.notifier)
          .extractResidenceCard(file);
      if (!mounted || out == null) return;

      final extraction = ResidenceCardExtraction.fromJson(out);
      _applyExtraction(extraction);

      if (extraction.warnings.isNotEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(extraction.warnings.join('\n'))));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.authRegisterCardExtractFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => extractingCard = false);
      }
    }
  }

  void _applyExtraction(ResidenceCardExtraction extraction) {
    extractedCard = extraction;
    final d = extraction.extractedData;

    cardFullNameCtrl.text = d.fullName ?? '';
    cardTownCtrl.text = d.town ?? '';
    cardBuildingCtrl.text = d.buildingNumber ?? '';
    cardIssueDateCtrl.text = d.issueDate ?? '';
    cardContractCtrl.text = d.contractNumber ?? '';
    cardFloorCtrl.text = d.floorNumber ?? '';
    cardApartmentCtrl.text = d.apartmentNumber ?? '';
    cardVisibleIdCtrl.text = d.visibleIdNumber ?? '';

    if ((d.fullName ?? '').trim().isNotEmpty &&
        fullNameCtrl.text.trim().isEmpty) {
      fullNameCtrl.text = d.fullName!.trim();
    }

    final suggested = _suggestAddress(
      town: d.town,
      buildingNumber: d.buildingNumber,
      floorNumber: d.floorNumber,
      apartmentNumber: d.apartmentNumber,
    );

    selectedBlock = suggested.$1 ?? selectedBlock;
    selectedBuilding = suggested.$2 ?? selectedBuilding;
    selectedApartment = suggested.$3 ?? selectedApartment;
    setState(() {});
  }

  (String?, String?, String?) _suggestAddress({
    required String? town,
    required String? buildingNumber,
    required String? floorNumber,
    required String? apartmentNumber,
  }) {
    final townLetter = (town ?? '').trim().toUpperCase();
    final buildingDigits = (buildingNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final floorDigits = (floorNumber ?? '').replaceAll(RegExp(r'\D'), '');
    final apartmentDigits = (apartmentNumber ?? '').replaceAll(
      RegExp(r'\D'),
      '',
    );

    String? block;
    if (townLetter.isNotEmpty && buildingDigits.isNotEmpty) {
      final candidate = '$townLetter${buildingDigits.substring(0, 1)}';
      if (BasmayaAddressCatalog.blockOptions.contains(candidate)) {
        block = candidate;
      }
    }

    String? building;
    if (townLetter.isNotEmpty && buildingDigits.isNotEmpty) {
      final candidate = '$townLetter${buildingDigits.padLeft(3, '0')}';
      final options = BasmayaAddressCatalog.buildingOptionsForBlock(block);
      if (options.contains(candidate)) {
        building = candidate;
      }
    }

    String? apartment;
    final floor = int.tryParse(floorDigits);
    final unit = int.tryParse(apartmentDigits);
    if (floor != null &&
        unit != null &&
        floor >= 0 &&
        floor <= 9 &&
        unit >= 1 &&
        unit <= 12) {
      apartment = floor == 0
          ? 'G${unit.toString().padLeft(2, '0')}'
          : '$floor${unit.toString().padLeft(2, '0')}';
    }

    return (block, building, apartment);
  }

  String? _errorOf(String field) => _fieldErrors[field];

  String _fieldLabel(BuildContext context, String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'fullName':
        return l10n.authRegisterFullName;
      case 'phone':
        return l10n.authPhoneLabel;
      case 'pin':
        return l10n.authPinLabel;
      case 'block':
        return l10n.basmayaSectorLabel;
      case 'buildingNumber':
        return l10n.authRegisterBuildingNumber;
      case 'apartment':
        return l10n.authRegisterApartmentNumber;
      case 'analyticsConsent':
        return l10n.authRegisterConsentCheckbox;
      default:
        return field;
    }
  }

  void _clearFieldError(String field) {
    if (!_fieldErrors.containsKey(field) &&
        _formError == null &&
        _addressError == null &&
        _consentError == null) {
      return;
    }
    setState(() {
      _fieldErrors.remove(field);
      if (field == 'analyticsConsent') {
        _consentError = null;
      }
      if (field == 'block' || field == 'buildingNumber' || field == 'apartment') {
        _addressError = null;
      }
      _formError = null;
    });
  }

  String? _validatePhone(BuildContext context, String value) {
    final digits = value.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return resolveFormFieldError(
        l10n: context.l10n,
        field: 'phone',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'phone'),
      );
    }
    if (digits.length < 10) {
      return context.l10n.validationInvalidPhone;
    }
    return null;
  }

  String? _validatePin(BuildContext context, String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return resolveFormFieldError(
        l10n: context.l10n,
        field: 'pin',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'pin'),
      );
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(trimmed)) {
      return context.l10n.validationInvalidPin;
    }
    return null;
  }

  bool _validateForm(BuildContext context) {
    final nextErrors = <String, String>{};
    if (fullNameCtrl.text.trim().isEmpty) {
      nextErrors['fullName'] = resolveFormFieldError(
        l10n: context.l10n,
        field: 'fullName',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'fullName'),
      );
    }

    final phoneError = _validatePhone(context, phoneCtrl.text);
    if (phoneError != null) {
      nextErrors['phone'] = phoneError;
    }

    final pinError = _validatePin(context, pinCtrl.text);
    if (pinError != null) {
      nextErrors['pin'] = pinError;
    }

    if ((selectedBlock ?? '').trim().isEmpty) {
      nextErrors['block'] = resolveFormFieldError(
        l10n: context.l10n,
        field: 'block',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'block'),
      );
    }
    if ((selectedBuilding ?? '').trim().isEmpty) {
      nextErrors['buildingNumber'] = resolveFormFieldError(
        l10n: context.l10n,
        field: 'buildingNumber',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'buildingNumber'),
      );
    }
    if ((selectedApartment ?? '').trim().isEmpty) {
      nextErrors['apartment'] = resolveFormFieldError(
        l10n: context.l10n,
        field: 'apartment',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'apartment'),
      );
    }

    final nextAddressError = nextErrors.containsKey('block') ||
            nextErrors.containsKey('buildingNumber') ||
            nextErrors.containsKey('apartment')
        ? null
        : BasmayaAddressCatalog.validateSelection(
            block: selectedBlock,
            buildingNumber: selectedBuilding,
            apartment: selectedApartment,
            l10n: context.l10n,
          );

    final nextConsentError = analyticsConsentAccepted
        ? null
        : resolveFormFieldError(
            l10n: context.l10n,
            field: 'analyticsConsent',
            code: 'REQUIRED',
            fieldLabel: _fieldLabel(context, 'analyticsConsent'),
          );

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
    final ordered = <String>[
      if (_errorOf('fullName') != null) 'fullName',
      if (_errorOf('phone') != null) 'phone',
      if (_errorOf('pin') != null) 'pin',
      if (_errorOf('block') != null) 'block',
      if (_errorOf('buildingNumber') != null) 'buildingNumber',
      if (_errorOf('apartment') != null) 'apartment',
      if (_consentError != null) 'analyticsConsent',
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

    final nextErrors = <String, String>{};
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
      _consentError = nextErrors['analyticsConsent'];
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

  Future<void> _submit() async {
    final auth = ref.read(authControllerProvider);
    if (auth.loading) return;

    FocusScope.of(context).unfocus();
    if (!_validateForm(context)) {
      await _focusFirstError();
      return;
    }

    final payload = <String, dynamic>{
      'fullName': fullNameCtrl.text.trim(),
      'phone': phoneCtrl.text.trim(),
      'pin': pinCtrl.text.trim(),
      'workTitle': workTitleCtrl.text.trim(),
      'workCompany': workCompanyCtrl.text.trim(),
      'block': selectedBlock!,
      'buildingNumber': selectedBuilding!,
      'apartment': selectedApartment!,
      'analyticsConsentAccepted': true,
      'analyticsConsentVersion': 'analytics_v1',
    };

    try {
      if (residenceCardImageFile != null) {
        payload.addAll({
          'documentType': 'residence_card',
          'full_name': cardFullNameCtrl.text.trim(),
          'town': cardTownCtrl.text.trim(),
          'building_number': cardBuildingCtrl.text.trim(),
          'issue_date': cardIssueDateCtrl.text.trim(),
          'contract_number': cardContractCtrl.text.trim(),
          'floor_number': cardFloorCtrl.text.trim(),
          'apartment_number': cardApartmentCtrl.text.trim(),
          'visible_id_number': cardVisibleIdCtrl.text.trim(),
          'extractionConfidence': extractedCard?.confidence ?? 0,
          if (extractedCard != null)
            'extractedPayload': extractedCard!.toJson(),
        });

        await ref
            .read(authControllerProvider.notifier)
            .registerWithCard(
              payload,
              imageFile: profileImageFile,
              cardImageFile: residenceCardImageFile!,
            );
      } else {
        await ref
            .read(authControllerProvider.notifier)
            .register(payload, imageFile: profileImageFile);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _formError = mapAnyError(
          error,
          fallback: context.l10n.authRegisterCreateFailed,
        );
      });
      return;
    }

    if (!mounted) return;
    final next = ref.read(authControllerProvider);
    if (next.isAuthed) {
      // The root auth listener owns the post-register navigation.
      // Popping from here can race with pushAndRemoveUntil and trigger
      // transient navigator errors / red screens.
      return;
    }
    if (await _applyBackendErrors(next)) {
      return;
    }
    if (next.error != null && next.error!.trim().isNotEmpty) {
      setState(() {
        _formError = next.error!.trim();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final textStyle = Theme.of(
      context,
    ).textTheme.bodyMedium?.copyWith(color: Colors.white);

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
        TextField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: obscure,
          focusNode: _scrollCoordinator.focusNodeFor(field),
          textDirection: textDirection,
          onChanged: (_) => _clearFieldError(field),
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: label,
            hintText: hint,
            errorText: _errorOf(field),
          ),
        ),
      );
    }

    return Scaffold(
      body: Stack(
        children: [
          const SizedBox.expand(),
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
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
                          color: Colors.white.withValues(alpha: 0.08),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.18),
                          ),
                        ),
                        child: Directionality(
                          textDirection: context.appTextDirection,
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Row(
                                  children: [
                                    IconButton(
                                      onPressed: () =>
                                          Navigator.of(context).pop(),
                                      icon: const Icon(
                                        Icons.arrow_back,
                                        color: Colors.white,
                                      ),
                                    ),
                                    Expanded(
                                      child: Text(
                                        context.l10n.authRegisterTitle,
                                        textAlign: TextAlign.center,
                                        style: const TextStyle(
                                          fontSize: 22,
                                          fontWeight: FontWeight.w800,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 48),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                FormErrorBanner(message: _formError),
                                Text(
                                  context
                                      .l10n
                                      .authRegisterResidenceCardSectionTitle,
                                  style: textStyle?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: auth.loading
                                            ? null
                                            : _pickResidenceCardFromGallery,
                                        icon: const Icon(
                                          Icons.upload_file_rounded,
                                        ),
                                        label: Text(
                                          context
                                              .l10n
                                              .authRegisterUploadCardImage,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: auth.loading
                                            ? null
                                            : _captureResidenceCard,
                                        icon: const Icon(
                                          Icons.photo_camera_rounded,
                                        ),
                                        label: Text(
                                          context
                                              .l10n
                                              .authRegisterCaptureFromCamera,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (residenceCardImageFile != null) ...[
                                  const SizedBox(height: 8),
                                  if (residenceCardImageFile!.hasBytes)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: Image.memory(
                                        residenceCardImageFile!.bytes!,
                                        height: 180,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                  const SizedBox(height: 8),
                                  FilledButton.icon(
                                    onPressed: (auth.loading || extractingCard)
                                        ? null
                                        : _extractResidenceCardData,
                                    icon: extractingCard
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(
                                            Icons.document_scanner_rounded,
                                          ),
                                    label: Text(
                                      extractingCard
                                          ? context
                                                .l10n
                                                .authRegisterAnalyzingCard
                                          : context
                                                .l10n
                                                .authRegisterExtractDataAutomatically,
                                    ),
                                  ),
                                ],
                                if (extractedCard != null) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '${context.l10n.authRegisterExtractionConfidenceLabel}: ${(extractedCard!.confidence * 100).toStringAsFixed(0)}%',
                                    style: textStyle,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardFullName',
                                    controller: cardFullNameCtrl,
                                    label:
                                        context.l10n.authRegisterNameFromCard,
                                    hint:
                                        context.l10n.authRegisterExtractedName,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardTown',
                                    controller: cardTownCtrl,
                                    label: context.l10n.authRegisterBlockOrTown,
                                    hint: context.l10n.basmayaGroupHint,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardBuilding',
                                    controller: cardBuildingCtrl,
                                    label:
                                        context.l10n.authRegisterBuildingNumber,
                                    hint: '313',
                                    textDirection: TextDirection.ltr,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardFloor',
                                    controller: cardFloorCtrl,
                                    label: context.l10n.authRegisterFloorNumber,
                                    hint: '5',
                                    textDirection: TextDirection.ltr,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardApartment',
                                    controller: cardApartmentCtrl,
                                    label: context
                                        .l10n
                                        .authRegisterApartmentNumber,
                                    hint: '12',
                                    textDirection: TextDirection.ltr,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardContract',
                                    controller: cardContractCtrl,
                                    label:
                                        context.l10n.authRegisterContractNumber,
                                    hint: '024820',
                                    textDirection: TextDirection.ltr,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardVisibleId',
                                    controller: cardVisibleIdCtrl,
                                    label: context
                                        .l10n
                                        .authRegisterVisibleIdNumber,
                                    hint: '0445',
                                    textDirection: TextDirection.ltr,
                                  ),
                                  const SizedBox(height: 8),
                                  buildField(
                                    field: 'cardIssueDate',
                                    controller: cardIssueDateCtrl,
                                    label: context.l10n.authRegisterIssueDate,
                                    hint: 'YYYY-MM-DD',
                                    textDirection: TextDirection.ltr,
                                  ),
                                ],
                                const SizedBox(height: 14),
                                buildField(
                                  field: 'fullName',
                                  controller: fullNameCtrl,
                                  label: context.l10n.authRegisterFullName,
                                  hint: context.l10n.authRegisterFullNameHint,
                                ),
                                const SizedBox(height: 10),
                                buildField(
                                  field: 'phone',
                                  controller: phoneCtrl,
                                  label: context.l10n.authPhoneLabel,
                                  hint: '0770xxxxxxx',
                                  keyboardType: TextInputType.phone,
                                  textDirection: TextDirection.ltr,
                                ),
                                const SizedBox(height: 10),
                                buildField(
                                  field: 'pin',
                                  controller: pinCtrl,
                                  label: context.l10n.authPinLabel,
                                  hint: context.l10n.authRegisterPinHint,
                                  keyboardType: TextInputType.number,
                                  obscure: true,
                                  textDirection: TextDirection.ltr,
                                ),
                                const SizedBox(height: 10),
                                buildField(
                                  field: 'workTitle',
                                  controller: workTitleCtrl,
                                  label:
                                      context.l10n.authRegisterCurrentJobTitle,
                                  hint: context.l10n.authRegisterWorkTitleHint,
                                ),
                                const SizedBox(height: 10),
                                buildField(
                                  field: 'workCompany',
                                  controller: workCompanyCtrl,
                                  label:
                                      context.l10n.authRegisterCurrentCompany,
                                  hint:
                                      context.l10n.authRegisterWorkCompanyHint,
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
                                        if (!buildings.contains(
                                          selectedBuilding,
                                        )) {
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
                                  title: context
                                      .l10n
                                      .authRegisterProfileImageOptional,
                                  selectedFile: profileImageFile,
                                  existingImageUrl: null,
                                  onPick: () async {
                                    final picked = await pickImageFromDevice();
                                    if (!mounted || picked == null) return;
                                    setState(() {
                                      profileImageFile = picked;
                                      _formError = null;
                                    });
                                  },
                                  onClear: profileImageFile == null
                                      ? null
                                      : () => setState(
                                          () => profileImageFile = null,
                                        ),
                                ),
                                const SizedBox(height: 8),
                                _scrollCoordinator.anchor(
                                  'analyticsConsent',
                                  CheckboxListTile(
                                    value: analyticsConsentAccepted,
                                    onChanged: (v) {
                                      setState(() {
                                        analyticsConsentAccepted = v == true;
                                        _consentError = null;
                                        _formError = null;
                                      });
                                    },
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                    title: Text(
                                      context.l10n.authRegisterConsentCheckbox,
                                      style: const TextStyle(color: Colors.white),
                                    ),
                                    subtitle: _consentError == null
                                        ? null
                                        : Text(
                                            _consentError!,
                                            style: TextStyle(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.error,
                                            ),
                                          ),
                                  ),
                                ),
                                FilledButton.icon(
                                  onPressed: auth.loading ? null : _submit,
                                  icon: auth.loading
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                          ),
                                        )
                                      : const Icon(
                                          Icons.check_circle_outline_rounded,
                                        ),
                                  label: Text(
                                    residenceCardImageFile == null
                                        ? context.l10n.authRegisterCreateAccount
                                        : context
                                              .l10n
                                              .authRegisterConfirmAndCreateAccount,
                                  ),
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
            ),
          ),
        ],
      ),
    );
  }
}
