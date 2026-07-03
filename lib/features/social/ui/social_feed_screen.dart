// ignore_for_file: use_build_context_synchronously

import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/maslaki_user_drawer.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../models/social_models.dart';
import '../state/social_controller.dart';
import 'social_content_navigation.dart';
import 'social_community_screen.dart';
import 'social_create_post_sheet.dart';
import 'social_search_screen.dart';
import 'social_story_composer_entry_sheet.dart';
import 'social_story_quick_viewer.dart';
import 'widgets/basmaya_shell_bars.dart';
import 'widgets/social_feed_controls.dart';
import 'widgets/social_feed_posts_sliver.dart';
import 'widgets/social_stories_strip.dart';

class SocialFeedScreen extends ConsumerStatefulWidget {
  const SocialFeedScreen({super.key});

  @override
  ConsumerState<SocialFeedScreen> createState() => _SocialFeedScreenState();
}

class _SocialFeedScreenState extends ConsumerState<SocialFeedScreen> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await ref.read(socialControllerProvider.notifier).bootstrap();
  }

  Future<void> _refresh() async {
    await ref.read(socialControllerProvider.notifier).bootstrap();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final threshold = _scrollController.position.maxScrollExtent - 260;
    if (_scrollController.position.pixels < threshold) return;
    ref.read(socialControllerProvider.notifier).loadMorePosts();
  }

  Future<void> _openCreateMenu() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'إنشاء منشور أو ستوري',
      featureEnglish: 'creating a post or story',
    )) {
      return;
    }
    if (!mounted) return;
    final l10n = context.l10n;
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.post_add_rounded),
                  title: Text(l10n.socialFeedCreatePostTitle),
                  subtitle: Text(l10n.socialFeedCreatePostBody),
                  onTap: () => Navigator.of(sheetContext).pop('post'),
                ),
                ListTile(
                  leading: const Icon(Icons.auto_stories_rounded),
                  title: Text(l10n.socialFeedCreateStoryTitle),
                  subtitle: Text(l10n.socialFeedCreateStoryBody),
                  onTap: () => Navigator.of(sheetContext).pop('story'),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (!mounted || action == null) return;
    if (action == 'story') {
      final posted = await showSocialStoryComposerEntrySheet(context);
      if (posted == true) {
        await _refresh();
      }
      return;
    }
    final posted = await showSocialCreatePostSheet(context);
    if (posted == true) {
      await _refresh();
    }
  }

  Future<void> _openStoryGroup(SocialStoryGroup group) async {
    await showSocialStoryQuickViewer(
      context: context,
      group: group,
      onStoryViewed: (storyId) =>
          ref.read(socialControllerProvider.notifier).markStoryViewed(storyId),
      api: ref.read(socialApiProvider),
    );
  }

  Future<void> _openSearch() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const SocialSearchScreen()));
  }

  ({String scopeType, String scopeCode})? _resolvePrimaryCommunityScope() {
    final scopes = ref.read(basmayaScopeCodesProvider).valueOrNull;
    if (scopes == null) return null;
    final building = (scopes.buildingScopeCode ?? '').trim().toUpperCase();
    if (building.isNotEmpty) {
      return (scopeType: 'building', scopeCode: building);
    }
    final compound = (scopes.compoundScopeCode ?? '').trim().toUpperCase();
    if (compound.isNotEmpty) {
      return (scopeType: 'compound', scopeCode: compound);
    }
    final block = (scopes.blockScopeCode ?? '').trim().toUpperCase();
    if (block.isNotEmpty) {
      return (scopeType: 'block', scopeCode: block);
    }
    return null;
  }

  String _scopeTitleForShortcut(
    BuildContext context, {
    required String scopeType,
    required String scopeCode,
  }) {
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    final kind = switch (scopeType) {
      'building' => isEnglish ? 'Building' : 'عمارة',
      'compound' => isEnglish ? 'Compound' : 'مجمع',
      _ => isEnglish ? 'Block' : 'بلوك',
    };
    return isEnglish ? 'Shdysir $kind $scopeCode' : 'شديصير $kind $scopeCode';
  }

  Future<void> _openCommunityTab(int initialTab) async {
    final l10n = context.l10n;
    if (initialTab == 2 || initialTab == 3) {
      if (!await requireAuthBeforeAction(
        context,
        featureArabic: initialTab == 2 ? 'محادثة المجتمع' : 'فواتير المجتمع',
        featureEnglish: initialTab == 2 ? 'community chat' : 'community bills',
      )) {
        return;
      }
    }
    if (!mounted) return;
    final scope = _resolvePrimaryCommunityScope();
    if (scope == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.socialBasmayaUnavailableScope)),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => SocialCommunityScreen(
          scopeType: scope.scopeType,
          scopeCode: scope.scopeCode,
          initialTab: initialTab,
          title: _scopeTitleForShortcut(
            context,
            scopeType: scope.scopeType,
            scopeCode: scope.scopeCode,
          ),
        ),
      ),
    );
  }

  Future<void> _toggleSave(SocialPost post) {
    return _toggleSaveAsync(post);
  }

  Future<void> _toggleSaveAsync(SocialPost post) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'حفظ المنشور',
      featureEnglish: 'saving a post',
    )) {
      return;
    }
    await ref.read(socialControllerProvider.notifier).toggleSave(post);
  }

  Future<void> _reportPost(SocialPost post) async {
    final l10n = context.l10n;
    String reason = '';
    String details = '';
    final approved = await showDialog<bool>(
      context: context,
      useRootNavigator: false,
      builder: (dialogContext) {
        return AlertDialog(
          scrollable: true,
          title: Text(l10n.commonReport, textAlign: TextAlign.end),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                onChanged: (value) => reason = value,
                decoration: const InputDecoration(labelText: 'السبب'),
              ),
              const SizedBox(height: 8),
              TextField(
                onChanged: (value) => details = value,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'تفاصيل إضافية'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.commonConfirm),
            ),
          ],
        );
      },
    );
    reason = reason.trim();
    details = details.trim();
    if (!mounted || approved != true || reason.isEmpty) return;

    try {
      await ref
          .read(socialApiProvider)
          .reportPost(postId: post.id, reason: reason, details: details);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('تم إرسال التبليغ بنجاح.')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(e, fallback: 'تعذر إرسال التبليغ، حاول مرة أخرى.'),
          ),
        ),
      );
    }
  }

  VoidCallback? _merchantLinkActionFor(SocialPost post) {
    if (post.contentLink == null && post.merchantId == null) {
      return null;
    }
    return () => _openMerchantFromPost(post);
  }

  void _openMerchantFromPost(SocialPost post) {
    final l10n = context.l10n;
    final merchantId = post.contentLink?.merchantId ?? post.merchantId;
    if (merchantId == null || merchantId <= 0) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => MerchantProductsScreen(
          merchant: MerchantModel(
            id: merchantId,
            name: (post.merchantName ?? '').trim().isEmpty
                ? l10n.commonStore
                : post.merchantName!.trim(),
            type: (post.merchantType ?? '').trim().isEmpty
                ? 'market'
                : post.merchantType!.trim(),
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
    final l10n = context.l10n;
    final state = ref.watch(socialControllerProvider);
    final hasPosts = state.posts.isNotEmpty;
    final primaryScope = ref.watch(basmayaScopeCodesProvider).valueOrNull;
    final hasCommunityScope =
        (primaryScope?.buildingScopeCode ?? '').trim().isNotEmpty ||
        (primaryScope?.compoundScopeCode ?? '').trim().isNotEmpty ||
        (primaryScope?.blockScopeCode ?? '').trim().isNotEmpty;

    ref.listen<String?>(socialControllerProvider.select((s) => s.error), (
      previous,
      next,
    ) {
      if (next == null || next == previous || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next)));
    });

    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        drawer: const MaslakiBasmayaDrawer(),
        appBar: MaslakiTopBar(
          title: context.l10n.customerDiscoveryBasmayaFeed,
          subtitle: context.lt(
            ar: 'المنشورات والريلز والرسائل ضمن نفس تجربة مسلكي.',
            en: 'Posts, reels, and messages inside the same Maslaki experience.',
          ),
          leading: const MaslakiUserDrawerButton(openStartDrawer: true),
          actions: const [NotificationsBellButton()],
        ),
        floatingActionButton: FloatingActionButton.extended(
          heroTag: null,
          onPressed: _openCreateMenu,
          icon: const Icon(Icons.add_rounded),
          label: Text(l10n.commonCreate),
        ),
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: CustomScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: SocialFeedActionStrip(
                    onOpenSearch: _openSearch,
                    onOpenCreateMenu: _openCreateMenu,
                  ),
                ),
              ),
              if (hasCommunityScope)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  sliver: SliverToBoxAdapter(
                    child: SocialCommunityQuickActionsRow(
                      onOpenAnnouncements: () => _openCommunityTab(1),
                      onOpenCommunityChat: () => _openCommunityTab(2),
                      onOpenBills: () => _openCommunityTab(3),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: SocialStoriesStrip(
                    loading: state.loadingStories,
                    stories: state.stories,
                    onAddStory: () async {
                      final posted = await showSocialStoryComposerEntrySheet(
                        context,
                      );
                      if (posted == true) {
                        await _refresh();
                      }
                    },
                    onOpenStoryGroup: _openStoryGroup,
                  ),
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: SocialFeedFiltersRow(
                    activeKind: state.activeKind,
                    onSelectKind: (kind) => ref
                        .read(socialControllerProvider.notifier)
                        .setActiveKind(kind),
                  ),
                ),
              ),
              if (state.loadingPosts && !hasPosts)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (!hasPosts)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: SocialFeedEmptyState(onCreate: _openCreateMenu),
                )
              else
                SocialFeedPostsSliver(
                  posts: state.posts,
                  loadingMore: state.loadingMorePosts,
                  onOpenComments: (post) =>
                      openSocialComments(context, post: post),
                  onToggleLike: (post) async {
                    if (!await requireAuthBeforeAction(
                      context,
                      featureArabic: 'الإعجاب بالمنشور',
                      featureEnglish: 'liking a post',
                    )) {
                      return;
                    }
                    await ref
                        .read(socialControllerProvider.notifier)
                        .toggleLike(post);
                  },
                  onToggleSave: _toggleSave,
                  onReportPost: _reportPost,
                  onOpenMerchantLink: _merchantLinkActionFor,
                  onCommentsCountChanged: (post, count) => ref
                      .read(socialControllerProvider.notifier)
                      .patchCommentsCount(
                        postId: post.id,
                        commentsCount: count,
                      ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
