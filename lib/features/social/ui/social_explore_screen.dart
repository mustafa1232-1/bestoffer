// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import '../state/social_explore_controller.dart';
import 'social_content_navigation.dart';
import 'social_discovery_people_screen.dart';
import 'social_hashtag_screen.dart';
import 'social_profile_screen.dart';
import 'social_reel_viewer_screen.dart';
import 'social_search_screen.dart';
import 'widgets/social_post_card_v2.dart';
import 'widgets/social_save_sheet.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialExploreScreen extends ConsumerStatefulWidget {
  const SocialExploreScreen({super.key});

  @override
  ConsumerState<SocialExploreScreen> createState() =>
      _SocialExploreScreenState();
}

class _SocialExploreScreenState extends ConsumerState<SocialExploreScreen> {
  final Set<int> _busySuggestedUserIds = <int>{};

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref
          .read(socialExploreControllerProvider.notifier)
          .load(refresh: true),
    );
  }

  Future<void> _toggleLike(SocialPost post) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'الإعجاب بالمنشور',
      featureEnglish: 'liking a post',
    )) {
      return;
    }
    final out = await ref.read(socialApiProvider).toggleLike(post.id);
    ref
        .read(socialExploreControllerProvider.notifier)
        .patchPost(
          post.copyWith(
            likesCount: int.tryParse('${out['likesCount']}') ?? post.likesCount,
            isLiked: out['isLiked'] == true,
          ),
        );
  }

  Future<void> _toggleSave(SocialPost post) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'حفظ المنشور',
      featureEnglish: 'saving a post',
    )) {
      return;
    }
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SocialSaveSheet(
        entityType: post.postKind == 'reel'
            ? 'reel'
            : post.postKind == 'merchant_review'
            ? 'review'
            : 'post',
        entityId: post.id,
        initiallySaved: post.isSaved,
      ),
    );
    if (saved == null) return;
    ref
        .read(socialExploreControllerProvider.notifier)
        .patchPost(
          post.copyWith(
            isSaved: saved,
            savesCount: saved
                ? post.savesCount + (post.isSaved ? 0 : 1)
                : (post.savesCount - (post.isSaved ? 1 : 0)).clamp(0, 1 << 30),
          ),
        );
  }

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message, textDirection: context.appTextDirection),
        ),
      );
  }

  void _openMerchant(SocialPost post) {
    final merchantId = post.contentLink?.merchantId ?? post.merchantId;
    if (merchantId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantProductsScreen(
          merchant: MerchantModel(
            id: merchantId,
            name: post.merchantName ?? context.l10n.commonStore,
            type: post.merchantType ?? 'market',
            imageUrl: post.merchantImageUrl,
            isOpen: true,
            hasDiscountOffer: false,
            hasFreeDeliveryOffer: false,
          ),
        ),
      ),
    );
  }

  String _relationButtonLabel(SocialRelation relation) {
    if (relation.isBlocked) return context.l10n.socialExploreBlocked;
    if (relation.isAccepted) return context.l10n.socialExploreFollowing;
    if (relation.isPendingOutgoing) {
      return context.l10n.socialExploreCancelRequest;
    }
    if (relation.isPendingIncoming) return context.l10n.socialExploreAccept;
    return context.l10n.socialExploreFollow;
  }

  Future<void> _onSuggestedRelationPressed(
    SocialUserSearchResult person,
  ) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'إرسال طلب متابعة',
      featureEnglish: 'sending a follow request',
    )) {
      return;
    }
    if (!mounted) return;
    if (_busySuggestedUserIds.contains(person.user.id) ||
        person.relation.isAccepted) {
      return;
    }
    if (person.relation.isBlockedByOther) {
      _snack(context.l10n.socialExploreBlockedByOther);
      return;
    }
    if (person.relation.isBlockedByMe) {
      _snack(context.l10n.socialExploreUnblockFirst);
      return;
    }

    setState(() => _busySuggestedUserIds.add(person.user.id));
    final l10n = context.l10n;
    try {
      final api = ref.read(socialApiProvider);
      late final Map<String, dynamic> out;
      late final String successMessage;
      if (person.relation.isPendingIncoming) {
        out = await api.acceptRelationRequest(person.user.id);
        successMessage = l10n.socialExploreFollowRequestAccepted;
      } else if (person.relation.isPendingOutgoing) {
        out = await api.cancelRelationRequest(person.user.id);
        successMessage = l10n.socialExploreRequestCancelled;
      } else {
        out = await api.sendRelationRequest(person.user.id);
        successMessage = l10n.socialExploreFollowRequestSent;
      }
      final rawRelation = out['relation'];
      if (rawRelation is Map) {
        ref
            .read(socialExploreControllerProvider.notifier)
            .patchSuggestedRelation(
              person.user.id,
              SocialRelation.fromJson(Map<String, dynamic>.from(rawRelation)),
            );
      }
      _snack(successMessage);
    } catch (error) {
      _snack(mapAnyError(error, fallback: l10n.socialExploreActionFailed));
    } finally {
      if (mounted) {
        setState(() => _busySuggestedUserIds.remove(person.user.id));
      }
    }
  }

  void _openProfile(SocialAuthor user) {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            SocialProfileScreen(userId: user.id, initialName: user.fullName),
      ),
    );
  }

  void _openReels(List<SocialPost> reels, {int initialIndex = 0}) {
    if (reels.isEmpty) return;
    final safeIndex = initialIndex.clamp(0, reels.length - 1);
    final target = reels[safeIndex];
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialReelViewerScreen(initialReelId: target.id),
      ),
    );
  }

  List<Widget> _buildPostSection(
    BuildContext context, {
    required String title,
    required List<SocialPost> posts,
    required List<SocialPost> sourcePosts,
    String? subtitle,
  }) {
    if (posts.isEmpty) return const <Widget>[];
    return <Widget>[
      _SectionTitle(title: title, subtitle: subtitle),
      const SizedBox(height: 8),
      ...posts.map(
        (post) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: SocialPostCardV2(
            post: post,
            onOpenDetails: () => openSocialContent(
              context,
              post: post,
              reelContextPosts: sourcePosts,
            ),
            onOpenProfile: () => _openProfile(post.author),
            onOpenMerchantLink: () => _openMerchant(post),
            onToggleLike: () => _toggleLike(post),
            onToggleSave: () => _toggleSave(post),
            onOpenComments: () => openSocialComments(context, post: post),
          ),
        ),
      ),
      const SizedBox(height: 6),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(socialExploreControllerProvider);
    final payload = state.payload;
    final trendingTags = state.trendingHashtags;
    final localTopics =
        payload?.localTopics
            .map((topic) => topic.trim())
            .where((topic) => topic.isNotEmpty)
            .toList(growable: false) ??
        const <String>[];
    final nearYouPosts = payload?.sameArea ?? const <SocialPost>[];
    final popularPosts = payload?.popularPosts.isNotEmpty == true
        ? payload!.popularPosts
        : payload?.trendingBasmaya ?? const <SocialPost>[];
    final reviewPicks = payload?.restaurantReviews ?? const <SocialPost>[];

    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.socialExploreTitle),
          actions: [
            IconButton(
              icon: const Icon(Icons.search_rounded),
              tooltip: context.l10n.socialExploreSearchTooltip,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SocialSearchScreen(),
                  ),
                );
              },
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: () => ref
              .read(socialExploreControllerProvider.notifier)
              .load(refresh: true),
          child: state.loading && payload == null
              ? ListView(
                  children: const [
                    SizedBox(height: 220),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : payload == null
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
                  children: [
                    Icon(
                      Icons.travel_explore_outlined,
                      size: 54,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      state.error?.trim().isNotEmpty == true
                          ? state.error!
                          : context.l10n.socialExploreLoadFailed,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: () => ref
                          .read(socialExploreControllerProvider.notifier)
                          .load(refresh: true),
                      child: Text(context.l10n.socialExploreRetry),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  children: [
                    _ExploreHeroCard(
                      title: context.l10n.socialExploreHeroTitle,
                      subtitle: context.l10n.socialExploreHeroSubtitle,
                      onTap: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const SocialSearchScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 18),
                    _SectionTitle(
                      title: context.l10n.socialExploreSuggestedPeople,
                      trailingLabel: payload.suggestedPeople.isNotEmpty
                          ? context.l10n.socialExploreSeeAll
                          : null,
                      onTrailingTap: payload.suggestedPeople.isNotEmpty
                          ? () {
                              Navigator.of(context).push(
                                MaterialPageRoute<void>(
                                  builder: (_) => SocialDiscoveryPeopleScreen(
                                    people: payload.suggestedPeople,
                                  ),
                                ),
                              );
                            }
                          : null,
                    ),
                    const SizedBox(height: 10),
                    if (payload.suggestedPeople.isEmpty)
                      _SimpleExploreEmptyState(
                        icon: Icons.person_search_outlined,
                        message: context.l10n.socialExploreSuggestedPeopleEmpty,
                      )
                    else
                      SizedBox(
                        height: 206,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: payload.suggestedPeople.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 10),
                          itemBuilder: (_, index) {
                            final person = payload.suggestedPeople[index];
                            return _SuggestedPersonCard(
                              person: person,
                              busy: _busySuggestedUserIds.contains(
                                person.user.id,
                              ),
                              buttonLabel: _relationButtonLabel(
                                person.relation,
                              ),
                              onTap: () => _openProfile(person.user),
                              onAction:
                                  person.relation.isBlocked ||
                                      person.relation.isAccepted
                                  ? null
                                  : () => _onSuggestedRelationPressed(person),
                            );
                          },
                        ),
                      ),
                    const SizedBox(height: 18),
                    if (trendingTags.isNotEmpty || localTopics.isNotEmpty) ...[
                      _SectionTitle(
                        title: context.l10n.socialExploreTrendingTopics,
                        subtitle:
                            context.l10n.socialExploreTrendingTopicsSubtitle,
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ...trendingTags
                              .take(8)
                              .map(
                                (tag) => ActionChip(
                                  label: Text('#${tag.tag}'),
                                  onPressed: () {
                                    Navigator.of(context).push(
                                      MaterialPageRoute<void>(
                                        builder: (_) =>
                                            SocialHashtagScreen(tag: tag.tag),
                                      ),
                                    );
                                  },
                                ),
                              ),
                          ...localTopics.take(6).map((topic) {
                            final cleanTag = topic.startsWith('#')
                                ? topic.substring(1)
                                : topic;
                            return ActionChip(
                              label: Text(
                                topic.startsWith('#') ? topic : '#$topic',
                              ),
                              onPressed: () {
                                Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) =>
                                        SocialHashtagScreen(tag: cleanTag),
                                  ),
                                );
                              },
                            );
                          }),
                        ],
                      ),
                      const SizedBox(height: 18),
                    ],
                    if (payload.reels.isNotEmpty) ...[
                      _SectionTitle(
                        title: context.l10n.socialExploreBasmayaReels,
                        trailingLabel: context.l10n.socialExploreOpenReels,
                        onTrailingTap: () => _openReels(payload.reels),
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 260,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: payload.reels.length,
                          separatorBuilder: (_, index) =>
                              const SizedBox(width: 12),
                          itemBuilder: (_, index) => _ReelPreviewCard(
                            reel: payload.reels[index],
                            onTap: () =>
                                _openReels(payload.reels, initialIndex: index),
                          ),
                        ),
                      ),
                      const SizedBox(height: 18),
                    ],
                    ..._buildPostSection(
                      context,
                      title: context.l10n.socialExploreNearYou,
                      subtitle: context.l10n.socialExploreNearYouSubtitle,
                      posts: nearYouPosts.take(2).toList(growable: false),
                      sourcePosts: nearYouPosts,
                    ),
                    ..._buildPostSection(
                      context,
                      title: context.l10n.socialExplorePopularNow,
                      subtitle: context.l10n.socialExplorePopularNowSubtitle,
                      posts: popularPosts.take(2).toList(growable: false),
                      sourcePosts: popularPosts,
                    ),
                    ..._buildPostSection(
                      context,
                      title: context.l10n.socialExploreLocalReviews,
                      subtitle: context.l10n.socialExploreLocalReviewsSubtitle,
                      posts: reviewPicks.take(2).toList(growable: false),
                      sourcePosts: reviewPicks,
                    ),
                    ..._buildPostSection(
                      context,
                      title: context.l10n.socialExploreForYou,
                      posts: payload.forYou.take(4).toList(growable: false),
                      sourcePosts: payload.forYou,
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class _ExploreHeroCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ExploreHeroCard({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(22),
      onTap: onTap,
      child: Ink(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: const LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [Color(0xFF21406D), Color(0xFF0E6C74)],
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: Colors.white, height: 1.35),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? trailingLabel;
  final VoidCallback? onTrailingTap;

  const _SectionTitle({
    required this.title,
    this.subtitle,
    this.trailingLabel,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
              ),
              if (subtitle != null && subtitle!.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  subtitle!,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
        if (trailingLabel != null && onTrailingTap != null)
          TextButton(onPressed: onTrailingTap, child: Text(trailingLabel!)),
      ],
    );
  }
}

class _SuggestedPersonCard extends StatelessWidget {
  final SocialUserSearchResult person;
  final bool busy;
  final String buttonLabel;
  final VoidCallback onTap;
  final VoidCallback? onAction;

  const _SuggestedPersonCard({
    required this.person,
    required this.busy,
    required this.buttonLabel,
    required this.onTap,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final username = (person.user.username ?? '').trim();
    final subtitle = username.isNotEmpty ? '@$username' : person.user.role;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Ink(
        width: 164,
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.28),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: CircleAvatar(
                radius: 26,
                backgroundImage: (person.user.imageUrl ?? '').trim().isNotEmpty
                    ? AppCachedImageProvider(person.user.imageUrl!)
                    : null,
                child: (person.user.imageUrl ?? '').trim().isEmpty
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              person.user.fullName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 12,
              ),
            ),
            const Spacer(),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 40,
              child: onAction == null
                  ? OutlinedButton(
                      onPressed: null,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: Text(
                        buttonLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    )
                  : FilledButton(
                      onPressed: busy ? null : onAction,
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: busy
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              buttonLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SimpleExploreEmptyState extends StatelessWidget {
  final IconData icon;
  final String message;

  const _SimpleExploreEmptyState({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.28),
        ),
      ),
      child: Column(
        children: [
          Icon(icon, size: 28, color: scheme.primary),
          const SizedBox(height: 10),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReelPreviewCard extends StatelessWidget {
  final SocialPost reel;
  final VoidCallback onTap;

  const _ReelPreviewCard({required this.reel, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cover =
        reel.asset?.thumbnailUrl ??
        reel.asset?.posterUrl ??
        reel.asset?.playbackUrl ??
        reel.asset?.normalizedUrl ??
        reel.mediaUrl;
    return InkWell(
      borderRadius: BorderRadius.circular(24),
      onTap: onTap,
      child: Container(
        width: 164,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          image: cover == null
              ? null
              : DecorationImage(
                  image: AppCachedImageProvider(cover),
                  fit: BoxFit.cover,
                ),
          gradient: cover == null
              ? const LinearGradient(
                  colors: [Color(0xFF1D315E), Color(0xFF0A6866)],
                )
              : null,
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withValues(alpha: 0.04),
                Colors.black.withValues(alpha: 0.52),
              ],
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Spacer(),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(
                  Icons.play_arrow_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                reel.author.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                ),
              ),
              if (reel.caption.trim().isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  reel.caption.trim(),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
