import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/utils/catalog_taxonomy.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../models/social_models.dart';
import '../state/social_search_controller.dart';
import 'social_content_navigation.dart';
import 'social_hashtag_screen.dart';
import 'social_profile_screen.dart';
import 'widgets/social_identity_view.dart';
import 'widgets/social_post_card_v2.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialSearchScreen extends ConsumerStatefulWidget {
  const SocialSearchScreen({super.key});

  @override
  ConsumerState<SocialSearchScreen> createState() => _SocialSearchScreenState();
}

class _SocialSearchScreenState extends ConsumerState<SocialSearchScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _debounce;

  static const List<String> _tabs = <String>[
    'all',
    'users',
    'posts',
    'reels',
    'hashtags',
    'merchants',
    'reviews',
  ];

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(socialSearchControllerProvider.notifier).search(query: ''),
    );
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  String _tabLabel(BuildContext context, String tab) {
    final l10n = context.l10n;
    switch (tab) {
      case 'users':
        return l10n.socialSearchUsers;
      case 'posts':
        return l10n.socialSearchPosts;
      case 'reels':
        return l10n.socialSearchReels;
      case 'hashtags':
        return l10n.socialSearchHashtags;
      case 'merchants':
        return l10n.socialSearchMerchants;
      case 'reviews':
        return l10n.socialSearchReviews;
      default:
        return l10n.commonAll;
    }
  }

  void _scheduleSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      ref
          .read(socialSearchControllerProvider.notifier)
          .search(query: _searchCtrl.text.trim());
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(socialSearchControllerProvider);
    final notifier = ref.read(socialSearchControllerProvider.notifier);
    final results = state.results;

    Widget buildUserTile(SocialUserSearchResult result) => ListTile(
      leading: CircleAvatar(
        backgroundImage: (result.user.imageUrl ?? '').trim().isNotEmpty
            ? AppCachedImageProvider(result.user.imageUrl!)
            : null,
        child: (result.user.imageUrl ?? '').trim().isEmpty
            ? const Icon(Icons.person_outline)
            : null,
      ),
      title: SocialIdentityView(
        author: result.user,
        showRoleFallback: true,
        primaryStyle: const TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 14,
        ),
        secondaryStyle: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w700,
          fontSize: 12,
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SocialProfileScreen(
              userId: result.user.id,
              initialName: result.user.fullName,
            ),
          ),
        );
      },
    );

    Widget buildMerchantTile(SocialMerchantOption merchant) => ListTile(
      leading: CircleAvatar(
        backgroundImage: (merchant.imageUrl ?? '').trim().isNotEmpty
            ? AppCachedImageProvider(merchant.imageUrl!)
            : null,
        child: (merchant.imageUrl ?? '').trim().isEmpty
            ? const Icon(Icons.storefront_outlined)
            : null,
      ),
      title: Text(merchant.name),
      subtitle: Text(
        merchantScopeTag(
          merchantType: merchant.type,
          activityType: merchant.activityType,
        ),
      ),
      onTap: () {
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => MerchantProductsScreen(
              merchant: MerchantModel(
                id: merchant.id,
                name: merchant.name,
                type: merchant.type,
                activityType: merchant.activityType,
                phone: merchant.phone,
                imageUrl: merchant.imageUrl,
                isOpen: true,
                hasDiscountOffer: false,
                hasFreeDeliveryOffer: false,
              ),
            ),
          ),
        );
      },
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.socialSearchTitle)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchCtrl,
              onChanged: (_) => _scheduleSearch(),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: l10n.socialSearchHint,
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchCtrl.text.trim().isEmpty
                    ? null
                    : IconButton(
                        onPressed: () {
                          _searchCtrl.clear();
                          _scheduleSearch();
                        },
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: _tabs
                  .map(
                    (tab) => Padding(
                      padding: const EdgeInsetsDirectional.only(end: 8),
                      child: ChoiceChip(
                        selected: state.tab == tab,
                        label: Text(_tabLabel(context, tab)),
                        onSelected: (_) => notifier.setTab(tab),
                      ),
                    ),
                  )
                  .toList(growable: false),
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: state.loading && results == null
                ? const Center(child: CircularProgressIndicator())
                : results == null
                ? const SizedBox.shrink()
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (results.recentSearches.isNotEmpty &&
                          state.query.trim().isEmpty) ...[
                        _SearchSectionTitle(
                          title: l10n.socialSearchRecentSearches,
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: results.recentSearches
                              .map(
                                (row) => ActionChip(
                                  label: Text('${row['rawQuery'] ?? ''}'),
                                  onPressed: () {
                                    _searchCtrl.text =
                                        '${row['rawQuery'] ?? ''}';
                                    notifier.search(
                                      query: _searchCtrl.text.trim(),
                                    );
                                  },
                                ),
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (results.suggestedPeople.isNotEmpty &&
                          state.query.trim().isEmpty) ...[
                        _SearchSectionTitle(
                          title: l10n.socialSearchSuggestedPeople,
                        ),
                        const SizedBox(height: 8),
                        ...results.suggestedPeople.map(buildUserTile),
                        const SizedBox(height: 16),
                      ],
                      if (results.users.isNotEmpty) ...[
                        _SearchSectionTitle(title: l10n.socialSearchUsers),
                        ...results.users.map(buildUserTile),
                        const SizedBox(height: 16),
                      ],
                      if (results.hashtags.isNotEmpty) ...[
                        _SearchSectionTitle(title: l10n.socialSearchHashtags),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: results.hashtags
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
                              )
                              .toList(growable: false),
                        ),
                        const SizedBox(height: 16),
                      ],
                      if (results.posts.isNotEmpty) ...[
                        _SearchSectionTitle(title: l10n.socialSearchPosts),
                        const SizedBox(height: 8),
                        ...results.posts.map(
                          (post) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SocialPostCardV2(
                              post: post,
                              onOpenDetails: () => openSocialContent(
                                context,
                                post: post,
                                reelContextPosts: results.posts,
                              ),
                            ),
                          ),
                        ),
                      ],
                      if (results.reels.isNotEmpty) ...[
                        _SearchSectionTitle(title: l10n.socialSearchReels),
                        const SizedBox(height: 8),
                        ...results.reels.map(
                          (post) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SocialPostCardV2(
                              post: post,
                              onOpenDetails: () {
                                openSocialReelsV3(
                                  context,
                                  reelId:
                                      socialCanonicalReelIdForPost(post) ??
                                      post.id,
                                );
                              },
                            ),
                          ),
                        ),
                      ],
                      if (results.reviews.isNotEmpty) ...[
                        _SearchSectionTitle(title: l10n.socialSearchReviews),
                        const SizedBox(height: 8),
                        ...results.reviews.map(
                          (post) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: SocialPostCardV2(post: post),
                          ),
                        ),
                      ],
                      if (results.merchants.isNotEmpty) ...[
                        _SearchSectionTitle(title: l10n.socialSearchMerchants),
                        ...results.merchants.map(buildMerchantTile),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

class _SearchSectionTitle extends StatelessWidget {
  final String title;

  const _SearchSectionTitle({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        title,
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
      ),
    );
  }
}
