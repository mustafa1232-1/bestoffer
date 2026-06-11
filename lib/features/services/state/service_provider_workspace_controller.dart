// ignore_for_file: use_null_aware_elements

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services_api.dart';
import '../models/service_models.dart';

class ServiceProviderWorkspaceState {
  final bool loadingWorkspace;
  final bool loadingRequests;
  final ServiceProviderWorkspaceModel? workspace;
  final List<ServiceRequestModel> requests;
  final String? error;

  const ServiceProviderWorkspaceState({
    this.loadingWorkspace = false,
    this.loadingRequests = false,
    this.workspace,
    this.requests = const <ServiceRequestModel>[],
    this.error,
  });

  ServiceProviderWorkspaceState copyWith({
    bool? loadingWorkspace,
    bool? loadingRequests,
    ServiceProviderWorkspaceModel? workspace,
    bool clearWorkspace = false,
    List<ServiceRequestModel>? requests,
    String? error,
    bool clearError = false,
  }) {
    return ServiceProviderWorkspaceState(
      loadingWorkspace: loadingWorkspace ?? this.loadingWorkspace,
      loadingRequests: loadingRequests ?? this.loadingRequests,
      workspace: clearWorkspace ? null : (workspace ?? this.workspace),
      requests: requests ?? this.requests,
      error: clearError ? null : error,
    );
  }
}

final serviceProviderWorkspaceControllerProvider =
    StateNotifierProvider<
      ServiceProviderWorkspaceController,
      ServiceProviderWorkspaceState
    >((ref) => ServiceProviderWorkspaceController(ref));

class ServiceProviderWorkspaceController
    extends StateNotifier<ServiceProviderWorkspaceState> {
  final Ref ref;

  ServiceProviderWorkspaceController(this.ref)
    : super(const ServiceProviderWorkspaceState()) {
    loadWorkspace();
    loadRequests();
  }

  Future<void> loadWorkspace() async {
    state = state.copyWith(loadingWorkspace: true, clearError: true);
    try {
      final raw = await ref.read(servicesApiProvider).getProviderWorkspace();
      state = state.copyWith(
        loadingWorkspace: false,
        workspace: ServiceProviderWorkspaceModel.fromJson(raw),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loadingWorkspace: false, error: '$e');
    }
  }

  Future<void> loadRequests({String? status}) async {
    state = state.copyWith(loadingRequests: true, clearError: true);
    try {
      final rows = await ref
          .read(servicesApiProvider)
          .listProviderRequests(status: status, limit: 40, offset: 0);
      state = state.copyWith(
        loadingRequests: false,
        requests: rows.map(ServiceRequestModel.fromJson).toList(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loadingRequests: false, error: '$e');
    }
  }

  Future<void> updateRequestStatus({
    required int requestId,
    required String status,
    String? note,
    DateTime? scheduledStartAt,
    DateTime? scheduledEndAt,
  }) async {
    try {
      await ref
          .read(servicesApiProvider)
          .updateProviderRequestStatus(
            requestId: requestId,
            status: status,
            note: note,
            scheduledStartAt: scheduledStartAt,
            scheduledEndAt: scheduledEndAt,
          );
      await loadRequests();
      await loadWorkspace();
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> createQuote({
    required int requestId,
    required String pricingModel,
    required String pricingUnit,
    double? amount,
    double? minAmount,
    double? maxAmount,
    double? visitFee,
    String currency = 'IQD',
    String? note,
  }) async {
    try {
      await ref
          .read(servicesApiProvider)
          .createQuote(
            requestId: requestId,
            payload: {
              'pricingModel': pricingModel,
              'pricingUnit': pricingUnit,
              if (amount != null) 'amount': amount,
              if (minAmount != null) 'minAmount': minAmount,
              if (maxAmount != null) 'maxAmount': maxAmount,
              if (visitFee != null) 'visitFee': visitFee,
              'currency': currency,
              if (note != null && note.trim().isNotEmpty) 'note': note.trim(),
            },
          );
      await loadRequests();
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }
}
