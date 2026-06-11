import 'package:maslaki/features/social/models/social_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SocialSearchResults reads nested results payloads', () {
    final results = SocialSearchResults.fromJson({
      'query': 'maslaki',
      'recentSearches': const [
        {'id': 1, 'rawQuery': 'maslaki', 'searchType': 'all'},
      ],
      'results': {
        'users': const [
          {
            'id': 7,
            'username': 'maslaki_test',
            'fullName': 'Maslaki Test',
            'imageUrl': null,
            'role': 'user',
            'relation': {'state': 'none'},
          },
        ],
        'hashtags': const [
          {'id': 3, 'tag': 'maslaki', 'usageCount': 4},
        ],
        'posts': const [
          {
            'id': 11,
            'userId': 7,
            'postKind': 'text',
            'caption': 'Nested payload works',
            'likesCount': 0,
            'commentsCount': 0,
            'savesCount': 0,
            'impressionsCount': 0,
            'reelViewsCount': 0,
            'isLiked': false,
            'isSaved': false,
            'reportCount': 0,
            'author': {
              'id': 7,
              'username': 'maslaki_test',
              'fullName': 'Maslaki Test',
              'role': 'user',
            },
          },
        ],
        'reels': const [],
        'reviews': const [],
        'merchants': const [],
        'suggestedPeople': const [],
      },
    });

    expect(results.recentSearches, hasLength(1));
    expect(results.users, hasLength(1));
    expect(results.users.first.user.username, 'maslaki_test');
    expect(results.hashtags, hasLength(1));
    expect(results.hashtags.first.tag, 'maslaki');
    expect(results.posts, hasLength(1));
    expect(results.posts.first.id, 11);
  });
}
