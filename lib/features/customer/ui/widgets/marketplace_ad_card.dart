import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/locale_text.dart';
import '../../../../core/media/cached_app_image.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../merchants/state/merchants_controller.dart';
import '../../models/customer_ad_board_item.dart';
import '../../state/customer_ad_board_controller.dart';

/// External-link allow-list, injected at build time. Empty = allow any HTTPS.
final Set<String> _allowedAdHosts =
    const String.fromEnvironment('ADS_EXTERNAL_ALLOWED_HOSTS')
        .split(',')
        .map((host) => host.trim().toLowerCase())
        .where((host) => host.isNotEmpty)
        .toSet();

bool _isAllowedExternalAdUri(Uri uri) {
  if (uri.scheme != 'https') return false;
  if (_allowedAdHosts.isEmpty) return true;
  final host = uri.host.trim().toLowerCase();
  return _allowedAdHosts.any(
    (allowed) => host == allowed || host.endsWith('.$allowed'),
  );
}

/// A placement-scoped marketplace ad carousel. Fetches every eligible ad for
/// its [request], collapses fully when no ad is available, records impressions
/// as ads become visible, and records clicks before delegating navigation.
class MarketplaceAdCard extends ConsumerStatefulWidget {
  final MarketplaceAdRequest request;

  /// Called after the click is recorded, for non-external targets.
  final void Function(CustomerAdBoardItem item)? onTapAd;

  /// Vertical space kept above the card when an ad is present.
  final EdgeInsetsGeometry margin;
  final double height;
  final bool showEmptyState;

  const MarketplaceAdCard({
    super.key,
    required this.request,
    this.onTapAd,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.height = 138,
    this.showEmptyState = false,
  });

  @override
  ConsumerState<MarketplaceAdCard> createState() => _MarketplaceAdCardState();
}

class _MarketplaceAdCardState extends ConsumerState<MarketplaceAdCard> {
  late final PageController _pageController;
  Timer? _timer;
  int _currentPage = 0;
  final Set<int> _impressionLoggedForIds = <int>{};

  @override
  void initState() {
    super.initState();
    _pageController = PageController(viewportFraction: 0.94);
    _startTimer();
  }

  @override
  void didUpdateWidget(covariant MarketplaceAdCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request != widget.request) {
      _currentPage = 0;
      _impressionLoggedForIds.clear();
      if (_pageController.hasClients) {
        _pageController.jumpToPage(0);
      }
    }
    _timer?.cancel();
    _startTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted || !_pageController.hasClients) return;
      final items =
          ref.read(marketplaceAdsProvider(widget.request)).valueOrNull ??
          const <CustomerAdBoardItem>[];
      if (items.length <= 1) return;
      final next = _currentPage + 1;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 420),
        curve: Curves.easeInOut,
      );
    });
  }

  void _maybeLogImpression(CustomerAdBoardItem item) {
    if (!_impressionLoggedForIds.add(item.id)) return;
    unawaited(ref.read(merchantsApiProvider).recordAdImpression(item.id));
  }

  Future<void> _handleTap(CustomerAdBoardItem item) async {
    unawaited(ref.read(merchantsApiProvider).recordAdClick(item.id));

    final actionType =
        (item.type.trim().isNotEmpty ? item.type : item.ctaTargetType)
            .trim()
            .toLowerCase();

    if (actionType == 'external_link' || actionType == 'url') {
      final raw = (item.externalLink ?? item.ctaTargetValue ?? '').trim();
      final uri = Uri.tryParse(raw);
      if (uri == null || !_isAllowedExternalAdUri(uri)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الرابط غير مسموح أو غير صالح')),
        );
        return;
      }
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('تعذر فتح الرابط')));
      }
      return;
    }

    widget.onTapAd?.call(item);
  }

  @override
  Widget build(BuildContext context) {
    final asyncAds = ref.watch(marketplaceAdsProvider(widget.request));
    final items = asyncAds.valueOrNull ?? const <CustomerAdBoardItem>[];

    if (items.isEmpty) {
      if (widget.showEmptyState) {
        return _MarketplaceAdEmptyState(
          height: widget.height,
          margin: widget.margin,
          isLoading: asyncAds.isLoading && !asyncAds.hasValue,
          hasError: asyncAds.hasError && !asyncAds.hasValue,
          onRetry: () => ref.invalidate(marketplaceAdsProvider(widget.request)),
        );
      }
      return const SizedBox.shrink();
    }

    final visibleIndex = _currentPage % items.length;
    final visibleItem = items[visibleIndex];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLogImpression(visibleItem);
    });

    return Padding(
      padding: widget.margin,
      child: Column(
        children: [
          SizedBox(
            height: widget.height,
            child: PageView.builder(
              controller: _pageController,
              onPageChanged: (value) {
                setState(() => _currentPage = value);
                _maybeLogImpression(items[value % items.length]);
              },
              itemBuilder: (context, index) {
                final item = items[index % items.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _MarketplaceAdTile(
                    item: item,
                    onTap: () => _handleTap(item),
                  ),
                );
              },
            ),
          ),
          if (items.length > 1) ...[
            const SizedBox(height: 9),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(items.length, (index) {
                  final active = index == visibleIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 220),
                    width: active ? 18 : 6,
                    height: 6,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(999),
                      color: active
                          ? context.visualTheme.accentCyan
                          : context.visualTheme.accentCyan.withValues(
                              alpha: 0.28,
                            ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MarketplaceAdTile extends StatelessWidget {
  final CustomerAdBoardItem item;
  final VoidCallback onTap;

  const _MarketplaceAdTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isArabic = context.appTextDirection == TextDirection.rtl;
    final title = item.resolvedTitle(isArabic);
    final subtitle = item.resolvedSubtitle(isArabic);
    final image = (item.displayImageUrl ?? '').trim();
    final visual = context.visualTheme;
    final ctaLabel = (item.resolvedCtaLabel(isArabic) ?? '').trim();

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            colors: [
              Color.alphaBlend(
                visual.accentViolet.withValues(alpha: 0.56),
                const Color(0xFF1A2E59),
              ),
              Color.alphaBlend(
                visual.accentBlue.withValues(alpha: 0.52),
                const Color(0xFF142D51),
              ),
            ],
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: CachedAppImage(
                  imageUrl: image,
                  cacheIdentity: 'mkt_ad_${item.id}',
                  fit: BoxFit.cover,
                  errorWidget: (context, url, error) => const SizedBox.shrink(),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.08),
                    Colors.black.withValues(alpha: 0.58),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if ((item.badgeLabel ?? '').trim().isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 9,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withValues(alpha: 0.18),
                      ),
                      child: Text(
                        item.badgeLabel!.trim(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  const Spacer(),
                  Text(
                    title,
                    textDirection: context.appTextDirection,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      height: 1.1,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (subtitle.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      textDirection: context.appTextDirection,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.86),
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                  if (ctaLabel.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Align(
                      alignment: isArabic
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: Colors.white.withValues(alpha: 0.92),
                        ),
                        child: Text(
                          ctaLabel,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF142D51),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MarketplaceAdEmptyState extends StatelessWidget {
  final double height;
  final EdgeInsetsGeometry margin;
  final bool isLoading;
  final bool hasError;
  final VoidCallback onRetry;

  const _MarketplaceAdEmptyState({
    required this.height,
    required this.margin,
    required this.isLoading,
    required this.hasError,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final visual = context.visualTheme;
    final isArabic = context.appTextDirection == TextDirection.rtl;
    final title = hasError
        ? (isArabic
              ? 'تعذر تحميل الإعلانات حالياً'
              : 'Could not load ads right now')
        : (isArabic
              ? 'لا توجد إعلانات مفعلة حالياً'
              : 'No active ads right now');
    final message = hasError
        ? (isArabic
              ? 'تحقق من اتصال الشبكة أو إعدادات الإعلان ثم أعد المحاولة'
              : 'Check the network or ad settings, then try again.')
        : (isArabic
              ? 'تأكد من تفعيل الإعلان والتاريخ وأن المتجر المرتبط موافق عليه'
              : 'Make sure the ad is active, in date, and linked to an approved store.');
    final buttonLabel = isArabic ? 'تحديث الإعلانات' : 'Refresh ads';

    return Padding(
      padding: margin,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          color: const Color(0xFF142D51).withValues(alpha: 0.62),
          border: Border.all(color: visual.accentGold.withValues(alpha: 0.82)),
        ),
        child: isLoading
            ? Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.4,
                    color: visual.accentGold,
                  ),
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Row(
                    textDirection: context.appTextDirection,
                    children: [
                      Icon(
                        hasError
                            ? Icons.warning_amber_rounded
                            : Icons.campaign_outlined,
                        color: visual.accentGold,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          textDirection: context.appTextDirection,
                          textAlign: isArabic
                              ? TextAlign.right
                              : TextAlign.left,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  Text(
                    message,
                    textDirection: context.appTextDirection,
                    textAlign: isArabic ? TextAlign.right : TextAlign.left,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.76),
                      fontSize: 12,
                      height: 1.35,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: isArabic
                        ? Alignment.centerLeft
                        : Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: onRetry,
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: Text(buttonLabel),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
