import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../../../core/media/media_cache_models.dart';
import '../../../core/media/media_cache_service.dart';
import '../media/social_media_presentation.dart';

typedef ReelVideoControllerFactory = VideoPlayerController Function(String url);
typedef ReelVideoSourceResolver =
    Future<CachedVideoSource> Function(String url);

/// Owns the [VideoPlayerController]s for the reels viewer.
///
/// Only current/next are retained. The active reel is the only one allowed to
/// play and every controller is disposed as soon as it leaves this window.
class ReelPlaybackCoordinator extends ChangeNotifier {
  ReelPlaybackCoordinator({
    ReelVideoControllerFactory? controllerFactory,
    ReelVideoSourceResolver? videoSourceResolver,
  }) : _factory = controllerFactory,
       _sourceResolver =
           videoSourceResolver ??
           ((url) => MediaCacheService.instance.resolveVideoSource(url: url));

  final ReelVideoControllerFactory? _factory;
  final ReelVideoSourceResolver _sourceResolver;

  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, String> _controllerUrls = {};
  final Map<int, String> _pendingControllerUrls = {};
  final Map<int, int> _sourceGenerations = {};
  final Set<int> _failed = {};
  final Map<int, bool> _lastBufferingState = {};
  final Map<int, bool> _lastInitializedState = {};

  List<SocialMediaPresentation> _items = const [];
  int _activeIndex = 0;
  bool _muted = false;
  bool _userPaused = false;
  double _playbackSpeed = 1;
  bool _routeVisible = true;
  bool _appActive = true;
  bool _disposed = false;

  int get activeIndex => _activeIndex;
  bool get isMuted => _muted;
  bool get isActivePaused => _userPaused;
  double get playbackSpeed => _playbackSpeed;

  VideoPlayerController? controllerFor(int index) => _controllers[index];
  bool isFailed(int index) => _failed.contains(index);

  bool isBuffering(int index) {
    final c = _controllers[index];
    if (c == null) {
      return _pendingControllerUrls.containsKey(index) ||
          !_failed.contains(index);
    }
    final v = c.value;
    return v.isBuffering || !v.isInitialized;
  }

  void setItems(List<SocialMediaPresentation> items) {
    if (_disposed) return;
    _failed.removeWhere(
      (index) =>
          index >= items.length ||
          index >= _items.length ||
          items[index].videoPlaybackUrl != _items[index].videoPlaybackUrl,
    );
    _items = items;
    if (_items.isEmpty) {
      _failed.clear();
      _activeIndex = 0;
    } else if (_activeIndex >= _items.length) {
      _activeIndex = _items.length - 1;
    }
    _reconcileWindow();
  }

  Future<void> setActiveIndex(int index) async {
    if (_disposed || _items.isEmpty) return;
    final safeIndex = index.clamp(0, _items.length - 1).toInt();
    if (safeIndex == _activeIndex && _controllers.containsKey(safeIndex)) {
      _applyPlayState();
      return;
    }
    _activeIndex = safeIndex;
    _userPaused = false;
    _reconcileWindow();
    notifyListeners();
  }

  void togglePlay() {
    if (_disposed) return;
    _userPaused = !_userPaused;
    _applyPlayState();
    notifyListeners();
  }

  void setMuted(bool muted) {
    if (_disposed) return;
    _muted = muted;
    for (final c in _controllers.values) {
      if (c.value.isInitialized) c.setVolume(muted ? 0 : 1);
    }
    notifyListeners();
  }

  void toggleMuted() => setMuted(!_muted);

  Future<void> setPlaybackSpeed(double speed) async {
    if (_disposed) return;
    final normalized = speed <= 0 ? 1.0 : speed;
    if (_playbackSpeed == normalized) return;
    _playbackSpeed = normalized;
    final controller = _controllers[_activeIndex];
    if (controller != null && controller.value.isInitialized) {
      await controller.setPlaybackSpeed(normalized);
    }
    notifyListeners();
  }

  Future<void> replayActive() async {
    if (_disposed || _activeIndex < 0 || _activeIndex >= _items.length) return;
    final controller = _controllers[_activeIndex];
    if (controller == null) return;
    try {
      await controller.seekTo(Duration.zero);
    } catch (_) {}
    _applyPlayState();
  }

  void setRouteVisible(bool visible) {
    if (_routeVisible == visible) return;
    _routeVisible = visible;
    _applyPlayState();
  }

  void setAppActive(bool active) {
    if (_appActive == active) return;
    _appActive = active;
    _applyPlayState();
  }

  bool get _shouldPlayActive => _routeVisible && _appActive && !_userPaused;

  void _applyPlayState() {
    for (final entry in _controllers.entries) {
      final isActive = entry.key == _activeIndex;
      final c = entry.value;
      if (!c.value.isInitialized) continue;
      if (isActive && _shouldPlayActive) {
        c.setVolume(_muted ? 0 : 1);
        c.setPlaybackSpeed(_playbackSpeed);
        if (!c.value.isPlaying) c.play();
      } else if (c.value.isPlaying) {
        c.pause();
      }
    }
  }

  void _reconcileWindow() {
    if (_disposed) return;
    if (_items.isEmpty) {
      for (final index in {
        ..._controllers.keys,
        ..._pendingControllerUrls.keys,
      }.toList()) {
        _disposeController(index);
      }
      return;
    }

    final keep = <int>{
      _activeIndex,
      _activeIndex + 1,
    }.where((i) => i >= 0 && i < _items.length).toSet();
    _failed.removeWhere((index) => !keep.contains(index));

    for (final index in {
      ..._controllers.keys,
      ..._pendingControllerUrls.keys,
    }.toList()) {
      if (!keep.contains(index)) _disposeController(index);
    }

    // Initialize the active item first so first-frame latency has priority over
    // background preloading, then warm the next reel.
    final ordered = <int>[
      _activeIndex,
      if (keep.contains(_activeIndex + 1)) _activeIndex + 1,
    ];
    for (final index in ordered) {
      if (index != _activeIndex &&
          _items[_activeIndex].hasVideo &&
          _controllers[_activeIndex]?.value.isInitialized != true &&
          !_failed.contains(_activeIndex)) {
        continue;
      }
      final media = _items[index];
      // A failed player stays in the retry state until an explicit retry or
      // until it leaves the retained window. Do not restart it on every tick.
      if (_failed.contains(index)) continue;
      if (!media.hasVideo) {
        _disposeController(index);
        continue;
      }
      final url = media.videoPlaybackUrl!;
      final existing = _controllers[index];
      if (existing != null && _controllerUrls[index] == url) continue;
      if (_pendingControllerUrls[index] == url) continue;
      if (existing != null || _pendingControllerUrls.containsKey(index)) {
        _disposeController(index);
      }
      _createController(index, url);
    }

    _applyPlayState();
  }

  void _createController(int index, String url) {
    _failed.remove(index);
    _lastBufferingState.remove(index);
    _lastInitializedState.remove(index);
    final generation = (_sourceGenerations[index] ?? 0) + 1;
    _sourceGenerations[index] = generation;
    final factory = _factory;
    if (factory != null) {
      try {
        _attachController(index, url, factory(url), generation);
      } catch (_) {
        _markSourceFailed(index, url, generation);
      }
      return;
    }

    _pendingControllerUrls[index] = url;
    _sourceResolver(url)
        .then((source) {
          if (_disposed ||
              _sourceGenerations[index] != generation ||
              _pendingControllerUrls[index] != url) {
            return;
          }
          _pendingControllerUrls.remove(index);
          final controller = source.isLocalFile
              ? VideoPlayerController.file(source.file!)
              : VideoPlayerController.networkUrl(source.uri);
          _attachController(index, url, controller, generation);
        })
        .catchError((Object _) {
          _markSourceFailed(index, url, generation);
        });
  }

  void _attachController(
    int index,
    String url,
    VideoPlayerController controller,
    int generation,
  ) {
    if (_disposed || _sourceGenerations[index] != generation) {
      controller.dispose();
      return;
    }
    _controllers[index] = controller;
    _controllerUrls[index] = url;
    controller.addListener(_onControllerTick);
    // Keep native looping disabled: SocialReelsScreenV3 owns completion and
    // either advances to the next reel or explicitly replays the final reel.
    // This avoids competing seek/loop behavior at the end of a video.
    controller
        .initialize()
        .timeout(const Duration(seconds: 20))
        .then((_) async {
          if (_disposed || _controllers[index] != controller) return;
          await controller.setLooping(false);
          if (_disposed || _controllers[index] != controller) return;
          _applyPlayState();
          _reconcileWindow();
          notifyListeners();
        })
        .catchError((Object error) {
          _markFailed(index, controller);
        });
  }

  void _markSourceFailed(int index, String url, int generation) {
    if (_disposed ||
        _sourceGenerations[index] != generation ||
        (_pendingControllerUrls[index] != null &&
            _pendingControllerUrls[index] != url)) {
      return;
    }
    _pendingControllerUrls.remove(index);
    _failed.add(index);
    notifyListeners();
  }

  void _markFailed(int index, VideoPlayerController controller) {
    if (_disposed || _controllers[index] != controller) return;
    _disposeController(index, deferDispose: true);
    _failed.add(index);
    notifyListeners();
  }

  void _onControllerTick() {
    if (_disposed) return;
    final index = _activeIndex;
    final c = _controllers[index];
    if (c == null) return;
    final value = c.value;
    if (value.hasError) {
      _markFailed(index, c);
      return;
    }
    final initialized = value.isInitialized;
    final buffering = value.isBuffering || !initialized;
    var changed = false;
    if (_lastInitializedState[index] != initialized) {
      _lastInitializedState[index] = initialized;
      changed = true;
    }
    if (_lastBufferingState[index] != buffering) {
      _lastBufferingState[index] = buffering;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  void _disposeController(int index, {bool deferDispose = false}) {
    _sourceGenerations[index] = (_sourceGenerations[index] ?? 0) + 1;
    _pendingControllerUrls.remove(index);
    final controller = _controllers.remove(index);
    _controllerUrls.remove(index);
    _lastBufferingState.remove(index);
    _lastInitializedState.remove(index);
    _failed.remove(index);
    if (controller != null) {
      controller.removeListener(_onControllerTick);
      void release() {
        controller.pause();
        controller.dispose();
      }

      // Runtime errors arrive inside the player's ValueNotifier callback.
      if (deferDispose) {
        Future<void>.microtask(release);
      } else {
        release();
      }
    }
  }

  void retry(int index) {
    if (_disposed ||
        index < _activeIndex ||
        index > _activeIndex + 1 ||
        index >= _items.length) {
      return;
    }
    final media = _items[index];
    if (!media.hasVideo) return;
    _disposeController(index);
    _createController(index, media.videoPlaybackUrl!);
    _applyPlayState();
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    for (final index in {
      ..._controllers.keys,
      ..._pendingControllerUrls.keys,
    }.toList()) {
      _disposeController(index);
    }
    super.dispose();
  }
}
