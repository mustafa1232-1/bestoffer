import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../data/social_api.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_content_navigation.dart';
import 'social_profile_screen.dart';
import 'widgets/social_post_card_v2.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum SocialProfilePostCollectionMode {
  userPosts,
  likedPosts,
  commentedPosts,
  archivedPosts,
}

class SocialProfilePostsScreen extends ConsumerStatefulWidget {
  final int userId;
  final String title;
  final SocialProfilePostCollectionMode mode;
  final String? kind;
  final bool gridLayout;
  final bool allowRestore;
  final bool showScaffold;

  const SocialProfilePostsScreen({
    super.key,
    required this.userId,
    required this.title,
    required this.mode,
    this.kind,
    this.gridLayout = false,
    this.allowRestore = false,
    this.showScaffold = true,
  });

  @override
  ConsumerState<SocialProfilePostsScreen> createState() =>
      _SocialProfilePostsScreenState();
}

class _SocialProfilePostsScreenState
    extends ConsumerState<SocialProfilePostsScreen> {
  late final SocialApi _api;
  bool _loading = true;
  bool _moreLoading = false;
  String? _error;
  int? _nextCursor;
  List<SocialPost> _posts = const <SocialPost>[];

  @override
  void initState() {
    super.initState();
    _api = ref.read(socialApiProvider);
    Future.microtask(() => _load(refresh: true));
  }

  Future<void> _load({required bool refresh}) async {
    if (refresh) {
      setState(() {
        _loading = true;
        _error = null;
      });
    } else {
      if (_moreLoading) return;
      setState(() => _moreLoading = true);
    }
    try {
      final beforeId = refresh ? null : _nextCursor;
      final out = await switch (widget.mode) {
        SocialProfilePostCollectionMode.userPosts => _api.listUserPosts(
          userId: widget.userId,
          limit: 24,
          beforeId: beforeId,
          kind: widget.kind,
        ),
        SocialProfilePostCollectionMode.likedPosts => _api.listUserLikedPosts(
          userId: widget.userId,
          limit: 24,
          beforeId: beforeId,
          kind: widget.kind,
        ),
        SocialProfilePostCollectionMode.commentedPosts =>
          _api.listUserCommentedPosts(
            userId: widget.userId,
            limit: 24,
            beforeId: beforeId,
            kind: widget.kind,
          ),
        SocialProfilePostCollectionMode.archivedPosts =>
          _api.listMyArchivedPosts(
            limit: 24,
            beforeId: beforeId,
            kind: widget.kind,
          ),
      };
      final rawPosts = List<dynamic>.from(out['posts'] as List? ?? const []);
      final loaded = rawPosts
          .map((e) => SocialPost.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _posts = refresh ? loaded : [..._posts, ...loaded];
        _nextCursor = out['nextCursor'] is num
            ? (out['nextCursor'] as num).toInt()
            : int.tryParse('${out['nextCursor']}');
        _loading = false;
        _moreLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = mapAnyError(
          e,
          fallback: Localizations.localeOf(context).languageCode == 'en'
              ? 'Unable to load profile posts.'
              : 'تعذر تحميل منشورات الملف الشخصي.',
        );
        _loading = false;
        _moreLoading = false;
      });
    }
  }

  Future<void> _toggleLike(SocialPost post) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'الإعجاب بالمنشور',
      featureEnglish: 'liking a post',
    )) {
      return;
    }
    final out = await _api.toggleLike(post.id);
    final updated = post.copyWith(
      likesCount:
          int.tryParse('${out['likesCount'] ?? out['likes_count']}') ??
          post.likesCount,
      isLiked: out['liked'] == true || out['isLiked'] == true,
    );
    if (!mounted) return;
    setState(() {
      _posts = _posts
          .map((item) => item.id == updated.id ? updated : item)
          .toList(growable: false);
    });
  }

  Future<void> _toggleSave(SocialPost post) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'حفظ المنشور',
      featureEnglish: 'saving a post',
    )) {
      return;
    }
    final entityType = post.postKind == 'reel'
        ? 'reel'
        : post.postKind == 'merchant_review'
        ? 'review'
        : 'post';
    final out = await _api.toggleSaved(
      entityType: entityType,
      entityId: post.id,
    );
    final isSaved = out['saved'] == true;
    if (!mounted) return;
    setState(() {
      _posts = _posts
          .map(
            (item) => item.id == post.id
                ? item.copyWith(
                    isSaved: isSaved,
                    savesCount:
                        int.tryParse(
                          '${out['savesCount'] ?? out['saves_count']}',
                        ) ??
                        item.savesCount,
                  )
                : item,
          )
          .toList(growable: false);
    });
  }

  Future<void> _restorePost(SocialPost post) async {
    await _api.restorePost(post.id);
    if (!mounted) return;
    setState(() {
      _posts = _posts
          .where((item) => item.id != post.id)
          .toList(growable: false);
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.socialProfilePostsRestored)),
    );
  }

  void _openMerchant(SocialPost post) {
    final l10n = context.l10n;
    final merchantId = post.contentLink?.merchantId ?? post.merchantId;
    if (merchantId == null) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantProductsScreen(
          merchant: MerchantModel(
            id: merchantId,
            name: post.merchantName ?? l10n.commonStore,
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

  void _openPost(SocialPost post) {
    openSocialContent(context, post: post, reelContextPosts: _posts);
  }

  void _openReel(SocialPost target) {
    openSocialReelsV3(context, reelId: target.id);
  }

  Widget _buildGrid() {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _posts.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: 6,
        mainAxisSpacing: 6,
        childAspectRatio: 0.82,
      ),
      itemBuilder: (context, index) {
        final post = _posts[index];
        final isReel = isSocialVideoPost(post);
        final mediaUrl = resolveSocialPostPosterUrl(post) ?? '';
        return InkWell(
          onTap: () => isReel ? _openReel(post) : _openPost(post),
          borderRadius: BorderRadius.circular(14),
          child: Stack(
            fit: StackFit.expand,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  image: mediaUrl.trim().isEmpty
                      ? null
                      : DecorationImage(
                          image: AppCachedImageProvider(mediaUrl),
                          fit: BoxFit.cover,
                        ),
                ),
                child: mediaUrl.trim().isEmpty
                    ? Icon(
                        isReel
                            ? Icons.play_circle_outline_rounded
                            : Icons.image_outlined,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      )
                    : null,
              ),
              if (isReel)
                const Positioned(
                  top: 8,
                  left: 8,
                  child: Icon(
                    Icons.play_circle_fill_rounded,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
              if (widget.allowRestore)
                Positioned(
                  top: 6,
                  right: 6,
                  child: Material(
                    color: Colors.black45,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => _restorePost(post),
                      child: const Padding(
                        padding: EdgeInsets.all(6),
                        child: Icon(
                          Icons.unarchive_outlined,
                          color: Colors.white,
                          size: 18,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final body = RefreshIndicator(
      onRefresh: () => _load(refresh: true),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 120),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_error != null)
            Padding(
              padding: const EdgeInsets.only(top: 120),
              child: Center(child: Text(_error!)),
            )
          else if (_posts.isEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 120),
              child: Center(child: Text(l10n.socialProfilePostsEmpty)),
            )
          else ...[
            if (widget.gridLayout)
              _buildGrid()
            else
              ..._posts.map(
                (post) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Stack(
                    children: [
                      SocialPostCardV2(
                        post: post,
                        onOpenDetails: () => _openPost(post),
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
                        onOpenComments: () => _openPost(post),
                      ),
                      if (widget.allowRestore)
                        Positioned(
                          top: 10,
                          left: 10,
                          child: FilledButton.tonalIcon(
                            onPressed: () => _restorePost(post),
                            icon: const Icon(
                              Icons.unarchive_outlined,
                              size: 18,
                            ),
                            label: Text(l10n.socialProfilePostsRestore),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            if (_nextCursor != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: OutlinedButton.icon(
                  onPressed: _moreLoading ? null : () => _load(refresh: false),
                  icon: _moreLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.expand_more_rounded),
                  label: Text(l10n.socialProfilePostsLoadMore),
                ),
              ),
          ],
        ],
      ),
    );
    if (!widget.showScaffold) {
      return Directionality(
        textDirection: Directionality.of(context),
        child: body,
      );
    }
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(title: Text(widget.title)),
        body: body,
      ),
    );
  }
}
