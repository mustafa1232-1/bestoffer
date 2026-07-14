import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../social_v3/state/social_reels_v3_connector.dart';

/// Live Reels tab. Cut over to Social V3 — this now renders the full-screen
/// [SocialReelsScreenV3] via [SocialReelsV3Connector]. The old
/// `SocialReelViewerScreen` is no longer reachable from this route.
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
    return SocialReelsV3Connector(
      initialReelId: initialReelId,
      playbackEnabledListenable: playbackEnabledListenable,
    );
  }
}
