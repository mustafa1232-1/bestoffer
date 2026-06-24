import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

bool _appRuntimeErrorPresentationInstalled = false;

void installAppRuntimeErrorPresentation() {
  if (_appRuntimeErrorPresentationInstalled) return;
  ErrorWidget.builder = (details) {
    return _AppRuntimeErrorFallback(details: details);
  };
  _appRuntimeErrorPresentationInstalled = true;
}

class _AppRuntimeErrorFallback extends StatelessWidget {
  final FlutterErrorDetails details;

  const _AppRuntimeErrorFallback({required this.details});

  @override
  Widget build(BuildContext context) {
    final locale = Localizations.maybeLocaleOf(context);
    final isArabic = locale?.languageCode.toLowerCase() == 'ar';
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final background = colorScheme.surface;
    final panel = colorScheme.surfaceContainerHighest;
    final textPrimary = colorScheme.onSurface;
    final textSecondary = colorScheme.onSurfaceVariant;
    final border = colorScheme.outlineVariant;

    final title = isArabic
        ? 'حدث خطأ في هذه الشاشة'
        : 'This screen hit an error';
    final message = isArabic
        ? 'تم إخفاء شاشة الخطأ الحمراء حتى لا يتعطل التطبيق. ارجع خطوة أو أعد فتح هذه الصفحة.'
        : 'The red error screen was suppressed so the app keeps running. Go back or reopen this page.';
    final debugDetails = kReleaseMode ? null : details.exceptionAsString();

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Material(
        color: background,
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: panel,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: border),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          color: textPrimary,
                          size: 28,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          title,
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          message,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: textSecondary,
                          ),
                        ),
                        if (debugDetails != null &&
                            debugDetails.trim().isNotEmpty) ...[
                          const SizedBox(height: 14),
                          SelectableText(
                            debugDetails,
                            maxLines: 6,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: textSecondary,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
