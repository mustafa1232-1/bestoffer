// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:connectivity_plus_platform_interface/connectivity_plus_platform_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';
import 'package:maslaki/features/social/state/social_call_voice_controller.dart';

class _OnlineConnectivity extends ConnectivityPlatform {
  @override
  Future<List<ConnectivityResult>> checkConnectivity() async => [
    ConnectivityResult.wifi,
  ];

  @override
  Stream<List<ConnectivityResult>> get onConnectivityChanged =>
      const Stream.empty();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const url = String.fromEnvironment('SOCIAL_LIVEKIT_URL');
  const firstToken = String.fromEnvironment('SOCIAL_LIVEKIT_FIRST');
  const secondToken = String.fromEnvironment('SOCIAL_LIVEKIT_SECOND');

  test(
    'social voice transports RTP in both directions and survives mute cycles',
    () async {
      final originalConnectivity = ConnectivityPlatform.instance;
      ConnectivityPlatform.instance = _OnlineConnectivity();
      final firstRoom = Room();
      final secondRoom = Room();
      final first = SocialCallVoiceController(
        factory: () => LiveKitSocialCallAudio(room: firstRoom),
      );
      final second = SocialCallVoiceController(
        factory: () => LiveKitSocialCallAudio(room: secondRoom),
      );
      void traceRoom(String label, Room room) {
        room.addListener(() {
          debugPrint(
            'social_voice_room: $label state=${room.connectionState.name} '
            'peers=${room.remoteParticipants.length}',
          );
        });
      }

      traceRoom('first', firstRoom);
      traceRoom('second', secondRoom);
      Future<RemoteAudioTrack> waitForTrack(Room room) async {
        final deadline = DateTime.now().add(const Duration(seconds: 25));
        while (DateTime.now().isBefore(deadline)) {
          for (final peer in room.remoteParticipants.values) {
            for (final publication in peer.audioTrackPublications) {
              if (publication.track is RemoteAudioTrack) {
                return publication.track!;
              }
            }
          }
          await Future<void>.delayed(const Duration(milliseconds: 150));
        }
        throw TimeoutException('No remote audio track');
      }

      Future<num> packets(RemoteAudioTrack track) async =>
          (await track.getReceiverStats())?.packetsReceived ?? 0;
      Future<void> waitUntil(bool Function() condition, String message) async {
        final deadline = DateTime.now().add(const Duration(seconds: 5));
        while (!condition() && DateTime.now().isBefore(deadline)) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        if (!condition()) throw TimeoutException(message);
      }

      try {
        debugPrint('social_voice_stage: connecting_first');
        await first.connect(() async => {'url': url, 'token': firstToken});
        debugPrint('social_voice_stage: connecting_second');
        await second.connect(() async => {'url': url, 'token': secondToken});
        debugPrint('social_voice_stage: waiting_tracks');
        final firstRemote = await waitForTrack(firstRoom);
        final secondRemote = await waitForTrack(secondRoom);
        final initialA = await packets(firstRemote);
        final initialB = await packets(secondRemote);
        await Future<void>.delayed(const Duration(seconds: 3));
        final receivedA = await packets(firstRemote);
        final receivedB = await packets(secondRemote);
        expect(receivedA, greaterThan(initialA));
        expect(receivedB, greaterThan(initialB));
        await Future.wait([first.setMuted(true), second.setMuted(true)]);
        expect(first.muted, isTrue);
        expect(second.muted, isTrue);
        await waitUntil(
          () =>
              !firstRoom.localParticipant!.isMicrophoneEnabled() &&
              !secondRoom.localParticipant!.isMicrophoneEnabled(),
          'Microphones did not mute',
        );
        await Future.wait([first.setMuted(false), second.setMuted(false)]);
        await waitUntil(
          () =>
              firstRoom.localParticipant!.isMicrophoneEnabled() &&
              secondRoom.localParticipant!.isMicrophoneEnabled(),
          'Microphones did not resume',
        );
        await Future<void>.delayed(const Duration(seconds: 3));
        expect(await packets(firstRemote), greaterThan(receivedA));
        expect(await packets(secondRemote), greaterThan(receivedB));
        // Only measurements, never provider credentials, enter the test log.
        debugPrint(
          'social_voice_rtp: first=$receivedA second=$receivedB mute_cycles=1',
        );
      } finally {
        await first.disconnect();
        await second.disconnect();
        first.dispose();
        second.dispose();
        ConnectivityPlatform.instance = originalConnectivity;
      }
    },
    skip: url.isEmpty || firstToken.isEmpty || secondToken.isEmpty,
    timeout: const Timeout(Duration(seconds: 100)),
  );
}
