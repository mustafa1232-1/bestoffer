import 'package:flutter/material.dart';

/// عنصر عرض موحد لرسائل الأخطاء أسفل widgets التي لا تملك `errorText`
/// مدمجاً داخل `InputDecoration` مثل upload/location المركب.
class InlineFieldErrorText extends StatelessWidget {
  final String? text;
  final EdgeInsetsGeometry padding;

  const InlineFieldErrorText({
    super.key,
    required this.text,
    this.padding = const EdgeInsetsDirectional.only(top: 8, start: 4, end: 4),
  });

  @override
  Widget build(BuildContext context) {
    if (text == null || text!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return Padding(
      padding: padding,
      child: Text(
        text!,
        style:
            theme.inputDecorationTheme.errorStyle ??
            theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
              fontWeight: FontWeight.w600,
            ) ??
            TextStyle(color: theme.colorScheme.error),
      ),
    );
  }
}
