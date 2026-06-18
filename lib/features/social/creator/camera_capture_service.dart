import 'dart:io';

import 'package:camera/camera.dart';
import 'package:path/path.dart' as path;

import '../../../core/files/local_media_file.dart';
import 'creator_temp_media_service.dart';

class CameraCaptureService {
  final CreatorTempMediaService tempMediaService;

  CameraCaptureService(this.tempMediaService);

  CameraController? _controller;
  List<CameraDescription> _cameras = const <CameraDescription>[];
  CameraDescription? _activeCamera;

  CameraController? get controller => _controller;
  List<CameraDescription> get cameras => _cameras;
  CameraDescription? get activeCamera => _activeCamera;

  Future<void> initialize({
    CameraLensDirection preferredLensDirection = CameraLensDirection.front,
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    bool enableAudio = true,
  }) async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) {
      throw CameraException('camera_unavailable', 'No device camera was found.');
    }
    _activeCamera =
        _cameras.where((camera) => camera.lensDirection == preferredLensDirection).firstOrNull ??
        _cameras.first;
    await _createController(
      description: _activeCamera!,
      resolutionPreset: resolutionPreset,
      enableAudio: enableAudio,
    );
  }

  Future<void> switchCamera({
    ResolutionPreset resolutionPreset = ResolutionPreset.high,
    bool enableAudio = true,
  }) async {
    if (_cameras.length < 2 || _activeCamera == null) return;
    final currentLens = _activeCamera!.lensDirection;
    final next = _cameras.firstWhere(
      (camera) => camera.lensDirection != currentLens,
      orElse: () => _activeCamera!,
    );
    if (next == _activeCamera) return;
    await _createController(
      description: next,
      resolutionPreset: resolutionPreset,
      enableAudio: enableAudio,
    );
    _activeCamera = next;
  }

  Future<void> setFlashMode(FlashMode mode) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    await controller.setFlashMode(mode);
  }

  Future<LocalMediaFile> takePhoto() async {
    final controller = _controller;
    if (controller == null) {
      throw CameraException('camera_not_initialized', 'Camera is not ready.');
    }
    final file = await controller.takePicture();
    return _localFileFromXFile(file, prefix: 'creator_photo', mimeType: 'image/jpeg');
  }

  Future<void> startRecording({onLatestImageAvailable? onAvailable}) async {
    final controller = _controller;
    if (controller == null) {
      throw CameraException('camera_not_initialized', 'Camera is not ready.');
    }
    try {
      await controller.prepareForVideoRecording();
    } catch (_) {
      // Some platforms do not need prewarming.
    }
    if (onAvailable == null) {
      await controller.startVideoRecording();
      return;
    }
    await controller.startVideoRecording(onAvailable: onAvailable);
  }

  Future<LocalMediaFile> stopRecording() async {
    final controller = _controller;
    if (controller == null) {
      throw CameraException('camera_not_initialized', 'Camera is not ready.');
    }
    final file = await controller.stopVideoRecording();
    return _localFileFromXFile(file, prefix: 'creator_video', mimeType: 'video/mp4');
  }

  Future<void> startPreviewStream(onLatestImageAvailable onAvailable) async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (controller.value.isRecordingVideo || controller.value.isStreamingImages) {
      return;
    }
    if (!controller.supportsImageStreaming()) return;
    await controller.startImageStream(onAvailable);
  }

  Future<void> stopPreviewStream() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (!controller.value.isStreamingImages || controller.value.isRecordingVideo) {
      return;
    }
    await controller.stopImageStream();
  }

  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> _createController({
    required CameraDescription description,
    required ResolutionPreset resolutionPreset,
    required bool enableAudio,
  }) async {
    // Tear the existing controller down FIRST. Keeping two CameraControllers
    // alive at once makes the new one open a camera the OS still holds, which
    // surfaces as a black preview (especially on Android). Stop any running
    // image stream before disposing so the platform releases cleanly.
    final existing = _controller;
    _controller = null;
    if (existing != null) {
      try {
        if (existing.value.isStreamingImages) {
          await existing.stopImageStream();
        }
      } catch (_) {
        // Best effort.
      }
      try {
        await existing.dispose();
      } catch (_) {
        // Best effort.
      }
    }
    final next = CameraController(
      description,
      resolutionPreset,
      enableAudio: enableAudio,
      imageFormatGroup: Platform.isIOS ? ImageFormatGroup.bgra8888 : ImageFormatGroup.yuv420,
    );
    await next.initialize();
    _controller = next;
  }

  Future<LocalMediaFile> _localFileFromXFile(
    XFile file, {
    required String prefix,
    required String mimeType,
  }) async {
    final copied = await tempMediaService.cleanupAndCopy(File(file.path), prefix: prefix);
    return LocalMediaFile(
      name: path.basename(copied.path),
      path: copied.path,
      bytes: null,
      mimeType: mimeType,
    );
  }
}

extension on Iterable<CameraDescription> {
  CameraDescription? get firstOrNull => isEmpty ? null : first;
}
