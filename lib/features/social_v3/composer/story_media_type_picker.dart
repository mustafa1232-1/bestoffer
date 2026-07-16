import 'package:flutter/material.dart';

import '../pickers/social_media_picker_v3.dart';

Future<PickedMediaType?> pickStoryMediaType(BuildContext context) {
  return showModalBottomSheet<PickedMediaType>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('صورة'),
              subtitle: const Text('اختيار صورة من المعرض'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(PickedMediaType.image),
            ),
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('فيديو'),
              subtitle: const Text('اختيار فيديو من المعرض'),
              onTap: () =>
                  Navigator.of(sheetContext).pop(PickedMediaType.video),
            ),
            const SizedBox(height: 8),
          ],
        ),
      );
    },
  );
}
