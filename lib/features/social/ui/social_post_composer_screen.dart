import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:video_player/video_player.dart';

import '../../../core/files/local_image_file.dart';
import '../../../core/files/local_media_file.dart';
import '../../../core/files/image_picker_service.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../creator/creator_filter_registry.dart';
import '../creator/creator_models.dart';
import '../creator/creator_temp_media_service.dart';
import '../creator/filter_pipeline_service.dart';
import '../creator/reel_export_service.dart';
import '../state/social_controller.dart';
import 'widgets/social_mention_composer_field.dart';
import '../creator/social_camera_creator_screen.dart';
import '../creator/creator_adapters.dart';

Future<bool?> showSocialPostComposerScreen(
  BuildContext context, {
  required String initialKind,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SocialPostComposerScreen(initialKind: initialKind),
    ),
  );
}

class SocialPostComposerScreen extends ConsumerStatefulWidget {
  final String initialKind;

  const SocialPostComposerScreen({super.key, required this.initialKind});

  @override
  ConsumerState<SocialPostComposerScreen> createState() =>
      _SocialPostComposerScreenState();
}

class _SocialPostComposerScreenState
    extends ConsumerState<SocialPostComposerScreen> {
  final SocialMentionComposerController _captionCtrl =
      SocialMentionComposerController();
  final PageController _pageController = PageController();
  final CreatorTempMediaService _tempMediaService =
      const CreatorTempMediaService();
  late final FilterPipelineService _filterPipelineService;
  late final ReelExportService _reelExportService;

  static const List<Color> _textBackgrounds = <Color>[
    Color(0xFF111827),
    Color(0xFF1D3557),
    Color(0xFF5B2C6F),
    Color(0xFF7C2D12),
    Color(0xFF14532D),
    Color(0xFF0F766E),
  ];

  late String _postKind;
  final List<_DraftMediaItem> _items = <_DraftMediaItem>[];
  int _currentIndex = 0;
  int _textBackgroundIndex = 0;
  bool _publishing = false;
  bool _ranInitialPicker = false;
  String? _error;

  _DraftMediaItem? get _currentItem =>
      _items.isEmpty || _currentIndex < 0 || _currentIndex >= _items.length
      ? null
      : _items[_currentIndex];

  @override
  void initState() {
    super.initState();
    _postKind = widget.initialKind.trim().toLowerCase();
    _filterPipelineService = FilterPipelineService(_tempMediaService);
    _reelExportService = ReelExportService(_tempMediaService);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runInitialPicker());
    });
  }

  @override
  void dispose() {
    _captionCtrl.dispose();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final picked = await pickMultipleImagesFromDevice(maxFiles: 10);
    if (!mounted || picked.isEmpty) return;
    setState(() {
      _postKind = 'image';
      for (final image in picked) {
        _items.add(_DraftMediaItem(file: _fromLocalImage(image)));
      }
      _currentIndex = _items.length - picked.length;
      _error = null;
    });
    unawaited(_animateToCurrentPage());
  }

  Future<void> _pickVideos({bool reelMode = false}) async {
    final picked = await pickMultiplePostMediaFromDevice(
      maxFiles: reelMode ? 1 : 10,
    );
    if (!mounted || picked.isEmpty) return;
    final videos = picked.where((item) => item.isVideo).toList(growable: false);
    if (videos.isEmpty) return;
    setState(() {
      _postKind = reelMode ? 'reel' : 'video';
      if (reelMode) {
        _items
          ..clear()
          ..add(_DraftMediaItem(file: videos.first));
        _currentIndex = 0;
      } else {
        for (final video in videos) {
          _items.add(_DraftMediaItem(file: video));
        }
        _currentIndex = _items.length - videos.length;
      }
      _error = null;
    });
    unawaited(_animateToCurrentPage());
  }

  Future<void> _captureReel() async {
    final creatorDraft = await showSocialCameraCreator(
      context,
      mode: SocialCreatorMode.reel,
    );
    if (!mounted || creatorDraft == null) return;
    setState(() {
      _postKind = 'reel';
      _items
        ..clear()
        ..add(
          _DraftMediaItem(
            file: buildReelMediaFromCreator(creatorDraft),
            filterId: creatorDraft.clip.filterId,
          ),
        );
      _currentIndex = 0;
      _error = null;
    });
  }

  Future<void> _addMoreMedia() async {
    if (_postKind == 'image') {
      await _pickPhotos();
      return;
    }
    if (_postKind == 'reel') {
      await _pickVideos(reelMode: true);
      return;
    }
    await _pickVideos(reelMode: false);
  }

  void _removeCurrentMedia() {
    if (_currentItem == null) return;
    setState(() {
      _items.removeAt(_currentIndex);
      if (_items.isEmpty) {
        _currentIndex = 0;
      } else if (_currentIndex >= _items.length) {
        _currentIndex = _items.length - 1;
      }
    });
    unawaited(_animateToCurrentPage());
  }

  Future<void> _animateToCurrentPage() async {
    if (!_pageController.hasClients || _items.isEmpty) return;
    await _pageController.animateToPage(
      _currentIndex,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
    );
  }

  void _applyFilter(String filterId) {
    final item = _currentItem;
    if (item == null) return;
    setState(() {
      _items[_currentIndex] = item.copyWith(filterId: filterId);
    });
  }

  Future<File> _materializeFile(
    LocalMediaFile file, {
    required String prefix,
  }) async {
    if ((file.path ?? '').trim().isNotEmpty) {
      return File(file.path!);
    }
    if (file.bytes == null || file.bytes!.isEmpty) {
      throw StateError('Selected media has no readable path or bytes.');
    }
    final extension = _extensionForMime(file.mimeType);
    final outputPath = await _tempMediaService.newFilePath(
      prefix: prefix,
      extension: extension,
    );
    return File(outputPath)..writeAsBytesSync(file.bytes!, flush: true);
  }

  Future<LocalMediaFile> _prepareDraftMedia(_DraftMediaItem item) async {
    final filterId = item.filterId;
    if ((filterId ?? creatorNoFilter.id) == creatorNoFilter.id) {
      return item.file;
    }
    if (item.file.isImage) {
      final sourceFile = await _materializeFile(
        item.file,
        prefix: 'post_image_source',
      );
      final filtered = await _filterPipelineService.exportPhoto(
        sourceImage: sourceFile,
        filterId: filterId,
      );
      return LocalMediaFile(
        name: path.basename(filtered.path),
        path: filtered.path,
        bytes: null,
        mimeType: 'image/jpeg',
      );
    }
    if (item.file.isVideo) {
      if ((item.file.path ?? '').trim().isEmpty) {
        return item.file;
      }
      return _reelExportService.exportVideo(
        sourceFile: item.file,
        maxDurationSeconds: 300,
        filterId: filterId,
        prefix: 'social_post_video',
      );
    }
    return item.file;
  }

  Future<void> _runInitialPicker() async {
    if (_ranInitialPicker || !mounted) return;
    _ranInitialPicker = true;
    switch (_postKind) {
      case 'image':
        await _pickPhotos();
        break;
      case 'video':
        await _pickVideos();
        break;
      case 'reel':
        await _pickVideos(reelMode: true);
        break;
      default:
        break;
    }
  }

  Future<void> _publish() async {
    if (_publishing) return;
    final caption = _captionCtrl.buildMarkedText().trim();
    if (_postKind == 'text' && caption.isEmpty) {
      setState(
        () => _error = context.lt(
          ar: 'اكتب شيئاً قبل النشر.',
          en: 'Write something before publishing.',
        ),
      );
      return;
    }
    if (_postKind != 'text' && _items.isEmpty) {
      setState(
        () => _error = context.lt(
          ar: 'أضف وسائط قبل النشر.',
          en: 'Add media before publishing.',
        ),
      );
      return;
    }

    setState(() {
      _publishing = true;
      _error = null;
    });

    try {
      final processedMedia = <LocalMediaFile>[];
      for (final item in _items) {
        processedMedia.add(await _prepareDraftMedia(item));
      }
      await ref
          .read(socialControllerProvider.notifier)
          .createPost(
            caption: caption,
            postKind: _postKind,
            mediaFiles: processedMedia,
          );
      if (!mounted) return;
      final err = ref.read(socialControllerProvider).error;
      if (err != null && err.trim().isNotEmpty) {
        setState(() {
          _publishing = false;
          _error = err;
        });
        return;
      }
      Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _publishing = false;
        _error = '$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final currentItem = _currentItem;
    final currentFilterId = currentItem?.filterId ?? creatorNoFilter.id;
    final isTextMode = _postKind == 'text';

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(
          context.lt(ar: 'منشور جديد', en: 'New post'),
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        actions: [
          TextButton(
            onPressed: _publishing ? null : _publish,
            child: _publishing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    l10n.socialCreatePostSubmitNow,
                    style: TextStyle(
                      color: scheme.primary,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: isTextMode
                  ? _TextComposerPreview(
                      controller: _captionCtrl,
                      background: _textBackgrounds[_textBackgroundIndex],
                    )
                  : _MediaComposerPreview(
                      items: _items,
                      currentIndex: _currentIndex,
                      controller: _pageController,
                      onPageChanged: (value) =>
                          setState(() => _currentIndex = value),
                    ),
            ),
            if (!isTextMode && _items.length > 1)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List<Widget>.generate(_items.length, (index) {
                    final active = index == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: active ? Colors.white : Colors.white38,
                        borderRadius: BorderRadius.circular(999),
                      ),
                    );
                  }),
                ),
              ),
            Container(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              decoration: BoxDecoration(
                color: const Color(0xFF09111F),
                border: Border(
                  top: BorderSide(color: Colors.white.withValues(alpha: 0.08)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      _ComposerActionChip(
                        label: context.lt(ar: 'نص', en: 'Text'),
                        selected: _postKind == 'text',
                        onTap: () => setState(() => _postKind = 'text'),
                      ),
                      const SizedBox(width: 8),
                      _ComposerActionChip(
                        label: context.lt(ar: 'صور', en: 'Photos'),
                        selected: _postKind == 'image',
                        onTap: _pickPhotos,
                      ),
                      const SizedBox(width: 8),
                      _ComposerActionChip(
                        label: context.lt(ar: 'فيديو', en: 'Video'),
                        selected: _postKind == 'video',
                        onTap: _pickVideos,
                      ),
                      const SizedBox(width: 8),
                      _ComposerActionChip(
                        label: context.lt(ar: 'ريل', en: 'Reel'),
                        selected: _postKind == 'reel',
                        onTap: _captureReel,
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (isTextMode)
                    SizedBox(
                      height: 54,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _textBackgrounds.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final selected = index == _textBackgroundIndex;
                          return GestureDetector(
                            onTap: () =>
                                setState(() => _textBackgroundIndex = index),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 46,
                              height: 46,
                              decoration: BoxDecoration(
                                color: _textBackgrounds[index],
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selected
                                      ? Colors.white
                                      : Colors.white24,
                                  width: selected ? 3 : 1,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    )
                  else ...[
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _addMoreMedia,
                          icon: const Icon(Icons.add_photo_alternate_outlined),
                          label: Text(
                            _postKind == 'image'
                                ? context.lt(ar: 'إضافة صور', en: 'Add photos')
                                : context.lt(
                                    ar: 'إضافة فيديو',
                                    en: 'Add video',
                                  ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (currentItem != null)
                          OutlinedButton.icon(
                            onPressed: _removeCurrentMedia,
                            icon: const Icon(Icons.delete_outline_rounded),
                            label: Text(
                              context.lt(
                                ar: 'حذف الحالي',
                                en: 'Remove current',
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 90,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: creatorSupportedFilterPresets.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 10),
                        itemBuilder: (context, index) {
                          final preset = creatorSupportedFilterPresets[index];
                          final selected = preset.id == currentFilterId;
                          return GestureDetector(
                            onTap: () => _applyFilter(preset.id),
                            child: Container(
                              width: 76,
                              padding: const EdgeInsets.all(6),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: selected
                                      ? scheme.primary
                                      : Colors.white12,
                                  width: selected ? 2 : 1,
                                ),
                              ),
                              child: Column(
                                children: [
                                  Expanded(
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(12),
                                      child: _FilterPreviewThumb(
                                        item: currentItem,
                                        preset: preset,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    preset.label(
                                      Localizations.localeOf(
                                        context,
                                      ).languageCode,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  SocialMentionComposerField(
                    controller: _captionCtrl,
                    minLines: 2,
                    maxLines: 5,
                    hintText: context.lt(
                      ar: 'اكتب وصف المنشور...',
                      en: 'Write a caption...',
                    ),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    Text(
                      _error!,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftMediaItem {
  final LocalMediaFile file;
  final String? filterId;

  const _DraftMediaItem({required this.file, this.filterId});

  _DraftMediaItem copyWith({LocalMediaFile? file, String? filterId}) {
    return _DraftMediaItem(
      file: file ?? this.file,
      filterId: filterId ?? this.filterId,
    );
  }
}

class _TextComposerPreview extends StatelessWidget {
  final SocialMentionComposerController controller;
  final Color background;

  const _TextComposerPreview({
    required this.controller,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller.textController,
      builder: (context, value, child) {
        final text = controller.buildMarkedText().trim();
        return Container(
          color: background,
          padding: const EdgeInsets.all(24),
          alignment: Alignment.center,
          child: Text(
            text.isEmpty
                ? context.lt(
                    ar: 'اكتب ما تريد مشاركته',
                    en: 'Write what you want to share',
                  )
                : text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 28,
              fontWeight: FontWeight.w900,
              height: 1.35,
            ),
          ),
        );
      },
    );
  }
}

class _MediaComposerPreview extends StatelessWidget {
  final List<_DraftMediaItem> items;
  final int currentIndex;
  final PageController controller;
  final ValueChanged<int> onPageChanged;

  const _MediaComposerPreview({
    required this.items,
    required this.currentIndex,
    required this.controller,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Center(
        child: Text(
          context.lt(
            ar: 'أضف وسائط لبدء المنشور',
            en: 'Add media to start the post',
          ),
          style: const TextStyle(
            color: Colors.white70,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    return PageView.builder(
      controller: controller,
      itemCount: items.length,
      onPageChanged: onPageChanged,
      itemBuilder: (context, index) {
        final item = items[index];
        return _FullScreenDraftMediaViewer(
          item: item,
          active: index == currentIndex,
        );
      },
    );
  }
}

class _FullScreenDraftMediaViewer extends StatelessWidget {
  final _DraftMediaItem item;
  final bool active;

  const _FullScreenDraftMediaViewer({required this.item, required this.active});

  @override
  Widget build(BuildContext context) {
    final preset = resolveCreatorFilterPreset(item.filterId);
    if (item.file.isVideo) {
      return _DraftVideoPlayer(
        file: item.file,
        active: active,
        filterPreset: preset,
      );
    }
    final image = _imageProviderFor(item.file);
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(preset.previewMatrix),
          child: Image(
            image: image,
            fit: BoxFit.contain,
            width: double.infinity,
            height: double.infinity,
          ),
        ),
      ),
    );
  }
}

class _DraftVideoPlayer extends StatefulWidget {
  final LocalMediaFile file;
  final bool active;
  final CreatorFilterPreset filterPreset;

  const _DraftVideoPlayer({
    required this.file,
    required this.active,
    required this.filterPreset,
  });

  @override
  State<_DraftVideoPlayer> createState() => _DraftVideoPlayerState();
}

class _DraftVideoPlayerState extends State<_DraftVideoPlayer> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  @override
  void didUpdateWidget(covariant _DraftVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.file.path != widget.file.path) {
      unawaited(_disposeController());
      unawaited(_init());
      return;
    }
    _syncPlayback();
  }

  Future<void> _init() async {
    final filePath = (widget.file.path ?? '').trim();
    if (filePath.isEmpty) return;
    final controller = VideoPlayerController.file(File(filePath));
    try {
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0);
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
      _syncPlayback();
    } catch (_) {
      await controller.dispose();
    }
  }

  void _syncPlayback() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    if (widget.active) {
      controller.play();
    } else {
      controller.pause();
    }
  }

  Future<void> _disposeController() async {
    final controller = _controller;
    _controller = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  @override
  void dispose() {
    unawaited(_disposeController());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return ColoredBox(
      color: Colors.black,
      child: Center(
        child: ColorFiltered(
          colorFilter: ColorFilter.matrix(widget.filterPreset.previewMatrix),
          child: AspectRatio(
            aspectRatio: controller.value.aspectRatio,
            child: VideoPlayer(controller),
          ),
        ),
      ),
    );
  }
}

class _FilterPreviewThumb extends StatelessWidget {
  final _DraftMediaItem? item;
  final CreatorFilterPreset preset;

  const _FilterPreviewThumb({required this.item, required this.preset});

  @override
  Widget build(BuildContext context) {
    final current = item;
    if (current == null) {
      return ColoredBox(color: Colors.white.withValues(alpha: 0.06));
    }
    if (current.file.isVideo) {
      return Stack(
        fit: StackFit.expand,
        children: [
          ColoredBox(color: Colors.white.withValues(alpha: 0.06)),
          Center(
            child: Icon(
              Icons.play_circle_outline_rounded,
              color: Colors.white.withValues(alpha: 0.85),
            ),
          ),
        ],
      );
    }
    return ColorFiltered(
      colorFilter: ColorFilter.matrix(preset.previewMatrix),
      child: Image(image: _imageProviderFor(current.file), fit: BoxFit.cover),
    );
  }
}

class _ComposerActionChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ComposerActionChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
    );
  }
}

ImageProvider _imageProviderFor(LocalMediaFile file) {
  if (file.bytes != null && file.bytes!.isNotEmpty) {
    return MemoryImage(file.bytes!);
  }
  return FileImage(File(file.path!));
}

LocalMediaFile _fromLocalImage(LocalImageFile file) {
  return LocalMediaFile(
    name: file.name,
    path: file.path,
    bytes: file.bytes,
    mimeType: 'image/jpeg',
  );
}

String _extensionForMime(String? mimeType) {
  final normalized = (mimeType ?? '').trim().toLowerCase();
  if (normalized == 'image/png') return 'png';
  if (normalized == 'image/webp') return 'webp';
  if (normalized == 'video/quicktime') return 'mov';
  if (normalized == 'video/webm') return 'webm';
  return normalized.startsWith('video/') ? 'mp4' : 'jpg';
}
