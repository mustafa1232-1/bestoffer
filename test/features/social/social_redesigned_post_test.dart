import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/models/social_models.dart';
import 'package:maslaki/features/social/ui/widgets/social_post_card_v2.dart';
import 'package:maslaki/features/social/ui/widgets/social_post_action.dart';
import 'package:maslaki/features/social/ui/widgets/social_bottom_navigation.dart';
import 'package:maslaki/features/social/ui/widgets/social_feed_tabs.dart';
import 'package:maslaki/l10n/app_localizations.dart';

SocialPost _post() => SocialPost.fromJson({
  'id': 10,
  'userId': 7,
  'postKind': 'text',
  'caption': List.filled(
    30,
    'A readable caption about our community.',
  ).join(' '),
  'author': {
    'id': 7,
    'fullName': 'A long community display name',
    'username': 'member',
  },
  'likesCount': 1250,
  'commentsCount': 18,
});

Widget _host(Widget child, {String language = 'ar', double scale = 1}) =>
    ProviderScope(
      child: MaterialApp(
        locale: Locale(language),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  testWidgets('author and bounded comment previews render under the post', (
    tester,
  ) async {
    var opened = 0;
    final post = _post().copyWith(
      commentPreview: [
        SocialComment.fromJson({
          'id': 1,
          'postId': 10,
          'body': 'First preview',
          'author': {'id': 2, 'fullName': 'Comment author'},
        }),
        SocialComment.fromJson({
          'id': 2,
          'postId': 10,
          'body': 'Second preview',
          'author': {'id': 3, 'fullName': 'Another author'},
        }),
      ],
    );
    await tester.pumpWidget(
      _host(
        SocialPostCardV2(post: post, onOpenComments: () => opened++),
        language: 'en',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('A long community display name'), findsOneWidget);
    expect(find.byType(CircleAvatar), findsNWidgets(3));
    expect(
      find.textContaining('First preview', findRichText: true),
      findsOneWidget,
    );
    final preview = find.textContaining('Second preview', findRichText: true);
    expect(preview, findsOneWidget);
    await tester.ensureVisible(preview);
    await tester.tap(preview);
    expect(opened, 1);
    expect(tester.takeException(), isNull);
  });

  test(
    'comment preview model excludes deleted comments and caps the payload',
    () {
      final post = SocialPost.fromJson({
        'id': 1,
        'author': {'id': 1},
        'commentPreview': [
          {
            'id': 1,
            'isDeleted': true,
            'author': {'id': 1},
          },
          for (var id = 2; id <= 5; id++)
            {
              'id': id,
              'author': {'id': 1},
            },
        ],
      });
      expect(post.commentPreview.map((c) => c.id), [2, 3]);
      expect(
        post.copyWith(commentsCount: 4).commentPreview,
        post.commentPreview,
      );
    },
  );

  testWidgets(
    'blank display name falls back to handle and caption remains visible',
    (tester) async {
      final post = _post().copyWith(
        author: _post().author.copyWith(fullName: ''),
      );
      await tester.pumpWidget(
        _host(SocialPostCardV2(post: post), language: 'en'),
      );
      await tester.pumpAndSettle();
      expect(find.text('@member'), findsWidgets);
      expect(
        find.textContaining('A readable caption', findRichText: true),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );
  for (final width in [320.0, 360.0, 390.0, 412.0, 430.0, 768.0]) {
    for (final language in ['ar', 'en']) {
      testWidgets('post and navigation fit $width $language at large text', (
        tester,
      ) async {
        await tester.binding.setSurfaceSize(Size(width, 915));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          _host(
            Column(
              children: [
                SocialFeedTabs(selected: 'for_you', onSelected: (_) {}),
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: SocialPostCardV2(
                    post: _post(),
                    onOpenComments: () {},
                    onToggleLike: () async {},
                    onToggleSave: () async {},
                  ),
                ),
                SocialBottomNavigation(
                  index: 0,
                  onSelected: (_) {},
                  messagesUnread: 3,
                ),
              ],
            ),
            language: language,
            scale: 1.6,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(SocialPostAction), findsNWidgets(4));
      });
    }
  }

  testWidgets('like, save, comments and caption expansion stay connected', (
    tester,
  ) async {
    var likes = 0;
    var saves = 0;
    var comments = 0;
    await tester.pumpWidget(
      _host(
        SocialPostCardV2(
          post: _post(),
          onToggleLike: () async => likes++,
          onToggleSave: () async => saves++,
          onOpenComments: () => comments++,
        ),
        language: 'en',
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.favorite_border_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.bookmark_outline_rounded));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.mode_comment_outlined).first);
    expect(likes, 1);
    expect(saves, 1);
    expect(comments, 1);
    await tester.tap(find.text('More'));
    await tester.pumpAndSettle();
    expect(find.text('Show less'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('disabled comments and sharing are visible and inactive', (
    tester,
  ) async {
    var comments = 0;
    await tester.pumpWidget(
      _host(
        SocialPostCardV2(
          post: _post().copyWith(
            storyStyle: const {
              'postSettings': {
                'commentsEnabled': false,
                'sharingEnabled': false,
              },
            },
          ),
          onOpenComments: () => comments++,
        ),
        language: 'en',
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text('Comments and sharing are turned off for this post'),
      findsOneWidget,
    );
    await tester.tap(find.byIcon(Icons.mode_comment_outlined).first);
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.share_outlined));
    await tester.pumpAndSettle();

    expect(comments, 0);
    expect(tester.takeException(), isNull);
  });
}
