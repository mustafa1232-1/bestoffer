/// Vendor-neutral AR effect models. These describe face/AR effects in a way that
/// is independent of any single SDK (DeepAR, Banuba, …) so the creator UI never
/// depends on a concrete vendor.
library;

enum ArEffectCategory { identity, funny, beauty, background, mask }

/// One AR effect exposed by a provider. `assetSlug` is the vendor asset name the
/// native layer loads (e.g. a DeepAR `.deepar` file or a Banuba effect folder).
class ArEffect {
  final String id;
  final String arabicName;
  final String englishName;
  final ArEffectCategory category;
  final String providerId;
  final String assetSlug;

  /// True only when the provider has the asset loaded and rendering works.
  final bool supported;

  const ArEffect({
    required this.id,
    required this.arabicName,
    required this.englishName,
    required this.category,
    required this.providerId,
    required this.assetSlug,
    this.supported = false,
  });

  String label(String languageCode) =>
      languageCode == 'ar' ? arabicName : englishName;
}

/// Snapshot of what an AR provider can currently do on this device + build.
class ArCapability {
  final String providerId;
  final bool sdkLinked; // native SDK present in the build
  final bool licensed; // a valid license/token is configured
  final bool faceTracking; // provider exposes a face mesh
  final bool backgroundSegmentation;
  final String? unavailableReason;

  const ArCapability({
    required this.providerId,
    required this.sdkLinked,
    required this.licensed,
    required this.faceTracking,
    required this.backgroundSegmentation,
    required this.unavailableReason,
  });

  bool get isUsable => sdkLinked && licensed;

  const ArCapability.unavailable(this.providerId, this.unavailableReason)
      : sdkLinked = false,
        licensed = false,
        faceTracking = false,
        backgroundSegmentation = false;
}
