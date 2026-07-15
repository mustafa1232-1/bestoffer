import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/ui/social_content_navigation.dart';
import 'package:maslaki/features/social_v3/sharing/canonical_links.dart';
import 'package:maslaki/features/social_v3/sharing/share_sheet_v3.dart';
import 'package:social_core/social_models.dart';

void main() {
  group('canonical links never leak internal URLs (§9/§11)', () {
    const links = SocialCanonicalLinks();

    test('reel/post/story links are canonical app URLs', () {
      expect(links.reel(12), 'https://maslaki.app/r/12');
      expect(links.post(3), 'https://maslaki.app/p/3');
      expect(links.story(7, 9), 'https://maslaki.app/s/7/9');
    });

    test('isSafeShareUrl rejects HLS / R2 / upload / api URLs', () {
      expect(
        isSafeShareUrl('https://videodelivery.net/uid/manifest/video.m3u8'),
        isFalse,
      );
      expect(isSafeShareUrl('https://x/v.m3u8'), isFalse);
      expect(
        isSafeShareUrl('https://bucket.r2.cloudflarestorage.com/key'),
        isFalse,
      );
      expect(
        isSafeShareUrl('https://upload.videodelivery.net/tus/abc'),
        isFalse,
      );
      expect(
        isSafeShareUrl(
          'https://bestoffer-production.up.railway.app/api/feed/reels/1',
        ),
        isFalse,
      );
      expect(isSafeShareUrl('https://x/clip.mp4'), isFalse);
    });

    test('isSafeShareUrl accepts a canonical app URL', () {
      expect(isSafeShareUrl('https://maslaki.app/r/12'), isTrue);
    });

    test('guardShareUrl returns the canonical url', () {
      expect(
        links.guardShareUrl('https://maslaki.app/r/5'),
        'https://maslaki.app/r/5',
      );
    });
  });

  group('ShareSheetV3', () {
    testWidgets('lists options in the required order and external-shares the '
        'canonical URL only', (tester) async {
      String? externallyShared;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ShareSheetV3(
              target: const ShareTargetV3(
                kind: ShareEntityKind.reel,
                entityId: 42,
                ownerId: 7,
                title: 'jacki',
              ),
              onExternalShare: (url) => externallyShared = url,
            ),
          ),
        ),
      );
      expect(find.text('إضافة إلى القصة'), findsOneWidget);
      expect(find.text('نسخ الرابط'), findsOneWidget);
      expect(find.text('مشاركة خارجية'), findsOneWidget);

      await tester.tap(find.text('مشاركة خارجية'));
      await tester.pump();
      expect(externallyShared, 'https://maslaki.app/r/42');
      // Never a manifest / storage / api url.
      expect(isSafeShareUrl(externallyShared!), isTrue);
    });
  });

  group('typed shared entity routing', () {
    test(
      'story/profile/user routes resolve to the exact navigation target',
      () {
        final story = SocialSharedEntity.fromJson({
          'type': 'story',
          'id': 55,
          'snapshot': {
            'title': 'Night view',
            'authorName': 'Lina',
            'authorUsername': 'lina.profile',
          },
        });
        final profile = SocialSharedEntity.fromJson({
          'type': 'profile',
          'id': 77,
          'snapshot': {'authorName': 'Mina', 'authorUsername': 'mina.user'},
        });
        final review = SocialSharedEntity.fromJson({
          'type': 'merchant_review',
          'id': 99,
          'snapshot': {'title': 'Great store'},
        });

        final storyTarget = buildSocialSharedEntityRouteTarget(story);
        final profileTarget = buildSocialSharedEntityRouteTarget(profile);
        final reviewTarget = buildSocialSharedEntityRouteTarget(review);

        expect(storyTarget?.kind, 'story');
        expect(storyTarget?.id, 55);
        expect(profileTarget?.kind, 'profile');
        expect(profileTarget?.id, 77);
        expect(profileTarget?.initialName, 'Mina');
        expect(reviewTarget?.kind, 'post');
        expect(reviewTarget?.id, 99);
      },
    );

    test('shared entity preview labels cover story/profile/review aliases', () {
      expect(
        SocialSharedEntity.fromJson({'type': 'story', 'id': 1}).previewLabel,
        'ستوري مشارك',
      );
      expect(
        SocialSharedEntity.fromJson({'type': 'profile', 'id': 2}).previewLabel,
        'ملف شخصي',
      );
      expect(
        SocialSharedEntity.fromJson({
          'type': 'merchant_review',
          'id': 3,
        }).previewLabel,
        'مراجعة مشاركة',
      );
    });

    test(
      'post and reel cards parse nested author metadata without duplicate captions',
      () {
        final post = SocialSharedEntity.fromJson({
          'type': 'post',
          'id': 11,
          'snapshot': {
            'caption': 'Only one caption',
            'posterUrl': 'https://cdn.test/post.jpg',
            'author': {
              'fullName': 'Nested Author',
              'username': '@nested.author',
              'imageUrl': 'https://cdn.test/avatar.jpg',
            },
          },
        });

        expect(post.title, post.previewLabel);
        expect(post.subtitle, 'Only one caption');
        expect(post.authorDisplayName, 'Nested Author');
        expect(post.authorUsername, 'nested.author');
        expect(post.authorAvatarUrl, 'https://cdn.test/avatar.jpg');
        expect(post.imageUrl, 'https://cdn.test/post.jpg');
        expect(post.title, isNot(post.subtitle));
      },
    );
  });
}
