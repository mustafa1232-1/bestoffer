import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/i18n/locale_text.dart';
import '../../../../core/media/cached_app_image.dart';
import '../../../../core/theme/app_theme.dart';
import '../../models/customer_ad_board_item.dart';
import '../../state/customer_ad_board_controller.dart';
import '../../../merchants/state/merchants_controller.dart';

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

/// A single placement-scoped marketplace ad. Fetches the winning ad for its
/// [request] from the shared `ad_board` backend, collapses fully when there is
/// no eligible ad, logs one impression when it first becomes visible (never on
/// rebuild), and records a click before invoking [onTapAd].
///
/// Navigation for store/product/category targets is delegated to [onTapAd] so
/// each host screen can reuse its own routing; external HTTPS links are opened
/// here directly (with the allow-list enforced).
class MarketplaceAdCard extends ConsumerStatefulWidget {
  final MarketplaceAdRequest request;

  /// Called after the click is recorded, for non-external targets. Receives the
  /// tapped ad so the host can route to a store/product/category.
  final void Function(CustomerAdBoardItem item)? onTapAd;

  /// Vertical space kept above the card when an ad is present. Collapses to zero
  /// along with the card when there is no ad.
  final EdgeInsetsGeometry margin;

  const MarketplaceAdCard({
    super.key,
    required this.request,
    this.onTapAd,
    this.margin = const EdgeInsets.only(bottom: 12),
  });

  @override
  ConsumerState<MarketplaceAdCard> createState() => _MarketplaceAdCardState();
}

class _MarketplaceAdCardState extends ConsumerState<MarketplaceAdCard> {
  int? _impressionLoggedForId;

  void _maybeLogImpression(CustomerAdBoardItem item) {
    if (_impressionLoggedForId == item.id) return;
    _impressionLoggedForId = item.id;
    // Fire-and-forget: analytics must never disrupt the UI.
    unawaited(ref.read(merchantsApiProvider).recordAdImpression(item.id));
  }

  Future<void> _handleTap(CustomerAdBoardItem item) async {
    // Best-effort analytics; ignore the returned future.
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
    final asyncAd = ref.watch(marketplaceAdProvider(widget.request));
    final item = asyncAd.asData?.value;
    if (item == null) {
      // Collapse fully: loading, error, and no-ad all render nothing.
      return const SizedBox.shrink();
    }

    // The ad is in the tree with real data → it is on the marketplace surface.
    // Log the impression once (guarded per ad id) after this frame.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _maybeLogImpression(item);
    });

    final isArabic = context.appTextDirection == TextDirection.rtl;
    final title = item.resolvedTitle(isArabic);
    final subtitle = item.resolvedSubtitle(isArabic);
    final image = (item.displayImageUrl ?? '').trim();
    final visual = context.visualTheme;

    return Padding(
      padding: widget.margin,
      child: AspectRatio(
        aspectRatio: 2.6,
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () => _handleTap(item),
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
                      errorWidget: (context, url, error) =>
                          const SizedBox.shrink(),
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
                      if ((item.resolvedCtaLabel(isArabic) ?? '')
                          .trim()
                          .isNotEmpty) ...[
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
                              item.resolvedCtaLabel(isArabic)!.trim(),
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
        ),
      ),
    );
  }
}
