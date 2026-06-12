import 'package:flutter/widgets.dart';

import '../../../core/i18n/locale_text.dart';
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
        '';
    final subtitle = parseNullableString(metadata['recentSubtitle']) ?? '';
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

  String resolveTitle(BuildContext context) {
    final merchantName = parseNullableString(
      metadata['merchantName'] ?? metadata['merchant_name'],
    );
    final destination = parseNullableString(
      metadata['destinationName'] ?? metadata['destination'],
    );
    final userName = parseNullableString(
      metadata['userName'] ?? metadata['username'] ?? metadata['peerName'],
    );
    final offeringName = parseNullableString(
      metadata['offeringName'] ?? metadata['serviceName'],
    );
    final merchantLabel = merchantName?.trim() ?? '';
    final destinationLabel = destination?.trim() ?? '';
    final userLabel = userName?.trim() ?? '';
    final offeringLabel = offeringName?.trim() ?? '';

    switch (type) {
      case RecentActivityType.shopping:
        if (merchantLabel.isNotEmpty) {
          return context.lt(
            ar: 'كنت تتصفح متجر: $merchantLabel',
            en: 'You were browsing: $merchantLabel',
          );
        }
        if (targetId != null) {
          return context.lt(
            ar: 'آخر متجر تصفحته رقم #$targetId',
            en: 'Last store you viewed #$targetId',
          );
        }
        return context.lt(
          ar: 'كنت تتصفح قسم التسوق',
          en: 'You were browsing shopping',
        );
      case RecentActivityType.taxi:
        if (destinationLabel.isNotEmpty) {
          return context.lt(
            ar: 'آخر رحلة إلى $destinationLabel',
            en: 'Last ride to $destinationLabel',
          );
        }
        return context.lt(
          ar: 'كنت تتابع رحلة مسلكي تكسي',
          en: 'You were following a Maslaki taxi ride',
        );
      case RecentActivityType.community:
        if (userLabel.isNotEmpty) {
          return context.lt(
            ar: 'كنت تتفاعل مع $userLabel',
            en: 'You were interacting with $userLabel',
          );
        }
        return context.lt(
          ar: 'كنت تتصفح مجتمع مسلكي',
          en: 'You were browsing the Maslaki community',
        );
      case RecentActivityType.services:
        if (offeringLabel.isNotEmpty) {
          return context.lt(
            ar: 'كنت تشاهد خدمة: $offeringLabel',
            en: 'You were viewing: $offeringLabel',
          );
        }
        return context.lt(
          ar: 'كنت تتصفح قسم الخدمات',
          en: 'You were browsing services',
        );
      case RecentActivityType.cars:
        return targetId == null
            ? context.lt(
                ar: 'كنت تتصفح سوق السيارات',
                en: 'You were browsing cars',
              )
            : context.lt(
                ar: 'آخر سيارة شاهدتها رقم #$targetId',
                en: 'Last car you viewed #$targetId',
              );
      case RecentActivityType.jobs:
        return targetId == null
            ? context.lt(ar: 'كنت تتصفح الوظائف', en: 'You were browsing jobs')
            : context.lt(
                ar: 'آخر وظيفة شاهدتها رقم #$targetId',
                en: 'Last job you viewed #$targetId',
              );
      case RecentActivityType.realEstate:
        return targetId == null
            ? context.lt(
                ar: 'كنت تتصفح العقارات',
                en: 'You were browsing real estate',
              )
            : context.lt(
                ar: 'آخر عقار شاهدته رقم #$targetId',
                en: 'Last property you viewed #$targetId',
              );
    }
  }

  String resolveSubtitle(BuildContext context) {
    switch (type) {
      case RecentActivityType.shopping:
        return context.lt(
          ar: 'اضغط للعودة إلى التسوق',
          en: 'Tap to return to shopping',
        );
      case RecentActivityType.taxi:
        return context.lt(
          ar: 'اضغط للعودة إلى خدمات التكسي',
          en: 'Tap to return to taxi',
        );
      case RecentActivityType.community:
        return context.lt(
          ar: 'اضغط للعودة إلى المجتمع',
          en: 'Tap to return to community',
        );
      case RecentActivityType.services:
        return context.lt(
          ar: 'اضغط للعودة إلى الخدمات',
          en: 'Tap to return to services',
        );
      case RecentActivityType.cars:
        return context.lt(
          ar: 'اضغط للعودة إلى السيارات',
          en: 'Tap to return to cars',
        );
      case RecentActivityType.jobs:
        return context.lt(
          ar: 'اضغط للعودة إلى الوظائف',
          en: 'Tap to return to jobs',
        );
      case RecentActivityType.realEstate:
        return context.lt(
          ar: 'اضغط للعودة إلى العقارات',
          en: 'Tap to return to real estate',
        );
    }
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
