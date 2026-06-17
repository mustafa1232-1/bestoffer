import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/secure_networking_config.dart';

void main() {
  group('SecureNetworkingConfig', () {
    test('auto mode disables pinning outside release builds', () {
      final config = SecureNetworkingConfig.fromEnvironment(
        mode: 'auto',
        pinHostsRaw: 'api.maslaki.app',
        spkiPinsRaw: 'sha256/pin-a,pin-b',
        pinSetLabel: 'rotation-a',
        releaseMode: false,
      );

      expect(config.mode, 'off');
      expect(config.pinningEnabled, isFalse);
    });

    test('release auto mode enables multi-pin SPKI validation', () {
      final config = SecureNetworkingConfig.fromEnvironment(
        mode: 'auto',
        pinHostsRaw: 'api.maslaki.app,cdn.maslaki.app',
        spkiPinsRaw: 'sha256/pin-a,pin-b',
        pinSetLabel: 'rotation-b',
        releaseMode: true,
      );

      expect(config.mode, 'always');
      expect(config.pinningEnabled, isTrue);
      expect(config.spkiPins, <String>{'pin-a', 'pin-b'});
      expect(config.shouldPinHost('api.maslaki.app'), isTrue);
      expect(config.shouldPinHost('media.api.maslaki.app'), isTrue);
      expect(config.shouldPinHost('example.com'), isFalse);
      expect(config.pinSetLabel, 'rotation-b');
    });

    test('explicit off keeps pinning disabled even in release', () {
      final config = SecureNetworkingConfig.fromEnvironment(
        mode: 'off',
        pinHostsRaw: 'api.maslaki.app',
        spkiPinsRaw: 'pin-a',
        pinSetLabel: 'disabled',
        releaseMode: true,
      );

      expect(config.mode, 'off');
      expect(config.pinningEnabled, isFalse);
    });
  });
}
