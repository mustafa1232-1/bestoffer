class ProductReview {
  final int id;
  final int rating;
  final String? body;
  final DateTime createdAt;
  final int customerId;
  final String customerName;
  final String? customerImageUrl;

  const ProductReview({
    required this.id,
    required this.rating,
    this.body,
    required this.createdAt,
    required this.customerId,
    required this.customerName,
    this.customerImageUrl,
  });

  factory ProductReview.fromJson(Map<String, dynamic> json) => ProductReview(
    id: json['id'] as int,
    rating: json['rating'] as int,
    body: json['body'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    customerId: json['customer_id'] as int,
    customerName: json['customer_name'] as String? ?? '',
    customerImageUrl: json['customer_image_url'] as String?,
  );
}

class ProductRatingSummary {
  final double? avgRating;
  final int reviewCount;

  const ProductRatingSummary({this.avgRating, required this.reviewCount});

  factory ProductRatingSummary.fromJson(Map<String, dynamic> json) =>
      ProductRatingSummary(
        avgRating: json['avg_rating'] != null
            ? double.tryParse(json['avg_rating'].toString())
            : null,
        reviewCount: int.tryParse(json['review_count'].toString()) ?? 0,
      );
}
