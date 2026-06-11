import '../../l10n/app_localizations.dart';
import '../network/api_error_mapper.dart';

/// يحول رمز خطأ قادم من الباكند أو التحقق المحلي إلى رسالة نهائية معرّبة
/// قابلة للعرض أسفل الحقل نفسه.
String resolveFormFieldError({
  required AppLocalizations l10n,
  required String field,
  String? code,
  String? fieldLabel,
  String? Function(AppLocalizations l10n, String field, String? code)?
  customResolver,
}) {
  final custom = customResolver?.call(l10n, field, code);
  if (custom != null && custom.trim().isNotEmpty) {
    return custom.trim();
  }

  final normalizedCode = code?.trim().toUpperCase();
  switch (normalizedCode) {
    case null:
    case '':
    case 'REQUIRED':
    case 'MISSING':
      return _requiredMessage(l10n, fieldLabel);
    case 'INVALID_EMAIL':
      return l10n.validationInvalidEmail;
    case 'INVALID_PHONE':
      return l10n.validationInvalidPhone;
    case 'INVALID_PIN':
      return l10n.validationInvalidPin;
    case 'INVALID_NUMBER':
      return l10n.validationInvalidNumber;
    case 'DUPLICATE':
    case 'ALREADY_EXISTS':
    case 'UNIQUE_VIOLATION':
      return l10n.validationValueAlreadyUsed;
    case 'PASSWORD_TOO_SHORT':
      return l10n.validationPasswordTooShort;
    case 'PASSWORD_MISMATCH':
      return l10n.validationPasswordMismatch;
    case 'SELECT_OPTION':
      return l10n.validationSelectOption;
    case 'SELECT_IMAGE':
    case 'IMAGE_REQUIRED':
      return l10n.validationSelectImage;
    case 'SELECT_LOCATION':
    case 'LOCATION_REQUIRED':
      return l10n.validationSelectLocation;
    case 'INVALID_DATE':
      return l10n.validationInvalidDate;
    case 'INVALID_TIME':
      return l10n.validationInvalidTime;
    case 'TOO_LONG':
    case 'INVALID_TEXT':
      return l10n.validationTextTooLong;
    case 'MESSAGE_REQUIRED':
      return fieldLabel == null || fieldLabel.trim().isEmpty
          ? l10n.validationMessageRequired
          : l10n.validationRequiredField(fieldLabel.trim());
    case 'NO_PERMISSION':
    case 'FORBIDDEN':
      return l10n.errorsPermissionDenied;
  }

  final apiMessage = resolveApiErrorCodeMessage(l10n, normalizedCode);
  if (apiMessage != null && apiMessage.trim().isNotEmpty) {
    return apiMessage;
  }

  return fieldLabel == null || fieldLabel.trim().isEmpty
      ? l10n.validationReviewField(field)
      : l10n.validationRequiredField(fieldLabel.trim());
}

String resolveFormLevelError(
  AppLocalizations l10n, {
  String? code,
  String? fallback,
}) {
  final normalizedCode = code?.trim().toUpperCase();
  if (normalizedCode == null || normalizedCode.isEmpty) {
    final normalizedFallback = fallback?.trim();
    if (normalizedFallback != null && normalizedFallback.isNotEmpty) {
      return normalizedFallback;
    }
    return l10n.validationReviewRequiredFields;
  }

  switch (normalizedCode) {
    case 'VALIDATION_ERROR':
    case 'ADDRESS_INVALID':
      return l10n.validationReviewRequiredFields;
    case 'NO_PERMISSION':
    case 'FORBIDDEN':
      return l10n.errorsPermissionDenied;
    case 'BUSINESS_RULE':
      return l10n.errorsBusinessRule;
    case 'SERVER_ERROR':
      return l10n.errorsServerFailure;
  }

  return resolveApiErrorCodeMessage(l10n, normalizedCode) ??
      fallback ??
      l10n.errorsUnknown;
}

String _requiredMessage(AppLocalizations l10n, String? fieldLabel) {
  if (fieldLabel == null || fieldLabel.trim().isEmpty) {
    return l10n.commonRequiredField;
  }
  return l10n.validationRequiredField(fieldLabel.trim());
}
