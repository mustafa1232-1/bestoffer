import 'package:flutter/material.dart';

import '../files/local_image_file.dart';
import '../forms/inline_field_error_text.dart';
import '../i18n/app_localizations_context.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class ImagePickerField extends StatelessWidget {
  final String title;
  final LocalImageFile? selectedFile;
  final String? existingImageUrl;
  final VoidCallback onPick;
  final VoidCallback? onClear;
  final String? errorText;
  final String? helperText;
  final bool required;

  const ImagePickerField({
    super.key,
    required this.title,
    required this.selectedFile,
    required this.existingImageUrl,
    required this.onPick,
    this.onClear,
    this.errorText,
    this.helperText,
    this.required = false,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final hasError = errorText != null && errorText!.trim().isNotEmpty;
    final borderColor = hasError
        ? theme.colorScheme.error
        : Colors.white.withValues(alpha: 0.18);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        RichText(
          text: TextSpan(
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            children: [
              TextSpan(text: title),
              if (required)
                TextSpan(
                  text: ' *',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildPreview(context),
        ),
        InlineFieldErrorText(text: errorText),
        if (helperText != null && helperText!.trim().isNotEmpty && !hasError)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 8, start: 4, end: 4),
            child: Text(
              helperText!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (onClear != null)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
                label: Text(l10n.commonRemoveImage),
              ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library_outlined),
              label: Text(l10n.commonChooseFromDevice),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (selectedFile?.hasBytes == true) {
      return Image.memory(selectedFile!.bytes!, fit: BoxFit.cover);
    }

    if (existingImageUrl != null && existingImageUrl!.trim().isNotEmpty) {
      return CachedAppImage(
        imageUrl: existingImageUrl!,
        fit: BoxFit.cover,
        errorWidget: (context, error, stackTrace) {
          return _placeholder();
        },
      );
    }

    return _placeholder();
  }

  Widget _placeholder() {
    return Container(
      color: Colors.white.withValues(alpha: 0.04),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, size: 34),
    );
  }
}
