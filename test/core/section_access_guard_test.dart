import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:maslaki/core/sections/section_access_guard.dart';
import 'package:maslaki/core/sections/section_availability_controller.dart';
import 'package:maslaki/core/sections/section_availability_models.dart';
import 'package:maslaki/core/sections/section_availability_registry.dart';

SectionAvailabilityEntry _entry(SectionAvailabilityStatus status) {
  return SectionAvailabilityEntry(
    id: 1,
    sectionKey: AppSectionKeys.taxi,
    displayName: 'Taxi',
    parentSectionKey: null,
    surfaceScope: 'user',
    status: status,
    isVisible: true,
    userMessage: status == SectionAvailabilityStatus.open ? null : 'Closed',
    sortOrder: 20,
    allowExistingActiveAccess: true,
    metadata: const <String, dynamic>{},
    updatedAt: null,
  );
}

class _RefreshingAvailabilityController extends SectionAvailabilityController {
  _RefreshingAvailabilityController(super.ref) {
    final closed = _entry(SectionAvailabilityStatus.temporarilyClosed);
    SectionAvailabilityRegistry.replaceAll([closed]);
    state = SectionAvailabilityState(
      initialized: true,
      entries: {closed.sectionKey: closed},
      lastSyncedAt: DateTime.now(),
    );
  }

  int refreshCalls = 0;

  @override
  Future<void> refresh({bool silent = false}) async {
    refreshCalls += 1;
    final open = _entry(SectionAvailabilityStatus.open);
    SectionAvailabilityRegistry.replaceAll([open]);
    state = SectionAvailabilityState(
      initialized: true,
      entries: {open.sectionKey: open},
      lastSyncedAt: DateTime.now(),
    );
  }
}

void main() {
  testWidgets('closed cached section refreshes before showing unavailable UI', (
    tester,
  ) async {
    late _RefreshingAvailabilityController controller;
    var allowed = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sectionAvailabilityControllerProvider.overrideWith((ref) {
            controller = _RefreshingAvailabilityController(ref);
            return controller;
          }),
        ],
        child: MaterialApp(
          home: Consumer(
            builder: (context, ref, _) => Scaffold(
              body: ElevatedButton(
                onPressed: () async {
                  allowed = await guardSectionAccess(
                    context,
                    ref,
                    sectionKey: AppSectionKeys.taxi,
                    displayName: 'Taxi',
                  );
                },
                child: const Text('Open taxi'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Open taxi'));
    await tester.pumpAndSettle();

    expect(controller.refreshCalls, 1);
    expect(allowed, isTrue);
    expect(find.text('Closed'), findsNothing);
  });
}
