import 'dart:io';

import 'package:printing/printing.dart';

class AppPrintCapabilities {
  const AppPrintCapabilities({
    required this.supportsInternalBluetoothEscPos,
    required this.supportsSystemPrint,
    required this.supportsNetworkEscPos,
    required this.unsupportedReason,
  });

  final bool supportsInternalBluetoothEscPos;
  final bool supportsSystemPrint;
  final bool supportsNetworkEscPos;
  final String? unsupportedReason;
}

AppPrintCapabilities resolveAppPrintCapabilities({
  required PrintingInfo? printingInfo,
  bool? isAndroidOverride,
  bool? isIosOverride,
}) {
  final isAndroid = isAndroidOverride ?? Platform.isAndroid;
  final isIos = isIosOverride ?? Platform.isIOS;
  final supportsSystemPrint =
      printingInfo?.canPrint == true || printingInfo?.canListPrinters == true;
  final supportsInternalBluetoothEscPos = isAndroid;
  const supportsNetworkEscPos = true;

  return AppPrintCapabilities(
    supportsInternalBluetoothEscPos: supportsInternalBluetoothEscPos,
    supportsSystemPrint: supportsSystemPrint,
    supportsNetworkEscPos: supportsNetworkEscPos,
    unsupportedReason: isIos ? 'ios_internal_bluetooth_not_supported' : null,
  );
}
