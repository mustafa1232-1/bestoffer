// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
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

class SocialHashtagScreen extends ConsumerStatefulWidget {
  final String tag;

  const SocialHashtagScreen({super.key, required this.tag});

  @override
  ConsumerState<SocialHashtagScreen> createState() =>
      _SocialHashtagScreenState();
}

class _SocialHashtagScreenState extends ConsumerState<SocialHashtagScreen> {
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
      final api = ref.read(socialApiProvider);
      final out = await api.listHashtagPosts(tag: widget.tag);
      final rows = List<dynamic>.from(out['posts'] as List? ?? const []);
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
        // Never store the raw exception (DioException / status code / request
        // id). Surface a clean, localized message only.
        _error = mapAnyError(
          e,
          fallback: context.lt(
            ar: 'تعذر تحميل المنشورات الآن.',
            en: 'Could not load posts right now.',
          ),
        );
        _loading = false;
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
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'حفظ المنشور',
      featureEnglish: 'saving a post',
    )) {
      return;
    }
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
            name: post.merchantName ?? 'متجر',
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
        appBar: AppBar(title: Text('#${widget.tag}')),
        body: RefreshIndicator(
          onRefresh: _load,
          child: _loading
              ? ListView(
                  children: const [
                    SizedBox(height: 240),
                    Center(child: CircularProgressIndicator()),
                  ],
                )
              : _error != null
              ? ListView(
                  children: [
                    const SizedBox(height: 120),
                    Center(child: Text(_error!)),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _posts.length,
                  separatorBuilder: (context, index) =>
                      const SizedBox(height: 14),
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
                      onOpenComments: () {
                        openSocialComments(context, post: post);
                      },
                    );
                  },
                ),
        ),
      ),
    );
  }
}
