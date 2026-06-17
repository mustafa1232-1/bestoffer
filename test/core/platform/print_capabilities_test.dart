import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/platform/print_capabilities.dart';
import 'package:printing/printing.dart';

void main() {
  group('AppPrintCapabilities', () {
    test('android exposes internal bluetooth and network printing', () {
      final capabilities = resolveAppPrintCapabilities(
        printingInfo: const PrintingInfo(
          canPrint: true,
          canListPrinters: true,
        ),
        isAndroidOverride: true,
        isIosOverride: false,
      );

      expect(capabilities.supportsInternalBluetoothEscPos, isTrue);
      expect(capabilities.supportsSystemPrint, isTrue);
      expect(capabilities.supportsNetworkEscPos, isTrue);
      expect(capabilities.unsupportedReason, isNull);
    });

    test('ios hides internal bluetooth while keeping supported paths visible', () {
      final capabilities = resolveAppPrintCapabilities(
        printingInfo: const PrintingInfo(canPrint: true),
        isAndroidOverride: false,
        isIosOverride: true,
      );

      expect(capabilities.supportsInternalBluetoothEscPos, isFalse);
      expect(capabilities.supportsSystemPrint, isTrue);
      expect(capabilities.supportsNetworkEscPos, isTrue);
      expect(
        capabilities.unsupportedReason,
        'ios_internal_bluetooth_not_supported',
      );
    });
  });
}
