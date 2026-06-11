import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class AdCampaignDetailsScreen extends StatelessWidget {
  final String title;
  final String subtitle;
  final String? badgeLabel;
  final String? imageUrl;
  final String? merchantName;
  final String? ctaLabel;
  final Future<void> Function()? onPrimaryAction;

  const AdCampaignDetailsScreen({
    super.key,
    required this.title,
    required this.subtitle,
    required this.badgeLabel,
    required this.imageUrl,
    required this.merchantName,
    required this.ctaLabel,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final image = (imageUrl ?? '').trim();
    final isEnglish = Localizations.localeOf(context).languageCode == 'en';
    return Directionality(
      textDirection: Directionality.of(context),
      child: Scaffold(
        appBar: AppBar(title: Text(l10n.adCampaignDetailsTitle)),
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Stack(
                children: [
                  Container(
                    height: 240,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topRight,
                        end: Alignment.bottomLeft,
                        colors: [Color(0xFF2453A6), Color(0xFF102850)],
                      ),
                    ),
                  ),
                  if (image.isNotEmpty)
                    Positioned.fill(
                      child: CachedAppImage(
                        imageUrl: image,
                        fit: BoxFit.cover,
                        errorWidget: (context, error, stackTrace) =>
                            const SizedBox.shrink(),
                      ),
                    ),
                  Positioned.fill(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.black.withValues(alpha: 0.18),
                            Colors.black.withValues(alpha: 0.58),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          if ((badgeLabel ?? '').trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                color: Colors.black.withValues(alpha: 0.26),
                              ),
                              child: Text(
                                badgeLabel!,
                                textDirection: Directionality.of(context),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          const Spacer(),
                          Text(
                            title,
                            textDirection: Directionality.of(context),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 22,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            subtitle,
                            textDirection: Directionality.of(context),
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.94),
                              height: 1.45,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            if ((merchantName ?? '').trim().isNotEmpty)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.storefront_rounded),
                title: Text(
                  l10n.adCampaignDetailsRelatedMerchant,
                  textDirection: Directionality.of(context),
                ),
                subtitle: Text(
                  merchantName!,
                  textDirection: Directionality.of(context),
                ),
              ),
            const SizedBox(height: 8),
            Text(
              l10n.adCampaignDetailsDescriptionTitle,
              textDirection: Directionality.of(context),
              style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textDirection: Directionality.of(context),
              style: const TextStyle(height: 1.55),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: onPrimaryAction == null
                  ? null
                  : () => onPrimaryAction!(),
              icon: Icon(
                isEnglish
                    ? Icons.arrow_forward_rounded
                    : Icons.arrow_back_rounded,
              ),
              label: Text(
                ctaLabel?.trim().isNotEmpty == true
                    ? ctaLabel!
                    : l10n.commonContinue,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
