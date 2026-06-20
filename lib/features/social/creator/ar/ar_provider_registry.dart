import 'ar_effect_provider.dart';
import 'channel_ar_provider.dart';
import 'none_ar_provider.dart';

/// Resolves which AR engine the creator should use. Order of preference:
/// DeepAR → Banuba → none. The first provider that reports a usable capability
/// (SDK linked + licensed) wins; otherwise the no-op provider is returned so the
/// creator falls back to the built-in color-grade filters with zero fake AR.
class ArProviderRegistry {
  ArProviderRegistry._();

  static final ArProviderRegistry instance = ArProviderRegistry._();

  static const NoneArProvider _none = NoneArProvider();

  ArEffectProvider? _active;

  /// All candidate providers in preference order (the no-op is the final
  /// fallback and is not probed).
  List<ArEffectProvider> candidates() => <ArEffectProvider>[
        buildDeepArProvider(),
        buildBanubaProvider(),
      ];

  /// Probes candidates once and caches the first usable one (or the no-op).
  Future<ArEffectProvider> resolveActive() async {
    final cached = _active;
    if (cached != null) return cached;
    for (final provider in candidates()) {
      try {
        final cap = await provider.capability();
        if (cap.isUsable) {
          _active = provider;
          return provider;
        }
      } catch (_) {
        // Probe failure → treat as unavailable and continue.
      }
    }
    _active = _none;
    return _none;
  }

  /// True when a real AR engine is linked + licensed on this build/device.
  Future<bool> hasUsableProvider() async {
    final provider = await resolveActive();
    return provider.id != 'none';
  }

  void reset() => _active = null;
}
