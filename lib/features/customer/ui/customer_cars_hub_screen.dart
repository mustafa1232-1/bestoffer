import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:simple_icons/simple_icons.dart';

import '../../auth/ui/merchants_list_screen.dart';
import '../../behavior/data/behavior_api.dart';
import '../data/car_catalog.dart';
import '../data/car_smart_recommendation.dart';

class CustomerCarsHubScreen extends ConsumerStatefulWidget {
  const CustomerCarsHubScreen({super.key});

  @override
  ConsumerState<CustomerCarsHubScreen> createState() =>
      _CustomerCarsHubScreenState();
}

class _CustomerCarsHubScreenState extends ConsumerState<CustomerCarsHubScreen> {
  String? _selectedBrand;
  String? _selectedModel;
  RangeValues? _selectedYearRange;
  String _condition = 'all';
  SmartCarCriteria? _smartCriteria;
  List<SmartCarRecommendation> _smartRecommendations = const [];
  bool _smartUsedRelaxedFilter = false;

  Future<void> _trackEvent({
    required String eventName,
    String? action,
    Map<String, dynamic>? metadata,
  }) async {
    await ref
        .read(behaviorApiProvider)
        .trackEvent(
          eventName: eventName,
          category: 'cars',
          action: action,
          metadata: metadata,
        );
  }

  List<String> get _brands => carBrandNames();
  List<String> get _models =>
      _selectedBrand == null ? const [] : carModelsForBrand(_selectedBrand!);

  String get _yearRangeLabel {
    if (_selectedYearRange == null) return 'اختر المدى الزمني';
    final from = _selectedYearRange!.start.round();
    final to = _selectedYearRange!.end.round();
    if (from == to) return '$from';
    return '$from - $to';
  }

  void _openSearch({required String title, required String query}) {
    unawaited(
      _trackEvent(
        eventName: 'cars.open_market_search',
        action: 'open_search',
        metadata: {'title': title, 'searchQuery': query},
      ),
    );
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MerchantsListScreen(
          initialType: 'market',
          initialSearchQuery: query,
          overrideTitle: title,
          compactCustomerMode: true,
        ),
      ),
    );
  }

  Future<T?> _showBlurOverlay<T>({required Widget child}) {
    return showGeneralDialog<T>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'dismiss',
      barrierColor: Colors.black.withValues(alpha: 0.28),
      transitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) {
        return SafeArea(
          child: Stack(
            children: [
              Positioned.fill(
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 7, sigmaY: 7),
                  child: Container(color: Colors.black.withValues(alpha: 0.10)),
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 12),
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(22),
                    clipBehavior: Clip.antiAlias,
                    child: child,
                  ),
                ),
              ),
            ],
          ),
        );
      },
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final fade = CurvedAnimation(parent: animation, curve: Curves.easeOut);
        final slide = Tween<Offset>(
          begin: const Offset(0, 0.06),
          end: Offset.zero,
        ).animate(fade);
        return FadeTransition(
          opacity: fade,
          child: SlideTransition(position: slide, child: child),
        );
      },
    );
  }

  Future<void> _pickBrand() async {
    final result = await _pickOptionFromList(
      title: 'اختر شركة السيارة',
      options: _brands,
      selectedValue: _selectedBrand,
      searchHint: 'ابحث عن شركة...',
      showBrandBadge: true,
    );
    if (!mounted) return;
    if (result == _selectedBrand) return;
    setState(() {
      _selectedBrand = result;
      _selectedModel = null;
    });
  }

  Future<void> _pickModel() async {
    if (_selectedBrand == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('اختر الشركة أولاً حتى تظهر الموديلات')),
      );
      return;
    }

    final result = await _pickOptionFromList(
      title: 'اختر موديل ${_selectedBrand!}',
      options: _models,
      selectedValue: _selectedModel,
      searchHint: 'ابحث عن موديل...',
    );
    if (!mounted) return;
    setState(() => _selectedModel = result);
  }

  Future<void> _pickYearRange() async {
    final currentYear = DateTime.now().year;
    const minYear = 1990;
    var range =
        _selectedYearRange ??
        RangeValues((currentYear - 6).toDouble(), currentYear.toDouble());

    final result = await _showBlurOverlay<RangeValues?>(
      child: StatefulBuilder(
        builder: (context, setBottomState) {
          return SizedBox(
            height: 380,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 46,
                      height: 5,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(999),
                        color: Colors.white.withValues(alpha: 0.25),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'اختر مدى سنة الصنع',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ActionChip(
                        label: const Text('آخر 3 سنوات'),
                        onPressed: () => setBottomState(
                          () => range = RangeValues(
                            (currentYear - 2).toDouble(),
                            currentYear.toDouble(),
                          ),
                        ),
                      ),
                      ActionChip(
                        label: const Text('آخر 5 سنوات'),
                        onPressed: () => setBottomState(
                          () => range = RangeValues(
                            (currentYear - 4).toDouble(),
                            currentYear.toDouble(),
                          ),
                        ),
                      ),
                      ActionChip(
                        label: const Text('آخر 10 سنوات'),
                        onPressed: () => setBottomState(
                          () => range = RangeValues(
                            (currentYear - 9).toDouble(),
                            currentYear.toDouble(),
                          ),
                        ),
                      ),
                      ActionChip(
                        label: const Text('إلغاء المدى'),
                        onPressed: () => Navigator.of(context).pop(null),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    '${range.start.round()}  \u2190  ${range.end.round()}',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  RangeSlider(
                    values: range,
                    min: minYear.toDouble(),
                    max: currentYear.toDouble(),
                    divisions: currentYear - minYear,
                    labels: RangeLabels(
                      range.start.round().toString(),
                      range.end.round().toString(),
                    ),
                    onChanged: (value) => setBottomState(() => range = value),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(range),
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('اعتماد المدى'),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );

    if (!mounted) return;
    setState(() => _selectedYearRange = result);
  }

  Future<String?> _pickOptionFromList({
    required String title,
    required List<String> options,
    required String searchHint,
    String? selectedValue,
    bool showBrandBadge = false,
  }) async {
    final queryCtrl = TextEditingController();
    var query = '';

    final picked = await _showBlurOverlay<String?>(
      child: StatefulBuilder(
        builder: (context, setBottomState) {
          final filtered = options
              .where((item) => item.toLowerCase().contains(query.toLowerCase()))
              .toList(growable: false);

          final onSurface = Theme.of(context).colorScheme.onSurface;

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.74,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: onSurface.withValues(alpha: 0.20),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(Icons.list_alt_rounded),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          title,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(null),
                        child: const Text('مسح'),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                  child: TextField(
                    controller: queryCtrl,
                    textDirection: TextDirection.rtl,
                    style: TextStyle(
                      color: onSurface,
                      fontWeight: FontWeight.w700,
                    ),
                    decoration: InputDecoration(
                      hintText: searchHint,
                      prefixIcon: const Icon(Icons.search_rounded),
                    ),
                    onChanged: (value) => setBottomState(() => query = value),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final active = item == selectedValue;
                      return ListTile(
                        leading: showBrandBadge
                            ? _BrandBadge(brand: item)
                            : null,
                        title: Text(
                          item,
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            color: onSurface,
                            fontWeight: active
                                ? FontWeight.w900
                                : FontWeight.w700,
                          ),
                        ),
                        trailing: active
                            ? const Icon(Icons.check_circle_rounded)
                            : const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                size: 14,
                              ),
                        onTap: () => Navigator.of(context).pop(item),
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    queryCtrl.dispose();
    return picked;
  }

  void _submitFilteredSearch() {
    final parts = <String>['سيارات'];
    if (_selectedBrand != null) parts.add('شركة ${_selectedBrand!}');
    if (_selectedModel != null) parts.add('موديل ${_selectedModel!}');
    if (_selectedYearRange != null) {
      final from = _selectedYearRange!.start.round();
      final to = _selectedYearRange!.end.round();
      if (from == to) {
        parts.add('سنة $from');
      } else {
        parts.add('من سنة $from إلى سنة $to');
      }
    }
    if (_condition == 'new') parts.add('جديدة');
    if (_condition == 'used') parts.add('مستعملة');
    final query = parts.join(' ');
    unawaited(
      _trackEvent(
        eventName: 'cars.filtered_search_submit',
        action: 'filtered_search',
        metadata: {
          'brand': _selectedBrand,
          'model': _selectedModel,
          'condition': _condition,
          'yearFrom': _selectedYearRange?.start.round(),
          'yearTo': _selectedYearRange?.end.round(),
          'searchQuery': query,
        },
      ),
    );
    _openSearch(title: 'نتائج بحث السيارات', query: query);
  }

  void _resetManualFilters() {
    setState(() {
      _selectedBrand = null;
      _selectedModel = null;
      _selectedYearRange = null;
      _condition = 'all';
    });
  }

  void _runSmartSearch(SmartCarCriteria criteria) {
    var results = getSmartCarRecommendations(criteria, limit: 6);
    var usedRelaxed = false;

    if (results.isEmpty) {
      final relaxedBudget = RangeDouble(
        math.max(5, criteria.budgetM.start - 8),
        math.min(250, criteria.budgetM.end + 8),
      );
      final relaxedCriteria = SmartCarCriteria(
        budgetM: relaxedBudget,
        bodyType: CarBodyType.any,
        usage: criteria.usage,
        condition: CarCondition.any,
        fuelPreference: FuelPreference.any,
        transmissionPref: TransmissionPref.any,
        priorityGoal: criteria.priorityGoal,
        minSeats: criteria.minSeats > 5 ? 5 : criteria.minSeats,
        freeText: '',
      );
      results = getSmartCarRecommendations(relaxedCriteria, limit: 6);
      usedRelaxed = results.isNotEmpty;
    }

    setState(() {
      _smartCriteria = criteria;
      _smartRecommendations = results;
      _smartUsedRelaxedFilter = usedRelaxed;
    });

    unawaited(
      _trackEvent(
        eventName: 'cars.smart_search_ui',
        action: 'smart_search',
        metadata: {
          'budgetMinM': criteria.budgetM.start,
          'budgetMaxM': criteria.budgetM.end,
          'usage': criteria.usage.name,
          'bodyType': criteria.bodyType.name,
          'condition': criteria.condition.name,
          'fuelPreference': criteria.fuelPreference.name,
          'transmissionPref': criteria.transmissionPref.name,
          'priority': criteria.priorityGoal.name,
          'minSeats': criteria.minSeats,
          'resultCount': results.length,
          'usedRelaxedFilter': usedRelaxed,
          'freeText': criteria.freeText,
        },
      ),
    );

    final messenger = ScaffoldMessenger.of(context);
    if (results.isEmpty) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'ما لقينا خيارات كافية بنفس الشروط. جرّب توسيع الميزانية أو تقليل القيود.',
          ),
        ),
      );
      return;
    }

    messenger.showSnackBar(
      SnackBar(
        content: Text(
          usedRelaxed
              ? 'وسعنا البحث شوي حتى طلعنا أفضل خيارات قريبة لاحتياجك.'
              : 'تم تجهيز ترشيحات ذكية مطابقة لاحتياجك.',
        ),
      ),
    );
  }

  Future<void> _openSmartFinder() async {
    final notesCtrl = TextEditingController();
    var budget = const RangeValues(20, 50);
    var bodyType = CarBodyType.any;
    var usage = CarUsage.personal;
    var condition = CarCondition.any;
    var fuelPreference = FuelPreference.any;
    var transmission = TransmissionPref.any;
    var priority = PriorityGoal.balanced;
    var minSeats = 4.0;

    final result = await _showBlurOverlay<SmartCarCriteria?>(
      child: StatefulBuilder(
        builder: (context, setBottomState) {
          Widget sectionTitle(String text) {
            return Align(
              alignment: Alignment.centerRight,
              child: Text(
                text,
                textDirection: TextDirection.rtl,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            );
          }

          return SizedBox(
            height: MediaQuery.of(context).size.height * 0.86,
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 46,
                  height: 5,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: Colors.white.withValues(alpha: 0.25),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      const Icon(Icons.psychology_alt_rounded, size: 20),
                      const SizedBox(width: 8),
                      const Expanded(
                        child: Text(
                          'دع التطبيق يبحث لك',
                          textDirection: TextDirection.rtl,
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close_rounded),
                      ),
                    ],
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      'جاوب بسرعة على كم سؤال، وبنعطيك أفضل سيارات حسب ميزانيتك واستخدامك.',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    children: [
                      sectionTitle('الميزانية (مليون IQD)'),
                      const SizedBox(height: 8),
                      Text(
                        '${budget.start.round()} - ${budget.end.round()} مليون',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                      RangeSlider(
                        values: budget,
                        min: 5,
                        max: 250,
                        divisions: 245,
                        labels: RangeLabels(
                          budget.start.round().toString(),
                          budget.end.round().toString(),
                        ),
                        onChanged: (value) {
                          setBottomState(() => budget = value);
                        },
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          ActionChip(
                            label: const Text('اقتصادي 10-25'),
                            onPressed: () => setBottomState(
                              () => budget = const RangeValues(10, 25),
                            ),
                          ),
                          ActionChip(
                            label: const Text('متوسط 25-60'),
                            onPressed: () => setBottomState(
                              () => budget = const RangeValues(25, 60),
                            ),
                          ),
                          ActionChip(
                            label: const Text('واسع 60-120'),
                            onPressed: () => setBottomState(
                              () => budget = const RangeValues(60, 120),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      sectionTitle('نوع السيارة (اختياري)'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CarBodyType.values
                            .map(
                              (value) => ChoiceChip(
                                label: Text(carBodyTypeLabel(value)),
                                selected: bodyType == value,
                                onSelected: (_) {
                                  setBottomState(() => bodyType = value);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      sectionTitle('طريقة الاستخدام'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CarUsage.values
                            .map(
                              (value) => ChoiceChip(
                                label: Text(carUsageLabel(value)),
                                selected: usage == value,
                                onSelected: (_) {
                                  setBottomState(() => usage = value);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      sectionTitle('الحالة المطلوبة'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: CarCondition.values
                            .map(
                              (value) => ChoiceChip(
                                label: Text(carConditionLabel(value)),
                                selected: condition == value,
                                onSelected: (_) {
                                  setBottomState(() => condition = value);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      sectionTitle('الأولوية الأهم بالنسبة الك'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: PriorityGoal.values
                            .map(
                              (value) => ChoiceChip(
                                label: Text(priorityGoalLabel(value)),
                                selected: priority == value,
                                onSelected: (_) {
                                  setBottomState(() => priority = value);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      sectionTitle('الوقود'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: FuelPreference.values
                            .map(
                              (value) => ChoiceChip(
                                label: Text(fuelPreferenceLabel(value)),
                                selected: fuelPreference == value,
                                onSelected: (_) {
                                  setBottomState(() => fuelPreference = value);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      sectionTitle('ناقل الحركة'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: TransmissionPref.values
                            .map(
                              (value) => ChoiceChip(
                                label: Text(transmissionLabel(value)),
                                selected: transmission == value,
                                onSelected: (_) {
                                  setBottomState(() => transmission = value);
                                },
                              ),
                            )
                            .toList(),
                      ),
                      const SizedBox(height: 14),
                      sectionTitle('الحد الأدنى للمقاعد'),
                      const SizedBox(height: 4),
                      Text(
                        '${minSeats.round()} مقاعد على الأقل',
                        textDirection: TextDirection.rtl,
                        textAlign: TextAlign.right,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Slider(
                        value: minSeats,
                        min: 2,
                        max: 8,
                        divisions: 6,
                        label: minSeats.round().toString(),
                        onChanged: (value) {
                          setBottomState(() => minSeats = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: notesCtrl,
                        textDirection: TextDirection.rtl,
                        maxLines: 2,
                        decoration: const InputDecoration(
                          hintText:
                              'تفاصيل إضافية (اختياري): موديل معين، اعتمادية، شكل... ',
                          prefixIcon: Icon(Icons.edit_note_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () {
                        Navigator.of(context).pop(
                          SmartCarCriteria(
                            budgetM: RangeDouble(budget.start, budget.end),
                            bodyType: bodyType,
                            usage: usage,
                            condition: condition,
                            fuelPreference: fuelPreference,
                            transmissionPref: transmission,
                            priorityGoal: priority,
                            minSeats: minSeats.round(),
                            freeText: notesCtrl.text.trim(),
                          ),
                        );
                      },
                      icon: const Icon(Icons.auto_awesome_rounded),
                      label: const Text('ابحث عن أفضل الخيارات'),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    notesCtrl.dispose();
    if (!mounted || result == null) return;
    _runSmartSearch(result);
  }

  void _applyRecommendationToFilters(SmartCarRecommendation recommendation) {
    setState(() {
      _selectedBrand = recommendation.spec.brand;
      _selectedModel = recommendation.spec.model;
      final condition = _smartCriteria?.condition ?? CarCondition.any;
      _condition = switch (condition) {
        CarCondition.newCar => 'new',
        CarCondition.used => 'used',
        CarCondition.any => 'all',
      };
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'تم تجهيز الفلاتر على ${recommendation.spec.fullName}. اضغط تطبيق الفلاتر للعرض.',
        ),
      ),
    );
  }

  void _openRecommendationSearch(SmartCarRecommendation recommendation) {
    final parts = <String>[
      'سيارات',
      recommendation.spec.brand,
      recommendation.spec.model,
    ];

    final condition = _smartCriteria?.condition ?? CarCondition.any;
    if (condition == CarCondition.newCar) parts.add('جديدة');
    if (condition == CarCondition.used) parts.add('مستعملة');

    _openSearch(
      title: 'عروض ${recommendation.spec.fullName}',
      query: parts.join(' '),
    );
  }

  bool get _isDefaultBrowseMode {
    return _smartCriteria == null &&
        _selectedBrand == null &&
        _selectedModel == null &&
        _selectedYearRange == null &&
        _condition == 'all';
  }

  List<_CarBrowseItem> get _allCarsForBrowsing {
    final items = <_CarBrowseItem>[];
    for (final brand in _brands) {
      for (final model in carModelsForBrand(brand)) {
        items.add(_CarBrowseItem(brand: brand, model: model));
      }
    }
    items.sort((a, b) {
      final brandCmp = a.brand.compareTo(b.brand);
      if (brandCmp != 0) return brandCmp;
      return a.model.compareTo(b.model);
    });
    return items;
  }

  void _openModelSearch({required String brand, required String model}) {
    _openSearch(title: '$brand $model', query: 'سيارات $brand $model');
  }

  @override
  Widget build(BuildContext context) {
    final allCars = _allCarsForBrowsing;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('سوق السيارات')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
          children: [
            const _CarsHeroBanner(),
            const SizedBox(height: 14),
            const _SectionHeader(
              title: 'البحث الذكي',
              subtitle: 'خل التطبيق يرشّح لك الأفضل حسب ميزانيتك واحتياجك',
            ),
            const SizedBox(height: 8),
            _FilterCard(
              title: 'دع التطبيق يبحث لك (ذكي)',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'جاوب على أسئلة سريعة عن الميزانية والاستخدام، وراح نرشح لك أفضل الخيارات مع أسباب واضحة.',
                    textDirection: TextDirection.rtl,
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _openSmartFinder,
                      icon: const Icon(Icons.psychology_alt_rounded),
                      label: const Text('ابدأ البحث الذكي'),
                    ),
                  ),
                ],
              ),
            ),
            if (_smartCriteria != null) ...[
              const SizedBox(height: 10),
              _FilterCard(
                title: _smartRecommendations.isEmpty
                    ? 'نتائج البحث الذكي'
                    : 'أفضل السيارات لك الآن',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      alignment: WrapAlignment.end,
                      children: [
                        _SmartSummaryChip(
                          icon: Icons.payments_rounded,
                          text:
                              '${_smartCriteria!.budgetM.start.round()}-${_smartCriteria!.budgetM.end.round()} مليون',
                        ),
                        _SmartSummaryChip(
                          icon: Icons.route_rounded,
                          text: carUsageLabel(_smartCriteria!.usage),
                        ),
                        _SmartSummaryChip(
                          icon: Icons.priority_high_rounded,
                          text: priorityGoalLabel(_smartCriteria!.priorityGoal),
                        ),
                        if (_smartCriteria!.bodyType != CarBodyType.any)
                          _SmartSummaryChip(
                            icon: Icons.category_rounded,
                            text: carBodyTypeLabel(_smartCriteria!.bodyType),
                          ),
                      ],
                    ),
                    if (_smartUsedRelaxedFilter) ...[
                      const SizedBox(height: 8),
                      const Text(
                        'ملاحظة: تم توسيع البحث قليلًا حتى نضمن ظهور نتائج مفيدة.',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: Color(0xFFFFD79D),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                    const SizedBox(height: 10),
                    if (_smartRecommendations.isEmpty)
                      const Text(
                        'حالياً ماكو سيارات مطابقة 100% للشروط. غيّر الميزانية أو خفف القيود وجرب مرة ثانية.',
                        textDirection: TextDirection.rtl,
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ..._smartRecommendations.asMap().entries.map(
                      (entry) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SmartRecommendationCard(
                          rank: entry.key + 1,
                          recommendation: entry.value,
                          onSearch: () =>
                              _openRecommendationSearch(entry.value),
                          onApplyFilters: () =>
                              _applyRecommendationToFilters(entry.value),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 14),
            const _SectionHeader(
              title: 'الفلاتر اليدوية',
              subtitle: 'اختيار دقيق بالشركة والموديل وسنة الصنع',
            ),
            const SizedBox(height: 8),
            _FilterCard(
              title: 'تحديد حسب الشركة والموديل وسنة الصنع',
              child: Column(
                children: [
                  _SelectField(
                    label: 'شركة السيارة',
                    value: _selectedBrand ?? 'اختر الشركة',
                    icon: Icons.business_rounded,
                    onTap: _pickBrand,
                    preview: _selectedBrand != null
                        ? _BrandBadge(brand: _selectedBrand!)
                        : null,
                  ),
                  const SizedBox(height: 10),
                  _SelectField(
                    label: 'موديل السيارة',
                    value: _selectedModel ?? 'اختر الموديل',
                    icon: Icons.directions_car_filled_rounded,
                    enabled: _selectedBrand != null,
                    onTap: _pickModel,
                  ),
                  const SizedBox(height: 10),
                  _SelectField(
                    label: 'سنة الصنع (من - إلى)',
                    value: _yearRangeLabel,
                    icon: Icons.calendar_month_rounded,
                    onTap: _pickYearRange,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _ConditionChip(
                          label: 'الكل',
                          selected: _condition == 'all',
                          onTap: () => setState(() => _condition = 'all'),
                        ),
                        _ConditionChip(
                          label: 'جديد',
                          selected: _condition == 'new',
                          onTap: () => setState(() => _condition = 'new'),
                        ),
                        _ConditionChip(
                          label: 'مستعمل',
                          selected: _condition == 'used',
                          onTap: () => setState(() => _condition = 'used'),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _resetManualFilters,
                          icon: const Icon(Icons.restart_alt_rounded, size: 18),
                          label: const Text('مسح الفلاتر'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _submitFilteredSearch,
                          icon: const Icon(Icons.manage_search_rounded),
                          label: const Text('تطبيق الفلاتر'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const _SectionHeader(
              title: 'اختصارات جاهزة',
              subtitle: 'وصول سريع للبحث المتكرر',
            ),
            const SizedBox(height: 8),
            _FilterCard(
              title: 'اختيارات سريعة',
              child: GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _carQuickQueries.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: 2.5,
                ),
                itemBuilder: (context, index) {
                  final item = _carQuickQueries[index];
                  return _QuickQueryTile(
                    title: item.title,
                    icon: item.icon,
                    onTap: () =>
                        _openSearch(title: item.title, query: item.query),
                  );
                },
              ),
            ),
            if (_isDefaultBrowseMode) ...[
              const SizedBox(height: 14),
              const _SectionHeader(
                title: 'تصفح كل السيارات',
                subtitle: 'ما اخترت طريقة بحث، فهذه كل السيارات للتصفح المباشر',
              ),
              const SizedBox(height: 8),
              _FilterCard(
                title: 'كل السيارات المتاحة',
                child: SizedBox(
                  height: 360,
                  child: ListView.separated(
                    itemCount: allCars.length,
                    separatorBuilder: (context, index) => Divider(
                      height: 1,
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                    itemBuilder: (context, index) {
                      final item = allCars[index];
                      return ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: _BrandBadge(brand: item.brand),
                        title: Text(
                          item.model,
                          style: const TextStyle(fontWeight: FontWeight.w900),
                        ),
                        subtitle: Text(
                          item.brand,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.70),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        trailing: TextButton(
                          onPressed: () => _openModelSearch(
                            brand: item.brand,
                            model: item.model,
                          ),
                          child: const Text('عرض'),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonalIcon(
                  onPressed: () =>
                      _openSearch(title: 'سوق السيارات', query: 'سيارات'),
                  icon: const Icon(Icons.grid_view_rounded),
                  label: const Text('عرض النتائج الكاملة كسوق'),
                ),
              ),
            ],
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

class _CarsHeroBanner extends StatefulWidget {
  const _CarsHeroBanner();

  @override
  State<_CarsHeroBanner> createState() => _CarsHeroBannerState();
}

class _CarsHeroBannerState extends State<_CarsHeroBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = _controller.value;
        final iconShift = math.sin(p * math.pi * 2) * 6;
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [Color(0xFF2E5D86), Color(0xFF1B3C59)],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Transform.translate(
                offset: Offset(iconShift, 0),
                child: const Icon(Icons.directions_car_rounded, size: 42),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: const [
                    Text(
                      'سوق سيارات متكامل',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'اختيارات واسعة مع بحث ذكي بالشركة والموديل والسنة والحالة.',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String subtitle;

  const _SectionHeader({required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          title,
          textDirection: TextDirection.rtl,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16.5),
        ),
        const SizedBox(height: 2),
        Text(
          subtitle,
          textDirection: TextDirection.rtl,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.74),
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
          ),
        ),
      ],
    );
  }
}

class _FilterCard extends StatelessWidget {
  final String title;
  final Widget child;

  const _FilterCard({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _QuickQueryTile extends StatelessWidget {
  final String title;
  final IconData icon;
  final VoidCallback onTap;

  const _QuickQueryTile({
    required this.title,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, size: 16),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  textDirection: TextDirection.rtl,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SelectField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;
  final Widget? preview;

  const _SelectField({
    required this.label,
    required this.value,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.preview,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: enabled ? onTap : null,
        child: Ink(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            color: Colors.white.withValues(alpha: 0.05),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      label,
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      value,
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
              ),
              if (preview != null) ...[const SizedBox(width: 8), preview!],
              const Icon(Icons.keyboard_arrow_down_rounded),
            ],
          ),
        ),
      ),
    );
  }
}

class _ConditionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ConditionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(
        context,
      ).colorScheme.primary.withValues(alpha: 0.25),
      side: BorderSide(color: Colors.white.withValues(alpha: 0.20)),
    );
  }
}

class _SmartSummaryChip extends StatelessWidget {
  final IconData icon;
  final String text;

  const _SmartSummaryChip({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withValues(alpha: 0.07),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        textDirection: TextDirection.rtl,
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 6),
          Text(
            text,
            textDirection: TextDirection.rtl,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _SmartRecommendationCard extends StatelessWidget {
  final int rank;
  final SmartCarRecommendation recommendation;
  final VoidCallback onSearch;
  final VoidCallback onApplyFilters;

  const _SmartRecommendationCard({
    required this.rank,
    required this.recommendation,
    required this.onSearch,
    required this.onApplyFilters,
  });

  @override
  Widget build(BuildContext context) {
    final spec = recommendation.spec;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.17)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Row(
            textDirection: TextDirection.rtl,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BrandBadge(brand: spec.brand),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$rank) ${spec.fullName}',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${recommendation.matchedPrice.min} - ${recommendation.matchedPrice.max} مليون IQD',
                      textDirection: TextDirection.rtl,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: const Color(0xFF1D4E73),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.30),
                  ),
                ),
                child: Text(
                  'ذكاء ${recommendation.score}',
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.end,
            children: [
              _SmartSummaryChip(
                icon: Icons.airline_seat_recline_normal_rounded,
                text: '${spec.seats} مقاعد',
              ),
              _SmartSummaryChip(
                icon: Icons.local_gas_station_rounded,
                text: spec.isElectric
                    ? 'كهربائي'
                    : (spec.hasHybrid ? 'هايبرد متوفر' : 'بنزين'),
              ),
              _SmartSummaryChip(
                icon: Icons.shield_rounded,
                text: 'اعتمادية ${spec.reliability}/10',
              ),
            ],
          ),
          const SizedBox(height: 8),
          ...recommendation.reasons
              .take(3)
              .map(
                (reason) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    '• $reason',
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
              ),
          const SizedBox(height: 8),
          Row(
            textDirection: TextDirection.rtl,
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: onApplyFilters,
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('تعبئة الفلاتر'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSearch,
                  icon: const Icon(Icons.search_rounded, size: 18),
                  label: const Text('بحث عن عروض'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BrandBadge extends StatelessWidget {
  final String brand;

  const _BrandBadge({required this.brand});

  static const Map<String, IconData> _brandIcons = {
    'toyota': SimpleIcons.toyota,
    'nissan': SimpleIcons.nissan,
    'hyundai': SimpleIcons.hyundai,
    'kia': SimpleIcons.kia,
    'chevrolet': SimpleIcons.chevrolet,
    'ford': SimpleIcons.ford,
    'honda': SimpleIcons.honda,
    'mazda': SimpleIcons.mazda,
    'mitsubishi': SimpleIcons.mitsubishi,
    'suzuki': SimpleIcons.suzuki,
    'volkswagen': SimpleIcons.volkswagen,
    'bmw': SimpleIcons.bmw,
    'mercedes-benz': SimpleIcons.mercedes,
    'audi': SimpleIcons.audi,
    'renault': SimpleIcons.renault,
    'peugeot': SimpleIcons.peugeot,
    'skoda': SimpleIcons.skoda,
    'seat': SimpleIcons.seat,
    'fiat': SimpleIcons.fiat,
    'jeep': SimpleIcons.jeep,
    'cadillac': SimpleIcons.cadillac,
    'subaru': SimpleIcons.subaru,
    'volvo': SimpleIcons.volvo,
    'porsche': SimpleIcons.porsche,
    'land rover': SimpleIcons.landrover,
    'jaguar': SimpleIcons.jaguar,
    'tesla': SimpleIcons.tesla,
    'mg': SimpleIcons.mg,
    'infiniti': SimpleIcons.infiniti,
    'acura': SimpleIcons.acura,
    'alfa romeo': SimpleIcons.alfaromeo,
  };

  IconData? _iconData() => _brandIcons[brand.trim().toLowerCase()];

  Widget _fallbackMonogram() {
    final text = _abbr(brand);
    final color = _brandColor(brand);
    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            color.withValues(alpha: 0.95),
            color.withValues(alpha: 0.65),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.40)),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w900,
          fontSize: 10.5,
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  String _abbr(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((p) => p.isNotEmpty)
        .toList(growable: false);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) {
      final single = parts.first.toUpperCase();
      return single.length <= 3 ? single : single.substring(0, 3);
    }
    return parts.take(2).map((p) => p[0].toUpperCase()).join();
  }

  Color _brandColor(String value) {
    final hash = value.hashCode.abs();
    final hue = (hash % 360).toDouble();
    return HSLColor.fromAHSL(1, hue, 0.55, 0.52).toColor();
  }

  @override
  Widget build(BuildContext context) {
    final iconData = _iconData();
    if (iconData == null) return _fallbackMonogram();

    return Container(
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.white,
        border: Border.all(color: Colors.white.withValues(alpha: 0.50)),
      ),
      child: Icon(iconData, size: 18, color: const Color(0xFF101C2E)),
    );
  }
}

class _CarQuickQuery {
  final String title;
  final String query;
  final IconData icon;

  const _CarQuickQuery({
    required this.title,
    required this.query,
    required this.icon,
  });
}

class _CarBrowseItem {
  final String brand;
  final String model;

  const _CarBrowseItem({required this.brand, required this.model});
}

const _carQuickQueries = <_CarQuickQuery>[
  _CarQuickQuery(
    title: 'سيارات جديدة',
    query: 'سيارات جديدة',
    icon: Icons.new_releases_rounded,
  ),
  _CarQuickQuery(
    title: 'سيارات مستعملة',
    query: 'سيارات مستعملة',
    icon: Icons.history_rounded,
  ),
  _CarQuickQuery(
    title: 'سيارات اقتصادية',
    query: 'سيارات اقتصادية قليلة الاستهلاك',
    icon: Icons.savings_rounded,
  ),
  _CarQuickQuery(
    title: 'سيارات عائلية',
    query: 'سيارات عائلية 7 مقاعد',
    icon: Icons.family_restroom_rounded,
  ),
  _CarQuickQuery(
    title: 'SUV',
    query: 'سيارات SUV',
    icon: Icons.airport_shuttle_rounded,
  ),
  _CarQuickQuery(
    title: 'موديلات حديثة',
    query: 'سيارات 2024 2025 2026',
    icon: Icons.auto_awesome_rounded,
  ),
];
