import 'package:flutter/material.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../../core/utils/currency.dart';
import '../../products/models/product_category_model.dart';
import '../../products/models/product_model.dart';
import '../../products/ui/product_summary_card.dart';

class ProductFormData {
  final String name;
  final String description;
  final int categoryId;
  final String price;
  final String discountedPrice;
  final String imageUrl;
  final LocalImageFile? imageFile;
  final List<LocalImageFile> galleryFiles;
  final List<LocalImageFile> variantFiles;
  final String stockQuantity;
  final List<Map<String, dynamic>> attributes;
  final List<Map<String, dynamic>> variantGroups;
  final List<Map<String, dynamic>> variants;
  final List<Map<String, dynamic>> media;
  final bool freeDelivery;
  final bool requiresPrescription;
  final bool requiresReview;
  final String offerLabel;
  final bool isAvailable;
  final int sortOrder;

  const ProductFormData({
    required this.name,
    required this.description,
    required this.categoryId,
    required this.price,
    required this.discountedPrice,
    required this.imageUrl,
    required this.imageFile,
    required this.galleryFiles,
    required this.variantFiles,
    required this.stockQuantity,
    required this.attributes,
    required this.variantGroups,
    required this.variants,
    required this.media,
    required this.freeDelivery,
    required this.requiresPrescription,
    required this.requiresReview,
    required this.offerLabel,
    required this.isAvailable,
    required this.sortOrder,
  });
}

class ProductFormSheet extends StatefulWidget {
  final ProductModel? product;
  final List<ProductCategoryModel> categories;
  final bool supportsPharmacyWorkflow;

  const ProductFormSheet({
    super.key,
    this.product,
    required this.categories,
    this.supportsPharmacyWorkflow = false,
  });

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  late final TextEditingController nameCtrl;
  late final TextEditingController descCtrl;
  late final TextEditingController priceCtrl;
  late final TextEditingController discountCtrl;
  late final TextEditingController imageCtrl;
  late final TextEditingController stockCtrl;
  late final TextEditingController sortCtrl;
  late final TextEditingController offerCtrl;
  final Map<String, TextEditingController> _attributeCtrls = {};
  final List<_SpecDraft> _shortSpecs = [];
  final List<_SpecDraft> _fullSpecs = [];
  final List<_ColorDraft> _colors = [];
  final List<TextEditingController> _sizes = [];
  final Map<String, _VariantDraft> _variants = {};
  final List<LocalImageFile> _galleryFiles = [];
  late List<Map<String, dynamic>> _existingMedia;
  LocalImageFile? imageFile;
  late bool isAvailable;
  late bool freeDelivery;
  late bool requiresPrescription;
  late bool requiresReview;
  int? categoryId;

  ProductCategoryModel? get _category {
    for (final category in widget.categories) {
      if (category.id == categoryId) return category;
    }
    return null;
  }

  String get _catalogType => _category?.catalogType ?? 'generic';

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
    stockCtrl = TextEditingController(
      text: product?.stockQuantity?.toString() ?? '',
    );
    sortCtrl = TextEditingController(
      text: product?.sortOrder.toString() ?? '0',
    );
    offerCtrl = TextEditingController(text: product?.offerLabel ?? '');
    isAvailable = product?.isAvailable ?? true;
    freeDelivery = product?.freeDelivery ?? false;
    requiresPrescription = product?.requiresPrescription ?? false;
    requiresReview = product?.requiresReview ?? false;
    categoryId =
        product?.categoryId ??
        (widget.categories.isEmpty ? null : widget.categories.first.id);
    _existingMedia = (product?.media ?? const [])
        .where((item) => !item.isPrimary)
        .map(
          (item) => <String, dynamic>{
            'imageUrl': item.imageUrl,
            'altText': item.altText,
            'isPrimary': false,
            'sortOrder': item.sortOrder,
            'variantGroupCode': item.variantGroupCode,
            'variantOptionCode': item.variantOptionCode,
          },
        )
        .toList();
    _seedAttributes(product);
    _seedOptions(product);
  }

  void _seedAttributes(ProductModel? product) {
    final categoryCodes = _allCategoryCodes;
    for (final attr in product?.attributes ?? const <ProductAttributeModel>[]) {
      if (categoryCodes.contains(attr.code)) {
        _attributeCtrls[attr.code] = TextEditingController(
          text: attr.valueText,
        );
      } else {
        final draft = _SpecDraft(
          label: attr.title,
          value: attr.valueText,
          showInCard: attr.showInCard,
          valueType: '${attr.metadata['valueType'] ?? 'text'}',
          filterable: attr.metadata['filterable'] == true,
        );
        (attr.showInCard ? _shortSpecs : _fullSpecs).add(draft);
      }
    }
  }

  void _seedOptions(ProductModel? product) {
    for (final group
        in product?.variantGroups ?? const <ProductVariantGroupModel>[]) {
      if (group.code == 'color') {
        for (final option in group.options) {
          _colors.add(
            _ColorDraft(
              name: option.title,
              hex: option.swatchHex ?? '',
              imageUrl: option.imageUrl ?? '',
            ),
          );
        }
      } else if (group.code == 'size') {
        for (final option in group.options) {
          _sizes.add(TextEditingController(text: option.title));
        }
      }
    }
    for (final variant in product?.variants ?? const <ProductVariantModel>[]) {
      _variants[variant.signature] = _VariantDraft.fromModel(variant);
    }
  }

  Set<String> get _allCategoryCodes => _categoryFields.values
      .expand((items) => items)
      .map((item) => item.code)
      .toSet();

  @override
  void dispose() {
    for (final controller in [
      nameCtrl,
      descCtrl,
      priceCtrl,
      discountCtrl,
      imageCtrl,
      stockCtrl,
      sortCtrl,
      offerCtrl,
    ]) {
      controller.dispose();
    }
    for (final controller in _attributeCtrls.values) {
      controller.dispose();
    }
    for (final draft in [..._shortSpecs, ..._fullSpecs]) {
      draft.dispose();
    }
    for (final color in _colors) {
      color.dispose();
    }
    for (final size in _sizes) {
      size.dispose();
    }
    for (final variant in _variants.values) {
      variant.dispose();
    }
    super.dispose();
  }

  String _categoryLabel(ProductCategoryModel category) {
    if (category.catalogType == 'clothes' &&
        const {
          'cloths',
          'clothes',
        }.contains(category.name.trim().toLowerCase())) {
      return 'Clothes / ملابس';
    }
    return category.name;
  }

  List<_FieldDefinition> get _activeFields =>
      _categoryFields[_catalogType] ?? const [];

  TextEditingController _attributeController(String code) =>
      _attributeCtrls.putIfAbsent(code, TextEditingController.new);

  String _slug(String value, String fallback) {
    final normalized = value.trim().toLowerCase().replaceAll(
      RegExp(r'[^a-z0-9\u0600-\u06ff]+'),
      '_',
    );
    return normalized.isEmpty ? fallback : normalized;
  }

  List<Map<String, dynamic>> _buildAttributes() {
    final attributes = <Map<String, dynamic>>[];
    for (final field in _activeFields) {
      final value = _attributeController(field.code).text.trim();
      if (value.isEmpty) continue;
      attributes.add({
        'code': field.code,
        'labelAr': field.label,
        'labelEn': field.labelEn,
        'valueText': value,
        'showInCard': field.showInCard,
        'showInDetails': true,
        'metadata': {
          'valueType': field.valueType,
          'filterable': true,
          'catalogType': _catalogType,
        },
      });
    }
    var index = 0;
    for (final draft in _shortSpecs.where((item) => item.isValid).take(5)) {
      attributes.add(draft.toJson('summary_${++index}', showInCard: true));
    }
    index = 0;
    for (final draft in _fullSpecs.where((item) => item.isValid)) {
      attributes.add(draft.toJson('detail_${++index}', showInCard: false));
    }
    return attributes;
  }

  List<Map<String, dynamic>> _buildVariantGroups(
    List<LocalImageFile> variantFiles,
  ) {
    final groups = <Map<String, dynamic>>[];
    final colors = _colors
        .where((item) => item.name.text.trim().isNotEmpty)
        .toList();
    final sizes = _sizes.where((item) => item.text.trim().isNotEmpty).toList();
    if (colors.isNotEmpty) {
      groups.add({
        'code': 'color',
        'labelAr': 'اللون',
        'labelEn': 'Color',
        'displayMode': 'swatches',
        'selectionMode': 'single',
        'required': true,
        'options': colors.asMap().entries.map((entry) {
          final draft = entry.value;
          final uploadIndex = draft.imageFile == null
              ? null
              : variantFiles.length;
          if (draft.imageFile != null) {
            variantFiles.add(draft.imageFile!);
          }
          final imageUrl = draft.imageUrl.text.trim();
          final option = <String, dynamic>{
            'code': _slug(draft.name.text, 'color_${entry.key + 1}'),
            'labelAr': draft.name.text.trim(),
            'labelEn': draft.name.text.trim(),
            'swatchHex': draft.hex.text.trim(),
          };
          if (imageUrl.isNotEmpty) option['imageUrl'] = imageUrl;
          if (uploadIndex != null) option['uploadIndex'] = uploadIndex;
          option['isAvailable'] = true;
          return option;
        }).toList(),
      });
    }
    if (sizes.isNotEmpty) {
      groups.add({
        'code': 'size',
        'labelAr': 'المقاس',
        'labelEn': 'Size',
        'displayMode': 'chips',
        'selectionMode': 'single',
        'required': true,
        'options': sizes
            .asMap()
            .entries
            .map(
              (entry) => {
                'code': _slug(entry.value.text, 'size_${entry.key + 1}'),
                'labelAr': entry.value.text.trim(),
                'labelEn': entry.value.text.trim(),
                'isAvailable': true,
              },
            )
            .toList(),
      });
    }
    if (_catalogType == 'restaurant') {
      final paid = _attributeController('paid_additions').text
          .split(RegExp(r'[,\n]'))
          .map((line) => line.trim())
          .where((line) => line.isNotEmpty)
          .toList();
      if (paid.isNotEmpty) {
        groups.add({
          'code': 'paid_additions',
          'labelAr': 'الإضافات المدفوعة',
          'labelEn': 'Paid additions',
          'displayMode': 'chips',
          'selectionMode': 'multiple',
          'required': false,
          'options': paid.asMap().entries.map((entry) {
            final parts = entry.value.split(':');
            final label = parts.first.trim();
            final price = parts.length > 1
                ? double.tryParse(parts.last.trim()) ?? 0
                : 0;
            return {
              'code': _slug(label, 'addition_${entry.key + 1}'),
              'labelAr': label,
              'labelEn': label,
              'priceDelta': price,
              'isAvailable': true,
            };
          }).toList(),
        });
      }
    }
    return groups;
  }

  List<String> _combinationSignatures() {
    final colors = _colors
        .where((item) => item.name.text.trim().isNotEmpty)
        .toList();
    final sizes = _sizes.where((item) => item.text.trim().isNotEmpty).toList();
    if (colors.isEmpty && sizes.isEmpty) return const [];
    if (colors.isEmpty) {
      return sizes
          .asMap()
          .entries
          .map(
            (entry) =>
                'size:${_slug(entry.value.text, 'size_${entry.key + 1}')}',
          )
          .toList();
    }
    if (sizes.isEmpty) {
      return colors
          .asMap()
          .entries
          .map(
            (entry) =>
                'color:${_slug(entry.value.name.text, 'color_${entry.key + 1}')}',
          )
          .toList();
    }
    return [
      for (final color in colors.asMap().entries)
        for (final size in sizes.asMap().entries)
          'color:${_slug(color.value.name.text, 'color_${color.key + 1}')}|size:${_slug(size.value.text, 'size_${size.key + 1}')}',
    ];
  }

  void _syncVariants() {
    final signatures = _combinationSignatures();
    for (final signature in signatures) {
      _variants.putIfAbsent(
        signature,
        () => _VariantDraft(signature: signature),
      );
    }
    final stale = _variants.keys
        .where((key) => !signatures.contains(key))
        .toList();
    for (final key in stale) {
      _variants.remove(key)?.dispose();
    }
  }

  List<Map<String, dynamic>> _buildVariants(List<LocalImageFile> files) {
    _syncVariants();
    return _variants.values.toList().asMap().entries.map((entry) {
      final draft = entry.value;
      final selections = draft.signature.split('|').map((part) {
        final split = part.split(':');
        return {
          'groupCode': split.first,
          'optionCode': split.skip(1).join(':'),
        };
      }).toList();
      int? uploadIndex;
      if (draft.imageFile != null) {
        uploadIndex = files.length;
        files.add(draft.imageFile!);
      }
      return {
        'selections': selections,
        'sku': draft.sku.text.trim(),
        'barcode': draft.barcode.text.trim(),
        'material': draft.material.text.trim(),
        'priceOverride': double.tryParse(draft.price.text.trim()),
        'discountedPriceOverride': double.tryParse(draft.discount.text.trim()),
        'stockQuantity': int.tryParse(draft.stock.text.trim()) ?? 0,
        'imageUrl': draft.imageUrl,
        'uploadIndex': ?uploadIndex,
        'isAvailable': draft.available,
        'sortOrder': entry.key,
      };
    }).toList();
  }

  void _submit() {
    if (nameCtrl.text.trim().isEmpty ||
        priceCtrl.text.trim().isEmpty ||
        categoryId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اسم المنتج والقسم والسعر مطلوبة')),
      );
      return;
    }
    final variantFiles = <LocalImageFile>[];
    final variantGroups = _buildVariantGroups(variantFiles);
    final variants = _buildVariants(variantFiles);
    final media = <Map<String, dynamic>>[
      ..._existingMedia,
      for (var i = 0; i < _galleryFiles.length; i++)
        {
          'uploadIndex': i,
          'isPrimary': false,
          'sortOrder': _existingMedia.length + i,
        },
    ];
    Navigator.pop(
      context,
      ProductFormData(
        name: nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
        categoryId: categoryId!,
        price: priceCtrl.text.trim(),
        discountedPrice: discountCtrl.text.trim(),
        imageUrl: imageCtrl.text.trim(),
        imageFile: imageFile,
        galleryFiles: List.unmodifiable(_galleryFiles),
        variantFiles: variantFiles,
        stockQuantity: variants.isEmpty ? stockCtrl.text.trim() : '',
        attributes: _buildAttributes(),
        variantGroups: variantGroups,
        variants: variants,
        media: media,
        freeDelivery: freeDelivery,
        requiresPrescription: requiresPrescription,
        requiresReview: requiresReview,
        offerLabel: offerCtrl.text.trim(),
        isAvailable: isAvailable,
        sortOrder: int.tryParse(sortCtrl.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: SizedBox(
            height: MediaQuery.sizeOf(context).height * .94,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Text(
                          isEdit ? 'تعديل المنتج' : 'إضافة منتج',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 48),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(14, 4, 14, 18),
                    children: [
                      _section(
                        'المعلومات الأساسية',
                        initiallyExpanded: true,
                        children: [
                          _field(nameCtrl, 'اسم المنتج'),
                          DropdownButtonFormField<int>(
                            initialValue: categoryId,
                            items: widget.categories
                                .map(
                                  (category) => DropdownMenuItem(
                                    value: category.id,
                                    child: Text(_categoryLabel(category)),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) => setState(() {
                              categoryId = value;
                              _syncVariants();
                            }),
                            decoration: const InputDecoration(
                              labelText: 'القسم',
                            ),
                          ),
                          _field(descCtrl, 'الوصف', lines: 2),
                        ],
                      ),
                      _section(
                        'الصور',
                        children: [
                          ImagePickerField(
                            title: 'صورة المنتج الأساسية (اختيارية)',
                            selectedFile: imageFile,
                            existingImageUrl: imageCtrl.text.trim().isEmpty
                                ? null
                                : imageCtrl.text.trim(),
                            onPick: () async {
                              final picked = await pickImageFromDevice();
                              if (mounted && picked != null) {
                                setState(() => imageFile = picked);
                              }
                            },
                            onClear:
                                imageFile == null &&
                                    imageCtrl.text.trim().isEmpty
                                ? null
                                : () => setState(() {
                                    imageFile = null;
                                    imageCtrl.clear();
                                  }),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              ..._existingMedia.asMap().entries.map(
                                (entry) => InputChip(
                                  label: Text('صورة محفوظة ${entry.key + 1}'),
                                  onDeleted: () => setState(
                                    () => _existingMedia.removeAt(entry.key),
                                  ),
                                ),
                              ),
                              ..._galleryFiles.asMap().entries.map(
                                (entry) => InputChip(
                                  label: Text(entry.value.name),
                                  onDeleted: () => setState(
                                    () => _galleryFiles.removeAt(entry.key),
                                  ),
                                ),
                              ),
                              ActionChip(
                                label: const Text('إضافة صورة للمعرض'),
                                avatar: const Icon(
                                  Icons.add_photo_alternate_outlined,
                                ),
                                onPressed: () async {
                                  final picked = await pickImageFromDevice();
                                  if (mounted && picked != null) {
                                    setState(() => _galleryFiles.add(picked));
                                  }
                                },
                              ),
                            ],
                          ),
                        ],
                      ),
                      _section(
                        'السعر والمخزون',
                        initiallyExpanded: true,
                        children: [
                          _field(priceCtrl, 'السعر', number: true),
                          _field(
                            discountCtrl,
                            'السعر بعد الخصم (اختياري)',
                            number: true,
                          ),
                          if (_variants.isEmpty &&
                              _combinationSignatures().isEmpty)
                            _field(
                              stockCtrl,
                              'مخزون المنتج (اتركه فارغاً لعدم تتبع المخزون)',
                              number: true,
                            ),
                          _field(offerCtrl, 'وصف العرض'),
                          SwitchListTile(
                            title: const Text('توصيل مجاني لهذا المنتج'),
                            value: freeDelivery,
                            onChanged: (value) =>
                                setState(() => freeDelivery = value),
                          ),
                          _field(sortCtrl, 'ترتيب العرض', number: true),
                          SwitchListTile(
                            title: const Text('متاح للبيع'),
                            value: isAvailable,
                            onChanged: (value) =>
                                setState(() => isAvailable = value),
                          ),
                        ],
                      ),
                      if (_activeFields.isNotEmpty)
                        _section(
                          'تفاصيل حسب نوع المنتج — ${_catalogTypeLabel(_catalogType)}',
                          initiallyExpanded: true,
                          children: _activeFields
                              .map(
                                (field) => _field(
                                  _attributeController(field.code),
                                  field.label,
                                  number: field.valueType == 'number',
                                  lines: field.multiline ? 3 : 1,
                                ),
                              )
                              .toList(),
                        ),
                      _section(
                        'الألوان والمقاسات / Variants',
                        initiallyExpanded: _catalogType == 'clothes',
                        children: [
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'الألوان المتوفرة',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          ..._colors.asMap().entries.map((entry) {
                            final draft = entry.value;
                            final swatch = _parseHexColor(
                              draft.hex.text.trim(),
                            );
                            return Card.outlined(
                              child: Padding(
                                padding: const EdgeInsets.all(10),
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    Row(
                                      children: [
                                        Expanded(
                                          flex: 2,
                                          child: _field(
                                            draft.name,
                                            'اسم اللون',
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _field(draft.hex, 'HEX'),
                                        ),
                                        IconButton(
                                          onPressed: () => setState(() {
                                            _colors
                                                .removeAt(entry.key)
                                                .dispose();
                                            _syncVariants();
                                          }),
                                          icon: const Icon(
                                            Icons.delete_outline,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        GestureDetector(
                                          onTap: () async {
                                            final picked = await _pickColorHex(
                                              initialHex: draft.hex.text.trim(),
                                            );
                                            if (!mounted || picked == null) {
                                              return;
                                            }
                                            setState(() {
                                              draft.hex.text = picked;
                                            });
                                          },
                                          child: Container(
                                            width: 42,
                                            height: 42,
                                            decoration: BoxDecoration(
                                              color:
                                                  swatch ??
                                                  Colors.white.withValues(
                                                    alpha: 0.12,
                                                  ),
                                              shape: BoxShape.circle,
                                              border: Border.all(
                                                color: Colors.white.withValues(
                                                  alpha: 0.25,
                                                ),
                                              ),
                                            ),
                                            alignment: Alignment.center,
                                            child: swatch == null
                                                ? const Icon(
                                                    Icons.palette_outlined,
                                                    size: 18,
                                                  )
                                                : null,
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        TextButton.icon(
                                          onPressed: () async {
                                            final picked = await _pickColorHex(
                                              initialHex: draft.hex.text.trim(),
                                            );
                                            if (!mounted || picked == null) {
                                              return;
                                            }
                                            setState(() {
                                              draft.hex.text = picked;
                                            });
                                          },
                                          icon: const Icon(
                                            Icons.palette_outlined,
                                          ),
                                          label: const Text('اختيار لون'),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    ImagePickerField(
                                      title: 'صورة هذا اللون (اختيارية)',
                                      selectedFile: draft.imageFile,
                                      existingImageUrl:
                                          draft.imageUrl.text.trim().isEmpty
                                          ? null
                                          : draft.imageUrl.text.trim(),
                                      onPick: () async {
                                        final picked =
                                            await pickImageFromDevice();
                                        if (mounted && picked != null) {
                                          setState(
                                            () => draft.imageFile = picked,
                                          );
                                        }
                                      },
                                      onClear:
                                          draft.imageFile == null &&
                                              draft.imageUrl.text.trim().isEmpty
                                          ? null
                                          : () => setState(() {
                                              draft.imageFile = null;
                                              draft.imageUrl.clear();
                                            }),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  setState(() => _colors.add(_ColorDraft())),
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة لون'),
                            ),
                          ),
                          const Align(
                            alignment: Alignment.centerRight,
                            child: Text(
                              'المقاسات',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                          ),
                          ..._sizes.asMap().entries.map(
                            (entry) => Row(
                              children: [
                                Expanded(
                                  child: _field(
                                    entry.value,
                                    'المقاس (XS / S / مخصص)',
                                  ),
                                ),
                                IconButton(
                                  onPressed: () => setState(() {
                                    _sizes.removeAt(entry.key).dispose();
                                    _syncVariants();
                                  }),
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () => setState(
                                () => _sizes.add(TextEditingController()),
                              ),
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة مقاس'),
                            ),
                          ),
                          FilledButton.tonal(
                            onPressed: () => setState(_syncVariants),
                            child: const Text('توليد تركيبات اللون والمقاس'),
                          ),
                          const Padding(
                            padding: EdgeInsets.only(top: 6),
                            child: Text(
                              'أدخل المخزون لكل تركيبة. تركيبة بمخزون 0 تظهر للمستخدم كغير متوفرة ولا يمكن طلبها.',
                              textAlign: TextAlign.right,
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                          const SizedBox(height: 8),
                          ..._variants.values.map(_variantEditor),
                        ],
                      ),
                      _section(
                        'المواصفات التي تظهر للمستخدم خارج المنتج',
                        children: [
                          ..._shortSpecs.asMap().entries.map(
                            (entry) => _specEditor(
                              entry.value,
                              onDelete: () => setState(
                                () => _shortSpecs.removeAt(entry.key).dispose(),
                              ),
                            ),
                          ),
                          if (_shortSpecs.length < 5)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton.icon(
                                onPressed: () => setState(
                                  () => _shortSpecs.add(
                                    _SpecDraft(showInCard: true),
                                  ),
                                ),
                                icon: const Icon(Icons.add),
                                label: const Text('إضافة مواصفة مختصرة'),
                              ),
                            ),
                        ],
                      ),
                      _section(
                        'المواصفات الكاملة',
                        children: [
                          ..._fullSpecs.asMap().entries.map(
                            (entry) => _specEditor(
                              entry.value,
                              full: true,
                              onDelete: () => setState(
                                () => _fullSpecs.removeAt(entry.key).dispose(),
                              ),
                            ),
                          ),
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton.icon(
                              onPressed: () =>
                                  setState(() => _fullSpecs.add(_SpecDraft())),
                              icon: const Icon(Icons.add),
                              label: const Text('إضافة مواصفة كاملة'),
                            ),
                          ),
                        ],
                      ),
                      if (widget.supportsPharmacyWorkflow)
                        _section(
                          'إعدادات الصيدلية',
                          children: [
                            SwitchListTile(
                              title: const Text('يتطلب وصفة'),
                              value: requiresPrescription,
                              onChanged: (v) =>
                                  setState(() => requiresPrescription = v),
                            ),
                            SwitchListTile(
                              title: const Text('يتطلب مراجعة صيدلانية'),
                              value: requiresReview,
                              onChanged: (v) =>
                                  setState(() => requiresReview = v),
                            ),
                          ],
                        ),
                      _section(
                        'معاينة شكل المنتج للمستخدم',
                        initiallyExpanded: true,
                        children: [_preview()],
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _submit,
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Text(
                            isEdit ? 'حفظ التعديلات' : 'إضافة المنتج',
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _section(
    String title, {
    bool initiallyExpanded = false,
    required List<Widget> children,
  }) => Card(
    margin: const EdgeInsets.only(bottom: 10),
    child: ExpansionTile(
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
      initiallyExpanded: initiallyExpanded,
      childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      children: [
        for (final child in children)
          Padding(padding: const EdgeInsets.only(top: 9), child: child),
      ],
    ),
  );

  Widget _field(
    TextEditingController controller,
    String label, {
    bool number = false,
    int lines = 1,
  }) => TextField(
    controller: controller,
    maxLines: lines,
    keyboardType: number
        ? const TextInputType.numberWithOptions(decimal: true)
        : TextInputType.text,
    onChanged: (_) {
      if (mounted) setState(() {});
    },
    decoration: InputDecoration(labelText: label),
  );

  Future<String?> _pickColorHex({required String initialHex}) async {
    final controller = TextEditingController(text: initialHex);
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        final palette = <String>[
          '#000000',
          '#FFFFFF',
          '#F44336',
          '#E91E63',
          '#9C27B0',
          '#673AB7',
          '#3F51B5',
          '#2196F3',
          '#03A9F4',
          '#009688',
          '#4CAF50',
          '#CDDC39',
          '#FFEB3B',
          '#FF9800',
          '#795548',
          '#607D8B',
        ];
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              16 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'اختيار لون',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: palette
                          .map((hex) {
                            final swatch = _parseHexColor(hex) ?? Colors.grey;
                            final isSelected =
                                controller.text
                                    .trim()
                                    .replaceAll('#', '')
                                    .toUpperCase() ==
                                hex.replaceAll('#', '').toUpperCase();
                            return InkWell(
                              onTap: () {
                                setModalState(() => controller.text = hex);
                              },
                              borderRadius: BorderRadius.circular(999),
                              child: Container(
                                width: 36,
                                height: 36,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: swatch,
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).colorScheme.primary
                                        : Colors.white.withValues(alpha: 0.2),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                              ),
                            );
                          })
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: controller,
                      textAlign: TextAlign.center,
                      decoration: const InputDecoration(
                        labelText: 'HEX',
                        hintText: '#RRGGBB',
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () {
                        final value = controller.text.trim();
                        if (_parseHexColor(value) == null) return;
                        Navigator.of(
                          context,
                        ).pop(value.startsWith('#') ? value : '#$value');
                      },
                      child: const Text('اعتماد اللون'),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
    controller.dispose();
    return result;
  }

  Widget _specEditor(
    _SpecDraft draft, {
    bool full = false,
    required VoidCallback onDelete,
  }) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _field(draft.label, 'اسم المواصفة')),
              IconButton(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline),
              ),
            ],
          ),
          _field(draft.value, 'القيمة'),
          if (full)
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: draft.valueType,
                    decoration: const InputDecoration(labelText: 'نوع الخاصية'),
                    items: const ['text', 'number', 'boolean', 'select']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) => draft.valueType = value ?? 'text',
                  ),
                ),
                Expanded(
                  child: SwitchListTile(
                    title: const Text('قابلة للفلترة'),
                    value: draft.filterable,
                    onChanged: (value) =>
                        setState(() => draft.filterable = value),
                  ),
                ),
              ],
            ),
        ],
      ),
    ),
  );

  Widget _variantEditor(_VariantDraft draft) => Card.outlined(
    child: Padding(
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            draft.signature.replaceAll('|', ' • '),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          Row(
            children: [
              Expanded(child: _field(draft.stock, 'المخزون', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field(draft.sku, 'SKU')),
            ],
          ),
          Row(
            children: [
              Expanded(child: _field(draft.price, 'سعر خاص', number: true)),
              const SizedBox(width: 8),
              Expanded(child: _field(draft.discount, 'خصم خاص', number: true)),
            ],
          ),
          Row(
            children: [
              Expanded(child: _field(draft.barcode, 'Barcode')),
              const SizedBox(width: 8),
              Expanded(child: _field(draft.material, 'الخامة')),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  draft.imageFile?.name ??
                      (draft.imageUrl?.isNotEmpty == true
                          ? 'صورة محفوظة'
                          : 'لا توجد صورة'),
                ),
              ),
              TextButton.icon(
                onPressed: () async {
                  final picked = await pickImageFromDevice();
                  if (mounted && picked != null) {
                    setState(() => draft.imageFile = picked);
                  }
                },
                icon: const Icon(Icons.image_outlined),
                label: const Text('صورة variant'),
              ),
              Switch(
                value: draft.available,
                onChanged: (value) => setState(() => draft.available = value),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _preview() {
    return ProductSummaryCard(
      data: _previewData(),
      compact: false,
      maxAttributeBadges: 5,
      maxVariantBadges: 6,
      maxStatusBadges: 4,
      imageSize: 92,
    );
  }

  ProductSummaryCardData _previewData() {
    final title = nameCtrl.text.trim().isEmpty
        ? 'اسم المنتج'
        : nameCtrl.text.trim();
    final description = descCtrl.text.trim().isEmpty
        ? null
        : descCtrl.text.trim();
    final hasDiscount = discountCtrl.text.trim().isNotEmpty;
    final currentPrice = _formatPreviewPrice(
      hasDiscount ? discountCtrl.text.trim() : priceCtrl.text.trim(),
    );
    final originalPrice = hasDiscount
        ? _formatPreviewPrice(priceCtrl.text.trim())
        : null;
    final previewColors = _colors
        .asMap()
        .entries
        .where((entry) => entry.value.name.text.trim().isNotEmpty)
        .map(
          (entry) => ProductSummaryColorData(
            optionId: null,
            code: _slug(entry.value.name.text, 'color_${entry.key + 1}'),
            label: entry.value.name.text.trim(),
            hex: entry.value.hex.text.trim().isEmpty
                ? null
                : entry.value.hex.text.trim(),
            imageUrl: entry.value.imageUrl.text.trim().isEmpty
                ? null
                : entry.value.imageUrl.text.trim(),
            available: true,
            availableSizeCodes: _sizes
                .where((size) => size.text.trim().isNotEmpty)
                .map((size) => _slug(size.text, 'size_1'))
                .toList(growable: false),
          ),
        )
        .toList(growable: false);
    final previewColorCodes = previewColors
        .map((color) => color.code)
        .toList(growable: false);
    final previewSizes = _sizes
        .asMap()
        .entries
        .where((entry) => entry.value.text.trim().isNotEmpty)
        .map(
          (entry) => ProductSummarySizeData(
            optionId: null,
            code: _slug(entry.value.text, 'size_${entry.key + 1}'),
            label: entry.value.text.trim(),
            available: true,
            availableColorCodes: previewColorCodes,
          ),
        )
        .toList(growable: false);
    final galleryImages = <ProductSummaryGalleryImageData>[
      if (imageCtrl.text.trim().isNotEmpty || imageFile != null)
        ProductSummaryGalleryImageData(
          imageUrl: imageCtrl.text.trim().isNotEmpty
              ? imageCtrl.text.trim()
              : null,
          imageFile: imageFile,
          colorCode: null,
          colorLabel: null,
          colorHex: null,
          isPrimary: true,
          sortOrder: -100,
        ),
      ..._galleryFiles.asMap().entries.map(
        (entry) => ProductSummaryGalleryImageData(
          imageUrl: null,
          imageFile: entry.value,
          colorCode: null,
          colorLabel: null,
          colorHex: null,
          isPrimary: false,
          sortOrder: entry.key,
        ),
      ),
    ];
    final attributeBadges = _shortSpecs
        .where((spec) => spec.isValid)
        .take(5)
        .map(
          (spec) => ProductSummaryBadgeData(
            text: '${spec.label.text.trim()}: ${spec.value.text.trim()}',
            kind: ProductSummaryBadgeKind.attribute,
          ),
        )
        .toList(growable: false);
    final variantBadges = <ProductSummaryBadgeData>[
      ..._colors
          .where((item) => item.name.text.trim().isNotEmpty)
          .take(3)
          .map(
            (item) => ProductSummaryBadgeData(
              text: 'اللون: ${item.name.text.trim()}',
              kind: ProductSummaryBadgeKind.variant,
            ),
          ),
      ..._sizes
          .where((item) => item.text.trim().isNotEmpty)
          .take(4)
          .map(
            (item) => ProductSummaryBadgeData(
              text: 'المقاس: ${item.text.trim()}',
              kind: ProductSummaryBadgeKind.variant,
            ),
          ),
    ];
    final statusBadges = <ProductSummaryBadgeData>[
      if (requiresPrescription)
        const ProductSummaryBadgeData(
          text: 'يتطلب وصفة',
          kind: ProductSummaryBadgeKind.status,
        ),
      if (requiresReview)
        const ProductSummaryBadgeData(
          text: 'يتطلب مراجعة صيدلانية',
          kind: ProductSummaryBadgeKind.status,
        ),
      if (_variants.isNotEmpty)
        ProductSummaryBadgeData(
          text: '${_variants.length} تركيبة',
          kind: ProductSummaryBadgeKind.status,
        ),
      if (_variants.isEmpty && stockCtrl.text.trim().isNotEmpty)
        ProductSummaryBadgeData(
          text: 'المخزون: ${stockCtrl.text.trim()}',
          kind: ProductSummaryBadgeKind.status,
        ),
    ];

    return ProductSummaryCardData(
      title: title,
      categoryLabel: _category == null ? null : _categoryLabel(_category!),
      description: description,
      imageUrl: imageFile == null && imageCtrl.text.trim().isNotEmpty
          ? imageCtrl.text.trim()
          : null,
      imageFile: imageFile,
      priceText: currentPrice.isEmpty ? 'السعر' : currentPrice,
      originalPriceText: originalPrice,
      discountBadge: hasDiscount
          ? const ProductSummaryBadgeData(
              text: 'بعد الخصم',
              kind: ProductSummaryBadgeKind.discount,
            )
          : null,
      availabilityBadge: ProductSummaryBadgeData(
        text: !isAvailable
            ? 'غير متاح'
            : (_previewInStock ? 'متاح للبيع' : 'نفد المخزون'),
        kind: isAvailable && _previewInStock
            ? ProductSummaryBadgeKind.success
            : ProductSummaryBadgeKind.danger,
      ),
      attributeBadges: attributeBadges,
      variantBadges: variantBadges,
      statusBadges: statusBadges,
      colors: previewColors,
      sizes: previewSizes,
      galleryImages: galleryImages,
      selectedColorCode: previewColors.isNotEmpty
          ? previewColors.first.code
          : null,
      selectedSizeCode: previewSizes.isNotEmpty
          ? previewSizes.first.code
          : null,
    );
  }

  String _formatPreviewPrice(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return '';
    final parsed = double.tryParse(value);
    if (parsed == null) return value;
    return formatIqd(parsed);
  }

  /// حالة التوفر الفعلية كما سيراها المستخدم: مع variants يعتمد مخزون
  /// التركيبات، ومع منتج بسيط يعتمد حقل المخزون (الفارغ = غير متتبع = متاح).
  bool get _previewInStock {
    if (_variants.isNotEmpty) {
      return _variants.values.any(
        (draft) =>
            draft.available &&
            (int.tryParse(draft.stock.text.trim()) ?? 0) > 0,
      );
    }
    final stock = int.tryParse(stockCtrl.text.trim());
    return stock == null || stock > 0;
  }
}

class _SpecDraft {
  final TextEditingController label;
  final TextEditingController value;
  bool showInCard;
  String valueType;
  bool filterable;
  _SpecDraft({
    String label = '',
    String value = '',
    this.showInCard = false,
    this.valueType = 'text',
    this.filterable = false,
  }) : label = TextEditingController(text: label),
       value = TextEditingController(text: value);
  bool get isValid =>
      label.text.trim().isNotEmpty && value.text.trim().isNotEmpty;
  Map<String, dynamic> toJson(String fallback, {required bool showInCard}) => {
    'code':
        label.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_').isEmpty
        ? fallback
        : label.text.trim().toLowerCase().replaceAll(RegExp(r'\s+'), '_'),
    'labelAr': label.text.trim(),
    'labelEn': label.text.trim(),
    'valueText': value.text.trim(),
    'showInCard': showInCard,
    'showInDetails': true,
    'metadata': {'valueType': valueType, 'filterable': filterable},
  };
  void dispose() {
    label.dispose();
    value.dispose();
  }
}

class _ColorDraft {
  final TextEditingController name;
  final TextEditingController hex;
  final TextEditingController imageUrl;
  LocalImageFile? imageFile;
  _ColorDraft({String name = '', String hex = '', String imageUrl = ''})
    : name = TextEditingController(text: name),
      hex = TextEditingController(text: hex),
      imageUrl = TextEditingController(text: imageUrl);
  void dispose() {
    name.dispose();
    hex.dispose();
    imageUrl.dispose();
  }
}

class _VariantDraft {
  final String signature;
  final TextEditingController sku;
  final TextEditingController barcode;
  final TextEditingController material;
  final TextEditingController price;
  final TextEditingController discount;
  final TextEditingController stock;
  String? imageUrl;
  LocalImageFile? imageFile;
  bool available;
  _VariantDraft({
    required this.signature,
    String sku = '',
    String barcode = '',
    String material = '',
    String price = '',
    String discount = '',
    String stock = '0',
    this.imageUrl,
    this.available = true,
  }) : sku = TextEditingController(text: sku),
       barcode = TextEditingController(text: barcode),
       material = TextEditingController(text: material),
       price = TextEditingController(text: price),
       discount = TextEditingController(text: discount),
       stock = TextEditingController(text: stock);
  factory _VariantDraft.fromModel(ProductVariantModel model) => _VariantDraft(
    signature: model.signature,
    sku: model.sku ?? '',
    barcode: model.barcode ?? '',
    material: model.material ?? '',
    price: model.priceOverride?.toString() ?? '',
    discount: model.discountedPriceOverride?.toString() ?? '',
    stock: model.stockQuantity.toString(),
    imageUrl: model.imageUrl,
    available: model.isAvailable,
  );
  void dispose() {
    sku.dispose();
    barcode.dispose();
    material.dispose();
    price.dispose();
    discount.dispose();
    stock.dispose();
  }
}

class _FieldDefinition {
  final String code;
  final String label;
  final String labelEn;
  final String valueType;
  final bool showInCard;
  final bool multiline;
  const _FieldDefinition(
    this.code,
    this.label,
    this.labelEn, {
    this.valueType = 'text',
    this.showInCard = false,
    this.multiline = false,
  });
}

String _catalogTypeLabel(String type) =>
    const {
      'clothes': 'ملابس',
      'furniture': 'أثاث',
      'electronics': 'إلكترونيات',
      'restaurant': 'مطاعم',
      'grocery': 'بقالة',
      'generic': 'عام',
    }[type] ??
    'عام';

Color? _parseHexColor(String? value) {
  final raw = value?.trim();
  if (raw == null || raw.isEmpty) return null;
  final normalized = raw.replaceAll('#', '');
  final hex = normalized.length == 6 ? 'FF$normalized' : normalized;
  if (hex.length != 8) return null;
  final parsed = int.tryParse(hex, radix: 16);
  if (parsed == null) return null;
  return Color(parsed);
}

const Map<String, List<_FieldDefinition>> _categoryFields = {
  'clothes': [
    _FieldDefinition(
      'material',
      'القماش / الخامة',
      'Material',
      showInCard: true,
    ),
    _FieldDefinition('gender', 'الجنس: رجالي / نسائي / أطفال / عام', 'Gender'),
    _FieldDefinition('fit', 'القصة: Slim / Regular / Oversized', 'Fit'),
    _FieldDefinition('season', 'الموسم', 'Season'),
    _FieldDefinition(
      'wash_instructions',
      'تعليمات الغسل',
      'Wash instructions',
      multiline: true,
    ),
    _FieldDefinition('origin', 'بلد المنشأ', 'Country of origin'),
    _FieldDefinition('brand', 'الماركة', 'Brand', showInCard: true),
  ],
  'furniture': [
    _FieldDefinition('color', 'اللون', 'Color'),
    _FieldDefinition('material', 'الخامة', 'Material', showInCard: true),
    _FieldDefinition('length', 'الطول', 'Length', valueType: 'number'),
    _FieldDefinition('width', 'العرض', 'Width', valueType: 'number'),
    _FieldDefinition('height', 'الارتفاع', 'Height', valueType: 'number'),
    _FieldDefinition('weight', 'الوزن', 'Weight', valueType: 'number'),
    _FieldDefinition(
      'assembly_required',
      'يحتاج تركيب: نعم/لا',
      'Assembly required',
    ),
    _FieldDefinition('room_type', 'نوع الغرفة', 'Room type'),
    _FieldDefinition('warranty', 'الضمان', 'Warranty', showInCard: true),
    _FieldDefinition('origin', 'بلد المنشأ', 'Country of origin'),
  ],
  'electronics': [
    _FieldDefinition('brand', 'الماركة', 'Brand', showInCard: true),
    _FieldDefinition('model', 'الموديل', 'Model'),
    _FieldDefinition('model_number', 'رقم الموديل', 'Model number'),
    _FieldDefinition('color', 'اللون', 'Color'),
    _FieldDefinition('wattage', 'القدرة الكهربائية', 'Wattage'),
    _FieldDefinition('voltage', 'الفولتية', 'Voltage', showInCard: true),
    _FieldDefinition('capacity', 'السعة', 'Capacity'),
    _FieldDefinition('dimensions', 'الأبعاد', 'Dimensions'),
    _FieldDefinition('warranty', 'الضمان', 'Warranty', showInCard: true),
    _FieldDefinition(
      'included_accessories',
      'الملحقات داخل العلبة',
      'Included accessories',
      multiline: true,
    ),
    _FieldDefinition('origin', 'بلد المنشأ', 'Country of origin'),
    _FieldDefinition(
      'compatibility',
      'التوافق',
      'Compatibility',
      multiline: true,
    ),
  ],
  'restaurant': [
    _FieldDefinition('meal_size', 'الحجم', 'Size'),
    _FieldDefinition('ingredients', 'المكونات', 'Ingredients', multiline: true),
    _FieldDefinition('additions', 'الإضافات', 'Additions', multiline: true),
    _FieldDefinition(
      'paid_additions',
      'الإضافات المدفوعة وأسعارها',
      'Paid additions',
      multiline: true,
    ),
    _FieldDefinition('spice_level', 'حار / عادي', 'Spice level'),
    _FieldDefinition(
      'calories',
      'السعرات إن وجدت',
      'Calories',
      valueType: 'number',
    ),
    _FieldDefinition(
      'special_notes',
      'ملاحظات خاصة',
      'Special notes',
      multiline: true,
    ),
  ],
  'grocery': [
    _FieldDefinition(
      'pack_size',
      'الوزن / الحجم',
      'Weight / volume',
      showInCard: true,
    ),
    _FieldDefinition('ingredients', 'المكونات', 'Ingredients', multiline: true),
    _FieldDefinition('origin', 'بلد المنشأ', 'Country of origin'),
    _FieldDefinition('storage', 'طريقة التخزين', 'Storage method'),
    _FieldDefinition('expiry', 'تاريخ الانتهاء', 'Expiry date'),
    _FieldDefinition(
      'pack_count',
      'عدد القطع داخل العبوة',
      'Pack count',
      valueType: 'number',
    ),
  ],
};
