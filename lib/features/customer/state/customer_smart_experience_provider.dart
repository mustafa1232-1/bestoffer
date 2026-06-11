import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../behavior/data/behavior_api.dart';
import '../../taxi/data/taxi_api.dart';

final customerSmartExperienceProvider =
    FutureProvider<CustomerSmartExperienceSnapshot>((ref) async {
      final behaviorApi = ref.read(behaviorApiProvider);
      final taxiApi = ref.read(taxiApiProvider);

      Map<String, dynamic> insights = const <String, dynamic>{};
      List<Map<String, dynamic>> savedPlaces = const <Map<String, dynamic>>[];
      List<Map<String, dynamic>> rideHistory = const <Map<String, dynamic>>[];

      try {
        insights = await behaviorApi.myInsights();
      } catch (_) {
        insights = const <String, dynamic>{};
      }

      try {
        savedPlaces = await taxiApi.listSavedPlaces();
      } catch (_) {
        savedPlaces = const <Map<String, dynamic>>[];
      }

      try {
        rideHistory = await taxiApi.listMyRideHistory(period: 'all', limit: 6);
      } catch (_) {
        rideHistory = const <Map<String, dynamic>>[];
      }

      return CustomerSmartExperienceSnapshot(
        insights: insights,
        savedPlaces: savedPlaces,
        rideHistory: rideHistory,
      );
    });

class CustomerSmartExperienceSnapshot {
  final Map<String, dynamic> insights;
  final List<Map<String, dynamic>> savedPlaces;
  final List<Map<String, dynamic>> rideHistory;

  const CustomerSmartExperienceSnapshot({
    required this.insights,
    required this.savedPlaces,
    required this.rideHistory,
  });

  Map<String, dynamic> get orderProfile =>
      _readMap(insights['orderProfile']);

  Map<String, dynamic> get behaviorProfile =>
      _readMap(insights['behaviorProfile']);

  Map<String, dynamic> get favoritesSummary =>
      _readMap(behaviorProfile['favoritesSummary']);

  Map<String, dynamic> get persona => _readMap(behaviorProfile['persona']);

  Map<String, dynamic>? get homePlace => _placeByTypes(const [
    'home',
    'house',
    'منزل',
    'بيت',
  ]);

  Map<String, dynamic>? get workPlace => _placeByTypes(const [
    'work',
    'office',
    'عمل',
    'مكتب',
  ]);

  Map<String, dynamic>? get lastRide =>
      rideHistory.isEmpty ? null : rideHistory.first;

  int get ordersCount => _toInt(orderProfile['ordersCount']);

  int get favoritesCount =>
      _toInt(favoritesSummary['favoritesCount'] ?? favoritesSummary['favorites_count']);

  List<String> get likelyInterests {
    final raw = persona['likelyInterests'];
    if (raw is! List) return const <String>[];
    return raw
        .map((entry) => '$entry'.trim())
        .where((entry) => entry.isNotEmpty)
        .take(3)
        .toList(growable: false);
  }

  List<String> get campaignHints {
    final raw = persona['campaignHints'];
    if (raw is! List) return const <String>[];
    return raw
        .map((entry) => '$entry'.trim())
        .where((entry) => entry.isNotEmpty)
        .take(3)
        .toList(growable: false);
  }

  String get engagementLevel => '${persona['engagementLevel'] ?? ''}'.trim();

  String get decisionStyle => '${persona['decisionStyle'] ?? ''}'.trim();

  String get bestSectionKey {
    final interests = likelyInterests.join(' ').toLowerCase();
    final merchantTypes = _readList(orderProfile['topMerchantTypes']);
    final merchantTypeText = merchantTypes
        .map((entry) => '${entry['type'] ?? ''}'.toLowerCase())
        .join(' ');
    final combined = '$interests $merchantTypeText';
    if (combined.contains('خدمات') || combined.contains('service')) {
      return 'services';
    }
    if (combined.contains('تكسي') ||
        combined.contains('ride') ||
        combined.contains('taxi')) {
      return 'taxi';
    }
    return 'shopping';
  }

  String get bestForYouTitle {
    switch (bestSectionKey) {
      case 'services':
        return 'الأفضل لك الآن في الخدمات';
      case 'taxi':
        return 'الأفضل لك الآن في التكسي';
      default:
        return 'الأفضل لك الآن في المتاجر';
    }
  }

  String get bestForYouSubtitle {
    if (campaignHints.isNotEmpty) {
      return campaignHints.first;
    }
    if (decisionStyle.isNotEmpty) {
      return decisionStyle;
    }
    return 'نرتب اختصاراتك بحسب نشاطك الفعلي وآخر استخداماتك.';
  }

  Map<String, dynamic>? _placeByTypes(List<String> aliases) {
    final normalizedAliases = aliases.map((entry) => entry.toLowerCase()).toSet();
    for (final place in savedPlaces) {
      final type = '${place['placeType'] ?? place['type'] ?? ''}'.trim().toLowerCase();
      final label = '${place['label'] ?? ''}'.trim().toLowerCase();
      if (normalizedAliases.contains(type) || normalizedAliases.contains(label)) {
        return place;
      }
    }
    return null;
  }
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map<String, dynamic>) return value;
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }
  return const <String, dynamic>{};
}

List<Map<String, dynamic>> _readList(Object? value) {
  if (value is! List) return const <Map<String, dynamic>>[];
  return value
      .whereType<Map>()
      .map((entry) => Map<String, dynamic>.from(entry))
      .toList(growable: false);
}

int _toInt(Object? value) {
  final number = int.tryParse('${value ?? ''}');
  return number ?? 0;
}
