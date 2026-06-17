import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/network/request_signing.dart';

void main() {
  group('request signing helpers', () {
    test('normalizePathForSigning collapses api v1 paths', () {
      expect(
        normalizePathForSigning('/api/v1/merchant/payment-requests?foo=1'),
        '/api/merchant/payment-requests',
      );
      expect(normalizePathForSigning('/api/v1'), '/api');
    });

    test('requiresRequestSigning matches sensitive routes on api and api v1', () {
      expect(
        requiresRequestSigning(
          method: 'POST',
          path: '/api/owner/settlements/request',
        ),
        isTrue,
      );
      expect(
        requiresRequestSigning(
          method: 'POST',
          path: '/api/v1/owner/settlements/request',
        ),
        isTrue,
      );
      expect(
        requiresRequestSigning(
          method: 'GET',
          path: '/api/owner/settlements/request',
        ),
        isFalse,
      );
    });

    test('stableJsonEncode and body hash stay stable across map order', () {
      final left = <String, Object?>{
        'b': 2,
        'a': <String, Object?>{'y': true, 'x': 1},
      };
      final right = <String, Object?>{
        'a': <String, Object?>{'x': 1, 'y': true},
        'b': 2,
      };

      expect(stableJsonEncode(left), stableJsonEncode(right));
      expect(buildRequestBodyHash(left), buildRequestBodyHash(right));
    });

    test('buildRequestSignature is deterministic for canonical payload', () {
      const secret = 'secret-value';
      final canonical = buildRequestSigningCanonical(
        method: 'POST',
        path: '/api/v1/owner/settlements/request?foo=1',
        timestamp: '1710000000000',
        nonce: 'nonce-1',
        sessionId: '17',
        deviceFingerprint: 'device-hash',
        bodyHash: buildRequestBodyHash(<String, Object?>{'amount': 5000}),
      );

      expect(
        canonical,
        'POST\n'
        '/api/owner/settlements/request\n'
        '1710000000000\n'
        'nonce-1\n'
        '17\n'
        'device-hash\n'
        '${buildRequestBodyHash(<String, Object?>{'amount': 5000})}',
      );
      expect(
        buildRequestSignature(secret: secret, canonical: canonical),
        buildRequestSignature(secret: secret, canonical: canonical),
      );
    });
  });
}
