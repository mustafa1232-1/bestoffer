import 'package:flutter/services.dart';

class IposPrinterStatus {
  final bool bluetoothEnabled;
  final bool bondedIposFound;
  final bool iposServiceInstalled;
  final String? deviceName;
  final String? deviceAddress;

  const IposPrinterStatus({
    required this.bluetoothEnabled,
    required this.bondedIposFound,
    required this.iposServiceInstalled,
    required this.deviceName,
    required this.deviceAddress,
  });

  factory IposPrinterStatus.fromMap(Map<Object?, Object?> map) {
    String? toStr(Object? v) {
      if (v == null) return null;
      final s = v.toString().trim();
      return s.isEmpty ? null : s;
    }

    bool toBool(Object? v) => v == true;

    return IposPrinterStatus(
      bluetoothEnabled: toBool(map['bluetoothEnabled']),
      bondedIposFound: toBool(map['bondedIposFound']),
      iposServiceInstalled: toBool(map['iposServiceInstalled']),
      deviceName: toStr(map['deviceName']),
      deviceAddress: toStr(map['deviceAddress']),
    );
  }
}

class IposPrintResponse {
  final bool success;
  final String? errorCode;
  final String? errorMessage;

  const IposPrintResponse({
    required this.success,
    this.errorCode,
    this.errorMessage,
  });
}

class IposPrinterBridge {
  static const MethodChannel _channel = MethodChannel('maslaki/printer_bridge');

  static Future<IposPrinterStatus> getStatus() async {
    try {
      final map =
          await _channel.invokeMapMethod<Object?, Object?>('getIposStatus') ??
          <Object?, Object?>{};
      return IposPrinterStatus.fromMap(map);
    } catch (_) {
      return const IposPrinterStatus(
        bluetoothEnabled: false,
        bondedIposFound: false,
        iposServiceInstalled: false,
        deviceName: null,
        deviceAddress: null,
      );
    }
  }

  static Future<bool> printEscPosBytes(Uint8List bytes) async {
    final response = await printEscPosBytesDetailed(bytes);
    return response.success;
  }

  static Future<IposPrintResponse> printEscPosBytesDetailed(
    Uint8List bytes,
  ) async {
    try {
      final ok = await _channel.invokeMethod<bool>('printEscPosBytes', {
        'bytes': bytes,
      });
      return IposPrintResponse(success: ok == true);
    } on PlatformException catch (e) {
      return IposPrintResponse(
        success: false,
        errorCode: e.code,
        errorMessage: (e.message ?? '').trim().isEmpty
            ? 'Native printer error'
            : e.message,
      );
    } catch (e) {
      return IposPrintResponse(
        success: false,
        errorCode: 'UNKNOWN',
        errorMessage: '$e',
      );
    }
  }
}
