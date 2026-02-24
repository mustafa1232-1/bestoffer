import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../../delivery/models/delivery_agent_model.dart';
import '../../orders/models/order_model.dart';
import '../../products/models/product_category_model.dart';
import '../../products/models/product_model.dart';
import '../data/owner_api.dart';
import '../models/owner_merchant_model.dart';

final ownerApiProvider = Provider<OwnerApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return OwnerApi(dio);
});

final ownerControllerProvider =
    StateNotifierProvider<OwnerController, OwnerState>((ref) {
      return OwnerController(ref);
    });

class OwnerState {
  final bool loading;
  final bool savingMerchant;
  final bool savingProduct;
  final bool savingOrder;
  final OwnerMerchantModel? merchant;
  final List<ProductCategoryModel> categories;
  final List<ProductModel> products;
  final List<OrderModel> currentOrders;
  final List<OrderModel> historyOrders;
  final List<DeliveryAgentModel> deliveryAgents;
  final Map<String, dynamic> analytics;
  final Map<String, dynamic>? settlementSummary;
  final String? error;

  const OwnerState({
    this.loading = false,
    this.savingMerchant = false,
    this.savingProduct = false,
    this.savingOrder = false,
    this.merchant,
    this.categories = const [],
    this.products = const [],
    this.currentOrders = const [],
    this.historyOrders = const [],
    this.deliveryAgents = const [],
    this.analytics = const {},
    this.settlementSummary,
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
    List<OrderModel>? currentOrders,
    List<OrderModel>? historyOrders,
    List<DeliveryAgentModel>? deliveryAgents,
    Map<String, dynamic>? analytics,
    Map<String, dynamic>? settlementSummary,
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
      currentOrders: currentOrders ?? this.currentOrders,
      historyOrders: historyOrders ?? this.historyOrders,
      deliveryAgents: deliveryAgents ?? this.deliveryAgents,
      analytics: analytics ?? this.analytics,
      settlementSummary: settlementSummary ?? this.settlementSummary,
      error: error,
    );
  }
}

class OwnerController extends StateNotifier<OwnerState> {
  final Ref ref;

  OwnerController(this.ref) : super(const OwnerState());

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null);
    try {
      final merchantResponse = await ref.read(ownerApiProvider).getMerchant();
      final productsResponse = await ref.read(ownerApiProvider).listProducts();
      final categoriesResponse = await ref
          .read(ownerApiProvider)
          .listCategories();
      final currentOrdersResponse = await ref
          .read(ownerApiProvider)
          .listCurrentOrders();
      final historyOrdersResponse = await ref
          .read(ownerApiProvider)
          .listOrderHistory();
      final deliveryAgentsResponse = await ref
          .read(ownerApiProvider)
          .listDeliveryAgents();
      final analyticsResponse = await ref.read(ownerApiProvider).analytics();
      final settlementSummaryResponse = await ref
          .read(ownerApiProvider)
          .settlementSummary();

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

      state = state.copyWith(
        loading: false,
        merchant: merchant,
        categories: categories,
        products: products,
        currentOrders: currentOrders,
        historyOrders: historyOrders,
        deliveryAgents: deliveryAgents,
        analytics: analyticsResponse,
        settlementSummary: settlementSummaryResponse,
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'فشل تحميل بيانات صاحب المتجر',
      );
    }
  }

  Future<void> refreshOrders({String? historyDate}) async {
    try {
      final currentOrdersResponse = await ref
          .read(ownerApiProvider)
          .listCurrentOrders();
      final historyOrdersResponse = await ref
          .read(ownerApiProvider)
          .listOrderHistory(date: historyDate);

      final currentOrders = currentOrdersResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
      final historyOrders = historyOrdersResponse
          .map((e) => OrderModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();

      state = state.copyWith(
        currentOrders: currentOrders,
        historyOrders: historyOrders,
      );
    } on DioException catch (e) {
      state = state.copyWith(error: _mapError(e));
    }
  }

  Future<void> updateMerchant({
    required String name,
    required String type,
    required String description,
    required String phone,
    required String imageUrl,
    LocalImageFile? imageFile,
    required bool isOpen,
  }) async {
    state = state.copyWith(savingMerchant: true, error: null);

    try {
      final response = await ref.read(ownerApiProvider).updateMerchant(
        {
          'name': name.trim(),
          'type': type,
          'description': description.trim(),
          'phone': phone.trim(),
          'imageUrl': imageUrl.trim(),
          'isOpen': isOpen,
        },
        imageFile: imageFile,
      );

      final merchant = OwnerMerchantModel.fromJson(
        Map<String, dynamic>.from(response['merchant'] as Map),
      );

      state = state.copyWith(savingMerchant: false, merchant: merchant);
    } on DioException catch (e) {
      state = state.copyWith(savingMerchant: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        savingMerchant: false,
        error: 'فشل تحديث بيانات المتجر',
      );
    }
  }

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
    required int sortOrder,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).createProduct(
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
          'offerLabel': offerLabel.trim().isEmpty ? null : offerLabel.trim(),
          'isAvailable': isAvailable,
          'sortOrder': sortOrder,
        },
        imageFile: imageFile,
      );

      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(savingProduct: false, error: 'فشل إضافة المنتج');
    }
  }

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
    required int sortOrder,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).updateProduct(
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
          'offerLabel': offerLabel.trim().isEmpty ? null : offerLabel.trim(),
          'isAvailable': isAvailable,
          'sortOrder': sortOrder,
        },
        imageFile: imageFile,
      );

      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(savingProduct: false, error: 'فشل تعديل المنتج');
    }
  }

  Future<void> deleteProduct(int productId) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).deleteProduct(productId);
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(savingProduct: false, error: 'فشل حذف المنتج');
    }
  }

  Future<void> createCategory({
    required String name,
    required int sortOrder,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).createCategory({
        'name': name.trim(),
        'sortOrder': sortOrder,
      });
      await _reloadCategories();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(savingProduct: false, error: 'فشل إضافة الصنف');
    }
  }

  Future<void> updateCategory({
    required int categoryId,
    required String name,
    required int sortOrder,
  }) async {
    state = state.copyWith(savingProduct: true, error: null);
    try {
      await ref.read(ownerApiProvider).updateCategory(categoryId, {
        'name': name.trim(),
        'sortOrder': sortOrder,
      });
      await _reloadCategories();
      await _reloadProducts();
      state = state.copyWith(savingProduct: false);
    } on DioException catch (e) {
      state = state.copyWith(savingProduct: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(savingProduct: false, error: 'فشل تعديل الصنف');
    }
  }

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
      state = state.copyWith(savingProduct: false, error: 'فشل حذف الصنف');
    }
  }

  Future<void> updateOrderStatus({
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
      await refreshOrders();
      state = state.copyWith(savingOrder: false);
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(savingOrder: false, error: 'فشل تحديث حالة الطلب');
    }
  }

  Future<void> assignDelivery({
    required int orderId,
    required int deliveryUserId,
  }) async {
    state = state.copyWith(savingOrder: true, error: null);
    try {
      await ref
          .read(ownerApiProvider)
          .assignDelivery(orderId: orderId, deliveryUserId: deliveryUserId);
      await refreshOrders();
      state = state.copyWith(savingOrder: false);
    } on DioException catch (e) {
      state = state.copyWith(savingOrder: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(savingOrder: false, error: 'فشل إسناد الدلفري');
    }
  }

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
        error: 'فشل إرسال طلب تسديد المستحقات',
      );
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

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) {
        return message;
      }
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }
}
