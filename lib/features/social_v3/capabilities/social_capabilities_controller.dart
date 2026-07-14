import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';
import 'social_capabilities.dart';
import 'social_capabilities_api.dart';

final socialCapabilitiesApiProvider = Provider<SocialCapabilitiesApi>((ref) {
  return SocialCapabilitiesApi(ref.read(dioClientProvider).dio);
});

/// Holds the current social capabilities with a short bounded cache. Defaults
/// fail-closed and can be forced back to fail-closed after a
/// `STORY_AUDIENCE_SCOPE_NOT_AVAILABLE` server response.
class SocialCapabilitiesController extends StateNotifier<SocialCapabilities> {
  SocialCapabilitiesController(
    this._api, {
    this.cacheTtl = const Duration(minutes: 5),
    DateTime Function() clock = DateTime.now,
  })  : _clock = clock,
        super(SocialCapabilities.failClosed);

  final SocialCapabilitiesApi _api;
  final Duration cacheTtl;
  final DateTime Function() _clock;

  DateTime? _fetchedAt;
  bool _inFlight = false;

  bool get _isStale {
    final at = _fetchedAt;
    if (at == null) return true;
    return _clock().difference(at) >= cacheTtl;
  }

  /// Fetch only if the cache is stale (bootstrap / login / session restore).
  Future<void> ensureFresh() async {
    if (!_isStale) return;
    await refresh();
  }

  /// Force a fetch (explicit refresh).
  Future<void> refresh() async {
    if (_inFlight) return;
    _inFlight = true;
    try {
      final caps = await _api.fetch();
      state = caps;
      _fetchedAt = _clock();
    } finally {
      _inFlight = false;
    }
  }

  /// Called after the backend returns STORY_AUDIENCE_SCOPE_NOT_AVAILABLE: a
  /// stale "supported=true" cache must immediately drop to fail-closed, then a
  /// refresh confirms the authoritative state.
  void markStoryScopeUnsupported() {
    state = SocialCapabilities.failClosed;
    _fetchedAt = null; // force the next ensureFresh() to refetch
  }
}

final socialCapabilitiesProvider =
    StateNotifierProvider<SocialCapabilitiesController, SocialCapabilities>(
  (ref) => SocialCapabilitiesController(
    ref.read(socialCapabilitiesApiProvider),
  ),
);
