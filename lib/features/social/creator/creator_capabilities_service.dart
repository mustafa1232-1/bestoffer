import 'package:camera/camera.dart';

import 'creator_models.dart';

class CreatorCapabilitiesService {
  CreatorCapabilitySnapshot inspect(List<CameraDescription> cameras) {
    final hasCamera = cameras.isNotEmpty;
    final hasFront = cameras.any(
      (camera) => camera.lensDirection == CameraLensDirection.front,
    );
    final hasRear = cameras.any(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    return CreatorCapabilitySnapshot(
      hasCamera: hasCamera,
      supportsPhotoCapture: hasCamera,
      supportsVideoCapture: hasCamera,
      supportsFrontCamera: hasFront,
      supportsRearCamera: hasRear,
      supportsFlash: hasCamera,
      supportsFaceTracking: hasCamera,
      supportsPhotoEffects: hasCamera,
      supportsVideoEffects: false,
      unsupportedReason: hasCamera ? null : 'camera_unavailable',
    );
  }
}
