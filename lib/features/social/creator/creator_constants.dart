const double storySegmentMaxSeconds = 60.0;
const double reelMaxSeconds = 90.0;
const double creatorStoryRecordingHardCapSeconds = 180.0;
const Duration creatorRecordingTick = Duration(milliseconds: 100);
const Duration creatorFaceTrackingThrottle = Duration(milliseconds: 180);

// ── Time Mood ─────────────────────────────────────────────────────────────────
// Key list: morning | forenoon | noon | afternoon | sunset | evening | night | late_night
String resolveTimeMoodKey() {
  final hour = DateTime.now().hour;
  if (hour >= 4 && hour < 8) return 'morning';
  if (hour >= 8 && hour < 12) return 'forenoon';
  if (hour >= 12 && hour < 14) return 'noon';
  if (hour >= 14 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 19) return 'sunset';
  if (hour >= 19 && hour < 22) return 'evening';
  if (hour >= 22) return 'night';
  return 'late_night'; // 00:00–03:59
}

String resolveTimeMoodKeyFromHour(int hour) {
  if (hour >= 4 && hour < 8) return 'morning';
  if (hour >= 8 && hour < 12) return 'forenoon';
  if (hour >= 12 && hour < 14) return 'noon';
  if (hour >= 14 && hour < 17) return 'afternoon';
  if (hour >= 17 && hour < 19) return 'sunset';
  if (hour >= 19 && hour < 22) return 'evening';
  if (hour >= 22) return 'night';
  return 'late_night';
}
