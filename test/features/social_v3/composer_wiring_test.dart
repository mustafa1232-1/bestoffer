import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dio/dio.dart';
import 'package:maslaki/features/social/data/social_api.dart';
import 'package:maslaki/features/social/state/social_controller.dart';
import 'package:maslaki/features/social_v3/reels/social_reels_screen_v3.dart';
import 'package:maslaki/features/social_v3/sharing/share_sheet_v3.dart';

import 'reels_v3_fixtures.dart';

class _FakeSocialApi extends SocialApi {
  _FakeSocialApi() : super(Dio());

  @override
  Future<Map<String, dynamic>> getUserRelation(int userId) async {
    return <String, dynamic>{
      'relation': <String, dynamic>{'state': 'none'},
    };
  }
}

void main() {
  testWidgets('Reels screen exposes a create control that fires onCreate',
      (tester) async {
    var created = false;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          socialApiProvider.overrideWithValue(_FakeSocialApi()),
        ],
        child: MediaQuery(
          data: const MediaQueryData(size: Size(393, 852)),
          child: MaterialApp(
            home: SocialReelsScreenV3(
              reels: fakeReels(1),
              coordinatorFactory: fakeCoordinator,
              onCreate: () => created = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final createIcon = find.byIcon(Icons.videocam_rounded);
    expect(createIcon, findsOneWidget);
    await tester.tap(createIcon);
    // Let the page's double-tap recognizer time out so the single-tap wins.
    await tester.pump(const Duration(milliseconds: 400));
    expect(created, isTrue);
  });

  testWidgets('Share sheet Add-to-Story fires its callback', (tester) async {
    var addToStory = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShareSheetV3(
            target: const ShareTargetV3(
              kind: ShareEntityKind.reel,
              entityId: 5,
              ownerId: 7,
              title: 'x',
            ),
            onAddToStory: () => addToStory = true,
          ),
        ),
      ),
    );
    await tester.tap(find.text('إضافة إلى القصة'));
    expect(addToStory, isTrue);
  });
}
