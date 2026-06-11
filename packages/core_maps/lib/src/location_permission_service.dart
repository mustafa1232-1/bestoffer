import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

final locationPermissionServiceProvider = Provider<LocationPermissionService>(
  (ref) => const LocationPermissionService(),
);

enum AppLocationPermissionState {
  serviceDisabled,
  denied,
  permanentlyDenied,
  grantedApproximate,
  grantedPrecise,
}

class LocationPermissionStatus {
  final bool serviceEnabled;
  final LocationPermission permission;
  final LocationAccuracyStatus? accuracyStatus;

  const LocationPermissionStatus({
    required this.serviceEnabled,
    required this.permission,
    required this.accuracyStatus,
  });

  bool get isGranted =>
      permission == LocationPermission.always ||
      permission == LocationPermission.whileInUse;

  bool get isPermanentlyDenied =>
      permission == LocationPermission.deniedForever;

  bool get isPrecise => accuracyStatus == LocationAccuracyStatus.precise;

  AppLocationPermissionState get state {
    if (!serviceEnabled) return AppLocationPermissionState.serviceDisabled;
    if (isPermanentlyDenied) {
      return AppLocationPermissionState.permanentlyDenied;
    }
    if (!isGranted) return AppLocationPermissionState.denied;
    if (isPrecise) return AppLocationPermissionState.grantedPrecise;
    return AppLocationPermissionState.grantedApproximate;
  }
}

class LocationPermissionService {
  const LocationPermissionService();

  Future<LocationPermissionStatus> getStatus() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    final permission = await Geolocator.checkPermission();
    final accuracyStatus = await _readAccuracyStatus(permission);
    return LocationPermissionStatus(
      serviceEnabled: serviceEnabled,
      permission: permission,
      accuracyStatus: accuracyStatus,
    );
  }

  Future<LocationPermissionStatus> requestPermission() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    final accuracyStatus = await _readAccuracyStatus(permission);
    return LocationPermissionStatus(
      serviceEnabled: serviceEnabled,
      permission: permission,
      accuracyStatus: accuracyStatus,
    );
  }

  Future<bool> openLocationSettings() {
    return Geolocator.openLocationSettings();
  }

  Future<bool> openAppSettings() {
    return Geolocator.openAppSettings();
  }

  Future<Position?> getCurrentPosition({
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) async {
    final status = await getStatus();
    if (!status.isGranted || !status.serviceEnabled) {
      return null;
    }
    try {
      return await Geolocator.getCurrentPosition(desiredAccuracy: accuracy);
    } catch (_) {
      try {
        return await Geolocator.getLastKnownPosition();
      } catch (_) {
        return null;
      }
    }
  }

  Future<LocationAccuracyStatus?> _readAccuracyStatus(
    LocationPermission permission,
  ) async {
    if (permission != LocationPermission.always &&
        permission != LocationPermission.whileInUse) {
      return null;
    }
    try {
      return await Geolocator.getLocationAccuracy();
    } catch (_) {
      return null;
    }
  }
}
