import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/subscriptions_api.dart';

final subscriptionsApiProvider = Provider<SubscriptionsApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return SubscriptionsApi(dio);
});

class AdminSubscriptionsState {
  final bool loading;
  final bool saving;
  final List<Map<String, dynamic>> invoices;
  final String? error;
  final String? successMessage;

  const AdminSubscriptionsState({
    this.loading = false,
    this.saving = false,
    this.invoices = const [],
    this.error,
    this.successMessage,
  });

  AdminSubscriptionsState copyWith({
    bool? loading,
    bool? saving,
    List<Map<String, dynamic>>? invoices,
    String? error,
    String? successMessage,
  }) {
    return AdminSubscriptionsState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      invoices: invoices ?? this.invoices,
      error: error,
      successMessage: successMessage,
    );
  }
}

final adminSubscriptionsControllerProvider =
    StateNotifierProvider<AdminSubscriptionsController, AdminSubscriptionsState>(
  (ref) => AdminSubscriptionsController(ref),
);

class AdminSubscriptionsController
    extends StateNotifier<AdminSubscriptionsState> {
  AdminSubscriptionsController(this.ref)
      : super(const AdminSubscriptionsState());

  final Ref ref;

  SubscriptionsApi get _api => ref.read(subscriptionsApiProvider);

  List<Map<String, dynamic>> _normalize(List<dynamic> rows) => rows
      .whereType<Map>()
      .map((row) => Map<String, dynamic>.from(row))
      .toList(growable: false);

  String _friendly(Object e) => mapAnyErrorL10n(
        e,
        fallbackBuilder: (_) => 'تعذّر تنفيذ العملية. حاول مرة أخرى.',
      );

  Future<void> bootstrap({String? status}) async {
    state = state.copyWith(loading: true, error: null);
    try {
      final invoices = await _api.adminListInvoices(status: status);
      state = state.copyWith(loading: false, invoices: _normalize(invoices));
    } catch (e) {
      state = state.copyWith(loading: false, error: _friendly(e));
    }
  }

  Future<void> generateCurrentMonth({String? month}) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      final out = await _api.adminGenerate(month: month);
      final generated = (out['generatedCount'] as num?)?.toInt() ?? 0;
      await bootstrap();
      state = state.copyWith(
        saving: false,
        successMessage: 'تم إنشاء $generated فاتورة اشتراك.',
      );
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
    }
  }

  Future<void> recordPayment({
    required int invoiceId,
    required num amount,
    String paymentMethod = 'cash',
    String? notes,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await _api.adminRecordPayment(
        invoiceId: invoiceId,
        amount: amount,
        paymentMethod: paymentMethod,
        notes: notes,
      );
      await bootstrap();
      state = state.copyWith(saving: false, successMessage: 'تم تسجيل الدفعة.');
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
    }
  }

  Future<void> waiveInvoice({
    required int invoiceId,
    required String reason,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await _api.adminWaive(invoiceId: invoiceId, reason: reason);
      await bootstrap();
      state = state.copyWith(saving: false, successMessage: 'تم إعفاء الفاتورة.');
    } catch (e) {
      state = state.copyWith(saving: false, error: _friendly(e));
    }
  }
}
