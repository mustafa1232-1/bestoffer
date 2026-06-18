import 'creator_models.dart';

List<double> _matrix({
  double red = 1,
  double green = 1,
  double blue = 1,
  double brightness = 0,
}) {
  final shift = brightness * 255;
  return <double>[
    red,
    0,
    0,
    0,
    shift,
    0,
    green,
    0,
    0,
    shift,
    0,
    0,
    blue,
    0,
    shift,
    0,
    0,
    0,
    1,
    0,
  ];
}

const CreatorFilterPreset creatorNoFilter = CreatorFilterPreset(
  id: 'none',
  arabicName: 'بدون فلتر',
  englishName: 'Original',
  previewMatrix: <double>[
    1, 0, 0, 0, 0,
    0, 1, 0, 0, 0,
    0, 0, 1, 0, 0,
    0, 0, 0, 1, 0,
  ],
  ffmpegFilterGraph: 'null',
);

final List<CreatorFilterPreset> creatorFilterPresets = <CreatorFilterPreset>[
  creatorNoFilter,
  CreatorFilterPreset(
    id: 'basmaya_glow',
    arabicName: 'بسمّاية جلو',
    englishName: 'Basmaya Glow',
    previewMatrix: _matrix(red: 1.06, green: 1.01, blue: 0.95, brightness: 0.03),
    ffmpegFilterGraph:
        'eq=brightness=0.03:saturation=1.10:contrast=1.05,colorchannelmixer=rr=1.04:gg=1.00:bb=0.94',
  ),
  CreatorFilterPreset(
    id: 'desert_honey',
    arabicName: 'عسل الصحراء',
    englishName: 'Desert Honey',
    previewMatrix: _matrix(red: 1.09, green: 1.02, blue: 0.90, brightness: 0.02),
    ffmpegFilterGraph:
        'eq=brightness=0.02:saturation=1.12:contrast=1.04,colorchannelmixer=rr=1.08:gg=1.00:bb=0.90',
  ),
  CreatorFilterPreset(
    id: 'indigo_night',
    arabicName: 'ليلة نيليّة',
    englishName: 'Indigo Night',
    previewMatrix: _matrix(red: 0.94, green: 0.98, blue: 1.08, brightness: -0.01),
    ffmpegFilterGraph:
        'eq=brightness=-0.01:saturation=1.06:contrast=1.08,colorchannelmixer=rr=0.94:gg=0.98:bb=1.08',
  ),
  CreatorFilterPreset(
    id: 'soft_sand',
    arabicName: 'رمل ناعم',
    englishName: 'Soft Sand',
    previewMatrix: _matrix(red: 1.04, green: 1.02, blue: 0.97, brightness: 0.01),
    ffmpegFilterGraph:
        'eq=brightness=0.01:saturation=0.96:contrast=1.01,colorchannelmixer=rr=1.03:gg=1.01:bb=0.97',
  ),
  CreatorFilterPreset(
    id: 'date_palm',
    arabicName: 'نخلة تمر',
    englishName: 'Date Palm',
    previewMatrix: _matrix(red: 1.00, green: 1.06, blue: 0.96, brightness: 0.00),
    ffmpegFilterGraph:
        'eq=brightness=0.00:saturation=1.05:contrast=1.02,colorchannelmixer=rr=0.99:gg=1.06:bb=0.96',
  ),
  CreatorFilterPreset(
    id: 'neon_souq',
    arabicName: 'سوق نيون',
    englishName: 'Neon Souq',
    previewMatrix: _matrix(red: 1.03, green: 0.97, blue: 1.10, brightness: 0.01),
    ffmpegFilterGraph:
        'eq=brightness=0.01:saturation=1.18:contrast=1.08,colorchannelmixer=rr=1.02:gg=0.96:bb=1.10',
  ),
  CreatorFilterPreset(
    id: 'morning_dust',
    arabicName: 'غبار الصباح',
    englishName: 'Morning Dust',
    previewMatrix: _matrix(red: 1.02, green: 1.01, blue: 0.94, brightness: 0.04),
    ffmpegFilterGraph:
        'eq=brightness=0.04:saturation=0.92:contrast=0.98,colorchannelmixer=rr=1.01:gg=1.00:bb=0.94',
  ),
  CreatorFilterPreset(
    id: 'pearl_skin',
    arabicName: 'بشرة لؤلؤية',
    englishName: 'Pearl Skin',
    previewMatrix: _matrix(red: 1.05, green: 1.03, blue: 1.01, brightness: 0.05),
    ffmpegFilterGraph:
        'eq=brightness=0.05:saturation=0.98:contrast=1.01,colorchannelmixer=rr=1.04:gg=1.02:bb=1.00',
  ),
  CreatorFilterPreset(
    id: 'warm_street',
    arabicName: 'شارع دافئ',
    englishName: 'Warm Street',
    previewMatrix: _matrix(red: 1.08, green: 1.00, blue: 0.93, brightness: 0.02),
    ffmpegFilterGraph:
        'eq=brightness=0.02:saturation=1.04:contrast=1.05,colorchannelmixer=rr=1.07:gg=1.00:bb=0.93',
  ),
  CreatorFilterPreset(
    id: 'royal_indigo',
    arabicName: 'نيلي ملكي',
    englishName: 'Royal Indigo',
    previewMatrix: _matrix(red: 0.96, green: 0.98, blue: 1.12, brightness: 0.00),
    ffmpegFilterGraph:
        'eq=brightness=0.00:saturation=1.12:contrast=1.07,colorchannelmixer=rr=0.95:gg=0.98:bb=1.12',
  ),
];

CreatorFilterPreset resolveCreatorFilterPreset(String? filterId) {
  return creatorFilterPresets.firstWhere(
    (preset) => preset.id == (filterId ?? '').trim(),
    orElse: () => creatorNoFilter,
  );
}
