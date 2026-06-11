import 'package:maslaki/features/social/models/social_models.dart';
import 'package:maslaki/features/social/ui/widgets/social_mention_composer_field.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('SocialMentionComposerController serializes inserted mentions to markup', () {
    final controller = SocialMentionComposerController(text: '@ma');

    controller.insertMention(
      start: 0,
      end: 3,
      author: const SocialAuthor(
        id: 42,
        username: 'maslaki.user',
        fullName: 'Maslaki User',
        imageUrl: null,
        phone: null,
        role: 'user',
      ),
    );

    expect(controller.plainText, '@maslaki.user ');
    expect(
      controller.buildMarkedText(),
      '@[maslaki.user](42) ',
    );

    controller.dispose();
  });

  test('SocialMentionComposerController drops broken mappings after editing mention text', () {
    final controller = SocialMentionComposerController(text: '');
    controller.insertMention(
      start: 0,
      end: 0,
      author: const SocialAuthor(
        id: 7,
        username: 'ali.saleh',
        fullName: 'Ali Saleh',
        imageUrl: null,
        phone: null,
        role: 'user',
      ),
    );

    controller.textController.text = '@ali friend';
    controller.handleExternalTextChange();

    expect(controller.buildMarkedText(), '@ali friend');
    controller.dispose();
  });
}
