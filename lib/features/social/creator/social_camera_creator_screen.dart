import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/maslaki_back_button.dart';
import '../../../core/files/local_media_file.dart';
import '../../../core/files/media_picker_service.dart';
import '../../../l10n/app_localizations.dart';
import 'camera_capture_service.dart';
import 'creator_capabilities_service.dart';
import 'creator_constants.dart';
import 'creator_effect_registry.dart';
import 'creator_models.dart';
import 'creator_permissions_service.dart';
import 'creator_temp_media_service.dart';
import 'effect_pipeline_service.dart';
import 'face_tracking_service.dart';
import 'filter_pipeline_service.dart';
import 'recording_session_controller.dart';
import 'reel_export_service.dart';
import 'story_layout_compositor.dart';
import 'story_layout_controller.dart';
import 'story_layout_models.dart';
import 'story_segmentation_service.dart';
import 'story_text_composer_screen.dart';
import 'creator_filter_registry.dart';

/// Primary creation mode shown in the story camera's bottom mode strip.
enum _StoryMode { camera, layout, text }

/// Which in-camera bottom carousel is currently open.
enum _CameraTray { none, filters, effects, mood }

/// Curated Maslaki Mood preset keys.
const List<String> kMaslakiMoodKeys = <String>[
  'quick_trip',
  'basmaya_morning',
  'daily_coffee',
  'on_the_way',
  'order_arrived',
];

/// Fallback face region (normalized) for the live effect preview before a live
/// face lock arrives — upper-centre, roughly where a selfie face sits. The
/// exported photo still uses real on-device face detection for accurate placement.
const Rect _kDefaultFaceBox = Rect.fromLTWH(0.28, 0.20, 0.44, 0.34);

/// Outcome returned by the story camera hub. The story flow either yields a
/// media draft (camera capture, layout composite, gallery import) or signals
/// that the user chose Text mode (routed to the text composer by the caller).
class StoryCameraOutcome {
  final CreatorPreviewDraft? mediaDraft;
  final bool textMode;

  const StoryCameraOutcome.media(this.mediaDraft) : textMode = false;
  const StoryCameraOutcome.text()
      : mediaDraft = null,
        textMode = true;
}

/// Reel entry point — opens the camera and returns the captured preview draft.
Future<CreatorPreviewDraft?> showSocialCameraCreator(
  BuildContext context, {
  required SocialCreatorMode mode,
}) {
  return Navigator.of(context).push<CreatorPreviewDraft>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => SocialCameraCreatorScreen(mode: mode),
    ),
  );
}

/// Story entry point — opens the full-screen story camera hub directly.
Future<StoryCameraOutcome?> showStoryCamera(BuildContext context) {
  return Navigator.of(context).push<StoryCameraOutcome>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const SocialCameraCreatorScreen(
        mode: SocialCreatorMode.story,
      ),
    ),
  );
}

class SocialCameraCreatorScreen extends StatefulWidget {
  final SocialCreatorMode mode;

  const SocialCameraCreatorScreen({super.key, required this.mode});

  @override
  State<SocialCameraCreatorScreen> createState() =>
      _SocialCameraCreatorScreenState();
}

class _SocialCameraCreatorScreenState extends State<SocialCameraCreatorScreen>
    with WidgetsBindingObserver {
  late final CreatorTempMediaService _tempMediaService;
  late final CreatorPermissionsService _permissionsService;
  late final CreatorCapabilitiesService _capabilitiesService;
  late final CameraCaptureService _cameraCaptureService;
  late final FaceTrackingService _faceTrackingService;
  late final FilterPipelineService _filterPipelineService;
  late final EffectPipelineService _effectPipelineService;
  late final ReelExportService _reelExportService;
  late final StorySegmentationService _storySegmentationService;
  late final StoryLayoutCompositor _layoutCompositor;
  late final RecordingSessionController _recordingController;
  late final StoryLayoutController _layoutController;

  CreatorPermissionState _permissionState = CreatorPermissionState.checking;
  CreatorCapabilitySnapshot? _capabilities;
  CreatorCaptureType _captureType = CreatorCaptureType.photo;
  FlashMode _flashMode = FlashMode.off;
  String _selectedFilterId = creatorNoFilter.id;
  String? _selectedEffectId;
  Rect? _previewFaceBounds;
  bool _initializing = true;
  bool _isBootstrapping = false;
  bool _exporting = false;
  bool _switchingCamera = false;
  String? _error;
  CreatorPreviewDraft? _previewDraft;
  VideoPlayerController? _previewVideoController;
  List<FaceTrackingSample> _trackingSamples = const <FaceTrackingSample>[];
  int _coverFrameMs = 0;

  // ── Story hub state ───────────────────────────────────────────────────────
  _StoryMode _storyMode = _StoryMode.camera;
  _CameraTray _tray = _CameraTray.none;

  // ── Maslaki unique features state ─────────────────────────────────────────
  late String _timeMoodKey;
  String? _placePulseLabel;
  bool _maslakiSealEnabled = false;
  String? _maslakiMoodKey;

  CameraController? get _cameraController => _cameraCaptureService.controller;
  bool get _isStoryMode => widget.mode == SocialCreatorMode.story;
  bool get _isLayoutMode => _isStoryMode && _storyMode == _StoryMode.layout;

  double get _maxVideoSeconds => widget.mode == SocialCreatorMode.reel
      ? reelMaxSeconds
      : creatorStoryRecordingHardCapSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tempMediaService = const CreatorTempMediaService();
    _permissionsService = CreatorPermissionsService();
    _capabilitiesService = CreatorCapabilitiesService();
    _cameraCaptureService = CameraCaptureService(_tempMediaService);
    _faceTrackingService = FaceTrackingService();
    _filterPipelineService = FilterPipelineService(_tempMediaService);
    _effectPipelineService = EffectPipelineService(_tempMediaService);
    _reelExportService = ReelExportService(_tempMediaService);
    _storySegmentationService = StorySegmentationService();
    _layoutCompositor = StoryLayoutCompositor(_tempMediaService);
    _recordingController = RecordingSessionController()
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
      });
    _layoutController = StoryLayoutController()
      ..addListener(() {
        if (!mounted) return;
        setState(() {});
      });
    _captureType = widget.mode == SocialCreatorMode.reel
        ? CreatorCaptureType.video
        : CreatorCaptureType.photo;
    _timeMoodKey = resolveTimeMoodKey();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    if (_isBootstrapping) return;
    _isBootstrapping = true;
    try {
      await _tempMediaService.clearAgedFiles();
      final permissionState = await _permissionsService.ensure(
        needsMicrophone: widget.mode == SocialCreatorMode.reel ||
            _captureType == CreatorCaptureType.video,
      );
      if (!mounted) return;
      if (permissionState != CreatorPermissionState.granted) {
        setState(() {
          _permissionState = permissionState;
          _initializing = false;
        });
        return;
      }
      _permissionState = CreatorPermissionState.granted;
      await _cameraCaptureService.initialize(
        preferredLensDirection: widget.mode == SocialCreatorMode.reel
            ? CameraLensDirection.back
            : CameraLensDirection.front,
      );
      final capabilities = _capabilitiesService.inspect(
        _cameraCaptureService.cameras,
      );
      if (!mounted) return;
      _capabilities = capabilities;
      _initializing = false;
      if (_shouldRunFacePreview) {
        await _startFacePreview();
      }
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _initializing = false;
        _error = '$error';
      });
    } finally {
      _isBootstrapping = false;
    }
  }

  bool get _shouldRunFacePreview =>
      _storyMode == _StoryMode.camera &&
      _captureType == CreatorCaptureType.photo &&
      (_selectedEffectId ?? '').trim().isNotEmpty &&
      (_capabilities?.supportsFaceTracking ?? false);

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.inactive) {
      if (_recordingController.isRecording) {
        unawaited(_finishRecording());
      } else {
        unawaited(_cameraCaptureService.stopPreviewStream());
      }
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (_isBootstrapping) return;
      if (_permissionState != CreatorPermissionState.granted ||
          _cameraController == null) {
        unawaited(_bootstrap());
        return;
      }
      if (_shouldRunFacePreview) {
        unawaited(_startFacePreview());
      }
    }
  }

  Future<void> _startFacePreview() async {
    final controller = _cameraController;
    if (controller == null || !controller.value.isInitialized) return;
    await _cameraCaptureService.stopPreviewStream();
    await _cameraCaptureService.startPreviewStream((image) async {
      final camera = _cameraCaptureService.activeCamera;
      final value = _cameraController?.value;
      if (!mounted || camera == null || value == null) return;
      await _faceTrackingService.processFrame(
        image: image,
        description: camera,
        deviceOrientation: value.deviceOrientation,
        onFaceDetected: (normalizedRect, face) {
          if (!mounted) return;
          setState(() => _previewFaceBounds = normalizedRect);
        },
      );
    });
  }

  Future<void> _toggleCamera() async {
    if (_exporting || _switchingCamera) return;
    setState(() => _switchingCamera = true);
    try {
      await _cameraCaptureService.switchCamera();
      if (!mounted) return;
      if (_shouldRunFacePreview) {
        await _startFacePreview();
      } else {
        await _cameraCaptureService.stopPreviewStream();
      }
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _switchingCamera = false);
    }
  }

  Future<void> _toggleFlash() async {
    final next = switch (_flashMode) {
      FlashMode.off => FlashMode.auto,
      FlashMode.auto => FlashMode.always,
      _ => FlashMode.off,
    };
    await _cameraCaptureService.setFlashMode(next);
    if (!mounted) return;
    setState(() => _flashMode = next);
  }

  Future<void> _changeCaptureType(CreatorCaptureType nextType) async {
    if (!_isStoryMode || _exporting || _recordingController.isRecording) return;
    if (nextType == _captureType) return;
    if (nextType == CreatorCaptureType.video) {
      final permissionState = await _permissionsService.ensure(
        needsMicrophone: true,
      );
      if (!mounted) return;
      if (permissionState != CreatorPermissionState.granted) {
        setState(() {
          _permissionState = permissionState;
          _initializing = false;
        });
        return;
      }
    }
    await _cameraCaptureService.stopPreviewStream();
    setState(() {
      _captureType = nextType;
      if (_captureType == CreatorCaptureType.video) {
        _selectedEffectId = null;
        _previewFaceBounds = null;
        if (_tray == _CameraTray.effects) _tray = _CameraTray.none;
      }
    });
    if (_shouldRunFacePreview) {
      await _startFacePreview();
    }
  }

  // ── Mode + tray switching ──────────────────────────────────────────────────

  Future<void> _selectStoryMode(_StoryMode mode) async {
    if (!_isStoryMode || mode == _storyMode) return;
    if (mode == _StoryMode.text) {
      // Full-screen text card editor → renders to an image → flows to publish.
      final file = await showStoryTextComposer(context);
      if (file == null || !mounted) return;
      final preview = CreatorPreviewDraft(
        mode: SocialCreatorMode.story,
        clip: _buildClip(
          file: file,
          mimeType: 'image/png',
          captureType: CreatorCaptureType.photo,
          duration: Duration.zero,
          captureSource: 'text_card',
          applySelectedFilter: false,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(StoryCameraOutcome.media(preview));
      return;
    }
    setState(() {
      _storyMode = mode;
      _tray = _CameraTray.none;
      if (mode == _StoryMode.layout) {
        _captureType = CreatorCaptureType.photo;
        _selectedEffectId = null;
        _previewFaceBounds = null;
      }
    });
    await _cameraCaptureService.stopPreviewStream();
    if (_shouldRunFacePreview) {
      await _startFacePreview();
    }
  }

  void _toggleTray(_CameraTray tray) {
    setState(() => _tray = _tray == tray ? _CameraTray.none : tray);
  }

  // ── Capture dispatch ────────────────────────────────────────────────────────

  Future<void> _onCapturePressed() async {
    if (_exporting) return;
    if (_isLayoutMode) {
      await _captureLayoutTile();
      return;
    }
    await _capturePrimaryAction();
  }

  Future<void> _capturePrimaryAction() async {
    if (_captureType == CreatorCaptureType.photo) {
      await _capturePhoto();
      return;
    }
    if (_recordingController.isRecording) {
      await _finishRecording();
      return;
    }
    await _startRecording();
  }

  Future<void> _capturePhoto() async {
    final faceNotFoundMessage = context.l10n.socialCreatorFaceNotFound;
    try {
      setState(() {
        _error = null;
        _exporting = true;
      });
      final photo = await _cameraCaptureService.takePhoto();
      var outputPath = photo.path!;
      var currentFile = File(outputPath);
      var currentMimeType = 'image/jpeg';
      currentFile = await _filterPipelineService.exportPhoto(
        sourceImage: currentFile,
        filterId: _selectedFilterId,
      );
      final effect = resolveCreatorEffectPreset(_selectedEffectId);
      if (effect != null) {
        final faceRect = await _faceTrackingService.detectPrimaryFaceFromFile(
          outputPath,
        );
        if (faceRect == null) {
          throw StateError(faceNotFoundMessage);
        }
        currentFile = await _effectPipelineService.exportPhoto(
          sourceImage: currentFile,
          effect: effect,
          faceBounds: faceRect,
        );
        currentMimeType = 'image/png';
      }
      final preview = CreatorPreviewDraft(
        mode: widget.mode,
        clip: _buildClip(
          file: currentFile,
          mimeType: currentMimeType,
          captureType: CreatorCaptureType.photo,
          duration: Duration.zero,
          captureSource: 'camera_photo',
          effectId: effect?.id,
        ),
      );
      if (!mounted) return;
      await _setPreview(preview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _startRecording() async {
    try {
      setState(() {
        _error = null;
        _tray = _CameraTray.none;
        _trackingSamples = const <FaceTrackingSample>[];
      });
      await _cameraCaptureService.stopPreviewStream();
      await _cameraCaptureService.startRecording();
      _recordingController.start(
        onTick: () {
          if (_recordingController.elapsed.inMilliseconds >=
              (_maxVideoSeconds * 1000).round()) {
            unawaited(_finishRecording());
          }
        },
      );
      setState(() {});
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    }
  }

  Future<void> _finishRecording() async {
    if (!_recordingController.isRecording || _exporting) return;
    _recordingController.stop();
    try {
      setState(() {
        _exporting = true;
        _error = null;
      });
      final rawVideo = await _cameraCaptureService.stopRecording();
      final exportedVideo = await _reelExportService.exportVideo(
        sourceFile: rawVideo,
        maxDurationSeconds: _maxVideoSeconds,
        filterId: _selectedFilterId,
        prefix: widget.mode == SocialCreatorMode.reel
            ? 'creator_reel'
            : 'creator_story_video',
      );
      final info = await _resolveVideoInfo(exportedVideo.path!);
      final segments = _isStoryMode
          ? await _storySegmentationService.buildSegments(exportedVideo)
          : const <StorySegmentDraft>[];
      final durationMs = info.$1.inMilliseconds;
      final preview = CreatorPreviewDraft(
        mode: widget.mode,
        clip: _buildClip(
          mediaFile: exportedVideo,
          mimeType: 'video/mp4',
          captureType: CreatorCaptureType.video,
          duration: info.$1,
          mediaSize: info.$2,
          captureSource: 'camera_video',
          trackingSamples: _trackingSamples,
          coverFrameMs: durationMs > 0 ? durationMs ~/ 3 : null,
        ),
        storySegments: segments,
        sequenceId: segments.length > 1
            ? DateTime.now().microsecondsSinceEpoch.toString()
            : null,
      );
      if (!mounted) return;
      _coverFrameMs = preview.clip.coverFrameMs ?? 0;
      await _setPreview(preview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  /// Builds a [RecordedClipDraft] threading the active Maslaki feature metadata.
  RecordedClipDraft _buildClip({
    File? file,
    LocalMediaFile? mediaFile,
    required String mimeType,
    required CreatorCaptureType captureType,
    required Duration duration,
    required String captureSource,
    Size? mediaSize,
    String? effectId,
    List<FaceTrackingSample> trackingSamples = const <FaceTrackingSample>[],
    int? coverFrameMs,
    bool applySelectedFilter = true,
  }) {
    final media = mediaFile ??
        LocalMediaFile(
          name: file!.uri.pathSegments.last,
          path: file.path,
          bytes: null,
          mimeType: mimeType,
        );
    return RecordedClipDraft(
      mediaFile: media,
      captureType: captureType,
      duration: duration,
      mediaSize: mediaSize,
      captureSource: captureSource,
      filterId: (!applySelectedFilter || _selectedFilterId == creatorNoFilter.id)
          ? null
          : _selectedFilterId,
      effectId: effectId,
      trackingSamples: trackingSamples,
      coverFrameMs: coverFrameMs,
      timeMoodKey: _timeMoodKey,
      placePulseLabel:
          (_placePulseLabel ?? '').trim().isEmpty ? null : _placePulseLabel,
      hasMaslakiSeal: _maslakiSealEnabled,
      maslakiMoodKey: _maslakiMoodKey,
    );
  }

  Future<(Duration, Size?)> _resolveVideoInfo(String path) async {
    final controller = VideoPlayerController.file(File(path));
    try {
      await controller.initialize();
      return (controller.value.duration, controller.value.size);
    } finally {
      await controller.dispose();
    }
  }

  Future<void> _setPreview(CreatorPreviewDraft preview) async {
    await _previewVideoController?.dispose();
    VideoPlayerController? controller;
    if (preview.clip.captureType == CreatorCaptureType.video &&
        (preview.clip.mediaFile.path ?? '').trim().isNotEmpty) {
      controller = VideoPlayerController.file(File(preview.clip.mediaFile.path!));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
    }
    if (!mounted) {
      await controller?.dispose();
      return;
    }
    setState(() {
      _previewDraft = preview;
      _previewVideoController = controller;
    });
  }

  Future<void> _retake() async {
    await _previewVideoController?.dispose();
    _previewVideoController = null;
    setState(() {
      _previewDraft = null;
      _coverFrameMs = 0;
      _error = null;
    });
    if (_shouldRunFacePreview) {
      await _startFacePreview();
    }
  }

  void _completePreview() {
    final preview = _previewDraft;
    if (preview == null) return;
    final nextPreview = CreatorPreviewDraft(
      mode: preview.mode,
      sequenceId: preview.sequenceId,
      storySegments: preview.storySegments,
      clip: RecordedClipDraft(
        mediaFile: preview.clip.mediaFile,
        captureType: preview.clip.captureType,
        duration: preview.clip.duration,
        mediaSize: preview.clip.mediaSize,
        captureSource: preview.clip.captureSource,
        filterId: preview.clip.filterId,
        effectId: preview.clip.effectId,
        trackingSamples: preview.clip.trackingSamples,
        coverFrameMs: preview.clip.captureType == CreatorCaptureType.video
            ? _coverFrameMs
            : preview.clip.coverFrameMs,
        timeMoodKey: preview.clip.timeMoodKey,
        placePulseLabel: preview.clip.placePulseLabel,
        hasMaslakiSeal: preview.clip.hasMaslakiSeal,
        maslakiMoodKey: preview.clip.maslakiMoodKey,
      ),
    );
    if (_isStoryMode) {
      Navigator.of(context).pop(StoryCameraOutcome.media(nextPreview));
    } else {
      Navigator.of(context).pop(nextPreview);
    }
  }

  // ── Gallery import ──────────────────────────────────────────────────────────

  Future<void> _openGallery() async {
    if (_exporting) return;
    final l10n = context.l10n;
    final picked = await pickPostMediaFromDevice();
    if (picked == null || !mounted) return;

    if (_isLayoutMode) {
      if (picked.isVideo) {
        setState(() => _error = l10n.socialCreatorLayoutImagesOnly);
        return;
      }
      final path = await _materializeImagePath(picked);
      if (path == null || !mounted) return;
      _layoutController.setCurrentImage(path, StoryTileSource.gallery);
      return;
    }

    try {
      setState(() {
        _error = null;
        _exporting = true;
      });
      if (picked.isVideo) {
        final path = (picked.path ?? '').trim();
        if (path.isEmpty) {
          throw StateError(l10n.socialCreatorCameraUnavailable);
        }
        final info = await _resolveVideoInfo(path);
        final segments = _isStoryMode
            ? await _storySegmentationService.buildSegments(picked)
            : const <StorySegmentDraft>[];
        final durationMs = info.$1.inMilliseconds;
        final preview = CreatorPreviewDraft(
          mode: widget.mode,
          clip: _buildClip(
            mediaFile: picked,
            mimeType: picked.mimeType ?? 'video/mp4',
            captureType: CreatorCaptureType.video,
            duration: info.$1,
            mediaSize: info.$2,
            captureSource: 'gallery',
            coverFrameMs: durationMs > 0 ? durationMs ~/ 3 : null,
            applySelectedFilter: false,
          ),
          storySegments: segments,
          sequenceId: segments.length > 1
              ? DateTime.now().microsecondsSinceEpoch.toString()
              : null,
        );
        _coverFrameMs = preview.clip.coverFrameMs ?? 0;
        await _setPreview(preview);
      } else {
        final preview = CreatorPreviewDraft(
          mode: widget.mode,
          clip: _buildClip(
            mediaFile: picked,
            mimeType: picked.mimeType ?? 'image/jpeg',
            captureType: CreatorCaptureType.photo,
            duration: Duration.zero,
            captureSource: 'gallery',
            applySelectedFilter: false,
          ),
        );
        await _setPreview(preview);
      }
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<String?> _materializeImagePath(LocalMediaFile file) async {
    final path = (file.path ?? '').trim();
    if (path.isNotEmpty) {
      final copied = await _tempMediaService.cleanupAndCopy(
        File(path),
        prefix: 'layout_src',
      );
      return copied.path;
    }
    final bytes = file.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      final ext = (file.mimeType ?? '').contains('png') ? 'png' : 'jpg';
      final outPath = await _tempMediaService.newFilePath(
        prefix: 'layout_src',
        extension: ext,
      );
      final out = File(outPath)..writeAsBytesSync(bytes, flush: true);
      return out.path;
    }
    return null;
  }

  // ── Layout mode ─────────────────────────────────────────────────────────────

  Future<void> _captureLayoutTile() async {
    if (_exporting) return;
    try {
      setState(() {
        _error = null;
        _exporting = true;
      });
      final photo = await _cameraCaptureService.takePhoto();
      var file = File(photo.path!);
      file = await _filterPipelineService.exportPhoto(
        sourceImage: file,
        filterId: _selectedFilterId,
      );
      _layoutController.setCurrentImage(file.path, StoryTileSource.camera);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  Future<void> _finishLayout() async {
    if (!_layoutController.isComplete || _exporting) return;
    try {
      setState(() {
        _error = null;
        _exporting = true;
      });
      final composed = await _layoutCompositor.compose(
        template: _layoutController.template,
        imagePaths: _layoutController.orderedImagePaths,
      );
      final preview = CreatorPreviewDraft(
        mode: SocialCreatorMode.story,
        clip: _buildClip(
          file: composed,
          mimeType: 'image/png',
          captureType: CreatorCaptureType.photo,
          duration: Duration.zero,
          captureSource: 'layout_${_layoutController.template.id}',
          // Per-tile filters are already baked into the composite image.
          applySelectedFilter: false,
        ),
      );
      if (!mounted) return;
      await _setPreview(preview);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = '$error');
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  // ── Maslaki unique feature logic ───────────────────────────────────────────

  String _timeMoodLabel() {
    final l10n = context.l10n;
    switch (_timeMoodKey) {
      case 'morning':
        return l10n.socialCreatorTimeMoodMorning;
      case 'forenoon':
        return l10n.socialCreatorTimeMoodForenoon;
      case 'noon':
        return l10n.socialCreatorTimeMoodNoon;
      case 'afternoon':
        return l10n.socialCreatorTimeMoodAfternoon;
      case 'sunset':
        return l10n.socialCreatorTimeMoodSunset;
      case 'evening':
        return l10n.socialCreatorTimeMoodEvening;
      case 'night':
        return l10n.socialCreatorTimeMoodNight;
      case 'late_night':
        return l10n.socialCreatorTimeMoodLateNight;
      default:
        return l10n.socialCreatorTimeMood;
    }
  }

  String _maslakiMoodLabel(String key) {
    final l10n = context.l10n;
    switch (key) {
      case 'quick_trip':
        return l10n.socialCreatorMoodQuickTrip;
      case 'basmaya_morning':
        return l10n.socialCreatorMoodBasmayaMorning;
      case 'daily_coffee':
        return l10n.socialCreatorMoodDailyCoffee;
      case 'on_the_way':
        return l10n.socialCreatorMoodOnTheWay;
      case 'order_arrived':
        return l10n.socialCreatorMoodOrderArrived;
      default:
        return l10n.socialCreatorMoodTool;
    }
  }

  String _layoutTemplateLabel(StoryLayoutTemplate template) {
    final l10n = context.l10n;
    switch (template.id) {
      case 'duo':
        return l10n.socialCreatorLayoutDuo;
      case 'trio':
        return l10n.socialCreatorLayoutTrio;
      case 'quad':
        return l10n.socialCreatorLayoutQuad;
      case 'grid':
        return l10n.socialCreatorLayoutGrid;
      default:
        return l10n.socialStoryModeLayout;
    }
  }

  /// Resolves the device's current location into a short label. Returns null if
  /// services are off or permission is denied. All geolocator calls happen here
  /// and the single caller wraps this in try/catch — nothing escapes to the UI.
  Future<String?> _resolveCurrentLocationLabel() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) return null;
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }
    final position = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    ).timeout(const Duration(seconds: 8));
    return '📍 ${position.latitude.toStringAsFixed(4)}, '
        '${position.longitude.toStringAsFixed(4)}';
  }

  Future<void> _openPlacePulseSheet() async {
    final l10n = context.l10n;
    final searchController =
        TextEditingController(text: _placePulseLabel ?? '');
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF111C2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) {
        var locating = false;
        String? localError;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> useCurrent() async {
              if (locating) return;
              setSheet(() {
                locating = true;
                localError = null;
              });
              try {
                final label = await _resolveCurrentLocationLabel();
                if (label == null) {
                  setSheet(() {
                    locating = false;
                    localError = l10n.socialCreatorPlacePulseError;
                  });
                  return;
                }
                if (ctx.mounted) Navigator.of(ctx).pop(label);
              } catch (_) {
                setSheet(() {
                  locating = false;
                  localError = l10n.socialCreatorPlacePulseError;
                });
              }
            }

            void submitSearch() {
              final text = searchController.text.trim();
              if (text.isEmpty) return;
              Navigator.of(ctx).pop(text);
            }

            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom,
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 14, 18, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.location_on_rounded,
                              color: Color(0xFFD4AF37), size: 20),
                          const SizedBox(width: 8),
                          Text(
                            l10n.socialCreatorPlacePulse,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w900,
                              fontSize: 16,
                            ),
                          ),
                          const Spacer(),
                          if ((_placePulseLabel ?? '').trim().isNotEmpty)
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(''),
                              child: Text(l10n.socialCreatorPlacePulseClear),
                            ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        onPressed: locating ? null : useCurrent,
                        icon: locating
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.my_location_rounded),
                        label: Text(
                          locating
                              ? l10n.socialCreatorPlacePulseLocating
                              : l10n.socialCreatorPlacePulseCurrent,
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextField(
                        controller: searchController,
                        textInputAction: TextInputAction.search,
                        maxLength: 60,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          hintText: l10n.socialCreatorPlacePulseSearchHint,
                          prefixIcon: const Icon(Icons.search_rounded),
                          counterText: '',
                          filled: true,
                          fillColor: Colors.white10,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(14),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        onSubmitted: (_) => submitSearch(),
                      ),
                      const SizedBox(height: 10),
                      FilledButton(
                        onPressed: submitSearch,
                        child: Text(l10n.socialCreatorPlacePulseSave),
                      ),
                      if (localError != null) ...[
                        const SizedBox(height: 10),
                        Text(
                          localError!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Color(0xFFFF8A80),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    searchController.dispose();
    if (!mounted) return;
    if (result == null) return; // dismissed — no change
    setState(() => _placePulseLabel = result.isEmpty ? null : result);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cameraCaptureService.dispose());
    unawaited(_cameraCaptureService.stopPreviewStream());
    unawaited(_faceTrackingService.dispose());
    unawaited(_previewVideoController?.dispose());
    _recordingController.dispose();
    _layoutController.dispose();
    super.dispose();
  }

  // ── Build ────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (_previewDraft != null) {
      return _CreatorPreviewScaffold(
        draft: _previewDraft!,
        videoController: _previewVideoController,
        coverFrameMs: _coverFrameMs,
        onCoverFrameChanged: (value) async {
          setState(() => _coverFrameMs = value);
          final controller = _previewVideoController;
          if (controller != null && controller.value.isInitialized) {
            await controller.seekTo(Duration(milliseconds: value));
          }
        },
        onRetake: _retake,
        onContinue: () async => _completePreview(),
      );
    }

    if (_initializing) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_permissionState != CreatorPermissionState.granted &&
        (_error ?? '').trim().isEmpty) {
      return _CreatorPermissionScaffold(
        permanentlyDenied:
            _permissionState == CreatorPermissionState.permanentlyDenied,
        onRetry: _bootstrap,
        onOpenSettings: _permissionsService.openSettings,
      );
    }

    if ((_capabilities?.hasCamera ?? false) == false) {
      return _cameraUnavailableScaffold(l10n);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _fullScreenCamera(),
          const _StageScrim(),
          if (_isLayoutMode) _LayoutGridFrame(
            controller: _layoutController,
            onSelectTile: (index) => _layoutController.selectTile(index),
            onDeleteTile: (index) => _layoutController.deleteTile(index),
          ),
          if (_maslakiSealEnabled)
            const PositionedDirectional(
              bottom: 150,
              end: 14,
              child: _MaslakiSealOverlay(),
            ),
          if (_recordingController.isRecording)
            PositionedDirectional(
              top: MediaQuery.of(context).padding.top + 64,
              end: 16,
              child: _RecordingBadge(
                elapsed: _recordingController.elapsed,
                maxSeconds: _maxVideoSeconds,
              ),
            ),
          if (_isStoryMode &&
              _storyMode == _StoryMode.camera &&
              !_recordingController.isRecording)
            _timeMoodBadge(),
          _topBar(l10n),
          if (_isStoryMode && !_recordingController.isRecording) _sideRail(l10n),
          _bottomArea(l10n),
        ],
      ),
    );
  }

  Widget _fullScreenCamera() {
    final controller = _cameraController;
    if (_switchingCamera ||
        controller == null ||
        !controller.value.isInitialized) {
      return const ColoredBox(
        color: Colors.black,
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final filterPreset = resolveCreatorFilterPreset(_selectedFilterId);
    final effect = resolveCreatorEffectPreset(_selectedEffectId);
    final mediaSize = MediaQuery.of(context).size;
    var scale = mediaSize.aspectRatio * controller.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;
    return ClipRect(
      child: Stack(
        fit: StackFit.expand,
        children: [
          Transform.scale(
            scale: scale,
            child: Center(
              child: ColorFiltered(
                colorFilter: ColorFilter.matrix(filterPreset.previewMatrix),
                child: CameraPreview(controller),
              ),
            ),
          ),
          if (effect != null &&
              _captureType == CreatorCaptureType.photo &&
              !_isLayoutMode)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: CreatorEffectPreviewPainter(
                    effect: effect,
                    // Always pass a box so the effect is visible even before/
                    // without a live face lock; live tracking refines it.
                    faceBounds: _previewFaceBounds ?? _kDefaultFaceBox,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _timeMoodBadge() {
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.32),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white24),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.wb_twilight_rounded,
                      size: 14, color: Color(0xFFD4AF37)),
                  const SizedBox(width: 5),
                  Text(
                    _timeMoodLabel(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _topBar(AppLocalizations l10n) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(6, 6, 6, 0),
        child: Row(
          children: [
            const MaslakiBackButton(
              fallbackTabIndex: 2,
              icon: Icons.close_rounded,
              color: Colors.white,
            ),
            const Spacer(),
            _GlassIconButton(
              icon: _flashIcon(_flashMode),
              tooltip: l10n.socialCreatorFlash,
              onTap: _toggleFlash,
            ),
            const SizedBox(width: 8),
            _GlassIconButton(
              icon: Icons.cameraswitch_outlined,
              tooltip: l10n.socialCreatorSwitchCamera,
              onTap: _toggleCamera,
            ),
          ],
        ),
      ),
    );
  }

  Widget _sideRail(AppLocalizations l10n) {
    final showEffects =
        _storyMode == _StoryMode.camera && _captureType == CreatorCaptureType.photo;
    return PositionedDirectional(
      top: MediaQuery.of(context).padding.top + 64,
      end: 8,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _SideRailButton(
            icon: Icons.auto_awesome_outlined,
            label: l10n.socialCreatorFiltersTool,
            active: _tray == _CameraTray.filters,
            onTap: () => _toggleTray(_CameraTray.filters),
          ),
          if (showEffects) ...[
            const SizedBox(height: 12),
            _SideRailButton(
              icon: Icons.face_retouching_natural_outlined,
              label: l10n.socialCreatorEffectsTool,
              active: _tray == _CameraTray.effects,
              onTap: () => _toggleTray(_CameraTray.effects),
            ),
          ],
          const SizedBox(height: 12),
          _SideRailButton(
            icon: Icons.mood_outlined,
            label: l10n.socialCreatorMoodTool,
            active: _tray == _CameraTray.mood,
            onTap: () => _toggleTray(_CameraTray.mood),
          ),
          const SizedBox(height: 12),
          _SideRailButton(
            icon: Icons.location_on_outlined,
            label: l10n.socialCreatorPlacePulse,
            active: (_placePulseLabel ?? '').trim().isNotEmpty,
            onTap: _openPlacePulseSheet,
          ),
          const SizedBox(height: 12),
          _SideRailButton(
            icon: Icons.verified_outlined,
            label: l10n.socialCreatorMaslakiSeal,
            active: _maslakiSealEnabled,
            onTap: () =>
                setState(() => _maslakiSealEnabled = !_maslakiSealEnabled),
          ),
        ],
      ),
    );
  }

  Widget _bottomArea(AppLocalizations l10n) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if ((_error ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 6, 18, 6),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF8A80),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            if (_tray != _CameraTray.none && !_recordingController.isRecording)
              _trayContent(l10n),
            if (_isLayoutMode && !_recordingController.isRecording)
              _layoutControlsRow(l10n),
            if (_isStoryMode &&
                _storyMode == _StoryMode.camera &&
                !_recordingController.isRecording)
              _captureTypeToggle(l10n),
            const SizedBox(height: 8),
            _controlsRow(l10n),
            if (_isStoryMode && !_recordingController.isRecording) ...[
              const SizedBox(height: 8),
              _modeStrip(l10n),
            ],
            const SizedBox(height: 6),
          ],
        ),
      ),
    );
  }

  Widget _trayContent(AppLocalizations l10n) {
    final languageCode = Localizations.localeOf(context).languageCode;
    switch (_tray) {
      case _CameraTray.filters:
        return _CarouselTray(
          height: 56,
          itemCount: creatorFilterPresets.length,
          itemBuilder: (context, index) {
            final preset = creatorFilterPresets[index];
            return _TrayPill(
              label: preset.label(languageCode),
              selected: preset.id == _selectedFilterId,
              onTap: () => setState(() => _selectedFilterId = preset.id),
            );
          },
        );
      case _CameraTray.effects:
        return _CarouselTray(
          height: 56,
          itemCount: creatorEffectPresets.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _TrayPill(
                label: l10n.socialCreatorNoEffect,
                selected: (_selectedEffectId ?? '').isEmpty,
                onTap: () async {
                  await _cameraCaptureService.stopPreviewStream();
                  setState(() {
                    _selectedEffectId = null;
                    _previewFaceBounds = null;
                  });
                },
              );
            }
            final preset = creatorEffectPresets[index - 1];
            return _TrayPill(
              label: preset.label(languageCode),
              selected: preset.id == _selectedEffectId,
              onTap: () async {
                setState(() => _selectedEffectId = preset.id);
                await _startFacePreview();
              },
            );
          },
        );
      case _CameraTray.mood:
        return _CarouselTray(
          height: 56,
          itemCount: kMaslakiMoodKeys.length + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _TrayPill(
                label: l10n.socialCreatorNoEffect,
                selected: (_maslakiMoodKey ?? '').isEmpty,
                onTap: () => setState(() => _maslakiMoodKey = null),
              );
            }
            final key = kMaslakiMoodKeys[index - 1];
            return _TrayPill(
              label: _maslakiMoodLabel(key),
              selected: _maslakiMoodKey == key,
              onTap: () => setState(() => _maslakiMoodKey = key),
            );
          },
        );
      case _CameraTray.none:
        return const SizedBox.shrink();
    }
  }

  Widget _layoutControlsRow(AppLocalizations l10n) {
    return Column(
      children: [
        SizedBox(
          height: 38,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: storyLayoutTemplates.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, index) {
              final template = storyLayoutTemplates[index];
              final selected = template == _layoutController.template;
              return _TrayPill(
                label: _layoutTemplateLabel(template),
                selected: selected,
                onTap: () => _layoutController.selectTemplate(template),
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        Text(
          l10n.socialCreatorLayoutHint(
            _layoutController.filledCount,
            _layoutController.cellCount,
          ),
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _controlsRow(AppLocalizations l10n) {
    final recording = _recordingController.isRecording;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22),
      child: Row(
        children: [
          // Gallery (story only; hidden while recording).
          SizedBox(
            width: 52,
            child: (_isStoryMode && !recording)
                ? _GalleryButton(
                    label: l10n.socialCreatorGallery,
                    onTap: _exporting ? null : _openGallery,
                  )
                : const SizedBox.shrink(),
          ),
          const Spacer(),
          GestureDetector(
            onTap: _exporting ? null : _onCapturePressed,
            child: _CaptureButton(
              recording: recording,
              busy: _exporting,
              captureType:
                  _isLayoutMode ? CreatorCaptureType.photo : _captureType,
            ),
          ),
          const Spacer(),
          SizedBox(
            width: 52,
            child: _isLayoutMode
                ? _DoneButton(
                    enabled: _layoutController.isComplete && !_exporting,
                    tooltip: l10n.socialCreatorLayoutDone,
                    onTap: _finishLayout,
                  )
                : (recording
                    ? const SizedBox.shrink()
                    : _GlassIconButton(
                        icon: Icons.cameraswitch_outlined,
                        tooltip: l10n.socialCreatorSwitchCamera,
                        onTap: _toggleCamera,
                      )),
          ),
        ],
      ),
    );
  }

  Widget _captureTypeToggle(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _ModeChip(
            label: l10n.socialCreatorPhotoMode,
            selected: _captureType == CreatorCaptureType.photo,
            onTap: () => _changeCaptureType(CreatorCaptureType.photo),
          ),
          _ModeChip(
            label: l10n.commonVideo,
            selected: _captureType == CreatorCaptureType.video,
            onTap: () => _changeCaptureType(CreatorCaptureType.video),
          ),
        ],
      ),
    );
  }

  Widget _modeStrip(AppLocalizations l10n) {
    if (!_isStoryMode) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _ModeChip(
          label: l10n.socialStoryModeStory,
          selected: _storyMode == _StoryMode.camera,
          onTap: () => _selectStoryMode(_StoryMode.camera),
        ),
        _ModeChip(
          label: l10n.socialStoryModeLayout,
          selected: _storyMode == _StoryMode.layout,
          onTap: () => _selectStoryMode(_StoryMode.layout),
        ),
        _ModeChip(
          label: l10n.socialStoryModeText,
          selected: false,
          onTap: () => _selectStoryMode(_StoryMode.text),
        ),
      ],
    );
  }

  Widget _cameraUnavailableScaffold(AppLocalizations l10n) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: const MaslakiBackButton(fallbackTabIndex: 2),
        title: Text(l10n.socialCreatorTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.socialCreatorCameraUnavailable,
                textAlign: TextAlign.center,
              ),
              if ((_error ?? '').trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _bootstrap,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n.commonRetry),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _flashIcon(FlashMode mode) {
    switch (mode) {
      case FlashMode.always:
      case FlashMode.torch:
        return Icons.flash_on_rounded;
      case FlashMode.auto:
        return Icons.flash_auto_rounded;
      case FlashMode.off:
        return Icons.flash_off_rounded;
    }
  }
}

// ── Shared chrome widgets ──────────────────────────────────────────────────────

/// Subtle top + bottom gradient so the white controls stay legible over video.
class _StageScrim extends StatelessWidget {
  const _StageScrim();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.black.withValues(alpha: 0.32),
              Colors.transparent,
              Colors.transparent,
              Colors.black.withValues(alpha: 0.46),
            ],
            stops: const [0.0, 0.18, 0.66, 1.0],
          ),
        ),
      ),
    );
  }
}

class _GlassIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _GlassIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkResponse(
        onTap: onTap,
        radius: 26,
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white24),
          ),
          child: Icon(icon, color: Colors.white, size: 22),
        ),
      ),
    );
  }
}

class _SideRailButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final VoidCallback onTap;

  const _SideRailButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: active
                    ? gold.withValues(alpha: 0.22)
                    : Colors.black.withValues(alpha: 0.34),
                shape: BoxShape.circle,
                border: Border.all(
                  color: active ? gold : Colors.white24,
                  width: 1.2,
                ),
              ),
              child: Icon(
                icon,
                color: active ? gold : Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(height: 3),
            SizedBox(
              width: 56,
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: active ? gold : Colors.white70,
                  fontSize: 9.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CarouselTray extends StatelessWidget {
  final double height;
  final int itemCount;
  final Widget Function(BuildContext, int) itemBuilder;

  const _CarouselTray({
    required this.height,
    required this.itemCount,
    required this.itemBuilder,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: SizedBox(
        height: height,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          itemCount: itemCount,
          separatorBuilder: (_, _) => const SizedBox(width: 8),
          itemBuilder: itemBuilder,
        ),
      ),
    );
  }
}

class _TrayPill extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _TrayPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: selected
              ? gold.withValues(alpha: 0.20)
              : Colors.black.withValues(alpha: 0.36),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? gold : Colors.white24,
            width: 1.2,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? gold : Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}

class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? const Color(0xFFD4AF37) : Colors.white70,
            fontWeight: selected ? FontWeight.w900 : FontWeight.w600,
            fontSize: 14,
            letterSpacing: 0.2,
          ),
        ),
      ),
    );
  }
}

class _GalleryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _GalleryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: label,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.34),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white38, width: 1.4),
          ),
          child: const Icon(
            Icons.photo_library_outlined,
            color: Colors.white,
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  final bool enabled;
  final String tooltip;
  final VoidCallback onTap;

  const _DoneButton({
    required this.enabled,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: enabled ? gold : Colors.white.withValues(alpha: 0.12),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.check_rounded,
            color: enabled ? const Color(0xFF0D1B2A) : Colors.white38,
            size: 24,
          ),
        ),
      ),
    );
  }
}

/// Compact 9:16 progress frame for Layout mode shown at top-center.
class _LayoutGridFrame extends StatelessWidget {
  final StoryLayoutController controller;
  final ValueChanged<int> onSelectTile;
  final ValueChanged<int> onDeleteTile;

  const _LayoutGridFrame({
    required this.controller,
    required this.onSelectTile,
    required this.onDeleteTile,
  });

  @override
  Widget build(BuildContext context) {
    const frameWidth = 92.0;
    const frameHeight = frameWidth * 16 / 9;
    final template = controller.template;
    return Align(
      alignment: Alignment.topCenter,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.only(top: 56),
          child: Container(
            width: frameWidth,
            height: frameHeight,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: const Color(0xFF0D1B2A).withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              children: List<Widget>.generate(template.rows, (row) {
                return Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: row == template.rows - 1 ? 0 : 3),
                    child: Row(
                      children: List<Widget>.generate(template.columns, (col) {
                        final index = row * template.columns + col;
                        final tile = controller.tiles[index];
                        final isCurrent = index == controller.currentIndex;
                        return Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(
                              right: col == template.columns - 1 ? 0 : 3,
                            ),
                            child: _LayoutCell(
                              tile: tile,
                              isCurrent: isCurrent,
                              onTap: () => onSelectTile(index),
                              onDelete: () => onDeleteTile(index),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}

class _LayoutCell extends StatelessWidget {
  final StoryLayoutTile tile;
  final bool isCurrent;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _LayoutCell({
    required this.tile,
    required this.isCurrent,
    required this.onTap,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    const gold = Color(0xFFD4AF37);
    return GestureDetector(
      onTap: tile.hasImage ? onDelete : onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: isCurrent ? gold : Colors.white30,
            width: isCurrent ? 1.6 : 0.8,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: tile.hasImage
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(tile.imagePath!), fit: BoxFit.cover),
                  Container(
                    alignment: Alignment.center,
                    color: Colors.black.withValues(alpha: 0.25),
                    child: const Icon(
                      Icons.close_rounded,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ],
              )
            : Center(
                child: Icon(
                  isCurrent ? Icons.camera_alt_rounded : Icons.add_rounded,
                  color: isCurrent ? gold : Colors.white54,
                  size: 16,
                ),
              ),
      ),
    );
  }
}

class _RecordingBadge extends StatelessWidget {
  final Duration elapsed;
  final double maxSeconds;

  const _RecordingBadge({required this.elapsed, required this.maxSeconds});

  @override
  Widget build(BuildContext context) {
    final progress = (elapsed.inMilliseconds / (maxSeconds * 1000)).clamp(
      0.0,
      1.0,
    );
    final mm = elapsed.inMinutes.toString().padLeft(2, '0');
    final ss = elapsed.inSeconds.remainder(60).toString().padLeft(2, '0');
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white24),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                value: progress,
                strokeWidth: 2.5,
                valueColor: const AlwaysStoppedAnimation<Color>(
                  Color(0xFFD4AF37),
                ),
                backgroundColor: Colors.white24,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '$mm:$ss',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptureButton extends StatelessWidget {
  final bool recording;
  final bool busy;
  final CreatorCaptureType captureType;

  const _CaptureButton({
    required this.recording,
    required this.busy,
    required this.captureType,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE6C98A), width: 4),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: recording ? 30 : 60,
          height: recording ? 30 : 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(recording ? 10 : 999),
            color: busy
                ? const Color(0xFF8A7A49)
                : recording
                    ? Colors.redAccent
                    : const Color(0xFFD4AF37),
          ),
          child: busy
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  captureType == CreatorCaptureType.photo
                      ? Icons.camera_alt_rounded
                      : (recording
                          ? Icons.stop_rounded
                          : Icons.fiber_manual_record_rounded),
                  color: captureType == CreatorCaptureType.photo || recording
                      ? Colors.white
                      : const Color(0xFF0D1B2A),
                ),
        ),
      ),
    );
  }
}

class _CreatorPreviewScaffold extends StatelessWidget {
  final CreatorPreviewDraft draft;
  final VideoPlayerController? videoController;
  final int coverFrameMs;
  final ValueChanged<int> onCoverFrameChanged;
  final Future<void> Function() onRetake;
  final Future<void> Function() onContinue;

  const _CreatorPreviewScaffold({
    required this.draft,
    required this.videoController,
    required this.coverFrameMs,
    required this.onCoverFrameChanged,
    required this.onRetake,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final durationMs = draft.clip.duration.inMilliseconds;
    return Scaffold(
      backgroundColor: const Color(0xFF09121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09121F),
        foregroundColor: Colors.white,
        title: Text(l10n.socialCreatorPreviewTitle),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (draft.clip.captureType == CreatorCaptureType.photo)
                        Image.file(
                          File(draft.clip.mediaFile.path!),
                          fit: BoxFit.contain,
                        )
                      else
                        _CreatorPreviewVideo(videoController: videoController),
                      if (draft.clip.hasMaslakiSeal)
                        const PositionedDirectional(
                          bottom: 14,
                          end: 14,
                          child: _MaslakiSealOverlay(),
                        ),
                    ],
                  ),
                ),
              ),
              if (draft.storySegments.length > 1) ...[
                const SizedBox(height: 14),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.socialCreatorStorySegments(draft.storySegments.length),
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 44,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: draft.storySegments.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, index) {
                      final segment = draft.storySegments[index];
                      return Chip(
                        label: Text(
                          '${index + 1}: ${segment.startSec.toStringAsFixed(0)}s - ${(segment.startSec + segment.durationSec).toStringAsFixed(0)}s',
                        ),
                      );
                    },
                  ),
                ),
              ],
              if (draft.mode == SocialCreatorMode.reel &&
                  draft.clip.captureType == CreatorCaptureType.video &&
                  durationMs > 0) ...[
                const SizedBox(height: 16),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    l10n.socialCreatorCoverFrame,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                ),
                Slider(
                  value: coverFrameMs.clamp(0, durationMs).toDouble(),
                  max: durationMs.toDouble(),
                  onChanged: (value) => onCoverFrameChanged(value.round()),
                ),
              ],
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        unawaited(onRetake());
                      },
                      icon: const Icon(Icons.refresh_rounded),
                      label: Text(l10n.socialCreatorRetake),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () {
                        unawaited(onContinue());
                      },
                      icon: const Icon(Icons.check_rounded),
                      label: Text(l10n.commonContinue),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CreatorPreviewVideo extends StatelessWidget {
  final VideoPlayerController? videoController;

  const _CreatorPreviewVideo({required this.videoController});

  @override
  Widget build(BuildContext context) {
    final controller = videoController;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }
    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _CreatorPermissionScaffold extends StatelessWidget {
  final bool permanentlyDenied;
  final Future<void> Function() onRetry;
  final Future<void> Function() onOpenSettings;

  const _CreatorPermissionScaffold({
    required this.permanentlyDenied,
    required this.onRetry,
    required this.onOpenSettings,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      backgroundColor: const Color(0xFF09121F),
      appBar: AppBar(
        backgroundColor: const Color(0xFF09121F),
        foregroundColor: Colors.white,
        leading: const MaslakiBackButton(
          fallbackTabIndex: 2,
          icon: Icons.close_rounded,
        ),
        title: Text(l10n.socialCreatorTitle),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.camera_alt_outlined, size: 52, color: Color(0xFFE6C98A)),
              const SizedBox(height: 14),
              Text(
                l10n.socialCreatorPermissionsTitle,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                permanentlyDenied
                    ? l10n.socialCreatorPermissionsPermanentlyDenied
                    : l10n.socialCreatorPermissionsBody,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.white70,
                    ),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: () {
                  if (permanentlyDenied) {
                    unawaited(onOpenSettings());
                    return;
                  }
                  unawaited(onRetry());
                },
                icon: Icon(
                  permanentlyDenied ? Icons.settings_outlined : Icons.refresh_rounded,
                ),
                label: Text(
                  permanentlyDenied ? l10n.commonSettings : l10n.commonRetry,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Gold Maslaki watermark badge shown on the camera preview and review screen.
class _MaslakiSealOverlay extends StatelessWidget {
  const _MaslakiSealOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha: 0.74),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(5, 4, 10, 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ClipOval(
              child: Image.asset(
                'assets/branding/logo_mark.png',
                width: 20,
                height: 20,
                fit: BoxFit.cover,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, _, _) => const Icon(
                  Icons.verified_rounded,
                  size: 16,
                  color: Color(0xFFD4AF37),
                ),
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'مسلكي',
              style: TextStyle(
                color: Color(0xFFD4AF37),
                fontSize: 12,
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
