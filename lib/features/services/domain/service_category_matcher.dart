import '../models/service_models.dart';

const Map<String, String> _categoryOwnerByRoot = <String, String>{
  'خدمات قانونية': 'legal',
  'خدمات طبية': 'medical',
  'تنظيف منازل': 'cleaning',
  'مكافحة حشرات': 'cleaning',
  'صيانة سيارات متنقلة': 'roadside',
  'غسيل سيارات': 'roadside',
  'خدمات الطوارئ SOS': 'sos',
  'حلاقة وتجميل منزلي': 'wellbeing',
  'تصوير ومناسبات': 'wellbeing',
  'صيانة تكييف وتبريد': 'home_maintenance',
  'صيانة كهرباء': 'home_maintenance',
  'صيانة سباكة': 'home_maintenance',
  'صيانة أجهزة منزلية': 'home_maintenance',
  'دهان وديكور': 'home_maintenance',
  'نجارة وأثاث': 'home_maintenance',
  'ألمنيوم وزجاج': 'home_maintenance',
  'نقل أثاث': 'home_maintenance',
  'تنسيق حدائق': 'home_maintenance',
  'كاميرات مراقبة': 'home_maintenance',
};

bool offeringBelongsToCategory(
  CentralServiceCatalogItem category,
  ServiceOfferingModel offering,
) {
  final mainCategoryName = offering.mainCategoryName?.trim();
  final knownOwner = mainCategoryName == null
      ? null
      : _categoryOwnerByRoot[mainCategoryName];
  if (knownOwner != null) return knownOwner == category.key;

  final haystack =
      '${offering.mainCategoryName ?? ''} '
              '${offering.subcategoryName ?? ''} ${offering.name}'
          .toLowerCase();
  final keywords = switch (category.key) {
    'legal' => const ['قانون', 'محام', 'عقد'],
    'medical' => const ['طب', 'صحي', 'تمريض', 'ممرض', 'إبر', 'ابر'],
    'home_maintenance' => const [
      'صيانة منزل',
      'كهرب',
      'سباك',
      'تكييف',
      'تبريد',
      'نجار',
      'دهان',
      'طلاء',
      'صبغ',
      'ديكور',
    ],
    'roadside' => const ['سيار', 'ميكانيك', 'إطار', 'اطار', 'بطارية'],
    'cleaning' => const ['تنظيف', 'مكافحة حشرات', 'تعقيم'],
    'wellbeing' => const ['رفاه', 'عناية', 'تجميل', 'مناسبات', 'ضيافة'],
    'sos' => const ['طوارئ', 'sos', 'إسعاف', 'اسعاف', 'إطفاء', 'اطفاء'],
    _ => const <String>[],
  };
  if (keywords.any(haystack.contains)) return true;

  final normalizedTitle = category.title
      .replaceAll('خدمات', '')
      .replaceAll('خدمة', '')
      .trim()
      .toLowerCase();
  return normalizedTitle.length >= 3 && haystack.contains(normalizedTitle);
}
