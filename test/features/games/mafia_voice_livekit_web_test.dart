import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:livekit_client/livekit_client.dart';

void main() {
  const url = String.fromEnvironment('MAFIA_LIVEKIT_URL');
  const publisherToken = String.fromEnvironment('MAFIA_LIVEKIT_PUBLISHER');
  const subscriberToken = String.fromEnvironment('MAFIA_LIVEKIT_SUBSCRIBER');

  test(
    'web client transports a microphone track through LiveKit',
    () async {
      final publisher = Room();
      final subscriber = Room();
      final listener = subscriber.createListener();
      final audioArrived = Completer<void>();
      listener.on<TrackSubscribedEvent>((event) {
        if (event.track.kind == TrackType.AUDIO && !audioArrived.isCompleted) {
          audioArrived.complete();
        }
      });

      try {
        await subscriber
            .connect(url, subscriberToken)
            .timeout(const Duration(seconds: 20));
        await publisher
            .connect(url, publisherToken)
            .timeout(const Duration(seconds: 20));

        await subscriber.startAudio();
        await publisher.localParticipant!
            .setMicrophoneEnabled(true)
            .timeout(const Duration(seconds: 20));
        await audioArrived.future.timeout(const Duration(seconds: 20));
        expect(
          subscriber.remoteParticipants.values.single.audioTrackPublications,
          isNotEmpty,
        );
      } finally {
        await publisher.localParticipant
            ?.setMicrophoneEnabled(false)
            .timeout(const Duration(seconds: 10));
        await publisher.disconnect();
        await subscriber.disconnect();
        await listener.dispose();
        await publisher.dispose();
        await subscriber.dispose();
      }
    },
    skip: url.isEmpty || publisherToken.isEmpty || subscriberToken.isEmpty,
    timeout: const Timeout(Duration(seconds: 80)),
  );
}
