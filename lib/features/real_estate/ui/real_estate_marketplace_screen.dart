import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../auth/state/auth_controller.dart';
import '../data/real_estate_api.dart';
import '../models/real_estate_models.dart';
import 'real_estate_filter_sheet.dart';
import 'real_estate_listing_details_screen.dart';
import 'real_estate_saved_listings_screen.dart';
import 'real_estate_workspace_screen.dart';
import 'widgets/real_estate_listing_card.dart';

class RealEstateMarketplaceScreen extends ConsumerStatefulWidget {
  const RealEstateMarketplaceScreen({super.key});

  @override
  ConsumerState<RealEstateMarketplaceScreen> createState() =>
      _RealEstateMarketplaceScreenState();
}

class _RealEstateMarketplaceScreenState
    extends ConsumerState<RealEstateMarketplaceScreen> {
  final TextEditingController _searchCtrl = TextEditingController();
  Timer? _searchDebounce;

  bool _loading = true;
  bool _savingBusy = false;
  String? _error;
  RealEstateListingQuery _query = const RealEstateListingQuery();
  List<RealEstateListingModel> _items = const [];
  Set<int> _savedIds = <int>{};

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_handleSearchChanged);
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _handleSearchChanged() {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), () {
      if (!mounted) return;
      final value = _searchCtrl.text.trim();
      final nextQuery =
          _query.copyWith(search: value.isEmpty ? null : value, sort: _query.sort);
      setState(() => _query = nextQuery);
      _load();
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final auth = ref.read(authControllerProvider);
      final listingsFuture = ref
          .read(realEstateApiProvider)
          .listListings(_query, limit: 80);
      final savedFuture = auth.isAuthed
          ? ref.read(realEstateApiProvider).listSavedListings(limit: 200)
          : Future.value(const <Map<String, dynamic>>[]);
      final results = await Future.wait<List<Map<String, dynamic>>>([
        listingsFuture,
        savedFuture,
      ]);
      if (!mounted) return;
      final savedIds = results[1]
          .map((e) => RealEstateListingModel.fromJson(e).id)
          .toSet();
      setState(() {
        _savedIds = savedIds;
        _items = results[0]
            .map(RealEstateListingModel.fromJson)
            .map(
              (item) => item.copyWith(
                isSaved: item.isSaved || savedIds.contains(item.id),
              ),
            )
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(error, fallback: context.l10n.realEstateLoadFailed);
      });
    }
  }

  Future<void> _openWorkspace() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RealEstateWorkspaceScreen()),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _openSaved() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RealEstateSavedListingsScreen()),
    );
    if (!mounted) return;
    await _load();
  }

  Future<void> _openFilters() async {
    final next = await showModalBottomSheet<RealEstateListingQuery>(
      context: context,
      isScrollControlled: true,
      builder: (_) => RealEstateFilterSheet(initialQuery: _query),
    );
    if (next == null || !mounted) return;
    _searchCtrl.text = next.search ?? '';
    setState(() => _query = next);
    await _load();
  }

  Future<void> _toggleSaved(RealEstateListingModel item) async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed || _savingBusy) return;
    setState(() => _savingBusy = true);
    try {
      final nextSaved = !item.isSaved;
      if (nextSaved) {
        await ref.read(realEstateApiProvider).saveListing(item.id);
        _savedIds.add(item.id);
      } else {
        await ref.read(realEstateApiProvider).unsaveListing(item.id);
        _savedIds.remove(item.id);
      }
      if (!mounted) return;
      setState(() {
        _items = _items
            .map(
              (entry) => entry.id == item.id
                  ? entry.copyWith(isSaved: nextSaved)
                  : entry,
            )
            .toList(growable: false);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            nextSaved
                ? context.l10n.realEstateSaved
                : context.l10n.realEstateUnsaved,
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: context.l10n.realEstateSaveFailed),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _savingBusy = false);
    }
  }

  void _applyQuickPreset({
    String? purpose,
    bool? furnished,
    bool featuredOnly = false,
    String? sort,
  }) {
    setState(() {
      _query = _query.copyWith(
        purpose: purpose,
        furnished: furnished,
        featuredOnly: featuredOnly,
        sort: sort ?? _query.sort,
      );
    });
    _load();
  }

  List<Widget> _activeFilterChips() {
    final l10n = context.l10n;
    final chips = <Widget>[];

    void addChip(String label, VoidCallback onDeleted) {
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: onDeleted,
        ),
      );
    }

    if ((_query.search ?? '').isNotEmpty) {
      addChip(_query.search!, () {
        _searchCtrl.clear();
        setState(() => _query = _query.copyWith(search: null));
        _load();
      });
    }
    if (_query.purpose != null) {
      addChip(purposeLabel(context, _query.purpose!), () {
        setState(() => _query = _query.copyWith(purpose: null));
        _load();
      });
    }
    if (_query.furnished != null) {
      addChip(
        _query.furnished! ? l10n.realEstateFurnished : l10n.realEstateUnfurnished,
        () {
          setState(() => _query = _query.copyWith(furnished: null));
          _load();
        },
      );
    }
    if ((_query.city ?? '').isNotEmpty) {
      addChip(_query.city!, () {
        setState(() => _query = _query.copyWith(city: null));
        _load();
      });
    }
    if ((_query.block ?? '').isNotEmpty) {
      addChip(_query.block!, () {
        setState(() => _query = _query.copyWith(block: null));
        _load();
      });
    }
    if (_query.featuredOnly) {
      addChip(l10n.realEstateFeaturedOnly, () {
        setState(() => _query = _query.copyWith(featuredOnly: false));
        _load();
      });
    }
    if (!_query.availableOnly) {
      addChip(l10n.commonAll, () {
        setState(() => _query = _query.copyWith(availableOnly: true));
        _load();
      });
    }
    return chips;
  }

  @override
  Widget build(BuildContext context) {
    final realEstateSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.realEstate, displayName: 'العقارات');
    if (realEstateSection.isBlocked) {
      return SectionUnavailableScreen(entry: realEstateSection);
    }
    final l10n = context.l10n;
    final activeFilterChips = _activeFilterChips();
    final isAuthed = ref.watch(authControllerProvider).isAuthed;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.realEstateMarketplaceTitle),
        actions: [
          if (isAuthed)
            IconButton(
              onPressed: _openSaved,
              icon: const Icon(Icons.favorite_border_rounded),
              tooltip: l10n.realEstateSavedTitle,
            ),
          IconButton(
            onPressed: _openWorkspace,
            icon: const Icon(Icons.business_center_outlined),
            tooltip: l10n.realEstateWorkspaceTitle,
          ),
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
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
                hintText: l10n.realEstateSearchHint,
                suffixIcon: IconButton(
                  onPressed: _openFilters,
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: l10n.commonFilters,
                ),
              ),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                ActionChip(
                  label: Text(l10n.realEstateSearchSectionNewest),
                  onPressed: () => _applyQuickPreset(sort: 'recent'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.realEstateSearchSectionSale),
                  onPressed: () => _applyQuickPreset(purpose: 'sale'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.realEstateSearchSectionRent),
                  onPressed: () => _applyQuickPreset(purpose: 'rent'),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.realEstateSearchSectionFurnished),
                  onPressed: () => _applyQuickPreset(furnished: true),
                ),
                const SizedBox(width: 8),
                ActionChip(
                  label: Text(l10n.realEstateSearchSectionFeatured),
                  onPressed: () => _applyQuickPreset(featuredOnly: true),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.realEstateFilterResults(_items.length),
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                DropdownButton<String>(
                  value: _query.sort,
                  items: [
                    DropdownMenuItem(
                      value: 'recent',
                      child: Text(l10n.realEstateNewest),
                    ),
                    DropdownMenuItem(
                      value: 'oldest',
                      child: Text(l10n.realEstateOldest),
                    ),
                    DropdownMenuItem(
                      value: 'price_low',
                      child: Text(l10n.realEstateLowestPrice),
                    ),
                    DropdownMenuItem(
                      value: 'price_high',
                      child: Text(l10n.realEstateHighestPrice),
                    ),
                    DropdownMenuItem(
                      value: 'most_viewed',
                      child: Text(l10n.realEstateMostViewed),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _query = _query.copyWith(sort: value));
                    _load();
                  },
                ),
              ],
            ),
          ),
          if (activeFilterChips.isNotEmpty)
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                child: Row(
                  children: activeFilterChips
                      .expand((chip) => [chip, const SizedBox(width: 8)])
                      .toList(growable: false),
                ),
              ),
            ),
          const SizedBox(height: 10),
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
                      children: [
                        const SizedBox(height: 140),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 28),
                            child: Text(
                              _activeFilterChips().isEmpty
                                  ? l10n.realEstateNoListings
                                  : l10n.realEstateNoFilterResults,
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      itemBuilder: (context, index) {
                        final item = _items[index];
                        return RealEstateListingCard(
                          listing: item,
                          onTap: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (_) => RealEstateListingDetailsScreen(
                                  listingId: item.id,
                                  initialListing: item,
                                ),
                              ),
                            );
                            if (mounted) {
                              await _load();
                            }
                          },
                          onToggleSaved: isAuthed ? () => _toggleSaved(item) : null,
                        );
                      },
                      separatorBuilder: (_, _) => const SizedBox(height: 14),
                      itemCount: _items.length,
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
