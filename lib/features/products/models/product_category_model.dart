import '../../../core/utils/parsers.dart';

class ProductCategoryModel {
  final int id;
  final int merchantId;
  final String name;
  final int sortOrder;
  final int availableProductsCount;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductCategoryModel({
    required this.id,
    required this.merchantId,
    required this.name,
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
      sortOrder: parseInt(j['sort_order'] ?? j['sortOrder']),
      availableProductsCount: parseInt(
        j['available_products_count'] ?? j['availableProductsCount'],
      ),
      createdAt: _parseDate(j['created_at'] ?? j['createdAt']),
      updatedAt: _parseDate(j['updated_at'] ?? j['updatedAt']),
    );
  }
}

DateTime? _parseDate(dynamic value) {
  if (value == null) return null;
  final s = value.toString();
  if (s.isEmpty) return null;
  return DateTime.tryParse(s);
}
