import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'section_availability_api.dart';
import 'section_availability_models.dart';
import 'section_availability_registry.dart';

class SectionAvailabilityState {
  final bool loading;
  final bool initialized;
  final Map<String, SectionAvailabilityEntry> entries;
  final String? error;
  final DateTime? lastSyncedAt;

  const SectionAvailabilityState({
    this.loading = false,
    this.initialized = false,
    this.entries = const <String, SectionAvailabilityEntry>{},
    this.error,
    this.lastSyncedAt,
  });

  SectionAvailabilityEntry entryFor(
    String sectionKey, {
    String? displayName,
  }) {
    return entries[sectionKey.trim().toLowerCase()] ??
        SectionAvailabilityRegistry.getOrDefault(
          sectionKey,
          displayName: displayName,
        );
  }

  SectionAvailabilityState copyWith({
    bool? loading,
    bool? initialized,
    Map<String, SectionAvailabilityEntry>? entries,
    String? error,
    bool clearError = false,
    DateTime? lastSyncedAt,
  }) {
    return SectionAvailabilityState(
      loading: loading ?? this.loading,
      initialized: initialized ?? this.initialized,
      entries: entries ?? this.entries,
      error: clearError ? null : error,
      lastSyncedAt: lastSyncedAt ?? this.lastSyncedAt,
    );
  }
}

final sectionAvailabilityControllerProvider = StateNotifierProvider<
  SectionAvailabilityController,
  SectionAvailabilityState
>((ref) => SectionAvailabilityController(ref));

class SectionAvailabilityController
    extends StateNotifier<SectionAvailabilityState> {
  final Ref ref;

  SectionAvailabilityController(this.ref)
    : super(const SectionAvailabilityState());

  Future<void> bootstrap() => refresh();

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      state = state.copyWith(loading: true, clearError: true);
    }
    try {
      final rows = await ref
          .read(sectionAvailabilityApiProvider)
          .listAvailability();
      final parsed = rows
          .map(SectionAvailabilityEntry.fromJson)
          .toList(growable: false);
      parsed.sort((a, b) {
        final bySort = a.sortOrder.compareTo(b.sortOrder);
        if (bySort != 0) return bySort;
        return a.sectionKey.compareTo(b.sectionKey);
      });
      final mapped = {
        for (final entry in parsed) entry.sectionKey: entry,
      };
      SectionAvailabilityRegistry.replaceAll(parsed);
      state = state.copyWith(
        loading: false,
        initialized: true,
        entries: mapped,
        clearError: true,
        lastSyncedAt: DateTime.now(),
      );
    } catch (error) {
      state = state.copyWith(
        loading: false,
        initialized: true,
        error: '$error',
      );
    }
  }
}
