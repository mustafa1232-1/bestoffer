import 'creator_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Maslaki professional color-grade engine.
//
// Each filter is defined by real grading parameters (temperature, tint,
// saturation, contrast, brightness). Those parameters are compiled into:
//   1. a 4x5 ColorFilter matrix for true live preview in the camera, and
//   2. a matching FFmpeg graph (eq + colorchannelmixer) applied on export,
// so what the user previews is what gets published — no fake "preview-only"
// filters. The math below is standard color science (luminance-preserving
// saturation, midpoint contrast, white-balance channel scaling).
// ─────────────────────────────────────────────────────────────────────────────

typedef _M = List<List<double>>;

_M _identity() => <List<double>>[
      <double>[1, 0, 0, 0, 0],
      <double>[0, 1, 0, 0, 0],
      <double>[0, 0, 1, 0, 0],
      <double>[0, 0, 0, 1, 0],
      <double>[0, 0, 0, 0, 1],
    ];

_M _mul(_M a, _M b) {
  final out = List<List<double>>.generate(5, (_) => List<double>.filled(5, 0));
  for (var i = 0; i < 5; i++) {
    for (var j = 0; j < 5; j++) {
      var sum = 0.0;
      for (var k = 0; k < 5; k++) {
        sum += a[i][k] * b[k][j];
      }
      out[i][j] = sum;
    }
  }
  return out;
}

/// Luminance-preserving saturation (Rec.709 weights).
_M _saturation(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final ir = (1 - s) * lr, ig = (1 - s) * lg, ib = (1 - s) * lb;
  return <List<double>>[
    <double>[ir + s, ig, ib, 0, 0],
    <double>[ir, ig + s, ib, 0, 0],
    <double>[ir, ig, ib + s, 0, 0],
    <double>[0, 0, 0, 1, 0],
    <double>[0, 0, 0, 0, 1],
  ];
}

/// Contrast around the 0.5 midpoint.
_M _contrast(double c) {
  final t = 0.5 * (1 - c);
  return <List<double>>[
    <double>[c, 0, 0, 0, t],
    <double>[0, c, 0, 0, t],
    <double>[0, 0, c, 0, t],
    <double>[0, 0, 0, 1, 0],
    <double>[0, 0, 0, 0, 1],
  ];
}

_M _channels(double r, double g, double b) => <List<double>>[
      <double>[r, 0, 0, 0, 0],
      <double>[0, g, 0, 0, 0],
      <double>[0, 0, b, 0, 0],
      <double>[0, 0, 0, 1, 0],
      <double>[0, 0, 0, 0, 1],
    ];

/// Additive brightness in normalized space.
_M _brightnessM(double v) => <List<double>>[
      <double>[1, 0, 0, 0, v],
      <double>[0, 1, 0, 0, v],
      <double>[0, 0, 1, 0, v],
      <double>[0, 0, 0, 1, 0],
      <double>[0, 0, 0, 0, 1],
    ];

/// White balance: temp>0 warms (R up, B down); tint>0 adds magenta.
_M _whiteBalance(double temp, double tint) => _channels(
      1 + 0.18 * temp + 0.08 * tint,
      1 + 0.04 * temp - 0.07 * tint,
      1 - 0.16 * temp + 0.08 * tint,
    );

double _rr(double temp, double tint) => 1 + 0.18 * temp + 0.08 * tint;
double _gg(double temp, double tint) => 1 + 0.04 * temp - 0.07 * tint;
double _bb(double temp, double tint) => 1 - 0.16 * temp + 0.08 * tint;

List<double> _gradeMatrix({
  required double temp,
  required double tint,
  required double sat,
  required double contrast,
  required double brightness,
}) {
  var m = _identity();
  m = _mul(_saturation(sat), m);
  m = _mul(_contrast(contrast), m);
  m = _mul(_whiteBalance(temp, tint), m);
  m = _mul(_brightnessM(brightness), m);
  final out = <double>[];
  for (var i = 0; i < 4; i++) {
    out
      ..add(m[i][0])
      ..add(m[i][1])
      ..add(m[i][2])
      ..add(m[i][3])
      ..add(m[i][4] * 255); // offset column is 0..255 for ColorFilter.matrix
  }
  return out;
}

String _gradeFfmpeg({
  required double temp,
  required double tint,
  required double sat,
  required double contrast,
  required double brightness,
}) {
  final eq = 'eq=contrast=${contrast.toStringAsFixed(3)}'
      ':brightness=${brightness.toStringAsFixed(3)}'
      ':saturation=${sat.toStringAsFixed(3)}';
  final mix = 'colorchannelmixer=rr=${_rr(temp, tint).toStringAsFixed(3)}'
      ':gg=${_gg(temp, tint).toStringAsFixed(3)}'
      ':bb=${_bb(temp, tint).toStringAsFixed(3)}';
  return '$eq,$mix';
}

CreatorFilterPreset _grade(
  String id,
  String ar,
  String en, {
  double temp = 0,
  double tint = 0,
  double sat = 1,
  double contrast = 1,
  double brightness = 0,
  CreatorFilterCategory category = CreatorFilterCategory.color,
}) {
  return CreatorFilterPreset(
    id: id,
    arabicName: ar,
    englishName: en,
    category: category,
    previewMatrix: _gradeMatrix(
      temp: temp,
      tint: tint,
      sat: sat,
      contrast: contrast,
      brightness: brightness,
    ),
    ffmpegFilterGraph: _gradeFfmpeg(
      temp: temp,
      tint: tint,
      sat: sat,
      contrast: contrast,
      brightness: brightness,
    ),
  );
}

const CreatorFilterPreset creatorNoFilter = CreatorFilterPreset(
  id: 'none',
  arabicName: 'بدون فلتر',
  englishName: 'Original',
  previewMatrix: <double>[
    1, 0, 0, 0, 0, //
    0, 1, 0, 0, 0, //
    0, 0, 1, 0, 0, //
    0, 0, 0, 1, 0, //
  ],
  ffmpegFilterGraph: 'null',
);

/// 30 professional color grades + 10 portrait-tuned (beauty) tone grades.
/// All are `supported: true` — they render live AND on export.
final List<CreatorFilterPreset> creatorFilterPresets = <CreatorFilterPreset>[
  creatorNoFilter,
  // ── 30 color grades ──────────────────────────────────────────────────────
  _grade('basmaya_glow', 'وهج بسماية', 'Basmaya Glow',
      temp: 0.50, sat: 1.10, contrast: 1.05, brightness: 0.04),
  _grade('indigo_night', 'ليل نيلي', 'Indigo Night',
      temp: -0.60, sat: 1.05, contrast: 1.12, brightness: -0.04),
  _grade('desert_honey', 'عسل الصحراء', 'Desert Honey',
      temp: 0.70, sat: 1.15, contrast: 1.04, brightness: 0.03),
  _grade('soft_sand', 'رمل ناعم', 'Soft Sand',
      temp: 0.30, sat: 0.92, contrast: 0.98, brightness: 0.04),
  _grade('gate_sunset', 'غروب البوابة', 'Gate Sunset',
      temp: 0.85, tint: 0.10, sat: 1.20, contrast: 1.06),
  _grade('souq_light', 'ضوء السوق', 'Souq Light',
      temp: 0.20, sat: 1.25, contrast: 1.08),
  _grade('palm_warmth', 'دفء النخيل', 'Palm Warmth',
      temp: 0.40, tint: -0.15, sat: 1.10, brightness: 0.02),
  _grade('sapphire_shade', 'ظل الياقوت', 'Sapphire Shade',
      temp: -0.70, sat: 1.08, contrast: 1.10),
  _grade('morning_dust', 'غبار الصباح', 'Morning Dust',
      temp: 0.25, sat: 0.85, contrast: 0.95, brightness: 0.05),
  _grade('pearl_skin', 'بشرة اللؤلؤ', 'Pearl Skin',
      temp: 0.15, sat: 1.00, contrast: 1.00, brightness: 0.06),
  _grade('royal_indigo', 'نيلي ملكي', 'Royal Indigo',
      temp: -0.50, tint: 0.05, sat: 1.15, contrast: 1.10),
  _grade('golden_noon', 'ذهب الظهيرة', 'Golden Noon',
      temp: 0.55, sat: 1.10, contrast: 1.04, brightness: 0.05),
  _grade('quiet_street', 'شارع هادئ', 'Quiet Street',
      temp: -0.10, sat: 0.80, contrast: 1.02),
  _grade('warm_window', 'نافذة دافئة', 'Warm Window',
      temp: 0.45, sat: 1.05, brightness: 0.03),
  _grade('coffee_tone', 'نغمة القهوة', 'Coffee Tone',
      temp: 0.60, tint: 0.08, sat: 0.90, contrast: 1.05),
  _grade('moon_walk', 'مشوار القمر', 'Moon Walk',
      temp: -0.55, sat: 0.95, contrast: 1.08, brightness: -0.03),
  _grade('blue_breeze', 'نسمة زرقاء', 'Blue Breeze',
      temp: -0.35, sat: 1.05, brightness: 0.03),
  _grade('date_glow', 'وهج التمر', 'Date Glow',
      temp: 0.65, sat: 1.12, contrast: 1.05),
  _grade('urban_soft', 'حضري ناعم', 'Urban Soft',
      temp: -0.15, sat: 0.82, contrast: 1.00),
  _grade('clean_day', 'يوم صافي', 'Clean Day',
      temp: 0.05, sat: 1.08, contrast: 1.05, brightness: 0.04),
  _grade('velvet_shadow', 'ظل مخملي', 'Velvet Shadow',
      temp: -0.10, sat: 1.10, contrast: 1.15, brightness: -0.05),
  _grade('amber_smile', 'ابتسامة كهرمانية', 'Amber Smile',
      temp: 0.60, sat: 1.15, brightness: 0.04),
  _grade('deep_alley', 'زقاق عميق', 'Deep Alley',
      temp: -0.20, sat: 0.90, contrast: 1.18, brightness: -0.06),
  _grade('silver_cloud', 'غيمة فضية', 'Silver Cloud',
      temp: -0.10, sat: 0.25, contrast: 1.08),
  _grade('night_market', 'سوق الليل', 'Night Market',
      temp: -0.30, sat: 1.30, contrast: 1.10),
  _grade('apricot_light', 'ضوء مشمشي', 'Apricot Light',
      temp: 0.50, sat: 1.05, brightness: 0.05),
  _grade('green_palm', 'نخلة خضراء', 'Green Palm',
      temp: 0.00, tint: -0.25, sat: 1.12, contrast: 1.04),
  _grade('cinema_basmaya', 'سينما بسماية', 'Cinema Basmaya',
      temp: 0.30, tint: -0.05, sat: 1.10, contrast: 1.14, brightness: -0.02),
  _grade('calm_beige', 'بيج هادئ', 'Calm Beige',
      temp: 0.30, sat: 0.78, contrast: 0.96, brightness: 0.05),
  _grade('neon_maslak', 'مسلك نيوني', 'Neon Maslak',
      temp: -0.10, sat: 1.40, contrast: 1.12),
  // ── 10 portrait / beauty tone grades (color-based, honest) ───────────────
  _grade('clean_skin', 'بشرة صافية', 'Clean Skin',
      temp: 0.20, sat: 0.98, contrast: 0.98, brightness: 0.05,
      category: CreatorFilterCategory.beauty),
  _grade('soft_portrait', 'بورتريه ناعم', 'Soft Portrait',
      temp: 0.25, sat: 1.00, contrast: 0.94, brightness: 0.04,
      category: CreatorFilterCategory.beauty),
  _grade('studio_light', 'إضاءة استوديو', 'Studio Light',
      temp: 0.10, sat: 1.02, contrast: 1.04, brightness: 0.07,
      category: CreatorFilterCategory.beauty),
  _grade('matte_face', 'وجه مطفي', 'Matte Face',
      temp: 0.05, sat: 0.85, contrast: 0.92, brightness: 0.03,
      category: CreatorFilterCategory.beauty),
  _grade('warm_beauty', 'جمال دافئ', 'Warm Beauty',
      temp: 0.40, sat: 1.05, contrast: 0.98, brightness: 0.04,
      category: CreatorFilterCategory.beauty),
  _grade('cool_beauty', 'جمال بارد', 'Cool Beauty',
      temp: -0.30, sat: 1.00, contrast: 1.00, brightness: 0.04,
      category: CreatorFilterCategory.beauty),
  _grade('golden_skin', 'بشرة ذهبية', 'Golden Skin',
      temp: 0.50, tint: 0.05, sat: 1.05, brightness: 0.04,
      category: CreatorFilterCategory.beauty),
  _grade('pearl_face', 'وجه لؤلؤي', 'Pearl Face',
      temp: 0.15, sat: 0.95, contrast: 1.00, brightness: 0.07,
      category: CreatorFilterCategory.beauty),
  _grade('fresh_morning', 'صباح منعش', 'Fresh Morning',
      temp: 0.10, sat: 1.08, contrast: 1.00, brightness: 0.06,
      category: CreatorFilterCategory.beauty),
  _grade('premium_portrait', 'بورتريه فاخر', 'Premium Portrait',
      temp: 0.20, sat: 1.05, contrast: 1.06, brightness: 0.03,
      category: CreatorFilterCategory.beauty),
];

/// Only filters that genuinely render (live + export) are exposed to the UI.
List<CreatorFilterPreset> get creatorSupportedFilterPresets =>
    creatorFilterPresets.where((preset) => preset.supported).toList();

List<CreatorFilterPreset> creatorFiltersByCategory(
  CreatorFilterCategory category,
) =>
    creatorFilterPresets
        .where((preset) => preset.supported && preset.category == category)
        .toList();

CreatorFilterPreset resolveCreatorFilterPreset(String? filterId) {
  return creatorFilterPresets.firstWhere(
    (preset) => preset.id == (filterId ?? '').trim(),
    orElse: () => creatorNoFilter,
  );
}
