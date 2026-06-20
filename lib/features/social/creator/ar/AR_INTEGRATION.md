# Maslaki AR effects — integration guide

The Dart abstraction layer is complete and vendor-neutral. It is **off by
default** and falls back to the built-in color-grade filters until a native SDK
+ license token are added. Nothing here ships a fake effect.

## Layer overview
- `ar_effect_models.dart` — `ArEffect`, `ArEffectCategory`, `ArCapability`.
- `ar_effect_provider.dart` — the `ArEffectProvider` contract the UI talks to.
- `none_ar_provider.dart` — default no-op (always falls back cleanly).
- `channel_ar_provider.dart` — one platform-channel impl for any SDK; ships
  `buildDeepArProvider()` and `buildBanubaProvider()`.
- `ar_provider_registry.dart` — picks DeepAR → Banuba → none by live capability.

## Method-channel contract (native must implement)
Channel names: `maslaki/ar/deepar`, `maslaki/ar/banuba`.

| method            | args                         | returns                                                                 |
|-------------------|------------------------------|-------------------------------------------------------------------------|
| `capability`      | —                            | `{sdkLinked, licensed, faceTracking, backgroundSegmentation, reason}`   |
| `initialize`      | `{licenseKey}`               | `bool`                                                                   |
| `availableEffects`| —                            | `[{id, arabicName, englishName, category, assetSlug, supported}]`       |
| `applyEffect`     | `{effectId}` (null = clear)  | —                                                                       |
| `dispose`         | —                            | —                                                                       |

The native renderer draws the SDK output into the camera surface (a
`PlatformView`/`Texture`). When a usable provider exists, the creator should
replace its `CameraPreview` with the provider's render view.

## DeepAR — Android
1. Add the SDK: `implementation 'ai.deepar:deepar:<version>'` in
   `android/app/build.gradle.kts`.
2. Place `.deepar` effect files in `android/app/src/main/assets/maslaki_ar/`.
3. Implement a `MethodChannel("maslaki/ar/deepar")` handler in a Kotlin plugin
   that owns a `DeepAR` instance + an `ARSurfaceProvider`, maps the methods
   above, and exposes a `PlatformView` for the render surface.
4. Pass the license via `--dart-define=MASLAKI_DEEPAR_LICENSE=<key>` (already
   read by `buildDeepArProvider()`).

## DeepAR — iOS
1. `pod 'DeepAR'` in `ios/Podfile`.
2. Add `.deepar` files to the app bundle.
3. Implement `FlutterMethodChannel("maslaki/ar/deepar")` in a Swift plugin that
   owns a `DeepAR` instance + a `FlutterPlatformView` for rendering.
4. Same `--dart-define` license key.

## Banuba — same shape
Use channel `maslaki/ar/banuba`, token via
`--dart-define=MASLAKI_BANUBA_TOKEN=<token>`, Banuba Player + effects folder.

## Assets the designer must deliver (per effect)
- Vendor effect file (`.deepar` for DeepAR, effect folder for Banuba).
- Anchored to face mesh landmarks; Maslaki palette (indigo / gold / beige).
- Preview thumbnail 256×256 PNG.

> Licenses/tokens are NEVER committed. They are injected at build time via
> `--dart-define` and stored in CI / local secrets only.
