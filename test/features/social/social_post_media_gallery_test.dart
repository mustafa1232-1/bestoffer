import 'package:flutter_test/flutter_test.dart';
import 'package:social_core/social_core.dart';

void main() {
  test('SocialPost parses media gallery and resolves first media urls', () {
    final post = SocialPost.fromJson({
      'id': 10,
      'userId': 7,
      'postKind': 'video',
      'audienceScopeType': 'global',
      'caption': 'gallery post',
      'mediaGallery': [
        {
          'id': 101,
          'sortOrder': 0,
          'mediaKind': 'image',
          'mediaUrl': '/uploads/first.jpg',
          'asset': {
            'id': 5001,
            'normalizedUrl': 'https://cdn.example.com/first.jpg',
            'posterUrl': 'https://cdn.example.com/first-poster.jpg',
          },
        },
        {
          'id': 102,
          'sortOrder': 1,
          'mediaKind': 'video',
          'mediaUrl': '/uploads/second.mp4',
          'asset': {
            'id': 5002,
            'normalizedUrl': 'https://cdn.example.com/second.mp4',
            'posterUrl': 'https://cdn.example.com/second-poster.jpg',
          },
        },
      ],
      'author': {'id': 7, 'fullName': 'Tester', 'role': 'user'},
      'likesCount': 0,
      'commentsCount': 0,
      'savesCount': 0,
      'impressionsCount': 0,
      'reelViewsCount': 0,
      'isLiked': false,
      'isSaved': false,
      'reportCount': 0,
    });

    expect(post.mediaGallery, hasLength(2));
    expect(
      post.mediaGallery.first.asset?.posterUrl,
      'https://cdn.example.com/first-poster.jpg',
    );
    expect(
      resolveSocialPostPosterUrl(post),
      'https://cdn.example.com/first-poster.jpg',
    );
    expect(
      resolveSocialPostVideoUrl(post),
      'https://cdn.example.com/first.jpg',
    );
  });
}
