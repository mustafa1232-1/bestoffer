import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

/// Global responsive shell:
/// - keeps content width readable on tablets/large screens,
/// - normalizes text scale for very small/very large devices.
class AppResponsiveShell extends StatelessWidget {
  final Widget child;

  const AppResponsiveShell({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final width = media.size.width;
    final appIsDesktop =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows ||
            defaultTargetPlatform == TargetPlatform.macOS ||
            defaultTargetPlatform == TargetPlatform.linux);
    final useDesktopCanvas = appIsDesktop && width >= 1180;
    final maxWidth = _maxContentWidth(width);
    final sidePadding = useDesktopCanvas ? 16.0 : _sidePadding(width);

    Widget out = MediaQuery(
      data: media.copyWith(
        textScaler: TextScaler.linear(_adaptiveTextScale(media)),
      ),
      child: child,
    );

    if (!useDesktopCanvas && width > maxWidth) {
      out = Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: out,
        ),
      );
    } else if (useDesktopCanvas) {
      out = Align(alignment: Alignment.topCenter, child: out);
    }

    if (sidePadding > 0) {
      out = Padding(
        padding: EdgeInsets.symmetric(horizontal: sidePadding),
        child: out,
      );
    }

    return out;
  }

  static double _adaptiveTextScale(MediaQueryData media) {
    final userScale = media.textScaler.scale(1.0);
    final widthFactor = (media.size.shortestSide / 390).clamp(0.92, 1.12);
    return (userScale * widthFactor).clamp(0.92, 1.20);
  }

  static double _maxContentWidth(double width) {
    if (width >= 1440) return 940;
    if (width >= 1180) return 860;
    if (width >= 920) return 760;
    if (width >= 760) return 680;
    return width;
  }

  static double _sidePadding(double width) {
    if (width >= 760) return 14;
    if (width >= 460) return 8;
    return 0;
  }
}
