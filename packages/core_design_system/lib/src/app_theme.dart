import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'system_ui_styles.dart';
import 'theme_preset.dart';

@immutable
class MaslakiThemeTokens extends ThemeExtension<MaslakiThemeTokens> {
  final Color backgroundPrimary;
  final Color backgroundSecondary;
  final Color backgroundTertiary;
  final Color surfacePrimary;
  final Color surfaceSecondary;
  final Color cardPrimary;
  final Color cardElevated;
  final Color primaryAccent;
  final Color secondaryAccent;
  final Color textPrimary;
  final Color textSecondary;
  final Color textMuted;
  final Color borderSubtle;
  final Color success;
  final Color warning;
  final Color danger;
  final Color glowPrimary;
  final Color glowSecondary;

  const MaslakiThemeTokens({
    required this.backgroundPrimary,
    required this.backgroundSecondary,
    required this.backgroundTertiary,
    required this.surfacePrimary,
    required this.surfaceSecondary,
    required this.cardPrimary,
    required this.cardElevated,
    required this.primaryAccent,
    required this.secondaryAccent,
    required this.textPrimary,
    required this.textSecondary,
    required this.textMuted,
    required this.borderSubtle,
    required this.success,
    required this.warning,
    required this.danger,
    required this.glowPrimary,
    required this.glowSecondary,
  });

  const MaslakiThemeTokens.darkPremium()
    : this(
        backgroundPrimary: const Color(0xFFFBFAF6),
        backgroundSecondary: const Color(0xFFF3F0E8),
        backgroundTertiary: const Color(0xFFE7EEE5),
        surfacePrimary: const Color(0xFFFFFFFF),
        surfaceSecondary: const Color(0xFFF8F4EC),
        cardPrimary: const Color(0xFFFFFFFF),
        cardElevated: const Color(0xFFFCF8F0),
        primaryAccent: const Color(0xFF2F5D46),
        secondaryAccent: const Color(0xFFB88A2D),
        textPrimary: const Color(0xFF071827),
        textSecondary: const Color(0xFF2F4052),
        textMuted: const Color(0xFF647181),
        borderSubtle: const Color(0x5C9F8A56),
        success: const Color(0xFF2F7D4E),
        warning: const Color(0xFFB97817),
        danger: const Color(0xFFB42318),
        glowPrimary: const Color(0x332F5D46),
        glowSecondary: const Color(0x2EB88A2D),
      );

  /// «مسلكي الأصلي» — نيلي/كحلي + كريمي + ذهبي (الاتجاه الرسمي، = darkPremium).
  const MaslakiThemeTokens.maslakiOriginal() : this.darkPremium();

  /// «شفق مسلكي» — أزرق ليلي + تركوازي + بنفسجي مضيء، حديث دون التضحية بالوضوح.
  const MaslakiThemeTokens.maslakiTwilight()
    : this(
        backgroundPrimary: const Color(0xFFFBFCF8),
        backgroundSecondary: const Color(0xFFF0F5EC),
        backgroundTertiary: const Color(0xFFEEF3F4),
        surfacePrimary: const Color(0xFFFFFFFF),
        surfaceSecondary: const Color(0xFFF6FAF3),
        cardPrimary: const Color(0xFFFFFFFF),
        cardElevated: const Color(0xFFFAFCF7),
        primaryAccent: const Color(0xFF365F4B),
        secondaryAccent: const Color(0xFF94723A),
        textPrimary: const Color(0xFF071827),
        textSecondary: const Color(0xFF2F4052),
        textMuted: const Color(0xFF647181),
        borderSubtle: const Color(0x5A365F4B),
        success: const Color(0xFF2F7D4E),
        warning: const Color(0xFFB7822C),
        danger: const Color(0xFFB42318),
        glowPrimary: const Color(0x30365F4B),
        glowSecondary: const Color(0x2694723A),
      );

  /// «مسلكي المرجاني» — فحمي داكن + مرجاني + فيروزي + عاجي، جريء ومختلف.
  const MaslakiThemeTokens.maslakiCoral()
    : this(
        backgroundPrimary: const Color(0xFFFFFAF2),
        backgroundSecondary: const Color(0xFFF8EFE0),
        backgroundTertiary: const Color(0xFFE9F0E7),
        surfacePrimary: const Color(0xFFFFFCF7),
        surfaceSecondary: const Color(0xFFFFF7EC),
        cardPrimary: const Color(0xFFFFFFFF),
        cardElevated: const Color(0xFFFFF8EE),
        primaryAccent: const Color(0xFF2C5A43),
        secondaryAccent: const Color(0xFFC19A4A),
        textPrimary: const Color(0xFF071827),
        textSecondary: const Color(0xFF334252),
        textMuted: const Color(0xFF6C7280),
        borderSubtle: const Color(0x5CC19A4A),
        success: const Color(0xFF2F7D4E),
        warning: const Color(0xFFB97817),
        danger: const Color(0xFFB42318),
        glowPrimary: const Color(0x302C5A43),
        glowSecondary: const Color(0x2EC19A4A),
      );

  @override
  MaslakiThemeTokens copyWith({
    Color? backgroundPrimary,
    Color? backgroundSecondary,
    Color? backgroundTertiary,
    Color? surfacePrimary,
    Color? surfaceSecondary,
    Color? cardPrimary,
    Color? cardElevated,
    Color? primaryAccent,
    Color? secondaryAccent,
    Color? textPrimary,
    Color? textSecondary,
    Color? textMuted,
    Color? borderSubtle,
    Color? success,
    Color? warning,
    Color? danger,
    Color? glowPrimary,
    Color? glowSecondary,
  }) {
    return MaslakiThemeTokens(
      backgroundPrimary: backgroundPrimary ?? this.backgroundPrimary,
      backgroundSecondary: backgroundSecondary ?? this.backgroundSecondary,
      backgroundTertiary: backgroundTertiary ?? this.backgroundTertiary,
      surfacePrimary: surfacePrimary ?? this.surfacePrimary,
      surfaceSecondary: surfaceSecondary ?? this.surfaceSecondary,
      cardPrimary: cardPrimary ?? this.cardPrimary,
      cardElevated: cardElevated ?? this.cardElevated,
      primaryAccent: primaryAccent ?? this.primaryAccent,
      secondaryAccent: secondaryAccent ?? this.secondaryAccent,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textMuted: textMuted ?? this.textMuted,
      borderSubtle: borderSubtle ?? this.borderSubtle,
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      glowPrimary: glowPrimary ?? this.glowPrimary,
      glowSecondary: glowSecondary ?? this.glowSecondary,
    );
  }

  @override
  MaslakiThemeTokens lerp(ThemeExtension<MaslakiThemeTokens>? other, double t) {
    if (other is! MaslakiThemeTokens) return this;
    return MaslakiThemeTokens(
      backgroundPrimary: Color.lerp(
        backgroundPrimary,
        other.backgroundPrimary,
        t,
      )!,
      backgroundSecondary: Color.lerp(
        backgroundSecondary,
        other.backgroundSecondary,
        t,
      )!,
      backgroundTertiary: Color.lerp(
        backgroundTertiary,
        other.backgroundTertiary,
        t,
      )!,
      surfacePrimary: Color.lerp(surfacePrimary, other.surfacePrimary, t)!,
      surfaceSecondary: Color.lerp(
        surfaceSecondary,
        other.surfaceSecondary,
        t,
      )!,
      cardPrimary: Color.lerp(cardPrimary, other.cardPrimary, t)!,
      cardElevated: Color.lerp(cardElevated, other.cardElevated, t)!,
      primaryAccent: Color.lerp(primaryAccent, other.primaryAccent, t)!,
      secondaryAccent: Color.lerp(secondaryAccent, other.secondaryAccent, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      borderSubtle: Color.lerp(borderSubtle, other.borderSubtle, t)!,
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      glowPrimary: Color.lerp(glowPrimary, other.glowPrimary, t)!,
      glowSecondary: Color.lerp(glowSecondary, other.glowSecondary, t)!,
    );
  }
}

typedef MaslakiLuxuryTokens = MaslakiThemeTokens;

@immutable
class MaslakiTypographyTokens extends ThemeExtension<MaslakiTypographyTokens> {
  final String displayFamily;
  final String bodyFamily;
  final double displayLarge;
  final double pageTitle;
  final double sectionTitle;
  final double cardTitle;
  final double body;
  final double caption;
  final double micro;

  const MaslakiTypographyTokens({
    required this.displayFamily,
    required this.bodyFamily,
    required this.displayLarge,
    required this.pageTitle,
    required this.sectionTitle,
    required this.cardTitle,
    required this.body,
    required this.caption,
    required this.micro,
  });

  const MaslakiTypographyTokens.luxury()
    : this(
        displayFamily: 'Cairo',
        bodyFamily: 'Tajawal',
        displayLarge: 34,
        pageTitle: 26,
        sectionTitle: 20,
        cardTitle: 17,
        body: 14,
        caption: 12,
        micro: 10,
      );

  @override
  MaslakiTypographyTokens copyWith({
    String? displayFamily,
    String? bodyFamily,
    double? displayLarge,
    double? pageTitle,
    double? sectionTitle,
    double? cardTitle,
    double? body,
    double? caption,
    double? micro,
  }) {
    return MaslakiTypographyTokens(
      displayFamily: displayFamily ?? this.displayFamily,
      bodyFamily: bodyFamily ?? this.bodyFamily,
      displayLarge: displayLarge ?? this.displayLarge,
      pageTitle: pageTitle ?? this.pageTitle,
      sectionTitle: sectionTitle ?? this.sectionTitle,
      cardTitle: cardTitle ?? this.cardTitle,
      body: body ?? this.body,
      caption: caption ?? this.caption,
      micro: micro ?? this.micro,
    );
  }

  @override
  MaslakiTypographyTokens lerp(
    ThemeExtension<MaslakiTypographyTokens>? other,
    double t,
  ) {
    if (other is! MaslakiTypographyTokens) return this;
    return MaslakiTypographyTokens(
      displayFamily: t < 0.5 ? displayFamily : other.displayFamily,
      bodyFamily: t < 0.5 ? bodyFamily : other.bodyFamily,
      displayLarge: lerpDouble(displayLarge, other.displayLarge, t)!,
      pageTitle: lerpDouble(pageTitle, other.pageTitle, t)!,
      sectionTitle: lerpDouble(sectionTitle, other.sectionTitle, t)!,
      cardTitle: lerpDouble(cardTitle, other.cardTitle, t)!,
      body: lerpDouble(body, other.body, t)!,
      caption: lerpDouble(caption, other.caption, t)!,
      micro: lerpDouble(micro, other.micro, t)!,
    );
  }
}

@immutable
class MaslakiMotionTokens extends ThemeExtension<MaslakiMotionTokens> {
  final Duration fast;
  final Duration normal;
  final Duration slow;
  final Curve emphasizedCurve;
  final Curve exitCurve;

  const MaslakiMotionTokens({
    required this.fast,
    required this.normal,
    required this.slow,
    required this.emphasizedCurve,
    required this.exitCurve,
  });

  const MaslakiMotionTokens.luxury()
    : this(
        fast: const Duration(milliseconds: 120),
        normal: const Duration(milliseconds: 220),
        slow: const Duration(milliseconds: 360),
        emphasizedCurve: Curves.easeOutCubic,
        exitCurve: Curves.easeInCubic,
      );

  @override
  MaslakiMotionTokens copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Curve? emphasizedCurve,
    Curve? exitCurve,
  }) {
    return MaslakiMotionTokens(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      emphasizedCurve: emphasizedCurve ?? this.emphasizedCurve,
      exitCurve: exitCurve ?? this.exitCurve,
    );
  }

  @override
  MaslakiMotionTokens lerp(
    ThemeExtension<MaslakiMotionTokens>? other,
    double t,
  ) {
    if (other is! MaslakiMotionTokens) return this;
    return MaslakiMotionTokens(
      fast: Duration(
        milliseconds: lerpDouble(
          fast.inMilliseconds.toDouble(),
          other.fast.inMilliseconds.toDouble(),
          t,
        )!.round(),
      ),
      normal: Duration(
        milliseconds: lerpDouble(
          normal.inMilliseconds.toDouble(),
          other.normal.inMilliseconds.toDouble(),
          t,
        )!.round(),
      ),
      slow: Duration(
        milliseconds: lerpDouble(
          slow.inMilliseconds.toDouble(),
          other.slow.inMilliseconds.toDouble(),
          t,
        )!.round(),
      ),
      emphasizedCurve: t < 0.5 ? emphasizedCurve : other.emphasizedCurve,
      exitCurve: t < 0.5 ? exitCurve : other.exitCurve,
    );
  }
}

@immutable
class MaslakiShellTokens extends ThemeExtension<MaslakiShellTokens> {
  final double screenRadius;
  final double cardRadius;
  final double chipRadius;
  final double fieldRadius;
  final double navRadius;
  final double borderWidth;
  final double outerPadding;
  final double contentSpacing;
  final double bottomNavHeight;

  const MaslakiShellTokens({
    required this.screenRadius,
    required this.cardRadius,
    required this.chipRadius,
    required this.fieldRadius,
    required this.navRadius,
    required this.borderWidth,
    required this.outerPadding,
    required this.contentSpacing,
    required this.bottomNavHeight,
  });

  const MaslakiShellTokens.luxury()
    : this(
        screenRadius: 28,
        cardRadius: 24,
        chipRadius: 18,
        fieldRadius: 20,
        navRadius: 26,
        borderWidth: 1.0,
        outerPadding: 20,
        contentSpacing: 20,
        bottomNavHeight: 82,
      );

  @override
  MaslakiShellTokens copyWith({
    double? screenRadius,
    double? cardRadius,
    double? chipRadius,
    double? fieldRadius,
    double? navRadius,
    double? borderWidth,
    double? outerPadding,
    double? contentSpacing,
    double? bottomNavHeight,
  }) {
    return MaslakiShellTokens(
      screenRadius: screenRadius ?? this.screenRadius,
      cardRadius: cardRadius ?? this.cardRadius,
      chipRadius: chipRadius ?? this.chipRadius,
      fieldRadius: fieldRadius ?? this.fieldRadius,
      navRadius: navRadius ?? this.navRadius,
      borderWidth: borderWidth ?? this.borderWidth,
      outerPadding: outerPadding ?? this.outerPadding,
      contentSpacing: contentSpacing ?? this.contentSpacing,
      bottomNavHeight: bottomNavHeight ?? this.bottomNavHeight,
    );
  }

  @override
  MaslakiShellTokens lerp(ThemeExtension<MaslakiShellTokens>? other, double t) {
    if (other is! MaslakiShellTokens) return this;
    return MaslakiShellTokens(
      screenRadius: lerpDouble(screenRadius, other.screenRadius, t)!,
      cardRadius: lerpDouble(cardRadius, other.cardRadius, t)!,
      chipRadius: lerpDouble(chipRadius, other.chipRadius, t)!,
      fieldRadius: lerpDouble(fieldRadius, other.fieldRadius, t)!,
      navRadius: lerpDouble(navRadius, other.navRadius, t)!,
      borderWidth: lerpDouble(borderWidth, other.borderWidth, t)!,
      outerPadding: lerpDouble(outerPadding, other.outerPadding, t)!,
      contentSpacing: lerpDouble(contentSpacing, other.contentSpacing, t)!,
      bottomNavHeight: lerpDouble(bottomNavHeight, other.bottomNavHeight, t)!,
    );
  }
}

@immutable
class AppVisualTheme extends ThemeExtension<AppVisualTheme> {
  final Color bgStart;
  final Color bgMiddle;
  final Color bgEnd;
  final Color glassBase;
  final Color glassStrong;
  final Color heroTop;
  final Color heroBottom;
  final Color accentBlue;
  final Color accentViolet;
  final Color accentCyan;
  final Color accentGold;

  const AppVisualTheme({
    required this.bgStart,
    required this.bgMiddle,
    required this.bgEnd,
    required this.glassBase,
    required this.glassStrong,
    required this.heroTop,
    required this.heroBottom,
    required this.accentBlue,
    required this.accentViolet,
    required this.accentCyan,
    required this.accentGold,
  });

  const AppVisualTheme.premium()
    : this(
        bgStart: const Color(0xFFF8F5EF),
        bgMiddle: const Color(0xFFF2EDE4),
        bgEnd: const Color(0xFFE9EFE7),
        glassBase: const Color(0xFFFFFCF7),
        glassStrong: const Color(0xFFFFFFFF),
        heroTop: const Color(0xFFF7F0E4),
        heroBottom: const Color(0xFFE3EBDD),
        accentBlue: const Color(0xFF17324A),
        accentViolet: const Color(0xFFCAD8CB),
        accentCyan: const Color(0xFF2F5D46),
        accentGold: const Color(0xFFB88A2D),
      );

  const AppVisualTheme.premiumLight() : this.premium();

  @override
  AppVisualTheme copyWith({
    Color? bgStart,
    Color? bgMiddle,
    Color? bgEnd,
    Color? glassBase,
    Color? glassStrong,
    Color? heroTop,
    Color? heroBottom,
    Color? accentBlue,
    Color? accentViolet,
    Color? accentCyan,
    Color? accentGold,
  }) {
    return AppVisualTheme(
      bgStart: bgStart ?? this.bgStart,
      bgMiddle: bgMiddle ?? this.bgMiddle,
      bgEnd: bgEnd ?? this.bgEnd,
      glassBase: glassBase ?? this.glassBase,
      glassStrong: glassStrong ?? this.glassStrong,
      heroTop: heroTop ?? this.heroTop,
      heroBottom: heroBottom ?? this.heroBottom,
      accentBlue: accentBlue ?? this.accentBlue,
      accentViolet: accentViolet ?? this.accentViolet,
      accentCyan: accentCyan ?? this.accentCyan,
      accentGold: accentGold ?? this.accentGold,
    );
  }

  @override
  AppVisualTheme lerp(ThemeExtension<AppVisualTheme>? other, double t) {
    if (other is! AppVisualTheme) return this;
    return AppVisualTheme(
      bgStart: Color.lerp(bgStart, other.bgStart, t)!,
      bgMiddle: Color.lerp(bgMiddle, other.bgMiddle, t)!,
      bgEnd: Color.lerp(bgEnd, other.bgEnd, t)!,
      glassBase: Color.lerp(glassBase, other.glassBase, t)!,
      glassStrong: Color.lerp(glassStrong, other.glassStrong, t)!,
      heroTop: Color.lerp(heroTop, other.heroTop, t)!,
      heroBottom: Color.lerp(heroBottom, other.heroBottom, t)!,
      accentBlue: Color.lerp(accentBlue, other.accentBlue, t)!,
      accentViolet: Color.lerp(accentViolet, other.accentViolet, t)!,
      accentCyan: Color.lerp(accentCyan, other.accentCyan, t)!,
      accentGold: Color.lerp(accentGold, other.accentGold, t)!,
    );
  }
}

extension AppVisualThemeContextX on BuildContext {
  AppVisualTheme get visualTheme =>
      Theme.of(this).extension<AppVisualTheme>() ??
      const AppVisualTheme.premium();

  MaslakiThemeTokens get maslakiTokens =>
      Theme.of(this).extension<MaslakiThemeTokens>() ??
      const MaslakiThemeTokens.darkPremium();

  MaslakiLuxuryTokens get luxuryTokens => maslakiTokens;

  MaslakiTypographyTokens get maslakiTypography =>
      Theme.of(this).extension<MaslakiTypographyTokens>() ??
      const MaslakiTypographyTokens.luxury();

  MaslakiMotionTokens get maslakiMotion =>
      Theme.of(this).extension<MaslakiMotionTokens>() ??
      const MaslakiMotionTokens.luxury();

  MaslakiShellTokens get maslakiShell =>
      Theme.of(this).extension<MaslakiShellTokens>() ??
      const MaslakiShellTokens.luxury();
}

class AppTheme {
  static const MaslakiThemeTokens _tokens = MaslakiThemeTokens.darkPremium();
  static const AppVisualTheme _visual = AppVisualTheme.premium();
  static const MaslakiTypographyTokens _type = MaslakiTypographyTokens.luxury();
  static const MaslakiMotionTokens _motion = MaslakiMotionTokens.luxury();
  static const MaslakiShellTokens _shell = MaslakiShellTokens.luxury();

  /// يختار لوحة الألوان حسب الثيم الرسمي (المرحلة 9).
  static MaslakiThemeTokens tokensForTheme(MaslakiTheme theme) {
    switch (theme) {
      case MaslakiTheme.twilight:
        return const MaslakiThemeTokens.maslakiTwilight();
      case MaslakiTheme.coral:
        return const MaslakiThemeTokens.maslakiCoral();
      case MaslakiTheme.original:
        return const MaslakiThemeTokens.maslakiOriginal();
    }
  }

  /// يبني ThemeData لأحد الثيمات الثلاثة.
  static ThemeData themed(MaslakiTheme theme) {
    return dark(tokens: tokensForTheme(theme));
  }

  static ThemeData light({
    AppThemePreset preset = AppThemePreset.midnightBlue,
    MaslakiThemeTokens? tokens,
  }) {
    return dark(preset: preset, tokens: tokens);
  }

  static ThemeData dark({
    AppThemePreset preset = AppThemePreset.midnightBlue,
    MaslakiThemeTokens? tokens,
  }) {
    final MaslakiThemeTokens t = tokens ?? _tokens;
    final scheme = ColorScheme(
      brightness: Brightness.light,
      primary: t.primaryAccent,
      onPrimary: Colors.white,
      secondary: t.secondaryAccent,
      onSecondary: const Color(0xFF071827),
      tertiary: t.success,
      onTertiary: Colors.white,
      error: t.danger,
      onError: Colors.white,
      surface: t.surfacePrimary,
      onSurface: t.textPrimary,
      primaryContainer: t.surfaceSecondary,
      onPrimaryContainer: t.textPrimary,
      secondaryContainer: t.cardElevated,
      onSecondaryContainer: t.textPrimary,
      tertiaryContainer: t.backgroundSecondary,
      onTertiaryContainer: t.textPrimary,
      outline: t.borderSubtle,
      outlineVariant: t.borderSubtle.withValues(alpha: 0.72),
      shadow: const Color(0x330D1B2A),
      scrim: Colors.black,
      inverseSurface: t.textPrimary,
      onInverseSurface: t.surfacePrimary,
      inversePrimary: t.primaryAccent.withValues(alpha: 0.48),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.light,
      extensions: <ThemeExtension<dynamic>>[t, _visual, _type, _motion, _shell],
    );

    final textTheme = _buildHybridTextTheme(base.textTheme, t);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: Colors.transparent,
      // Legacy DropdownButton routes use canvasColor as their menu surface.
      // Keep it opaque so menu options never blend into the form underneath.
      canvasColor: t.surfacePrimary,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        // Color-free overlay: the M3 AppBar default sets a transparent
        // statusBarColor, which routes to deprecated Window APIs.
        systemOverlayStyle: MaslakiSystemUiStyles.lightIcons,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: t.textPrimary,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w800,
          color: t.textPrimary,
        ),
        iconTheme: IconThemeData(color: t.secondaryAccent),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: t.surfacePrimary.withValues(alpha: 0.98),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(
            right: Radius.circular(_shell.screenRadius),
          ),
        ),
      ),
      cardTheme: CardThemeData(
        color: t.cardPrimary.withValues(alpha: 0.98),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.cardRadius),
          side: BorderSide(color: t.borderSubtle.withValues(alpha: 0.90)),
        ),
      ),
      dividerColor: t.borderSubtle.withValues(alpha: 0.66),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: t.surfacePrimary,
        errorMaxLines: 3,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 16,
        ),
        errorStyle: textTheme.bodySmall?.copyWith(
          color: t.danger,
          fontWeight: FontWeight.w700,
        ),
        border: _outlineBorder(t, _shell.fieldRadius),
        enabledBorder: _outlineBorder(t, _shell.fieldRadius),
        disabledBorder: _outlineBorder(t, _shell.fieldRadius),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_shell.fieldRadius),
          borderSide: BorderSide(color: t.primaryAccent, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_shell.fieldRadius),
          borderSide: BorderSide(color: t.danger, width: 1.1),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(_shell.fieldRadius),
          borderSide: BorderSide(color: t.danger, width: 1.3),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w800,
        ),
        floatingLabelStyle: textTheme.bodyMedium?.copyWith(
          color: t.primaryAccent,
          fontWeight: FontWeight.w900,
        ),
        hintStyle: textTheme.bodyMedium?.copyWith(
          color: t.textMuted,
          fontWeight: FontWeight.w600,
        ),
        prefixIconColor: t.primaryAccent,
        suffixIconColor: t.secondaryAccent,
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyLarge?.copyWith(
          color: t.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        menuStyle: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surfacePrimary),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            t.textPrimary.withValues(alpha: 0.22),
          ),
          elevation: const WidgetStatePropertyAll(10),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 8),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: t.borderSubtle.withValues(alpha: 0.95)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_shell.fieldRadius),
            ),
          ),
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(t.surfacePrimary),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          shadowColor: WidgetStatePropertyAll(
            t.textPrimary.withValues(alpha: 0.22),
          ),
          elevation: const WidgetStatePropertyAll(10),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(vertical: 8),
          ),
          side: WidgetStatePropertyAll(
            BorderSide(color: t.borderSubtle.withValues(alpha: 0.95)),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_shell.fieldRadius),
            ),
          ),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: t.surfacePrimary,
        surfaceTintColor: Colors.transparent,
        shadowColor: t.textPrimary.withValues(alpha: 0.22),
        elevation: 10,
        position: PopupMenuPosition.under,
        menuPadding: const EdgeInsets.symmetric(vertical: 8),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.fieldRadius),
          side: BorderSide(color: t.borderSubtle.withValues(alpha: 0.95)),
        ),
        textStyle: textTheme.bodyLarge?.copyWith(
          color: t.textPrimary,
          fontWeight: FontWeight.w700,
        ),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          return textTheme.bodyLarge?.copyWith(
            color: states.contains(WidgetState.disabled)
                ? t.textMuted
                : t.textPrimary,
            fontWeight: FontWeight.w700,
          );
        }),
        iconColor: t.primaryAccent,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: const Size(0, 54),
          elevation: 0,
          backgroundColor: t.primaryAccent,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_shell.fieldRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
            fontFamily: GoogleFonts.tajawal().fontFamily,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 50),
          foregroundColor: t.textPrimary,
          side: BorderSide(color: t.borderSubtle.withValues(alpha: 0.95)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_shell.fieldRadius),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: t.secondaryAccent,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: t.primaryAccent,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.fieldRadius),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: t.primaryAccent,
        unselectedLabelColor: t.textMuted,
        indicatorColor: t.secondaryAccent,
        dividerColor: t.borderSubtle.withValues(alpha: 0.58),
        labelStyle: textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w900),
        unselectedLabelStyle: textTheme.labelLarge?.copyWith(
          fontWeight: FontWeight.w700,
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: t.surfacePrimary.withValues(alpha: 0.99),
        indicatorColor: t.primaryAccent.withValues(alpha: 0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.navRadius),
        ),
        elevation: 0,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? t.primaryAccent : t.textMuted,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? t.primaryAccent : t.textMuted);
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: t.surfaceSecondary.withValues(alpha: 0.72),
        selectedColor: t.primaryAccent.withValues(alpha: 0.16),
        side: BorderSide(color: t.borderSubtle.withValues(alpha: 0.94)),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.chipRadius),
        ),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w700,
        ),
        secondaryLabelStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white,
          fontWeight: FontWeight.w800,
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: t.primaryAccent,
        textColor: t.textPrimary,
        titleTextStyle: textTheme.titleSmall?.copyWith(
          color: t.textPrimary,
          fontWeight: FontWeight.w900,
        ),
        subtitleTextStyle: textTheme.bodySmall?.copyWith(
          color: t.textSecondary,
          fontWeight: FontWeight.w600,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.fieldRadius),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: t.surfaceSecondary.withValues(alpha: 0.98),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: t.textPrimary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.fieldRadius),
          side: BorderSide(color: t.borderSubtle.withValues(alpha: 0.92)),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: t.primaryAccent,
        circularTrackColor: t.borderSubtle.withValues(alpha: 0.42),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: t.surfacePrimary.withValues(alpha: 0.98),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(_shell.screenRadius),
          ),
          side: BorderSide(color: t.borderSubtle.withValues(alpha: 0.90)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: t.surfacePrimary,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(_shell.cardRadius),
          side: BorderSide(color: t.borderSubtle.withValues(alpha: 0.92)),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, 50),
          backgroundColor: t.primaryAccent,
          foregroundColor: Colors.white,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(_shell.fieldRadius),
          ),
        ),
      ),
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _RiseFadePageTransitionsBuilder(),
          TargetPlatform.iOS: _RiseFadePageTransitionsBuilder(),
          TargetPlatform.linux: _RiseFadePageTransitionsBuilder(),
          TargetPlatform.macOS: _RiseFadePageTransitionsBuilder(),
          TargetPlatform.windows: _RiseFadePageTransitionsBuilder(),
        },
      ),
    );
  }

  static OutlineInputBorder _outlineBorder(
    MaslakiThemeTokens tokens,
    double radius,
  ) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radius),
      borderSide: BorderSide(
        color: tokens.borderSubtle.withValues(alpha: 0.88),
      ),
    );
  }

  static TextTheme _buildHybridTextTheme(
    TextTheme base,
    MaslakiThemeTokens tokens,
  ) {
    // Bundled Arabic fallback (assets/fonts/NotoNaskhArabic). The primary fonts
    // (Cairo/Tajawal) are fetched at runtime via google_fonts and can be
    // unavailable in release/offline, and some weights miss glyphs — without a
    // bundled fallback, letters like "ف" can drop out. Noto Naskh covers the
    // full Arabic set so every glyph always renders.
    const arabicFallback = <String>['TajawalLocal'];
    final display = GoogleFonts.cairoTextTheme(base).apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
      fontFamilyFallback: arabicFallback,
    );
    final body = GoogleFonts.tajawalTextTheme(base).apply(
      bodyColor: tokens.textPrimary,
      displayColor: tokens.textPrimary,
      fontFamilyFallback: arabicFallback,
    );

    return base.copyWith(
      displayLarge: display.displayLarge?.copyWith(
        fontWeight: FontWeight.w900,
        fontSize: 38,
        height: 1.08,
        letterSpacing: 0.1,
        color: tokens.textPrimary,
      ),
      displayMedium: display.displayMedium?.copyWith(
        fontWeight: FontWeight.w900,
        fontSize: 32,
        height: 1.1,
        color: tokens.textPrimary,
      ),
      headlineLarge: display.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 28,
        height: 1.15,
        color: tokens.textPrimary,
      ),
      headlineMedium: display.headlineMedium?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 24,
        height: 1.18,
        color: tokens.textPrimary,
      ),
      headlineSmall: display.headlineSmall?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 21,
        height: 1.2,
        color: tokens.textPrimary,
      ),
      titleLarge: display.titleLarge?.copyWith(
        fontWeight: FontWeight.w900,
        fontSize: 19,
        height: 1.24,
        color: tokens.textPrimary,
      ),
      titleMedium: display.titleMedium?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 16.5,
        height: 1.25,
        color: tokens.textPrimary,
      ),
      titleSmall: display.titleSmall?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 14.5,
        height: 1.22,
        color: tokens.textPrimary,
      ),
      bodyLarge: body.bodyLarge?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 15.5,
        height: 1.48,
        color: tokens.textPrimary,
      ),
      bodyMedium: body.bodyMedium?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 14.5,
        height: 1.52,
        color: tokens.textSecondary,
      ),
      bodySmall: body.bodySmall?.copyWith(
        fontWeight: FontWeight.w600,
        fontSize: 12.5,
        height: 1.46,
        color: tokens.textMuted,
      ),
      labelLarge: body.labelLarge?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 14.5,
        height: 1.14,
        color: tokens.textPrimary,
      ),
      labelMedium: body.labelMedium?.copyWith(
        fontWeight: FontWeight.w800,
        fontSize: 12.5,
        height: 1.14,
        color: tokens.textSecondary,
      ),
      labelSmall: body.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        fontSize: 11,
        height: 1.1,
        color: tokens.textMuted,
      ),
    );
  }
}

abstract final class MaslakiSpacing {
  static const double xxs = 4;
  static const double xs = 8;
  static const double sm = 12;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double xxl = 32;
  static const double xxxl = 40;
}

abstract final class MaslakiRadius {
  static const Radius sm = Radius.circular(12);
  static const Radius md = Radius.circular(16);
  static const Radius lg = Radius.circular(20);
  static const Radius xl = Radius.circular(24);
  static const Radius xxl = Radius.circular(28);
}

class _RiseFadePageTransitionsBuilder extends PageTransitionsBuilder {
  const _RiseFadePageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    return FadeTransition(
      opacity: Tween<double>(begin: 0, end: 1).animate(curved),
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.026),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
