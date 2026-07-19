class ProductVariantLabelSet {
  final String colorLabelAr;
  final String colorLabelEn;
  final String sizeLabelAr;
  final String sizeLabelEn;
  final String selectionPromptAr;
  final String selectionPromptEn;
  final String unavailablePromptAr;
  final String unavailablePromptEn;

  const ProductVariantLabelSet({
    required this.colorLabelAr,
    required this.colorLabelEn,
    required this.sizeLabelAr,
    required this.sizeLabelEn,
    required this.selectionPromptAr,
    required this.selectionPromptEn,
    required this.unavailablePromptAr,
    required this.unavailablePromptEn,
  });
}

const ProductVariantLabelSet productVariantDefaultLabels = ProductVariantLabelSet(
  colorLabelAr: 'اللون',
  colorLabelEn: 'Color',
  sizeLabelAr: 'المقاس',
  sizeLabelEn: 'Size',
  selectionPromptAr: 'اختر اللون والمقاس أولاً',
  selectionPromptEn: 'Choose color and size first',
  unavailablePromptAr: 'هذا اللون/المقاس غير متوفر حالياً',
  unavailablePromptEn: 'This color/size is currently unavailable',
);

const ProductVariantLabelSet productVariantRestaurantLabels =
    ProductVariantLabelSet(
  colorLabelAr: 'درجة التتبيل',
  colorLabelEn: 'Seasoning level',
  sizeLabelAr: 'الحجم',
  sizeLabelEn: 'Size',
  selectionPromptAr: 'اختر درجة التتبيل والحجم أولاً',
  selectionPromptEn: 'Choose seasoning level and size first',
  unavailablePromptAr: 'هذه الدرجة/الحجم غير متوفر حالياً',
  unavailablePromptEn: 'This seasoning level/size is currently unavailable',
);

ProductVariantLabelSet productVariantLabelsForCatalogType(String? catalogType) {
  final normalized = catalogType?.trim().toLowerCase();
  if (normalized == 'restaurant') return productVariantRestaurantLabels;
  return productVariantDefaultLabels;
}
