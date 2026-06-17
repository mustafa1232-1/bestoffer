import 'dart:convert';
import 'dart:typed_data';

import 'package:asn1lib/asn1lib.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';

import 'secure_networking_config.dart';

void configureSecureHttpAdapter(
  Dio dio,
  SecureNetworkingConfig config,
) {
  if (!config.pinningEnabled) return;
  dio.httpClientAdapter = IOHttpClientAdapter(
    validateCertificate: (certificate, host, port) {
      if (!config.shouldPinHost(host)) return true;
      final spkiPin = _extractSpkiPin(certificate);
      return spkiPin != null && config.spkiPins.contains(spkiPin);
    },
  );
}

String? _extractSpkiPin(dynamic certificate) {
  final der = certificate?.der;
  if (der is! List<int> || der.isEmpty) return null;
  try {
    final parser = ASN1Parser(Uint8List.fromList(der));
    final root = parser.nextObject();
    if (root is! ASN1Sequence || root.elements.isEmpty) {
      return null;
    }
    final tbsCertificate = root.elements.first;
    if (tbsCertificate is! ASN1Sequence || tbsCertificate.elements.isEmpty) {
      return null;
    }
    final tbsElements = tbsCertificate.elements;
    final hasExplicitVersion =
        tbsElements.isNotEmpty && (tbsElements.first.tag & 0xA0) == 0xA0;
    final spkiIndex = hasExplicitVersion ? 6 : 5;
    if (tbsElements.length <= spkiIndex) return null;
    final subjectPublicKeyInfo = tbsElements[spkiIndex];
    final encoded = subjectPublicKeyInfo.encodedBytes;
    if (encoded.isEmpty) return null;
    return base64Encode(sha256.convert(encoded).bytes).replaceAll('=', '');
  } catch (_) {
    return null;
  }
}
