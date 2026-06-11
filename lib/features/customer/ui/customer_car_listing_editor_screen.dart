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
import '../data/car_catalog.dart';
import '../data/cars_api.dart';
import '../models/car_listing_model.dart';
import 'widgets/customer_car_listing_card.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CustomerCarListingEditorScreen extends ConsumerStatefulWidget {
  final CarListingModel? existing;

  const CustomerCarListingEditorScreen({super.key, this.existing});

  @override
  ConsumerState<CustomerCarListingEditorScreen> createState() =>
      _CustomerCarListingEditorScreenState();
}

class _CustomerCarListingEditorScreenState
    extends ConsumerState<CustomerCarListingEditorScreen> {
  final _titleCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _yearCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _mileageCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _colorCtrl = TextEditingController();
  final _scrollCoordinator = FormScrollCoordinator();
  final List<LocalImageFile> _images = <LocalImageFile>[];
  final Map<String, String> _fieldErrors = <String, String>{};

  late String _brand;
  late String _model;
  late String _condition;
  late String _transmission;
  late String _fuelType;
  late String _bodyType;
  bool _saving = false;
  String? _formError;

  CarsApi get _api => ref.read(carsApiProvider);

  List<String> get _brands {
    final existingBrand = widget.existing?.brand;
    final base = [...carBrandNames()];
    if (existingBrand != null &&
        existingBrand.isNotEmpty &&
        !base.contains(existingBrand)) {
      base.insert(0, existingBrand);
    }
    return base;
  }

  List<String> get _models {
    final base = [...carModelsForBrand(_brand)];
    final existingModel = widget.existing?.model;
    if (existingModel != null &&
        existingModel.isNotEmpty &&
        !base.contains(existingModel)) {
      base.insert(0, existingModel);
    }
    return base;
  }

  @override
  void initState() {
    super.initState();
    final item = widget.existing;
    _brand = item?.brand ?? (_brands.isNotEmpty ? _brands.first : 'Toyota');
    _model =
        item?.model ??
        (() {
          final models = carModelsForBrand(_brand);
          return models.isNotEmpty ? models.first : '';
        })();
    _condition = item?.condition ?? 'used';
    _transmission = item?.transmission ?? 'automatic';
    _fuelType = item?.fuelType ?? 'fuel';
    _bodyType = item?.bodyType ?? 'sedan';
    _titleCtrl.text = item?.title ?? '';
    _descriptionCtrl.text = item?.description ?? '';
    _yearCtrl.text = item == null ? '' : item.modelYear.toString();
    _priceCtrl.text = item == null ? '' : item.price.round().toString();
    _mileageCtrl.text = item?.mileageKm?.toString() ?? '';
    _cityCtrl.text = item?.city ?? '';
    _phoneCtrl.text = item?.phone ?? '';
    _colorCtrl.text = item?.color ?? '';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descriptionCtrl.dispose();
    _yearCtrl.dispose();
    _priceCtrl.dispose();
    _mileageCtrl.dispose();
    _cityCtrl.dispose();
    _phoneCtrl.dispose();
    _colorCtrl.dispose();
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
        return l10n.carsListingTitle;
      case 'brand':
        return l10n.carsBrand;
      case 'model':
        return l10n.carsModel;
      case 'modelYear':
        return l10n.carsModelYear;
      case 'price':
        return l10n.realEstatePrice;
      case 'mileageKm':
        return l10n.carsMileage;
      case 'phone':
        return l10n.carsPhone;
      case 'images':
        return l10n.carsPhotosSection;
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

  bool _validate() {
    final l10n = context.l10n;
    final next = <String, String>{};

    if (_titleCtrl.text.trim().isEmpty) {
      next['title'] = l10n.carsValidationTitleRequired;
    }
    if (_brand.trim().isEmpty) {
      next['brand'] = l10n.carsValidationBrandRequired;
    }
    if (_model.trim().isEmpty) {
      next['model'] = l10n.carsValidationModelRequired;
    }
    final modelYear = _parseIntOrNull(_yearCtrl.text);
    if (modelYear == null || modelYear < 1980 || modelYear > 2035) {
      next['modelYear'] = l10n.carsValidationModelYearRequired;
    }
    final price = _parseDoubleOrNull(_priceCtrl.text);
    if (price == null || price < 0) {
      next['price'] = l10n.carsValidationPriceRequired;
    }
    if (_condition == 'used') {
      final mileage = _parseIntOrNull(_mileageCtrl.text);
      if (mileage == null || mileage < 0) {
        next['mileageKm'] = l10n.carsValidationMileageRequired;
      }
    }
    if (_phoneCtrl.text.trim().isEmpty) {
      next['phone'] = l10n.carsValidationPhoneRequired;
    }
    if (widget.existing == null && _images.isEmpty) {
      next['images'] = l10n.carsValidationImagesRequired;
    }

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(next);
      _formError = next.isEmpty ? null : l10n.validationReviewRequiredFields;
    });
    return next.isEmpty;
  }

  Future<void> _focusFirstError() async {
    final ordered = <String>[
      if (_errorFor('title') != null) 'title',
      if (_errorFor('brand') != null) 'brand',
      if (_errorFor('model') != null) 'model',
      if (_errorFor('modelYear') != null) 'modelYear',
      if (_errorFor('price') != null) 'price',
      if (_errorFor('mileageKm') != null) 'mileageKm',
      if (_errorFor('phone') != null) 'phone',
      if (_errorFor('images') != null) 'images',
    ];
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
              fallback: context.l10n.carsSaveFailed,
            );
    });
    await _focusFirstError();
    return true;
  }

  Future<void> _pickImages() async {
    final remaining = 6 - _images.length;
    if (remaining <= 0) return;
    final picked = await pickMultipleImagesFromDevice(maxFiles: remaining);
    if (picked.isEmpty) return;
    setState(() {
      _images.addAll(picked);
      _fieldErrors.remove('images');
      _formError = null;
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    if (!_validate()) {
      await _focusFirstError();
      return;
    }
    setState(() => _saving = true);

    final body = <String, dynamic>{
      'title': _titleCtrl.text.trim(),
      'description': _descriptionCtrl.text.trim(),
      'brand': _brand,
      'model': _model,
      'modelYear': _yearCtrl.text.trim(),
      'condition': _condition,
      'price': _priceCtrl.text.trim(),
      'mileageKm': _condition == 'used' ? _mileageCtrl.text.trim() : '',
      'city': _cityCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'transmission': _transmission,
      'fuelType': _fuelType,
      'bodyType': _bodyType,
      'color': _colorCtrl.text.trim(),
    };

    try {
      final multipartFiles = <MultipartFile>[];
      for (final image in _images) {
        multipartFiles.add(await image.toMultipartFile());
      }
      if (widget.existing == null) {
        await _api.createSellerListing(body, imageFiles: multipartFiles);
      } else {
        await _api.updateSellerListing(
          widget.existing!.id,
          body,
          imageFiles: multipartFiles,
        );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on DioException catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      if (await _applyBackendErrors(error)) return;
      setState(() {
        _formError = mapAnyError(error, fallback: context.l10n.carsSaveFailed);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _formError = mapAnyError(error, fallback: context.l10n.carsSaveFailed);
      });
    }
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
      bool? enabled,
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
          enabled: enabled,
          onChanged: (_) => _clearFieldError(field),
          decoration: decoration.copyWith(errorText: _errorFor(field)),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.existing == null ? l10n.carsAddListing : l10n.carsEditListing,
        ),
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        child: FilledButton.icon(
          onPressed: _saving ? null : _save,
          icon: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_saving ? l10n.commonLoading : l10n.commonSave),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
        children: [
          FormErrorBanner(message: _formError),
          _SectionCard(
            title: l10n.carsBasicSection,
            children: [
              buildTextField(
                field: 'title',
                controller: _titleCtrl,
                decoration: InputDecoration(labelText: l10n.carsListingTitle),
              ),
              const SizedBox(height: 12),
              _scrollCoordinator.anchor(
                'brand',
                DropdownButtonFormField<String>(
                  key: ValueKey('brand:$_brand'),
                  initialValue: _brand,
                  decoration: InputDecoration(
                    labelText: l10n.carsBrand,
                    errorText: _errorFor('brand'),
                  ),
                  items: _brands
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(growable: false),
                  onChanged: (value) {
                    if (value == null || value == _brand) return;
                    final nextModels = carModelsForBrand(value);
                    setState(() {
                      _brand = value;
                      _model = nextModels.isNotEmpty ? nextModels.first : '';
                      _fieldErrors.remove('brand');
                      _fieldErrors.remove('model');
                      _formError = null;
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),
              _scrollCoordinator.anchor(
                'model',
                DropdownButtonFormField<String>(
                  key: ValueKey('model:${_brand}_$_model'),
                  initialValue: _model.isEmpty ? null : _model,
                  decoration: InputDecoration(
                    labelText: l10n.carsModel,
                    errorText: _errorFor('model'),
                  ),
                  items: _models
                      .map(
                        (value) =>
                            DropdownMenuItem(value: value, child: Text(value)),
                      )
                      .toList(growable: false),
                  onChanged: (value) => setState(() {
                    _model = value ?? '';
                    _fieldErrors.remove('model');
                    _formError = null;
                  }),
                ),
              ),
              const SizedBox(height: 12),
              buildTextField(
                field: 'description',
                controller: _descriptionCtrl,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(labelText: l10n.carsDescription),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: l10n.carsPricingSection,
            children: [
              Row(
                children: [
                  Expanded(
                    child: buildTextField(
                      field: 'modelYear',
                      controller: _yearCtrl,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: l10n.carsModelYear,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('condition:$_condition'),
                      initialValue: _condition,
                      decoration: InputDecoration(
                        labelText: l10n.carsCondition,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'new',
                          child: Text(l10n.carsConditionNew),
                        ),
                        DropdownMenuItem(
                          value: 'used',
                          child: Text(l10n.carsConditionUsed),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() {
                          _condition = value ?? 'used';
                          if (_condition != 'used') {
                            _fieldErrors.remove('mileageKm');
                          }
                          _formError = null;
                        });
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: buildTextField(
                      field: 'price',
                      controller: _priceCtrl,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      decoration: InputDecoration(
                        labelText: l10n.realEstatePrice,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: buildTextField(
                      field: 'mileageKm',
                      controller: _mileageCtrl,
                      keyboardType: TextInputType.number,
                      textDirection: TextDirection.ltr,
                      enabled: _condition == 'used',
                      decoration: InputDecoration(labelText: l10n.carsMileage),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: l10n.carsSpecsSection,
            children: [
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('transmission:$_transmission'),
                      initialValue: _transmission,
                      decoration: InputDecoration(
                        labelText: l10n.carsTransmission,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'automatic',
                          child: Text(l10n.carsTransmissionAutomatic),
                        ),
                        DropdownMenuItem(
                          value: 'manual',
                          child: Text(l10n.carsTransmissionManual),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _transmission = value ?? 'automatic');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('fuel:$_fuelType'),
                      initialValue: _fuelType,
                      decoration: InputDecoration(labelText: l10n.carsFuelType),
                      items: [
                        DropdownMenuItem(
                          value: 'fuel',
                          child: Text(l10n.carsFuelTypeFuel),
                        ),
                        DropdownMenuItem(
                          value: 'hybrid',
                          child: Text(l10n.carsFuelTypeHybrid),
                        ),
                        DropdownMenuItem(
                          value: 'electric',
                          child: Text(l10n.carsFuelTypeElectric),
                        ),
                      ],
                      onChanged: (value) {
                        setState(() => _fuelType = value ?? 'fuel');
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      key: ValueKey('body:$_bodyType'),
                      initialValue: _bodyType,
                      decoration: InputDecoration(labelText: l10n.carsBodyType),
                      items:
                          [
                                'sedan',
                                'suv',
                                'crossover',
                                'hatchback',
                                'pickup',
                                'van',
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(carBodyTypeLabel(context, value)),
                                ),
                              )
                              .toList(growable: false),
                      selectedItemBuilder: (context) =>
                          [
                                'sedan',
                                'suv',
                                'crossover',
                                'hatchback',
                                'pickup',
                                'van',
                              ]
                              .map(
                                (value) =>
                                    Text(carBodyTypeLabel(context, value)),
                              )
                              .toList(growable: false),
                      onChanged: (value) {
                        setState(() => _bodyType = value ?? 'sedan');
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: buildTextField(
                      field: 'color',
                      controller: _colorCtrl,
                      decoration: InputDecoration(labelText: l10n.carsColor),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          _SectionCard(
            title: l10n.carsContactSection,
            children: [
              buildTextField(
                field: 'city',
                controller: _cityCtrl,
                decoration: InputDecoration(labelText: l10n.carsCity),
              ),
              const SizedBox(height: 12),
              buildTextField(
                field: 'phone',
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: InputDecoration(labelText: l10n.carsPhone),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _scrollCoordinator.anchor(
            'images',
            _SectionCard(
              title: l10n.carsPhotosSection,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.carsImageLimitHint,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: _images.length >= 6 ? null : _pickImages,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(l10n.carsChoosePhotos),
                    ),
                  ],
                ),
                if (_errorFor('images') != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _errorFor('images')!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
                if ((widget.existing?.media.isNotEmpty ?? false) ||
                    _images.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 92,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: [
                        ...?widget.existing?.media.map(
                          (image) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 10),
                            child: _NetworkThumb(url: image.imageUrl),
                          ),
                        ),
                        ..._images.asMap().entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsetsDirectional.only(end: 10),
                            child: _LocalThumb(
                              file: entry.value,
                              onRemove: () {
                                setState(() {
                                  _images.removeAt(entry.key);
                                  _fieldErrors.remove('images');
                                  _formError = null;
                                });
                              },
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const _SectionCard({required this.title, required this.children});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 14),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _NetworkThumb extends StatelessWidget {
  final String url;

  const _NetworkThumb({required this.url});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        width: 92,
        height: 92,
        child: CachedAppImage(
          imageUrl: url,
          cacheIdentity: 'car_media_${url.hashCode}',
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}

class _LocalThumb extends StatelessWidget {
  final LocalImageFile file;
  final VoidCallback onRemove;

  const _LocalThumb({required this.file, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
            width: 92,
            height: 92,
            child: file.hasBytes
                ? Image.memory(file.bytes!, fit: BoxFit.cover)
                : Container(
                    color: Theme.of(
                      context,
                    ).colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: const Icon(Icons.image_outlined),
                  ),
          ),
        ),
        PositionedDirectional(
          top: 6,
          end: 6,
          child: Material(
            color: Colors.black.withValues(alpha: 0.45),
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onRemove,
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.close_rounded, size: 16, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
