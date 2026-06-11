import 'dart:io';

import 'package:maslaki/features/social/ui/widgets/social_voice_composer_controller.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeRecorderDriver implements SocialVoiceRecorderDriver {
  String? startedPath;
  String? stopPath;
  bool disposed = false;
  bool started = false;

  @override
  Future<void> start(String path) async {
    started = true;
    startedPath = path;
  }

  @override
  Future<String?> stop() async => stopPath ?? startedPath;

  @override
  Future<void> dispose() async {
    disposed = true;
  }
}

void main() {
  test('voice composer moves from hold to locked preview and sends draft', () async {
    final tempDir = await Directory.systemTemp.createTemp('voice_composer_test');
    final recorder = _FakeRecorderDriver();
    DateTime now = DateTime(2026, 4, 9, 12, 0, 0);
    final deletedPaths = <String>[];
    final controller = SocialVoiceComposerController(
      recorder: recorder,
      requestPermission: () async => true,
      tempDirProvider: () async => tempDir,
      deleteFile: (path) async {
        deletedPaths.add(path);
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      },
      now: () => now,
    );

    final started = await controller.startHolding(draftKey: 'thread_9_voice');
    expect(started.type, SocialVoiceComposerResultType.started);
    expect(controller.state.phase, SocialVoiceComposerPhase.holding);

    final lockResult = controller.lock();
    expect(lockResult.type, SocialVoiceComposerResultType.locked);
    expect(controller.state.phase, SocialVoiceComposerPhase.locked);

    now = now.add(const Duration(seconds: 4));
    final path = '${tempDir.path}${Platform.pathSeparator}voice.m4a';
    await File(path).writeAsBytes(const <int>[1, 2, 3, 4]);
    recorder.stopPath = path;

    final preview = await controller.stopLockedRecordingToPreview();
    expect(preview.type, SocialVoiceComposerResultType.previewReady);
    expect(controller.state.phase, SocialVoiceComposerPhase.preview);
    expect(controller.draft, isNotNull);
    expect(controller.draft!.duration.inSeconds, 4);

    SocialVoiceRecordingDraft? sentDraft;
    final sent = await controller.sendDraft((draft) async {
      sentDraft = draft;
    });
    expect(sent.type, SocialVoiceComposerResultType.sent);
    expect(sentDraft, isNotNull);
    expect(sentDraft!.duration.inSeconds, 4);
    expect(controller.state.phase, SocialVoiceComposerPhase.idle);
    expect(deletedPaths, contains(path));

    controller.dispose();
    await tempDir.delete(recursive: true);
  });

  test('voice composer rejects too short recordings', () async {
    final tempDir = await Directory.systemTemp.createTemp('voice_composer_short');
    final recorder = _FakeRecorderDriver();
    DateTime now = DateTime(2026, 4, 9, 12, 0, 0);
    final deletedPaths = <String>[];
    final controller = SocialVoiceComposerController(
      recorder: recorder,
      requestPermission: () async => true,
      tempDirProvider: () async => tempDir,
      deleteFile: (path) async {
        deletedPaths.add(path);
        final file = File(path);
        if (await file.exists()) {
          await file.delete();
        }
      },
      now: () => now,
    );

    await controller.startHolding(draftKey: 'thread_short_voice');
    now = now.add(const Duration(milliseconds: 600));
    final path = '${tempDir.path}${Platform.pathSeparator}short.m4a';
    await File(path).writeAsBytes(const <int>[7, 8, 9]);
    recorder.stopPath = path;

    final result = await controller.releaseHoldToPreview();
    expect(result.type, SocialVoiceComposerResultType.tooShort);
    expect(controller.state.phase, SocialVoiceComposerPhase.idle);
    expect(deletedPaths, contains(path));

    controller.dispose();
    await tempDir.delete(recursive: true);
  });

  test('voice composer reports permission denial before starting', () async {
    final controller = SocialVoiceComposerController(
      recorder: _FakeRecorderDriver(),
      requestPermission: () async => false,
    );

    final result = await controller.startHolding(draftKey: 'thread_denied_voice');
    expect(result.type, SocialVoiceComposerResultType.permissionDenied);
    expect(controller.state.phase, SocialVoiceComposerPhase.idle);

    controller.dispose();
  });
}
