import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'social_reel_viewer_screen.dart';

class SocialReelsScreen extends StatelessWidget {
  final int? initialReelId;
  final bool playbackEnabled;
  final ValueListenable<bool>? playbackEnabledListenable;

  const SocialReelsScreen({
    super.key,
    this.initialReelId,
    this.playbackEnabled = true,
    this.playbackEnabledListenable,
  });

  @override
  Widget build(BuildContext context) {
    final listenable = playbackEnabledListenable;
    if (listenable == null) {
      return SocialReelViewerScreen(
        initialReelId: initialReelId,
        playbackEnabled: playbackEnabled,
      );
    }
    return ValueListenableBuilder<bool>(
      valueListenable: listenable,
      builder: (context, enabled, _) {
        return SocialReelViewerScreen(
          initialReelId: initialReelId,
          playbackEnabled: enabled,
        );
      },
    );
  }
}
