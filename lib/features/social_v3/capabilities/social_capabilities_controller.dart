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
  }) : _clock = clock,
       super(SocialCapabilities.failClosed);

  final SocialCapabilitiesApi _api;
  final Duration cacheTtl;
  final DateTime Function() _clock;

  DateTime? _fetchedAt;
  bool _inFlight = false;
  int _sessionGeneration = 0;

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
    final generation = _sessionGeneration;
    _inFlight = true;
    try {
      final caps = await _api.fetch();
      if (generation != _sessionGeneration) return;
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
    _sessionGeneration++;
    state = SocialCapabilities.failClosed;
    _fetchedAt = null; // force the next ensureFresh() to refetch
  }

  /// Resets to fail-closed and clears the cache. Used on logout and account
  /// switch so capabilities from a previous session/account are never reused.
  void resetForSession() {
    _sessionGeneration++;
    state = SocialCapabilities.failClosed;
    _fetchedAt = null;
    _inFlight = false;
  }

  /// Reacts to an auth-lifecycle transition (login / logout / account switch /
  /// session restore). Extracted with primitive params so it is unit-testable.
  Future<void> onAuthChanged({
    required bool wasAuthed,
    int? prevUserId,
    required bool isAuthed,
    int? nextUserId,
  }) async {
    if (isAuthed && (!wasAuthed || prevUserId != nextUserId)) {
      // Login or account switch: drop any prior-account state, then fetch.
      resetForSession();
      await ensureFresh();
    } else if (!isAuthed && wasAuthed) {
      // Logout: reset to fail-closed.
      resetForSession();
    }
  }
}

final socialCapabilitiesProvider =
    StateNotifierProvider<SocialCapabilitiesController, SocialCapabilities>((
      ref,
    ) {
      final controller = SocialCapabilitiesController(
        ref.read(socialCapabilitiesApiProvider),
      );
      // Wire to the REAL auth lifecycle: AuthState changes on login, authenticated
      // bootstrap, session restore, token refresh, logout, and account switch.
      ref.listen<AuthState>(authControllerProvider, (previous, next) {
        // Fire-and-forget — never block startup on this request.
        controller.onAuthChanged(
          wasAuthed: previous?.isAuthed == true && previous?.user != null,
          prevUserId: previous?.user?.id,
          isAuthed: next.isAuthed && next.user != null,
          nextUserId: next.user?.id,
        );
      }, fireImmediately: true);
      return controller;
    });
