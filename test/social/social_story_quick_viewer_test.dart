import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/ui/social_story_quick_viewer.dart';
import 'package:social_core/social_core.dart';

void main() {
  testWidgets('story viewer advances across stories and users', (tester) async {
    final groupOne = SocialStoryGroup.fromJson({
      'userId': 11,
      'author': {
        'id': 11,
        'fullName': 'Alpha User',
        'role': 'user',
      },
      'latestAt': '2026-07-14T00:00:00Z',
      'hasUnviewed': true,
      'stories': [
        _storyJson(1, 11, 'Alpha one'),
        _storyJson(2, 11, 'Alpha two'),
      ],
    });
    final groupTwo = SocialStoryGroup.fromJson({
      'userId': 22,
      'author': {
        'id': 22,
        'fullName': 'Beta User',
        'role': 'user',
      },
      'latestAt': '2026-07-14T00:05:00Z',
      'hasUnviewed': true,
      'stories': [
        _storyJson(3, 22, 'Beta one'),
      ],
    });
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: SizedBox.shrink()),
      ),
    );

    final context = tester.element(find.byType(Scaffold));
    unawaited(
      showSocialStoryQuickViewer(
        context: context,
        group: groupOne,
        storyGroups: [groupOne, groupTwo],
        initialStoryId: 1,
      ),
    );

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.text('Alpha User'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Alpha User'), findsOneWidget);

    await tester.drag(find.byType(PageView), const Offset(-500, 0));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Beta User'), findsOneWidget);
    expect(find.text('Beta one'), findsOneWidget);
  });
}

Map<String, dynamic> _storyJson(int id, int userId, String caption) {
  return {
    'id': id,
    'userId': userId,
    'caption': caption,
    'mediaKind': 'image',
    'mediaUrl': null,
    'storyStyle': {
      'version': 1,
      'mode': 'text',
      'background': {
        'type': 'solid',
        'primaryColor': '#112233',
      },
    },
    'isViewed': false,
    'isMine': false,
    'likesCount': 0,
    'commentsCount': 0,
    'isLiked': false,
    'createdAt': '2026-07-14T00:00:00Z',
    'expiresAt': '2026-07-15T00:00:00Z',
  };
}
