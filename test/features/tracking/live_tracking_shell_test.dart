import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:maslaki/core/theme/app_theme.dart';
import 'package:maslaki/features/tracking/tracking_map_utils.dart';
import 'package:maslaki/features/tracking/ui/live_tracking_shell.dart';

void main() {
  setUp(() {
    LiveTrackingShell.disableNetworkTilesForTests = true;
  });

  tearDown(() {
    LiveTrackingShell.disableNetworkTilesForTests = false;
  });

  testWidgets('manual map gesture pauses follow until recenter', (
    tester,
  ) async {
    final followChanges = <bool>[];
    final sample = TrackingMotionSample(
      point: const LatLng(33.19302, 44.62071),
      headingDegrees: 15,
      recordedAt: DateTime.utc(2026, 9, 29, 10),
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: LiveTrackingShell(
          title: 'Tracking',
          initialCenter: sample.point,
          trackedSample: sample,
          trackedMarkerBuilder: (_, heading) => const Icon(Icons.local_taxi),
          markers: const [],
          polylines: const [],
          onFollowModeChanged: followChanges.add,
          sheetBuilder: (_, controller) => ListView(
            controller: controller,
            children: const [Text('Details')],
          ),
        ),
      ),
    );
    await tester.pump();

    await tester.drag(find.byType(FlutterMap), const Offset(80, 20));
    await tester.pump();
    expect(followChanges, contains(false));

    await tester.tap(find.byIcon(Icons.my_location_rounded));
    await tester.pump();
    expect(followChanges.last, isTrue);
  });

  testWidgets('rapid samples reuse the map and keep one moving marker', (
    tester,
  ) async {
    TrackingMotionSample sample = TrackingMotionSample(
      point: const LatLng(33.19302, 44.62071),
      headingDegrees: 350,
      recordedAt: DateTime.utc(2026, 9, 29, 10),
    );
    late StateSetter update;

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark(),
        home: StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return LiveTrackingShell(
              title: 'Tracking',
              initialCenter: sample.point,
              trackedSample: sample,
              trackedMarkerBuilder: (_, heading) => Transform.rotate(
                angle: heading,
                child: const Icon(Icons.local_taxi),
              ),
              markers: const [],
              polylines: const [],
              sheetBuilder: (_, controller) => ListView(
                controller: controller,
                children: const [Text('Details')],
              ),
            );
          },
        ),
      ),
    );

    for (var i = 1; i <= 40; i++) {
      update(() {
        sample = TrackingMotionSample(
          point: LatLng(33.19302 + i * 0.00001, 44.62071 + i * 0.00001),
          headingDegrees: (350 + i).toDouble(),
          recordedAt: DateTime.utc(2026, 9, 29, 10, 0, i),
        );
      });
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(
      find.byKey(const ValueKey('live-tracking-moving-marker')),
      findsOneWidget,
    );
  });
}
