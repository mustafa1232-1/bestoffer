import 'package:flutter/material.dart';

import '../../models/social_models.dart';
import '../social_content_navigation.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class SocialBusinessContextBanner extends StatelessWidget {
  final SocialBusinessContext contextModel;

  const SocialBusinessContextBanner({super.key, required this.contextModel});

  String _statusLabel() {
    switch (contextModel.status.trim().toLowerCase()) {
      case 'sold':
        return 'تم البيع';
      case 'rented':
        return 'تم التأجير';
      case 'archived':
        return 'مؤرشف';
      case 'unavailable':
        return 'لم يعد متاحًا';
      default:
        return 'متاح';
    }
  }

  String _kindLabel() {
    switch (contextModel.type.trim().toLowerCase()) {
      case 'car_listing':
        return 'سيارة';
      case 'real_estate_listing':
        return 'عقار';
      default:
        return 'إعلان';
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final entity = SocialSharedEntity(
      type: contextModel.type,
      id: contextModel.id,
      snapshot: <String, dynamic>{
        'title': contextModel.title,
        'subtitle': contextModel.subtitle,
        'price': contextModel.price,
        'imageUrl': contextModel.imageUrl,
        'posterUrl': contextModel.posterUrl,
      },
    );
    return InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: () => openSocialSharedEntity(context, entity: entity),
      child: Ink(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.72),
          border: Border.all(
            color: scheme.outlineVariant.withValues(alpha: 0.38),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 58,
              height: 58,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: scheme.primary.withValues(alpha: 0.12),
                image: (contextModel.imageUrl ?? '').trim().isEmpty
                    ? null
                    : DecorationImage(
                        image: AppCachedImageProvider(contextModel.imageUrl!),
                        fit: BoxFit.cover,
                      ),
              ),
              child: (contextModel.imageUrl ?? '').trim().isEmpty
                  ? Icon(
                      contextModel.type == 'real_estate_listing'
                          ? Icons.apartment_rounded
                          : Icons.directions_car_filled_rounded,
                      color: scheme.primary,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        _kindLabel(),
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                          fontSize: 12,
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: contextModel.isAvailable
                              ? Colors.green.withValues(alpha: 0.12)
                              : scheme.error.withValues(alpha: 0.12),
                        ),
                        child: Text(
                          _statusLabel(),
                          style: TextStyle(
                            color: contextModel.isAvailable
                                ? Colors.green.shade700
                                : scheme.error,
                            fontWeight: FontWeight.w800,
                            fontSize: 11.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    contextModel.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                  if ((contextModel.subtitle ?? '').trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        contextModel.subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  if (contextModel.price != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        '${contextModel.price}',
                        style: TextStyle(
                          color: scheme.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              Icons.open_in_new_rounded,
              size: 18,
              color: scheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }
}
