import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/utils/currency.dart';
import '../../models/real_estate_models.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class RealEstateListingCard extends StatelessWidget {
  final RealEstateListingModel listing;
  final VoidCallback? onTap;
  final VoidCallback? onToggleSaved;
  final bool compact;

  const RealEstateListingCard({
    super.key,
    required this.listing,
    this.onTap,
    this.onToggleSaved,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = context.l10n;
    final cover = listing.media.isNotEmpty
        ? listing.media.first.imageUrl
        : null;
    final isNew =
        listing.createdAt != null &&
        DateTime.now().difference(listing.createdAt!).inDays <= 7;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.28),
            border: Border.all(
              color: scheme.outlineVariant.withValues(alpha: 0.32),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                child: AspectRatio(
                  aspectRatio: compact ? 1.55 : 1.7,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if ((cover ?? '').isNotEmpty)
                        CachedAppImage(
                          imageUrl: cover!,
                          cacheIdentity: 'real_estate_${listing.id}_cover',
                          version: listing.updatedAt?.toIso8601String(),
                          fit: BoxFit.cover,
                        )
                      else
                        Container(
                          color: scheme.surfaceContainer,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.apartment_rounded,
                            size: 40,
                            color: scheme.primary.withValues(alpha: 0.75),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.06),
                              Colors.black.withValues(alpha: 0.28),
                            ],
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        top: 12,
                        start: 12,
                        child: _BadgePill(
                          label: purposeLabel(context, listing.purpose),
                          background: listing.purpose == 'sale'
                              ? const Color(0xFF0F766E)
                              : const Color(0xFF7C3AED),
                        ),
                      ),
                      PositionedDirectional(
                        top: 12,
                        end: 12,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isNew)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 8,
                                ),
                                child: _BadgePill(
                                  label: l10n.realEstateNew,
                                  background: const Color(0xFF1D4ED8),
                                ),
                              ),
                            if (listing.isFeatured)
                              Padding(
                                padding: const EdgeInsetsDirectional.only(
                                  end: 8,
                                ),
                                child: _BadgePill(
                                  label: l10n.realEstateFeatured,
                                  background: const Color(0xFFEA580C),
                                ),
                              ),
                            if (onToggleSaved != null)
                              Material(
                                color: Colors.black.withValues(alpha: 0.32),
                                borderRadius: BorderRadius.circular(999),
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(999),
                                  onTap: onToggleSaved,
                                  child: Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Icon(
                                      listing.isSaved
                                          ? Icons.favorite_rounded
                                          : Icons.favorite_border_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      PositionedDirectional(
                        bottom: 12,
                        start: 12,
                        end: 12,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              formatIqd(listing.price),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if ((listing.city ?? '').isNotEmpty ||
                                (listing.block ?? '').isNotEmpty)
                              Padding(
                                padding: const EdgeInsets.only(top: 2),
                                child: Text(
                                  [
                                    if ((listing.city ?? '').isNotEmpty)
                                      listing.city!,
                                    if ((listing.block ?? '').isNotEmpty)
                                      listing.block!,
                                  ].join(' • '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.white.withValues(alpha: 0.92),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            listing.title,
                            maxLines: compact ? 1 : 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        _StatusDotChip(
                          label: statusLabel(context, listing.status),
                          color: statusColor(listing.status),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaPill(
                          icon: Icons.straighten_rounded,
                          label: '${listing.areaSqm} m²',
                        ),
                        _MetaPill(
                          icon: listing.furnished
                              ? Icons.chair_alt_rounded
                              : Icons.chair_outlined,
                          label: listing.furnished
                              ? l10n.realEstateFurnished
                              : l10n.realEstateUnfurnished,
                        ),
                        if (listing.roomsCount != null)
                          _MetaPill(
                            icon: Icons.bed_outlined,
                            label:
                                '${listing.roomsCount} ${l10n.realEstateRooms}',
                          ),
                        if (listing.bathroomsCount != null)
                          _MetaPill(
                            icon: Icons.bathtub_outlined,
                            label:
                                '${listing.bathroomsCount} ${l10n.realEstateBathrooms}',
                          ),
                      ],
                    ),
                    if ((listing.description ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        listing.description!,
                        maxLines: compact ? 2 : 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.onSurface.withValues(alpha: 0.74),
                          height: 1.35,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            listing.ownerFullName?.trim().isNotEmpty == true
                                ? listing.ownerFullName!
                                : l10n.realEstateListingOwnerUnknown,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: scheme.onSurface.withValues(alpha: 0.68),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          '${listing.viewCount}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: scheme.onSurface.withValues(alpha: 0.68),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.visibility_outlined,
                          size: 16,
                          color: scheme.onSurface.withValues(alpha: 0.58),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String purposeLabel(BuildContext context, String purpose) {
  final l10n = context.l10n;
  return purpose == 'rent' ? l10n.realEstateRent : l10n.realEstateSale;
}

String statusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  switch (status) {
    case 'active':
      return l10n.realEstateAvailable;
    case 'sold':
      return l10n.realEstateSold;
    case 'rented':
      return l10n.realEstateRented;
    case 'archived':
      return l10n.realEstateArchived;
    case 'pending_admin_review':
      return l10n.realEstatePendingReview;
    case 'hidden_due_subscription_expiry':
      return l10n.realEstateReviewStatusHiddenByExpiry;
    default:
      return status;
  }
}

String settlementModeLabel(BuildContext context, String value) {
  final l10n = context.l10n;
  switch (value) {
    case 'full':
      return l10n.realEstateSettlementFull;
    case 'partial':
      return l10n.realEstateSettlementPartial;
    case 'none':
    default:
      return l10n.realEstateSettlementNone;
  }
}

String paymentMethodLabel(BuildContext context, String value) {
  final l10n = context.l10n;
  switch (value) {
    case 'installments':
      return l10n.realEstateInstallments;
    case 'negotiable':
      return l10n.realEstateNegotiable;
    case 'cash':
    default:
      return l10n.realEstateCash;
  }
}

Color statusColor(String status) {
  switch (status) {
    case 'active':
      return const Color(0xFF16A34A);
    case 'sold':
      return const Color(0xFFEA580C);
    case 'rented':
      return const Color(0xFF7C3AED);
    case 'pending_admin_review':
      return const Color(0xFFF59E0B);
    case 'hidden_due_subscription_expiry':
      return const Color(0xFF64748B);
    case 'archived':
    default:
      return const Color(0xFF475569);
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color background;

  const _BadgePill({required this.label, required this.background});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: background.withValues(alpha: 0.92),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w800,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _MetaPill extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MetaPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.38),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: scheme.onSurface.withValues(alpha: 0.84),
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusDotChip extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusDotChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: color.withValues(alpha: 0.12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
