import 'ar_effect_models.dart';

/// Vendor-neutral contract every AR engine (DeepAR, Banuba, …) must implement.
///
/// The creator UI talks ONLY to this interface, so swapping or adding an SDK is
/// a registry change, never a UI change. A provider must honestly report
/// [capability]; a provider that is not licensed/linked returns `isUsable=false`
/// and an empty effect list, so the app never shows a non-working AR effect.
abstract class ArEffectProvider {
  String get id;

  /// Inspect the live capability (SDK linked? licensed? face mesh?).
  Future<ArCapability> capability();

  /// Initialize the native engine with the license token. No-op for providers
  /// that are not present. Returns true when the engine is ready to render.
  Future<bool> initialize();

  /// Effects this provider can render right now (empty until usable).
  Future<List<ArEffect>> availableEffects();

  /// Switch the active effect (null clears it). Throws nothing on unusable
  /// providers — it is a safe no-op.
  Future<void> applyEffect(String? effectId);

  /// Release native resources.
  Future<void> dispose();
}
