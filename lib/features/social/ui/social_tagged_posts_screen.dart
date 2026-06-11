import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_content_navigation.dart';
import 'social_profile_screen.dart';
import 'widgets/social_post_card_v2.dart';
import 'widgets/social_save_sheet.dart';

class SocialTaggedPostsScreen extends ConsumerStatefulWidget {
  final int userId;
  final String? title;

  const SocialTaggedPostsScreen({super.key, required this.userId, this.title});

  @override
  ConsumerState<SocialTaggedPostsScreen> createState() =>
      _SocialTaggedPostsScreenState();
}

class _SocialTaggedPostsScreenState
    extends ConsumerState<SocialTaggedPostsScreen> {
  bool _loading = true;
  List<SocialPost> _posts = <SocialPost>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(socialApiProvider)
          .listProfileTagged(userId: widget.userId);
      final rows = List<dynamic>.from(
        out['posts'] ??
            out['items'] ??
            out['taggedPosts'] ??
            out['tagged_posts'] ??
            const [],
      );
      setState(() {
        _posts = rows
            .map(
              (e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.socialTaggedPostsLoadFailedFriendly,
        );
      });
    }
  }

  Future<void> _toggleLike(SocialPost post) async {
    final out = await ref.read(socialApiProvider).toggleLike(post.id);
    final next = post.copyWith(
      likesCount: int.tryParse('${out['likesCount']}') ?? post.likesCount,
      isLiked: out['isLiked'] == true,
    );
    if (!mounted) return;
    setState(() {
      _posts = _posts.map((item) => item.id == next.id ? next : item).toList();
    });
  }

  Future<void> _toggleSave(SocialPost post) async {
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
    if (saved == null || !mounted) return;
    setState(() {
      _posts = _posts
          .map(
            (item) => item.id == post.id
                ? item.copyWith(
                    isSaved: saved,
                    savesCount: saved
                        ? item.savesCount + (item.isSaved ? 0 : 1)
                        : (item.savesCount - (item.isSaved ? 1 : 0)).clamp(
                            0,
                            1 << 30,
                          ),
                  )
                : item,
          )
          .toList(growable: false);
    });
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

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: context.appTextDirection,
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? context.l10n.socialTaggedPostsTitle),
        ),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? ListView(
                  children: const [
                    SizedBox(height: 200),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : _error != null
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
                  children: [
                    Icon(
                      Icons.alternate_email_rounded,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Center(
                      child: Text(
                        _error!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Center(
                      child: Text(
                        context.l10n.commonTryAgainLater,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: Text(context.l10n.socialExploreRetry),
                    ),
                  ],
                )
              : _posts.isEmpty
              ? ListView(
                  padding: const EdgeInsets.fromLTRB(24, 120, 24, 24),
                  children: [
                    Icon(
                      Icons.alternate_email_outlined,
                      size: 48,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      context.l10n.socialTaggedPostsEmpty,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _posts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 12),
                  itemBuilder: (_, index) {
                    final post = _posts[index];
                    return SocialPostCardV2(
                      post: post,
                      onOpenDetails: () {
                        openSocialContent(
                          context,
                          post: post,
                          reelContextPosts: _posts,
                        );
                      },
                      onOpenProfile: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SocialProfileScreen(
                              userId: post.userId,
                              initialName: post.author.fullName,
                            ),
                          ),
                        );
                      },
                      onOpenMerchantLink: () => _openMerchant(post),
                      onToggleLike: () => _toggleLike(post),
                      onToggleSave: () => _toggleSave(post),
                    );
                  },
                ),
        ),
      ),
    );
  }
}
