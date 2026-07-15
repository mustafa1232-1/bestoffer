import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:maslaki/features/social/ui/social_story_viewer_screen.dart';
import 'package:maslaki/features/social_v3/stories/social_story_viewer_v3.dart';
import 'package:maslaki/l10n/app_localizations.dart';

class _ExactStoryApi extends SocialApi {
  _ExactStoryApi() : super(Dio());

  int exactCalls = 0;
  int listCalls = 0;

  @override
  Future<Map<String, dynamic>> getStoryById(int storyId) async {
    exactCalls += 1;
    return <String, dynamic>{
      'story': <String, dynamic>{
        'id': storyId,
        'userId': 7,
        'caption': 'Exact shared story',
        'mediaUrl': null,
        'mediaKind': null,
        'storyStyle': <String, dynamic>{'backgroundColor': '#1E3A8A'},
        'allowLikes': true,
        'allowPrivateReplies': true,
        'allowComments': true,
        'allowSharing': true,
        'allowReshare': true,
        'isViewed': false,
        'isMine': false,
        'likesCount': 2,
        'commentsCount': 1,
        'isLiked': false,
        'createdAt': '2026-07-15T10:00:00.000Z',
        'expiresAt': '2026-07-16T10:00:00.000Z',
        'author': <String, dynamic>{
          'id': 7,
          'fullName': 'Story Owner',
          'username': 'story.owner',
          'imageUrl': null,
          'role': 'user',
        },
      },
    };
  }

  @override
  Future<Map<String, dynamic>> listStories({
    int limitUsers = 30,
    int maxPerUser = 8,
  }) async {
    listCalls += 1;
    throw StateError('the exact Story screen must not scan the active feed');
  }
}

void main() {
  testWidgets('native Story card destination fetches the exact Story id', (
    tester,
  ) async {
    final api = _ExactStoryApi();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [socialApiProvider.overrideWithValue(api)],
        child: const MaterialApp(
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: SocialStoryViewerScreen(storyId: 42),
        ),
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(api.exactCalls, 1);
    expect(api.listCalls, 0);
    expect(find.byType(SocialStoryViewerV3), findsOneWidget);
  });
}
