import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/pricing.dart';
import '../../../core/i18n/app_strings.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../merchants/models/merchant_model.dart';
import '../../merchants/state/merchants_controller.dart';
import '../../merchants/ui/merchant_products_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../orders/state/cart_controller.dart';
import '../../orders/state/delivery_address_controller.dart';
import '../../orders/ui/cart_screen.dart';
import '../../orders/ui/customer_orders_screen.dart';
import '../../orders/ui/delivery_addresses_screen.dart';
import '../../assistant/ui/assistant_chat_screen.dart';
import '../state/auth_controller.dart';
import 'add_merchant_screen.dart';

class MerchantsListScreen extends ConsumerStatefulWidget {
  const MerchantsListScreen({super.key});

  @override
  ConsumerState<MerchantsListScreen> createState() =>
      _MerchantsListScreenState();
}

class _MerchantsListScreenState extends ConsumerState<MerchantsListScreen> {
  static const _promoItems = <_PromoItem>[
    _PromoItem(
      title: 'عروض بسماية اليومية',
      subtitle: 'خصومات متجددة على المطاعم والمتاجر القريبة منك',
      icon: Icons.local_offer_rounded,
    ),
    _PromoItem(
      title: 'توصيل سريع داخل المجمع',
      subtitle: 'من المتجر إلى باب بيتك بأجور ثابتة وواضحة',
      icon: Icons.delivery_dining_rounded,
    ),
    _PromoItem(
      title: 'متاجر الحي بين يديك',
      subtitle: 'كل ما تحتاجه يوميًا من مكان واحد وبلمسة حديثة',
      icon: Icons.storefront_rounded,
    ),
  ];

  String? filterType;
  String searchQuery = '';
  bool openNowOnly = false;

  final searchCtrl = TextEditingController();
  final promoController = PageController(viewportFraction: 0.92);
  Timer? promoTimer;
  int promoPage = 0;

  @override
  void initState() {
    super.initState();
    Future.microtask(() async {
      await ref.read(merchantsControllerProvider.notifier).load();
      await ref.read(deliveryAddressControllerProvider.notifier).bootstrap();
    });
    promoTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted || !promoController.hasClients) return;
      promoPage = (promoPage + 1) % _promoItems.length;
      promoController.animateToPage(
        promoPage,
        duration: const Duration(milliseconds: 520),
        curve: Curves.easeOutCubic,
      );
      setState(() {});
    });
  }

  @override
  void dispose() {
    promoTimer?.cancel();
    promoController.dispose();
    searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _openCart() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CartScreen()));
  }

  Future<void> _openOrders() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CustomerOrdersScreen()));
  }

  Future<void> _openAssistant() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const AssistantChatScreen()));
  }

  Future<void> _refresh() {
    return ref
        .read(merchantsControllerProvider.notifier)
        .load(type: filterType);
  }

  void _onChangeType(String? value) {
    if (filterType == value) return;
    setState(() => filterType = value);
    ref.read(merchantsControllerProvider.notifier).load(type: value);
  }

  List<MerchantModel> _applySearch(List<MerchantModel> list) {
    final q = searchQuery.trim().toLowerCase();
    final filtered = q.isEmpty
        ? list
        : list.where((merchant) {
            final name = merchant.name.toLowerCase();
            final description = (merchant.description ?? '').toLowerCase();
            final phone = (merchant.phone ?? '').toLowerCase();
            return name.contains(q) ||
                description.contains(q) ||
                phone.contains(q);
          }).toList();

    if (!openNowOnly) return filtered;
    return filtered.where((merchant) => merchant.isOpen).toList();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final merchants = ref.watch(merchantsControllerProvider);
    final cart = ref.watch(cartControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final showCustomerActions =
        !auth.isBackoffice && !auth.isOwner && !auth.isDelivery;
    final drawerItems = <AppUserDrawerItem>[
      AppUserDrawerItem(
        icon: Icons.home_outlined,
        label: strings.t('drawerHome'),
      ),
      AppUserDrawerItem(
        icon: Icons.refresh_rounded,
        label: strings.t('drawerRefresh'),
        onTap: (_) => _refresh(),
      ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.receipt_long_rounded,
          label: strings.t('myOrders'),
          onTap: (_) async => _openOrders(),
        ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.shopping_cart_outlined,
          label: strings.t('drawerCart'),
          onTap: (_) async => _openCart(),
        ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.location_on_outlined,
          label: 'عناوين التوصيل',
          onTap: (_) async => _openAddresses(),
        ),
      if (showCustomerActions)
        AppUserDrawerItem(
          icon: Icons.smart_toy_outlined,
          label: 'المساعد الذكي',
          onTap: (_) async => _openAssistant(),
        ),
      if (auth.isAdmin)
        AppUserDrawerItem(
          icon: Icons.add_business_rounded,
          label: strings.t('drawerCreateMerchant'),
          onTap: (_) async {
            final created = await Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const AddMerchantScreen()),
            );
            if (created == true) {
              await _refresh();
            }
          },
        ),
    ];

    return Scaffold(
      drawer: AppUserDrawer(
        title: strings.t('drawerWorkspace'),
        subtitle: strings.t('drawerMerchantsSub'),
        items: drawerItems,
      ),
      appBar: AppBar(
        title: Text(
          showCustomerActions
              ? strings.t('customerHomeTitle')
              : strings.t('backofficeMerchantsTitle'),
        ),
        actions: [
          if (showCustomerActions)
            IconButton(
              tooltip: strings.t('myOrders'),
              onPressed: _openOrders,
              icon: const Icon(Icons.receipt_long),
            ),
          if (showCustomerActions)
            IconButton(
              tooltip: 'المساعد الذكي',
              onPressed: _openAssistant,
              icon: const Icon(Icons.smart_toy_outlined),
            ),
          if (showCustomerActions)
            IconButton(
              tooltip: 'عناوين التوصيل',
              onPressed: _openAddresses,
              icon: const Icon(Icons.location_on_outlined),
            ),
          if (showCustomerActions)
            _CartButton(totalItems: cart.totalItems, onPressed: _openCart),
          if (showCustomerActions) const NotificationsBellButton(),
        ],
      ),
      floatingActionButton: auth.isAdmin
          ? FloatingActionButton.extended(
              onPressed: () async {
                final created = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(builder: (_) => const AddMerchantScreen()),
                );
                if (created == true) {
                  await _refresh();
                }
              },
              label: const Text('إنشاء متجر'),
              icon: const Icon(Icons.add_business_rounded),
            )
          : showCustomerActions
          ? FloatingActionButton.small(
              onPressed: _openAssistant,
              tooltip: 'المساعد الذكي',
              child: const Icon(Icons.smart_toy_outlined),
            )
          : null,
      body: merchants.when(
        data: (list) {
          if (!showCustomerActions) {
            return _BackofficeMerchantsView(
              merchants: list,
              selectedType: filterType,
              onSelectType: _onChangeType,
              onRefresh: _refresh,
              onOpenMerchant: (merchant) {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MerchantProductsScreen(merchant: merchant),
                  ),
                );
              },
            );
          }

          final filtered = _applySearch(list);
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 22),
              children: [
                _BasmayaLocationStrip(onOpenAddresses: _openAddresses),
                const SizedBox(height: 12),
                _CustomerQuickActions(
                  openNowOnly: openNowOnly,
                  onToggleOpenNowOnly: (value) =>
                      setState(() => openNowOnly = value),
                  onOpenAddresses: () => _openAddresses(),
                  onOpenOrders: _openOrders,
                  onOpenCart: _openCart,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchCtrl,
                  textDirection: TextDirection.rtl,
                  onChanged: (value) => setState(() => searchQuery = value),
                  decoration: InputDecoration(
                    hintText: 'ابحث عن مطعم، متجر أو رقم هاتف',
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searchQuery.isEmpty
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchCtrl.clear();
                              setState(() => searchQuery = '');
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(height: 14),
                _CustomerCategoryRail(
                  selectedType: filterType,
                  onSelectType: _onChangeType,
                ),
                const SizedBox(height: 14),
                _PromoCarousel(
                  controller: promoController,
                  promoItems: _promoItems,
                  currentPage: promoPage,
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  title: 'متاجر بسماية',
                  subtitle:
                      '${filtered.length} متجر متاح • ${filtered.where((m) => m.isOpen).length} مفتوح الآن',
                ),
                const SizedBox(height: 8),
                if (filtered.isEmpty)
                  const _EmptySearchState()
                else
                  ...List.generate(filtered.length, (index) {
                    final merchant = filtered[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: TweenAnimationBuilder<double>(
                        duration: Duration(milliseconds: 260 + (index * 55)),
                        curve: Curves.easeOutCubic,
                        tween: Tween(begin: 0, end: 1),
                        builder: (context, value, child) {
                          return Opacity(
                            opacity: value,
                            child: Transform.translate(
                              offset: Offset(0, (1 - value) * 14),
                              child: child,
                            ),
                          );
                        },
                        child: _MerchantTalabatCard(
                          merchant: merchant,
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) =>
                                    MerchantProductsScreen(merchant: merchant),
                              ),
                            );
                          },
                        ),
                      ),
                    );
                  }),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(child: Text(error.toString())),
      ),
    );
  }

  Future<void> _openAddresses({bool selectMode = false}) async {
    final changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => DeliveryAddressesScreen(selectOnTap: selectMode),
      ),
    );
    if (changed == true || selectMode) {
      await ref
          .read(deliveryAddressControllerProvider.notifier)
          .bootstrap(silent: true);
    }
  }
}

class _BackofficeMerchantsView extends StatelessWidget {
  final List<MerchantModel> merchants;
  final String? selectedType;
  final void Function(String? value) onSelectType;
  final Future<void> Function() onRefresh;
  final void Function(MerchantModel merchant) onOpenMerchant;

  const _BackofficeMerchantsView({
    required this.merchants,
    required this.selectedType,
    required this.onSelectType,
    required this.onRefresh,
    required this.onOpenMerchant,
  });

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Column(
        children: [
          const SizedBox(height: 10),
          _BackofficeFilters(
            selectedType: selectedType,
            onSelectType: onSelectType,
          ),
          Expanded(
            child: merchants.isEmpty
                ? ListView(
                    children: const [
                      SizedBox(height: 180),
                      Center(child: Text('لا توجد متاجر')),
                    ],
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: merchants.length,
                    separatorBuilder: (_, index) => const SizedBox(height: 10),
                    itemBuilder: (_, index) {
                      final merchant = merchants[index];
                      final typeLabel = merchant.type == 'restaurant'
                          ? 'مطعم'
                          : 'سوق';
                      return Card(
                        child: ListTile(
                          onTap: () => onOpenMerchant(merchant),
                          title: Text(
                            merchant.name,
                            textDirection: TextDirection.rtl,
                          ),
                          subtitle: Text(
                            '$typeLabel • ${merchant.phone ?? ''}',
                            textDirection: TextDirection.rtl,
                          ),
                          trailing: Text(merchant.isOpen ? 'مفتوح' : 'مغلق'),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _CustomerQuickActions extends StatelessWidget {
  final bool openNowOnly;
  final ValueChanged<bool> onToggleOpenNowOnly;
  final Future<void> Function() onOpenAddresses;
  final Future<void> Function() onOpenOrders;
  final Future<void> Function() onOpenCart;

  const _CustomerQuickActions({
    required this.openNowOnly,
    required this.onToggleOpenNowOnly,
    required this.onOpenAddresses,
    required this.onOpenOrders,
    required this.onOpenCart,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.location_on_outlined,
                    label: 'العناوين',
                    onTap: onOpenAddresses,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.receipt_long_outlined,
                    label: 'طلباتي',
                    onTap: onOpenOrders,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _QuickActionButton(
                    icon: Icons.shopping_cart_outlined,
                    label: 'السلة',
                    onTap: onOpenCart,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: const Text('عرض المتاجر المفتوحة الآن فقط'),
              value: openNowOnly,
              onChanged: onToggleOpenNowOnly,
            ),
          ],
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Future<void> Function() onTap;

  const _QuickActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }
}

class _CartButton extends StatelessWidget {
  final int totalItems;
  final VoidCallback onPressed;

  const _CartButton({required this.totalItems, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          tooltip: 'السلة',
          onPressed: onPressed,
          icon: const Icon(Icons.shopping_bag_outlined),
        ),
        if (totalItems > 0)
          Positioned(
            right: 8,
            top: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '$totalItems',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BasmayaLocationStrip extends ConsumerWidget {
  final Future<void> Function({bool selectMode}) onOpenAddresses;

  const _BasmayaLocationStrip({required this.onOpenAddresses});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressState = ref.watch(deliveryAddressControllerProvider);
    final selected = addressState.selectedAddress;

    final listItems = addressState.addresses
        .map(
          (a) => DropdownMenuItem<int>(
            value: a.id,
            child: Text(
              a.shortText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textDirection: TextDirection.rtl,
            ),
          ),
        )
        .toList();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0xFF1C4C89), Color(0xFF0D2A52)],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          IconButton(
            tooltip: 'إدارة العناوين',
            onPressed: () => onOpenAddresses(),
            icon: const Icon(Icons.edit_location_alt_outlined),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'مدينة بسماية',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Colors.white.withValues(alpha: 0.90),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                if (addressState.loading)
                  const Text(
                    'جاري تحميل العناوين...',
                    textDirection: TextDirection.rtl,
                  )
                else if (selected == null && listItems.isEmpty)
                  InkWell(
                    onTap: () => onOpenAddresses(selectMode: true),
                    child: Text(
                      'أضف عنوان توصيل للبدء',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        decoration: TextDecoration.underline,
                        color: Colors.white.withValues(alpha: 0.90),
                      ),
                    ),
                  )
                else
                  Directionality(
                    textDirection: TextDirection.rtl,
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        isExpanded: true,
                        value: selected?.id,
                        hint: const Text('اختر عنوان التوصيل'),
                        items: listItems,
                        onChanged: (value) {
                          if (value == null) return;
                          ref
                              .read(deliveryAddressControllerProvider.notifier)
                              .selectAddress(value);
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const Icon(Icons.place_rounded),
        ],
      ),
    );
  }
}

class _CustomerCategoryRail extends StatelessWidget {
  final String? selectedType;
  final void Function(String? value) onSelectType;

  const _CustomerCategoryRail({
    required this.selectedType,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 56,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _CategoryPill(
            label: 'الكل',
            icon: Icons.grid_view_rounded,
            selected: selectedType == null,
            onTap: () => onSelectType(null),
          ),
          const SizedBox(width: 8),
          _CategoryPill(
            label: 'مطاعم',
            icon: Icons.restaurant_menu_rounded,
            selected: selectedType == 'restaurant',
            onTap: () => onSelectType('restaurant'),
          ),
          const SizedBox(width: 8),
          _CategoryPill(
            label: 'أسواق',
            icon: Icons.storefront_rounded,
            selected: selectedType == 'market',
            onTap: () => onSelectType('market'),
          ),
        ],
      ),
    );
  }
}

class _CategoryPill extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _CategoryPill({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.22)
                : Theme.of(context).colorScheme.surface.withValues(alpha: 0.72),
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18),
              const SizedBox(width: 8),
              Text(label),
            ],
          ),
        ),
      ),
    );
  }
}

class _PromoCarousel extends StatelessWidget {
  final PageController controller;
  final List<_PromoItem> promoItems;
  final int currentPage;

  const _PromoCarousel({
    required this.controller,
    required this.promoItems,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(
          height: 138,
          child: PageView.builder(
            controller: controller,
            itemCount: promoItems.length,
            itemBuilder: (context, index) {
              final promo = promoItems[index];
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    gradient: const LinearGradient(
                      begin: Alignment.topRight,
                      end: Alignment.bottomLeft,
                      colors: [Color(0xFF203E72), Color(0xFF0D2A4F)],
                    ),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.10),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(promo.icon, size: 24),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              promo.title,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              promo.subtitle,
                              textDirection: TextDirection.rtl,
                              textAlign: TextAlign.right,
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.88),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(promoItems.length, (index) {
            final selected = index == currentPage;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              width: selected ? 20 : 8,
              height: 8,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.white.withValues(alpha: 0.24),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          subtitle,
          style: TextStyle(color: Colors.white.withValues(alpha: 0.70)),
        ),
        const Spacer(),
        Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ],
    );
  }
}

class _EmptySearchState extends StatelessWidget {
  const _EmptySearchState();

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          children: [
            const Icon(Icons.search_off_rounded, size: 34),
            const SizedBox(height: 8),
            const Text(
              'لا توجد نتائج مطابقة',
              textDirection: TextDirection.rtl,
              style: TextStyle(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              'جرّب البحث باسم مختلف أو اختر قسمًا آخر',
              textDirection: TextDirection.rtl,
              style: TextStyle(color: Colors.white.withValues(alpha: 0.76)),
            ),
          ],
        ),
      ),
    );
  }
}

class _MerchantTalabatCard extends StatelessWidget {
  final MerchantModel merchant;
  final VoidCallback onTap;

  const _MerchantTalabatCard({required this.merchant, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final typeLabel = merchant.type == 'restaurant' ? 'مطعم' : 'متجر';
    final hasOffers =
        merchant.hasDiscountOffer || merchant.hasFreeDeliveryOffer;
    final deliveryLabel = merchant.hasFreeDeliveryOffer
        ? 'توصيل مجاني'
        : formatIqd(deliveryFeeIqd);
    final etaLabel = merchant.isOpen ? '25 - 40 دقيقة' : 'خارج الدوام';
    final statusLabel = merchant.isOpen ? 'مفتوح الآن' : 'مغلق الآن';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: merchant.isOpen
                  ? [
                      const Color(0xFF1B3E72).withValues(alpha: 0.88),
                      const Color(0xFF122E55).withValues(alpha: 0.88),
                    ]
                  : [
                      const Color(0xFF2B3346).withValues(alpha: 0.92),
                      const Color(0xFF1E2434).withValues(alpha: 0.92),
                    ],
            ),
            border: Border.all(
              color: merchant.isOpen
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.25)
                  : Colors.white.withValues(alpha: 0.10),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: SizedBox(
                        width: 66,
                        height: 66,
                        child: merchant.imageUrl?.isNotEmpty == true
                            ? Image.network(
                                merchant.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    Container(
                                      color: Colors.white.withValues(
                                        alpha: 0.10,
                                      ),
                                      alignment: Alignment.center,
                                      child: Icon(
                                        merchant.type == 'restaurant'
                                            ? Icons.restaurant_rounded
                                            : Icons.storefront_rounded,
                                      ),
                                    ),
                              )
                            : Container(
                                color: Colors.white.withValues(alpha: 0.10),
                                alignment: Alignment.center,
                                child: Icon(
                                  merchant.type == 'restaurant'
                                      ? Icons.restaurant_rounded
                                      : Icons.storefront_rounded,
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            merchant.name,
                            textDirection: TextDirection.rtl,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            merchant.description?.trim().isNotEmpty == true
                                ? merchant.description!
                                : 'متجر من قلب بسماية',
                            textDirection: TextDirection.rtl,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.82),
                            ),
                          ),
                          if (hasOffers) ...[
                            const SizedBox(height: 6),
                            Wrap(
                              spacing: 6,
                              runSpacing: 6,
                              alignment: WrapAlignment.end,
                              children: [
                                if (merchant.hasDiscountOffer)
                                  const _MetaChip(
                                    icon: Icons.local_offer_rounded,
                                    text: 'عروض خصم',
                                  ),
                                if (merchant.hasFreeDeliveryOffer)
                                  const _MetaChip(
                                    icon: Icons.local_shipping_rounded,
                                    text: 'توصيل مجاني',
                                  ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.end,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    textDirection: TextDirection.rtl,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 220),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(999),
                          color: merchant.isOpen
                              ? Colors.green.withValues(alpha: 0.20)
                              : Colors.red.withValues(alpha: 0.20),
                          border: Border.all(
                            color: merchant.isOpen
                                ? Colors.green.withValues(alpha: 0.45)
                                : Colors.red.withValues(alpha: 0.45),
                          ),
                        ),
                        child: Text(
                          statusLabel,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      _MetaChip(icon: Icons.category_rounded, text: typeLabel),
                      _MetaChip(
                        icon: Icons.local_shipping_rounded,
                        text: deliveryLabel,
                      ),
                      _MetaChip(
                        icon: Icons.schedule_rounded,
                        text: etaLabel,
                        maxTextWidth: 118,
                      ),
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

class _MetaChip extends StatelessWidget {
  final IconData icon;
  final String text;
  final double maxTextWidth;

  const _MetaChip({
    required this.icon,
    required this.text,
    this.maxTextWidth = 110,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: Colors.white.withValues(alpha: 0.10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.white70),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxTextWidth),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _BackofficeFilters extends StatelessWidget {
  final String? selectedType;
  final void Function(String? value) onSelectType;

  const _BackofficeFilters({
    required this.selectedType,
    required this.onSelectType,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        children: [
          ChoiceChip(
            label: const Text('الكل'),
            selected: selectedType == null,
            onSelected: (_) => onSelectType(null),
          ),
          ChoiceChip(
            label: const Text('مطاعم'),
            selected: selectedType == 'restaurant',
            onSelected: (_) => onSelectType('restaurant'),
          ),
          ChoiceChip(
            label: const Text('أسواق'),
            selected: selectedType == 'market',
            onSelected: (_) => onSelectType('market'),
          ),
        ],
      ),
    );
  }
}

class _PromoItem {
  final String title;
  final String subtitle;
  final IconData icon;

  const _PromoItem({
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}
