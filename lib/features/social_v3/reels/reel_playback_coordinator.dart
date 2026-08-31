import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../media/social_media_presentation.dart';

/// Owns the [VideoPlayerController]s for the reels viewer.
///
/// Only previous/current/next are retained, the active reel is the only one
/// allowed to play, adjacent reels initialize in advance, and every controller
/// is disposed as soon as it leaves the three-item window.
class ReelPlaybackCoordinator extends ChangeNotifier {
  ReelPlaybackCoordinator({
    VideoPlayerController Function(String url)? controllerFactory,
  }) : _factory =
           controllerFactory ??
           ((url) => VideoPlayerController.networkUrl(Uri.parse(url)));

  final VideoPlayerController Function(String url) _factory;

  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, String> _controllerUrls = {};
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
    if (c == null) return !_failed.contains(index);
    final v = c.value;
    return v.isBuffering || !v.isInitialized;
  }

  void setItems(List<SocialMediaPresentation> items) {
    _items = items;
    if (_items.isEmpty) {
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
      _userPaused = false;
      _applyPlayState();
      return;
    }
    _activeIndex = safeIndex;
    _userPaused = false;
    _reconcileWindow();
    notifyListeners();
  }

  void togglePlay() {
    _userPaused = !_userPaused;
    _applyPlayState();
    notifyListeners();
  }

  void setMuted(bool muted) {
    _muted = muted;
    for (final c in _controllers.values) {
      c.setVolume(muted ? 0 : 1);
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
      for (final index in _controllers.keys.toList()) {
        _disposeController(index);
      }
      return;
    }

    final keep = <int>{
      _activeIndex - 1,
      _activeIndex,
      _activeIndex + 1,
    }.where((i) => i >= 0 && i < _items.length).toSet();

    for (final index in _controllers.keys.toList()) {
      if (!keep.contains(index)) _disposeController(index);
    }

    // Initialize the active item first so first-frame latency has priority over
    // background preloading, then warm next/previous.
    final ordered = <int>[
      _activeIndex,
      if (keep.contains(_activeIndex + 1)) _activeIndex + 1,
      if (keep.contains(_activeIndex - 1)) _activeIndex - 1,
    ];
    for (final index in ordered) {
      final media = _items[index];
      if (!media.hasVideo) continue;
      final url = media.videoPlaybackUrl!;
      final existing = _controllers[index];
      if (existing != null && _controllerUrls[index] == url) continue;
      if (existing != null) _disposeController(index);
      _createController(index, url);
    }

    _applyPlayState();
  }

  void _createController(int index, String url) {
    _failed.remove(index);
    _lastBufferingState.remove(index);
    _lastInitializedState.remove(index);
    final controller = _factory(url);
    _controllers[index] = controller;
    _controllerUrls[index] = url;
    controller.addListener(_onControllerTick);
    // Keep native looping disabled: SocialReelsScreenV3 owns completion and
    // either advances to the next reel or explicitly replays the final reel.
    // This avoids competing seek/loop behavior at the end of a video.
    controller.setLooping(false);
    controller
        .initialize()
        .then((_) {
          if (_disposed || _controllers[index] != controller) return;
          controller.setVolume(_muted ? 0 : 1);
          controller.setPlaybackSpeed(_playbackSpeed);
          _applyPlayState();
          notifyListeners();
        })
        .catchError((Object error) {
          if (_disposed || _controllers[index] != controller) return;
          _failed.add(index);
          notifyListeners();
        });
  }

  void _onControllerTick() {
    if (_disposed) return;
    final index = _activeIndex;
    final c = _controllers[index];
    if (c == null) return;
    final value = c.value;
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

  void _disposeController(int index) {
    final controller = _controllers.remove(index);
    _controllerUrls.remove(index);
    _lastBufferingState.remove(index);
    _lastInitializedState.remove(index);
    _failed.remove(index);
    if (controller != null) {
      controller.removeListener(_onControllerTick);
      controller.pause();
      controller.dispose();
    }
  }

  void retry(int index) {
    if (index < 0 || index >= _items.length) return;
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
    for (final index in _controllers.keys.toList()) {
      _disposeController(index);
    }
    super.dispose();
  }
}
