import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../data/merchants_api.dart';
import '../models/merchant_model.dart';

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

  MerchantsController(this.ref) : super(const AsyncValue.loading());

  Future<void> load({String? type}) async {
    state = const AsyncValue.loading();

    try {
      final list = await ref.read(merchantsApiProvider).list(type: type);
      final merchants = list
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(MerchantModel.fromJson)
          .toList();
      state = AsyncValue.data(merchants);
    } catch (_) {
      state = const AsyncValue.error('فشل تحميل المتاجر', StackTrace.empty);
    }
  }

  Future<MerchantModel> addMerchant({
    required String name,
    required String type,
    required String description,
    required String phone,
    required String imageUrl,
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
      'description': description,
      'phone': phone,
      'imageUrl': imageUrl,
    };

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
