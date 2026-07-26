import 'package:core_design_system/core_design_system.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the three official themes have distinct palettes', () {
    final original = AppTheme.tokensForTheme(MaslakiTheme.original);
    final twilight = AppTheme.tokensForTheme(MaslakiTheme.twilight);
    final coral = AppTheme.tokensForTheme(MaslakiTheme.coral);

    final primaries = {
      original.primaryAccent,
      twilight.primaryAccent,
      coral.primaryAccent,
    };
    expect(primaries.length, 3, reason: 'each theme has a distinct primary');

    final backgrounds = {
      original.backgroundPrimary,
      twilight.backgroundPrimary,
      coral.backgroundPrimary,
    };
    expect(backgrounds.length, 3);
  });

  test('each theme exposes a coherent, readable token set', () {
    for (final theme in MaslakiTheme.values) {
      final t = AppTheme.tokensForTheme(theme);
      // sanity: text and background differ (contrast) and accents are set
      expect(t.textPrimary, isNot(t.backgroundPrimary));
      expect(t.primaryAccent, isNot(t.secondaryAccent));
    }
  });

  test('theme storage values round-trip and default to original', () {
    for (final theme in MaslakiTheme.values) {
      expect(MaslakiTheme.fromStorageValue(theme.storageValue), theme);
    }
    expect(MaslakiTheme.fromStorageValue(null), MaslakiTheme.original);
    expect(
      MaslakiTheme.fromStorageValue('legacy_unknown'),
      MaslakiTheme.original,
    );
  });
}
