import 'package:flutter/foundation.dart';

class SecureNetworkingConfig {
  const SecureNetworkingConfig({
    required this.mode,
    required this.pinHosts,
    required this.spkiPins,
    required this.pinSetLabel,
  });

  final String mode;
  final Set<String> pinHosts;
  final Set<String> spkiPins;
  final String pinSetLabel;

  static SecureNetworkingConfig current() {
    return fromEnvironment(
      mode: const String.fromEnvironment(
        'TLS_PINNING_MODE',
        defaultValue: 'auto',
      ),
      pinHostsRaw: const String.fromEnvironment('TLS_PINNING_HOSTS'),
      spkiPinsRaw: const String.fromEnvironment('TLS_SPKI_PINS'),
      pinSetLabel: const String.fromEnvironment(
        'TLS_PIN_SET_LABEL',
        defaultValue: 'default',
      ),
      releaseMode: kReleaseMode,
    );
  }

  static SecureNetworkingConfig fromEnvironment({
    required String mode,
    required String pinHostsRaw,
    required String spkiPinsRaw,
    required String pinSetLabel,
    required bool releaseMode,
  }) {
    final normalizedMode = mode.trim().toLowerCase();
    final hosts = pinHostsRaw
        .split(',')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.isNotEmpty)
        .toSet();
    final pins = spkiPinsRaw
        .split(',')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .map((value) => value.replaceFirst(RegExp(r'^sha256/'), ''))
        .toSet();

    final effectiveMode = switch (normalizedMode) {
      'off' => 'off',
      'always' => 'always',
      _ => releaseMode ? 'always' : 'off',
    };

    return SecureNetworkingConfig(
      mode: effectiveMode,
      pinHosts: hosts,
      spkiPins: pins,
      pinSetLabel: pinSetLabel.trim().isEmpty ? 'default' : pinSetLabel.trim(),
    );
  }

  bool get pinningEnabled =>
      mode == 'always' && pinHosts.isNotEmpty && spkiPins.isNotEmpty;

  bool shouldPinHost(String host) {
    final normalized = host.trim().toLowerCase();
    if (!pinningEnabled || normalized.isEmpty) return false;
    for (final pattern in pinHosts) {
      if (normalized == pattern || normalized.endsWith('.$pattern')) {
        return true;
      }
    }
    return false;
  }
}
