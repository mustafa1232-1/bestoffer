import 'package:core_design_system/core_design_system.dart'
    show MaslakiSystemUiStyles;
import 'package:flutter/material.dart';

/// Scoped to community: commerce, orders and taxi keep their existing theme.
abstract final class SocialDesignTheme {
  static const background = Color(0xFFF7F3EA);
  static const indigo = Color(0xFF10233F);
  static const gold = Color(0xFFC89B3C);
  static const ink = Color(0xFF14202E);
  static const muted = Color(0xFF636C78);
  static const dark = Color(0xFF080B10);
  static const motion = Duration(milliseconds: 200);

  static ThemeData of(BuildContext context) {
    final base = Theme.of(context);
    final scheme =
        ColorScheme.fromSeed(
          seedColor: indigo,
          brightness: Brightness.light,
        ).copyWith(
          primary: indigo,
          onPrimary: Colors.white,
          secondary: gold,
          onSecondary: ink,
          surface: Colors.white,
          onSurface: ink,
          onSurfaceVariant: muted,
          outline: const Color(0xFF8C9097),
          outlineVariant: const Color(0xFFE3DED4),
        );
    return base.copyWith(
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: base.textTheme.apply(bodyColor: ink, displayColor: ink),
      appBarTheme: base.appBarTheme.copyWith(
        systemOverlayStyle: MaslakiSystemUiStyles.darkIcons,
        backgroundColor: background,
        foregroundColor: indigo,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: indigo,
        foregroundColor: gold,
        shape: CircleBorder(),
      ),
      iconTheme: const IconThemeData(color: indigo),
    );
  }
}
