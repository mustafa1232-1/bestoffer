import 'package:flutter/material.dart';

class SocialThreadVisualTheme {
  final String key;
  final List<Color> backgroundGradient;
  final Color mineBubble;
  final Color peerBubble;
  final Color mineText;
  final Color peerText;
  final Color accent;

  const SocialThreadVisualTheme({
    required this.key,
    required this.backgroundGradient,
    required this.mineBubble,
    required this.peerBubble,
    required this.mineText,
    required this.peerText,
    required this.accent,
  });
}

const socialThreadThemeKeys = <String>[
  'default',
  'sunset',
  'ocean',
  'forest',
  'violet',
];

SocialThreadVisualTheme resolveSocialThreadTheme(
  ColorScheme scheme,
  String? themeKey,
) {
  final key = (themeKey ?? 'default').trim().toLowerCase();
  switch (key) {
    case 'sunset':
      return SocialThreadVisualTheme(
        key: key,
        backgroundGradient: <Color>[
          const Color(0xFFFFF0E4),
          const Color(0xFFFFE2D7),
        ],
        mineBubble: const Color(0xFFFF8A65),
        peerBubble: const Color(0xFFFFE0D1),
        mineText: Colors.white,
        peerText: const Color(0xFF5D2B1B),
        accent: const Color(0xFFE65100),
      );
    case 'ocean':
      return SocialThreadVisualTheme(
        key: key,
        backgroundGradient: <Color>[
          const Color(0xFFE5F5FF),
          const Color(0xFFDFF0F8),
        ],
        mineBubble: const Color(0xFF1E88E5),
        peerBubble: const Color(0xFFD7ECFF),
        mineText: Colors.white,
        peerText: const Color(0xFF113A5C),
        accent: const Color(0xFF1565C0),
      );
    case 'forest':
      return SocialThreadVisualTheme(
        key: key,
        backgroundGradient: <Color>[
          const Color(0xFFEAF7ED),
          const Color(0xFFDDEEE2),
        ],
        mineBubble: const Color(0xFF2E7D32),
        peerBubble: const Color(0xFFDCEFD8),
        mineText: Colors.white,
        peerText: const Color(0xFF193A1C),
        accent: const Color(0xFF1B5E20),
      );
    case 'violet':
      return SocialThreadVisualTheme(
        key: key,
        backgroundGradient: <Color>[
          const Color(0xFFF4EAFE),
          const Color(0xFFECE0FB),
        ],
        mineBubble: const Color(0xFF7E57C2),
        peerBubble: const Color(0xFFE6DBFB),
        mineText: Colors.white,
        peerText: const Color(0xFF39235C),
        accent: const Color(0xFF5E35B1),
      );
    default:
      return SocialThreadVisualTheme(
        key: 'default',
        backgroundGradient: <Color>[
          scheme.surface,
          scheme.surfaceContainerLowest,
        ],
        mineBubble: scheme.primaryContainer,
        peerBubble: scheme.surfaceContainerHighest,
        mineText: scheme.onPrimaryContainer,
        peerText: scheme.onSurface,
        accent: scheme.primary,
      );
  }
}
