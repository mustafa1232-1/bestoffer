import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/files/image_picker_service.dart';

void main() {
  // No platform plugin is registered in the unit-test VM, so every picker call
  // hits a MissingPluginException. The wrapper must swallow it and return a
  // safe empty result instead of crashing the calling screen (the same path a
  // user cancellation / null result takes on-device).
  TestWidgetsFlutterBinding.ensureInitialized();

  test('pickImageFromDevice returns null without throwing when unavailable',
      () async {
    expect(await pickImageFromDevice(), isNull);
  });

  test('pickMultipleImagesFromDevice returns empty without throwing', () async {
    expect(await pickMultipleImagesFromDevice(), isEmpty);
  });

  test('captureImageFromCamera returns null without throwing', () async {
    expect(await captureImageFromCamera(), isNull);
  });
}
