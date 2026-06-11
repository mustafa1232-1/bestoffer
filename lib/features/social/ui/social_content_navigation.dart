import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../customer/ui/customer_car_listing_details_screen.dart';
import '../../real_estate/ui/real_estate_listing_details_screen.dart';
import '../models/social_models.dart';
import 'social_post_details_screen.dart';
import 'social_reel_comments_sheet.dart';
import 'social_reel_viewer_screen.dart';

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

  final reelPosts = (reelContextPosts ?? const <SocialPost>[])
      .where(isSocialVideoPost)
      .toList(growable: false);

  if (reelPosts.isEmpty) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialReelViewerScreen(initialReelId: post.id),
      ),
    );
  }

  return Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SocialReelViewerScreen(initialReelId: post.id),
    ),
  );
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
  if (normalizedType == 'reel') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialReelViewerScreen(initialReelId: entity.id),
      ),
    );
    return;
  }
  if (normalizedType == 'car_listing') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => CustomerCarListingDetailsScreen(listingId: entity.id),
      ),
    );
    return;
  }
  if (normalizedType == 'real_estate_listing') {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RealEstateListingDetailsScreen(listingId: entity.id),
      ),
    );
    return;
  }
  await Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => SocialPostDetailsScreen(postId: entity.id),
    ),
  );
  return;
}
