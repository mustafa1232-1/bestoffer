import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../models/real_estate_models.dart';
import 'widgets/real_estate_listing_card.dart';

class RealEstateFilterSheet extends StatefulWidget {
  final RealEstateListingQuery initialQuery;

  const RealEstateFilterSheet({super.key, required this.initialQuery});

  @override
  State<RealEstateFilterSheet> createState() => _RealEstateFilterSheetState();
}

class _RealEstateFilterSheetState extends State<RealEstateFilterSheet> {
  late String? _purpose;
  late bool? _furnished;
  late bool _availableOnly;
  late bool _featuredOnly;
  late String? _bankSettlementMode;
  late String? _paymentMethod;
  late String _sort;
  late final TextEditingController _searchCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _blockCtrl;
  late final TextEditingController _minPriceCtrl;
  late final TextEditingController _maxPriceCtrl;
  late final TextEditingController _minAreaCtrl;
  late final TextEditingController _maxAreaCtrl;
  late final TextEditingController _roomsCtrl;
  late final TextEditingController _bathroomsCtrl;
  late final TextEditingController _floorMinCtrl;
  late final TextEditingController _floorMaxCtrl;

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    _purpose = query.purpose;
    _furnished = query.furnished;
    _availableOnly = query.availableOnly;
    _featuredOnly = query.featuredOnly;
    _bankSettlementMode = query.bankSettlementMode;
    _paymentMethod = query.paymentMethod;
    _sort = query.sort;
    _searchCtrl = TextEditingController(text: query.search ?? '');
    _cityCtrl = TextEditingController(text: query.city ?? '');
    _blockCtrl = TextEditingController(text: query.block ?? '');
    _minPriceCtrl = TextEditingController(
      text: query.minPrice == null ? '' : query.minPrice!.round().toString(),
    );
    _maxPriceCtrl = TextEditingController(
      text: query.maxPrice == null ? '' : query.maxPrice!.round().toString(),
    );
    _minAreaCtrl = TextEditingController(
      text: query.areaMin == null ? '' : query.areaMin!.toString(),
    );
    _maxAreaCtrl = TextEditingController(
      text: query.areaMax == null ? '' : query.areaMax!.toString(),
    );
    _roomsCtrl = TextEditingController(
      text: query.roomsCount == null ? '' : query.roomsCount!.toString(),
    );
    _bathroomsCtrl = TextEditingController(
      text: query.bathroomsCount == null ? '' : query.bathroomsCount!.toString(),
    );
    _floorMinCtrl = TextEditingController(
      text: query.floorMin == null ? '' : query.floorMin!.toString(),
    );
    _floorMaxCtrl = TextEditingController(
      text: query.floorMax == null ? '' : query.floorMax!.toString(),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _cityCtrl.dispose();
    _blockCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    _minAreaCtrl.dispose();
    _maxAreaCtrl.dispose();
    _roomsCtrl.dispose();
    _bathroomsCtrl.dispose();
    _floorMinCtrl.dispose();
    _floorMaxCtrl.dispose();
    super.dispose();
  }

  void _reset() {
    Navigator.of(context).pop(const RealEstateListingQuery());
  }

  void _apply() {
    double? parseDoubleOrNull(String value) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return double.tryParse(text);
    }

    int? parseIntOrNull(String value) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return int.tryParse(text);
    }

    Navigator.of(context).pop(
      RealEstateListingQuery(
        purpose: _purpose,
        search: _searchCtrl.text.trim().isEmpty ? null : _searchCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        block: _blockCtrl.text.trim().isEmpty ? null : _blockCtrl.text.trim(),
        areaMin: parseIntOrNull(_minAreaCtrl.text),
        areaMax: parseIntOrNull(_maxAreaCtrl.text),
        furnished: _furnished,
        availableOnly: _availableOnly,
        featuredOnly: _featuredOnly,
        bankSettlementMode: _bankSettlementMode,
        paymentMethod: _paymentMethod,
        minPrice: parseDoubleOrNull(_minPriceCtrl.text),
        maxPrice: parseDoubleOrNull(_maxPriceCtrl.text),
        roomsCount: parseIntOrNull(_roomsCtrl.text),
        bathroomsCount: parseIntOrNull(_bathroomsCtrl.text),
        floorMin: parseIntOrNull(_floorMinCtrl.text),
        floorMax: parseIntOrNull(_floorMaxCtrl.text),
        sort: _sort,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.88,
          minChildSize: 0.58,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: ListView(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                children: [
                  Center(
                    child: Container(
                      width: 44,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    l10n.realEstateFilterTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.commonSearch),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(hintText: l10n.realEstateSearchHint),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstatePurposeLabel),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.realEstateFilterPurposeAll),
                        selected: _purpose == null,
                        onSelected: (_) => setState(() => _purpose = null),
                      ),
                      ChoiceChip(
                        label: Text(l10n.realEstateSale),
                        selected: _purpose == 'sale',
                        onSelected: (_) => setState(() => _purpose = 'sale'),
                      ),
                      ChoiceChip(
                        label: Text(l10n.realEstateRent),
                        selected: _purpose == 'rent',
                        onSelected: (_) => setState(() => _purpose = 'rent'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstateAllFurnishing),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.commonAll),
                        selected: _furnished == null,
                        onSelected: (_) => setState(() => _furnished = null),
                      ),
                      ChoiceChip(
                        label: Text(l10n.realEstateFurnished),
                        selected: _furnished == true,
                        onSelected: (_) => setState(() => _furnished = true),
                      ),
                      ChoiceChip(
                        label: Text(l10n.realEstateUnfurnished),
                        selected: _furnished == false,
                        onSelected: (_) => setState(() => _furnished = false),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstatePriceRange),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minPriceCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: l10n.realEstateMinPrice),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: l10n.realEstateMaxPrice),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstateAreaRange),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _minAreaCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: l10n.realEstateMinArea),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxAreaCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(labelText: l10n.realEstateMaxArea),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstatePaymentMethod),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.commonAll),
                        selected: _paymentMethod == null,
                        onSelected: (_) => setState(() => _paymentMethod = null),
                      ),
                      ChoiceChip(
                        label: Text(paymentMethodLabel(context, 'cash')),
                        selected: _paymentMethod == 'cash',
                        onSelected: (_) => setState(() => _paymentMethod = 'cash'),
                      ),
                      ChoiceChip(
                        label: Text(paymentMethodLabel(context, 'installments')),
                        selected: _paymentMethod == 'installments',
                        onSelected: (_) =>
                            setState(() => _paymentMethod = 'installments'),
                      ),
                      ChoiceChip(
                        label: Text(paymentMethodLabel(context, 'negotiable')),
                        selected: _paymentMethod == 'negotiable',
                        onSelected: (_) =>
                            setState(() => _paymentMethod = 'negotiable'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstateSettlementMode),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.commonAll),
                        selected: _bankSettlementMode == null,
                        onSelected: (_) => setState(() => _bankSettlementMode = null),
                      ),
                      ChoiceChip(
                        label: Text(settlementModeLabel(context, 'none')),
                        selected: _bankSettlementMode == 'none',
                        onSelected: (_) => setState(() => _bankSettlementMode = 'none'),
                      ),
                      ChoiceChip(
                        label: Text(settlementModeLabel(context, 'partial')),
                        selected: _bankSettlementMode == 'partial',
                        onSelected: (_) =>
                            setState(() => _bankSettlementMode = 'partial'),
                      ),
                      ChoiceChip(
                        label: Text(settlementModeLabel(context, 'full')),
                        selected: _bankSettlementMode == 'full',
                        onSelected: (_) => setState(() => _bankSettlementMode = 'full'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstateLocation),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _cityCtrl,
                          decoration: InputDecoration(labelText: l10n.realEstateCity),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _blockCtrl,
                          decoration: InputDecoration(labelText: l10n.realEstateBlock),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstateSpecsStep),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _roomsCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: l10n.realEstateRoomsAtLeast,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _bathroomsCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: l10n.realEstateBathroomsAtLeast,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _floorMinCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: l10n.realEstateFloorAtLeast,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _floorMaxCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: l10n.realEstateFloorAtMost,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _availableOnly,
                    onChanged: (value) => setState(() => _availableOnly = value),
                    title: Text(l10n.realEstateOnlyAvailable),
                    subtitle: Text(l10n.realEstateAvailableOnlyHint),
                  ),
                  SwitchListTile.adaptive(
                    contentPadding: EdgeInsets.zero,
                    value: _featuredOnly,
                    onChanged: (value) => setState(() => _featuredOnly = value),
                    title: Text(l10n.realEstateFeaturedOnly),
                    subtitle: Text(l10n.realEstateFeaturedOnlyHint),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstateFilterSort),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _sort,
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
                    onChanged: (value) => setState(() => _sort = value ?? 'recent'),
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: _reset,
                          child: Text(l10n.commonReset),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: _apply,
                          child: Text(l10n.commonApply),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String label;

  const _SectionTitle({required this.label});

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: Theme.of(context).textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w900,
      ),
    );
  }
}
