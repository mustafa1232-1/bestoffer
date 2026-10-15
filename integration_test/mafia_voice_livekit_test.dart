import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:livekit_client/livekit_client.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const url = String.fromEnvironment('MAFIA_LIVEKIT_URL');
  const publisherToken = String.fromEnvironment('MAFIA_LIVEKIT_PUBLISHER');
  const subscriberToken = String.fromEnvironment('MAFIA_LIVEKIT_SUBSCRIBER');

  testWidgets(
    'Mafia LiveKit room carries a microphone track between two participants',
    (tester) async {
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
        await subscriber.connect(url, subscriberToken);
        await publisher.connect(url, publisherToken);
        await publisher.localParticipant!.setMicrophoneEnabled(true);
        await audioArrived.future.timeout(const Duration(seconds: 20));

        expect(subscriber.remoteParticipants, hasLength(1));
        expect(
          subscriber.remoteParticipants.values.single.audioTrackPublications,
          isNotEmpty,
        );
      } finally {
        await publisher.localParticipant?.setMicrophoneEnabled(false);
        await publisher.disconnect();
        await subscriber.disconnect();
        await listener.dispose();
        await publisher.dispose();
        await subscriber.dispose();
      }
    },
    skip: url.isEmpty || publisherToken.isEmpty || subscriberToken.isEmpty,
  );
}
