import 'dart:io';

import 'package:camera/camera.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:image_picker/image_picker.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('release keeps native plugin entry points registered', (
    tester,
  ) async {
    final tempDirectory = await getTemporaryDirectory();
    expect(await tempDirectory.exists(), isTrue);

    await Firebase.initializeApp();
    expect(Firebase.apps, isNotEmpty);

    await expectLater(
      availableCameras().timeout(const Duration(seconds: 15)),
      completes,
    );
    await expectLater(ImagePicker().retrieveLostData(), completes);
    await expectLater(Permission.camera.status, completes);
    await expectLater(Geolocator.isLocationServiceEnabled(), completes);

    final detector = FaceDetector(
      options: FaceDetectorOptions(performanceMode: FaceDetectorMode.fast),
    );
    try {
      await detector.processImage(
        InputImage.fromFilePath(
          '${tempDirectory.path}${Platform.pathSeparator}missing-smoke.jpg',
        ),
      );
    } catch (error) {
      expect(error, isNot(isA<MissingPluginException>()));
    } finally {
      await detector.close();
    }
  }, timeout: const Timeout(Duration(minutes: 2)));
}
