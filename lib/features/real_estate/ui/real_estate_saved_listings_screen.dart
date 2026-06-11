import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../data/real_estate_api.dart';
import '../models/real_estate_models.dart';
import 'real_estate_listing_details_screen.dart';
import 'widgets/real_estate_listing_card.dart';

class RealEstateSavedListingsScreen extends ConsumerStatefulWidget {
  const RealEstateSavedListingsScreen({super.key});

  @override
  ConsumerState<RealEstateSavedListingsScreen> createState() =>
      _RealEstateSavedListingsScreenState();
}

class _RealEstateSavedListingsScreenState
    extends ConsumerState<RealEstateSavedListingsScreen> {
  bool _loading = true;
  String? _error;
  List<RealEstateListingModel> _items = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final raw = await ref.read(realEstateApiProvider).listSavedListings();
      if (!mounted) return;
      setState(() {
        _items = raw
            .map(RealEstateListingModel.fromJson)
            .toList(growable: false);
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          error,
          fallback: context.l10n.realEstateLoadFailed,
        );
      });
    }
  }

  Future<void> _toggleSaved(RealEstateListingModel item) async {
    try {
      await ref.read(realEstateApiProvider).unsaveListing(item.id);
      if (!mounted) return;
      setState(() => _items = _items.where((e) => e.id != item.id).toList());
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(context.l10n.realEstateUnsaved)));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(error, fallback: context.l10n.realEstateSaveFailed),
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.realEstateSavedTitle)),
      body: RefreshIndicator(
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
                      child: Column(
                        children: [
                          Text(
                            l10n.realEstateNoSaved,
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            l10n.realEstateSavedEmptyHint,
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              )
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  return RealEstateListingCard(
                    listing: item,
                    compact: true,
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
                    onToggleSaved: () => _toggleSaved(item),
                  );
                },
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemCount: _items.length,
              ),
      ),
    );
  }
}
