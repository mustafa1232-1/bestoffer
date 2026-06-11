import '../../../core/utils/parsers.dart';

enum RecentActivityType {
  shopping,
  taxi,
  community,
  services,
  cars,
  jobs,
  realEstate,
}

class RecentActivityModel {
  final int id;
  final RecentActivityType type;
  final int? targetId;
  final String? targetType;
  final String title;
  final String subtitle;
  final String? imageUrl;
  final String route;
  final Map<String, dynamic> metadata;
  final DateTime? createdAt;

  const RecentActivityModel({
    required this.id,
    required this.type,
    required this.targetId,
    required this.targetType,
    required this.title,
    required this.subtitle,
    required this.imageUrl,
    required this.route,
    required this.metadata,
    required this.createdAt,
  });

  factory RecentActivityModel.fromEvent(Map<String, dynamic> event) {
    final metadata = _asMap(event['metadata']);
    final category = parseString(event['category'], fallback: '').toLowerCase();
    final eventName = parseString(
      event['eventName'] ?? event['event_name'],
      fallback: '',
    ).toLowerCase();
    final type = _inferType(category: category, eventName: eventName);

    final targetId = parseNullableInt(
      event['entityId'] ?? event['entity_id'] ?? metadata['entityId'],
    );
    final targetType = parseNullableString(
      event['entityType'] ?? event['entity_type'],
    );

    final title =
        parseNullableString(metadata['recentTitle']) ??
        parseNullableString(metadata['screenLabel']) ??
        _buildTitle(type, eventName, targetId, metadata);
    final subtitle =
        parseNullableString(metadata['recentSubtitle']) ??
        _buildSubtitle(type, category, eventName, metadata);
    final route = parseNullableString(metadata['route']) ?? _routeForType(type);

    return RecentActivityModel(
      id: parseInt(event['id']),
      type: type,
      targetId: targetId,
      targetType: targetType,
      title: title,
      subtitle: subtitle,
      imageUrl: parseNullableString(
        metadata['imageUrl'] ?? metadata['image_url'],
      ),
      route: route,
      metadata: metadata,
      createdAt: parseNullableDateTime(
        event['createdAt'] ?? event['created_at'],
      ),
    );
  }

  static RecentActivityType _inferType({
    required String category,
    required String eventName,
  }) {
    if (category.contains('taxi') || eventName.contains('taxi')) {
      return RecentActivityType.taxi;
    }
    if (category.contains('cars') || eventName.contains('cars')) {
      return RecentActivityType.cars;
    }
    if (category.contains('service') ||
        category.contains('services') ||
        eventName.contains('service')) {
      return RecentActivityType.services;
    }
    if (category.contains('jobs') || eventName.contains('jobs')) {
      return RecentActivityType.jobs;
    }
    if (category.contains('real') || eventName.contains('estate')) {
      return RecentActivityType.realEstate;
    }
    if (category.contains('social') ||
        category.contains('community') ||
        eventName.contains('social') ||
        eventName.contains('reel')) {
      return RecentActivityType.community;
    }
    return RecentActivityType.shopping;
  }

  static String _buildTitle(
    RecentActivityType type,
    String eventName,
    int? targetId,
    Map<String, dynamic> metadata,
  ) {
    switch (type) {
      case RecentActivityType.shopping:
        final merchantName = parseNullableString(
          metadata['merchantName'] ?? metadata['merchant_name'],
        );
        if ((merchantName ?? '').trim().isNotEmpty) {
          return 'كنت تتصفح متجر: ${merchantName!.trim()}';
        }
        if (targetId != null) {
          return 'آخر متجر تصفحته رقم #$targetId';
        }
        if (eventName.contains('search')) {
          return 'كنت تبحث في قسم التسوق';
        }
        return 'كنت تتصفح قسم التسوق';
      case RecentActivityType.taxi:
        final destination = parseNullableString(
          metadata['destinationName'] ?? metadata['destination'],
        );
        if ((destination ?? '').trim().isNotEmpty) {
          return 'آخر رحلة إلى ${destination!.trim()}';
        }
        return 'كنت تتابع رحلة مسلكي تكسي';
      case RecentActivityType.community:
        final userName = parseNullableString(
          metadata['userName'] ?? metadata['username'] ?? metadata['peerName'],
        );
        if ((userName ?? '').trim().isNotEmpty) {
          return 'كنت تتفاعل مع ${userName!.trim()}';
        }
        return 'كنت تتصفح مجتمع مسلكي';
      case RecentActivityType.services:
        final offeringName = parseNullableString(
          metadata['offeringName'] ?? metadata['serviceName'],
        );
        if ((offeringName ?? '').trim().isNotEmpty) {
          return 'كنت تشاهد خدمة: ${offeringName!.trim()}';
        }
        return 'كنت تتصفح قسم الخدمات';
      case RecentActivityType.cars:
        return targetId == null
            ? 'كنت تتصفح سوق السيارات'
            : 'آخر سيارة شاهدتها رقم #$targetId';
      case RecentActivityType.jobs:
        return targetId == null
            ? 'كنت تتصفح الوظائف'
            : 'آخر وظيفة شاهدتها رقم #$targetId';
      case RecentActivityType.realEstate:
        return targetId == null
            ? 'كنت تتصفح العقارات'
            : 'آخر عقار شاهدته رقم #$targetId';
    }
  }

  static String _buildSubtitle(
    RecentActivityType type,
    String category,
    String eventName,
    Map<String, dynamic> metadata,
  ) {
    final route = parseNullableString(metadata['route']);
    if ((route ?? '').trim().isNotEmpty) {
      return route!.trim();
    }

    switch (type) {
      case RecentActivityType.shopping:
        return 'اضغط للعودة إلى التسوق';
      case RecentActivityType.taxi:
        return 'اضغط للعودة إلى خدمات التكسي';
      case RecentActivityType.community:
        return 'اضغط للعودة إلى المجتمع';
      case RecentActivityType.services:
        return 'اضغط للعودة إلى الخدمات';
      case RecentActivityType.cars:
        return 'اضغط للعودة إلى السيارات';
      case RecentActivityType.jobs:
        return 'اضغط للعودة إلى الوظائف';
      case RecentActivityType.realEstate:
        return 'اضغط للعودة إلى العقارات';
    }
  }

  static String _routeForType(RecentActivityType type) {
    switch (type) {
      case RecentActivityType.shopping:
        return 'shopping';
      case RecentActivityType.taxi:
        return 'taxi';
      case RecentActivityType.community:
        return 'community';
      case RecentActivityType.services:
        return 'services';
      case RecentActivityType.cars:
        return 'cars';
      case RecentActivityType.jobs:
        return 'jobs';
      case RecentActivityType.realEstate:
        return 'real_estate';
    }
  }
}

Map<String, dynamic> _asMap(dynamic value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}
