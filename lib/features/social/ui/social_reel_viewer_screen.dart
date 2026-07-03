// ignore_for_file: use_build_context_synchronously

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_guard.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/navigation/app_route_observer.dart';
import '../data/social_api.dart';
import 'social_create_post_sheet.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../models/social_models.dart';
import '../models/social_story_document.dart';
import '../state/social_controller.dart';
import '../state/social_reels_controller.dart';
import 'social_profile_screen.dart';
import 'social_reel_comments_sheet.dart';
import 'social_share_sheet.dart';
import 'social_story_composer_screen.dart';
import 'widgets/social_reel_card.dart';
import 'widgets/social_save_sheet.dart';

class SocialReelViewerScreen extends ConsumerStatefulWidget {
  final List<SocialReelItem>? initialItems;
  final int initialIndex;
  final int? initialReelId;
  final bool playbackEnabled;

  const SocialReelViewerScreen({
    super.key,
    this.initialItems,
    this.initialIndex = 0,
    this.initialReelId,
    this.playbackEnabled = true,
  });

  @override
  ConsumerState<SocialReelViewerScreen> createState() =>
      _SocialReelViewerScreenState();
}

class _SocialReelViewerScreenState extends ConsumerState<SocialReelViewerScreen>
    with WidgetsBindingObserver, RouteAware {
  static const Duration _reelsLoadTimeout = Duration(seconds: 12);
  static bool _rememberedMuted = true;
  late final PageController _pageController;
  late final SocialApi _socialApi;
  late int _currentIndex;
  DateTime? _activeSince;
  List<SocialReelItem>? _seedItems;
  List<SocialReelItem> _lastKnownItems = const <SocialReelItem>[];
  late bool _muted;
  bool _appInForeground = true;
  bool _routeVisible = true;
  ModalRoute<dynamic>? _subscribedRoute;

  bool get _playbackActive =>
      widget.playbackEnabled && _appInForeground && _routeVisible;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
    _socialApi = ref.read(socialApiProvider);
    _activeSince = DateTime.now();
    _muted = _rememberedMuted;
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      _seedItems = List<SocialReelItem>.of(widget.initialItems!);
      Future.microtask(_hydrateSeedItemsFromExploreFeed);
    } else if (widget.initialReelId != null) {
      Future.microtask(_bootstrapInitialReel);
    } else {
      Future.microtask(
        () => ref
            .read(socialReelsControllerProvider.notifier)
            .load(refresh: true),
      );
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route == null || identical(route, _subscribedRoute)) {
      return;
    }
    if (_subscribedRoute != null) {
      appRouteObserver.unsubscribe(this);
    }
    _subscribedRoute = route;
    appRouteObserver.subscribe(this, route);
    final isCurrent = route.isCurrent;
    if (_routeVisible != isCurrent) {
      setState(() => _routeVisible = isCurrent);
    }
  }

  @override
  void didPush() {
    if (!_routeVisible && mounted) {
      setState(() => _routeVisible = true);
    }
  }

  @override
  void didPopNext() {
    if (!_routeVisible && mounted) {
      setState(() => _routeVisible = true);
    }
  }

  @override
  void didPushNext() {
    if (_routeVisible && mounted) {
      setState(() => _routeVisible = false);
    }
  }

  @override
  void didPop() {
    _routeVisible = false;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final nextForeground = state == AppLifecycleState.resumed;
    if (_appInForeground == nextForeground || !mounted) {
      return;
    }
    setState(() => _appInForeground = nextForeground);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_subscribedRoute != null) {
      appRouteObserver.unsubscribe(this);
      _subscribedRoute = null;
    }
    _recordCurrentViewFromItems(_seedItems ?? _lastKnownItems);
    _pageController.dispose();
    super.dispose();
  }

  List<SocialReelItem> get _items {
    if (_seedItems != null) return _seedItems!;
    return ref.read(socialReelsControllerProvider).items;
  }

  List<SocialReelItem> _mergeReelItems(
    Iterable<SocialReelItem> primary,
    Iterable<SocialReelItem> secondary,
  ) {
    final merged = <SocialReelItem>[];
    final seen = <int>{};
    for (final item in [...primary, ...secondary]) {
      if (seen.add(item.post.id)) {
        merged.add(item);
      }
    }
    return merged;
  }

  Future<void> _hydrateSeedItemsFromExploreFeed() async {
    await _loadReels(refresh: true);
    if (!mounted) return;
    final loaded = ref.read(socialReelsControllerProvider).items;
    if (loaded.isEmpty) return;
    setState(() {
      _seedItems = _mergeReelItems(
        _seedItems ?? const <SocialReelItem>[],
        loaded,
      );
    });
  }

  Future<void> _loadMoreIntoSeedItems() async {
    await _loadReels(refresh: false);
    if (!mounted) return;
    final loaded = ref.read(socialReelsControllerProvider).items;
    if (loaded.isEmpty) return;
    setState(() {
      _seedItems = _mergeReelItems(
        _seedItems ?? const <SocialReelItem>[],
        loaded,
      );
    });
  }

  Future<void> _bootstrapInitialReel() async {
    final reelId = widget.initialReelId;
    if (reelId == null || reelId <= 0) return;
    try {
      final api = ref.read(socialApiProvider);
      final response = await api.getReelById(reelId).timeout(_reelsLoadTimeout);
      final target = SocialReelItem.fromJson(
        Map<String, dynamic>.from(response['reel'] as Map? ?? const {}),
      );
      await _loadReels(refresh: true);
      if (!mounted) return;
      final loaded = ref.read(socialReelsControllerProvider).items;
      final merged = _mergeReelItems(<SocialReelItem>[target], loaded);
      setState(() {
        _seedItems = merged;
        _currentIndex = 0;
      });
    } catch (_) {
      if (!mounted) return;
      await _loadReels(refresh: true);
    }
  }

  Future<void> _loadReels({required bool refresh}) async {
    await ref
        .read(socialReelsControllerProvider.notifier)
        .load(refresh: refresh, timeout: _reelsLoadTimeout);
  }

  Future<void> _recordCurrentView() async {
    await _recordCurrentViewFromItems(_items);
  }

  Future<void> _recordCurrentViewFromItems(List<SocialReelItem> items) async {
    if (_currentIndex < 0 || _currentIndex >= items.length) return;
    final startedAt = _activeSince;
    if (startedAt == null) return;
    final item = items[_currentIndex];
    final durationMs = math.max(
      0,
      DateTime.now().difference(startedAt).inMilliseconds,
    );
    final assetDurationMs = item.post.asset?.durationMs ?? 0;
    final completionRate = assetDurationMs <= 0
        ? 0.0
        : (durationMs / assetDurationMs).clamp(0.0, 1.0);
    try {
      await _socialApi
          .recordReelView(
            reelId: item.post.id,
            watchDurationMs: durationMs,
            completionRate: completionRate,
            completed: completionRate >= 0.92,
            replayCount: completionRate >= 0.98 ? 1 : 0,
            context: 'reel_viewer',
          )
          .timeout(const Duration(seconds: 6));
    } catch (_) {
      // Keep viewer disposal/navigation resilient.
    }
  }

  void _patchCurrentPost(SocialPost next) {
    ref.read(socialReelsControllerProvider.notifier).patchPost(next);
    if (_seedItems != null) {
      setState(() {
        _seedItems = _seedItems!
            .map(
              (item) => item.post.id == next.id
                  ? SocialReelItem(post: next, metrics: item.metrics)
                  : item,
            )
            .toList(growable: false);
      });
    }
  }

  Future<void> _toggleLike(SocialPost post) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'الإعجاب بالريلز',
      featureEnglish: 'liking a reel',
    )) {
      return;
    }
    final out = await ref.read(socialApiProvider).toggleLike(post.id);
    _patchCurrentPost(
      post.copyWith(
        likesCount:
            int.tryParse('${out['likesCount'] ?? out['likes_count']}') ??
            post.likesCount,
        isLiked: out['liked'] == true || out['isLiked'] == true,
      ),
    );
  }

  Future<void> _toggleSave(SocialPost post) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'حفظ الريلز',
      featureEnglish: 'saving a reel',
    )) {
      return;
    }
    if (!mounted) return;
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => SocialSaveSheet(
        entityType: 'reel',
        entityId: post.id,
        initiallySaved: post.isSaved,
      ),
    );
    if (saved == null) return;
    _patchCurrentPost(
      post.copyWith(
        isSaved: saved,
        savesCount: saved
            ? post.savesCount + (post.isSaved ? 0 : 1)
            : (post.savesCount - (post.isSaved ? 1 : 0)).clamp(0, 1 << 30),
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

  Future<void> _openComments(SocialReelItem item) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'التعليق على الريلز',
      featureEnglish: 'commenting on a reel',
    )) {
      return;
    }
    if (!mounted) return;
    final nextCount = await showSocialReelCommentsSheet(
      context,
      reelPost: item.post,
    );
    if (!mounted || nextCount == null) return;
    _patchCurrentPost(item.post.copyWith(commentsCount: nextCount));
  }

  Future<void> _shareToStory(SocialReelItem item) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'مشاركة الريلز في ستوري',
      featureEnglish: 'sharing a reel to story',
    )) {
      return;
    }
    if (!mounted) return;
    final posted = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SocialStoryComposerScreen(
          initialMode: SocialStoryComposerMode.reelShare,
          initialDraft: buildReelShareDraft(item),
        ),
      ),
    );
    if (!mounted || posted != true) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.socialReelViewerSharedToStory)),
    );
  }

  Future<void> _shareToChat(SocialReelItem item) async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'مشاركة الريلز في محادثة',
      featureEnglish: 'sharing a reel in chat',
    )) {
      return;
    }
    if (!mounted) return;
    await showSocialShareSheet(
      context: context,
      entityType: 'reel',
      entityId: item.post.id,
      previewTitle: item.post.author.fullName,
      previewSubtitle: item.post.caption.trim(),
      externalShareText: [
        item.post.caption.trim(),
        (item.post.asset?.posterUrl ?? item.post.mediaUrl ?? '').trim(),
      ].where((item) => item.isNotEmpty).join('\n'),
      sharedSnapshot: buildSocialSharedSnapshotFromPost(item.post),
    );
  }

  Future<void> _openCreateReel() async {
    if (!await requireAuthBeforeAction(
      context,
      featureArabic: 'إنشاء ريلز',
      featureEnglish: 'creating a reel',
    )) {
      return;
    }
    if (!mounted) return;
    await showSocialCreatePostSheet(context);
  }

  Future<void> _retryLoading() async {
    if (widget.initialReelId != null) {
      await _bootstrapInitialReel();
      return;
    }
    if (widget.initialItems != null && widget.initialItems!.isNotEmpty) {
      await _hydrateSeedItemsFromExploreFeed();
      return;
    }
    await _loadReels(refresh: true);
  }

  void _toggleMute() {
    setState(() {
      _muted = !_muted;
      _rememberedMuted = _muted;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(socialReelsControllerProvider);
    final items = _seedItems ?? widget.initialItems ?? state.items;
    _lastKnownItems = List<SocialReelItem>.of(items);
    final errorText = _resolveErrorText(context, state.error);

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(l10n.socialReelViewerTitle),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: items.isEmpty
                ? state.loading
                      ? const Center(child: CircularProgressIndicator())
                      : _ReelViewerEmptyState(
                          message: errorText ?? l10n.socialReelViewerEmpty,
                          isError: errorText != null,
                          onRetry: _retryLoading,
                          onCreateReel: _openCreateReel,
                        )
                : PageView.builder(
                    controller: _pageController,
                    scrollDirection: Axis.vertical,
                    onPageChanged: (index) async {
                      unawaited(_recordCurrentView());
                      if (!mounted) return;
                      setState(() {
                        _currentIndex = index;
                        _activeSince = DateTime.now();
                      });
                      if (index >= items.length - 3 &&
                          state.nextCursor != null) {
                        if (_seedItems != null) {
                          await _loadMoreIntoSeedItems();
                        } else {
                          await ref
                              .read(socialReelsControllerProvider.notifier)
                              .loadMore();
                        }
                      }
                    },
                    itemCount: items.length,
                    itemBuilder: (_, index) {
                      final item = items[index];
                      return SocialReelCard(
                        item: item,
                        active: index == _currentIndex && _playbackActive,
                        muted: _muted,
                        onOpenProfile: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => SocialProfileScreen(
                                userId: item.post.userId,
                                initialName: item.post.author.fullName,
                              ),
                            ),
                          );
                        },
                        onOpenComments: () => _openComments(item),
                        onOpenMerchantLink: () => _openMerchant(item.post),
                        onToggleLike: () => _toggleLike(item.post),
                        onToggleSave: () => _toggleSave(item.post),
                        onShare: () => _shareToChat(item),
                        onShareToStory: () => _shareToStory(item),
                        onToggleMute: _toggleMute,
                      );
                    },
                  ),
          ),
          if (items.isNotEmpty)
            Positioned(
              left: 14,
              bottom: 18 + MediaQuery.paddingOf(context).bottom,
              child: _ReelViewerMuteButton(
                muted: _muted,
                tooltip: _muted ? l10n.socialReelUnmute : l10n.socialReelMute,
                onPressed: _toggleMute,
              ),
            ),
        ],
      ),
    );
  }
}

String? _resolveErrorText(BuildContext context, String? error) {
  final value = error?.trim();
  if (value == null || value.isEmpty) return null;
  if (value == 'REELS_LOAD_TIMEOUT') {
    return context.lt(
      ar: 'استغرق تحميل الريلز وقتًا أطول من اللازم.',
      en: 'Reels took too long to load.',
    );
  }
  return value;
}

class _ReelViewerEmptyState extends StatelessWidget {
  final String message;
  final bool isError;
  final VoidCallback onRetry;
  final Future<void> Function() onCreateReel;

  const _ReelViewerEmptyState({
    required this.message,
    required this.isError,
    required this.onRetry,
    required this.onCreateReel,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isError
                  ? Icons.cloud_off_rounded
                  : Icons.play_circle_outline_rounded,
              color: Colors.white70,
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
                height: 1.35,
              ),
            ),
            const SizedBox(height: 18),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 12,
              runSpacing: 12,
              children: [
                FilledButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.commonRetry),
                ),
                OutlinedButton.icon(
                  onPressed: () => unawaited(onCreateReel()),
                  icon: const Icon(Icons.add_rounded),
                  label: Text(context.lt(ar: 'إنشاء ريلز', en: 'Create reel')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReelViewerMuteButton extends StatelessWidget {
  final bool muted;
  final String tooltip;
  final VoidCallback onPressed;

  const _ReelViewerMuteButton({
    required this.muted,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.black.withValues(alpha: 0.38),
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox(
            width: 46,
            height: 46,
            child: Icon(
              muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
              color: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}
