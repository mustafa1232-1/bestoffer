import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery_address_model.dart';
import 'orders_controller.dart';

final deliveryAddressControllerProvider =
    StateNotifierProvider<DeliveryAddressController, DeliveryAddressState>((
      ref,
    ) {
      return DeliveryAddressController(ref);
    });

class DeliveryAddressState {
  final bool loading;
  final bool saving;
  final List<DeliveryAddressModel> addresses;
  final int? selectedAddressId;
  final String? error;

  const DeliveryAddressState({
    this.loading = false,
    this.saving = false,
    this.addresses = const [],
    this.selectedAddressId,
    this.error,
  });

  DeliveryAddressModel? get selectedAddress {
    if (selectedAddressId == null) return null;
    for (final address in addresses) {
      if (address.id == selectedAddressId) return address;
    }
    return null;
  }

  DeliveryAddressState copyWith({
    bool? loading,
    bool? saving,
    List<DeliveryAddressModel>? addresses,
    int? selectedAddressId,
    bool clearSelection = false,
    String? error,
  }) {
    return DeliveryAddressState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      addresses: addresses ?? this.addresses,
      selectedAddressId: clearSelection
          ? null
          : selectedAddressId ?? this.selectedAddressId,
      error: error,
    );
  }
}

class DeliveryAddressController extends StateNotifier<DeliveryAddressState> {
  final Ref ref;

  DeliveryAddressController(this.ref) : super(const DeliveryAddressState());

  Future<void> bootstrap({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(loading: true, error: null);
    }
    try {
      final raw = await ref.read(ordersApiProvider).listDeliveryAddresses();
      final addresses = raw
          .map(
            (e) => DeliveryAddressModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();

      int? nextSelected = state.selectedAddressId;
      if (addresses.isEmpty) {
        nextSelected = null;
      } else {
        final hasCurrent =
            nextSelected != null && addresses.any((a) => a.id == nextSelected);
        if (!hasCurrent) {
          nextSelected =
              addresses.firstWhere((a) => a.isDefault, orElse: () => addresses.first).id;
        }
      }

      state = state.copyWith(
        loading: false,
        addresses: addresses,
        selectedAddressId: nextSelected,
        error: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(loading: false, error: 'تعذر تحميل عناوين التوصيل');
    }
  }

  void selectAddress(int addressId) {
    if (!state.addresses.any((a) => a.id == addressId)) return;
    state = state.copyWith(selectedAddressId: addressId, error: null);
  }

  Future<void> createAddress({
    required String label,
    required String city,
    required String block,
    required String buildingNumber,
    required String apartment,
    bool isDefault = false,
  }) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(ordersApiProvider).createDeliveryAddress({
        'label': label.trim(),
        'city': city.trim(),
        'block': block.trim(),
        'buildingNumber': buildingNumber.trim(),
        'apartment': apartment.trim(),
        'isDefault': isDefault,
      });
      await bootstrap(silent: true);
      state = state.copyWith(saving: false, error: null);
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل إضافة عنوان التوصيل');
    }
  }

  Future<void> updateAddress({
    required int addressId,
    required String label,
    required String city,
    required String block,
    required String buildingNumber,
    required String apartment,
    bool isDefault = false,
  }) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(ordersApiProvider).updateDeliveryAddress(addressId, {
        'label': label.trim(),
        'city': city.trim(),
        'block': block.trim(),
        'buildingNumber': buildingNumber.trim(),
        'apartment': apartment.trim(),
        'isDefault': isDefault,
      });
      await bootstrap(silent: true);
      state = state.copyWith(saving: false, error: null);
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل تحديث عنوان التوصيل');
    }
  }

  Future<void> setDefaultAddress(int addressId) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(ordersApiProvider).setDefaultDeliveryAddress(addressId);
      await bootstrap(silent: true);
      state = state.copyWith(
        saving: false,
        selectedAddressId: addressId,
        error: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: 'فشل تعيين العنوان الافتراضي',
      );
    }
  }

  Future<void> deleteAddress(int addressId) async {
    state = state.copyWith(saving: true, error: null);
    try {
      await ref.read(ordersApiProvider).deleteDeliveryAddress(addressId);
      await bootstrap(silent: true);
      state = state.copyWith(saving: false, error: null);
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'فشل حذف عنوان التوصيل');
    }
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final map = Map<String, dynamic>.from(data);
      final message = map['message'];
      if (message is String && message.isNotEmpty) return message;
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }
}
