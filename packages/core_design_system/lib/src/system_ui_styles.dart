import 'package:flutter/services.dart';

/// System bar styles for Maslaki's edge-to-edge window.
///
/// These deliberately carry NO colors (statusBarColor,
/// systemNavigationBarColor, systemNavigationBarDividerColor). Any non-null
/// color — even transparent — makes the Flutter engine call the deprecated
/// `Window.setStatusBarColor` / `setNavigationBarColor` APIs that Google Play
/// flags on Android 15. Bar transparency is owned natively by
/// `enableEdgeToEdge()` in MainActivity; Dart only picks the icon brightness,
/// which goes through the non-deprecated WindowInsetsController APIs.
abstract final class MaslakiSystemUiStyles {
  /// Light icons, for the default dark Maslaki surfaces.
  static const SystemUiOverlayStyle lightIcons = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  /// Dark icons, for light surfaces such as the community theme.
  static const SystemUiOverlayStyle darkIcons = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.dark,
    statusBarBrightness: Brightness.light,
    systemNavigationBarIconBrightness: Brightness.dark,
  );
}
