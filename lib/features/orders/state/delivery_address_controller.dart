import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/backend_field_error_parser.dart'
    show ParsedBackendFieldErrors;
import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
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
  final ParsedBackendFieldErrors? validationError;

  const DeliveryAddressState({
    this.loading = false,
    this.saving = false,
    this.addresses = const [],
    this.selectedAddressId,
    this.error,
    this.validationError,
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
    ParsedBackendFieldErrors? validationError,
  }) {
    return DeliveryAddressState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      addresses: addresses ?? this.addresses,
      selectedAddressId: clearSelection
          ? null
          : selectedAddressId ?? this.selectedAddressId,
      error: error,
      validationError: validationError,
    );
  }
}

class DeliveryAddressController extends StateNotifier<DeliveryAddressState> {
  final Ref ref;

  DeliveryAddressController(this.ref) : super(const DeliveryAddressState());

  Future<void> bootstrap({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(
        loading: true,
        error: null,
        validationError: null,
      );
    }
    try {
      var raw = await ref.read(ordersApiProvider).listDeliveryAddresses();
      var addresses = raw
          .map(
            (e) => DeliveryAddressModel.fromJson(
              Map<String, dynamic>.from(e as Map),
            ),
          )
          .toList();

      if (addresses.isEmpty && await _ensurePrimaryAddressFromAccount()) {
        raw = await ref.read(ordersApiProvider).listDeliveryAddresses();
        addresses = raw
            .map(
              (e) => DeliveryAddressModel.fromJson(
                Map<String, dynamic>.from(e as Map),
              ),
            )
            .toList();
      }

      int? nextSelected = state.selectedAddressId;
      if (addresses.isEmpty) {
        nextSelected = null;
      } else {
        final hasCurrent =
            nextSelected != null && addresses.any((a) => a.id == nextSelected);
        if (!hasCurrent) {
          nextSelected = addresses
              .firstWhere((a) => a.isDefault, orElse: () => addresses.first)
              .id;
        }
      }

      state = state.copyWith(
        loading: false,
        addresses: addresses,
        selectedAddressId: nextSelected,
        error: null,
        validationError: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        loading: false,
        error: _mapError(e),
        validationError: parseBackendFieldErrors(e),
      );
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: resolveLocalizedText(
          (l10n) => l10n.deliveryAddressesLoadFailed,
        ),
        validationError: null,
      );
    }
  }

  Future<bool> _ensurePrimaryAddressFromAccount() async {
    final auth = ref.read(authControllerProvider);
    final user = auth.user;
    if (user == null || auth.isBackoffice || auth.isOwner || auth.isDelivery) {
      return false;
    }

    final block = user.block.trim();
    final buildingNumber = user.buildingNumber.trim();
    final apartment = user.apartment.trim();
    if (block.isEmpty || buildingNumber.isEmpty || apartment.isEmpty) {
      return false;
    }

    try {
      await ref.read(ordersApiProvider).createDeliveryAddress({
        'label': resolveLocalizedText(
          (l10n) => l10n.deliveryAddressesDefaultLabel,
        ),
        'city': resolveLocalizedText(
          (l10n) => l10n.deliveryAddressesDefaultCity,
        ),
        'block': block,
        'buildingNumber': buildingNumber,
        'apartment': apartment,
        'isDefault': true,
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  void selectAddress(int addressId) {
    if (!state.addresses.any((a) => a.id == addressId)) return;
    state = state.copyWith(
      selectedAddressId: addressId,
      error: null,
      validationError: null,
    );
  }

  Future<void> createAddress({
    required String label,
    required String city,
    required String block,
    required String buildingNumber,
    required String apartment,
    bool isDefault = false,
  }) async {
    state = state.copyWith(
      saving: true,
      error: null,
      validationError: null,
    );
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
      state = state.copyWith(
        saving: false,
        error: null,
        validationError: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        saving: false,
        error: _mapError(e),
        validationError: parseBackendFieldErrors(e),
      );
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: resolveLocalizedText(
          (l10n) => l10n.deliveryAddressesCreateFailed,
        ),
        validationError: null,
      );
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
    state = state.copyWith(
      saving: true,
      error: null,
      validationError: null,
    );
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
      state = state.copyWith(
        saving: false,
        error: null,
        validationError: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        saving: false,
        error: _mapError(e),
        validationError: parseBackendFieldErrors(e),
      );
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: resolveLocalizedText(
          (l10n) => l10n.deliveryAddressesUpdateFailed,
        ),
        validationError: null,
      );
    }
  }

  Future<void> setDefaultAddress(int addressId) async {
    state = state.copyWith(
      saving: true,
      error: null,
      validationError: null,
    );
    try {
      await ref.read(ordersApiProvider).setDefaultDeliveryAddress(addressId);
      await bootstrap(silent: true);
      state = state.copyWith(
        saving: false,
        selectedAddressId: addressId,
        error: null,
        validationError: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        saving: false,
        error: _mapError(e),
        validationError: parseBackendFieldErrors(e),
      );
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: resolveLocalizedText(
          (l10n) => l10n.deliveryAddressesDefaultFailed,
        ),
        validationError: null,
      );
    }
  }

  Future<void> deleteAddress(int addressId) async {
    state = state.copyWith(
      saving: true,
      error: null,
      validationError: null,
    );
    try {
      await ref.read(ordersApiProvider).deleteDeliveryAddress(addressId);
      await bootstrap(silent: true);
      state = state.copyWith(
        saving: false,
        error: null,
        validationError: null,
      );
    } on DioException catch (e) {
      state = state.copyWith(
        saving: false,
        error: _mapError(e),
        validationError: parseBackendFieldErrors(e),
      );
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: resolveLocalizedText(
          (l10n) => l10n.deliveryAddressesDeleteFailed,
        ),
        validationError: null,
      );
    }
  }

  String _mapError(DioException e) {
    return mapDioErrorL10n(
      e,
      fallbackBuilder: (l10n) => l10n.errorsServerFailure,
      appendRequestId: true,
    );
  }
}
