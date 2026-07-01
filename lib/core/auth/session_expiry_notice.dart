import 'package:flutter/material.dart';

import '../i18n/locale_text.dart';

class SessionExpiryNoticeGate {
  SessionExpiryNoticeGate._();

  static final SessionExpiryNoticeGate instance =
      SessionExpiryNoticeGate._();

  static const Duration _debounceWindow = Duration(seconds: 8);

  DateTime? _lastShownAt;
  bool _showing = false;

  Future<void> show(
    BuildContext context, {
    String? messageArabic,
    String? messageEnglish,
  }) async {
    if (!context.mounted) return;
    final now = DateTime.now();
    if (_showing) return;
    final lastShownAt = _lastShownAt;
    if (lastShownAt != null && now.difference(lastShownAt) < _debounceWindow) {
      return;
    }

    _showing = true;
    _lastShownAt = now;
    try {
      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              context.lt(
                ar: messageArabic ??
                    'انتهت الجلسة الحالية. يمكنك متابعة التصفح كزائر.',
                en: messageEnglish ??
                    'Your session expired. You can continue browsing as a guest.',
              ),
              textDirection: context.appTextDirection,
            ),
          ),
        );
    } finally {
      _showing = false;
    }
  }
}
