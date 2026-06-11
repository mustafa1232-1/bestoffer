import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:social_core/social_core.dart';

enum SocialVoiceComposerPhase { idle, holding, locked, preview, sending }

enum SocialVoiceComposerResultType {
  none,
  started,
  locked,
  previewReady,
  cancelled,
  permissionDenied,
  tooShort,
  failed,
  sent,
}

class SocialVoiceComposerResult {
  final SocialVoiceComposerResultType type;
  final Object? error;

  const SocialVoiceComposerResult(this.type, {this.error});
}

class SocialVoiceRecordingDraft {
  final LocalMediaFile file;
  final Duration duration;

  const SocialVoiceRecordingDraft({required this.file, required this.duration});

  int get durationMs => duration.inMilliseconds;
}

class SocialVoiceComposerState {
  final SocialVoiceComposerPhase phase;
  final Duration duration;
  final SocialVoiceRecordingDraft? draft;

  const SocialVoiceComposerState({
    required this.phase,
    required this.duration,
    required this.draft,
  });

  const SocialVoiceComposerState.idle()
    : phase = SocialVoiceComposerPhase.idle,
      duration = Duration.zero,
      draft = null;

  bool get isRecording =>
      phase == SocialVoiceComposerPhase.holding ||
      phase == SocialVoiceComposerPhase.locked;

  bool get isLocked => phase == SocialVoiceComposerPhase.locked;

  bool get hasPreview =>
      phase == SocialVoiceComposerPhase.preview ||
      phase == SocialVoiceComposerPhase.sending;

  bool get isSending => phase == SocialVoiceComposerPhase.sending;
}

abstract class SocialVoiceRecorderDriver {
  Future<void> start(String path);

  Future<String?> stop();

  Future<void> dispose();
}

class DefaultSocialVoiceRecorderDriver implements SocialVoiceRecorderDriver {
  final AudioRecorder _recorder = AudioRecorder();

  @override
  Future<void> start(String path) {
    return _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 96000,
        sampleRate: 44100,
      ),
      path: path,
    );
  }

  @override
  Future<String?> stop() => _recorder.stop();

  @override
  Future<void> dispose() => _recorder.dispose();
}

typedef SocialVoicePermissionRequester = Future<bool> Function();
typedef SocialVoiceTempDirProvider = Future<Directory> Function();
typedef SocialVoiceNow = DateTime Function();
typedef SocialVoiceDeleteFile = Future<void> Function(String path);

class SocialVoiceComposerController extends ChangeNotifier {
  SocialVoiceComposerController({
    SocialVoiceRecorderDriver? recorder,
    SocialVoicePermissionRequester? requestPermission,
    SocialVoiceTempDirProvider? tempDirProvider,
    SocialVoiceDeleteFile? deleteFile,
    SocialVoiceNow? now,
    Duration minimumDuration = const Duration(seconds: 1),
  }) : _recorder = recorder ?? DefaultSocialVoiceRecorderDriver(),
       _requestPermission = requestPermission ?? _defaultRequestPermission,
       _tempDirProvider = tempDirProvider ?? getTemporaryDirectory,
       _deleteFile = deleteFile ?? _defaultDeleteFile,
       _now = now ?? DateTime.now,
       _minimumDuration = minimumDuration;

  final SocialVoiceRecorderDriver _recorder;
  final SocialVoicePermissionRequester _requestPermission;
  final SocialVoiceTempDirProvider _tempDirProvider;
  final SocialVoiceDeleteFile _deleteFile;
  final SocialVoiceNow _now;
  final Duration _minimumDuration;

  SocialVoiceComposerState _state = const SocialVoiceComposerState.idle();
  Timer? _ticker;
  DateTime? _startedAt;
  String? _activeRecordingPath;
  bool _disposed = false;

  SocialVoiceComposerState get state => _state;

  SocialVoiceRecordingDraft? get draft => _state.draft;

  Future<SocialVoiceComposerResult> startHolding({
    required String draftKey,
  }) async {
    if (_state.isRecording || _state.isSending) {
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.none,
      );
    }
    if (_state.draft != null) {
      await discardDraft();
    }
    final granted = await _requestPermission();
    if (!granted) {
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.permissionDenied,
      );
    }

    try {
      final tempDir = await _tempDirProvider();
      final stamp = _now().millisecondsSinceEpoch;
      final path =
          '${tempDir.path}${Platform.pathSeparator}${draftKey}_$stamp.m4a';
      await _recorder.start(path);
      _activeRecordingPath = path;
      _startedAt = _now();
      _setState(
        const SocialVoiceComposerState(
          phase: SocialVoiceComposerPhase.holding,
          duration: Duration.zero,
          draft: null,
        ),
      );
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 200), (_) {
        if (!_state.isRecording || _startedAt == null) return;
        final elapsed = _now().difference(_startedAt!);
        _setState(
          SocialVoiceComposerState(
            phase: _state.phase,
            duration: elapsed,
            draft: null,
          ),
        );
      });
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.started,
      );
    } catch (error) {
      await _cleanupActiveRecordingPath();
      _startedAt = null;
      _ticker?.cancel();
      _setState(const SocialVoiceComposerState.idle());
      return SocialVoiceComposerResult(
        SocialVoiceComposerResultType.failed,
        error: error,
      );
    }
  }

  SocialVoiceComposerResult lock() {
    if (_state.phase != SocialVoiceComposerPhase.holding) {
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.none,
      );
    }
    _setState(
      SocialVoiceComposerState(
        phase: SocialVoiceComposerPhase.locked,
        duration: _state.duration,
        draft: null,
      ),
    );
    return const SocialVoiceComposerResult(
      SocialVoiceComposerResultType.locked,
    );
  }

  Future<SocialVoiceComposerResult> releaseHoldToPreview() async {
    if (_state.phase != SocialVoiceComposerPhase.holding) {
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.none,
      );
    }
    return _finishRecordingToPreview();
  }

  Future<SocialVoiceComposerResult> stopLockedRecordingToPreview() async {
    if (_state.phase != SocialVoiceComposerPhase.locked) {
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.none,
      );
    }
    return _finishRecordingToPreview();
  }

  Future<SocialVoiceComposerResult> handleAppPause() async {
    if (!_state.isRecording) {
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.none,
      );
    }
    return _finishRecordingToPreview();
  }

  Future<SocialVoiceComposerResult> cancelRecording() async {
    if (_state.isRecording) {
      _ticker?.cancel();
      try {
        await _recorder.stop();
      } catch (_) {
        // Best effort only.
      }
      await _cleanupActiveRecordingPath();
      _startedAt = null;
      _setState(const SocialVoiceComposerState.idle());
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.cancelled,
      );
    }
    if (_state.draft != null) {
      await discardDraft();
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.cancelled,
      );
    }
    return const SocialVoiceComposerResult(SocialVoiceComposerResultType.none);
  }

  Future<void> discardDraft() async {
    final existing = _state.draft;
    _setState(const SocialVoiceComposerState.idle());
    if (existing?.file.path != null) {
      await _deleteFile(existing!.file.path!);
    }
  }

  Future<SocialVoiceComposerResult> sendDraft(
    Future<void> Function(SocialVoiceRecordingDraft draft) sender,
  ) async {
    final existing = _state.draft;
    if (existing == null || _state.isSending) {
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.none,
      );
    }
    _setState(
      SocialVoiceComposerState(
        phase: SocialVoiceComposerPhase.sending,
        duration: existing.duration,
        draft: existing,
      ),
    );
    try {
      await sender(existing);
      await discardDraft();
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.sent,
      );
    } catch (error) {
      _setState(
        SocialVoiceComposerState(
          phase: SocialVoiceComposerPhase.preview,
          duration: existing.duration,
          draft: existing,
        ),
      );
      return SocialVoiceComposerResult(
        SocialVoiceComposerResultType.failed,
        error: error,
      );
    }
  }

  Future<SocialVoiceComposerResult> _finishRecordingToPreview() async {
    final elapsed = _state.duration;
    _ticker?.cancel();
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {
      path = null;
    }
    final safeDuration = elapsed > Duration.zero
        ? elapsed
        : (_startedAt == null ? Duration.zero : _now().difference(_startedAt!));
    _startedAt = null;
    if (path == null || path.trim().isEmpty) {
      await _cleanupActiveRecordingPath();
      _setState(const SocialVoiceComposerState.idle());
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.failed,
      );
    }
    if (safeDuration < _minimumDuration) {
      await _deleteFile(path);
      _activeRecordingPath = null;
      _setState(const SocialVoiceComposerState.idle());
      return const SocialVoiceComposerResult(
        SocialVoiceComposerResultType.tooShort,
      );
    }
    _activeRecordingPath = null;
    final fileName = path.split(RegExp(r'[\\/]')).last;
    final draft = SocialVoiceRecordingDraft(
      file: LocalMediaFile(
        name: fileName,
        path: path,
        bytes: null,
        mimeType: 'audio/mp4',
      ),
      duration: safeDuration,
    );
    _setState(
      SocialVoiceComposerState(
        phase: SocialVoiceComposerPhase.preview,
        duration: safeDuration,
        draft: draft,
      ),
    );
    return const SocialVoiceComposerResult(
      SocialVoiceComposerResultType.previewReady,
    );
  }

  void _setState(SocialVoiceComposerState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  Future<void> _cleanupActiveRecordingPath() async {
    final path = _activeRecordingPath;
    _activeRecordingPath = null;
    if (path != null && path.trim().isNotEmpty) {
      await _deleteFile(path);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    final draftPath = _state.draft?.file.path;
    if (_state.isRecording) {
      unawaited(_stopRecorderSafely());
    }
    if (_activeRecordingPath != null) {
      unawaited(_cleanupActiveRecordingPath());
    }
    if (draftPath != null && draftPath.trim().isNotEmpty) {
      unawaited(_deleteFile(draftPath));
    }
    unawaited(_recorder.dispose());
    super.dispose();
  }

  Future<void> _stopRecorderSafely() async {
    try {
      await _recorder.stop();
    } catch (_) {
      // Ignore recorder shutdown failures during dispose.
    }
  }

  static Future<bool> _defaultRequestPermission() async {
    final permission = await Permission.microphone.request();
    return permission.isGranted;
  }

  static Future<void> _defaultDeleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    } catch (_) {
      // Ignore temp cleanup failures.
    }
  }
}
