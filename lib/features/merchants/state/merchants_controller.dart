import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../data/merchants_api.dart';
import '../models/merchant_model.dart';
import '../models/store_activity_model.dart';

final merchantsApiProvider = Provider<MerchantsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return MerchantsApi(dio);
});

final merchantsControllerProvider =
    StateNotifierProvider<MerchantsController, AsyncValue<List<MerchantModel>>>(
      (ref) => MerchantsController(ref),
    );

class MerchantsController
    extends StateNotifier<AsyncValue<List<MerchantModel>>> {
  final Ref ref;
  String? _lastRequestKey;
  String? _inFlightRequestKey;
  Future<void>? _inFlight;
  int _loadGeneration = 0;

  MerchantsController(this.ref) : super(const AsyncValue.loading());

  Future<void> load({String? type, String? search, bool force = false}) {
    return _performLoad(type: type, search: search, force: force);
  }

  Future<void> loadWithFilters({
    String? type,
    String? search,
    String? activityType,
    String? discoverySubcategory,
    String? department,
    bool force = false,
  }) async {
    if ((activityType == null || activityType.trim().isEmpty) &&
        (discoverySubcategory == null || discoverySubcategory.trim().isEmpty) &&
        (department == null || department.trim().isEmpty)) {
      return load(type: type, search: search, force: force);
    }
    return _performLoad(
      type: type,
      search: search,
      activityType: activityType,
      discoverySubcategory: discoverySubcategory,
      department: department,
      force: force,
    );
  }

  Future<void> _performLoad({
    String? type,
    String? search,
    String? activityType,
    String? discoverySubcategory,
    String? department,
    bool force = false,
  }) async {
    final requestedType = _normalizeMerchantType(type);
    final requestedActivity = _normalizeActivityType(activityType);
    final requestedDiscovery = _normalizeDiscovery(discoverySubcategory);
    final departmentRaw = department?.trim().toLowerCase();
    final requestedDepartment =
        departmentRaw == 'men' || departmentRaw == 'women'
        ? departmentRaw
        : null;
    final normalizedSearch = search?.trim().toLowerCase();
    final requestKey = [
      requestedType ?? '',
      requestedActivity ?? '',
      requestedDiscovery ?? '',
      requestedDepartment ?? '',
      normalizedSearch ?? '',
    ].join('|');

    final hasLoadedCurrent = _lastRequestKey == requestKey && state.hasValue;
    if (!force && hasLoadedCurrent) return;
    if (!force && _inFlight != null && _inFlightRequestKey == requestKey) {
      return _inFlight!;
    }

    final generation = ++_loadGeneration;
    _inFlightRequestKey = requestKey;
    final future = () async {
      if (!state.hasValue) {
        state = const AsyncValue.loading();
      }

      try {
        final api = ref.read(merchantsApiProvider);
        final primaryList = await api.list(
          type: requestedType,
          search: search,
          activityType: requestedActivity,
          discoverySubcategory: requestedDiscovery,
          department: requestedDepartment,
        );
        final merchants = _parseMerchants(primaryList);

        if (generation == _loadGeneration) {
          _lastRequestKey = requestKey;
          state = AsyncValue.data(merchants);
        }
      } catch (error, stackTrace) {
        if (generation == _loadGeneration) {
          state = AsyncValue.error(error, stackTrace);
        }
      }
    }();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
        _inFlightRequestKey = null;
      }
    });
  }

  List<MerchantModel> _parseMerchants(List<dynamic> raw) {
    final out = <MerchantModel>[];
    for (final item in raw) {
      if (item is! Map) continue;
      try {
        out.add(MerchantModel.fromJson(Map<String, dynamic>.from(item)));
      } catch (_) {
        // Skip malformed rows instead of failing the whole list.
      }
    }
    return out;
  }

  String? _normalizeMerchantType(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    if (value.isEmpty) return null;

    if (value == 'restaurant' || value == 'restaurants') return 'restaurant';
    if (value == 'market' || value == 'markets') return 'market';

    if ({
      'food',
      'cafe',
      'coffee',
      'bakery',
      'sweets',
      'dessert',
      'pastry',
    }.contains(value)) {
      return 'restaurant';
    }

    if ({
      'store',
      'shop',
      'grocery',
      'supermarket',
      'pharmacy',
      'electronics',
      'fashion',
      'cars',
      'car',
      'home',
    }.contains(value)) {
      return 'market';
    }

    return null;
  }

  String? _normalizeActivityType(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    return value.isEmpty ? null : value;
  }

  String? _normalizeDiscovery(String? raw) {
    if (raw == null) return null;
    final value = raw.trim().toLowerCase();
    return value.isEmpty ? null : value;
  }

  Future<List<StoreActivityModel>> listActivities() async {
    try {
      final raw = await ref.read(merchantsApiProvider).listActivities();
      final items = raw
          .whereType<Map>()
          .map((e) => StoreActivityModel.fromJson(Map<String, dynamic>.from(e)))
          .toList();
      if (items.isNotEmpty) return items;
    } catch (_) {
      // Fall back to built-in registry to keep onboarding/discovery usable
      // even when the activity endpoint is temporarily unavailable.
    }
    return _fallbackStoreActivities;
  }

  Future<List<StoreDiscoveryOptionModel>> listDiscoveryOptions({
    required String activityType,
  }) async {
    final normalized = _normalizeActivityType(activityType) ?? '';
    try {
      final raw = await ref
          .read(merchantsApiProvider)
          .listDiscoveryOptions(activityType: activityType);
      final items = raw
          .whereType<Map>()
          .map(
            (e) => StoreDiscoveryOptionModel.fromJson(
              Map<String, dynamic>.from(e),
            ),
          )
          .toList();
      if (items.isNotEmpty) return items;
    } catch (_) {
      // Keep local fallback below.
    }
    return _fallbackDiscoveryOptions[normalized] ??
        const <StoreDiscoveryOptionModel>[];
  }

  Future<MerchantModel> addMerchant({
    required String name,
    required String type,
    String? activityType,
    String? department,
    String? discoverySubcategory,
    List<String>? discoverySubcategories,
    bool? discoverySelectAll,
    required String description,
    required String phone,
    required String imageUrl,
    Map<String, dynamic>? serviceFlags,
    List<String>? badges,
    bool? supportsChat,
    bool? supportsAttachments,
    bool? supportsPharmacyWorkflow,
    LocalImageFile? merchantImageFile,
    LocalImageFile? ownerImageFile,
    int? ownerUserId,
    Map<String, dynamic>? ownerPayload,
  }) async {
    final hasOwnerId = ownerUserId != null;
    final hasOwnerPayload = ownerPayload != null;
    if (hasOwnerId == hasOwnerPayload) {
      throw ArgumentError(
        'Exactly one of ownerUserId or ownerPayload must be provided.',
      );
    }

    final body = <String, dynamic>{
      'name': name,
      'type': type,
      if (activityType != null && activityType.trim().isNotEmpty)
        'activityType': activityType.trim(),
      if (department != null && department.trim().isNotEmpty)
        'department': department.trim().toLowerCase(),
      if (discoverySubcategory != null &&
          discoverySubcategory.trim().isNotEmpty)
        'discoverySubcategory': discoverySubcategory.trim(),
      'description': description,
      'phone': phone,
      'imageUrl': imageUrl,
      'serviceFlags': serviceFlags,
      'badges': badges,
      'supportsChat': supportsChat,
      'supportsAttachments': supportsAttachments,
      'supportsPharmacyWorkflow': supportsPharmacyWorkflow,
    };
    if (discoverySubcategories != null) {
      body['discoverySubcategories'] = discoverySubcategories;
    }
    if (discoverySelectAll != null) {
      body['discoverySelectAll'] = discoverySelectAll;
    }
    body.removeWhere((_, value) => value == null);

    if (ownerUserId != null) {
      body['ownerUserId'] = ownerUserId;
    }

    if (ownerPayload != null) {
      body['owner'] = ownerPayload;
    }

    final data = await ref
        .read(merchantsApiProvider)
        .create(
          {...body},
          merchantImageFile: merchantImageFile,
          ownerImageFile: ownerImageFile,
        );

    return MerchantModel.fromJson(data);
  }
}

const List<StoreActivityModel> _fallbackStoreActivities = <StoreActivityModel>[
  StoreActivityModel(
    activityType: 'restaurant',
    baseType: 'restaurant',
    displayNameEn: 'Restaurant',
    displayNameAr: 'مطعم',
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'pharmacy',
    baseType: 'market',
    displayNameEn: 'Pharmacy',
    displayNameAr: 'صيدلية',
    hasDiscoverySubcategories: true,
    supportsChat: true,
    supportsAttachments: true,
    supportsPharmacyWorkflow: true,
    internalCategoryMode: 'merchant_defined_with_templates_and_constraints',
    defaultServiceFlags: <String, dynamic>{
      'acceptsPrescriptions': true,
      'supportsConsultation': true,
    },
    defaultBadges: <String>['prescriptions', 'delivery'],
  ),
  StoreActivityModel(
    activityType: 'supermarket',
    baseType: 'market',
    displayNameEn: 'Supermarket',
    displayNameAr: 'سوبرماركت',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'sweets_bakery',
    baseType: 'restaurant',
    displayNameEn: 'Sweets & Bakery',
    displayNameAr: 'حلويات ومخبوزات',
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'coffee_drinks',
    baseType: 'restaurant',
    displayNameEn: 'Coffee & Drinks',
    displayNameAr: 'قهوة ومشروبات',
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'meat_poultry',
    baseType: 'market',
    displayNameEn: 'Meat & Poultry',
    displayNameAr: 'ملحمة ودواجن',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'seafood',
    baseType: 'market',
    displayNameEn: 'Seafood',
    displayNameAr: 'أسماك ومأكولات بحرية',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'fruits_vegetables',
    baseType: 'market',
    displayNameEn: 'Fruits & Vegetables',
    displayNameAr: 'خضار وفواكه',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'construction',
    baseType: 'market',
    displayNameEn: 'Construction & Tools',
    displayNameAr: 'مواد إنشائية وعدة',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'electrical_lighting',
    baseType: 'market',
    displayNameEn: 'Electrical & Lighting',
    displayNameAr: 'كهربائيات وإنارة',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'electronics_mobile',
    baseType: 'market',
    displayNameEn: 'Electronics & Mobile',
    displayNameAr: 'إلكترونيات وموبايل',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'phone_maintenance',
    baseType: 'market',
    displayNameEn: 'Phone Maintenance',
    displayNameAr: 'Phone Maintenance',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'phones_technology',
    baseType: 'market',
    displayNameEn: 'Phones & Technology',
    displayNameAr: 'Phones & Technology',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'home_kitchen',
    baseType: 'market',
    displayNameEn: 'Home & Kitchen',
    displayNameAr: 'منزل ومطبخ',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'furnishings',
    baseType: 'market',
    displayNameEn: 'Furnishings',
    displayNameAr: 'Furnishings',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'personal_care_beauty',
    baseType: 'market',
    displayNameEn: 'Personal Care & Beauty',
    displayNameAr: 'عناية شخصية وتجميل',
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'dietary_supplements',
    baseType: 'market',
    displayNameEn: 'Dietary Supplements',
    displayNameAr: 'Dietary Supplements',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'fashion_clothing',
    baseType: 'market',
    displayNameEn: 'Fashion & Clothing',
    displayNameAr: 'الملابس والأزياء',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'flowers_gifts',
    baseType: 'market',
    displayNameEn: 'Flowers & Gifts',
    displayNameAr: 'زهور وهدايا',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'stationery_office',
    baseType: 'market',
    displayNameEn: 'Stationery & Office',
    displayNameAr: 'قرطاسية ومكتبية',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'mother_child',
    baseType: 'market',
    displayNameEn: 'Mother & Child',
    displayNameAr: 'أم وطفل',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'pet_supplies',
    baseType: 'market',
    displayNameEn: 'Pet Supplies',
    displayNameAr: 'مستلزمات حيوانات',
    hasDiscoverySubcategories: false,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
  StoreActivityModel(
    activityType: 'smoking_supplies',
    baseType: 'market',
    displayNameEn: 'Smoking Supplies',
    displayNameAr: 'Smoking Supplies',
    hasDiscoverySubcategories: true,
    supportsChat: false,
    supportsAttachments: false,
    supportsPharmacyWorkflow: false,
    internalCategoryMode: 'merchant_defined_with_templates',
    defaultServiceFlags: <String, dynamic>{},
    defaultBadges: <String>[],
  ),
];

const Map<String, List<StoreDiscoveryOptionModel>> _fallbackDiscoveryOptions =
    <String, List<StoreDiscoveryOptionModel>>{
      'restaurant': <StoreDiscoveryOptionModel>[
        StoreDiscoveryOptionModel(
          id: 1,
          activityType: 'restaurant',
          code: 'eastern',
          labelEn: 'Eastern',
          labelAr: 'شرقي',
          orderIndex: 1,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 2,
          activityType: 'restaurant',
          code: 'western',
          labelEn: 'Western',
          labelAr: 'غربي',
          orderIndex: 2,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 3,
          activityType: 'restaurant',
          code: 'grills',
          labelEn: 'Grills',
          labelAr: 'مشويات',
          orderIndex: 3,
          metadata: <String, dynamic>{},
        ),
      ],
      'pharmacy': <StoreDiscoveryOptionModel>[
        StoreDiscoveryOptionModel(
          id: 101,
          activityType: 'pharmacy',
          code: 'prescriptions',
          labelEn: 'Prescriptions',
          labelAr: 'وصفات طبية',
          orderIndex: 1,
          metadata: <String, dynamic>{'feature': 'accepts_prescriptions'},
        ),
        StoreDiscoveryOptionModel(
          id: 102,
          activityType: 'pharmacy',
          code: 'otc',
          labelEn: 'OTC',
          labelAr: 'أدوية بدون وصفة',
          orderIndex: 2,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 103,
          activityType: 'pharmacy',
          code: 'vitamins',
          labelEn: 'Vitamins',
          labelAr: 'فيتامينات',
          orderIndex: 3,
          metadata: <String, dynamic>{},
        ),
      ],
      'sweets_bakery': <StoreDiscoveryOptionModel>[
        StoreDiscoveryOptionModel(
          id: 201,
          activityType: 'sweets_bakery',
          code: 'eastern_sweets',
          labelEn: 'Eastern Sweets',
          labelAr: 'حلويات شرقية',
          orderIndex: 1,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 202,
          activityType: 'sweets_bakery',
          code: 'western_sweets',
          labelEn: 'Western Sweets',
          labelAr: 'حلويات غربية',
          orderIndex: 2,
          metadata: <String, dynamic>{},
        ),
      ],
      'coffee_drinks': <StoreDiscoveryOptionModel>[
        StoreDiscoveryOptionModel(
          id: 301,
          activityType: 'coffee_drinks',
          code: 'cafe',
          labelEn: 'Cafe',
          labelAr: 'كافيه',
          orderIndex: 1,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 302,
          activityType: 'coffee_drinks',
          code: 'juices',
          labelEn: 'Juices',
          labelAr: 'عصائر',
          orderIndex: 2,
          metadata: <String, dynamic>{},
        ),
      ],
      'personal_care_beauty': <StoreDiscoveryOptionModel>[
        StoreDiscoveryOptionModel(
          id: 401,
          activityType: 'personal_care_beauty',
          code: 'skin_care',
          labelEn: 'Skin Care',
          labelAr: 'عناية بالبشرة',
          orderIndex: 1,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 402,
          activityType: 'personal_care_beauty',
          code: 'hair_care',
          labelEn: 'Hair Care',
          labelAr: 'عناية بالشعر',
          orderIndex: 2,
          metadata: <String, dynamic>{},
        ),
      ],
      'smoking_supplies': <StoreDiscoveryOptionModel>[
        StoreDiscoveryOptionModel(
          id: 501,
          activityType: 'smoking_supplies',
          code: 'cigarettes',
          labelEn: 'Cigarettes',
          labelAr: 'Cigarettes',
          orderIndex: 1,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 502,
          activityType: 'smoking_supplies',
          code: 'hookahs_accessories',
          labelEn: 'Hookahs & Accessories',
          labelAr: 'Hookahs & Accessories',
          orderIndex: 2,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 503,
          activityType: 'smoking_supplies',
          code: 'electronic_hookahs',
          labelEn: 'Electronic Hookahs',
          labelAr: 'Electronic Hookahs',
          orderIndex: 3,
          metadata: <String, dynamic>{},
        ),
        StoreDiscoveryOptionModel(
          id: 504,
          activityType: 'smoking_supplies',
          code: 'vapes',
          labelEn: 'Vapes',
          labelAr: 'Vapes',
          orderIndex: 4,
          metadata: <String, dynamic>{},
        ),
      ],
    };
