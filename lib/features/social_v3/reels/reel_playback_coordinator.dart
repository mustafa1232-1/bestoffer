import 'package:flutter/foundation.dart';
import 'package:video_player/video_player.dart';

import '../media/social_media_presentation.dart';

/// Owns the [VideoPlayerController]s for the reels viewer and enforces the §3
/// playback rules:
///  * At most one controller plays at a time.
///  * Only {previous, active, next} controllers are retained; distant ones are
///    disposed to bound memory.
///  * Mute preference is preserved across page changes.
///  * Audio stops immediately when the route is hidden or the app is inactive.
///  * The active controller is NOT recreated just because likes/comments change
///    (the coordinator is keyed by index + playback URL, not by post state).
///
/// A [controllerFactory] seam lets tests inject fakes; production uses
/// [VideoPlayerController.networkUrl].
class ReelPlaybackCoordinator extends ChangeNotifier {
  ReelPlaybackCoordinator({
    VideoPlayerController Function(String url)? controllerFactory,
  }) : _factory = controllerFactory ??
            ((url) => VideoPlayerController.networkUrl(Uri.parse(url)));

  final VideoPlayerController Function(String url) _factory;

  final Map<int, VideoPlayerController> _controllers = {};
  final Map<int, String> _controllerUrls = {};
  final Set<int> _failed = {};

  List<SocialMediaPresentation> _items = const [];
  int _activeIndex = 0;
  bool _muted = false;
  bool _userPaused = false;
  bool _routeVisible = true;
  bool _appActive = true;
  bool _disposed = false;

  int get activeIndex => _activeIndex;
  bool get isMuted => _muted;
  bool get isActivePaused => _userPaused;

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
    _reconcileWindow();
  }

  /// Called when the visible page settles on [index].
  Future<void> setActiveIndex(int index) async {
    if (_disposed) return;
    if (index == _activeIndex && _controllers.containsKey(index)) {
      // Re-assert play state without tearing anything down.
      _userPaused = false;
      _applyPlayState();
      return;
    }
    _activeIndex = index;
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

  /// Route visibility (e.g. pushed a comments route on top or left the tab).
  void setRouteVisible(bool visible) {
    if (_routeVisible == visible) return;
    _routeVisible = visible;
    _applyPlayState();
  }

  /// App lifecycle (resumed vs inactive/paused).
  void setAppActive(bool active) {
    if (_appActive == active) return;
    _appActive = active;
    _applyPlayState();
  }

  bool get _shouldPlayActive =>
      _routeVisible && _appActive && !_userPaused;

  void _applyPlayState() {
    for (final entry in _controllers.entries) {
      final isActive = entry.key == _activeIndex;
      final c = entry.value;
      if (!c.value.isInitialized) continue;
      if (isActive && _shouldPlayActive) {
        c.setVolume(_muted ? 0 : 1);
        if (!c.value.isPlaying) c.play();
      } else {
        if (c.value.isPlaying) c.pause();
      }
    }
  }

  void _reconcileWindow() {
    if (_disposed) return;
    final keep = <int>{
      _activeIndex - 1,
      _activeIndex,
      _activeIndex + 1,
    }.where((i) => i >= 0 && i < _items.length).toSet();

    // Dispose controllers outside the window.
    for (final index in _controllers.keys.toList()) {
      if (!keep.contains(index)) {
        _disposeController(index);
      }
    }

    // Ensure controllers inside the window exist.
    for (final index in keep) {
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
    final controller = _factory(url);
    _controllers[index] = controller;
    _controllerUrls[index] = url;
    controller.addListener(_onControllerTick);
    controller.setLooping(false);
    controller.initialize().then((_) {
      if (_disposed || _controllers[index] != controller) return;
      controller.setVolume(_muted ? 0 : 1);
      _applyPlayState();
      notifyListeners();
    }).catchError((Object error) {
      if (_disposed) return;
      _failed.add(index);
      notifyListeners();
    });
  }

  void _onControllerTick() {
    if (_disposed) return;
    // Buffering state changes drive the surface spinner.
    notifyListeners();
  }

  void _disposeController(int index) {
    final controller = _controllers.remove(index);
    _controllerUrls.remove(index);
    if (controller != null) {
      controller.removeListener(_onControllerTick);
      controller.pause();
      controller.dispose();
    }
  }

  /// Retry a controller that failed to initialize (§3 "retry controlled
  /// network failures").
  void retry(int index) {
    if (index < 0 || index >= _items.length) return;
    final media = _items[index];
    if (!media.hasVideo) return;
    _disposeController(index);
    _createController(index, media.videoPlaybackUrl!);
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
