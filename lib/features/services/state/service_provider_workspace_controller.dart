// ignore_for_file: use_null_aware_elements

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/services_api.dart';
import '../models/service_models.dart';

class ServiceProviderWorkspaceState {
  final bool loadingWorkspace;
  final bool loadingRequests;
  final ServiceProviderWorkspaceModel? workspace;
  final List<ServiceRequestModel> requests;
  final String? error;
  final bool workspaceMissingProfile;

  const ServiceProviderWorkspaceState({
    this.loadingWorkspace = false,
    this.loadingRequests = false,
    this.workspace,
    this.requests = const <ServiceRequestModel>[],
    this.error,
    this.workspaceMissingProfile = false,
  });

  ServiceProviderWorkspaceState copyWith({
    bool? loadingWorkspace,
    bool? loadingRequests,
    ServiceProviderWorkspaceModel? workspace,
    bool clearWorkspace = false,
    List<ServiceRequestModel>? requests,
    String? error,
    bool clearError = false,
    bool? workspaceMissingProfile,
  }) {
    return ServiceProviderWorkspaceState(
      loadingWorkspace: loadingWorkspace ?? this.loadingWorkspace,
      loadingRequests: loadingRequests ?? this.loadingRequests,
      workspace: clearWorkspace ? null : (workspace ?? this.workspace),
      requests: requests ?? this.requests,
      error: clearError ? null : error,
      workspaceMissingProfile:
          workspaceMissingProfile ?? this.workspaceMissingProfile,
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
  }

  Future<void> loadWorkspace() async {
    state = state.copyWith(loadingWorkspace: true, clearError: true);
    try {
      final raw = await ref.read(servicesApiProvider).getProviderWorkspace();
      final workspace = ServiceProviderWorkspaceModel.fromJson(raw);
      state = state.copyWith(
        loadingWorkspace: false,
        workspace: workspace,
        clearError: true,
        workspaceMissingProfile: false,
      );
      final canViewRequests =
          workspace.access?.isOwner == true ||
          workspace.access?.permissionMap['view_service_requests'] == true;
      if (canViewRequests) {
        await loadRequests();
      } else {
        state = state.copyWith(requests: const <ServiceRequestModel>[]);
      }
    } on DioException catch (e) {
      final missingProfile = _isMissingWorkspaceProfileError(e);
      state = state.copyWith(
        loadingWorkspace: false,
        clearWorkspace: missingProfile,
        workspaceMissingProfile: missingProfile,
        error: missingProfile ? null : '$e',
      );
    } catch (e) {
      state = state.copyWith(
        loadingWorkspace: false,
        workspaceMissingProfile: false,
        error: '$e',
      );
    }
  }

  Future<void> loadRequests({String? status}) async {
    final workspace = state.workspace;
    final canViewRequests =
        workspace?.access?.isOwner == true ||
        workspace?.access?.permissionMap['view_service_requests'] == true;
    if (!canViewRequests) {
      state = state.copyWith(requests: const <ServiceRequestModel>[]);
      return;
    }
    state = state.copyWith(loadingRequests: true, clearError: true);
    try {
      final rows = await ref
          .read(servicesApiProvider)
          .listProviderRequests(status: status, limit: 100, offset: 0);
      state = state.copyWith(
        loadingRequests: false,
        requests: rows.map(ServiceRequestModel.fromJson).toList(),
        clearError: true,
      );
    } catch (e) {
      state = state.copyWith(loadingRequests: false, error: '$e');
    }
  }

  bool _isMissingWorkspaceProfileError(Object error) {
    if (error is DioException) {
      final statusCode = error.response?.statusCode;
      if (statusCode == 404) return true;
      final data = error.response?.data;
      if (data is Map) {
        final message = '${data['message'] ?? data['error'] ?? ''}'
            .trim()
            .toUpperCase();
        return message.contains('SERVICE_PROVIDER_PROFILE_NOT_FOUND') ||
            message.contains('PROFILE_NOT_FOUND');
      }
      return false;
    }
    final message = '$error'.trim().toUpperCase();
    return message.contains('SERVICE_PROVIDER_PROFILE_NOT_FOUND') ||
        message.contains('PROFILE_NOT_FOUND');
  }

  Future<void> inviteEmployee(Map<String, dynamic> payload) async {
    try {
      await ref.read(servicesApiProvider).inviteProviderEmployee(payload);
      await loadWorkspace();
    } catch (e) {
      state = state.copyWith(error: '$e');
    }
  }

  Future<void> upsertEmployee(Map<String, dynamic> payload) async {
    try {
      await ref.read(servicesApiProvider).upsertProviderEmployee(payload);
      await loadWorkspace();
    } catch (e) {
      state = state.copyWith(error: '$e');
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
