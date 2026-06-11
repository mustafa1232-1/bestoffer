import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/social_models.dart';
import 'social_controller.dart';

final socialProfileInsightsProvider =
    FutureProvider.autoDispose.family<SocialProfileInsights, int>((
      ref,
      userId,
    ) async {
      final out = await ref.read(socialApiProvider).getProfileInsights(userId);
      return SocialProfileInsights.fromJson(out);
    });
