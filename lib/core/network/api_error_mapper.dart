import 'package:dio/dio.dart';

import '../utils/parsers.dart';

const Map<String, String> _defaultApiMessages = {
  'INVALID_CREDENTIALS': 'رقم الهاتف أو الرمز غير صحيح.',
  'INVALID_CURRENT_PIN': 'الرمز الحالي غير صحيح.',
  'PHONE_EXISTS': 'رقم الهاتف مسجل مسبقًا.',
  'VALIDATION_ERROR': 'يرجى التحقق من البيانات المدخلة.',
  'INVALID_TOKEN': 'انتهت الجلسة. يرجى تسجيل الدخول مجددًا.',
  'NO_TOKEN': 'انتهت الجلسة. يرجى تسجيل الدخول مجددًا.',
  'SERVER_ERROR': 'حدث خطأ في الخادم. حاول لاحقًا.',
  'ROUTE_NOT_FOUND': 'الخدمة المطلوبة غير متاحة.',
  'ANALYTICS_CONSENT_REQUIRED':
      'يجب الموافقة على سياسة التحليلات قبل إنشاء الحساب.',
  'DELIVERY_ACCOUNT_PENDING_APPROVAL': 'الحساب بانتظار موافقة الإدارة.',
  'DELIVERY_SUBSCRIPTION_EXPIRED':
      'انتهى الاشتراك. يرجى تسديد المستحقات لإعادة التفعيل.',
  'DELIVERY_SUBSCRIPTION_PAYMENT_PENDING':
      'تم إرسال طلب الدفع. بانتظار موافقة الإدارة.',
  'TAXI_ACTIVE_RIDE_EXISTS': 'لديك رحلة نشطة بالفعل.',
  'TAXI_RIDE_NOT_ACCEPTING_BIDS': 'هذا الطلب لا يستقبل عروضًا حاليًا.',
  'TAXI_RIDE_OUT_OF_RANGE': 'الكابتن خارج نطاق الطلب.',
  'TAXI_NO_ACTIVE_BID': 'لا يوجد عرض نشط حاليًا.',
  'TAXI_CHAT_EMPTY_MESSAGE': 'لا يمكن إرسال رسالة فارغة.',
  'TAXI_CALL_PEER_NOT_AVAILABLE': 'الطرف الآخر غير متاح حاليًا.',
  'TAXI_CALL_SESSION_NOT_FOUND': 'لم يتم العثور على جلسة الاتصال.',
  'TAXI_RIDE_NOT_COMPLETED': 'لا يمكن تقييم الرحلة قبل اكتمالها.',
  'TAXI_RIDE_CAPTAIN_NOT_FOUND': 'لم يتم العثور على الكابتن لهذه الرحلة.',
};

String mapDioError(
  DioException error, {
  required String fallback,
  Map<String, String> customMessages = const {},
  bool appendRequestId = false,
}) {
  if (_isConnectionError(error)) {
    return 'تعذر الاتصال بالخادم. تحقق من الإنترنت وحاول مرة أخرى.';
  }

  final response = error.response;
  final data = response?.data;
  final requestId = _extractRequestId(data);
  final apiCode = _extractMessageCode(data);
  final apiText = _extractMessageText(data);

  if (apiCode != null) {
    final mapped =
        customMessages[apiCode] ??
        _defaultApiMessages[apiCode] ??
        (_isLikelyErrorCode(apiCode) ? fallback : apiCode);
    return _withRequestId(mapped, requestId, appendRequestId);
  }

  if (apiText != null && apiText.isNotEmpty) {
    final normalized = normalizeText(apiText);
    final message = _isLikelyErrorCode(normalized) ? fallback : normalized;
    return _withRequestId(message, requestId, appendRequestId);
  }

  return _withRequestId(fallback, requestId, appendRequestId);
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
  return fallback;
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
    final m = RegExp(r'"requestId"\s*:\s*"([^"]+)"').firstMatch(data);
    return m?.group(1);
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
    final m = RegExp(r'"message"\s*:\s*"([^"]+)"').firstMatch(data);
    if (m != null) return normalizeText(m.group(1) ?? '').trim();
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
