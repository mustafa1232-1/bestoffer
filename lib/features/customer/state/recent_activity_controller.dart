import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../behavior/data/behavior_api.dart';
import '../models/recent_activity.dart';

final recentActivityControllerProvider =
    StateNotifierProvider<
      RecentActivityController,
      AsyncValue<RecentActivityModel?>
    >((ref) => RecentActivityController(ref));

class RecentActivityController
    extends StateNotifier<AsyncValue<RecentActivityModel?>> {
  final Ref ref;
  bool _loaded = false;
  Future<void>? _inFlight;

  RecentActivityController(this.ref) : super(const AsyncValue.loading());

  Future<void> load({bool force = false}) {
    if (!force && _loaded && state.hasValue) {
      return Future.value();
    }
    if (!force && _inFlight != null) {
      return _inFlight!;
    }

    final future = _performLoad();
    _inFlight = future;
    return future.whenComplete(() {
      if (identical(_inFlight, future)) {
        _inFlight = null;
      }
    });
  }

  Future<void> _performLoad() async {
    if (!state.hasValue) {
      state = const AsyncValue.loading();
    }

    try {
      final page = await ref.read(behaviorApiProvider).myEvents(limit: 60);
      RecentActivityModel? latest;

      for (final item in page.items) {
        final model = RecentActivityModel.fromEvent(item);
        if (model.id > 0) {
          latest = model;
          break;
        }
      }

      _loaded = true;
      state = AsyncValue.data(latest);
    } catch (error, stackTrace) {
      state = AsyncValue.error(error, stackTrace);
    }
  }
}
