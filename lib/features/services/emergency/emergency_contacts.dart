import 'package:flutter/material.dart';

class EmergencyContact {
  const EmergencyContact({
    required this.key,
    required this.title,
    required this.subtitle,
    required this.phone,
    required this.icon,
  });

  final String key;
  final String title;
  final String subtitle;
  final String phone;
  final IconData icon;
}

const iraqEmergencyContacts = <EmergencyContact>[
  EmergencyContact(
    key: 'other',
    title: 'الطوارئ الموحدة',
    subtitle: 'أي خطر عاجل أو عند عدم معرفة الجهة',
    phone: '911',
    icon: Icons.sos_rounded,
  ),
  EmergencyContact(
    key: 'ambulance',
    title: 'الإسعاف',
    subtitle: 'إصابة، مرض مفاجئ أو حالة طبية حرجة',
    phone: '911',
    icon: Icons.emergency_rounded,
  ),
  EmergencyContact(
    key: 'police',
    title: 'الشرطة',
    subtitle: 'جريمة، اعتداء أو خطر أمني مباشر',
    phone: '104',
    icon: Icons.local_police_rounded,
  ),
  EmergencyContact(
    key: 'fire',
    title: 'الإطفاء والدفاع المدني',
    subtitle: 'حريق، احتجاز أو إنقاذ',
    phone: '911',
    icon: Icons.local_fire_department_rounded,
  ),
  EmergencyContact(
    key: 'traffic_accident',
    title: 'حادث سير',
    subtitle: 'حادث مروري مع إصابة أو خطر عاجل',
    phone: '911',
    icon: Icons.car_crash_rounded,
  ),
  EmergencyContact(
    key: 'road_hazard',
    title: 'خطر أو عائق مروري',
    subtitle: 'مشكلة طريق أو حركة مرور دون إصابات',
    phone: '455',
    icon: Icons.traffic_rounded,
  ),
  EmergencyContact(
    key: 'family_protection',
    title: 'حماية الأسرة والطفل',
    subtitle: 'عنف أسري أو طفل معرض للخطر',
    phone: '139',
    icon: Icons.family_restroom_rounded,
  ),
  EmergencyContact(
    key: 'rescue',
    title: 'إنقاذ وكوارث',
    subtitle: 'غرق، انهيار، احتجاز أو كارثة',
    phone: '911',
    icon: Icons.health_and_safety_rounded,
  ),
  EmergencyContact(
    key: 'security_threat',
    title: 'تهديد أمني خطير',
    subtitle: 'جسم مشبوه أو تهديد يعرّض الناس للخطر',
    phone: '911',
    icon: Icons.shield_rounded,
  ),
  EmergencyContact(
    key: 'community_police',
    title: 'الشرطة المجتمعية',
    subtitle: 'ابتزاز، عنف مجتمعي أو مشكلة تتطلب تدخلاً مجتمعياً',
    phone: '497',
    icon: Icons.groups_rounded,
  ),
  EmergencyContact(
    key: 'drugs',
    title: 'مكافحة المخدرات',
    subtitle: 'بلاغ عاجل متعلق بالمخدرات',
    phone: '278',
    icon: Icons.no_drinks_rounded,
  ),
  EmergencyContact(
    key: 'organized_crime',
    title: 'مكافحة الجريمة المنظمة',
    subtitle: 'بلاغ عن جريمة منظمة أو اتجار بالبشر',
    phone: '911',
    icon: Icons.policy_rounded,
  ),
  EmergencyContact(
    key: 'national_security',
    title: 'جهاز الأمن الوطني',
    subtitle: 'بلاغ أمني يتطلب تدخل جهاز الأمن الوطني',
    phone: '131',
    icon: Icons.security_rounded,
  ),
  EmergencyContact(
    key: 'intelligence',
    title: 'جهاز المخابرات',
    subtitle: 'بلاغ أمني خطير مخصص لجهاز المخابرات',
    phone: '400',
    icon: Icons.admin_panel_settings_rounded,
  ),
];

EmergencyContact? emergencyContactByKey(String? key) {
  for (final contact in iraqEmergencyContacts) {
    if (contact.key == key) return contact;
  }
  return null;
}
