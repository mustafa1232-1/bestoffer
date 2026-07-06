import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../../delivery/models/delivery_agent_model.dart';
import '../../orders/models/order_model.dart';
import '../../products/models/product_category_model.dart';
import '../../products/models/product_model.dart';
import '../data/owner_api.dart';
import '../models/merchant_offer_model.dart';
import '../models/owner_merchant_model.dart';

/// Purpose: مصدر الحالة المركزي لمساحة صاحب المتجر: المتجر، الطلبات، الكاتالوج، العروض، والموظفين.
/// Used by: `OwnerDashboardScreen` والشيتات المرتبطة بإدارة المتجر والطلبات.
/// Depends on: `OwnerApi`, `authControllerProvider`, و`api_error_mapper.dart`.
/// Critical notes: هذا controller يجمع أكثر من domain في حالة واحدة، لذلك أي bootstrap جزئي أو polling خاطئ ينعكس على عدة tabs دفعة واحدة.
/// Maintenance notes: إذا ظهرت بيانات owner غير متزامنة افحص `bootstrap`, ثم `_reload*` helpers, ثم polling `startLiveOrders`.
final ownerApiProvider = Provider<OwnerApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return OwnerApi(dio);
});

final ownerControllerProvider =
    StateNotifierProvider<OwnerController, OwnerState>((ref) {
      return OwnerController(ref);
    });

/// Snapshot الحالة المعروضة داخل مساحة صاحب المتجر.
///
/// هذه البنية هي source of truth للواجهة، ولذلك أي حقل جديد يظهر في dashboard
/// يجب أن يمر من هنا أولاً بدلاً من تخزينه محلياً داخل الشاشة.
class OwnerState {
  final bool loading;
  final bool savingMerchant;
  final bool savingProduct;
  final bool savingOrder;
  final OwnerMerchantModel? merchant;
  final List<ProductCategoryModel> categories;
  final List<ProductModel> products;
  final List<MerchantOfferModel> offers;
  final List<OrderModel> currentOrders;
  final List<OrderModel> historyOrders;
  final List<DeliveryAgentModel> deliveryAgents;
  final List<DeliveryAgentModel> accountants;
  final List<DeliveryAgentModel> hrStaff;
  final Map<String, dynamic> analytics;
  final Map<String, dynamic>? settlementSummary;
  final Map<String, dynamic> merchantDashboardV2;
  final Map<String, dynamic> merchantKpisV2;
  final List<Map<String, dynamic>> merchantTopProductsV2;
  final List<Map<String, dynamic>> merchantTopCategoriesV2;
  final Map<String, dynamic> merchantOrdersReportsV2;
  final List<Map<String, dynamic>> merchantCouriersV2;
  final Map<String, dynamic> merchantReceivablesV2;
  final List<Map<String, dynamic>> merchantReceivablesLedgerV2;
  final List<Map<String, dynamic>> merchantPaymentRequestsV2;
  final String? error;

  const OwnerState({
    this.loading = false,
    this.savingMerchant = false,
    this.savingProduct = false,
    this.savingOrder = false,
    this.merchant,
    this.categories = const [],
    this.products = const [],
    this.offers = const [],
    this.currentOrders = const [],
    this.historyOrders = const [],
    this.deliveryAgents = const [],
    this.accountants = const [],
    this.hrStaff = const [],
    this.analytics = const {},
    this.settlementSummary,
    this.merchantDashboardV2 = const {},
    this.merchantKpisV2 = const {},
    this.merchantTopProductsV2 = const [],
    this.merchantTopCategoriesV2 = const [],
    this.merchantOrdersReportsV2 = const {},
    this.merchantCouriersV2 = const [],
    this.merchantReceivablesV2 = const {},
    this.merchantReceivablesLedgerV2 = const [],
    this.merchantPaymentRequestsV2 = const [],
    this.error,
  });

  OwnerState copyWith({
    bool? loading,
    bool? savingMerchant,
    bool? savingProduct,
    bool? savingOrder,
    OwnerMerchantModel? merchant,
    List<ProductCategoryModel>? categories,
    List<ProductModel>? products,
    List<MerchantOfferModel>? offers,
    List<OrderModel>? currentOrders,
    List<OrderModel>? historyOrders,
    List<DeliveryAgentModel>? deliveryAgents,
    List<DeliveryAgentModel>? accountants,
    List<DeliveryAgentModel>? hrStaff,
    Map<String, dynamic>? analytics,
    Map<String, dynamic>? settlementSummary,
    Map<String, dynamic>? merchantDashboardV2,
    Map<String, dynamic>? merchantKpisV2,
    List<Map<String, dynamic>>? merchantTopProductsV2,
    List<Map<String, dynamic>>? merchantTopCategoriesV2,
    Map<String, dynamic>? merchantOrdersReportsV2,
    List<Map<String, dynamic>>? merchantCouriersV2,
    Map<String, dynamic>? merchantReceivablesV2,
    List<Map<String, dynamic>>? merchantReceivablesLedgerV2,
    List<Map<String, dynamic>>? merchantPaymentRequestsV2,
    String? error,
  }) {
    return OwnerState(
      loading: loading ?? this.loading,
      savingMerchant: savingMerchant ?? this.savingMerchant,
      savingProduct: savingProduct ?? this.savingProduct,
      savingOrder: savingOrder ?? this.savingOrder,
      merchant: merchant ?? this.merchant,
      categories: categories ?? this.categories,
      products: products ?? this.products,
      offers: offers ?? this.offers,
      currentOrders: currentOrders ?? this.currentOrders,
      historyOrders: historyOrders ?? this.historyOrders,
      deliveryAgents: deliveryAgents ?? this.deliveryAgents,
      accountants: accountants ?? this.accountants,
      hrStaff: hrStaff ?? this.hrStaff,
      analytics: analytics ?? this.analytics,
      settlementSummary: settlementSummary ?? this.settlementSummary,
      merchantDashboardV2: merchantDashboardV2 ?? this.merchantDashboardV2,
      merchantKpisV2: merchantKpisV2 ?? this.merchantKpisV2,
      merchantTopProductsV2:
          merchantTopProductsV2 ?? this.merchantTopProductsV2,
      merchantTopCategoriesV2:
          merchantTopCategoriesV2 ?? this.merchantTopCategoriesV2,
      merchantOrdersReportsV2:
          merchantOrdersReportsV2 ?? this.merchantOrdersReportsV2,
      merchantCouriersV2: merchantCouriersV2 ?? this.merchantCouriersV2,
      merchantReceivablesV2:
          merchantReceivablesV2 ?? this.merchantReceivablesV2,
      merchantReceivablesLedgerV2:
          merchantReceivablesLedgerV2 ?? this.merchantReceivablesLedgerV2,
      merchantPaymentRequestsV2:
          merchantPaymentRequestsV2 ?? this.merchantPaymentRequestsV2,
      error: error,
    );
  }
}

/// المتحكم الرئيسي في تدفقات owner، ويجمع بين bootstrap، polling، وعمليات CRUD.
class OwnerController extends StateNotifier<OwnerState> {
  final Ref ref;
  Timer? _liveOrdersTimer;
  bool _liveFetchInFlight = false;
  bool _ordersRefreshInFlight = false;
  Future<void>? _bootstrapInFlight;
  DateTime? _lastBootstrapAt;
  bool _disposed = false;
  static const Duration _bootstrapFreshWindow = Duration(seconds: 12);

  OwnerController(this.ref) : super(const OwnerState());

  /// يحدد ما إذا كان polling مسموحاً حالياً حسب جلسة المستخدم والدور.
  bool _canRunOwnerPolling() {
    final auth = ref.read(authControllerProvider);
    return auth.isAuthed && auth.isOwner;
  }

  /// يميز أخطاء الصلاحية الخاصة بصاحب المتجر لإيقاف polling ومنع التكرار الضار.
  bool _isOwnerForbiddenError(DioException error) {
    if (error.response?.statusCode != 403) return false;
    final data = error.response?.data;
    if (data is! Map) return false;
    final message = '${data['message'] ?? ''}'.trim().toUpperCase();
    final code = '${data['code'] ?? ''}'.trim().toUpperCase();
    return message == 'FORBIDDEN_OWNER_ONLY' || code == 'FORBIDDEN_OWNER_ONLY';
  }

  /// يحمّل snapshot owner الكامل المستخدم في معظم tabs.
  ///
  /// يستدعي عدة endpoints بالتتابع لأن بعضها يعتمد على وجود merchant فعلي،
  /// ثم يحولها إلى نماذج Dart قبل ضخها في الحالة الموحدة.
  Future<void> bootstrap({String? period, bool force = false}) async {
    if (_bootstrapInFlight != null) {
      await _bootstrapInFlight;
      return;
    }
    final hasSnapshot = state.merchant != null;
    final recentlyBootstrapped =
        _lastBootstrapAt != null &&
        DateTime.now().difference(_lastBootstrapAt!) < _bootstrapFreshWindow;
    if (!force && hasSnapshot && recentlyBootstrapped) {
      return;
    }
    final future = _runBootstrap(period: period);
    _bootstrapInFlight = future;
    try {
      await future;
    } finally {
      _bootstrapInFlight = null;
    }
  }

  Future<void> _runBootstrap({String? period}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final api = ref.read(ownerApiProvider);
      final merchantFuture = api.getMerchant();
      final productsFuture = api.listProducts();
      final categoriesFuture = api.listCategories();
      final offersFuture = api.listOffers();
      final currentOrdersFuture = api.listCurrentOrders();
      final historyOrdersFuture = api.listOrderHistory();
      final deliveryAgentsFuture = api.listDeliveryAgents();
      final accountantsFuture = api.listAccountants().catchError(
        (_) => <dynamic>[],
      );
      final hrStaffFuture = api.listHrStaff().catchError((_) => <dynamic>[]);
      final analyticsFuture = api.analytics();
      final settlementSummaryFuture = api.settlementSummary();

      final merchantResponse = await merchantFuture;
      final productsResponse = await productsFuture;
      final categoriesResponse = await categoriesFuture;
      final offersResponse = await offersFuture;
      final currentOrdersResponse = await currentOrdersFuture;
      final historyOrdersResponse = await historyOrdersFuture;
      final deliveryAgentsResponse = await deliveryAgentsFuture;
      final accountantsResponse = await accountantsFuture;
      final hrStaffResponse = await hrStaffFuture;
      final analyticsResponse = await analyticsFuture;
      final settlementSummaryResponse = await settlementSummaryFuture;

      final merchant = OwnerMerchantModel.fromJson(
        Map<String, dynamic>.from(merchantResponse['merchant'] as Map),
      );
      final products = productsResponse
          .map(
            (e) => ProductModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();
      final categories = categoriesResponse
          .map(
            (e) => ProductCategoryModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      final offers = offersResponse
          .map(
            (e) => MerchantOfferModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      final currentOrders = currentOrdersResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final historyOrders = historyOrdersResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final deliveryAgents = deliveryAgentsResponse
          .map(
            (e) => DeliveryAgentModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      final accountants = accountantsResponse
          .map(
            (e) => DeliveryAgentModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();
      final hrStaff = hrStaffResponse
          .map(
            (e) => DeliveryAgentModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();

      state = state.copyWith(
        loading: false,
        merchant: merchant,
        categories: categories,
        products: products,
        offers: offers,
        currentOrders: currentOrders,
        historyOrders: historyOrders,
        deliveryAgents: deliveryAgents,
        accountants: accountants,
        hrStaff: hrStaff,
        analytics: analyticsResponse,
        settlementSummary: settlementSummaryResponse,
      );
      _lastBootstrapAt = DateTime.now();
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _ownerText('dashboard_load_failed'),
      );
    }
  }

  /// يعتمد الشروط المالية ثم يعيد bootstrap كامل لأن أكثر من قسم في الواجهة يتأثر بهذا القرار.
  Future<bool> acceptFinancialTerms() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final response = await ref.read(ownerApiProvider).acceptFinancialTerms();
      final merchant = OwnerMerchantModel.fromJson(
        Map<String, dynamic>.from(response['merchant'] as Map),
      );
      state = state.copyWith(loading: false, merchant: merchant);
      await bootstrap();
      return true;
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _ownerText('financial_terms_accept_failed'),
      );
      return false;
    }
  }

  /// يرفض الشروط المالية مع ملاحظة اختيارية ثم يعيد bootstrap لإعادة مزامنة approval state.
  Future<bool> rejectFinancialTerms({String? note}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final response = await ref
          .read(ownerApiProvider)
          .rejectFinancialTerms(note: note);
      final merchant = OwnerMerchantModel.fromJson(
        Map<String, dynamic>.from(response['merchant'] as Map),
      );
      state = state.copyWith(loading: false, merchant: merchant);
      await bootstrap();
      return true;
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _ownerText('financial_terms_reject_failed'),
      );
      return false;
    }
  }

  /// يحدّث قوائم الطلبات الحالية والمؤرشفة فقط دون إعادة تحميل بقية مساحة المتجر.
  Future<void> refreshOrders({
    String? historyDate,
    bool silent = false,
    bool includeHistory = true,
  }) async {
    if (_ordersRefreshInFlight) return;
    _ordersRefreshInFlight = true;
    try {
      final currentOrdersResponse = await ref
          .read(ownerApiProvider)
          .listCurrentOrders();
      final historyOrdersResponse = includeHistory
          ? await ref.read(ownerApiProvider).listOrderHistory(date: historyDate)
          : null;

      final currentOrders = currentOrdersResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final historyOrders = historyOrdersResponse
          ?.map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      state = state.copyWith(
        currentOrders: currentOrders,
        historyOrders: historyOrders ?? state.historyOrders,
        error: null,
      );
    } on DioException catch (e) {
      if (_isOwnerForbiddenError(e)) {
        stopLiveOrders();
      }
      if (silent) return;
      state = state.copyWith(error: _mapError(e));
    } finally {
      _ordersRefreshInFlight = false;
    }
  }

  /// يفعّل polling منخفض التواتر للطلبات الحالية كـ fallback عند غياب realtime.
  ///
  /// التشخيص: إذا تكررت requests كل عدة ثوانٍ على مستخدم غير owner فافحص
  /// `_canRunOwnerPolling` ومواضع استدعاء `startLiveOrders/stopLiveOrders`.
  void startLiveOrders({Duration interval = const Duration(seconds: 15)}) {
    if (!_canRunOwnerPolling()) {
      stopLiveOrders();
      return;
    }
    _liveOrdersTimer?.cancel();
    _liveOrdersTimer = Timer.periodic(interval, (_) async {
      if (_disposed || _liveFetchInFlight) return;
      if (!_canRunOwnerPolling()) {
        stopLiveOrders();
        return;
      }
      _liveFetchInFlight = true;
      try {
        await refreshOrders(silent: true, includeHistory: false);
      } finally {
        _liveFetchInFlight = false;
      }
    });
  }

  /// يوقف polling ويحرر المؤقت الدوري.
  void stopLiveOrders() {
    _liveOrdersTimer?.cancel();
    _liveOrdersTimer = null;
  }

  /// يحدّث بطاقة المتجر وبياناته المرئية في تبويب profile/store.
  Future<void> updateMerchant({
    required String name,
    required String type,
    required String description,
    required String phone,
    required String imageUrl,
    String? tagline,
    String? workingHours,
    String? serviceAreaNote,
    LocalImageFile? imageFile,
    required bool isOpen,
  }) async {
    state = state.copyWith(savingMerchant: true, error: null);

    try {
      final response = await ref.read(ownerApiProvider).updateMerchant({
        'name': name.trim(),
        'type': type,
        'description': description.trim(),
        'phone': phone.trim(),
        'imageUrl': imageUrl.trim(),
        'tagline': tagline?.trim(),
        'workingHours': workingHours?.trim(),
        'serviceAreaNote': serviceAreaNote?.trim(),
        'isOpen': isOpen,
      }, imageFile: imageFile);

      final merchant = OwnerMerchantModel.fromJson(
        Map<String, dynamic>.from(response['merchant'] as Map),
      );

      state = state.copyWith(savingMerchant: false, merchant: merchant);
    } on DioException catch (e) {
      state = state.copyWith(savingMerchant: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingMerchant: false,
        error: _ownerText('merchant_update_failed'),
      );
    }
  }

  /// ينشئ منتجاً جديداً ثم يعيد تحميل المنتجات المتأثرة من الخادم.
  Future<void> createProduct({
    required String name,
    required String description,
    int? categoryId,
    required String price,
    required String discountedPrice,
    required String imageUrl,
    LocalImageFile? imageFile,
    required bool freeDelivery,
    required String offerLabel,
    required bool isAvailable,
    String? unavailableReason,
    String? unavailableUntil,
    required bool requiresPrescription,
    required bool requiresReview,
    required int sortOrder,
    String? stockQuantity,
    List<Map<String, dynamic>> attributes = const [],
    List<Map<String, dynamic>> variantGroups = const [],
    List<Map<String, dynamic>> variants = const [],
    List<Map<String, dynamic>> media = const [],
    List<LocalImageFile> galleryFiles = const [],
    List<LocalImageFile> variantFiles = const [],
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .createProduct(
            {
              'name': name.trim(),
              'description': description.trim(),
              'categoryId': categoryId,
              'price': price.trim(),
              'discountedPrice': discountedPrice.trim().isEmpty
                  ? null
                  : discountedPrice.trim(),
              'imageUrl': imageUrl.trim(),
              'freeDelivery': freeDelivery,
              'offerLabel': offerLabel.trim().isEmpty
                  ? null
                  : offerLabel.trim(),
              'isAvailable': isAvailable,
              'unavailableReason': unavailableReason?.trim().isEmpty == true
                  ? null
                  : unavailableReason?.trim(),
              'unavailableUntil': unavailableUntil?.trim().isEmpty == true
                  ? null
                  : unavailableUntil?.trim(),
              'requiresPrescription': requiresPrescription,
              'requiresReview': requiresReview,
              'sortOrder': sortOrder,
              'stockQuantity': stockQuantity?.trim().isEmpty == true
                  ? null
                  : stockQuantity?.trim(),
              'attributes': attributes,
              'variantGroups': variantGroups,
              'variants': variants,
              'media': media,
            },
            imageFile: imageFile,
            galleryFiles: galleryFiles,
            variantFiles: variantFiles,
          );

      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error: _ownerText('product_create_failed'),
      );
    }
  }

  /// يعدّل المنتج ثم ينعش الكاتالوج من المصدر بدلاً من optimistic mutation.
  Future<void> updateProduct({
    required int productId,
    required String name,
    required String description,
    int? categoryId,
    required String price,
    required String discountedPrice,
    required String imageUrl,
    LocalImageFile? imageFile,
    required bool freeDelivery,
    required String offerLabel,
    required bool isAvailable,
    String? unavailableReason,
    String? unavailableUntil,
    required bool requiresPrescription,
    required bool requiresReview,
    required int sortOrder,
    String? stockQuantity,
    List<Map<String, dynamic>> attributes = const [],
    List<Map<String, dynamic>> variantGroups = const [],
    List<Map<String, dynamic>> variants = const [],
    List<Map<String, dynamic>> media = const [],
    List<LocalImageFile> galleryFiles = const [],
    List<LocalImageFile> variantFiles = const [],
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .updateProduct(
            productId,
            {
              'name': name.trim(),
              'description': description.trim(),
              'categoryId': categoryId,
              'price': price.trim(),
              'discountedPrice': discountedPrice.trim().isEmpty
                  ? null
                  : discountedPrice.trim(),
              'imageUrl': imageUrl.trim(),
              'freeDelivery': freeDelivery,
              'offerLabel': offerLabel.trim().isEmpty
                  ? null
                  : offerLabel.trim(),
              'isAvailable': isAvailable,
              'unavailableReason': unavailableReason?.trim().isEmpty == true
                  ? null
                  : unavailableReason?.trim(),
              'unavailableUntil': unavailableUntil?.trim().isEmpty == true
                  ? null
                  : unavailableUntil?.trim(),
              'requiresPrescription': requiresPrescription,
              'requiresReview': requiresReview,
              'sortOrder': sortOrder,
              'stockQuantity': stockQuantity?.trim().isEmpty == true
                  ? null
                  : stockQuantity?.trim(),
              'attributes': attributes,
              'variantGroups': variantGroups,
              'variants': variants,
              'media': media,
            },
            imageFile: imageFile,
            galleryFiles: galleryFiles,
            variantFiles: variantFiles,
          );

      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error: _ownerText('product_update_failed'),
      );
    }
  }

  Future<void> updateProductAvailability({
    required int productId,
    required bool isAvailable,
    String? unavailableReason,
    String? unavailableUntil,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).updateProductAvailability(productId, {
        'isAvailable': isAvailable,
        'unavailableReason': unavailableReason?.trim().isEmpty == true
            ? null
            : unavailableReason?.trim(),
        'unavailableUntil': unavailableUntil?.trim().isEmpty == true
            ? null
            : unavailableUntil?.trim(),
      });
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error: _ownerText('product_update_failed'),
      );
    }
  }

  /// يحذف المنتج ثم يطلب القائمة الجديدة من الخادم لتفادي بقاء بيانات مشتقة قديمة.
  Future<void> deleteProduct(int productId) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).deleteProduct(productId);
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error: _ownerText('product_delete_failed'),
      );
    }
  }

  /// ينشئ عرضاً جديداً ويعيد مزامنة العروض والمنتجات لأن كلاهما يتأثران بالخصومات.
  Future<void> createOffer({
    required String title,
    String? description,
    required String offerType,
    double? discountValue,
    int? buyQuantity,
    int? getQuantity,
    DateTime? startsAt,
    DateTime? endsAt,
    required String status,
    int? maxUsage,
    required List<int> productIds,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).createOffer({
        'title': title.trim(),
        'description': description?.trim().isEmpty == true
            ? null
            : description?.trim(),
        'offerType': offerType,
        'discountValue': discountValue,
        'buyQuantity': buyQuantity,
        'getQuantity': getQuantity,
        'startsAt': startsAt?.toUtc().toIso8601String(),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'status': status,
        'maxUsage': maxUsage,
        'productIds': productIds,
      });
      await _reloadOffers();
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error:
            '\u062a\u0639\u0630\u0631 \u0625\u0646\u0634\u0627\u0621 \u0627\u0644\u0639\u0631\u0636.',
      );
    }
  }

  /// يحدّث العرض ثم يعيد تحميل datasets المرتبطة به.
  Future<void> updateOffer({
    required int offerId,
    required String title,
    String? description,
    required String offerType,
    double? discountValue,
    int? buyQuantity,
    int? getQuantity,
    DateTime? startsAt,
    DateTime? endsAt,
    required String status,
    int? maxUsage,
    required List<int> productIds,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).updateOffer(offerId, {
        'title': title.trim(),
        'description': description?.trim().isEmpty == true
            ? null
            : description?.trim(),
        'offerType': offerType,
        'discountValue': discountValue,
        'buyQuantity': buyQuantity,
        'getQuantity': getQuantity,
        'startsAt': startsAt?.toUtc().toIso8601String(),
        'endsAt': endsAt?.toUtc().toIso8601String(),
        'status': status,
        'maxUsage': maxUsage,
        'productIds': productIds,
      });
      await _reloadOffers();
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error:
            '\u062a\u0639\u0630\u0631 \u062a\u062d\u062f\u064a\u062b \u0627\u0644\u0639\u0631\u0636.',
      );
    }
  }

  /// يحذف العرض ويعيد تحميل العروض والمنتجات لحذف labels المشتقة.
  Future<void> deleteOffer(int offerId) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).deleteOffer(offerId);
      await _reloadOffers();
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error:
            '\u062a\u0639\u0630\u0631 \u062d\u0630\u0641 \u0627\u0644\u0639\u0631\u0636.',
      );
    }
  }

  /// ينشئ تصنيفاً جديداً داخل المتجر.
  Future<void> createCategory({
    required String name,
    required int sortOrder,
    required String catalogType,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).createCategory({
        'name': name.trim(),
        'sortOrder': sortOrder,
        'catalogType': catalogType,
      });
      await _reloadCategories();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error: _ownerText('category_create_failed'),
      );
    }
  }

  /// يعدّل التصنيف ثم يعيد تحميل التصنيفات والمنتجات المرتبطة به.
  Future<void> updateCategory({
    required int categoryId,
    required String name,
    required int sortOrder,
    required String catalogType,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).updateCategory(categoryId, {
        'name': name.trim(),
        'sortOrder': sortOrder,
        'catalogType': catalogType,
      });
      await _reloadCategories();
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error: _ownerText('category_update_failed'),
      );
    }
  }

  /// يحذف التصنيف إذا سمح الخادم بذلك.
  Future<void> deleteCategory(int categoryId) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).deleteCategory(categoryId);
      await _reloadCategories();
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingProduct: false,
        error: _ownerText('category_delete_failed'),
      );
    }
  }

  /// يرسل انتقال حالة الطلب إلى الباكند ثم يجلب أحدث snapshot للطلبات.
  Future<bool> updateOrderStatus({
    required int orderId,
    required String status,
    int? estimatedPrepMinutes,
    int? estimatedDeliveryMinutes,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .updateOrderStatus(
            orderId: orderId,
            status: status,
            estimatedPrepMinutes: estimatedPrepMinutes,
            estimatedDeliveryMinutes: estimatedDeliveryMinutes,
          );
      await refreshOrders(includeHistory: false);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('order_status_update_failed'),
      );
      return false;
    }
  }

  /// يربط order بسائق delivery أو بنمط إسناد محدد.
  Future<bool> assignDelivery({
    required int orderId,
    int? deliveryUserId,
    String assignmentMode = 'platform_delivery',
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .assignDelivery(
            orderId: orderId,
            deliveryUserId: deliveryUserId,
            assignmentMode: assignmentMode,
          );
      await refreshOrders(includeHistory: false);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('assign_delivery_failed'),
      );
      return false;
    }
  }

  /// يرسل طلب تسوية مالية ثم يحدّث الملخص المالي المعروض في dashboard.
  Future<void> requestSettlement({String? note}) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref.read(ownerApiProvider).requestSettlement(note: note?.trim());
      final settlementSummary = await ref
          .read(ownerApiProvider)
          .settlementSummary();
      state = state.copyWith(
        savingOrder: false,
        settlementSummary: settlementSummary,
      );
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerReceivablesSubmitFailed,
        ),
      );
    }
  }

  /// يشغّل أول مرحلة من flow العمليات v2 الخاص بتحضير الطلب.
  Future<bool> startPreparingFlowV2({
    required int orderId,
    int? preferredCourierUserId,
    int? estimatedPrepMinutes,
    String? note,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .startPreparingV2(
            orderId: orderId,
            preferredCourierUserId: preferredCourierUserId,
            estimatedPrepMinutes: estimatedPrepMinutes,
            note: note,
          );
      await refreshOrders(includeHistory: false);
      await loadMerchantOpsOverviewV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('order_preparation_start_failed'),
      );
      return false;
    }
  }

  /// يعيّن courier في flow v2 ويعيد تحميل لوحة العمليات.
  Future<bool> assignCourierFlowV2({
    required int orderId,
    int? courierUserId,
    String assignmentMode = 'manual',
    String? note,
  }) async {
    if (courierUserId == null) return false;
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .assignCourierV2(
            orderId: orderId,
            courierUserId: courierUserId,
            assignmentMode: assignmentMode,
            note: note,
          );
      await refreshOrders(includeHistory: false);
      await loadMerchantOpsOverviewV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('assign_delivery_failed'),
      );
      return false;
    }
  }

  /// ينقل الطلب إلى حالة ready for pickup ضمن flow v2.
  Future<bool> readyForPickupFlowV2({
    required int orderId,
    int? estimatedDeliveryMinutes,
    String? note,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .readyForPickupV2(
            orderId: orderId,
            estimatedDeliveryMinutes: estimatedDeliveryMinutes,
            note: note,
          );
      await refreshOrders(includeHistory: false);
      await loadMerchantOpsOverviewV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('order_ready_status_failed'),
      );
      return false;
    }
  }

  /// يجمع مؤشرات التشغيل v2 المتعددة في استدعاء واحد للواجهة.
  Future<void> loadMerchantOpsOverviewV2({
    String period = 'day',
    String? from,
    String? to,
    bool silent = false,
  }) async {
    try {
      final api = ref.read(ownerApiProvider);
      final dashboard = await api
          .merchantDashboardV2(period: period, from: from, to: to)
          .catchError((_) => <String, dynamic>{});
      final kpis = await api
          .merchantKpisV2(period: period, from: from, to: to)
          .catchError((_) => <String, dynamic>{});
      final topProducts = await api
          .merchantTopProductsV2(period: period, from: from, to: to)
          .catchError((_) => <dynamic>[]);
      final topCategories = await api
          .merchantTopCategoriesV2(period: period, from: from, to: to)
          .catchError((_) => <dynamic>[]);
      final reports = await api
          .merchantOrdersReportsV2(period: period, from: from, to: to)
          .catchError((_) => <String, dynamic>{});
      final couriers = await api.merchantCouriersV2().catchError(
        (_) => <dynamic>[],
      );
      state = state.copyWith(
        merchantDashboardV2: Map<String, dynamic>.from(dashboard),
        merchantKpisV2: Map<String, dynamic>.from(kpis),
        merchantTopProductsV2: topProducts
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        merchantTopCategoriesV2: topCategories
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        merchantOrdersReportsV2: Map<String, dynamic>.from(reports),
        merchantCouriersV2: couriers
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
      );
    } on DioException catch (e) {
      if (!silent) state = state.copyWith(error: _mapError(e));
    }
  }

  /// يجلب summary/ledger/payment requests الخاصة بالمستحقات المالية.
  Future<void> loadMerchantReceivablesV2({bool silent = false}) async {
    try {
      final api = ref.read(ownerApiProvider);
      final summary = await api.merchantReceivablesV2().catchError(
        (_) => <String, dynamic>{},
      );
      final ledger = await api.merchantReceivablesLedgerV2().catchError(
        (_) => <dynamic>[],
      );
      final requests = await api.listPaymentRequestsV2().catchError(
        (_) => <String, dynamic>{'requests': <dynamic>[]},
      );
      state = state.copyWith(
        merchantReceivablesV2: Map<String, dynamic>.from(summary),
        merchantReceivablesLedgerV2: ledger
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(),
        merchantPaymentRequestsV2: List<dynamic>.from(
          Map<String, dynamic>.from(requests)['requests'] as List? ?? const [],
        ).whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList(),
      );
    } on DioException catch (e) {
      if (!silent) state = state.copyWith(error: _mapError(e));
    }
  }

  Future<List<Map<String, dynamic>>> fetchMerchantReceivableInvoicesV2({
    int limit = 500,
    int offset = 0,
    String period = 'all',
    String? from,
    String? to,
    bool? onlyOpen,
  }) async {
    try {
      final raw = await ref
          .read(ownerApiProvider)
          .merchantReceivableInvoicesV2(
            limit: limit,
            offset: offset,
            period: period,
            from: from,
            to: to,
            onlyOpen: onlyOpen,
          );
      final invoices = List<dynamic>.from(raw['invoices'] as List? ?? const []);
      return invoices
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList(growable: false);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return const [];
    } catch (_) {
      state = state.copyWith(
        error: _ownerText('receivable_invoices_load_failed'),
      );
      return const [];
    }
  }

  Future<Map<String, dynamic>?> previewMerchantPaymentSelectionV2({
    required String selectionMode,
    List<int> selectedInvoiceIds = const [],
    double? amount,
    double? targetAmount,
    double? confirmedAdjustedAmount,
  }) async {
    try {
      return await ref
          .read(ownerApiProvider)
          .previewPaymentSelectionV2(
            selectionMode: selectionMode,
            selectedInvoiceIds: selectedInvoiceIds,
            amount: amount,
            targetAmount: targetAmount,
            confirmedAdjustedAmount: confirmedAdjustedAmount,
          );
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return null;
    } catch (_) {
      state = state.copyWith(error: _ownerText('receivable_preview_failed'));
      return null;
    }
  }

  Future<Map<String, dynamic>?> fetchMerchantPaymentRequestInvoicesV2(
    int paymentRequestId,
  ) async {
    try {
      return await ref
          .read(ownerApiProvider)
          .paymentRequestInvoicesV2(paymentRequestId);
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
      return null;
    } catch (_) {
      state = state.copyWith(
        error: _ownerText('payment_request_invoices_load_failed'),
      );
      return null;
    }
  }

  Future<bool> createMerchantCourierV2({
    required int deliveryUserId,
    String? vehicleType,
    String? coverageBlock,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .createMerchantCourierV2(
            deliveryUserId: deliveryUserId,
            vehicleType: vehicleType,
            coverageBlock: coverageBlock,
          );
      await loadMerchantOpsOverviewV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText((l10n) => l10n.ownerCouriersAddFailed),
      );
      return false;
    }
  }

  Future<bool> patchMerchantCourierV2({
    required int courierUserId,
    bool? isActive,
    String? availabilityStatus,
    String? vehicleType,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .patchMerchantCourierV2(
            courierUserId: courierUserId,
            isActive: isActive,
            availabilityStatus: availabilityStatus,
            vehicleType: vehicleType,
          );
      await loadMerchantOpsOverviewV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('courier_update_failed'),
      );
      return false;
    }
  }

  Future<bool> createMerchantPaymentRequestV2({
    String requestType = 'store_pays_app',
    required String paymentScope,
    double? amount,
    String? proofFileUrl,
    String? note,
    String? paymentMethod,
    String? paymentMethodOther,
    String? paymentAt,
    String? referenceCode,
    String? receiverName,
    String? selectionMode,
    List<int> selectedInvoiceIds = const [],
    double? targetAmount,
    double? confirmedAdjustedAmount,
    Map<String, dynamic>? selectionMeta,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .createPaymentRequestV2(
            requestType: requestType,
            paymentScope: paymentScope,
            amount: amount,
            proofFileUrl: proofFileUrl,
            note: note,
            paymentMethod: paymentMethod,
            paymentMethodOther: paymentMethodOther,
            paymentAt: paymentAt,
            referenceCode: referenceCode,
            receiverName: receiverName,
            selectionMode: selectionMode,
            selectedInvoiceIds: selectedInvoiceIds,
            targetAmount: targetAmount,
            confirmedAdjustedAmount: confirmedAdjustedAmount,
            selectionMeta: selectionMeta,
          );
      await loadMerchantReceivablesV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerReceivablesSubmitFailed,
        ),
      );
      return false;
    }
  }

  Future<bool> patchMerchantPaymentRequestV2({
    required int paymentRequestId,
    String? paymentScope,
    double? amount,
    String? note,
    String? proofFileUrl,
    String? paymentMethod,
    String? paymentMethodOther,
    String? paymentAt,
    String? referenceCode,
    String? receiverName,
    String? selectionMode,
    List<int> selectedInvoiceIds = const [],
    double? targetAmount,
    double? confirmedAdjustedAmount,
    Map<String, dynamic>? selectionMeta,
    bool? resubmit,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .patchPaymentRequestV2(
            paymentRequestId: paymentRequestId,
            paymentScope: paymentScope,
            amount: amount,
            note: note,
            proofFileUrl: proofFileUrl,
            paymentMethod: paymentMethod,
            paymentMethodOther: paymentMethodOther,
            paymentAt: paymentAt,
            referenceCode: referenceCode,
            receiverName: receiverName,
            selectionMode: selectionMode,
            selectedInvoiceIds: selectedInvoiceIds,
            targetAmount: targetAmount,
            confirmedAdjustedAmount: confirmedAdjustedAmount,
            selectionMeta: selectionMeta,
            resubmit: resubmit,
          );
      await loadMerchantReceivablesV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerReceivablesUpdateFailed,
        ),
      );
      return false;
    }
  }

  Future<bool> confirmMerchantPaymentRequestReceivedV2({
    required int paymentRequestId,
    String? note,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .confirmPaymentRequestReceivedV2(
            paymentRequestId: paymentRequestId,
            note: note,
          );
      await loadMerchantReceivablesV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerReceivablesConfirmReceiptFailed,
        ),
      );
      return false;
    }
  }

  Future<bool> reportMerchantPaymentRequestIssueV2({
    required int paymentRequestId,
    required String issueNote,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .reportPaymentRequestIssueV2(
            paymentRequestId: paymentRequestId,
            issueNote: issueNote,
          );
      await loadMerchantReceivablesV2(silent: true);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerReceivablesIssueReportFailed,
        ),
      );
      return false;
    }
  }

  Future<void> _reloadProducts() async {
    final response = await ref.read(ownerApiProvider).listProducts();
    final products = response
        .map((e) => ProductModel.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
    state = state.copyWith(products: products);
  }

  Future<void> _reloadCategories() async {
    final response = await ref.read(ownerApiProvider).listCategories();
    final categories = response
        .map(
          (e) => ProductCategoryModel.fromJson(
            Map<String, dynamic>.from(e as Map),
          ),
        )
        .toList();
    state = state.copyWith(categories: categories);
  }

  Future<void> _reloadOffers() async {
    final response = await ref.read(ownerApiProvider).listOffers();
    final offers = response
        .map(
          (e) =>
              MerchantOfferModel.fromJson(Map<String, dynamic>.from(e as Map)),
        )
        .toList();
    state = state.copyWith(offers: offers);
  }

  Future<void> _reloadStaffLists() async {
    try {
      final deliveryAgentsResponse = await ref
          .read(ownerApiProvider)
          .listDeliveryAgents();
      final accountantsResponse = await ref
          .read(ownerApiProvider)
          .listAccountants()
          .catchError((_) => <dynamic>[]);
      final hrStaffResponse = await ref
          .read(ownerApiProvider)
          .listHrStaff()
          .catchError((_) => <dynamic>[]);

      state = state.copyWith(
        deliveryAgents: deliveryAgentsResponse
            .map(
              (e) => DeliveryAgentModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        accountants: accountantsResponse
            .map(
              (e) => DeliveryAgentModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
        hrStaff: hrStaffResponse
            .map(
              (e) => DeliveryAgentModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList(),
      );
    } catch (_) {}
  }

  Future<List<Map<String, dynamic>>> searchStaffUsers({
    String search = '',
    int limit = 100,
  }) async {
    final rows = await ref
        .read(ownerApiProvider)
        .searchStaffUsers(search: search, limit: limit);
    return rows
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Future<bool> createDeliveryAgent({
    required String fullName,
    required String phone,
    required String pin,
    LocalImageFile? imageFile,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref.read(ownerApiProvider).createDeliveryAgent({
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'pin': pin.trim(),
      }, imageFile: imageFile);
      await _reloadStaffLists();
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('create_delivery_account_failed'),
      );
      return false;
    }
  }

  Future<bool> createAccountant({
    required String fullName,
    required String phone,
    required String pin,
    LocalImageFile? imageFile,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref.read(ownerApiProvider).createAccountant({
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'pin': pin.trim(),
      }, imageFile: imageFile);
      await _reloadStaffLists();
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('create_accountant_failed'),
      );
      return false;
    }
  }

  Future<bool> createHrStaff({
    required String fullName,
    required String phone,
    required String pin,
    LocalImageFile? imageFile,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref.read(ownerApiProvider).createHrStaff({
        'fullName': fullName.trim(),
        'phone': phone.trim(),
        'pin': pin.trim(),
      }, imageFile: imageFile);
      await _reloadStaffLists();
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('create_hr_account_failed'),
      );
      return false;
    }
  }

  Future<bool> assignExistingDeliveryAgent({required int userId}) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .assignExistingDeliveryAgent(userId: userId);
      await _reloadStaffLists();
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: _ownerText('assign_existing_delivery_failed'),
      );
      return false;
    }
  }

  Future<bool> assignExistingAccountant({required int userId}) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref.read(ownerApiProvider).assignExistingAccountant(userId: userId);
      await _reloadStaffLists();
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerAssignExistingAccountantFailed,
        ),
      );
      return false;
    }
  }

  Future<bool> assignExistingHrStaff({required int userId}) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref.read(ownerApiProvider).assignExistingHrStaff(userId: userId);
      await _reloadStaffLists();
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerAssignExistingHrStaffFailed,
        ),
      );
      return false;
    }
  }

  Future<bool> markOrderItemUnavailable({
    required int orderId,
    required int productId,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .markOrderItemUnavailable(orderId: orderId, productId: productId);
      await refreshOrders(includeHistory: false);
      state = state.copyWith(savingOrder: false);
      return true;
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
      return false;
    } catch (_) {
      state = state.copyWith(
        savingOrder: false,
        error: resolveLocalizedText(
          (l10n) => l10n.ownerMarkOrderItemUnavailableFailed,
        ),
      );
      return false;
    }
  }

  String _ownerText(String code) {
    return resolveLocalizedText((l10n) {
      switch (code) {
        case 'dashboard_load_failed':
          return l10n.ownerDashboardLoadFailed;
        case 'financial_terms_accept_failed':
          return l10n.ownerFinancialTermsAcceptFailed;
        case 'financial_terms_reject_failed':
          return l10n.ownerFinancialTermsRejectFailed;
        case 'merchant_update_failed':
          return l10n.ownerMerchantUpdateFailed;
        case 'product_create_failed':
          return l10n.ownerProductCreateFailed;
        case 'product_update_failed':
          return l10n.ownerProductUpdateFailed;
        case 'product_delete_failed':
          return l10n.ownerProductDeleteFailed;
        case 'category_create_failed':
          return l10n.ownerCategoryCreateFailed;
        case 'category_update_failed':
          return l10n.ownerCategoryUpdateFailed;
        case 'category_delete_failed':
          return l10n.ownerCategoryDeleteFailed;
        case 'order_status_update_failed':
          return l10n.ownerOrderStatusUpdateFailed;
        case 'assign_delivery_failed':
          return l10n.ownerAssignDeliveryFailed;
        case 'order_preparation_start_failed':
          return l10n.ownerOrderPreparationStartFailed;
        case 'order_ready_status_failed':
          return l10n.ownerOrderReadyStatusFailed;
        case 'receivable_invoices_load_failed':
          return l10n.ownerReceivablesInvoicesLoadFailed;
        case 'receivable_preview_failed':
          return l10n.ownerReceivablesPreviewSelectionFailed;
        case 'payment_request_invoices_load_failed':
          return l10n.ownerReceivablesRequestInvoicesLoadFailed;
        case 'courier_update_failed':
          return l10n.ownerCouriersUpdateFailed;
        case 'create_delivery_account_failed':
          return l10n.ownerCreateDeliveryAccountFailed;
        case 'create_accountant_failed':
          return l10n.ownerCreateAccountantFailed;
        case 'create_hr_account_failed':
          return l10n.ownerCreateHrAccountFailed;
        case 'assign_existing_delivery_failed':
          return l10n.ownerAssignExistingDeliveryFailed;
        default:
          return l10n.commonUnexpectedError;
      }
    });
  }

  String _mapError(DioException e) {
    return mapDioErrorL10n(
      e,
      fallbackBuilder: (l10n) => l10n.commonUnexpectedError,
      appendRequestId: true,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    stopLiveOrders();
    super.dispose();
  }
}
