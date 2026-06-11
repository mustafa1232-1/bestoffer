import 'package:flutter/material.dart';

import 'social_reel_viewer_screen.dart';

class SocialReelsScreen extends StatelessWidget {
  final int? initialReelId;

  const SocialReelsScreen({super.key, this.initialReelId});

  @override
  Widget build(BuildContext context) {
    return SocialReelViewerScreen(initialReelId: initialReelId);
  }
}
