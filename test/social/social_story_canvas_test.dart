import 'package:maslaki/features/social/models/social_story_document.dart';
import 'package:maslaki/features/social/ui/widgets/social_story_canvas.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'SocialStoryCanvas renders published remote media with text layers',
    (tester) async {
      final draft = SocialStoryDraft.initialText().copyWith(
        mode: SocialStoryComposerMode.media,
        layers: const [
          SocialStoryLayer(
            id: 'headline',
            type: SocialStoryLayerType.text,
            x: 0.5,
            y: 0.8,
            scale: 1,
            rotation: 0,
            zIndex: 10,
            text: 'Overlay after publish',
            color: '#FFFFFF',
            backgroundColor: '#66000000',
            fontFamily: 'system',
            fontWeight: 'bold',
            textAlign: 'center',
            fontScale: 1,
            sticker: null,
            mentionedUserId: null,
            displayLabel: null,
          ),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SocialStoryCanvas(
                draft: draft,
                remoteMediaUrl: 'https://example.com/story.jpg',
                remoteMediaKind: 'image',
              ),
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
      expect(find.text('Overlay after publish'), findsOneWidget);
    },
  );
}
