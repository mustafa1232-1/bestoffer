import 'package:flutter/material.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../data/car_catalog.dart';
import '../models/car_listing_model.dart';
import 'widgets/customer_car_listing_card.dart';

class CustomerCarsFilterSheet extends StatefulWidget {
  final CarListingQuery initialQuery;
  final List<String> brands;

  const CustomerCarsFilterSheet({
    super.key,
    required this.initialQuery,
    required this.brands,
  });

  @override
  State<CustomerCarsFilterSheet> createState() =>
      _CustomerCarsFilterSheetState();
}

class _CustomerCarsFilterSheetState extends State<CustomerCarsFilterSheet> {
  late String? _brand;
  late String? _model;
  late String? _condition;
  late String? _bodyType;
  late String _sort;
  late final TextEditingController _searchCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _minPriceCtrl;
  late final TextEditingController _maxPriceCtrl;

  List<String> get _brands =>
      widget.brands.isNotEmpty ? widget.brands : carBrandNames();

  List<String> get _models {
    final brand = _brand;
    if (brand == null || brand.isEmpty) return const [];
    return carModelsForBrand(brand);
  }

  @override
  void initState() {
    super.initState();
    final query = widget.initialQuery;
    _brand = query.brand;
    _model = query.model;
    _condition = query.condition;
    _bodyType = query.bodyType;
    _sort = query.sort;
    _searchCtrl = TextEditingController(text: query.search ?? '');
    _cityCtrl = TextEditingController(text: query.city ?? '');
    _minPriceCtrl = TextEditingController(
      text: query.minPrice == null ? '' : query.minPrice!.round().toString(),
    );
    _maxPriceCtrl = TextEditingController(
      text: query.maxPrice == null ? '' : query.maxPrice!.round().toString(),
    );
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _cityCtrl.dispose();
    _minPriceCtrl.dispose();
    _maxPriceCtrl.dispose();
    super.dispose();
  }

  void _reset() {
    Navigator.of(context).pop(const CarListingQuery());
  }

  void _apply() {
    double? parseDoubleOrNull(String value) {
      final text = value.trim();
      if (text.isEmpty) return null;
      return double.tryParse(text);
    }

    Navigator.of(context).pop(
      CarListingQuery(
        brand: _brand,
        model: _model,
        search: _searchCtrl.text.trim().isEmpty
            ? null
            : _searchCtrl.text.trim(),
        city: _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        condition: _condition,
        bodyType: _bodyType,
        minPrice: parseDoubleOrNull(_minPriceCtrl.text),
        maxPrice: parseDoubleOrNull(_maxPriceCtrl.text),
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
          initialChildSize: 0.82,
          minChildSize: 0.56,
          maxChildSize: 0.95,
          builder: (context, controller) {
            return Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
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
                    l10n.carsFilterTitle,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.commonSearch),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _searchCtrl,
                    decoration: InputDecoration(hintText: l10n.carsSearchHint),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.carsBrand),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: _brand,
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.commonAll),
                      ),
                      ..._brands.map(
                        (brand) => DropdownMenuItem<String?>(
                          value: brand,
                          child: Text(brand),
                        ),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _brand = value;
                        if (value == null || !_models.contains(_model)) {
                          _model = null;
                        }
                      });
                    },
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.carsModel),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: _models.contains(_model) ? _model : null,
                    items: [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text(l10n.commonAll),
                      ),
                      ..._models.map(
                        (model) => DropdownMenuItem<String?>(
                          value: model,
                          child: Text(model),
                        ),
                      ),
                    ],
                    onChanged: _brand == null
                        ? null
                        : (value) => setState(() => _model = value),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.carsCity),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _cityCtrl,
                    decoration: InputDecoration(hintText: l10n.carsCity),
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.carsCondition),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.commonAll),
                        selected: _condition == null,
                        onSelected: (_) => setState(() => _condition = null),
                      ),
                      ChoiceChip(
                        label: Text(l10n.carsConditionNew),
                        selected: _condition == 'new',
                        onSelected: (_) => setState(() => _condition = 'new'),
                      ),
                      ChoiceChip(
                        label: Text(l10n.carsConditionUsed),
                        selected: _condition == 'used',
                        onSelected: (_) => setState(() => _condition = 'used'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.carsBodyType),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: Text(l10n.commonAll),
                        selected: _bodyType == null,
                        onSelected: (_) => setState(() => _bodyType = null),
                      ),
                      for (final value in const [
                        'sedan',
                        'suv',
                        'crossover',
                        'hatchback',
                        'pickup',
                        'van',
                      ])
                        ChoiceChip(
                          label: Text(carBodyTypeLabel(context, value)),
                          selected: _bodyType == value,
                          onSelected: (_) => setState(() => _bodyType = value),
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
                          decoration: InputDecoration(
                            labelText: l10n.carsMinPrice,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _maxPriceCtrl,
                          keyboardType: TextInputType.number,
                          textDirection: TextDirection.ltr,
                          decoration: InputDecoration(
                            labelText: l10n.carsMaxPrice,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _SectionTitle(label: l10n.realEstateFilterSort),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String>(
                    initialValue: _sort,
                    items: [
                      DropdownMenuItem(
                        value: 'recent',
                        child: Text(l10n.carsSortRecent),
                      ),
                      DropdownMenuItem(
                        value: 'oldest',
                        child: Text(l10n.carsSortOldest),
                      ),
                      DropdownMenuItem(
                        value: 'price_low',
                        child: Text(l10n.carsSortPriceLow),
                      ),
                      DropdownMenuItem(
                        value: 'price_high',
                        child: Text(l10n.carsSortPriceHigh),
                      ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setState(() => _sort = value);
                      }
                    },
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
      style: Theme.of(
        context,
      ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
    );
  }
}
