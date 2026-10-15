import 'dart:math' as math;

import 'package:latlong2/latlong.dart';

class TaxiPlaceRecord {
  const TaxiPlaceRecord({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    required this.aliases,
    required this.tags,
    required this.priority,
  });

  final String id;
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
  final List<String> aliases;
  final List<String> tags;
  final int priority;

  LatLng get point => LatLng(latitude, longitude);
}

const List<TaxiPlaceRecord> taxiPlaceIndex = [
  TaxiPlaceRecord(
    id: 'karrada-main',
    title: 'الكرادة',
    subtitle: 'منطقة الكرادة - بغداد',
    latitude: 33.3006,
    longitude: 44.4262,
    aliases: ['كراده', 'karrada', 'karada', 'al karrada'],
    tags: ['منطقة', 'بغداد', 'مطاعم', 'كافيه', 'تسوق'],
    priority: 98,
  ),
  TaxiPlaceRecord(
    id: 'karrada-andalus',
    title: 'الكرادة - ساحة الاندلس',
    subtitle: 'ساحة الاندلس وما حولها',
    latitude: 33.3156,
    longitude: 44.4114,
    aliases: ['ساحة الاندلس', 'اندلس', 'andalus', 'andlus'],
    tags: ['كرادة', 'منطقة', 'تقاطع', 'مطاعم', 'كافيه'],
    priority: 100,
  ),
  TaxiPlaceRecord(
    id: 'karrada-kahramana',
    title: 'الكرادة - كهرمانة',
    subtitle: 'نصب كهرمانة والشارع القريب',
    latitude: 33.3037,
    longitude: 44.4282,
    aliases: ['كهرمانة', 'كهرمانه', 'kahramana', 'kahramaneh'],
    tags: ['كرادة', 'معلم', 'مطاعم', 'كافيه'],
    priority: 99,
  ),
  TaxiPlaceRecord(
    id: 'karrada-esraa-university',
    title: 'جامعة الاسراء',
    subtitle: 'الكرادة - بغداد',
    latitude: 33.2894,
    longitude: 44.4319,
    aliases: ['الاسراء', 'جامعة الاسرا', 'esraa university', 'al-esraa'],
    tags: ['كرادة', 'جامعة', 'كلية', 'دراسة'],
    priority: 97,
  ),
  TaxiPlaceRecord(
    id: 'karrada-arasat',
    title: 'الكرادة - العرصات',
    subtitle: 'شارع العرصات الهندية',
    latitude: 33.2869,
    longitude: 44.4293,
    aliases: ['العرصات', 'عرصات', 'arasat', 'arrassat', 'karrada arasat'],
    tags: ['كرادة', 'شارع', 'مطاعم', 'كافيه'],
    priority: 96,
  ),
  TaxiPlaceRecord(
    id: 'karrada-inside',
    title: 'كرادة داخل',
    subtitle: 'قلب الكرادة داخل',
    latitude: 33.3036,
    longitude: 44.4242,
    aliases: ['الكرادة داخل', 'كراده داخل', 'karrada dakhil'],
    tags: ['كرادة', 'منطقة', 'مطاعم', 'كافيه'],
    priority: 95,
  ),
  TaxiPlaceRecord(
    id: 'karrada-outside',
    title: 'كرادة خارج',
    subtitle: 'محور كرادة خارج',
    latitude: 33.2928,
    longitude: 44.4271,
    aliases: ['الكرادة خارج', 'كراده خارج', 'karrada kharij'],
    tags: ['كرادة', 'منطقة', 'مطاعم', 'كافيه'],
    priority: 94,
  ),
  TaxiPlaceRecord(
    id: 'karrada-cafes',
    title: 'كافيهات الكرادة',
    subtitle: 'اقتراح عام للكافيهات داخل الكرادة',
    latitude: 33.2995,
    longitude: 44.4254,
    aliases: ['كافيه الكرادة', 'كوفي كرادة', 'cafe karrada', 'coffee karrada'],
    tags: ['كرادة', 'كافيه', 'كوفي', 'مقهى'],
    priority: 93,
  ),
  TaxiPlaceRecord(
    id: 'karrada-restaurants',
    title: 'مطاعم الكرادة',
    subtitle: 'اقتراح عام للمطاعم داخل الكرادة',
    latitude: 33.3009,
    longitude: 44.4270,
    aliases: ['مطعم كرادة', 'مطاعم كراده', 'restaurant karrada'],
    tags: ['كرادة', 'مطعم', 'مطاعم', 'اكل'],
    priority: 92,
  ),
  TaxiPlaceRecord(
    id: 'abu-nuwas',
    title: 'شارع ابو نواس',
    subtitle: 'قريب من الكرادة ونهر دجلة',
    latitude: 33.3063,
    longitude: 44.4297,
    aliases: ['ابو نؤاس', 'ابو نواس', 'abu nuwas'],
    tags: ['شارع', 'كرادة', 'مطاعم', 'كورنيش'],
    priority: 88,
  ),
  TaxiPlaceRecord(
    id: 'national-theatre',
    title: 'المسرح الوطني',
    subtitle: 'الكرادة - بغداد',
    latitude: 33.3024,
    longitude: 44.4218,
    aliases: ['مسرح الوطني', 'national theatre', 'national theater'],
    tags: ['كرادة', 'معلم', 'ثقافة'],
    priority: 87,
  ),
  TaxiPlaceRecord(
    id: 'jadriya',
    title: 'الجادرية',
    subtitle: 'منطقة الجادرية - بغداد',
    latitude: 33.2747,
    longitude: 44.3885,
    aliases: ['جادرية', 'jadriya', 'jadriyah'],
    tags: ['منطقة', 'جامعة', 'مطاعم', 'كافيه'],
    priority: 84,
  ),
  TaxiPlaceRecord(
    id: 'mansour',
    title: 'المنصور',
    subtitle: 'منطقة المنصور - بغداد',
    latitude: 33.3147,
    longitude: 44.3446,
    aliases: ['mansour', 'al mansour'],
    tags: ['منطقة', 'مطاعم', 'كافيه', 'مول'],
    priority: 82,
  ),
  TaxiPlaceRecord(
    id: 'zayouna',
    title: 'زيونة',
    subtitle: 'منطقة زيونة - بغداد',
    latitude: 33.3210,
    longitude: 44.4880,
    aliases: ['زيونه', 'zayouna', 'zayoona'],
    tags: ['منطقة', 'مطاعم', 'كافيه'],
    priority: 80,
  ),
  TaxiPlaceRecord(
    id: 'palestine-street',
    title: 'شارع فلسطين',
    subtitle: 'بغداد',
    latitude: 33.3222,
    longitude: 44.4640,
    aliases: ['فلسطين', 'palestine street'],
    tags: ['شارع', 'مطاعم', 'كافيه'],
    priority: 78,
  ),
  TaxiPlaceRecord(
    id: 'baghdad-mall',
    title: 'بغداد مول',
    subtitle: 'الحارثية - بغداد',
    latitude: 33.3126,
    longitude: 44.3534,
    aliases: ['مول بغداد', 'baghdad mall'],
    tags: ['مول', 'تسوق', 'مطاعم', 'كافيه', 'الحارثية'],
    priority: 94,
  ),
  TaxiPlaceRecord(
    id: 'mansour-mall',
    title: 'مول المنصور',
    subtitle: 'المنصور - بغداد',
    latitude: 33.3209,
    longitude: 44.3369,
    aliases: ['المنصور مول', 'mansour mall'],
    tags: ['مول', 'تسوق', 'مطاعم', 'كافيه', 'المنصور'],
    priority: 91,
  ),
  TaxiPlaceRecord(
    id: 'zayoona-mall',
    title: 'زيونة مول',
    subtitle: 'زيونة - بغداد',
    latitude: 33.3244,
    longitude: 44.4943,
    aliases: ['مول زيونة', 'zayoona mall', 'zayouna mall'],
    tags: ['مول', 'تسوق', 'مطاعم', 'كافيه', 'زيونة'],
    priority: 89,
  ),
  TaxiPlaceRecord(
    id: 'mall-of-iraq',
    title: 'مول العراق',
    subtitle: 'بغداد',
    latitude: 33.2768,
    longitude: 44.3087,
    aliases: ['العراق مول', 'mall of iraq'],
    tags: ['مول', 'تسوق', 'مطاعم', 'كافيه'],
    priority: 84,
  ),
  TaxiPlaceRecord(
    id: 'harithiya',
    title: 'الحارثية',
    subtitle: 'منطقة الحارثية - بغداد',
    latitude: 33.3145,
    longitude: 44.3576,
    aliases: ['حارثية', 'harithiya', 'al harithiya'],
    tags: ['منطقة', 'بغداد', 'مول', 'مطاعم', 'كافيه'],
    priority: 82,
  ),
  TaxiPlaceRecord(
    id: 'yarmouk',
    title: 'اليرموك',
    subtitle: 'منطقة اليرموك - بغداد',
    latitude: 33.2941,
    longitude: 44.3353,
    aliases: ['يرموك', 'yarmouk', 'al yarmouk'],
    tags: ['منطقة', 'بغداد', 'مستشفى', 'مطاعم'],
    priority: 81,
  ),
  TaxiPlaceRecord(
    id: 'al-jadriya-bridge',
    title: 'جسر الجادرية',
    subtitle: 'الجادرية - بغداد',
    latitude: 33.2788,
    longitude: 44.4010,
    aliases: ['جسر جادرية', 'jadriya bridge'],
    tags: ['جسر', 'الجادرية', 'طريق', 'معلم'],
    priority: 83,
  ),
  TaxiPlaceRecord(
    id: 'university-of-baghdad',
    title: 'جامعة بغداد',
    subtitle: 'مجمع الجادرية - بغداد',
    latitude: 33.2722,
    longitude: 44.3777,
    aliases: [
      'جامعة بغداد الجادرية',
      'baghdad university',
      'university of baghdad',
    ],
    tags: ['جامعة', 'كلية', 'الجادرية', 'دراسة'],
    priority: 96,
  ),
  TaxiPlaceRecord(
    id: 'al-nahrain-university',
    title: 'جامعة النهرين',
    subtitle: 'الجادرية - بغداد',
    latitude: 33.2766,
    longitude: 44.3775,
    aliases: ['النهرين', 'nahrain university', 'al nahrain university'],
    tags: ['جامعة', 'كلية', 'الجادرية', 'دراسة'],
    priority: 92,
  ),
  TaxiPlaceRecord(
    id: 'mustansiriyah-university',
    title: 'الجامعة المستنصرية',
    subtitle: 'شارع فلسطين - بغداد',
    latitude: 33.3654,
    longitude: 44.4550,
    aliases: ['المستنصرية', 'جامعة المستنصرية', 'mustansiriyah university'],
    tags: ['جامعة', 'كلية', 'شارع فلسطين', 'دراسة'],
    priority: 91,
  ),
  TaxiPlaceRecord(
    id: 'university-of-technology',
    title: 'الجامعة التكنولوجية',
    subtitle: 'شارع الصناعة - بغداد',
    latitude: 33.3130,
    longitude: 44.4543,
    aliases: ['جامعة التكنولوجيا', 'التكنولوجية', 'university of technology'],
    tags: ['جامعة', 'كلية', 'شارع الصناعة', 'دراسة'],
    priority: 90,
  ),
  TaxiPlaceRecord(
    id: 'medical-city-baghdad',
    title: 'مدينة الطب',
    subtitle: 'باب المعظم - بغداد',
    latitude: 33.3550,
    longitude: 44.3794,
    aliases: ['مستشفى مدينة الطب', 'medical city baghdad'],
    tags: ['مستشفى', 'طوارئ', 'مركز صحي', 'باب المعظم'],
    priority: 97,
  ),
  TaxiPlaceRecord(
    id: 'al-kindi-hospital',
    title: 'مستشفى الكندي',
    subtitle: 'النهضة - بغداد',
    latitude: 33.3448,
    longitude: 44.4319,
    aliases: ['الكندي', 'al kindi hospital', 'kindi hospital'],
    tags: ['مستشفى', 'طوارئ', 'مركز صحي', 'بغداد'],
    priority: 92,
  ),
  TaxiPlaceRecord(
    id: 'yarmouk-hospital',
    title: 'مستشفى اليرموك',
    subtitle: 'اليرموك - بغداد',
    latitude: 33.2966,
    longitude: 44.3446,
    aliases: ['اليرموك التعليمي', 'yarmouk hospital'],
    tags: ['مستشفى', 'طوارئ', 'مركز صحي', 'اليرموك'],
    priority: 91,
  ),
  TaxiPlaceRecord(
    id: 'baghdad-airport',
    title: 'مطار بغداد الدولي',
    subtitle: 'مطار بغداد - بغداد',
    latitude: 33.2625,
    longitude: 44.2346,
    aliases: [
      'مطار بغداد',
      'baghdad airport',
      'baghdad international airport',
      'bgw',
    ],
    tags: ['مطار', 'سفر', 'طيران', 'بغداد'],
    priority: 100,
  ),
  TaxiPlaceRecord(
    id: 'alawi-garage',
    title: 'كراج العلاوي',
    subtitle: 'العلاوي - بغداد',
    latitude: 33.3231,
    longitude: 44.3833,
    aliases: ['علاوي كراج', 'alawi garage', 'allawi garage'],
    tags: ['كراج', 'نقل', 'سفر', 'العلاوي'],
    priority: 88,
  ),
  TaxiPlaceRecord(
    id: 'tahrir-square',
    title: 'ساحة التحرير',
    subtitle: 'الباب الشرقي - بغداد',
    latitude: 33.3199,
    longitude: 44.4216,
    aliases: ['تحرير', 'tahrir square'],
    tags: ['ساحة', 'معلم', 'الباب الشرقي', 'مركز بغداد'],
    priority: 90,
  ),
  TaxiPlaceRecord(
    id: 'firdaus-square',
    title: 'ساحة الفردوس',
    subtitle: 'السعدون - بغداد',
    latitude: 33.3152,
    longitude: 44.4327,
    aliases: ['فردوس', 'firdos square', 'firdaus square'],
    tags: ['ساحة', 'معلم', 'السعدون', 'بغداد'],
    priority: 86,
  ),
  TaxiPlaceRecord(
    id: 'sinaa-street',
    title: 'شارع الصناعة',
    subtitle: 'بغداد',
    latitude: 33.3133,
    longitude: 44.4504,
    aliases: ['الصناعة', 'sinaa street', 'industry street'],
    tags: ['شارع', 'طريق', 'جامعة', 'بغداد'],
    priority: 82,
  ),
  TaxiPlaceRecord(
    id: 'al-saadoon-street',
    title: 'شارع السعدون',
    subtitle: 'وسط بغداد',
    latitude: 33.3181,
    longitude: 44.4320,
    aliases: ['السعدون', 'saadoon street', 'al saadoun'],
    tags: ['شارع', 'طريق', 'فنادق', 'مطاعم', 'بغداد'],
    priority: 81,
  ),
  TaxiPlaceRecord(
    id: 'bab-al-sharqi',
    title: 'الباب الشرقي',
    subtitle: 'مركز بغداد',
    latitude: 33.3195,
    longitude: 44.4218,
    aliases: ['باب الشرقي', 'bab al sharqi', 'tahrir square'],
    tags: ['منطقة', 'ساحة', 'مركز'],
    priority: 78,
  ),
  TaxiPlaceRecord(
    id: 'kadhimiya',
    title: 'الكاظمية',
    subtitle: 'منطقة الكاظمية - بغداد',
    latitude: 33.3790,
    longitude: 44.3390,
    aliases: ['كاظمية', 'kadhimiya', 'kadimiya'],
    tags: ['منطقة', 'جامع', 'زيارة', 'سوق'],
    priority: 76,
  ),
  TaxiPlaceRecord(
    id: 'adhamiya',
    title: 'الاعظمية',
    subtitle: 'منطقة الاعظمية - بغداد',
    latitude: 33.3710,
    longitude: 44.3830,
    aliases: ['اعظمية', 'الاعضميه', 'adhamiya', 'adhamiyah'],
    tags: ['منطقة', 'سوق', 'مطاعم'],
    priority: 75,
  ),
  TaxiPlaceRecord(
    id: 'bismayah-main',
    title: 'بسماية',
    subtitle: 'مدينة بسماية',
    latitude: 33.1930,
    longitude: 44.6207,
    aliases: ['بسمaya', 'بسمية', 'basmaya', 'bismayah', 'bismaya'],
    tags: ['مدينة', 'منطقة', 'سكن'],
    priority: 90,
  ),
  TaxiPlaceRecord(
    id: 'bismayah-main-market',
    title: 'السوق الرئيسي بسماية',
    subtitle: 'بسماية - السوق الرئيسي',
    latitude: 33.1915,
    longitude: 44.6218,
    aliases: ['سوق بسماية', 'السوق الرئيسي', 'bismayah market'],
    tags: ['بسماية', 'سوق', 'تسوق', 'مطاعم'],
    priority: 89,
  ),
  TaxiPlaceRecord(
    id: 'bismayah-commercial-center',
    title: 'المركز التجاري في بسماية',
    subtitle: 'مدينة بسماية',
    latitude: 33.1938,
    longitude: 44.6197,
    aliases: ['تجاري بسماية', 'اسواق بسماية', 'bismayah commercial center'],
    tags: ['بسماية', 'سوق', 'تسوق', 'مطاعم', 'كافيه'],
    priority: 86,
  ),
  TaxiPlaceRecord(
    id: 'bismayah-health-center',
    title: 'المركز الصحي في بسماية',
    subtitle: 'مدينة بسماية',
    latitude: 33.1948,
    longitude: 44.6241,
    aliases: ['صحي بسماية', 'مستشفى بسماية', 'bismayah health center'],
    tags: ['بسماية', 'مستشفى', 'مركز صحي', 'عيادة'],
    priority: 85,
  ),
  TaxiPlaceRecord(
    id: 'bismayah-schools',
    title: 'مدارس بسماية',
    subtitle: 'مدينة بسماية',
    latitude: 33.1961,
    longitude: 44.6189,
    aliases: ['مدرسة بسماية', 'مدارس بسمaya', 'bismayah schools'],
    tags: ['بسماية', 'مدرسة', 'تعليم'],
    priority: 80,
  ),
  TaxiPlaceRecord(
    id: 'bismayah-gate',
    title: 'بوابة بسماية',
    subtitle: 'مدخل مدينة بسماية',
    latitude: 33.1804,
    longitude: 44.6196,
    aliases: ['بوابة بسمaya', 'مدخل بسماية', 'bismayah gate'],
    tags: ['بسماية', 'بوابة', 'مدخل'],
    priority: 88,
  ),
];

List<TaxiPlaceRecord> searchTaxiPlaceIndex(
  String rawQuery, {
  LatLng? bias,
  int limit = 16,
}) {
  final query = normalizeTaxiPlaceQuery(rawQuery);
  if (query.length < 2) return const [];
  final queryTokens = query
      .split(' ')
      .where((part) => part.isNotEmpty)
      .toList();
  final scored = <({TaxiPlaceRecord record, int score})>[];

  for (final record in taxiPlaceIndex) {
    final searchableValues = <String>[
      record.title,
      record.subtitle,
      ...record.aliases,
      ...record.tags,
    ].map(normalizeTaxiPlaceQuery).toList();

    var score = 0;
    for (final value in searchableValues) {
      if (value == query) score = math.max(score, 140);
      if (value.startsWith(query)) score = math.max(score, 115);
      if (value.contains(query)) score = math.max(score, 90);
      if (queryTokens.isNotEmpty &&
          queryTokens.every((token) => value.contains(token))) {
        score = math.max(score, 82 + queryTokens.length * 4);
      }
    }

    if (query.contains('كراد') &&
        searchableValues.any((value) => value.contains('كراد'))) {
      score = math.max(score, 86);
    }
    const categoryStems = <String>[
      'كاف',
      'مطعم',
      'جامع',
      'جامعه',
      'مستش',
      'مول',
      'سوق',
      'مدرس',
      'مطار',
      'كراج',
      'جسر',
    ];
    for (final stem in categoryStems) {
      if (query.contains(stem) &&
          searchableValues.any((value) => value.contains(stem))) {
        score = math.max(score, 78);
      }
    }

    if (score == 0) continue;
    score += record.priority;
    if (bias != null) {
      score -= (_distanceKm(bias, record.point) * 0.9).round();
    }
    scored.add((record: record, score: score));
  }

  scored.sort((a, b) {
    final scoreCompare = b.score.compareTo(a.score);
    if (scoreCompare != 0) return scoreCompare;
    return b.record.priority.compareTo(a.record.priority);
  });

  return scored.map((item) => item.record).take(limit).toList(growable: false);
}

String normalizeTaxiPlaceQuery(String value) {
  return value
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\u064B-\u065F\u0670]'), '')
      .replaceAll('ـ', '')
      .replaceAll('أ', 'ا')
      .replaceAll('إ', 'ا')
      .replaceAll('آ', 'ا')
      .replaceAll('ٱ', 'ا')
      .replaceAll('ى', 'ي')
      .replaceAll('ؤ', 'و')
      .replaceAll('ئ', 'ي')
      .replaceAll('ة', 'ه')
      .replaceAll('گ', 'ك')
      .replaceAll('ک', 'ك')
      .replaceAll(RegExp(r'[^\w\s\u0600-\u06FF]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ');
}

double _distanceKm(LatLng a, LatLng b) {
  const radiusKm = 6371.0;
  final dLat = _radians(b.latitude - a.latitude);
  final dLng = _radians(b.longitude - a.longitude);
  final lat1 = _radians(a.latitude);
  final lat2 = _radians(b.latitude);
  final h =
      math.sin(dLat / 2) * math.sin(dLat / 2) +
      math.cos(lat1) * math.cos(lat2) * math.sin(dLng / 2) * math.sin(dLng / 2);
  return radiusKm * 2 * math.atan2(math.sqrt(h), math.sqrt(1 - h));
}

double _radians(double value) => value * math.pi / 180;
