import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:video_player/video_player.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/widgets/maslaki_back_button.dart';
import '../../../core/files/local_media_file.dart';
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
import 'story_segmentation_service.dart';
import 'creator_filter_registry.dart';

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
  late final RecordingSessionController _recordingController;

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
  String? _error;
  CreatorPreviewDraft? _previewDraft;
  VideoPlayerController? _previewVideoController;
  List<FaceTrackingSample> _trackingSamples = const <FaceTrackingSample>[];
  int _coverFrameMs = 0;

  // ── Maslaki unique features state ─────────────────────────────────────────
  /// Auto-resolved on init; shown as a non-interactive badge.
  late String _timeMoodKey;

  /// User-confirmed location label from Place Pulse.
  String? _placePulseLabel;
  bool _placePulseLocating = false;

  /// Maslaki Seal toggle.
  bool _maslakiSealEnabled = false;

  CameraController? get _cameraController => _cameraCaptureService.controller;
  bool get _isStoryMode => widget.mode == SocialCreatorMode.story;

  double get _maxVideoSeconds =>
      widget.mode == SocialCreatorMode.reel
          ? reelMaxSeconds
          : creatorStoryRecordingHardCapSeconds;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tempMediaService = CreatorTempMediaService();
    _permissionsService = CreatorPermissionsService();
    _capabilitiesService = CreatorCapabilitiesService();
    _cameraCaptureService = CameraCaptureService(_tempMediaService);
    _faceTrackingService = FaceTrackingService();
    _filterPipelineService = FilterPipelineService(_tempMediaService);
    _effectPipelineService = EffectPipelineService(_tempMediaService);
    _reelExportService = ReelExportService(_tempMediaService);
    _storySegmentationService = StorySegmentationService();
    _recordingController = RecordingSessionController()
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
    if (_exporting) return;
    await _cameraCaptureService.switchCamera();
    if (!mounted) return;
    if (_shouldRunFacePreview) {
      await _startFacePreview();
    } else {
      await _cameraCaptureService.stopPreviewStream();
    }
    setState(() {});
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
      }
    });
    if (_shouldRunFacePreview) {
      await _startFacePreview();
    }
  }

  Future<void> _capturePrimaryAction() async {
    if (_exporting) return;
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
        clip: RecordedClipDraft(
          mediaFile: LocalMediaFile(
            name: currentFile.uri.pathSegments.last,
            path: currentFile.path,
            bytes: null,
            mimeType: currentMimeType,
          ),
          captureType: CreatorCaptureType.photo,
          duration: Duration.zero,
          mediaSize: null,
          captureSource: 'camera_photo',
          filterId: _selectedFilterId == creatorNoFilter.id
              ? null
              : _selectedFilterId,
          effectId: effect?.id,
          trackingSamples: const <FaceTrackingSample>[],
          coverFrameMs: null,
          timeMoodKey: _timeMoodKey,
          placePulseLabel: (_placePulseLabel ?? '').trim().isEmpty
              ? null
              : _placePulseLabel,
          hasMaslakiSeal: _maslakiSealEnabled,
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
        clip: RecordedClipDraft(
          mediaFile: exportedVideo,
          captureType: CreatorCaptureType.video,
          duration: info.$1,
          mediaSize: info.$2,
          captureSource: 'camera_video',
          filterId: _selectedFilterId == creatorNoFilter.id
              ? null
              : _selectedFilterId,
          effectId: null,
          trackingSamples: _trackingSamples,
          coverFrameMs: durationMs > 0 ? durationMs ~/ 3 : null,
          timeMoodKey: _timeMoodKey,
          placePulseLabel: (_placePulseLabel ?? '').trim().isEmpty
              ? null
              : _placePulseLabel,
          hasMaslakiSeal: _maslakiSealEnabled,
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

  Future<void> _onPlacePulseTap() async {
    if (_placePulseLocating) return;
    // If label already set, show edit dialog.
    if ((_placePulseLabel ?? '').trim().isNotEmpty) {
      await _showPlacePulseDialog(prefill: _placePulseLabel);
      return;
    }
    setState(() => _placePulseLocating = true);
    try {
      String prefill = '';
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (serviceEnabled) {
        final permission = await Geolocator.checkPermission();
        if (permission == LocationPermission.always ||
            permission == LocationPermission.whileInUse) {
          final position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.low,
          ).timeout(const Duration(seconds: 6));
          prefill = '${position.latitude.toStringAsFixed(3)}° N, '
              '${position.longitude.toStringAsFixed(3)}° E';
        }
      }
      if (!mounted) return;
      await _showPlacePulseDialog(prefill: prefill.isNotEmpty ? prefill : null);
    } catch (_) {
      if (!mounted) return;
      await _showPlacePulseDialog(prefill: null);
    } finally {
      if (mounted) setState(() => _placePulseLocating = false);
    }
  }

  Future<void> _showPlacePulseDialog({String? prefill}) async {
    final l10n = context.l10n;
    final controller = TextEditingController(text: prefill ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.socialCreatorPlacePulse),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLength: 60,
          decoration: InputDecoration(
            hintText: l10n.socialCreatorPlacePulseHint,
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(null),
            child: Text(
              MaterialLocalizations.of(ctx).cancelButtonLabel,
            ),
          ),
          if ((_placePulseLabel ?? '').trim().isNotEmpty)
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(''),
              child: Text(MaterialLocalizations.of(ctx).deleteButtonTooltip),
            ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(controller.text.trim()),
            child: Text(l10n.socialCreatorPlacePulseSave),
          ),
        ],
      ),
    );
    controller.dispose();
    if (!mounted) return;
    if (result == null) return; // cancelled
    setState(() => _placePulseLabel = result.isEmpty ? null : result);
  }

  Future<void> _completePreview() async {
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
      ),
    );
    Navigator.of(context).pop(nextPreview);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_cameraCaptureService.dispose());
    unawaited(_cameraCaptureService.stopPreviewStream());
    unawaited(_faceTrackingService.dispose());
    unawaited(_previewVideoController?.dispose());
    _recordingController.dispose();
    super.dispose();
  }

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
        onContinue: _completePreview,
      );
    }

    if (_initializing) {
      return const Scaffold(
        backgroundColor: Color(0xFF09121F),
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

    if ((_capabilities?.hasCamera ?? false) == false || _cameraController == null) {
      return Scaffold(
        backgroundColor: const Color(0xFF09121F),
        appBar: AppBar(
          backgroundColor: const Color(0xFF09121F),
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

    final controller = _cameraController!;
    final effect = resolveCreatorEffectPreset(_selectedEffectId);
    final filterPreset = resolveCreatorFilterPreset(_selectedFilterId);
    final languageCode = Localizations.localeOf(context).languageCode;

    return Scaffold(
      backgroundColor: const Color(0xFF09121F),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Row(
                children: [
                  const MaslakiBackButton(
                    fallbackTabIndex: 2,
                    icon: Icons.close_rounded,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.mode == SocialCreatorMode.story
                          ? l10n.socialCreatorStoryMode
                          : l10n.socialCreatorReelMode,
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.socialCreatorSwitchCamera,
                    onPressed: _toggleCamera,
                    icon: const Icon(Icons.cameraswitch_outlined, color: Colors.white),
                  ),
                  IconButton(
                    tooltip: l10n.socialCreatorFlash,
                    onPressed: _toggleFlash,
                    icon: Icon(_flashIcon(_flashMode), color: Colors.white),
                  ),
                ],
              ),
            ),
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: controller.value.aspectRatio,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColorFiltered(
                          colorFilter: ColorFilter.matrix(filterPreset.previewMatrix),
                          child: CameraPreview(controller),
                        ),
                        if (effect != null && _captureType == CreatorCaptureType.photo)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: CreatorEffectPreviewPainter(
                                effect: effect,
                                faceBounds: _previewFaceBounds,
                              ),
                            ),
                          ),
                        if (_recordingController.isRecording)
                          PositionedDirectional(
                            top: 16,
                            end: 16,
                            child: _RecordingBadge(
                              elapsed: _recordingController.elapsed,
                              maxSeconds: _maxVideoSeconds,
                            ),
                          ),
                        // Maslaki Seal overlay — gold badge bottom-right
                        if (_maslakiSealEnabled)
                          const PositionedDirectional(
                            bottom: 14,
                            end: 14,
                            child: _MaslakiSealOverlay(),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if ((_error ?? '').trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 10, 18, 0),
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
              child: Column(
                children: [
                  if (_isStoryMode)
                    SegmentedButton<CreatorCaptureType>(
                      segments: <ButtonSegment<CreatorCaptureType>>[
                        ButtonSegment(
                          value: CreatorCaptureType.photo,
                          label: Text(l10n.socialCreatorPhotoMode),
                          icon: const Icon(Icons.photo_camera_outlined),
                        ),
                        ButtonSegment(
                          value: CreatorCaptureType.video,
                          label: Text(l10n.commonVideo),
                          icon: const Icon(Icons.videocam_outlined),
                        ),
                      ],
                      selected: <CreatorCaptureType>{_captureType},
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          unawaited(_changeCaptureType(selection.first));
                        }
                      },
                    ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 42,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: creatorFilterPresets.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final preset = creatorFilterPresets[index];
                        final selected = preset.id == _selectedFilterId;
                        return ChoiceChip(
                          selected: selected,
                          label: Text(preset.label(languageCode)),
                          onSelected: (_) => setState(() {
                            _selectedFilterId = preset.id;
                          }),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (_captureType == CreatorCaptureType.photo)
                    SizedBox(
                      height: 42,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: creatorEffectPresets.length + 1,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            return ChoiceChip(
                              selected: (_selectedEffectId ?? '').isEmpty,
                              label: Text(l10n.socialCreatorNoEffect),
                              onSelected: (_) async {
                                await _cameraCaptureService.stopPreviewStream();
                                setState(() {
                                  _selectedEffectId = null;
                                  _previewFaceBounds = null;
                                });
                              },
                            );
                          }
                          final preset = creatorEffectPresets[index - 1];
                          final selected = preset.id == _selectedEffectId;
                          return ChoiceChip(
                            selected: selected,
                            label: Text(preset.label(languageCode)),
                            onSelected: (_) async {
                              setState(() => _selectedEffectId = preset.id);
                              await _startFacePreview();
                            },
                          );
                        },
                      ),
                    )
                  else
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: Text(
                        l10n.socialCreatorEffectsPhotoOnly,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: context.maslakiTokens.textMuted,
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  // ── Maslaki unique feature chips ───────────────────────────
                  if (!_recordingController.isRecording)
                    SizedBox(
                      height: 38,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        children: [
                          // Time Mood — always shown, non-interactive
                          _MaslakiFeatureChip(
                            icon: Icons.wb_twilight_rounded,
                            label: _timeMoodLabel(),
                            active: true,
                            interactive: false,
                            onTap: null,
                          ),
                          const SizedBox(width: 8),
                          // Place Pulse — tap to set location label
                          _MaslakiFeatureChip(
                            icon: _placePulseLocating
                                ? Icons.hourglass_top_rounded
                                : Icons.location_on_outlined,
                            label: (_placePulseLabel ?? '').trim().isNotEmpty
                                ? _placePulseLabel!
                                : l10n.socialCreatorPlacePulse,
                            active: (_placePulseLabel ?? '').trim().isNotEmpty,
                            interactive: true,
                            onTap: _placePulseLocating || _exporting
                                ? null
                                : _onPlacePulseTap,
                          ),
                          const SizedBox(width: 8),
                          // Maslaki Seal toggle
                          _MaslakiFeatureChip(
                            icon: Icons.verified_rounded,
                            label: _maslakiSealEnabled
                                ? l10n.socialCreatorMaslakiSealOn
                                : l10n.socialCreatorMaslakiSeal,
                            active: _maslakiSealEnabled,
                            interactive: true,
                            onTap: _exporting
                                ? null
                                : () => setState(
                                    () => _maslakiSealEnabled =
                                        !_maslakiSealEnabled,
                                  ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _captureType == CreatorCaptureType.photo
                              ? l10n.socialCreatorPhotoHint
                              : l10n.socialCreatorVideoHint,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: context.maslakiTokens.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: _exporting ? null : _capturePrimaryAction,
                        child: _CaptureButton(
                          recording: _recordingController.isRecording,
                          busy: _exporting,
                          captureType: _captureType,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
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
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE6C98A), width: 3),
        color: Colors.white.withValues(alpha: 0.06),
      ),
      child: Center(
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          width: recording ? 28 : 54,
          height: recording ? 28 : 54,
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
                  padding: EdgeInsets.all(15),
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

// ── Maslaki unique feature widgets ────────────────────────────────────────────

class _MaslakiFeatureChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool active;
  final bool interactive;
  final VoidCallback? onTap;

  const _MaslakiFeatureChip({
    required this.icon,
    required this.label,
    required this.active,
    required this.interactive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    const goldColor = Color(0xFFD4AF37);
    const goldDim = Color(0xFF8A7A49);
    final activeColor = active ? goldColor : Colors.white54;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: active
              ? goldColor.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: active ? goldDim : Colors.white24,
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: activeColor),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: activeColor,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.1,
              ),
            ),
            if (interactive && active) ...[
              const SizedBox(width: 4),
              const Icon(Icons.check_circle_rounded, size: 13, color: Color(0xFFD4AF37)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Gold Maslaki watermark badge shown on the camera preview and preview screen.
class _MaslakiSealOverlay extends StatelessWidget {
  const _MaslakiSealOverlay();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1B2A).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD4AF37), width: 1.2),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.verified_rounded, size: 14, color: Color(0xFFD4AF37)),
            SizedBox(width: 4),
            Text(
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
