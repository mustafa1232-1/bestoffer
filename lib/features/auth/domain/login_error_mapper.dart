import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';

String mapLoginDioErrorForUser(DioException error) {
  final l10n = _currentL10n();
  final status = error.response?.statusCode ?? 0;
  final code = _extractCode(error.response?.data);

  if (_isConnectionError(error)) {
    return l10n.commonNoInternet;
  }

  if (code == 'ACCOUNT_DISABLED') {
    return _accountDisabledMessage(l10n);
  }

  if (code == 'DELIVERY_ACCOUNT_PENDING_APPROVAL') {
    return l10n.apiDeliveryAccountPendingApproval;
  }

  if (status == 404 || status == 429 || status >= 500) {
    return l10n.apiServerError;
  }

  if (code == 'INVALID_CREDENTIALS' ||
      status == 400 ||
      status == 401 ||
      status == 403 ||
      status == 422) {
    return l10n.authLoginFailedGeneric;
  }

  return l10n.authLoginFailedGeneric;
}

bool _isConnectionError(DioException error) {
  return error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout;
}

String? _extractCode(dynamic data) {
  if (data is Map) {
    final raw = data['message'] ?? data['code'];
    final normalized = '$raw'.trim().toUpperCase();
    return normalized.isEmpty ? null : normalized;
  }
  if (data is String) {
    final normalized = data.trim().toUpperCase();
    return normalized.isEmpty ? null : normalized;
  }
  return null;
}

String _accountDisabledMessage(AppLocalizations l10n) {
  return l10n.localeName.startsWith('ar')
      ? 'تم تعطيل هذا الحساب من قبل الإدارة.'
      : 'This account has been disabled by the administration.';
}

AppLocalizations _currentL10n() {
  final localeCode = Intl.getCurrentLocale().toLowerCase();
  final locale = localeCode.startsWith('en')
      ? const Locale('en')
      : const Locale('ar');
  return lookupAppLocalizations(locale);
}
