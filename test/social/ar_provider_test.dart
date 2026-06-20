import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/creator/ar/ar_effect_models.dart';
import 'package:maslaki/features/social/creator/ar/ar_provider_registry.dart';
import 'package:maslaki/features/social/creator/ar/channel_ar_provider.dart';
import 'package:maslaki/features/social/creator/ar/none_ar_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AR abstraction layer (no SDK linked)', () {
    test('none provider is always a safe, empty fallback', () async {
      const provider = NoneArProvider();
      expect(provider.id, 'none');
      expect((await provider.capability()).isUsable, isFalse);
      expect(await provider.initialize(), isFalse);
      expect(await provider.availableEffects(), isEmpty);
      // applyEffect/dispose must not throw.
      await provider.applyEffect('anything');
      await provider.dispose();
    });

    test('channel providers report unavailable without a license token', () async {
      // No --dart-define license in the test env → degrade gracefully.
      final deepar = buildDeepArProvider();
      final banuba = buildBanubaProvider();
      expect(deepar.id, 'deepar');
      expect(banuba.id, 'banuba');
      expect((await deepar.capability()).isUsable, isFalse);
      expect((await banuba.capability()).isUsable, isFalse);
      expect(await deepar.availableEffects(), isEmpty);
      expect(await deepar.initialize(), isFalse);
      await deepar.applyEffect('x'); // no throw
    });

    test('registry falls back to none when nothing is usable', () async {
      ArProviderRegistry.instance.reset();
      final active = await ArProviderRegistry.instance.resolveActive();
      expect(active.id, 'none');
      expect(await ArProviderRegistry.instance.hasUsableProvider(), isFalse);
    });

    test('effect model exposes localized labels', () {
      const effect = ArEffect(
        id: 'golden_palm_crown',
        arabicName: 'تاج النخلة الذهبي',
        englishName: 'Golden Palm Crown',
        category: ArEffectCategory.identity,
        providerId: 'deepar',
        assetSlug: 'golden_palm_crown.deepar',
        supported: true,
      );
      expect(effect.label('ar'), 'تاج النخلة الذهبي');
      expect(effect.label('en'), 'Golden Palm Crown');
    });
  });
}
