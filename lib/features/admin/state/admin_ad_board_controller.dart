import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'admin_controller.dart';
import '../models/ad_board_item_model.dart';

final adminAdBoardControllerProvider =
    StateNotifierProvider<AdminAdBoardController, AdminAdBoardState>(
      (ref) => AdminAdBoardController(ref),
    );

class AdminAdBoardState {
  final bool loading;
  final bool saving;
  final List<AdBoardItemModel> items;
  final String? error;
  final String? success;

  const AdminAdBoardState({
    this.loading = false,
    this.saving = false,
    this.items = const [],
    this.error,
    this.success,
  });

  AdminAdBoardState copyWith({
    bool? loading,
    bool? saving,
    List<AdBoardItemModel>? items,
    String? error,
    String? success,
  }) {
    return AdminAdBoardState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      items: items ?? this.items,
      error: error,
      success: success,
    );
  }
}

class AdminAdBoardController extends StateNotifier<AdminAdBoardState> {
  final Ref ref;

  AdminAdBoardController(this.ref) : super(const AdminAdBoardState());

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null, success: null);
    try {
      final raw = await ref.read(adminApiProvider).adBoardItems();
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .map(AdBoardItemModel.fromJson)
          .toList();
      state = state.copyWith(loading: false, items: items);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: 'تعذر تحميل لوحة الإعلانات',
      );
    }
  }

  Future<void> createItem(Map<String, dynamic> body) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).createAdBoardItem(body);
      await bootstrap();
      state = state.copyWith(saving: false, success: 'تمت إضافة الإعلان بنجاح');
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'تعذر إضافة الإعلان');
    }
  }

  Future<void> updateItem(int itemId, Map<String, dynamic> body) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).updateAdBoardItem(itemId, body);
      await bootstrap();
      state = state.copyWith(saving: false, success: 'تم تحديث الإعلان');
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'تعذر تحديث الإعلان');
    }
  }

  Future<void> deleteItem(int itemId) async {
    state = state.copyWith(saving: true, error: null, success: null);
    try {
      await ref.read(adminApiProvider).deleteAdBoardItem(itemId);
      await bootstrap();
      state = state.copyWith(saving: false, success: 'تم حذف الإعلان');
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(saving: false, error: 'تعذر حذف الإعلان');
    }
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final fields = data['fields'];
      if (fields is List && fields.isNotEmpty) {
        return 'التحقق فشل: ${fields.join(", ")}';
      }
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        return message;
      }
    }
    return 'حدث خطأ في الاتصال بالخادم';
  }
}
