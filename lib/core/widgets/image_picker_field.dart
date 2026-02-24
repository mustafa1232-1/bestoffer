import 'package:flutter/material.dart';

import '../files/local_image_file.dart';

class ImagePickerField extends StatelessWidget {
  final String title;
  final LocalImageFile? selectedFile;
  final String? existingImageUrl;
  final VoidCallback onPick;
  final VoidCallback? onClear;

  const ImagePickerField({
    super.key,
    required this.title,
    required this.selectedFile,
    required this.existingImageUrl,
    required this.onPick,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title,
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.right,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        Container(
          height: 140,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
          ),
          clipBehavior: Clip.antiAlias,
          child: _buildPreview(context),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            if (onClear != null)
              TextButton.icon(
                onPressed: onClear,
                icon: const Icon(Icons.delete_outline),
                label: const Text('حذف الصورة'),
              ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: onPick,
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('اختيار من الجهاز'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildPreview(BuildContext context) {
    if (selectedFile?.hasBytes == true) {
      return Image.memory(
        selectedFile!.bytes!,
        fit: BoxFit.cover,
      );
    }

    if (existingImageUrl != null && existingImageUrl!.trim().isNotEmpty) {
      return Image.network(
        existingImageUrl!,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
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

