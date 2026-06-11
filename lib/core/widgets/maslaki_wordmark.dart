import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';

class MaslakiWordmark extends StatelessWidget {
  final double arabicSize;
  final double latinSize;
  final bool showLatin;
  final String arabicText;
  final String? subtitle;
  final CrossAxisAlignment crossAxisAlignment;
  final Color? arabicColor;
  final Color? latinColor;
  final FontWeight arabicWeight;
  final FontWeight latinWeight;
  final double latinLetterSpacing;

  const MaslakiWordmark({
    super.key,
    this.arabicSize = 28,
    this.latinSize = 12,
    this.showLatin = false,
    this.arabicText = 'مسلكي',
    this.subtitle,
    this.crossAxisAlignment = CrossAxisAlignment.start,
    this.arabicColor,
    this.latinColor,
    this.arabicWeight = FontWeight.w900,
    this.latinWeight = FontWeight.w500,
    this.latinLetterSpacing = 5.2,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final visual = context.visualTheme;
    final arColor = arabicColor ?? tokens.textPrimary;
    final enColor = latinColor ?? visual.accentGold;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: crossAxisAlignment,
      children: [
        Text(
          arabicText,
          textDirection: TextDirection.rtl,
          maxLines: 1,
          style: GoogleFonts.cairo(
            color: arColor,
            fontSize: arabicSize,
            fontWeight: arabicWeight,
            height: 1.02,
            letterSpacing: 0.1,
          ),
        ),
        if ((subtitle ?? '').trim().isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            subtitle!,
            textDirection: TextDirection.rtl,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.tajawal(
              color: enColor.withValues(alpha: 0.88),
              fontSize: latinSize,
              fontWeight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ],
        if (showLatin) ...[
          const SizedBox(height: 2),
          Text(
            'MASLAKI',
            maxLines: 1,
            style: GoogleFonts.montserrat(
              color: enColor,
              fontSize: latinSize,
              fontWeight: latinWeight,
              height: 1.0,
              letterSpacing: latinLetterSpacing,
            ),
          ),
        ],
      ],
    );
  }
}
