import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import '../data/assistant_api.dart';
import '../models/assistant_chat_models.dart';

final assistantApiProvider = Provider<AssistantApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return AssistantApi(dio);
});

final assistantControllerProvider =
    StateNotifierProvider<AssistantController, AssistantState>((ref) {
      return AssistantController(ref);
    });

class AssistantState {
  final bool loading;
  final bool sending;
  final int? sessionId;
  final List<AssistantMessageModel> messages;
  final List<AssistantMerchantSuggestionModel> merchants;
  final List<AssistantProductSuggestionModel> products;
  final AssistantDraftOrderModel? draftOrder;
  final AssistantCreatedOrderModel? createdOrder;
  final List<AssistantAddressOptionModel> addresses;
  final Map<String, dynamic>? profile;
  final String? error;

  const AssistantState({
    this.loading = false,
    this.sending = false,
    this.sessionId,
    this.messages = const <AssistantMessageModel>[],
    this.merchants = const <AssistantMerchantSuggestionModel>[],
    this.products = const <AssistantProductSuggestionModel>[],
    this.draftOrder,
    this.createdOrder,
    this.addresses = const <AssistantAddressOptionModel>[],
    this.profile,
    this.error,
  });

  AssistantState copyWith({
    bool? loading,
    bool? sending,
    int? sessionId,
    List<AssistantMessageModel>? messages,
    List<AssistantMerchantSuggestionModel>? merchants,
    List<AssistantProductSuggestionModel>? products,
    AssistantDraftOrderModel? draftOrder,
    bool clearDraftOrder = false,
    AssistantCreatedOrderModel? createdOrder,
    bool clearCreatedOrder = false,
    List<AssistantAddressOptionModel>? addresses,
    Map<String, dynamic>? profile,
    String? error,
  }) {
    return AssistantState(
      loading: loading ?? this.loading,
      sending: sending ?? this.sending,
      sessionId: sessionId ?? this.sessionId,
      messages: messages ?? this.messages,
      merchants: merchants ?? this.merchants,
      products: products ?? this.products,
      draftOrder: clearDraftOrder ? null : draftOrder ?? this.draftOrder,
      createdOrder: clearCreatedOrder
          ? null
          : createdOrder ?? this.createdOrder,
      addresses: addresses ?? this.addresses,
      profile: profile ?? this.profile,
      error: error,
    );
  }
}

class AssistantController extends StateNotifier<AssistantState> {
  final Ref ref;

  AssistantController(this.ref) : super(const AssistantState());

  Future<void> loadCurrentSession({int? sessionId}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final json = await ref
          .read(assistantApiProvider)
          .getCurrentSession(sessionId: sessionId, limit: 50);
      _applyPayload(json, loading: false);
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(loading: false, error: 'تعذر تحميل جلسة المساعد');
    }
  }

  Future<void> sendMessage(
    String message, {
    int? addressId,
    bool createDraft = false,
  }) async {
    final cleanMessage = message.trim();
    if (cleanMessage.isEmpty) return;

    final optimisticMessage = AssistantMessageModel(
      id: -(DateTime.now().millisecondsSinceEpoch),
      role: 'user',
      text: cleanMessage,
      metadata: null,
      createdAt: DateTime.now(),
    );

    state = state.copyWith(
      sending: true,
      error: null,
      clearCreatedOrder: true,
      messages: [...state.messages, optimisticMessage],
    );

    try {
      final json = await ref
          .read(assistantApiProvider)
          .chat(
            message: cleanMessage,
            sessionId: state.sessionId,
            addressId: addressId,
            createDraft: createDraft,
          );
      _applyPayload(json, sending: false);
    } on DioException catch (e) {
      state = state.copyWith(sending: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        sending: false,
        error: 'تعذر إرسال الرسالة إلى المساعد',
      );
    }
  }

  Future<void> confirmDraft({
    required String token,
    int? addressId,
    String? note,
  }) async {
    state = state.copyWith(sending: true, error: null);
    try {
      final json = await ref
          .read(assistantApiProvider)
          .confirmDraft(
            token: token,
            sessionId: state.sessionId,
            addressId: addressId,
            note: note,
          );
      _applyPayload(json, sending: false);
    } on DioException catch (e) {
      state = state.copyWith(sending: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(sending: false, error: 'تعذر تثبيت المسودة');
    }
  }

  void clearCreatedOrder() {
    state = state.copyWith(clearCreatedOrder: true, error: null);
  }

  void _applyPayload(
    Map<String, dynamic> json, {
    bool? loading,
    bool? sending,
  }) {
    final payload = AssistantChatPayloadModel.fromJson(json);
    state = state.copyWith(
      loading: loading ?? state.loading,
      sending: sending ?? state.sending,
      sessionId: payload.sessionId,
      messages: payload.messages,
      merchants: payload.merchants,
      products: payload.products,
      draftOrder: payload.draftOrder,
      clearDraftOrder: payload.draftOrder == null,
      createdOrder: payload.createdOrder,
      clearCreatedOrder: payload.createdOrder == null,
      addresses: payload.addresses,
      profile: payload.profile,
      error: null,
    );
  }

  String _mapError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.isNotEmpty) {
        switch (message) {
          case 'DRAFT_NOT_FOUND':
            return 'المسودة غير موجودة أو منتهية';
          case 'DRAFT_EXPIRED':
            return 'انتهت صلاحية المسودة. أعد الطلب من المساعد';
          case 'ADDRESS_REQUIRED':
            return 'اختر عنوان توصيل قبل تثبيت الطلب';
          case 'MESSAGE_REQUIRED':
            return 'اكتب رسالة أولاً';
          default:
            return message;
        }
      }
    }
    return 'حدث خطأ أثناء الاتصال بالخادم';
  }
}
