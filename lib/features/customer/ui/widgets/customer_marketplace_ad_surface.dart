import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/i18n/locale_text.dart';
import '../../../auth/ui/merchants_list_screen.dart';
import '../../../merchants/models/merchant_model.dart';
import '../../../merchants/state/merchants_controller.dart';
import '../../../merchants/ui/merchant_products_screen.dart';
import '../../models/customer_ad_board_item.dart';
import '../../state/customer_ad_board_controller.dart';
import 'marketplace_ad_card.dart';

class CustomerMarketplaceAdSurface extends ConsumerWidget {
  final MarketplaceAdRequest request;
  final bool showEmptyState;
  final EdgeInsetsGeometry margin;
  final double height;

  const CustomerMarketplaceAdSurface({
    super.key,
    required this.request,
    this.showEmptyState = false,
    this.margin = const EdgeInsets.only(bottom: 12),
    this.height = 138,
  });

  Future<void> _openMerchant(
    BuildContext context,
    WidgetRef ref,
    int merchantId,
  ) async {
    if (merchantId <= 0) return;
    try {
      final raw = await ref.read(merchantsApiProvider).getById(merchantId);
      final merchant = MerchantModel.fromJson(raw);
      if (!context.mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => MerchantProductsScreen(merchant: merchant),
        ),
      );
    } catch (_) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            context.lt(
              ar: 'تعذر فتح المتجر حالياً',
              en: 'Could not open store right now',
            ),
          ),
        ),
      );
    }
  }

  Future<void> _handleTap(
    BuildContext context,
    WidgetRef ref,
    CustomerAdBoardItem ad,
  ) async {
    final actionType = (ad.type.trim().isNotEmpty ? ad.type : ad.ctaTargetType)
        .trim()
        .toLowerCase();

    switch (actionType) {
      case 'store_ad':
      case 'merchant':
      case 'product':
        final merchantId = ad.merchantId ?? ad.targetId;
        if (merchantId != null && merchantId > 0) {
          await _openMerchant(context, ref, merchantId);
          return;
        }
        break;
      case 'category_ad':
      case 'category':
        final activityType = (ad.activityType ?? '').trim();
        final category = (ad.category ?? ad.ctaTargetValue ?? '').trim();
        final normalizedCategory = category.toLowerCase();
        final isFashionDepartment =
            activityType == 'fashion_clothing' &&
            (normalizedCategory == 'men' || normalizedCategory == 'women');
        if (activityType.isNotEmpty || category.isNotEmpty) {
          await Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => MerchantsListScreen(
                initialType: 'market',
                initialActivityType: activityType.isEmpty ? null : activityType,
                initialDiscoverySubcategory:
                    activityType.isNotEmpty && !isFashionDepartment
                    ? category
                    : null,
                initialDepartment: isFashionDepartment
                    ? normalizedCategory
                    : null,
                overrideTitle: ad.resolvedTitle(
                  Directionality.of(context) == TextDirection.rtl,
                ),
                compactCustomerMode: true,
                strictCategoryMode: activityType.isNotEmpty,
                showCategoryIntelligence: false,
              ),
            ),
          );
          return;
        }
        break;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          overrideTitle: context.l10n.customerDiscoveryMerchants,
          compactCustomerMode: true,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MarketplaceAdCard(
      request: request,
      showEmptyState: showEmptyState,
      margin: margin,
      height: height,
      onTapAd: (ad) => _handleTap(context, ref, ad),
    );
  }
}
