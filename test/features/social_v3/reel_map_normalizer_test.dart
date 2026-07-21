import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/features/social/models/social_story_document.dart';
import 'package:maslaki/features/social_v3/upload/reel_map_normalizer.dart';

void main() {
  test('normalizeOptionalMap accepts deeply dynamic reel style maps', () {
    final style = normalizeOptionalMap(<dynamic, dynamic>{
      'caption': 'hello',
      1: 'numeric-key',
      'layers': <dynamic>[
        <dynamic, dynamic>{
          'type': 'text',
          2: <dynamic, dynamic>{'nested': true},
        },
      ],
    });

    expect(style?['1'], 'numeric-key');
    final layers = style?['layers'] as List<dynamic>;
    final firstLayer = layers.single as Map<String, dynamic>;
    expect(firstLayer['2'], isA<Map<String, dynamic>>());
  });

  test('draft restored from jsonDecode is normalized before fromJson', () {
    final raw = jsonDecode(
      jsonEncode(<dynamic, dynamic>{
        'draftId': 'draft-1',
        'version': 2,
        'mode': 'media',
        'caption': 'restored',
        'background': <dynamic, dynamic>{
          'type': 'solid',
          'primaryColor': '#000000',
        },
        'layers': <dynamic>[
          <dynamic, dynamic>{
            'id': 'layer-1',
            'type': 'mention',
            'x': 0.5,
            'y': 0.5,
            'scale': 1,
            'rotation': 0,
            'zIndex': 1,
            'text': '@user',
            'mentionedUserId': 44,
          },
        ],
      }),
    );

    final draft = SocialStoryDraft.fromJson(
      normalizeReelMap(raw, 'INVALID_REEL_DRAFT'),
    );

    expect(draft.caption, 'restored');
    expect(draft.layers.single.mentionedUserId, 44);
  });
}
