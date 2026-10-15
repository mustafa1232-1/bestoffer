import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../auth/ui/merchants_list_screen.dart';
import '../../behavior/data/behavior_api.dart';

class CustomerMainMarketScreen extends ConsumerStatefulWidget {
  const CustomerMainMarketScreen({super.key});

  @override
  ConsumerState<CustomerMainMarketScreen> createState() =>
      _CustomerMainMarketScreenState();
}

class _CustomerMainMarketScreenState
    extends ConsumerState<CustomerMainMarketScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(behaviorApiProvider)
          .trackEvent(
            eventName: 'shopping.main_market_open',
            category: 'shopping',
            action: 'open_direct_market',
            metadata: const {
              'route': 'main_market_direct',
              'screenLabel': 'كل السوق',
              'recentTitle': 'كنت تتصفح كل السوق',
              'recentSubtitle': 'اضغط للعودة إلى كل السوق',
            },
          );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MerchantsListScreen(
      overrideTitle: context.l10n.customerMainMarketTitle,
      compactCustomerMode: true,
      showShoppingCategoryCards: true,
      showCategoryIntelligence: false,
    );
  }
}
