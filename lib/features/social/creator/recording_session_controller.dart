import 'dart:async';

import 'package:flutter/foundation.dart';

class RecordingSessionController extends ChangeNotifier {
  Timer? _timer;
  Duration _elapsed = Duration.zero;
  bool _recording = false;

  Duration get elapsed => _elapsed;
  bool get isRecording => _recording;

  void start({required void Function() onTick}) {
    _timer?.cancel();
    _elapsed = Duration.zero;
    _recording = true;
    notifyListeners();
    _timer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      _elapsed += const Duration(milliseconds: 100);
      onTick();
      notifyListeners();
    });
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
    _recording = false;
    notifyListeners();
  }

  void reset() {
    _timer?.cancel();
    _timer = null;
    _elapsed = Duration.zero;
    _recording = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
