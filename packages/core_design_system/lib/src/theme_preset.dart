/// الثيمات الرسمية الثلاثة (المرحلة 9). الشعار ثابت عبر جميع الثيمات.
enum MaslakiTheme {
  original,
  twilight,
  coral;

  String get storageValue {
    switch (this) {
      case MaslakiTheme.original:
        return 'maslaki_original';
      case MaslakiTheme.twilight:
        return 'maslaki_twilight';
      case MaslakiTheme.coral:
        return 'maslaki_coral';
    }
  }

  static MaslakiTheme fromStorageValue(String? raw) {
    switch ((raw ?? '').trim().toLowerCase()) {
      case 'maslaki_twilight':
        return MaslakiTheme.twilight;
      case 'maslaki_coral':
        return MaslakiTheme.coral;
      // الافتراضي + توافق مع القيم القديمة.
      default:
        return MaslakiTheme.original;
    }
  }
}

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
