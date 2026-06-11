import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../../paid_upgrades/ui/paid_upgrades_home_screen.dart';
import '../data/car_catalog.dart';
import '../data/cars_api.dart';
import '../models/car_listing_model.dart';
import 'customer_car_listing_details_screen.dart';
import 'customer_cars_filter_sheet.dart';
import 'customer_cars_workspace_screen.dart';
import 'widgets/customer_car_listing_card.dart';

class CustomerCarsMarketplaceScreen extends ConsumerStatefulWidget {
  const CustomerCarsMarketplaceScreen({super.key});

  @override
  ConsumerState<CustomerCarsMarketplaceScreen> createState() =>
      _CustomerCarsMarketplaceScreenState();
}

class _CustomerCarsMarketplaceScreenState
    extends ConsumerState<CustomerCarsMarketplaceScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  bool _loading = true;
  bool _loadingEntitlement = false;
  String? _error;
  bool _canSellCars = false;
  bool _premiumUnlocksCars = false;
  CarListingQuery _query = const CarListingQuery();
  List<CarListingModel> _items = const [];
  List<String> _brands = const [];

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _loadEntitlement();
    await _loadBrands();
    await _load();
  }

  Future<void> _loadBrands() async {
    try {
      final brands = await ref.read(carsApiProvider).listBrands();
      if (!mounted || brands.isEmpty) return;
      setState(() => _brands = brands);
    } catch (_) {
      // ignore and fall back to local catalog
    }
  }

  Future<void> _loadEntitlement() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed) return;
    setState(() => _loadingEntitlement = true);
    try {
      final out = await ref
          .read(carsApiProvider)
          .entitlements(forceRefresh: true);
      if (!mounted) return;
      setState(() {
        _canSellCars = out['canPostCars'] == true;
        _premiumUnlocksCars = out['premiumMonthly'] == true;
        _loadingEntitlement = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingEntitlement = false);
      }
    }
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final value = _searchCtrl.text.trim();
      setState(() {
        _query = _query.copyWith(search: value.isEmpty ? null : value);
      });
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await ref
          .read(carsApiProvider)
          .listMarketplaceListings(_query, limit: 80);
      if (!mounted) return;
      setState(() {
        _items = rows.map(CarListingModel.fromJson).toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(error, fallback: context.l10n.carsLoadFailed);
      });
    }
  }

  Future<void> _openWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const CustomerCarsWorkspaceScreen()),
    );
    if (!mounted) return;
    await _loadEntitlement();
    await _load();
  }

  Future<void> _openUpgrade() async {
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const PaidUpgradesHomeScreen()));
    if (!mounted) return;
    await _loadEntitlement();
  }

  Future<void> _openFilters() async {
    final next = await showModalBottomSheet<CarListingQuery>(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          CustomerCarsFilterSheet(initialQuery: _query, brands: _brands),
    );
    if (next == null || !mounted) return;
    _searchCtrl.text = next.search ?? '';
    setState(() => _query = next);
    await _load();
  }

  void _openDetails(CarListingModel item) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CustomerCarListingDetailsScreen(
          listingId: item.id,
          initialListing: item,
        ),
      ),
    );
  }

  void _applyQuickPreset({String? condition, String? bodyType, String? sort}) {
    setState(() {
      _query = _query.copyWith(
        condition: condition,
        bodyType: bodyType,
        sort: sort ?? _query.sort,
      );
    });
    _load();
  }

  List<Widget> _activeFilterChips() {
    final chips = <Widget>[];

    void addChip(String label, VoidCallback onDeleted) {
      chips.add(InputChip(label: Text(label), onDeleted: onDeleted));
    }

    if ((_query.search ?? '').isNotEmpty) {
      addChip(_query.search!, () {
        _searchCtrl.clear();
        setState(() => _query = _query.copyWith(search: null));
        _load();
      });
    }
    if ((_query.brand ?? '').isNotEmpty) {
      addChip(_query.brand!, () {
        setState(() => _query = _query.copyWith(brand: null, model: null));
        _load();
      });
    }
    if ((_query.model ?? '').isNotEmpty) {
      addChip(_query.model!, () {
        setState(() => _query = _query.copyWith(model: null));
        _load();
      });
    }
    if ((_query.city ?? '').isNotEmpty) {
      addChip(_query.city!, () {
        setState(() => _query = _query.copyWith(city: null));
        _load();
      });
    }
    if ((_query.condition ?? '').isNotEmpty) {
      addChip(carConditionLabel(context, _query.condition!), () {
        setState(() => _query = _query.copyWith(condition: null));
        _load();
      });
    }
    if ((_query.bodyType ?? '').isNotEmpty) {
      addChip(carBodyTypeLabel(context, _query.bodyType!), () {
        setState(() => _query = _query.copyWith(bodyType: null));
        _load();
      });
    }
    if (_query.minPrice != null || _query.maxPrice != null) {
      final min = _query.minPrice?.round().toString() ?? '0';
      final max = _query.maxPrice?.round().toString() ?? '∞';
      addChip('$min - $max', () {
        setState(
          () => _query = _query.copyWith(minPrice: null, maxPrice: null),
        );
        _load();
      });
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = ref.watch(authControllerProvider);
    final activeChips = _activeFilterChips();
    final brands = _brands.isNotEmpty ? _brands : carBrandNames();

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.carsMarketplaceTitle),
        actions: [
          if (auth.isAuthed)
            IconButton(
              onPressed: _openWorkspace,
              icon: const Icon(Icons.directions_car_filled_outlined),
              tooltip: l10n.carsManageListings,
            ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_rounded),
                hintText: l10n.carsSearchHint,
                suffixIcon: IconButton(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: l10n.commonFilters,
                ),
              ),
            ),
          ),
          if (auth.isAuthed)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: _SellerBanner(
                loading: _loadingEntitlement,
                canSellCars: _canSellCars,
                premiumUnlocksCars: _premiumUnlocksCars,
                onPrimaryAction: _canSellCars ? _openWorkspace : _openUpgrade,
              ),
            ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ActionChip(
                  label: Text(l10n.carsQuickNewest),
                  onPressed: () => _applyQuickPreset(sort: 'recent'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.carsQuickSedan),
                  onPressed: () => _applyQuickPreset(bodyType: 'sedan'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.carsQuickSuv),
                  onPressed: () => _applyQuickPreset(bodyType: 'suv'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.carsQuickUsed),
                  onPressed: () => _applyQuickPreset(condition: 'used'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.carsQuickPriceLow),
                  onPressed: () => _applyQuickPreset(sort: 'price_low'),
                ),
              ],
            ),
          ),
          if (activeChips.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                child: Wrap(spacing: 8, runSpacing: 8, children: activeChips),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.carsResultsCount(_items.length),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if ((_query.brand ?? '').isEmpty && brands.isNotEmpty)
                  Flexible(
                    child: Text(
                      brands.take(3).join(' • '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(child: Text(_error!)),
                      ],
                    )
                  : _items.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.fromLTRB(16, 80, 16, 24),
                      children: [
                        Icon(
                          Icons.directions_car_filled_outlined,
                          size: 54,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.carsNoListings,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          l10n.commonNoResults,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 18),
                        Center(
                          child: OutlinedButton(
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _query = const CarListingQuery());
                              _load();
                            },
                            child: Text(l10n.commonReset),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return CustomerCarListingCard(
                          listing: item,
                          onTap: () => _openDetails(item),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerBanner extends StatelessWidget {
  final bool loading;
  final bool canSellCars;
  final bool premiumUnlocksCars;
  final VoidCallback onPrimaryAction;

  const _SellerBanner({
    required this.loading,
    required this.canSellCars,
    required this.premiumUnlocksCars,
    required this.onPrimaryAction,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: scheme.primary.withValues(alpha: 0.14),
            ),
            child: Icon(
              canSellCars
                  ? Icons.verified_outlined
                  : Icons.workspace_premium_outlined,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  canSellCars
                      ? l10n.carsManageListings
                      : l10n.carsActivateSelling,
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                if (loading)
                  const LinearProgressIndicator(minHeight: 3)
                else
                  Text(
                    canSellCars
                        ? (premiumUnlocksCars
                              ? '${l10n.carsSellerBannerActive} ${l10n.settingsPremiumActive}.'
                              : l10n.carsSellerBannerActive)
                        : l10n.carsSellerBannerInactive,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.onSurface.withValues(alpha: 0.74),
                      height: 1.35,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          FilledButton.tonal(
            onPressed: loading ? null : onPrimaryAction,
            child: Text(
              canSellCars ? l10n.carsManageListings : l10n.carsActivateSelling,
            ),
          ),
        ],
      ),
    );
  }
}
