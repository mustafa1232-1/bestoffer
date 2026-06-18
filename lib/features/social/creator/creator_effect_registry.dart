import 'creator_models.dart';

final List<CreatorEffectPreset> creatorEffectPresets = <CreatorEffectPreset>[
  const CreatorEffectPreset(
    id: 'desert_gazelle',
    arabicName: 'غزالة الصحراء',
    englishName: 'Desert Gazelle',
  ),
  const CreatorEffectPreset(
    id: 'golden_palm_crown',
    arabicName: 'تاج النخلة الذهبي',
    englishName: 'Golden Palm Crown',
  ),
  const CreatorEffectPreset(
    id: 'indigo_light_mask',
    arabicName: 'قناع النيلي الضوئي',
    englishName: 'Indigo Light Mask',
  ),
  const CreatorEffectPreset(
    id: 'baghdadi_mustache',
    arabicName: 'شارب بغدادي',
    englishName: 'Baghdadi Mustache',
  ),
  const CreatorEffectPreset(
    id: 'souq_glasses',
    arabicName: 'نظارات السوق',
    englishName: 'Souq Glasses',
  ),
  const CreatorEffectPreset(
    id: 'date_stars',
    arabicName: 'نجوم التمر',
    englishName: 'Date Stars',
  ),
  const CreatorEffectPreset(
    id: 'sand_rabbit',
    arabicName: 'أرنب الرمل',
    englishName: 'Sand Rabbit',
  ),
  const CreatorEffectPreset(
    id: 'maslaki_glow',
    arabicName: 'توهج مسلكي',
    englishName: 'Maslaki Glow',
  ),
];

CreatorEffectPreset? resolveCreatorEffectPreset(String? effectId) {
  final trimmed = (effectId ?? '').trim();
  if (trimmed.isEmpty) return null;
  for (final preset in creatorEffectPresets) {
    if (preset.id == trimmed) return preset;
  }
  return null;
}
