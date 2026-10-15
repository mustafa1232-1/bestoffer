import 'package:flutter/material.dart';

/// Maslaki Social Design Tokens.
///
/// Centralized spacing, radius, shadow and typography constants scoped to the
/// community/social surfaces. These mirror the existing [SocialDesignTheme]
/// color palette (cream background, deep indigo primary, muted gold accent)
/// without duplicating color definitions.

abstract final class MaslakiSpacing {
  const MaslakiSpacing._();

  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 20;
  static const double xxl = 24;
  static const double xxxl = 32;
}

abstract final class MaslakiRadius {
  const MaslakiRadius._();

  static const double sm = 10;
  static const double md = 16;
  static const double lg = 20;
  static const double xl = 24;
  static const double pill = 999;
}

abstract final class MaslakiShadows {
  const MaslakiShadows._();

  static const List<BoxShadow> card = [
    BoxShadow(
      color: Color(0x1A000000),
      blurRadius: 8,
      offset: Offset(0, 4),
    ),
  ];

  static const List<BoxShadow> elevated = [
    BoxShadow(
      color: Color(0x29000000),
      blurRadius: 16,
      offset: Offset(0, 8),
    ),
  ];
}