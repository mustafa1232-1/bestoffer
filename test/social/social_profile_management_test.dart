import 'package:maslaki/features/paid_upgrades/models/paid_upgrade_models.dart';
import 'package:maslaki/features/social/models/social_models.dart';
import 'package:maslaki/features/social/ui/social_profile_account_management_screen.dart';
import 'package:maslaki/features/social/ui/social_profile_activity_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/l10n/app_localizations.dart';

SocialUserProfile _profile({required bool isMe}) {
  return SocialUserProfile.fromJson({
    'id': 7,
    'fullName': 'Ali Hassan',
    'role': 'user',
    'isMe': isMe,
    'bio': 'Local creator',
    'workTitle': 'Designer',
    'workCompany': 'Maslaki',
    'imageUrl': null,
    'phone': '07700000000',
    'showPhone': false,
    'postsPublic': true,
    'storiesPublic': false,
    'relationsPublic': true,
    'localContext': 'Basmaya / Block A',
    'badges': ['Premium'],
    'tabs': {'saved': 3, 'tagged': 2, 'insights': true},
    'joinedAt': '2026-01-10T00:00:00.000Z',
    'relation': {
      'state': isMe ? 'accepted' : 'none',
      'canChat': true,
      'canCall': true,
      'canSendRequest': true,
    },
    'stats': {
      'totalPosts': 14,
      'imagePosts': 8,
      'videoPosts': 3,
      'reviewPosts': 2,
      'likesGiven': 9,
      'commentsMade': 5,
      'likesReceived': 22,
      'commentsReceived': 11,
      'activeStories': 1,
      'highlightsCount': 4,
      'connectionsCount': 6,
      'friendsCount': 6,
      'followersCount': 120,
      'followingCount': 48,
      'pendingIncomingCount': 2,
      'pendingOutgoingCount': 1,
    },
  });
}

Widget _wrap(Widget child) {
  return MaterialApp(
    locale: const Locale('en'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: child,
  );
}

void main() {
  testWidgets('Account management screen groups profile privacy and account info',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        SocialProfileAccountManagementScreen(
          profile: _profile(isMe: true),
          paidSummary: PaidUpgradesSummaryModel.fromJson({
            'plans': const [],
            'requests': const [],
            'subscriptions': const [],
            'activeSubscriptions': const [],
            'activePlanCodes': const [],
            'entitlements': const {},
            'premiumBadge': const {'active': false},
          }),
        ),
      ),
    );

    expect(find.text('Account management'), findsOneWidget);
    expect(find.text('Profile and privacy'), findsOneWidget);
    expect(find.text('Account actions'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -500));
    await tester.pumpAndSettle();
    expect(find.text('Account info'), findsOneWidget);
  });

  testWidgets('Activity screen renders secondary metrics and merchant chips',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        SocialProfileActivityScreen(
          profile: _profile(isMe: true),
          favoriteMerchants: const ['Maslaki Cafe', 'Local Market'],
          savedCount: 3,
        ),
      ),
    );

    expect(find.text('Profile activity'), findsOneWidget);
    expect(find.text('Images'), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    await tester.drag(find.byType(ListView), const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(find.text('Maslaki Cafe'), findsOneWidget);
  });
}
