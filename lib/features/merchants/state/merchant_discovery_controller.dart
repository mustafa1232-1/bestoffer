import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/merchant_discovery_model.dart';
import 'merchants_controller.dart';

final merchantDiscoveryControllerProvider =
    StateNotifierProvider<
      MerchantDiscoveryController,
      AsyncValue<MerchantDiscoveryModel?>
    >((ref) => MerchantDiscoveryController(ref));

class MerchantDiscoveryController
    extends StateNotifier<AsyncValue<MerchantDiscoveryModel?>> {
  final Ref ref;
  String? _loadedType;

  MerchantDiscoveryController(this.ref) : super(const AsyncValue.data(null));

  String? get loadedType => _loadedType;

  Future<void> clear() async {
    _loadedType = null;
    state = const AsyncValue.data(null);
  }

  Future<void> load({required String? type, bool force = false}) async {
    final normalizedType = (type ?? '').trim();
    if (normalizedType.isEmpty) {
      await clear();
      return;
    }
    if (!force &&
        _loadedType == normalizedType &&
        state is AsyncData<MerchantDiscoveryModel?>) {
      return;
    }

    state = const AsyncValue.loading();
    try {
      final json = await ref
          .read(merchantsApiProvider)
          .customerDiscovery(type: normalizedType);
      final model = MerchantDiscoveryModel.fromJson(json);
      _loadedType = normalizedType;
      state = AsyncValue.data(model);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
