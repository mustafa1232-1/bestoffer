import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/media/cached_app_image.dart';

void main() {
  testWidgets('empty image URL renders a graceful error widget, no red screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 120,
            child: CachedAppImage(imageUrl: '   '),
          ),
        ),
      ),
    );
    await tester.pump();

    // No exception (no red error screen) and the broken-image fallback shows.
    expect(tester.takeException(), isNull);
    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
  });

  testWidgets('custom errorWidget is honored for empty URLs', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 120,
            height: 120,
            child: CachedAppImage(
              imageUrl: '',
              errorWidget: (context, url, error) =>
                  const Text('media-unavailable'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('media-unavailable'), findsOneWidget);
  });
}
