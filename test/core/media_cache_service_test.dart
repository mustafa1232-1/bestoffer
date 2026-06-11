import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/core/media/media_cache_models.dart';
import 'package:maslaki/core/media/media_cache_service.dart';

void main() {
  group('MediaCacheService keying', () {
    test('public keys are deterministic for same identity/version', () {
      final first = MediaCacheService.computeKey(
        const MediaCacheKeyInput(
          url: 'https://cdn.example.com/a.png?token=abc',
          stableId: 'media-1',
          version: '2026-05-08T10:00:00Z',
          scope: MediaCacheScope.public,
        ),
      );
      final second = MediaCacheService.computeKey(
        const MediaCacheKeyInput(
          url: 'https://cdn.example.com/a.png?token=xyz',
          stableId: 'media-1',
          version: '2026-05-08T10:00:00Z',
          scope: MediaCacheScope.public,
        ),
      );

      expect(first, equals(second));
      expect(first.startsWith('pub_'), isTrue);
    });

    test('private keys are isolated per user', () {
      final user1 = MediaCacheService.computeKey(
        const MediaCacheKeyInput(
          url: 'https://cdn.example.com/private.jpg',
          stableId: 'private-asset',
          version: 'v1',
          scope: MediaCacheScope.userPrivate,
          userId: 101,
        ),
      );
      final user2 = MediaCacheService.computeKey(
        const MediaCacheKeyInput(
          url: 'https://cdn.example.com/private.jpg',
          stableId: 'private-asset',
          version: 'v1',
          scope: MediaCacheScope.userPrivate,
          userId: 202,
        ),
      );

      expect(user1, isNot(equals(user2)));
      expect(user1.startsWith('u101_'), isTrue);
      expect(user2.startsWith('u202_'), isTrue);
    });

    test('key does not leak raw url or token text', () {
      const rawUrl =
          'https://cdn.example.com/file.png?token=very-secret-signature';
      final key = MediaCacheService.computeKey(
        const MediaCacheKeyInput(url: rawUrl, scope: MediaCacheScope.public),
      );

      expect(key.contains('token'), isFalse);
      expect(key.contains('very-secret-signature'), isFalse);
      expect(key.contains('cdn.example.com'), isFalse);
    });
  });
}
