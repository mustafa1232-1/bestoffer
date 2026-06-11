import 'package:flutter/material.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/utils/currency.dart';
import '../../models/car_listing_model.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CustomerCarListingCard extends StatelessWidget {
  final CarListingModel listing;
  final VoidCallback? onTap;
  final bool compact;

  const CustomerCarListingCard({
    super.key,
    required this.listing,
    this.onTap,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cover = listing.media.isNotEmpty
        ? listing.media.first.imageUrl
        : null;
    final isNew =
        listing.createdAt != null &&
        DateTime.now().difference(listing.createdAt!).inDays <= 10;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            color: scheme.surfaceContainerHighest.withValues(alpha: 0.24),
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
                  aspectRatio: compact ? 1.45 : 1.7,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if ((cover ?? '').isNotEmpty)
                        CachedAppImage(
                          imageUrl: cover!,
                          cacheIdentity: 'car_listing_${listing.id}_cover',
                          version: listing.updatedAt?.toIso8601String(),
                          fit: BoxFit.cover,
                        )
                      else
                        Container(
                          color: scheme.surfaceContainer,
                          alignment: Alignment.center,
                          child: Icon(
                            Icons.directions_car_filled_rounded,
                            size: 46,
                            color: scheme.primary.withValues(alpha: 0.72),
                          ),
                        ),
                      DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.black.withValues(alpha: 0.06),
                              Colors.black.withValues(alpha: 0.36),
                            ],
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        top: 12,
                        start: 12,
                        child: _BadgePill(
                          label: carConditionLabel(context, listing.condition),
                          background: listing.condition == 'new'
                              ? const Color(0xFF0F766E)
                              : const Color(0xFF475569),
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
                                  label: context.l10n.realEstateNew,
                                  background: const Color(0xFF1D4ED8),
                                ),
                              ),
                            _BadgePill(
                              label: carListingStatusLabel(
                                context,
                                listing.status,
                              ),
                              background: carListingStatusColor(listing.status),
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
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '${listing.brand} ${listing.model} • ${listing.modelYear}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: Colors.white.withValues(alpha: 0.92),
                                  fontWeight: FontWeight.w700,
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
                        if ((listing.city ?? '').isNotEmpty)
                          Text(
                            listing.city!,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurface.withValues(alpha: 0.66),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _MetaPill(
                          icon: Icons.calendar_today_rounded,
                          label: listing.modelYear.toString(),
                        ),
                        if (listing.mileageKm != null)
                          _MetaPill(
                            icon: Icons.route_rounded,
                            label: '${listing.mileageKm} km',
                          ),
                        _MetaPill(
                          icon: Icons.category_outlined,
                          label: carBodyTypeLabel(context, listing.bodyType),
                        ),
                        _MetaPill(
                          icon: Icons.settings_outlined,
                          label: carTransmissionLabel(
                            context,
                            listing.transmission,
                          ),
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
                    Text(
                      listing.ownerFullName?.trim().isNotEmpty == true
                          ? listing.ownerFullName!
                          : context.l10n.carsSellerUnknown,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: scheme.onSurface.withValues(alpha: 0.68),
                      ),
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

String carConditionLabel(BuildContext context, String condition) {
  switch (condition) {
    case 'new':
      return context.l10n.carsConditionNew;
    case 'used':
      return context.l10n.carsConditionUsed;
    default:
      return condition;
  }
}

String carBodyTypeLabel(BuildContext context, String bodyType) {
  switch (bodyType) {
    case 'sedan':
      return context.l10n.carsBodyTypeSedan;
    case 'suv':
      return context.l10n.carsBodyTypeSuv;
    case 'crossover':
      return context.l10n.carsBodyTypeCrossover;
    case 'hatchback':
      return context.l10n.carsBodyTypeHatchback;
    case 'pickup':
      return context.l10n.carsBodyTypePickup;
    case 'van':
      return context.l10n.carsBodyTypeVan;
    default:
      return bodyType;
  }
}

String carTransmissionLabel(BuildContext context, String transmission) {
  switch (transmission) {
    case 'automatic':
      return context.l10n.carsTransmissionAutomatic;
    case 'manual':
      return context.l10n.carsTransmissionManual;
    default:
      return transmission;
  }
}

String carFuelTypeLabel(BuildContext context, String fuelType) {
  switch (fuelType) {
    case 'fuel':
      return context.l10n.carsFuelTypeFuel;
    case 'hybrid':
      return context.l10n.carsFuelTypeHybrid;
    case 'electric':
      return context.l10n.carsFuelTypeElectric;
    default:
      return fuelType;
  }
}

String carListingStatusLabel(BuildContext context, String status) {
  switch (status) {
    case 'active':
      return context.l10n.carsStatusActive;
    case 'sold':
      return context.l10n.carsStatusSold;
    case 'archived':
      return context.l10n.carsStatusArchived;
    case 'hidden_due_subscription_expiry':
      return context.l10n.carsStatusHiddenByExpiry;
    default:
      return status;
  }
}

Color carListingStatusColor(String status) {
  switch (status) {
    case 'active':
      return const Color(0xFF15803D);
    case 'sold':
      return const Color(0xFF1D4ED8);
    case 'archived':
      return const Color(0xFF6B7280);
    case 'hidden_due_subscription_expiry':
      return const Color(0xFFB45309);
    default:
      return const Color(0xFF374151);
  }
}

class _BadgePill extends StatelessWidget {
  final String label;
  final Color background;

  const _BadgePill({required this.label, required this.background});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Text(
          label,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w800,
            fontSize: 12,
          ),
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
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: theme.colorScheme.surfaceContainerHighest.withValues(
          alpha: 0.46,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}
