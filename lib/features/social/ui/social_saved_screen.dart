import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import '../state/social_saved_controller.dart';
import 'social_collections_screen.dart';
import 'social_content_navigation.dart';
import 'social_profile_screen.dart';
import 'widgets/social_post_card_v2.dart';

class SocialSavedScreen extends ConsumerStatefulWidget {
  const SocialSavedScreen({super.key});

  @override
  ConsumerState<SocialSavedScreen> createState() => _SocialSavedScreenState();
}

class _SocialSavedScreenState extends ConsumerState<SocialSavedScreen> {
  String? _entityType;

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () =>
          ref.read(socialSavedControllerProvider.notifier).load(refresh: true),
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
            name: post.merchantName ?? context.l10n.commonMerchant,
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

  Future<void> _toggleLike(SocialPost post) async {
    await ref.read(socialApiProvider).toggleLike(post.id);
    if (!mounted) return;
    await ref.read(socialSavedControllerProvider.notifier).refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(socialSavedControllerProvider);
    final notifier = ref.read(socialSavedControllerProvider.notifier);
    final filters = <String?, String>{
      null: l10n.commonAll,
      'post': l10n.socialSavedPosts,
      'reel': l10n.socialSavedReels,
      'review': l10n.socialSavedReviews,
    };

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(
          title: Text(l10n.socialSavedTitle),
          actions: [
            IconButton(
              tooltip: l10n.socialSavedCollections,
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const SocialCollectionsScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.collections_bookmark_outlined),
            ),
          ],
        ),
        body: RefreshIndicator(
          onRefresh: notifier.refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: filters.entries
                    .map(
                      (entry) => ChoiceChip(
                        selected: _entityType == entry.key,
                        label: Text(entry.value),
                        onSelected: (_) async {
                          setState(() => _entityType = entry.key);
                          await notifier.load(
                            refresh: true,
                            entityType: entry.key,
                          );
                        },
                      ),
                    )
                    .toList(growable: false),
              ),
              const SizedBox(height: 16),
              if (state.loading && state.items.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 80),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (state.items.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 80),
                  child: Center(child: Text(l10n.socialSavedEmpty)),
                )
              else
                ...state.items.map(
                  (item) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: SocialPostCardV2(
                      post: item.content,
                      onOpenDetails: () {
                        openSocialContent(context, post: item.content);
                      },
                      onOpenProfile: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SocialProfileScreen(
                              userId: item.content.userId,
                              initialName: item.content.author.fullName,
                            ),
                          ),
                        );
                      },
                      onOpenMerchantLink: () => _openMerchant(item.content),
                      onToggleLike: () => _toggleLike(item.content),
                      onToggleSave: () async {
                        await notifier.toggleSaved(
                          entityType: item.entityType,
                          entityId: item.entityId,
                        );
                      },
                      onOpenComments: () {
                        openSocialComments(context, post: item.content);
                      },
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
