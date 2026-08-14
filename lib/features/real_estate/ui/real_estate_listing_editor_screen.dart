import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/currency.dart';
import '../data/real_estate_api.dart';
import '../models/real_estate_models.dart';
import 'widgets/real_estate_listing_card.dart';

class RealEstateListingEditorScreen extends ConsumerStatefulWidget {
  final RealEstateListingModel? existing;

  const RealEstateListingEditorScreen({super.key, this.existing});

  @override
  ConsumerState<RealEstateListingEditorScreen> createState() =>
      _RealEstateListingEditorScreenState();
}

class _RealEstateListingEditorScreenState
    extends ConsumerState<RealEstateListingEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _bankAmountCtrl = TextEditingController();
  final _furnishingCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _blockCtrl = TextEditingController();
  final _buildingCtrl = TextEditingController();
  final _apartmentCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _roomsCtrl = TextEditingController();
  final _bathroomsCtrl = TextEditingController();
  final _floorCtrl = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();
  final List<LocalImageFile> _images = <LocalImageFile>[];
  final Map<String, String> _fieldErrors = <String, String>{};

  int _currentStep = 0;
  bool _saving = false;
  String _purpose = 'sale';
  String _bankSettlementMode = 'none';
  String _paymentMethod = 'cash';
  bool _furnished = false;
  String? _formError;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    if (existing != null) {
      _purpose = existing.purpose;
      _bankSettlementMode = existing.bankSettlementMode;
      _paymentMethod = existing.paymentMethod;
      _furnished = existing.furnished;
      _titleCtrl.text = existing.title;
      _descriptionCtrl.text = existing.description ?? '';
      _priceCtrl.text = existing.price.round().toString();
      _bankAmountCtrl.text = existing.bankSettlementAmount.round().toString();
      _furnishingCtrl.text = existing.furnishingDescription ?? '';
      _phoneCtrl.text = existing.phone;
      _cityCtrl.text = existing.city ?? '';
      _blockCtrl.text = existing.block ?? '';
      _buildingCtrl.text = existing.buildingNumber ?? '';
      _apartmentCtrl.text = existing.apartmentNumber ?? '';
      _areaCtrl.text = existing.areaSqm.toString();
      _roomsCtrl.text = existing.roomsCount?.toString() ?? '';
      _bathroomsCtrl.text = existing.bathroomsCount?.toString() ?? '';
      _floorCtrl.text = existing.floorNumber?.toString() ?? '';
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _priceCtrl.dispose();
    _bankAmountCtrl.dispose();
    _furnishingCtrl.dispose();
    _phoneCtrl.dispose();
    _cityCtrl.dispose();
    _blockCtrl.dispose();
    _buildingCtrl.dispose();
    _apartmentCtrl.dispose();
    _areaCtrl.dispose();
    _roomsCtrl.dispose();
    _bathroomsCtrl.dispose();
    _floorCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _errorFor(String key) => _fieldErrors[key];

  void _clearFieldError(String key) {
    if (!_fieldErrors.containsKey(key) && _formError == null) return;
    setState(() {
      _fieldErrors.remove(key);
      _formError = null;
    });
  }

  String _fieldLabel(BuildContext context, String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'title':
        return l10n.realEstateTitleLabel;
      case 'areaSqm':
        return l10n.realEstateAreaLabel;
      case 'price':
        return l10n.realEstatePriceLabel;
      case 'furnishingDescription':
        return l10n.realEstateFurnishingDescription;
      case 'phone':
        return l10n.realEstatePhone;
      case 'images':
        return l10n.realEstateImagesStep;
      default:
        return field;
    }
  }

  int? _parseIntOrNull(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return int.tryParse(text);
  }

  double? _parseDoubleOrNull(String value) {
    final text = value.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  bool _validateStep(int step) {
    final l10n = context.l10n;
    final next = <String, String>{};
    final area = _parseIntOrNull(_areaCtrl.text);
    final price = _parseDoubleOrNull(_priceCtrl.text);

    if (step >= 0) {
      if (_titleCtrl.text.trim().isEmpty) {
        next['title'] = l10n.realEstateValidationTitleRequired;
      }
      if (area == null || area <= 0) {
        next['areaSqm'] = l10n.realEstateValidationAreaRequired;
      }
    }
    if (step >= 1) {
      if (price == null || price < 0) {
        next['price'] = l10n.realEstateValidationPriceRequired;
      }
    }
    if (step >= 2) {
      if (_furnished && _furnishingCtrl.text.trim().isEmpty) {
        next['furnishingDescription'] =
            l10n.realEstateValidationFurnishingDetails;
      }
    }
    if (step >= 3) {
      if (_phoneCtrl.text.trim().isEmpty) {
        next['phone'] = l10n.realEstateValidationPhoneRequired;
      }
    }
    if (step >= 4 && widget.existing == null && _images.isEmpty) {
      next['images'] = l10n.realEstateValidationImagesRequired;
    }

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(next);
      _formError = next.isEmpty ? null : l10n.validationReviewRequiredFields;
    });
    return next.isEmpty;
  }

  int _stepForField(String field) {
    switch (field) {
      case 'title':
      case 'areaSqm':
        return 0;
      case 'price':
        return 1;
      case 'furnishingDescription':
        return 2;
      case 'phone':
        return 3;
      case 'images':
        return 4;
      default:
        return _currentStep;
    }
  }

  Future<void> _focusFirstError() async {
    final ordered = <String>[
      if (_errorFor('title') != null) 'title',
      if (_errorFor('areaSqm') != null) 'areaSqm',
      if (_errorFor('price') != null) 'price',
      if (_errorFor('furnishingDescription') != null) 'furnishingDescription',
      if (_errorFor('phone') != null) 'phone',
      if (_errorFor('images') != null) 'images',
    ];
    if (ordered.isEmpty) return;
    final firstStep = _stepForField(ordered.first);
    if (_currentStep != firstStep) {
      setState(() => _currentStep = firstStep);
      await Future<void>.delayed(const Duration(milliseconds: 16));
    }
    await _scrollCoordinator.focusFirstError(ordered);
  }

  Future<bool> _applyBackendErrors(Object error) async {
    final parsed = parseBackendFieldErrors(error);
    final nextErrors = <String, String>{};
    for (final entry in parsed.fieldCodes.entries) {
      nextErrors[entry.key] = resolveFormFieldError(
        l10n: context.l10n,
        field: entry.key,
        code: entry.value ?? parsed.messageCode,
        fieldLabel: _fieldLabel(context, entry.key),
      );
    }

    if (nextErrors.isEmpty &&
        (parsed.formCode == null || parsed.formCode!.isEmpty) &&
        (parsed.messageCode == null || parsed.messageCode!.isEmpty)) {
      return false;
    }

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(nextErrors);
      _formError = nextErrors.isNotEmpty
          ? context.l10n.validationReviewRequiredFields
          : resolveFormLevelError(
              context.l10n,
              code: parsed.formCode ?? parsed.messageCode,
              fallback: context.l10n.realEstateSaveFailed,
            );
    });
    await _focusFirstError();
    return true;
  }

  Future<void> _pickImages() async {
    final remaining = 10 - _images.length;
    if (remaining <= 0) return;
    final picked = await pickMultipleImagesFromDevice(maxFiles: remaining);
    if (picked.isEmpty) return;
    setState(() {
      _images.addAll(picked);
      _fieldErrors.remove('images');
      _formError = null;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    if (!_validateStep(5)) {
      await _focusFirstError();
      return;
    }
    setState(() => _saving = true);

    final body = <String, dynamic>{
      'purpose': _purpose,
      'title': _titleCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'areaSqm': _parseIntOrNull(_areaCtrl.text),
      'price': _parseDoubleOrNull(_priceCtrl.text),
      'bankSettlementAmount': _parseDoubleOrNull(_bankAmountCtrl.text) ?? 0,
      'bankSettlementMode': _bankSettlementMode,
      'paymentMethod': _paymentMethod,
      'furnished': _furnished,
      'furnishingDescription': _furnished ? _furnishingCtrl.text.trim() : null,
      'phone': _phoneCtrl.text.trim(),
      'city': _cityCtrl.text.trim(),
      'block': _blockCtrl.text.trim(),
      'buildingNumber': _buildingCtrl.text.trim(),
      'apartmentNumber': _apartmentCtrl.text.trim(),
      'roomsCount': _parseIntOrNull(_roomsCtrl.text),
      'bathroomsCount': _parseIntOrNull(_bathroomsCtrl.text),
      'floorNumber': _parseIntOrNull(_floorCtrl.text),
      'detailsJson': const <String, dynamic>{},
    };

    try {
      if (widget.existing == null) {
        await ref
            .read(realEstateApiProvider)
            .createListing(body, imageFiles: _images);
      } else {
        await ref
            .read(realEstateApiProvider)
            .updateListing(widget.existing!.id, body, imageFiles: _images);
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (await _applyBackendErrors(error)) return;
      setState(() {
        _formError = mapAnyError(
          error,
          fallback: context.l10n.realEstateSaveFailed,
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = mapAnyError(
          error,
          fallback: context.l10n.realEstateSaveFailed,
        );
      });
    }
  }

  RealEstateListingModel _previewListing() {
    final existing = widget.existing;
    return RealEstateListingModel(
      id: existing?.id ?? 0,
      ownerId: existing?.ownerId ?? 0,
      ownerFullName: existing?.ownerFullName,
      ownerPhone: existing?.ownerPhone,
      purpose: _purpose,
      status: existing?.status ?? 'active',
      title: _titleCtrl.text.trim(),
      description: _descriptionCtrl.text.trim(),
      areaSqm: _parseIntOrNull(_areaCtrl.text) ?? 0,
      bankSettlementAmount: _parseDoubleOrNull(_bankAmountCtrl.text) ?? 0,
      bankSettlementMode: _bankSettlementMode,
      furnished: _furnished,
      furnishingDescription: _furnishingCtrl.text.trim(),
      phone: _phoneCtrl.text.trim(),
      price: _parseDoubleOrNull(_priceCtrl.text) ?? 0,
      city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
      block: _blockCtrl.text.trim().isEmpty ? null : _blockCtrl.text.trim(),
      buildingNumber: _buildingCtrl.text.trim().isEmpty
          ? null
          : _buildingCtrl.text.trim(),
      apartmentNumber: _apartmentCtrl.text.trim().isEmpty
          ? null
          : _apartmentCtrl.text.trim(),
      roomsCount: _parseIntOrNull(_roomsCtrl.text),
      bathroomsCount: _parseIntOrNull(_bathroomsCtrl.text),
      floorNumber: _parseIntOrNull(_floorCtrl.text),
      paymentMethod: _paymentMethod,
      isFeatured: existing?.isFeatured ?? false,
      viewCount: existing?.viewCount ?? 0,
      isSaved: existing?.isSaved ?? false,
      detailsJson: const <String, dynamic>{},
      reviewNote: existing?.reviewNote,
      reviewedByUserId: existing?.reviewedByUserId,
      reviewedAt: existing?.reviewedAt,
      lastVisibleStatus: existing?.lastVisibleStatus,
      hiddenDueSubscriptionExpiryAt: existing?.hiddenDueSubscriptionExpiryAt,
      soldAt: existing?.soldAt,
      rentedAt: existing?.rentedAt,
      archivedAt: existing?.archivedAt,
      createdAt: existing?.createdAt,
      updatedAt: existing?.updatedAt,
      media: existing?.media ?? const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;

    Widget buildTextField({
      required String field,
      required TextEditingController controller,
      required InputDecoration decoration,
      TextInputType? keyboardType,
      TextDirection? textDirection,
      int? minLines,
      int? maxLines = 1,
    }) {
      return _scrollCoordinator.anchor(
        field,
        TextField(
          controller: controller,
          focusNode: _scrollCoordinator.focusNodeFor(field),
          keyboardType: keyboardType,
          textDirection: textDirection,
          minLines: minLines,
          maxLines: maxLines,
          onChanged: (_) => _clearFieldError(field),
          decoration: decoration.copyWith(errorText: _errorFor(field)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null
              ? l10n.realEstateAddTitle
              : l10n.realEstateEditTitle,
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: FormErrorBanner(message: _formError),
          ),
          Expanded(
            child: Stepper(
              type: StepperType.vertical,
              currentStep: _currentStep,
              onStepTapped: (value) => setState(() => _currentStep = value),
              onStepContinue: () async {
                if (_currentStep == 5) {
                  await _submit();
                  return;
                }
                if (_validateStep(_currentStep)) {
                  setState(() => _currentStep += 1);
                } else {
                  await _focusFirstError();
                }
              },
              onStepCancel: () {
                if (_currentStep == 0) {
                  Navigator.of(context).maybePop();
                  return;
                }
                setState(() => _currentStep -= 1);
              },
              controlsBuilder: (context, details) {
                return Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton(
                          onPressed: _saving ? null : details.onStepContinue,
                          child: Text(
                            _currentStep == 5
                                ? l10n.commonPublish
                                : l10n.commonNext,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _saving ? null : details.onStepCancel,
                          child: Text(
                            _currentStep == 0
                                ? l10n.commonCancel
                                : l10n.commonBack,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
              steps: [
                Step(
                  title: Text(l10n.realEstateBasicStep),
                  isActive: _currentStep >= 0,
                  content: Column(
                    children: [
                      DropdownButtonFormField<String>(
                        initialValue: _purpose,
                        decoration: InputDecoration(
                          labelText: l10n.realEstatePurposeLabel,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'sale',
                            child: Text(l10n.realEstateSale),
                          ),
                          DropdownMenuItem(
                            value: 'rent',
                            child: Text(l10n.realEstateRent),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _purpose = value ?? 'sale'),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'title',
                        controller: _titleCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateTitleLabel,
                          hintText: l10n.realEstateTitlePlaceholder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'areaSqm',
                        controller: _areaCtrl,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateAreaLabel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'description',
                        controller: _descriptionCtrl,
                        minLines: 4,
                        maxLines: 6,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateDescription,
                          hintText: l10n.realEstateDescriptionPlaceholder,
                        ),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: Text(l10n.realEstatePricingStep),
                  isActive: _currentStep >= 1,
                  content: Column(
                    children: [
                      buildTextField(
                        field: 'price',
                        controller: _priceCtrl,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: l10n.realEstatePriceLabel,
                        ),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _paymentMethod,
                        decoration: InputDecoration(
                          labelText: l10n.realEstatePaymentMethodLabel,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'cash',
                            child: Text(l10n.realEstateCash),
                          ),
                          DropdownMenuItem(
                            value: 'installments',
                            child: Text(l10n.realEstateInstallments),
                          ),
                          DropdownMenuItem(
                            value: 'negotiable',
                            child: Text(l10n.realEstateNegotiable),
                          ),
                        ],
                        onChanged: (value) =>
                            setState(() => _paymentMethod = value ?? 'cash'),
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        initialValue: _bankSettlementMode,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateSettlementMode,
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'none',
                            child: Text(l10n.realEstateSettlementNone),
                          ),
                          DropdownMenuItem(
                            value: 'partial',
                            child: Text(l10n.realEstateSettlementPartial),
                          ),
                          DropdownMenuItem(
                            value: 'full',
                            child: Text(l10n.realEstateSettlementFull),
                          ),
                        ],
                        onChanged: (value) => setState(
                          () => _bankSettlementMode = value ?? 'none',
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'bankSettlementAmount',
                        controller: _bankAmountCtrl,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateBankAmountLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: Text(l10n.realEstateSpecsStep),
                  isActive: _currentStep >= 2,
                  content: Column(
                    children: [
                      SwitchListTile.adaptive(
                        contentPadding: EdgeInsets.zero,
                        value: _furnished,
                        onChanged: (value) => setState(() {
                          _furnished = value;
                          _fieldErrors.remove('furnishingDescription');
                          _formError = null;
                        }),
                        title: Text(l10n.realEstateFurnished),
                      ),
                      if (_furnished) ...[
                        const SizedBox(height: 8),
                        buildTextField(
                          field: 'furnishingDescription',
                          controller: _furnishingCtrl,
                          minLines: 2,
                          maxLines: 4,
                          decoration: InputDecoration(
                            labelText: l10n.realEstateFurnishingDescription,
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: buildTextField(
                              field: 'roomsCount',
                              controller: _roomsCtrl,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(
                                labelText: l10n.realEstateRoomsLabel,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: buildTextField(
                              field: 'bathroomsCount',
                              controller: _bathroomsCtrl,
                              keyboardType: TextInputType.number,
                              textDirection: TextDirection.ltr,
                              decoration: InputDecoration(
                                labelText: l10n.realEstateBathroomsLabel,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'floorNumber',
                        controller: _floorCtrl,
                        keyboardType: TextInputType.number,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateFloorLabel,
                        ),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: Text(l10n.realEstateContactStep),
                  isActive: _currentStep >= 3,
                  content: Column(
                    children: [
                      buildTextField(
                        field: 'phone',
                        controller: _phoneCtrl,
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: InputDecoration(
                          labelText: l10n.realEstatePhone,
                          hintText: l10n.realEstatePhonePlaceholder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'city',
                        controller: _cityCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateCity,
                          hintText: l10n.realEstateCityPlaceholder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'block',
                        controller: _blockCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateBlock,
                          hintText: l10n.realEstateBlockPlaceholder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'buildingNumber',
                        controller: _buildingCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateBuildingNumber,
                          hintText: l10n.realEstateBuildingPlaceholder,
                        ),
                      ),
                      const SizedBox(height: 12),
                      buildTextField(
                        field: 'apartmentNumber',
                        controller: _apartmentCtrl,
                        decoration: InputDecoration(
                          labelText: l10n.realEstateApartmentNumber,
                          hintText: l10n.realEstateApartmentPlaceholder,
                        ),
                      ),
                    ],
                  ),
                ),
                Step(
                  title: Text(l10n.realEstateImagesStep),
                  isActive: _currentStep >= 4,
                  content: _scrollCoordinator.anchor(
                    'images',
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(l10n.realEstateImagesHint),
                        if (widget.existing != null &&
                            widget.existing!.media.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            l10n.realEstateKeepCurrentImages,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _images.length >= 10
                                    ? null
                                    : _pickImages,
                                icon: const Icon(Icons.photo_library_outlined),
                                label: Text(l10n.realEstateAddImages),
                              ),
                            ),
                          ],
                        ),
                        if (_errorFor('images') != null) ...[
                          const SizedBox(height: 8),
                          Text(
                            _errorFor('images')!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (_images.isNotEmpty)
                          SizedBox(
                            height: 112,
                            child: ReorderableListView.builder(
                              scrollDirection: Axis.horizontal,
                              buildDefaultDragHandles: false,
                              itemCount: _images.length,
                              onReorderItem: (oldIndex, newIndex) {
                                // onReorderItem already adjusts newIndex for the
                                // removed item, so no manual `newIndex -= 1`.
                                setState(() {
                                  final item = _images.removeAt(oldIndex);
                                  _images.insert(newIndex, item);
                                });
                              },
                              itemBuilder: (context, index) {
                                final image = _images[index];
                                return Padding(
                                  key: ValueKey('${image.name}-$index'),
                                  padding: const EdgeInsetsDirectional.only(
                                    end: 12,
                                  ),
                                  child: Stack(
                                    children: [
                                      Container(
                                        width: 110,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(
                                            18,
                                          ),
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.surfaceContainerHighest,
                                        ),
                                        clipBehavior: Clip.antiAlias,
                                        child: image.hasBytes
                                            ? Image.memory(
                                                image.bytes!,
                                                fit: BoxFit.cover,
                                              )
                                            : const SizedBox.shrink(),
                                      ),
                                      PositionedDirectional(
                                        top: 4,
                                        end: 4,
                                        child: IconButton.filledTonal(
                                          onPressed: () => setState(() {
                                            _images.removeAt(index);
                                            _fieldErrors.remove('images');
                                            _formError = null;
                                          }),
                                          icon: const Icon(
                                            Icons.close_rounded,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                      PositionedDirectional(
                                        bottom: 6,
                                        end: 6,
                                        child: ReorderableDragStartListener(
                                          index: index,
                                          child: const CircleAvatar(
                                            radius: 16,
                                            child: Icon(
                                              Icons.drag_handle_rounded,
                                            ),
                                          ),
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
                Step(
                  title: Text(l10n.realEstatePreviewStep),
                  isActive: _currentStep >= 5,
                  content: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.realEstatePreviewSubtitle),
                      const SizedBox(height: 12),
                      RealEstateListingCard(
                        listing: _previewListing(),
                        compact: true,
                      ),
                      const SizedBox(height: 12),
                      _PreviewRow(
                        label: l10n.realEstatePrice,
                        value: formatIqd(
                          _parseDoubleOrNull(_priceCtrl.text) ?? 0,
                        ),
                      ),
                      _PreviewRow(
                        label: l10n.realEstatePaymentMethod,
                        value: paymentMethodLabel(context, _paymentMethod),
                      ),
                      _PreviewRow(
                        label: l10n.realEstateSettlementMode,
                        value: settlementModeLabel(
                          context,
                          _bankSettlementMode,
                        ),
                      ),
                      _PreviewRow(
                        label: l10n.realEstateLocation,
                        value: [
                          if (_cityCtrl.text.trim().isNotEmpty)
                            _cityCtrl.text.trim(),
                          if (_blockCtrl.text.trim().isNotEmpty)
                            _blockCtrl.text.trim(),
                          if (_buildingCtrl.text.trim().isNotEmpty)
                            _buildingCtrl.text.trim(),
                        ].join(' • '),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  final String label;
  final String value;

  const _PreviewRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value.isEmpty ? context.l10n.commonUnknown : value,
              textAlign: TextAlign.end,
            ),
          ),
          const SizedBox(width: 16),
          Text(label, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
