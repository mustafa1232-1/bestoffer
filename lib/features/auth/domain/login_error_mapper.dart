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

  if (code == 'FORBIDDEN_APP_SURFACE') {
    return l10n.localeName.startsWith('ar')
        ? 'هذا الحساب غير مسموح له على هذه الواجهة.'
        : 'This account is not allowed on this app surface.';
  }

  if (code == 'ACCOUNT_LOCKED' || status == 423) {
    return l10n.localeName.startsWith('ar')
        ? 'تم قفل الحساب مؤقتاً بسبب محاولات دخول متكررة. انتظر قليلاً ثم حاول مرة أخرى.'
        : 'This account is temporarily locked after repeated sign-in attempts. Wait a moment, then try again.';
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
  if (error.type == DioExceptionType.connectionError ||
      error.type == DioExceptionType.connectionTimeout ||
      error.type == DioExceptionType.sendTimeout ||
      error.type == DioExceptionType.receiveTimeout) {
    return true;
  }
  final rawError = '${error.error ?? ''}'.toLowerCase();
  return error.response == null &&
      error.type == DioExceptionType.unknown &&
      (rawError.contains('socket') ||
          rawError.contains('failed host lookup') ||
          rawError.contains('name resolution') ||
          rawError.contains('remote name could not be resolved'));
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
