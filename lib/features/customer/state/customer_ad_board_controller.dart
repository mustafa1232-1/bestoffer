import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../merchants/state/merchants_controller.dart';
import '../models/customer_ad_board_item.dart';

final customerAdBoardControllerProvider =
    StateNotifierProvider<
      CustomerAdBoardController,
      AsyncValue<List<CustomerAdBoardItem>>
    >((ref) => CustomerAdBoardController(ref));

class CustomerAdBoardController
    extends StateNotifier<AsyncValue<List<CustomerAdBoardItem>>> {
  final Ref ref;

  CustomerAdBoardController(this.ref) : super(const AsyncValue.loading()) {
    Future.microtask(load);
  }

  Future<void> load({String? type}) async {
    state = const AsyncValue.loading();
    try {
      final raw = await ref.read(merchantsApiProvider).adBoard(type: type);
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(CustomerAdBoardItem.fromJson)
          .toList();
      state = AsyncValue.data(items);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
