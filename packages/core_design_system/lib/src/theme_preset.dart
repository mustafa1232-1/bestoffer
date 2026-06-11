enum AppThemePreset {
  midnightBlue,
  royalIndigo,
  emeraldNight,
  sunsetNeon;

  /// Kept for backward-compatibility with older persisted values.
  /// Visual output is now fixed to one official Maslaki design direction.
  static const String fixedStorageValue = 'maslaki_dark_premium';

  String get storageValue => fixedStorageValue;

  static AppThemePreset fromStorageValue(String? raw) {
    final normalized = (raw ?? '').trim().toLowerCase();
    if (normalized == fixedStorageValue) return AppThemePreset.midnightBlue;
    // Legacy compatibility (old presets now map to the official fixed preset).
    if (normalized == 'midnight_blue') return AppThemePreset.midnightBlue;
    if (normalized == 'royal_indigo') return AppThemePreset.midnightBlue;
    if (normalized == 'emerald_night') return AppThemePreset.midnightBlue;
    if (normalized == 'sunset_neon') return AppThemePreset.midnightBlue;
    return AppThemePreset.midnightBlue;
  }
}
