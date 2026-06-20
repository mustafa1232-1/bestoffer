import 'ar_effect_models.dart';
import 'ar_effect_provider.dart';

/// Default provider used when no AR SDK is linked. It is always "available" but
/// renders nothing, so the creator falls back cleanly to the color-grade filters.
class NoneArProvider implements ArEffectProvider {
  const NoneArProvider();

  @override
  String get id => 'none';

  @override
  Future<ArCapability> capability() async => const ArCapability.unavailable(
        'none',
        'no_ar_sdk_linked',
      );

  @override
  Future<bool> initialize() async => false;

  @override
  Future<List<ArEffect>> availableEffects() async => const <ArEffect>[];

  @override
  Future<void> applyEffect(String? effectId) async {}

  @override
  Future<void> dispose() async {}
}
