import 'package:maslaki/features/social/ui/widgets/social_mention_hashtag_text.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('SocialMentionHashtagText renders and handles hashtags and mentions', (
    tester,
  ) async {
    String? openedTag;
    int? openedUserId;
    String? openedUserName;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SocialMentionHashtagText(
            text: 'اهلا #بسماية و @[Ali](42)',
            onOpenHashtag: (tag) => openedTag = tag,
            onOpenMention: (userId, displayName) {
              openedUserId = userId;
              openedUserName = displayName;
            },
          ),
        ),
      ),
    );

    expect(find.textContaining('#بسماية'), findsOneWidget);
    expect(find.textContaining('@Ali'), findsOneWidget);

    final richText = tester.widget<RichText>(find.byType(RichText));
    final rootSpan = richText.text as TextSpan;
    final children = <TextSpan>[];

    void collect(TextSpan span) {
      children.add(span);
      final nested = span.children;
      if (nested == null) return;
      for (final child in nested.whereType<TextSpan>()) {
        collect(child);
      }
    }

    collect(rootSpan);
    final hashtagSpan = children.firstWhere((span) => span.text == '#بسماية');
    final mentionSpan = children.firstWhere((span) => span.text == '@Ali');

    (hashtagSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(openedTag, 'بسماية');

    (mentionSpan.recognizer as TapGestureRecognizer).onTap!();
    expect(openedUserId, 42);
    expect(openedUserName, 'Ali');
  });
}
