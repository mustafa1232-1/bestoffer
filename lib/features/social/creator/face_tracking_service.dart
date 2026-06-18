import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';

import 'creator_constants.dart';

class FaceTrackingService {
  final FaceDetector _detector = FaceDetector(
    options: FaceDetectorOptions(
      enableContours: true,
      enableTracking: true,
      performanceMode: FaceDetectorMode.fast,
    ),
  );

  bool _processing = false;
  DateTime? _lastProcessedAt;

  Future<void> processFrame({
    required CameraImage image,
    required CameraDescription description,
    required DeviceOrientation deviceOrientation,
    required void Function(Rect? normalizedRect, Face? face) onFaceDetected,
  }) async {
    final now = DateTime.now();
    if (_processing) return;
    if (_lastProcessedAt != null &&
        now.difference(_lastProcessedAt!) < creatorFaceTrackingThrottle) {
      return;
    }
    final rotation = _rotationFromCamera(
      description: description,
      deviceOrientation: deviceOrientation,
    );
    if (rotation == null) return;
    final inputImage = _buildInputImage(image: image, rotation: rotation);
    if (inputImage == null) return;
    _processing = true;
    _lastProcessedAt = now;
    try {
      final faces = await _detector.processImage(inputImage);
      if (faces.isEmpty) {
        onFaceDetected(null, null);
        return;
      }
      faces.sort(
        (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
          a.boundingBox.width * a.boundingBox.height,
        ),
      );
      final face = faces.first;
      // ML Kit reports the bounding box in the image space AFTER the rotation
      // metadata is applied, so for 90°/270° the displayed frame is portrait
      // (width/height swapped). Normalising by the raw sensor dimensions would
      // push `top` past 1.0 and the overlay off-screen — swap accordingly.
      final rotated = rotation == InputImageRotation.rotation90deg ||
          rotation == InputImageRotation.rotation270deg;
      final frameWidth =
          (rotated ? image.height : image.width).toDouble();
      final frameHeight =
          (rotated ? image.width : image.height).toDouble();
      final box = face.boundingBox;
      var left = (box.left / frameWidth).clamp(0.0, 1.0);
      final top = (box.top / frameHeight).clamp(0.0, 1.0);
      final width = (box.width / frameWidth).clamp(0.0, 1.0);
      final height = (box.height / frameHeight).clamp(0.0, 1.0);
      // The front-camera preview is mirrored, so mirror the overlay's X too.
      if (description.lensDirection == CameraLensDirection.front) {
        left = (1.0 - left - width).clamp(0.0, 1.0);
      }
      onFaceDetected(Rect.fromLTWH(left, top, width, height), face);
    } catch (_) {
      onFaceDetected(null, null);
    } finally {
      _processing = false;
    }
  }

  Future<Rect?> detectPrimaryFaceFromFile(String path) async {
    final faces = await _detector.processImage(InputImage.fromFilePath(path));
    if (faces.isEmpty) return null;
    faces.sort(
      (a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(
        a.boundingBox.width * a.boundingBox.height,
      ),
    );
    final face = faces.first.boundingBox;
    return Rect.fromLTWH(face.left, face.top, face.width, face.height);
  }

  Future<void> dispose() => _detector.close();

  InputImage? _buildInputImage({
    required CameraImage image,
    required InputImageRotation rotation,
  }) {
    final format = InputImageFormatValue.fromRawValue(image.format.raw);
    if (format == null) return null;
    if (Platform.isAndroid &&
        format != InputImageFormat.nv21 &&
        format != InputImageFormat.yuv_420_888) {
      return null;
    }
    if (Platform.isIOS &&
        format != InputImageFormat.bgra8888 &&
        format != InputImageFormat.yuv420) {
      return null;
    }
    if (image.planes.isEmpty) return null;
    final plane = image.planes.first;
    return InputImage.fromBytes(
      bytes: _concatenatePlanes(image.planes),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: plane.bytesPerRow,
      ),
    );
  }

  InputImageRotation? _rotationFromCamera({
    required CameraDescription description,
    required DeviceOrientation deviceOrientation,
  }) {
    if (Platform.isIOS) {
      return InputImageRotationValue.fromRawValue(description.sensorOrientation);
    }
    final compensation = switch (deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final sensor = description.sensorOrientation;
    final adjusted = description.lensDirection == CameraLensDirection.front
        ? (sensor + compensation) % 360
        : (sensor - compensation + 360) % 360;
    return InputImageRotationValue.fromRawValue(adjusted);
  }

  Uint8List _concatenatePlanes(List<Plane> planes) {
    final builder = BytesBuilder(copy: false);
    for (final plane in planes) {
      builder.add(plane.bytes);
    }
    return builder.toBytes();
  }
}
