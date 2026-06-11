import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services_api.dart';
import '../models/service_models.dart';

class ServicesDiscoveryState {
  final bool loading;
  final bool loadingCategories;
  final String query;
  final int? categoryId;
  final int? subcategoryId;
  final String sort;
  final String? city;
  final String? area;
  final bool? homeService;
  final bool? emergency;
  final bool? offersOnly;
  final List<ServiceCategoryModel> categories;
  final List<ServiceOfferingModel> offerings;
  final String? error;

  const ServicesDiscoveryState({
    this.loading = false,
    this.loadingCategories = false,
    this.query = '',
    this.categoryId,
    this.subcategoryId,
    this.sort = 'newest',
    this.city,
    this.area,
    this.homeService,
    this.emergency,
    this.offersOnly,
    this.categories = const <ServiceCategoryModel>[],
    this.offerings = const <ServiceOfferingModel>[],
    this.error,
  });

  ServicesDiscoveryState copyWith({
    bool? loading,
    bool? loadingCategories,
    String? query,
    int? categoryId,
    bool clearCategory = false,
    int? subcategoryId,
    bool clearSubcategory = false,
    String? sort,
    String? city,
    bool clearCity = false,
    String? area,
    bool clearArea = false,
    bool? homeService,
    bool clearHomeService = false,
    bool? emergency,
    bool clearEmergency = false,
    bool? offersOnly,
    bool clearOffersOnly = false,
    List<ServiceCategoryModel>? categories,
    List<ServiceOfferingModel>? offerings,
    String? error,
    bool clearError = false,
  }) {
    return ServicesDiscoveryState(
      loading: loading ?? this.loading,
      loadingCategories: loadingCategories ?? this.loadingCategories,
      query: query ?? this.query,
      categoryId: clearCategory ? null : (categoryId ?? this.categoryId),
      subcategoryId: clearSubcategory
          ? null
          : (subcategoryId ?? this.subcategoryId),
      sort: sort ?? this.sort,
      city: clearCity ? null : (city ?? this.city),
      area: clearArea ? null : (area ?? this.area),
      homeService: clearHomeService ? null : (homeService ?? this.homeService),
      emergency: clearEmergency ? null : (emergency ?? this.emergency),
      offersOnly: clearOffersOnly ? null : (offersOnly ?? this.offersOnly),
      categories: categories ?? this.categories,
      offerings: offerings ?? this.offerings,
      error: clearError ? null : error,
    );
  }
}

final servicesDiscoveryControllerProvider =
    StateNotifierProvider<ServicesDiscoveryController, ServicesDiscoveryState>(
      (ref) => ServicesDiscoveryController(ref),
    );

class ServicesDiscoveryController
    extends StateNotifier<ServicesDiscoveryState> {
  final Ref ref;

  ServicesDiscoveryController(this.ref)
    : super(const ServicesDiscoveryState()) {
    loadCategories();
    search();
  }

  Future<void> loadCategories() async {
    state = state.copyWith(loadingCategories: true, clearError: true);
    try {
      final rows = await ref.read(servicesApiProvider).listPublicCategories();
      final categories = rows.map(ServiceCategoryModel.fromJson).toList();
      state = state.copyWith(
        loadingCategories: false,
        categories: categories,
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loadingCategories: false, error: '$e');
    }
  }

  Future<void> search({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(loading: true, clearError: true);
    }
    try {
      final rows = await ref
          .read(servicesApiProvider)
          .searchPublicOfferings(
            q: state.query.trim().isEmpty ? null : state.query.trim(),
            categoryId: state.categoryId,
            subcategoryId: state.subcategoryId,
            city: state.city,
            area: state.area,
            homeService: state.homeService,
            emergency: state.emergency,
            offersOnly: state.offersOnly,
            sort: state.sort,
          );
      state = state.copyWith(
        loading: false,
        offerings: rows.map(ServiceOfferingModel.fromJson).toList(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loading: false, error: '$e');
    }
  }

  void setQuery(String value) {
    state = state.copyWith(query: value, clearError: true);
  }

  Future<void> setCategory(int? value) async {
    state = state.copyWith(
      categoryId: value,
      clearCategory: value == null,
      clearSubcategory: true,
      clearError: true,
    );
    await search();
  }

  Future<void> setSubcategory(int? value) async {
    state = state.copyWith(
      subcategoryId: value,
      clearSubcategory: value == null,
      clearError: true,
    );
    await search();
  }

  Future<void> setSort(String value) async {
    state = state.copyWith(sort: value, clearError: true);
    await search();
  }

  Future<void> toggleHomeService() async {
    final current = state.homeService;
    state = state.copyWith(
      homeService: current == true ? null : true,
      clearHomeService: current == true,
    );
    await search();
  }

  Future<void> toggleEmergencyService() async {
    final current = state.emergency;
    state = state.copyWith(
      emergency: current == true ? null : true,
      clearEmergency: current == true,
    );
    await search();
  }

  Future<void> toggleOffersOnly() async {
    final current = state.offersOnly;
    state = state.copyWith(
      offersOnly: current == true ? null : true,
      clearOffersOnly: current == true,
    );
    await search();
  }

  Future<void> setCity(String? value) async {
    final normalized = value?.trim();
    state = state.copyWith(
      city: (normalized == null || normalized.isEmpty) ? null : normalized,
      clearCity: normalized == null || normalized.isEmpty,
    );
    await search();
  }

  Future<void> setArea(String? value) async {
    final normalized = value?.trim();
    state = state.copyWith(
      area: (normalized == null || normalized.isEmpty) ? null : normalized,
      clearArea: normalized == null || normalized.isEmpty,
    );
    await search();
  }
}
