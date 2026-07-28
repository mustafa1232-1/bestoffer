import '../../products/models/product_category_model.dart';

const Map<String, List<String>> _allowedCatalogTypesByActivity = {
  'restaurant': ['restaurant'],
  'sweets_bakery': ['restaurant'],
  'coffee_drinks': ['restaurant'],
  'pharmacy': ['generic'],
  'fashion_clothing': ['clothes'],
  'electronics_mobile': ['electronics'],
  'phone_maintenance': ['electronics'],
  'phones_technology': ['electronics'],
  'electrical_lighting': ['electronics'],
  'supermarket': ['grocery'],
  'fruits_vegetables': ['grocery'],
  'meat_poultry': ['grocery'],
  'seafood': ['grocery'],
  'home_kitchen': ['furniture', 'electronics'],
  'furnishings': ['furniture'],
  'home_furniture': ['furniture'],
  'kitchens_decor': ['furniture'],
  'dietary_supplements': ['generic', 'supplements'],
  'smoking_supplies': ['generic', 'smoking', 'vapes', 'hookah'],
  'nuts_snacks': ['grocery'],
  'mineral_water': ['grocery'],
  'art_studio': ['generic'],
};

const Map<String, String> _catalogTypeAliases = {
  'cloths': 'clothes',
  'clothes': 'clothes',
  'clothing': 'clothes',
  'fashion': 'clothes',
  'ملابس': 'clothes',
  'الملابس': 'clothes',
  'furniture': 'furniture',
  'اثاث': 'furniture',
  'أثاث': 'furniture',
  'الاثاث': 'furniture',
  'الأثاث': 'furniture',
  'electronics': 'electronics',
  'electrical': 'electronics',
  'الكترونيات': 'electronics',
  'إلكترونيات': 'electronics',
  'كهربائيات': 'electronics',
  'restaurant': 'restaurant',
  'restaurants': 'restaurant',
  'food': 'restaurant',
  'مطعم': 'restaurant',
  'مطاعم': 'restaurant',
  'grocery': 'grocery',
  'groceries': 'grocery',
  'supermarket': 'grocery',
  'smoking': 'smoking',
  'tobacco': 'smoking',
  'cigarettes': 'smoking',
  'cigarette': 'smoking',
  'smoking_supplies': 'smoking',
  'vape': 'vapes',
  'vapes': 'vapes',
  'e-cigarettes': 'vapes',
  'ecigarettes': 'vapes',
  'hookah': 'hookah',
  'hookahs': 'hookah',
  'shisha': 'hookah',
  'arakil': 'hookah',
  'arakeel': 'hookah',
  'supplements': 'supplements',
  'dietary_supplements': 'supplements',
  'vitamins': 'supplements',
  'protein': 'supplements',
  'بقالة': 'grocery',
  'مواد غذائية': 'grocery',
};

const Map<String, String> _catalogTypeLabels = {
  'generic': 'عام',
  'clothes': 'ملابس',
  'furniture': 'أثاث',
  'electronics': 'إلكترونيات',
  'restaurant': 'مطاعم',
  'grocery': 'بقالة',
  'smoking': 'Smoking',
  'vapes': 'Vapes',
  'hookah': 'Hookah',
  'supplements': 'Supplements',
};

String _normalize(String? value) {
  return value == null ? '' : value.trim().toLowerCase();
}

String normalizeCatalogType(String? value, {String fallback = 'generic'}) {
  final normalized = _normalize(value);
  if (normalized.isEmpty) return fallback;
  final alias = _catalogTypeAliases[normalized];
  if (alias != null) return alias;
  if (_catalogTypeLabels.containsKey(normalized)) return normalized;
  return fallback;
}

String inferCatalogTypeFromName(String? name) {
  return normalizeCatalogType(name, fallback: 'generic');
}

List<String> allowedCatalogTypesForActivity(String? activityType) {
  final normalized = _normalize(activityType);
  final allowed = <String>{};
  final extras = _allowedCatalogTypesByActivity[normalized] ?? const <String>[];
  allowed.addAll(extras);
  return allowed.toList(growable: false);
}

bool isCatalogTypeAllowedForActivity(
  String? activityType,
  String? catalogType,
) {
  final normalizedType = normalizeCatalogType(catalogType, fallback: '');
  if (normalizedType.isEmpty) return false;
  final allowed = allowedCatalogTypesForActivity(activityType);
  if (allowed.isEmpty) return normalizedType == 'generic';
  return allowed.contains(normalizedType);
}

List<ProductCategoryModel> filterCategoriesForActivity(
  Iterable<ProductCategoryModel> categories,
  String? activityType,
) {
  return categories
      .where(
        (category) =>
            isCatalogTypeAllowedForActivity(activityType, category.catalogType),
      )
      .toList(growable: false);
}

String catalogTypeLabel(String type) {
  return _catalogTypeLabels[normalizeCatalogType(type)] ?? 'عام';
}

String merchantScopeTag({
  required String merchantType,
  required String activityType,
}) {
  final typeLabel = merchantType.trim().isEmpty
      ? 'market'
      : merchantType.trim();
  final activityLabel = activityType.trim().isEmpty
      ? 'market'
      : activityType.trim();
  return '$typeLabel / $activityLabel';
}
