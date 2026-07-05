import '../../../core/utils/parsers.dart';

class ProductCategoryModel {
  final int id;
  final int merchantId;
  final String name;
  final String catalogType;
  final int sortOrder;
  final int availableProductsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductCategoryModel({
    required this.id,
    required this.merchantId,
    required this.name,
    this.catalogType = 'generic',
    required this.sortOrder,
    required this.availableProductsCount,
    required this.createdAt,
    required this.updatedAt,
  });

  factory ProductCategoryModel.fromJson(Map<String, dynamic> j) {
    return ProductCategoryModel(
      id: parseInt(j['id']),
      merchantId: parseInt(j['merchant_id'] ?? j['merchantId']),
      name: parseString(j['name']),
      catalogType: _catalogType(
        j['catalog_type'] ?? j['catalogType'],
        j['name'],
      ),
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder']),
      availableProductsCount: parseInt(
        j['available_products_count'] ?? j['availableProductsCount'],
      ),
      createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
      updatedAt: _parseDate(j['updated_at'] ?? j['updatedAt']),
    );
  }

  String get displayName =>
      catalogType == 'clothes' &&
          const {'cloths', 'clothes'}.contains(name.trim().toLowerCase())
      ? 'Clothes / ملابس'
      : name;
}

String _catalogType(dynamic raw, dynamic name) {
  final explicit = '${raw ?? ''}'.trim().toLowerCase();
  const allowed = {
    'generic',
    'clothes',
    'furniture',
    'electronics',
    'restaurant',
    'grocery',
  };
  if (allowed.contains(explicit) && explicit != 'generic') return explicit;
  final value = '${name ?? ''}'.trim().toLowerCase();
  if (const {
    'cloths',
    'clothes',
    'clothing',
    'fashion',
    'ملابس',
    'الملابس',
  }.contains(value)) {
    return 'clothes';
  }
  if (const {'furniture', 'اثاث', 'أثاث', 'الاثاث', 'الأثاث'}.contains(value)) {
    return 'furniture';
  }
  if (const {
    'electronics',
    'electrical',
    'الكترونيات',
    'إلكترونيات',
    'كهربائيات',
  }.contains(value)) {
    return 'electronics';
  }
  if (const {
    'restaurant',
    'restaurants',
    'food',
    'مطعم',
    'مطاعم',
  }.contains(value)) {
    return 'restaurant';
  }
  if (const {
    'grocery',
    'groceries',
    'supermarket',
    'بقالة',
    'مواد غذائية',
  }.contains(value)) {
    return 'grocery';
  }
  if (allowed.contains(explicit)) return explicit;
  return 'generic';
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
