import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:maslaki/features/social/ui/widgets/social_feed_controls.dart';
import 'package:maslaki/features/social/ui/widgets/social_stories_strip.dart';
import 'package:maslaki/l10n/app_localizations.dart';

Future<AppLocalizations> _l10n() =>
    AppLocalizations.delegate.load(const Locale('ar'));

Widget _host(Widget child) {
  return MaterialApp(
    locale: const Locale('ar'),
    supportedLocales: AppLocalizations.supportedLocales,
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    home: Scaffold(body: child),
  );
}

void main() {
  testWidgets(
    'guest action strip hides the create affordance',
    (tester) async {
      await tester.pumpWidget(
        _host(
          SocialFeedActionStrip(
            onOpenSearch: () {},
            onOpenCreateMenu: () {},
            showCreate: false,
          ),
        ),
      );
      await tester.pump();

      // Search stays; the create affordance is gone for guests.
      final l10n = await _l10n();
      expect(find.byType(OutlinedButton), findsOneWidget);
      expect(find.text(l10n.socialFeedControlsCreatePostOrStory), findsNothing);
    },
  );

  testWidgets(
    'signed-in action strip keeps the create affordance',
    (tester) async {
      await tester.pumpWidget(
        _host(
          SocialFeedActionStrip(
            onOpenSearch: () {},
            onOpenCreateMenu: () {},
            showCreate: true,
          ),
        ),
      );
      await tester.pump();

      final l10n = await _l10n();
      expect(
        find.text(l10n.socialFeedControlsCreatePostOrStory),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'guest stories strip collapses cleanly when there is nothing to show',
    (tester) async {
      await tester.pumpWidget(
        _host(
          SocialStoriesStrip(
            loading: false,
            stories: const [],
            showAddStory: false,
            onAddStory: () {},
            onOpenStoryGroup: (_) {},
          ),
        ),
      );
      await tester.pump();

      // No "add story" tile and no "no stories yet" label for guests.
      expect(find.byIcon(Icons.add_rounded), findsNothing);
      final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
      expect(find.text(l10n.socialStoriesStripEmpty), findsNothing);
    },
  );

  testWidgets(
    'signed-in stories strip still offers the add-story tile',
    (tester) async {
      await tester.pumpWidget(
        _host(
          SocialStoriesStrip(
            loading: false,
            stories: const [],
            showAddStory: true,
            onAddStory: () {},
            onOpenStoryGroup: (_) {},
          ),
        ),
      );
      await tester.pump();

      expect(find.byIcon(Icons.add_rounded), findsOneWidget);
    },
  );
}
