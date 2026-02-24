import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class AppBackdrop extends StatefulWidget {
  final Widget child;
  final bool animationsEnabled;
  final bool weatherEffectsEnabled;

  const AppBackdrop({
    super.key,
    required this.child,
    this.animationsEnabled = true,
    this.weatherEffectsEnabled = true,
  });

  @override
  State<AppBackdrop> createState() => _AppBackdropState();
}

class _AppBackdropState extends State<AppBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Timer _solarTimer;
  late final Timer _weatherTimer;
  late _SolarSnapshot _solar;
  _WeatherSnapshot _weather = _WeatherSnapshot.clear();

  @override
  void initState() {
    super.initState();
    _solar = _SolarCalculator.forBasmaya(DateTime.now());
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 26),
    );
    if (widget.animationsEnabled) {
      _controller.repeat();
    } else {
      _controller.value = 0;
    }
    _solarTimer = Timer.periodic(const Duration(seconds: 45), (_) {
      if (!mounted) return;
      setState(() => _solar = _SolarCalculator.forBasmaya(DateTime.now()));
    });
    if (widget.weatherEffectsEnabled) {
      _refreshWeather();
    }
    _weatherTimer = Timer.periodic(const Duration(minutes: 15), (_) {
      if (!widget.weatherEffectsEnabled) return;
      _refreshWeather();
    });
  }

  @override
  void didUpdateWidget(covariant AppBackdrop oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.animationsEnabled != widget.animationsEnabled) {
      if (widget.animationsEnabled) {
        _controller.repeat();
      } else {
        _controller.stop(canceled: false);
        _controller.value = 0;
      }
    }
    if (oldWidget.weatherEffectsEnabled != widget.weatherEffectsEnabled) {
      if (widget.weatherEffectsEnabled) {
        _refreshWeather();
      } else {
        setState(() => _weather = _WeatherSnapshot.clear());
      }
    }
  }

  Future<void> _refreshWeather() async {
    try {
      final latest = await _BasmayaWeatherClient.fetch();
      if (!mounted || _weather == latest) return;
      setState(() => _weather = latest);
    } catch (_) {
      // Keep previous weather state on network/API failures.
    }
  }

  @override
  void dispose() {
    _solarTimer.cancel();
    _weatherTimer.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final weather = widget.weatherEffectsEnabled
        ? _weather
        : _WeatherSnapshot.clear();

    if (widget.animationsEnabled) {
      return AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return _buildScene(progress: _controller.value, weather: weather);
        },
      );
    }

    return _buildScene(progress: 0, weather: weather);
  }

  Widget _buildScene({
    required double progress,
    required _WeatherSnapshot weather,
  }) {
    final t = progress * math.pi * 2;

    return RepaintBoundary(
      child: Stack(
        fit: StackFit.expand,
        children: [
          _SkyAuraLayer(
            t: t,
            progress: progress,
            solar: _solar,
            weather: weather,
          ),
          IgnorePointer(
            child: CustomPaint(
              painter: _TwinklePainter(
                progress: progress,
                daylight: _solar.daylight,
                cloudFactor: weather.cloudFactor,
              ),
            ),
          ),
          if (widget.weatherEffectsEnabled)
            IgnorePointer(
              child: CustomPaint(
                painter: _WeatherEffectPainter(
                  progress: progress,
                  weather: weather,
                  daylight: _solar.daylight,
                ),
              ),
            ),
          IgnorePointer(
            child: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox.expand(
                child: CustomPaint(
                  painter: _BasmayaSkylinePainter(
                    progress: progress,
                    daylight: _solar.daylight,
                    weather: weather,
                  ),
                ),
              ),
            ),
          ),
          IgnorePointer(
            child: Align(
              alignment: const Alignment(0.84, -0.72),
              child: _SolarRing(progress: progress, solar: _solar),
            ),
          ),
          widget.child,
        ],
      ),
    );
  }
}

class _SkyAuraLayer extends StatelessWidget {
  final double t;
  final double progress;
  final _SolarSnapshot solar;
  final _WeatherSnapshot weather;

  const _SkyAuraLayer({
    required this.t,
    required this.progress,
    required this.solar,
    required this.weather,
  });

  @override
  Widget build(BuildContext context) {
    final palette = _SkyPalette.fromSolar(solar, weather);
    final celestialAlignment = solar.skyAlignment;
    final celestialSize = solar.isDay ? 56.0 : 42.0;

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.top, palette.mid, palette.bottom],
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _orb(
            alignment: celestialAlignment,
            size: solar.isDay ? 220 : 170,
            color: (solar.isDay ? palette.sunGlow : palette.moonGlow)
                .withValues(alpha: solar.isDay ? 0.32 : 0.24),
            blur: solar.isDay ? 52 : 42,
          ),
          IgnorePointer(
            child: Align(
              alignment: celestialAlignment,
              child: Container(
                width: celestialSize,
                height: celestialSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: solar.isDay
                        ? [
                            const Color(0xFFFFF7CF),
                            const Color(0xFFFFD577),
                            const Color(0xFFFFB25A),
                          ]
                        : [
                            const Color(0xFFF7FAFF),
                            const Color(0xFFDCE9FF),
                            const Color(0xFFB4C9E8),
                          ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      blurRadius: solar.isDay ? 28 : 18,
                      spreadRadius: solar.isDay ? 5 : 2,
                      color: (solar.isDay ? palette.sunGlow : palette.moonGlow)
                          .withValues(alpha: solar.isDay ? 0.32 : 0.22),
                    ),
                  ],
                ),
              ),
            ),
          ),
          _orb(
            alignment: Alignment(-0.92 + 0.18 * math.sin(t), -0.76),
            size: 340,
            color: palette.cyanAura.withValues(alpha: 0.30),
          ),
          _orb(
            alignment: Alignment(0.88, -0.84 + 0.22 * math.cos(t * 0.8)),
            size: 280,
            color: palette.blueAura.withValues(alpha: 0.24),
          ),
          _orb(
            alignment: Alignment(0.72 - 0.2 * math.sin(t * 0.7), 0.52),
            size: 380,
            color: palette.mintAura.withValues(alpha: 0.14),
          ),
          _orb(
            alignment: Alignment(-0.82, 0.62 - 0.2 * math.cos(t * 1.25)),
            size: 300,
            color: palette.indigoAura.withValues(alpha: 0.20),
          ),
          Align(
            alignment: Alignment(0.02 + 0.08 * math.sin(t * 0.5), -0.24),
            child: Container(
              width: 420,
              height: 420,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    palette.haze.withValues(alpha: 0.10),
                    const Color(0xFFEFF8FF).withValues(alpha: 0.0),
                  ],
                ),
              ),
            ),
          ),
          if (weather.cloudFactor > 0.1)
            Align(
              alignment: const Alignment(0, -0.48),
              child: Opacity(
                opacity: (0.09 + weather.cloudFactor * 0.28).clamp(0.0, 0.36),
                child: Container(
                  width: 510,
                  height: 210,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(140),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFFE5EFFA).withValues(alpha: 0.80),
                        const Color(0xFFE5EFFA).withValues(alpha: 0.0),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          CustomPaint(
            painter: _DistrictGridPainter(progress: progress),
            child: const SizedBox.expand(),
          ),
        ],
      ),
    );
  }

  Widget _orb({
    required Alignment alignment,
    required double size,
    required Color color,
    double blur = 62,
  }) {
    return IgnorePointer(
      child: Align(
        alignment: alignment,
        child: ImageFiltered(
          imageFilter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color),
          ),
        ),
      ),
    );
  }
}

class _SkyPalette {
  final Color top;
  final Color mid;
  final Color bottom;
  final Color sunGlow;
  final Color moonGlow;
  final Color cyanAura;
  final Color blueAura;
  final Color mintAura;
  final Color indigoAura;
  final Color haze;

  const _SkyPalette({
    required this.top,
    required this.mid,
    required this.bottom,
    required this.sunGlow,
    required this.moonGlow,
    required this.cyanAura,
    required this.blueAura,
    required this.mintAura,
    required this.indigoAura,
    required this.haze,
  });

  factory _SkyPalette.fromSolar(
    _SolarSnapshot solar,
    _WeatherSnapshot weather,
  ) {
    final d = solar.daylight;
    final g = solar.goldenHour;
    final cloud = weather.cloudFactor;
    final rain = weather.rainFactor;
    final haze = weather.hazeFactor;

    final nightTop = const Color(0xFF071229);
    final nightMid = const Color(0xFF0D2448);
    final nightBottom = const Color(0xFF0A1429);

    final dayTop = const Color(0xFF72C6FF);
    final dayMid = const Color(0xFF4C9FDB);
    final dayBottom = const Color(0xFF1A4E84);

    final sunsetTop = const Color(0xFFEF9A63);
    final sunsetMid = const Color(0xFFF0AF75);
    final sunsetBottom = const Color(0xFF284C7A);

    Color blend(Color a, Color b, double t) => Color.lerp(a, b, t)!;

    final topBase = blend(nightTop, dayTop, d);
    final midBase = blend(nightMid, dayMid, d);
    final bottomBase = blend(nightBottom, dayBottom, d);

    final weatherTop = blend(
      blend(topBase, const Color(0xFF6A7B91), cloud * 0.52),
      const Color(0xFF8A7A61),
      haze * 0.48,
    );
    final weatherMid = blend(
      blend(midBase, const Color(0xFF5D728A), cloud * 0.44),
      const Color(0xFF8A7A61),
      haze * 0.34,
    );
    final weatherBottom = blend(
      blend(bottomBase, const Color(0xFF3A4E67), rain * 0.35),
      const Color(0xFF7D6A54),
      haze * 0.25,
    );

    return _SkyPalette(
      top: blend(weatherTop, sunsetTop, g * (1 - cloud * 0.5)),
      mid: blend(weatherMid, sunsetMid, g * (1 - cloud * 0.45)),
      bottom: blend(weatherBottom, sunsetBottom, g * (0.6 - cloud * 0.15)),
      sunGlow: blend(const Color(0xFFFFC768), const Color(0xFFFF8B4A), g),
      moonGlow: const Color(0xFFBBD8FF),
      cyanAura: blend(
        blend(const Color(0xFF4ED6FF), const Color(0xFF92E7FF), d),
        const Color(0xFF96A8BD),
        cloud * 0.45,
      ),
      blueAura: blend(
        blend(const Color(0xFF7EC3FF), const Color(0xFF6AA8E4), d),
        const Color(0xFF7A8EA4),
        cloud * 0.52,
      ),
      mintAura: blend(const Color(0xFF9AFCCB), const Color(0xFF7BE8B8), d),
      indigoAura: blend(const Color(0xFF5B8DFF), const Color(0xFF6F95E8), d),
      haze: blend(
        blend(const Color(0xFFEFF8FF), const Color(0xFFDFF2FF), d),
        const Color(0xFFD9CBB8),
        haze * 0.45,
      ),
    );
  }
}

enum _WeatherKind { clear, cloudy, rain, dust, fog, storm }

class _WeatherSnapshot {
  final _WeatherKind kind;
  final double cloudCover;
  final double precipitationMm;
  final double visibilityKm;
  final double windKph;
  final double temperatureC;
  final DateTime fetchedAt;

  const _WeatherSnapshot({
    required this.kind,
    required this.cloudCover,
    required this.precipitationMm,
    required this.visibilityKm,
    required this.windKph,
    required this.temperatureC,
    required this.fetchedAt,
  });

  factory _WeatherSnapshot.clear() {
    return _WeatherSnapshot(
      kind: _WeatherKind.clear,
      cloudCover: 0,
      precipitationMm: 0,
      visibilityKm: 10,
      windKph: 0,
      temperatureC: 28,
      fetchedAt: DateTime.now(),
    );
  }

  bool get isRainy => kind == _WeatherKind.rain || kind == _WeatherKind.storm;
  bool get isDusty => kind == _WeatherKind.dust;
  bool get isFoggy => kind == _WeatherKind.fog;
  bool get isStormy => kind == _WeatherKind.storm;
  bool get hasClouds => kind == _WeatherKind.cloudy || cloudCover > 0.2;

  double get cloudFactor => cloudCover.clamp(0.0, 1.0);

  double get rainFactor {
    if (!isRainy) return 0;
    return (0.35 + (precipitationMm / 4.0)).clamp(0.35, 1.0);
  }

  double get hazeFactor {
    if (isDusty) return 0.95;
    if (isFoggy) return 0.72;
    if (visibilityKm < 5 && !isRainy) return 0.45;
    return 0;
  }

  @override
  int get hashCode {
    return Object.hash(
      kind,
      cloudCover.toStringAsFixed(2),
      precipitationMm.toStringAsFixed(2),
      visibilityKm.toStringAsFixed(1),
      windKph.toStringAsFixed(1),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is _WeatherSnapshot &&
        other.kind == kind &&
        (other.cloudCover - cloudCover).abs() < 0.02 &&
        (other.precipitationMm - precipitationMm).abs() < 0.05 &&
        (other.visibilityKm - visibilityKm).abs() < 0.3 &&
        (other.windKph - windKph).abs() < 0.4;
  }
}

class _BasmayaWeatherClient {
  static const double _lat = 33.30;
  static const double _lon = 44.65;

  static final Dio _dio = Dio(
    BaseOptions(
      baseUrl: 'https://api.open-meteo.com',
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      responseType: ResponseType.json,
    ),
  );

  static Future<_WeatherSnapshot> fetch() async {
    final response = await _dio.get<Map<String, dynamic>>(
      '/v1/forecast',
      queryParameters: const {
        'latitude': _lat,
        'longitude': _lon,
        'current':
            'temperature_2m,weather_code,cloud_cover,precipitation,visibility,wind_speed_10m',
        'timezone': 'auto',
        'forecast_days': 1,
      },
    );

    final root = response.data;
    if (root == null) throw StateError('missing weather payload');
    final current = root['current'];
    if (current is! Map) throw StateError('missing weather current block');

    final weatherCode = _asInt(current['weather_code']);
    final cloudCover = (_asDouble(current['cloud_cover']) / 100).clamp(
      0.0,
      1.0,
    );
    final precipitation = _asDouble(current['precipitation']);
    final visibilityKm = (_asDouble(current['visibility']) / 1000).clamp(
      0.0,
      20.0,
    );
    final windKph = _asDouble(current['wind_speed_10m']);
    final temperatureC = _asDouble(current['temperature_2m']);

    return _WeatherSnapshot(
      kind: _mapWeatherKind(
        code: weatherCode,
        cloudCover: cloudCover,
        precipitationMm: precipitation,
        visibilityKm: visibilityKm,
        windKph: windKph,
      ),
      cloudCover: cloudCover,
      precipitationMm: precipitation,
      visibilityKm: visibilityKm,
      windKph: windKph,
      temperatureC: temperatureC,
      fetchedAt: DateTime.now(),
    );
  }

  static _WeatherKind _mapWeatherKind({
    required int code,
    required double cloudCover,
    required double precipitationMm,
    required double visibilityKm,
    required double windKph,
  }) {
    if (code >= 95) return _WeatherKind.storm;
    final rainyCode = (code >= 51 && code <= 67) || (code >= 80 && code <= 82);
    if (rainyCode || precipitationMm >= 0.12) return _WeatherKind.rain;
    if (code == 45 || code == 48) return _WeatherKind.fog;

    // WMO code does not expose dust directly. We infer it from low visibility
    // with relatively high wind and no rain/fog.
    final likelyDust =
        visibilityKm > 0 &&
        visibilityKm <= 4.5 &&
        windKph >= 18 &&
        precipitationMm < 0.1;
    if (likelyDust) return _WeatherKind.dust;

    final cloudyCode = code == 3 || (code >= 1 && code <= 2);
    if (cloudyCode || cloudCover >= 0.5) return _WeatherKind.cloudy;
    return _WeatherKind.clear;
  }
}

class _SolarSnapshot {
  final DateTime dateTime;
  final double altitudeDeg;
  final double azimuthDeg;
  final double daylight;
  final double goldenHour;

  const _SolarSnapshot({
    required this.dateTime,
    required this.altitudeDeg,
    required this.azimuthDeg,
    required this.daylight,
    required this.goldenHour,
  });

  bool get isDay => altitudeDeg > -0.8;

  Alignment get skyAlignment {
    final az = isDay ? azimuthDeg : (azimuthDeg + 180) % 360;
    final alt = isDay
        ? altitudeDeg
        : ((-altitudeDeg * 0.45) + 8).clamp(-10.0, 65.0);

    final x = ((az - 180.0) / 115.0).clamp(-1.2, 1.2);
    final elevNorm = ((alt + 18.0) / 98.0).clamp(0.0, 1.0);
    final y = _lerpDouble(0.74, -0.82, elevNorm);
    return Alignment(x, y);
  }

  Offset get orbitOffset {
    final az = isDay ? azimuthDeg : (azimuthDeg + 180) % 360;
    final angle = _degToRad(az - 90);
    final radius = _lerpDouble(22, 37, isDay ? 1 - daylight : 0.65);
    return Offset(math.cos(angle) * radius, math.sin(angle) * radius);
  }
}

class _SolarCalculator {
  // Basmaya New City (near Baghdad).
  static const double _lat = 33.30;
  static const double _lon = 44.65;

  static _SolarSnapshot forBasmaya(DateTime localTime) {
    final utc = localTime.toUtc();
    final tzHours = localTime.timeZoneOffset.inMinutes / 60.0;

    final jd = _julianDay(utc);
    final t = (jd - 2451545.0) / 36525.0;

    final l0 = _normalizeDeg(280.46646 + t * (36000.76983 + (0.0003032 * t)));
    final m = _normalizeDeg(357.52911 + t * (35999.05029 - 0.0001537 * t));
    final e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t);

    final c =
        math.sin(_degToRad(m)) * (1.914602 - t * (0.004817 + 0.000014 * t)) +
        math.sin(_degToRad(2 * m)) * (0.019993 - 0.000101 * t) +
        math.sin(_degToRad(3 * m)) * 0.000289;

    final trueLong = l0 + c;
    final omega = 125.04 - 1934.136 * t;
    final lambda = trueLong - 0.00569 - 0.00478 * math.sin(_degToRad(omega));

    final meanObliq =
        23 +
        (26 + ((21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60)) /
            60;
    final obliqCorr = meanObliq + 0.00256 * math.cos(_degToRad(omega));

    final decl = _radToDeg(
      math.asin(math.sin(_degToRad(obliqCorr)) * math.sin(_degToRad(lambda))),
    );

    final y = math.pow(math.tan(_degToRad(obliqCorr / 2)), 2).toDouble();
    final eqTime =
        4 *
        _radToDeg(
          y * math.sin(2 * _degToRad(l0)) -
              2 * e * math.sin(_degToRad(m)) +
              4 * e * y * math.sin(_degToRad(m)) * math.cos(2 * _degToRad(l0)) -
              0.5 * y * y * math.sin(4 * _degToRad(l0)) -
              1.25 * e * e * math.sin(2 * _degToRad(m)),
        );

    final minutes =
        localTime.hour * 60 + localTime.minute + localTime.second / 60;
    final trueSolarTime = (minutes + eqTime + 4 * _lon - 60 * tzHours)
        .remainder(1440);

    final hourAngle = trueSolarTime / 4 < 0
        ? trueSolarTime / 4 + 180
        : trueSolarTime / 4 - 180;

    final haRad = _degToRad(hourAngle);
    final latRad = _degToRad(_lat);
    final decRad = _degToRad(decl);

    final cosZenith =
        math.sin(latRad) * math.sin(decRad) +
        math.cos(latRad) * math.cos(decRad) * math.cos(haRad);
    final zenithRad = math.acos(cosZenith.clamp(-1.0, 1.0));
    final altitude = 90 - _radToDeg(zenithRad);

    final azimuthRad = math.atan2(
      math.sin(haRad),
      math.cos(haRad) * math.sin(latRad) - math.tan(decRad) * math.cos(latRad),
    );
    final azimuth = (_radToDeg(azimuthRad) + 180).remainder(360);

    final daylight = _smoothStep(-6, 8, altitude);
    final golden = (1 - ((altitude - 3).abs() / 14).clamp(0.0, 1.0)) * daylight;

    return _SolarSnapshot(
      dateTime: localTime,
      altitudeDeg: altitude,
      azimuthDeg: azimuth,
      daylight: daylight,
      goldenHour: golden,
    );
  }
}

double _julianDay(DateTime utc) {
  var year = utc.year;
  var month = utc.month;
  final day =
      utc.day +
      (utc.hour +
              utc.minute / 60 +
              utc.second / 3600 +
              utc.millisecond / 3.6e6) /
          24;

  if (month <= 2) {
    year -= 1;
    month += 12;
  }

  final a = (year / 100).floor();
  final b = 2 - a + (a / 4).floor();

  return (365.25 * (year + 4716)).floor() +
      (30.6001 * (month + 1)).floor() +
      day +
      b -
      1524.5;
}

double _normalizeDeg(double value) {
  var out = value % 360;
  if (out < 0) out += 360;
  return out;
}

double _degToRad(double deg) => deg * math.pi / 180;

double _radToDeg(double rad) => rad * 180 / math.pi;

double _smoothStep(double edge0, double edge1, double x) {
  final t = ((x - edge0) / (edge1 - edge0)).clamp(0.0, 1.0);
  return t * t * (3 - 2 * t);
}

double _lerpDouble(double a, double b, double t) {
  return a + ((b - a) * t);
}

double _asDouble(dynamic value) {
  if (value is num) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0;
  return 0;
}

int _asInt(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.round();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0;
}

class _DistrictGridPainter extends CustomPainter {
  final double progress;

  const _DistrictGridPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFB7E6FF).withValues(alpha: 0.045)
      ..strokeWidth = 1.0;

    final spacing = 36.0;
    final dxShift = 8 * math.sin(progress * math.pi * 2);
    for (double x = -spacing; x < size.width + spacing; x += spacing) {
      canvas.drawLine(
        Offset(x + dxShift, 0),
        Offset(x + dxShift, size.height),
        paint,
      );
    }

    for (double y = size.height * 0.18; y < size.height * 0.86; y += spacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _DistrictGridPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}

class _TwinklePainter extends CustomPainter {
  final double progress;
  final double daylight;
  final double cloudFactor;

  const _TwinklePainter({
    required this.progress,
    required this.daylight,
    required this.cloudFactor,
  });

  static const List<Offset> _stars = [
    Offset(0.12, 0.12),
    Offset(0.21, 0.22),
    Offset(0.36, 0.11),
    Offset(0.47, 0.18),
    Offset(0.58, 0.09),
    Offset(0.72, 0.19),
    Offset(0.84, 0.13),
    Offset(0.18, 0.34),
    Offset(0.31, 0.30),
    Offset(0.53, 0.28),
    Offset(0.67, 0.33),
    Offset(0.79, 0.27),
    Offset(0.91, 0.36),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final nightFactor = ((1 - daylight) * (1 - cloudFactor * 0.74)).clamp(
      0.0,
      1.0,
    );
    if (nightFactor < 0.02) return;

    for (var i = 0; i < _stars.length; i++) {
      final s = _stars[i];
      final pulse = (math.sin(progress * math.pi * 2 * 1.3 + i) + 1) / 2;
      final radius = 0.9 + (pulse * 1.25);
      final color = Color.lerp(
        const Color(0xFFC2E8FF).withValues(alpha: 0.18 * nightFactor),
        const Color(0xFFFFFFFF).withValues(alpha: 0.75 * nightFactor),
        pulse,
      )!;

      final paint = Paint()..color = color;
      canvas.drawCircle(
        Offset(s.dx * size.width, s.dy * size.height),
        radius,
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TwinklePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.daylight != daylight ||
        oldDelegate.cloudFactor != cloudFactor;
  }
}

class _WeatherEffectPainter extends CustomPainter {
  final double progress;
  final _WeatherSnapshot weather;
  final double daylight;

  const _WeatherEffectPainter({
    required this.progress,
    required this.weather,
    required this.daylight,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (weather.cloudFactor > 0.16) {
      _paintCloudBands(canvas, size);
    }
    if (weather.isFoggy) {
      _paintFog(canvas, size);
    }
    if (weather.isDusty) {
      _paintDust(canvas, size);
    }
    if (weather.isRainy) {
      _paintRain(canvas, size);
    }
    if (weather.isStormy) {
      _paintLightning(canvas, size);
    }
  }

  void _paintCloudBands(Canvas canvas, Size size) {
    final cloudAlpha = (0.06 + weather.cloudFactor * 0.22).clamp(0.0, 0.34);
    final cloudColor = Color.lerp(
      const Color(0xFFDDE9F7),
      const Color(0xFFB8C8DD),
      (weather.cloudFactor * (0.45 + (1 - daylight) * 0.4)).clamp(0.0, 1.0),
    )!;

    final paint = Paint()..color = cloudColor.withValues(alpha: cloudAlpha);

    for (var i = 0; i < 6; i++) {
      final lane = i / 6;
      final y = size.height * (0.12 + lane * 0.11);
      final speed = 70 + i * 18;
      final offset =
          ((progress * speed) + (i * 57)).remainder(size.width + 260) - 130;

      final baseX = offset;
      final baseW = 150 + (i % 3) * 26;
      final baseH = 40 + (i % 2) * 14;
      final rect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(baseX, y),
          width: baseW.toDouble(),
          height: baseH.toDouble(),
        ),
        const Radius.circular(28),
      );
      canvas.drawRRect(rect, paint);
      canvas.drawCircle(Offset(baseX - 42, y - 8), 28, paint);
      canvas.drawCircle(Offset(baseX + 44, y - 10), 24, paint);
    }
  }

  void _paintRain(Canvas canvas, Size size) {
    final rainStrength = weather.rainFactor.clamp(0.0, 1.0);
    final count = (65 + rainStrength * 95).round();
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 1.05 + rainStrength * 0.7
      ..color = const Color(
        0xFFC6E9FF,
      ).withValues(alpha: 0.14 + rainStrength * 0.26);

    final hLimit = size.height * 0.86;
    for (var i = 0; i < count; i++) {
      final seed = i * 17.43;
      final x =
          ((i * 31.0) + progress * 2100 + (math.sin(seed) * 33)).remainder(
            size.width + 50,
          ) -
          25;
      final y = ((i * 47.0) + progress * 2600).remainder(hLimit + 65) - 35;
      final len = 8 + ((i % 5) * 2) + rainStrength * 5;
      canvas.drawLine(
        Offset(x, y),
        Offset(x - 4 - rainStrength * 3, y + len),
        paint,
      );
    }
  }

  void _paintDust(Canvas canvas, Size size) {
    final dust = weather.hazeFactor.clamp(0.0, 1.0);
    final haze = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0x00CFB082),
          const Color(0x66CFB082).withValues(alpha: 0.10 + dust * 0.22),
          const Color(0x99B99D75).withValues(alpha: 0.08 + dust * 0.28),
          const Color(0x00000000),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, size.height));
    canvas.drawRect(Offset.zero & size, haze);

    final particles = (26 + dust * 24).round();
    final sand = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFF1CC96).withValues(alpha: 0.08 + dust * 0.15);
    for (var i = 0; i < particles; i++) {
      final x = ((i * 58.0) + progress * 900).remainder(size.width + 24) - 12;
      final y =
          size.height * (0.18 + ((i * 0.037 + progress * 0.7).remainder(0.62)));
      final r = 0.8 + ((i % 4) * 0.35);
      canvas.drawCircle(Offset(x, y), r, sand);
    }
  }

  void _paintFog(Canvas canvas, Size size) {
    final fog = weather.hazeFactor.clamp(0.0, 1.0);
    final paint = Paint()
      ..color = const Color(0xFFE8EFF8).withValues(alpha: 0.08 + fog * 0.14);

    for (var i = 0; i < 4; i++) {
      final wave = (math.sin((progress * math.pi * 2) + i) + 1) / 2;
      final y = size.height * (0.2 + i * 0.12 + wave * 0.02);
      final rect = RRect.fromRectAndRadius(
        Rect.fromLTWH(-20, y, size.width + 40, 34 + i * 4),
        const Radius.circular(22),
      );
      canvas.drawRRect(rect, paint);
    }
  }

  void _paintLightning(Canvas canvas, Size size) {
    final flash = (math.sin(progress * math.pi * 2 * 21) + 1) / 2;
    if (flash < 0.985) return;

    final p = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.20)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    final path = Path()
      ..moveTo(size.width * 0.62, size.height * 0.09)
      ..lineTo(size.width * 0.57, size.height * 0.2)
      ..lineTo(size.width * 0.64, size.height * 0.2)
      ..lineTo(size.width * 0.54, size.height * 0.36)
      ..lineTo(size.width * 0.6, size.height * 0.26)
      ..lineTo(size.width * 0.55, size.height * 0.26);
    canvas.drawPath(path, p);

    final overlay = Paint()
      ..color = const Color(0xFFFFFFFF).withValues(alpha: 0.05);
    canvas.drawRect(Offset.zero & size, overlay);
  }

  @override
  bool shouldRepaint(covariant _WeatherEffectPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.daylight != daylight ||
        oldDelegate.weather != weather;
  }
}

class _BasmayaSkylinePainter extends CustomPainter {
  final double progress;
  final double daylight;
  final _WeatherSnapshot weather;

  const _BasmayaSkylinePainter({
    required this.progress,
    required this.daylight,
    required this.weather,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final night = (1 - daylight).clamp(0.0, 1.0);
    final rain = weather.rainFactor;
    final haze = weather.hazeFactor;
    final horizon = size.height * 0.70;
    final deepShadow = Paint()
      ..color = Color.lerp(
        const Color(0xFF2D4D70).withValues(alpha: 0.82),
        const Color(0xFF050B18).withValues(alpha: 0.90),
        (night + rain * 0.2).clamp(0.0, 1.0),
      )!;
    canvas.drawRect(
      Rect.fromLTWH(0, horizon, size.width, size.height),
      deepShadow,
    );

    final towers = 18;
    final segment = size.width / towers;
    for (int i = 0; i < towers; i++) {
      final x = (i * segment) - 4;
      final wave = (math.sin((i * 0.75) + (progress * math.pi * 2)) + 1) / 2;
      final h = 64 + (i % 4) * 18 + (wave * 14);
      final w = segment * 0.82;
      final top = horizon - h;

      final bodyColor = Color.lerp(
        Color.lerp(
          const Color(0xFF3D6287).withValues(alpha: 0.95),
          const Color(0xFF304E73).withValues(alpha: 0.95),
          (i % 5) / 4,
        ),
        Color.lerp(
          const Color(0xFF10213F).withValues(alpha: 0.95),
          const Color(0xFF1A3560).withValues(alpha: 0.95),
          (i % 5) / 4,
        ),
        (night + haze * 0.22).clamp(0.0, 1.0),
      )!;
      final bodyPaint = Paint()..color = bodyColor;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x, top, w, h),
          const Radius.circular(4),
        ),
        bodyPaint,
      );

      final sideShade = Paint()
        ..color = const Color(
          0xFF030914,
        ).withValues(alpha: 0.06 + night * 0.10 + haze * 0.07);
      canvas.drawRect(Rect.fromLTWH(x + w * 0.62, top, w * 0.38, h), sideShade);

      final glowPaint = Paint()
        ..color = const Color(
          0xFF8ED9FF,
        ).withValues(alpha: 0.02 + (0.04 * night) + rain * 0.02);
      canvas.drawRect(Rect.fromLTWH(x, top, w, 2), glowPaint);

      final roofBlink = (math.sin(progress * math.pi * 2 * 1.7 + i) + 1) / 2;
      final roofPaint = Paint()
        ..color = Color.lerp(
          const Color(0xFF8EC4FF).withValues(alpha: 0.10 + night * 0.07),
          const Color(0xFFFFDDA5).withValues(alpha: 0.16 + night * 0.17),
          roofBlink,
        )!;
      canvas.drawCircle(Offset(x + w * 0.18, top + 2), 1.2, roofPaint);

      final cols = math.max(2, (w / 9).floor());
      final rows = math.max(3, (h / 12).floor());
      for (int r = 0; r < rows; r++) {
        for (int c = 0; c < cols; c++) {
          final seed = ((i + 1) * (r + 3) * (c + 5)) % 11;
          final flicker = (math.sin(progress * math.pi * 2 + seed) + 1) / 2;
          final dayTint = daylight > 0.42 && seed % 5 == 0;
          final lightOn =
              (night > 0.18 && ((seed % 3 == 0) || (flicker > 0.86))) ||
              dayTint;
          if (!lightOn) continue;

          final wx = x + 4 + (c * 7.5);
          final wy = top + 7 + (r * 9.0);
          final winPaint = Paint()
            ..color = Color.lerp(
              const Color(0xFFFFDFA3).withValues(alpha: 0.24 + night * 0.13),
              const Color(0xFFBEEBFF).withValues(alpha: 0.35 + night * 0.29),
              flicker,
            )!;
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(wx, wy, 3.2, 4.2),
              const Radius.circular(1),
            ),
            winPaint,
          );
        }
      }
    }

    final roadTop = horizon + 26;
    final roadPaint = Paint()
      ..color = const Color(0xFF0E2341).withValues(alpha: 0.60 + rain * 0.18);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, roadTop, size.width, 28),
        const Radius.circular(8),
      ),
      roadPaint,
    );

    final lanePaint = Paint()
      ..color = const Color(0xFF8EC9FF).withValues(alpha: 0.08 + night * 0.08)
      ..strokeWidth = 1.2;
    for (var i = 0; i < 5; i++) {
      final start = (i * 88.0 + progress * 180).remainder(size.width + 70) - 35;
      canvas.drawLine(
        Offset(start, roadTop + 14),
        Offset(start + 26, roadTop + 14),
        lanePaint,
      );
    }

    final carFront = Paint()
      ..color = const Color(0xFFFFE3A8).withValues(alpha: 0.20 + night * 0.42)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    final carRear = Paint()
      ..color = const Color(0xFFFF7892).withValues(alpha: 0.18 + night * 0.28)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < 4; i++) {
      final fx = ((progress * 300) + i * 96).remainder(size.width + 60) - 30;
      final rx =
          ((1 - progress) * 280 + i * 118).remainder(size.width + 60) - 30;
      canvas.drawLine(
        Offset(fx - 6, roadTop + 9),
        Offset(fx + 8, roadTop + 9),
        carFront,
      );
      canvas.drawLine(
        Offset(rx - 7, roadTop + 20),
        Offset(rx + 6, roadTop + 20),
        carRear,
      );
    }

    final groundGlow = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          const Color(0x004ED6FF),
          Color.lerp(
            const Color(0x194ED6FF),
            const Color(0x3B4ED6FF),
            (night + rain * 0.2).clamp(0.0, 1.0),
          )!,
          const Color(0x00112645).withValues(alpha: haze * 0.08),
        ],
      ).createShader(Rect.fromLTWH(0, horizon - 32, size.width, 90));
    canvas.drawRect(Rect.fromLTWH(0, horizon - 32, size.width, 90), groundGlow);

    final tp = TextPainter(
      text: TextSpan(
        text: '\u0628\u0633\u0645\u0627\u064a\u0629',
        style: TextStyle(
          fontSize: 28,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: const Color(
            0xFF9ADFFF,
          ).withValues(alpha: 0.06 + (0.07 * night) + rain * 0.03),
        ),
      ),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset((size.width - tp.width) / 2, horizon + 16));
  }

  @override
  bool shouldRepaint(covariant _BasmayaSkylinePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.daylight != daylight ||
        oldDelegate.weather != weather;
  }
}

class _SolarRing extends StatelessWidget {
  final double progress;
  final _SolarSnapshot solar;

  const _SolarRing({required this.progress, required this.solar});

  @override
  Widget build(BuildContext context) {
    final bodyOffset = solar.orbitOffset;
    final isDay = solar.isDay;

    return SizedBox(
      width: 132,
      height: 132,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: const Size.square(132),
            painter: _RingPainter(
              progress: progress,
              daylight: solar.daylight,
              isDay: solar.isDay,
            ),
          ),
          Transform.translate(
            offset: bodyOffset,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 900),
              curve: Curves.easeOutCubic,
              width: isDay ? 30 : 24,
              height: isDay ? 30 : 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: isDay
                      ? const [
                          Color(0xFFFFF6C2),
                          Color(0xFFFFD773),
                          Color(0xFFFFB25A),
                        ]
                      : const [
                          Color(0xFFF8FBFF),
                          Color(0xFFDDEBFF),
                          Color(0xFFB6C9E8),
                        ],
                ),
                boxShadow: [
                  BoxShadow(
                    blurRadius: isDay ? 20 : 13,
                    spreadRadius: isDay ? 2 : 1,
                    color:
                        (isDay
                                ? const Color(0xFFFFC36A)
                                : const Color(0xFFCDE0FF))
                            .withValues(alpha: isDay ? 0.50 : 0.35),
                  ),
                ],
                border: Border.all(
                  color:
                      (isDay
                              ? const Color(0xFFFFE2A0)
                              : const Color(0xFFEAF3FF))
                          .withValues(alpha: 0.85),
                ),
              ),
              child: Icon(
                isDay ? Icons.light_mode_rounded : Icons.dark_mode_rounded,
                size: 14,
                color: isDay
                    ? const Color(0xFF805100)
                    : const Color(0xFF445B78),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double daylight;
  final bool isDay;

  const _RingPainter({
    required this.progress,
    required this.daylight,
    required this.isDay,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2;

    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Color.lerp(
        const Color(0xFF5AC7FF).withValues(alpha: 0.28),
        const Color(0xFF33D4FF).withValues(alpha: 0.35),
        1 - daylight,
      )!;

    canvas.drawCircle(center, radius - 16, base);

    final pulse = (math.sin(progress * math.pi * 2) + 1) / 2;
    final pulsePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..color = (isDay
          ? Color.lerp(
              const Color(0xFFFFD986).withValues(alpha: 0.26),
              const Color(0xFFFF9F4A).withValues(alpha: 0.70),
              pulse,
            )
          : Color.lerp(
              const Color(0xFF95D8FF).withValues(alpha: 0.18),
              const Color(0xFF8BFAB8).withValues(alpha: 0.56),
              pulse,
            ))!;
    canvas.drawCircle(center, radius - 27, pulsePaint);

    final orbitPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = const Color(0xFFE8F6FF).withValues(alpha: 0.8);

    for (var i = 0; i < 3; i++) {
      final phase = progress * math.pi * 2 + (i * 2.1);
      final dx = center.dx + (radius - 18) * math.cos(phase);
      final dy = center.dy + (radius - 18) * math.sin(phase);
      canvas.drawCircle(Offset(dx, dy), 2.0, orbitPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.daylight != daylight ||
        oldDelegate.isDay != isDay;
  }
}
