import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../forms/backend_field_error_parser.dart' as form_errors;
import '../../l10n/app_localizations.dart';
import '../utils/parsers.dart';

String mapDioError(
  DioException error, {
  required String fallback,
  Map<String, String> customMessages = const {},
  bool appendRequestId = false,
}) {
  final l10n = _currentL10n();
  if (_isConnectionError(error)) {
    return _withRequestId(
      l10n.commonNoInternet,
      _extractRequestId(error.response?.data),
      appendRequestId,
    );
  }

  final response = error.response;
  final data = response?.data;
  final requestId = _extractRequestId(data);
  final apiCode = _extractMessageCode(data);
  final apiText = _extractMessageText(data);

  if (apiCode == 'VALIDATION_ERROR') {
    final validationMessage = _buildValidationMessage(data, l10n);
    if (validationMessage != null) {
      return _withRequestId(validationMessage, requestId, appendRequestId);
    }
  }

  if (apiCode != null) {
    final mapped =
        customMessages[apiCode] ??
        _messageForCode(l10n, apiCode) ??
        (_isLikelyErrorCode(apiCode) ? fallback : apiCode);
    return _withRequestId(normalizeText(mapped), requestId, appendRequestId);
  }

  if (apiText != null && apiText.isNotEmpty) {
    final normalized = normalizeText(apiText);
    final message = _isLikelyErrorCode(normalized) ? fallback : normalized;
    return _withRequestId(message, requestId, appendRequestId);
  }

  return _withRequestId(normalizeText(fallback), requestId, appendRequestId);
}

form_errors.ParsedBackendFieldErrors parseBackendFieldErrors(Object? source) =>
    form_errors.parseBackendFieldErrors(source);

String? _buildValidationMessage(dynamic data, AppLocalizations l10n) {
  final parsed = form_errors.parseBackendFieldErrors(data);
  if (!parsed.hasAnyErrors) return null;

  final lines = <String>[];
  for (final entry in parsed.fieldCodes.entries) {
    lines.add(_validationFieldCodeMessage(l10n, entry.key, entry.value));
  }

  final formCode = parsed.formCode?.trim().toUpperCase();
  if (formCode != null && formCode.isNotEmpty) {
    lines.add(resolveApiErrorCodeMessage(l10n, formCode) ?? l10n.apiValidationError);
  }

  final compact = lines
      .map((line) => normalizeText(line).trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  if (compact.isEmpty) return null;
  return compact.join('\n');
}

String _validationFieldCodeMessage(
  AppLocalizations l10n,
  String field,
  String? code,
) {
  final normalizedCode = code?.trim().toUpperCase();
  switch (normalizedCode) {
    case 'PHONE_EXISTS':
    case 'INVALID_CREDENTIALS':
    case 'MESSAGE_REQUIRED':
      return resolveApiErrorCodeMessage(l10n, normalizedCode!) ??
          _validationFieldMessage(l10n, field);
  }

  final mapped = normalizedCode == null
      ? null
      : resolveApiErrorCodeMessage(l10n, normalizedCode);
  return mapped ?? _validationFieldMessage(l10n, field);
}

String _validationFieldMessage(AppLocalizations l10n, String field) {
  switch (field) {
    case 'amount':
      return l10n.validationAmountInvalid;
    case 'paymentDate':
      return l10n.validationPaymentDateInvalid;
    case 'paymentAt':
      return l10n.validationPaymentAtInvalid;
    case 'paymentMethod':
      return l10n.validationPaymentMethodInvalid;
    case 'paymentMethodOther':
      return l10n.validationPaymentMethodOtherRequired;
    case 'selectionMode':
      return l10n.validationSelectionModeRequired;
    case 'selectedInvoiceIds':
      return l10n.validationSelectedInvoiceIdsRequired;
    case 'targetAmount':
      return l10n.validationTargetAmountInvalid;
    case 'referenceCode':
      return l10n.validationReferenceCodeInvalid;
    case 'receiverName':
      return l10n.validationReceiverNameInvalid;
    case 'requestType':
      return l10n.validationRequestTypeInvalid;
    case 'paymentScope':
      return l10n.validationPaymentScopeInvalid;
    case 'driverType':
      return l10n.validationDriverTypeInvalid;
    case 'merchantId':
      return l10n.validationMerchantRequired;
    case 'isActive':
      return l10n.validationCouponActiveFlagRequired;
    default:
      return l10n.validationReviewField(field);
  }
}

String? resolveApiErrorCodeMessage(AppLocalizations l10n, String code) {
  return _messageForCode(l10n, code);
}

String? _messageForCode(AppLocalizations l10n, String code) {
  switch (code) {
    case 'INVALID_CREDENTIALS':
      return l10n.apiInvalidCredentials;
    case 'INVALID_CURRENT_PIN':
      return l10n.apiInvalidCurrentPin;
    case 'PHONE_EXISTS':
      return l10n.apiPhoneExists;
    case 'VALIDATION_ERROR':
      return l10n.apiValidationError;
    case 'CATEGORY_REQUIRED':
      return l10n.apiCategoryRequired;
    case 'CATEGORY_INVALID':
      return l10n.apiCategoryInvalid;
    case 'CATEGORY_NOT_FOUND':
      return l10n.apiCategoryNotFound;
    case 'CATEGORY_HAS_PRODUCTS':
      return l10n.apiCategoryHasProducts;
    case 'ORDER_ITEM_NOT_FOUND':
      return l10n.apiOrderItemNotFound;
    case 'PRODUCT_UNAVAILABLE':
      return l10n.apiProductUnavailable;
    case 'INVALID_TOKEN':
      return l10n.apiInvalidToken;
    case 'NO_TOKEN':
      return l10n.apiNoToken;
    case 'SERVER_ERROR':
      return l10n.apiServerError;
    case 'ROUTE_NOT_FOUND':
      return l10n.apiRouteNotFound;
    case 'FORBIDDEN_OWNER_ONLY':
      return l10n.apiForbiddenOwnerOnly;
    case 'FORBIDDEN_DELIVERY_ONLY':
      return l10n.apiForbiddenDeliveryOnly;
    case 'ORDER_NOT_FOUND':
      return l10n.apiOrderNotFound;
    case 'NO_OPEN_RECEIVABLE_INVOICES':
      return l10n.apiNoOpenReceivableInvoices;
    case 'INVALID_SELECTED_RECEIVABLE_INVOICES':
      return l10n.apiInvalidSelectedReceivableInvoices;
    case 'PAYMENT_REQUEST_AMOUNT_CONFIRMATION_REQUIRED':
      return l10n.apiPaymentRequestAmountConfirmationRequired;
    case 'PAYMENT_REQUEST_SELECTION_OUTDATED':
      return l10n.apiPaymentRequestSelectionOutdated;
    case 'PAYMENT_REQUEST_SELECTION_AMOUNT_CHANGED':
      return l10n.apiPaymentRequestSelectionAmountChanged;
    case 'ORDER_PREPARING_NOT_ALLOWED':
      return l10n.apiOrderPreparingNotAllowed;
    case 'ORDER_ASSIGNMENT_NOT_ALLOWED':
      return l10n.apiOrderAssignmentNotAllowed;
    case 'ORDER_READY_NOT_ALLOWED':
      return l10n.apiOrderReadyNotAllowed;
    case 'COURIER_NOT_AVAILABLE':
      return l10n.apiCourierNotAvailable;
    case 'COURIER_NOT_ALLOWED':
      return l10n.apiCourierNotAllowed;
    case 'STORE_DRIVER_MERCHANT_REQUIRED':
      return l10n.apiStoreDriverMerchantRequired;
    case 'DELIVERY_DRIVER_TYPE_CHANGE_BLOCKED_BY_ACTIVE_ORDERS':
      return l10n.apiDeliveryDriverTypeChangeBlockedByActiveOrders;
    case 'ORDER_ALREADY_ASSIGNED':
      return l10n.apiOrderAlreadyAssigned;
    case 'ASSIGNMENT_NOT_AVAILABLE':
      return l10n.apiAssignmentNotAvailable;
    case 'ANALYTICS_CONSENT_REQUIRED':
      return l10n.apiAnalyticsConsentRequired;
    case 'DELIVERY_ACCOUNT_PENDING_APPROVAL':
      return l10n.apiDeliveryAccountPendingApproval;
    case 'DELIVERY_SUBSCRIPTION_EXPIRED':
      return l10n.apiDeliverySubscriptionExpired;
    case 'DELIVERY_SUBSCRIPTION_PAYMENT_PENDING':
      return l10n.apiDeliverySubscriptionPaymentPending;
    case 'ACCOUNT_DISABLED':
      return 'This account has been disabled by admin.';
    case 'PROFILE_CORE_EDIT_LOCKED':
      return l10n.apiProfileCoreEditLocked;
    case 'TAXI_ACTIVE_RIDE_EXISTS':
      return l10n.apiTaxiActiveRideExists;
    case 'TAXI_RIDE_NOT_ACCEPTING_BIDS':
      return l10n.apiTaxiRideNotAcceptingBids;
    case 'TAXI_RIDE_OUT_OF_RANGE':
      return l10n.apiTaxiRideOutOfRange;
    case 'TAXI_NO_ACTIVE_BID':
      return l10n.apiTaxiNoActiveBid;
    case 'TAXI_CHAT_EMPTY_MESSAGE':
      return l10n.apiTaxiChatEmptyMessage;
    case 'TAXI_CHAT_CLOSED':
      return l10n.apiTaxiChatClosed;
    case 'TAXI_CALL_PEER_NOT_AVAILABLE':
      return l10n.apiTaxiCallPeerNotAvailable;
    case 'TAXI_CALL_SESSION_NOT_FOUND':
      return l10n.apiTaxiCallSessionNotFound;
    case 'TAXI_RIDE_NOT_COMPLETED':
      return l10n.apiTaxiRideNotCompleted;
    case 'TAXI_RIDE_CAPTAIN_NOT_FOUND':
      return l10n.apiTaxiRideCaptainNotFound;
    case 'PROPERTY_SELLER_SUBSCRIPTION_REQUIRED':
      return l10n.apiPropertySellerRequired;
    case 'REAL_ESTATE_LISTING_NOT_FOUND':
      return l10n.apiRealEstateNotFound;
    case 'PIN_UNCHANGED':
      return l10n.authUpdatePinUnchanged;
    case 'NO_CHANGES':
      return l10n.authUpdateNoChanges;
    case 'MESSAGE_REQUIRED':
      return l10n.validationMessageRequired;
    default:
      return null;
  }
}

String mapAnyError(
  Object error, {
  required String fallback,
  Map<String, String> customMessages = const {},
  bool appendRequestId = false,
}) {
  if (error is DioException) {
    return mapDioError(
      error,
      fallback: fallback,
      customMessages: customMessages,
      appendRequestId: appendRequestId,
    );
  }
  return normalizeText(fallback);
}

String mapDioErrorL10n(
  DioException error, {
  required String Function(AppLocalizations l10n) fallbackBuilder,
  Map<String, String> customMessages = const {},
  bool appendRequestId = false,
}) {
  final l10n = _currentL10n();
  return mapDioError(
    error,
    fallback: fallbackBuilder(l10n),
    customMessages: customMessages,
    appendRequestId: appendRequestId,
  );
}

String mapAnyErrorL10n(
  Object error, {
  required String Function(AppLocalizations l10n) fallbackBuilder,
  Map<String, String> customMessages = const {},
  bool appendRequestId = false,
}) {
  if (error is DioException) {
    return mapDioErrorL10n(
      error,
      fallbackBuilder: fallbackBuilder,
      customMessages: customMessages,
      appendRequestId: appendRequestId,
    );
  }
  return normalizeText(fallbackBuilder(_currentL10n()));
}

String resolveLocalizedText(String Function(AppLocalizations l10n) builder) {
  return normalizeText(builder(_currentL10n()));
}

bool _isConnectionError(DioException error) {
  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;
}

String _withRequestId(String message, String? requestId, bool appendRequestId) {
  if (!appendRequestId || requestId == null || requestId.isEmpty) {
    return message;
  }
  return '$message (ID: $requestId)';
}

String? _extractRequestId(dynamic data) {
  if (data is Map) {
    final id = data['requestId'];
    if (id == null) return null;
    final normalized = normalizeText('$id').trim();
    return normalized.isEmpty ? null : normalized;
  }
  if (data is String) {
    final match = RegExp(r'"requestId"\s*:\s*"([^"]+)"').firstMatch(data);
    return match?.group(1);
  }
  return null;
}

String? _extractMessageCode(dynamic data) {
  if (data is Map) {
    final message = data['message'];
    if (message == null) return null;
    final normalized = normalizeText('$message').trim();
    return normalized.isEmpty ? null : normalized;
  }
  if (data is String) {
    final match = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(data);
    if (match != null) return normalizeText(match.group(1) ?? '').trim();
    final normalized = normalizeText(data).trim();
    return normalized.isEmpty ? null : normalized;
  }
  return null;
}

String? _extractMessageText(dynamic data) {
  if (data == null) return null;
  if (data is String) return data;
  if (data is Map) {
    final message = data['message'];
    if (message is String) return message;
  }
  return null;
}

bool _isLikelyErrorCode(String value) {
  return RegExp(r'^[A-Z0-9_]+$').hasMatch(value);
}

AppLocalizations _currentL10n() {
  final localeCode = Intl.getCurrentLocale().toLowerCase();
  final locale = localeCode.startsWith('en')
      ? const Locale('en')
      : const Locale('ar');
  return lookupAppLocalizations(locale);
}
