import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class AppTheme {
  static const Color _ink = Color(0xFF061225);
  static const Color _surface = Color(0xFF10264D);
  static const Color _surfaceSoft = Color(0xFF1A3A73);
  static const Color _surfaceElevated = Color(0xFF224B86);
  static const Color _sky = Color(0xFF68E5FF);
  static const Color _sun = Color(0xFFFFB45E);
  static const Color _mint = Color(0xFF9EF9CB);

  static ThemeData light() {
    final scheme =
        ColorScheme.fromSeed(
          seedColor: _sky,
          brightness: Brightness.dark,
        ).copyWith(
          primary: _sky,
          onPrimary: _ink,
          secondary: _sun,
          onSecondary: _ink,
          tertiary: _mint,
          onTertiary: _ink,
          surface: _surface,
          onSurface: const Color(0xFFF2F7FF),
          error: const Color(0xFFFF678E),
          onError: Colors.white,
          primaryContainer: const Color(0xFF1A3D73),
          onPrimaryContainer: const Color(0xFFE9F6FF),
        );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      brightness: Brightness.dark,
    );

    final textTheme = GoogleFonts.cairoTextTheme(
      base.textTheme,
    ).apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

    return base.copyWith(
      textTheme: textTheme,
      scaffoldBackgroundColor: Colors.transparent,
      canvasColor: Colors.transparent,
      splashFactory: InkRipple.splashFactory,
      appBarTheme: AppBarTheme(
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: true,
        backgroundColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        titleTextStyle: textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.2,
        ),
      ),
      drawerTheme: DrawerThemeData(
        backgroundColor: scheme.surface.withValues(alpha: 0.93),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.horizontal(right: Radius.circular(24)),
        ),
      ),
      cardTheme: CardThemeData(
        color: _surfaceSoft.withValues(alpha: 0.76),
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.primary.withValues(alpha: 0.34)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surfaceElevated.withValues(alpha: 0.66),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary.withValues(alpha: 0.22)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.16)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: BorderSide(color: scheme.error),
        ),
        labelStyle: TextStyle(color: Colors.white.withValues(alpha: 0.92)),
        hintStyle: TextStyle(color: Colors.white.withValues(alpha: 0.60)),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 220),
          minimumSize: WidgetStateProperty.all(const Size(0, 48)),
          textStyle: WidgetStateProperty.all(
            textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.white.withValues(alpha: 0.44);
            }
            return _ink;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            if (states.contains(WidgetState.pressed)) {
              return _mint;
            }
            return scheme.primary;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return BorderSide(color: Colors.white.withValues(alpha: 0.08));
            }
            return BorderSide(color: scheme.primary.withValues(alpha: 0.45));
          }),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 46),
          foregroundColor: scheme.onSurface,
          side: BorderSide(color: scheme.secondary.withValues(alpha: 0.54)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: scheme.secondary,
          textStyle: textTheme.labelLarge?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.secondary,
        foregroundColor: _ink,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: _surface.withValues(alpha: 0.92),
        indicatorColor: scheme.primary.withValues(alpha: 0.20),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: scheme.primary,
            );
          }
          return textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w700,
            color: Colors.white.withValues(alpha: 0.72),
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return IconThemeData(color: scheme.primary);
          }
          return IconThemeData(color: Colors.white.withValues(alpha: 0.72));
        }),
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: _surfaceElevated.withValues(alpha: 0.58),
        selectedColor: scheme.primary.withValues(alpha: 0.28),
        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
        labelStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white.withValues(alpha: 0.94),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: scheme.secondary,
        textColor: scheme.onSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: _surfaceSoft.withValues(alpha: 0.95),
        contentTextStyle: textTheme.bodyMedium,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        circularTrackColor: Colors.white.withValues(alpha: 0.16),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: _surfaceSoft.withValues(alpha: 0.96),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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

    final opacity = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    final offset = Tween<Offset>(
      begin: const Offset(0, 0.05),
      end: Offset.zero,
    ).animate(curved);
    final scale = Tween<double>(begin: 0.986, end: 1.0).animate(curved);

    return FadeTransition(
      opacity: opacity,
      child: SlideTransition(
        position: offset,
        child: ScaleTransition(scale: scale, child: child),
      ),
    );
  }
}
