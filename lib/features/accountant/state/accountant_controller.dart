import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../auth/state/auth_controller.dart';
import '../data/accountant_api.dart';

final accountantApiProvider = Provider<AccountantApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return AccountantApi(dio);
});

class AccountantState {
  final bool loading;
  final bool saving;
  final Map<String, dynamic>? merchant;
  final Map<String, dynamic> summary;
  final List<Map<String, dynamic>> pendingSettlements;
  final List<Map<String, dynamic>> ledger;
  final List<Map<String, dynamic>> pendingPayrollBatches;
  final List<Map<String, dynamic>> payrollItems;
  final String? error;
  final String? successMessage;

  const AccountantState({
    this.loading = false,
    this.saving = false,
    this.merchant,
    this.summary = const {},
    this.pendingSettlements = const [],
    this.ledger = const [],
    this.pendingPayrollBatches = const [],
    this.payrollItems = const [],
    this.error,
    this.successMessage,
  });

  AccountantState copyWith({
    bool? loading,
    bool? saving,
    Map<String, dynamic>? merchant,
    Map<String, dynamic>? summary,
    List<Map<String, dynamic>>? pendingSettlements,
    List<Map<String, dynamic>>? ledger,
    List<Map<String, dynamic>>? pendingPayrollBatches,
    List<Map<String, dynamic>>? payrollItems,
    String? error,
    String? successMessage,
  }) {
    return AccountantState(
      loading: loading ?? this.loading,
      saving: saving ?? this.saving,
      merchant: merchant ?? this.merchant,
      summary: summary ?? this.summary,
      pendingSettlements: pendingSettlements ?? this.pendingSettlements,
      ledger: ledger ?? this.ledger,
      pendingPayrollBatches:
          pendingPayrollBatches ?? this.pendingPayrollBatches,
      payrollItems: payrollItems ?? this.payrollItems,
      error: error,
      successMessage: successMessage,
    );
  }
}

final accountantControllerProvider =
    StateNotifierProvider<AccountantController, AccountantState>(
      (ref) => AccountantController(ref),
    );

class AccountantController extends StateNotifier<AccountantState> {
  final Ref ref;

  AccountantController(this.ref) : super(const AccountantState());

  Future<void> bootstrap() async {
    state = state.copyWith(loading: true, error: null, successMessage: null);
    try {
      final api = ref.read(accountantApiProvider);
      final summaryFuture = api.getSummary();
      final payrollFuture = api.listPendingPayrollBatches();
      await Future.wait([summaryFuture, payrollFuture]);
      final response = await summaryFuture;
      final payroll = await payrollFuture;
      state = state.copyWith(
        loading: false,
        merchant: response['merchant'] is Map
            ? Map<String, dynamic>.from(response['merchant'] as Map)
            : null,
        summary: response['summary'] is Map
            ? Map<String, dynamic>.from(response['summary'] as Map)
            : const {},
        pendingSettlements:
            (response['pendingSettlements'] as List? ?? const [])
                .map((e) => Map<String, dynamic>.from(e as Map))
                .toList(),
        ledger: (response['ledger'] as List? ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
        pendingPayrollBatches: ((payroll['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _accountantText((l10n) => l10n.accountantDashboardLoadFailed),
      );
    }
  }

  Future<void> confirmSettlement({
    required int settlementId,
    String? note,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref
          .read(accountantApiProvider)
          .confirmSettlement(settlementId: settlementId, note: note);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        successMessage: _accountantText(
          (l10n) => l10n.accountantSettlementConfirmSuccess,
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _accountantText(
          (l10n) => l10n.accountantSettlementConfirmFailed,
        ),
      );
    }
  }

  Future<void> addOpeningBalance({required num amount, String? note}) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref
          .read(accountantApiProvider)
          .addOpeningBalance(amount: amount, note: note);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        successMessage: _accountantText(
          (l10n) => l10n.accountantOpeningBalanceAddSuccess,
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _accountantText(
          (l10n) => l10n.accountantOpeningBalanceAddFailed,
        ),
      );
    }
  }

  Future<void> addExpense({required num amount, String? note}) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref
          .read(accountantApiProvider)
          .addExpense(amount: amount, note: note);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        successMessage: _accountantText(
          (l10n) => l10n.accountantExpenseAddSuccess,
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _accountantText((l10n) => l10n.accountantExpenseAddFailed),
      );
    }
  }

  Future<void> openPayrollBatch(int batchId) async {
    state = state.copyWith(loading: true, error: null, successMessage: null);
    try {
      final response = await ref
          .read(accountantApiProvider)
          .getPayrollBatch(batchId);
      state = state.copyWith(
        loading: false,
        payrollItems: ((response['items'] as List?) ?? const [])
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList(),
      );
    } on DioException catch (e) {
      state = state.copyWith(loading: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        loading: false,
        error: _accountantText((l10n) => l10n.accountantPayrollBatchOpenFailed),
      );
    }
  }

  Future<void> acknowledgePayrollBatch(int batchId) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref.read(accountantApiProvider).acknowledgePayrollBatch(batchId);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        successMessage: _accountantText(
          (l10n) => l10n.accountantPayrollBatchAcknowledgeSuccess,
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _accountantText(
          (l10n) => l10n.accountantPayrollBatchAcknowledgeFailed,
        ),
      );
    }
  }

  Future<void> markPayrollItemPaid({
    required int itemId,
    String? payoutNote,
  }) async {
    state = state.copyWith(saving: true, error: null, successMessage: null);
    try {
      await ref
          .read(accountantApiProvider)
          .markPayrollItemPaid(itemId: itemId, payoutNote: payoutNote);
      await bootstrap();
      state = state.copyWith(
        saving: false,
        successMessage: _accountantText(
          (l10n) => l10n.accountantPayrollItemPaidSuccess,
        ),
      );
    } on DioException catch (e) {
      state = state.copyWith(saving: false, error: _mapError(e));
    } catch (_) {
      state = state.copyWith(
        saving: false,
        error: _accountantText((l10n) => l10n.accountantPayrollItemPaidFailed),
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

  String _accountantText(String Function(dynamic l10n) builder) {
    return resolveLocalizedText(builder);
  }
}
