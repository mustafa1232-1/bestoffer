import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../customer/ui/customer_car_listing_details_screen.dart';
import '../../real_estate/ui/real_estate_listing_details_screen.dart';
import '../../social_v3/state/social_reels_v3_connector.dart';
import '../models/social_models.dart';
import 'social_post_details_screen.dart';
import 'social_profile_screen.dart';
import 'social_reel_comments_sheet.dart';
import 'social_story_viewer_screen.dart';

/// Opens the full-screen Social V3 reels experience pinned to [reelId].
Future<void> openSocialReelsV3(BuildContext context, {required int reelId}) {
  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SocialReelsV3Connector(initialReelId: reelId),
    ),
  );
}

@immutable
class SocialSharedEntityRouteTarget {
  final String kind;
  final int id;
  final String? initialName;

  const SocialSharedEntityRouteTarget._({
    required this.kind,
    required this.id,
    this.initialName,
  });

  const SocialSharedEntityRouteTarget.reel(int reelId)
    : this._(kind: 'reel', id: reelId);

  const SocialSharedEntityRouteTarget.story(int storyId)
    : this._(kind: 'story', id: storyId);

  const SocialSharedEntityRouteTarget.post(int postId)
    : this._(kind: 'post', id: postId);

  const SocialSharedEntityRouteTarget.profile(int userId, {String? initialName})
    : this._(kind: 'profile', id: userId, initialName: initialName);

  const SocialSharedEntityRouteTarget.carListing(int listingId)
    : this._(kind: 'car_listing', id: listingId);

  const SocialSharedEntityRouteTarget.realEstateListing(int listingId)
    : this._(kind: 'real_estate_listing', id: listingId);
}

@visibleForTesting
SocialSharedEntityRouteTarget? buildSocialSharedEntityRouteTarget(
  SocialSharedEntity entity,
) {
  final normalizedType = entity.type.trim().toLowerCase();
  switch (normalizedType) {
    case 'story':
      return SocialSharedEntityRouteTarget.story(entity.id);
    case 'reel':
      return SocialSharedEntityRouteTarget.reel(entity.id);
    case 'profile':
    case 'user':
      return SocialSharedEntityRouteTarget.profile(
        entity.id,
        initialName: entity.authorDisplayName ?? entity.title,
      );
    case 'car_listing':
      return SocialSharedEntityRouteTarget.carListing(entity.id);
    case 'real_estate_listing':
      return SocialSharedEntityRouteTarget.realEstateListing(entity.id);
    case 'review':
    case 'merchant_review':
    case 'post':
      return SocialSharedEntityRouteTarget.post(entity.id);
    default:
      return SocialSharedEntityRouteTarget.post(entity.id);
  }
}

Future<void> openSocialContent(
  BuildContext context, {
  required SocialPost post,
  List<SocialPost>? reelContextPosts,
}) {
  if (!isSocialVideoPost(post)) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialPostDetailsScreen(initialPost: post),
      ),
    );
  }

  return openSocialReelsV3(context, reelId: post.id);
}

Future<int?> openSocialComments(
  BuildContext context, {
  required SocialPost post,
  String? title,
}) {
  if (isSocialVideoPost(post)) {
    return showSocialReelCommentsSheet(context, reelPost: post);
  }
  return showSocialPostCommentsSheet(context, post: post, title: title);
}

Future<void> openSocialSharedEntity(
  BuildContext context, {
  required SocialSharedEntity entity,
}) async {
  final normalizedType = entity.type.trim().toLowerCase();
  if (normalizedType == 'location') {
    final lat = entity.latitude;
    final lng = entity.longitude;
    if (lat != null && lng != null) {
      final uri = Uri.parse(
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng',
      );
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return;
  }
  final target = buildSocialSharedEntityRouteTarget(entity);
  if (target == null) return;
  switch (target.kind) {
    case 'story':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SocialStoryViewerScreen(storyId: target.id),
        ),
      );
      return;
    case 'reel':
      await openSocialReelsV3(context, reelId: target.id);
      return;
    case 'profile':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SocialProfileScreen(
            userId: target.id,
            initialName: target.initialName,
          ),
        ),
      );
      return;
    case 'car_listing':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CustomerCarListingDetailsScreen(listingId: target.id),
        ),
      );
      return;
    case 'real_estate_listing':
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RealEstateListingDetailsScreen(listingId: target.id),
        ),
      );
      return;
    case 'post':
    default:
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => SocialPostDetailsScreen(postId: target.id),
        ),
      );
      return;
  }
}
