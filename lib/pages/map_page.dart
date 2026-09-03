import 'dart:math' as math;
import 'dart:async';

import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/core/auth/auth_guard.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/data/taxi_route_service.dart';
import 'package:maslaki/features/taxi/domain/taxi_assignment_contract.dart';
import 'package:maslaki/features/taxi/domain/taxi_fare_policy.dart';
import 'package:maslaki/features/taxi/ui/taxi_cancel_reason_sheet.dart';
import 'package:maslaki/features/taxi/ui/taxi_share_ride_friends_sheet.dart';
import 'package:maslaki/features/tracking/ui/taxi_live_tracking_screen.dart';
import 'package:maslaki/core/forms/form_error_banner.dart';
import 'package:maslaki/core/forms/form_field_error_resolver.dart';
import 'package:maslaki/core/forms/form_scroll_coordinator.dart';
import 'package:maslaki/core/i18n/app_localizations_context.dart';
import 'package:maslaki/core/i18n/locale_text.dart';
import 'package:maslaki/core/network/api_error_mapper.dart';
import 'package:maslaki/core/network/session_invalidation.dart';
import 'package:maslaki/core/sections/section_availability_controller.dart';
import 'package:maslaki/core/sections/section_availability_models.dart';
import 'package:maslaki/core/sections/section_unavailable_screen.dart';
import 'package:core_maps/core_maps.dart';
import 'package:maslaki/core/utils/currency.dart';
import 'package:maslaki/core/utils/parsers.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'package:maslaki/core/media/cached_app_image.dart';
import 'package:maslaki/core/widgets/maslaki_user_drawer.dart';

enum _PointSelectionMode { pickup, dropoff }

enum _RideRequestTimingMode { now, scheduled }

enum TaxiRequestStep {
  timing,
  pickupSearch,
  pickupConfirm,
  dropoffSearch,
  dropoffConfirm,
  summaryAndSubmit,
}

enum TaxiSheetStage { collapsed, half, expanded }

final taxiRouteServiceProvider = Provider<TaxiRouteService>((ref) {
  return TaxiRouteService();
});

class MapPage extends ConsumerStatefulWidget {
  final Map<String, dynamic>? initialPickupSnapshot;
  final Map<String, dynamic>? initialDropoffSnapshot;
  final String? initialCouponCode;
  final int? initialFareIqd;
  final DateTime? initialScheduledFor;
  final bool skipInitialBootstrap;

  const MapPage({
    super.key,
    this.initialPickupSnapshot,
    this.initialDropoffSnapshot,
    this.initialCouponCode,
    this.initialFareIqd,
    this.initialScheduledFor,
    this.skipInitialBootstrap = false,
  });

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> with WidgetsBindingObserver {
  static const LatLng _bismayahCenter = LatLng(33.3128, 44.3615);
  static const String _iraqViewbox = '38.79,37.39,48.58,29.06';
  static const double _initialZoom = 15;
  static const double _collapsedSheetExtent = 0.18;
  static const double _halfSheetExtent = 0.46;
  static const double _expandedSheetExtent = 0.88;

  final MapController _mapController = MapController();
  final DraggableScrollableController _requestSheetController =
      DraggableScrollableController();
  final TextEditingController _pickupLabelController = TextEditingController();
  final TextEditingController _dropoffLabelController = TextEditingController();
  final TextEditingController _pickupSearchController = TextEditingController();
  final TextEditingController _dropoffSearchController =
      TextEditingController();
  final TextEditingController _fareController = TextEditingController();
  final TextEditingController _noteController = TextEditingController();
  final TextEditingController _couponCodeController = TextEditingController();
  final FormScrollCoordinator _rideComposerScroll = FormScrollCoordinator();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late final TaxiApi _taxiApi;
  late final TaxiRouteService _routeService;
  late final Dio _placeSearchDio;

  StreamSubscription<TaxiLiveEvent>? _streamSub;
  Timer? _reconnectTimer;
  Timer? _uiTickTimer;
  Timer? _nearbyCaptainsTimer;
  Timer? _captainAnimationTimer;
  Timer? _pickupSearchDebounce;
  Timer? _dropoffSearchDebounce;
  Timer? _sheetDragSettleTimer;

  _PointSelectionMode _selectionMode = _PointSelectionMode.pickup;
  _RideRequestTimingMode _timingMode = _RideRequestTimingMode.now;
  LatLng? _pickupPoint;
  LatLng? _dropoffPoint;
  LatLng? _captainPoint;
  LatLng? _myLocation;
  double? _captainHeadingDeg;

  Map<String, dynamic>? _activeRideEnvelope;
  bool _loading = true;
  bool _submitting = false;
  bool _isLocating = false;
  bool _isSearchingPickup = false;
  bool _isSearchingDropoff = false;
  bool _pickupConfirmed = false;
  bool _streamConnected = false;
  bool _canUseTaxiApi = true;
  bool _routeLoading = false;
  // ignore: unused_field
  DateTime? _lastRealtimeAt;
  DateTime? _lastRouteAt;
  DateTime? _lastSilentRefreshAt;
  int? _lastEventId;
  int? _openedLiveTrackingRideId;
  int _reconnectAttempt = 0;
  String? _error;
  String? _rideFormError;
  final Map<String, String> _rideFieldErrors = <String, String>{};
  final List<Map<String, dynamic>> _savedPlaces = <Map<String, dynamic>>[];
  final List<Map<String, dynamic>> _favoriteTrips = <Map<String, dynamic>>[];
  List<_PlaceSuggestion> _pickupSuggestions = const [];
  List<_PlaceSuggestion> _dropoffSuggestions = const [];
  List<LatLng> _routePoints = const [];
  LatLng? _lastRouteFrom;
  LatLng? _lastRouteTo;
  String? _lastAppliedPickupDefaultLabel;
  double? _routeDistanceMeters;
  int? _routeDurationSeconds;
  DateTime? _scheduledFor;
  bool _loadingQuickOptions = false;
  bool _initialIntentApplied = false;
  bool _loadingNearbyCaptains = false;
  bool _sheetProgrammaticMotion = false;
  bool _sheetDragInProgress = false;
  bool _keyboardVisible = false;
  TaxiRequestStep _requestStep = TaxiRequestStep.pickupSearch;
  TaxiSheetStage _sheetStage = TaxiSheetStage.half;
  TaxiSheetStage? _sheetStageBeforeKeyboard;
  double _lastSheetExtent = _halfSheetExtent;
  final List<Map<String, dynamic>> _nearbyCaptainMarkers =
      <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _taxiApi = ref.read(taxiApiProvider);
    _routeService = ref.read(taxiRouteServiceProvider);
    _placeSearchDio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 8),
        receiveTimeout: const Duration(seconds: 8),
        headers: {
          'User-Agent': 'MaslakiTaxi/1.0 (support@maslaki.app)',
          'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.8',
        },
      ),
    );
    if (widget.skipInitialBootstrap) {
      _loading = false;
    }
    _fareController.addListener(_handleFareChanged);
    _uiTickTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final rideStatus = _string(_ride?['status']);
      if (rideStatus == 'searching' && _currentBid != null) {
        setState(() {});
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap(backgroundOnly: widget.skipInitialBootstrap);
    });
  }

  String _t(String ar, String en) => context.lt(ar: ar, en: en);

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted || _activeRideEnvelope != null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _activeRideEnvelope != null) return;
      final keyboardVisible = MediaQuery.viewInsetsOf(context).bottom > 0;
      if (keyboardVisible == _keyboardVisible) return;
      _keyboardVisible = keyboardVisible;
      if (keyboardVisible) {
        _sheetStageBeforeKeyboard ??= _sheetStage;
        unawaited(_setSheetStage(TaxiSheetStage.expanded));
        return;
      }
      final restoreStage = _sheetStageBeforeKeyboard;
      _sheetStageBeforeKeyboard = null;
      if (restoreStage != null) {
        unawaited(_setSheetStage(restoreStage));
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!mounted || !_canUseTaxiApi) return;
    if (state != AppLifecycleState.resumed) return;
    _reconnectTimer?.cancel();
    _connectRealtimeStream();
    unawaited(_loadCurrentRide(silent: true));
    if (_activeRideEnvelope == null) {
      unawaited(_loadNearbyCaptains());
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final defaultLabel = context.l10n.mapPageCurrentLocation;
    final currentText = _pickupLabelController.text.trim();
    final canApplyDefault =
        currentText.isEmpty ||
        (_lastAppliedPickupDefaultLabel != null &&
            currentText == _lastAppliedPickupDefaultLabel);
    if (!canApplyDefault) return;
    _pickupLabelController.text = defaultLabel;
    _lastAppliedPickupDefaultLabel = defaultLabel;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _streamSub?.cancel();
    _reconnectTimer?.cancel();
    _uiTickTimer?.cancel();
    _nearbyCaptainsTimer?.cancel();
    _captainAnimationTimer?.cancel();
    _pickupSearchDebounce?.cancel();
    _dropoffSearchDebounce?.cancel();
    _sheetDragSettleTimer?.cancel();
    _requestSheetController.dispose();
    _pickupLabelController.dispose();
    _dropoffLabelController.dispose();
    _pickupSearchController.dispose();
    _dropoffSearchController.dispose();
    _fareController.removeListener(_handleFareChanged);
    _fareController.dispose();
    _noteController.dispose();
    _couponCodeController.dispose();
    _rideComposerScroll.dispose();
    _placeSearchDio.close(force: true);
    super.dispose();
  }

  void _handleFareChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _bootstrap({bool backgroundOnly = false}) async {
    if (!mounted) return;
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed) {
      await requireAuthBeforeAction(
        context,
        featureArabic: 'خدمة التكسي',
        featureEnglish: 'taxi booking',
      );
      if (mounted) {
        Navigator.of(context).maybePop();
      }
      return;
    }
    if (auth.isBackoffice || auth.isOwner || auth.isDelivery) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _canUseTaxiApi = false;
        _error = context.l10n.mapPageCustomerOnly;
      });
      return;
    }

    await Future.wait([
      _goToMyLocation(setAsPickupIfEmpty: true),
      _loadCurrentRide(silent: backgroundOnly),
    ]);
    if (!mounted) return;
    _applyInitialIntentIfNeeded();
    unawaited(_loadQuickOptions(force: true));
    _syncRequestStepFromState();
    _startNearbyCaptainsPolling();
    if (_canUseTaxiApi) _connectRealtimeStream();
  }

  Future<void> _loadCurrentRide({bool silent = false}) async {
    final hadRideBeforeRefresh = taxiRideViewFromEnvelope(_activeRideEnvelope);
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final envelope = await _taxiApi.getCurrentRideForCustomer();
      if (!mounted) return;

      final ride = taxiRideViewFromEnvelope(envelope);
      final rideStatus = _string(ride?['status'])?.toLowerCase();
      final isTerminalRide = _isTerminalTaxiRideStatus(rideStatus);
      final shouldResetComposer =
          isTerminalRide || (envelope == null && hadRideBeforeRefresh != null);

      if (shouldResetComposer) {
        _resetRideComposerState();
      }

      _activeRideEnvelope = shouldResetComposer ? null : envelope;
      _syncMapFromRideEnvelope();

      setState(() {
        _loading = false;
        _error = null;
      });
      if (!shouldResetComposer) {
        _maybeOpenLiveTrackingFromEnvelope(envelope);
      }
    } on DioException catch (e) {
      if (!mounted) return;
      final unauthorized = isTerminalAuthError(e);
      if (unauthorized) {
        _canUseTaxiApi = false;
        _streamSub?.cancel();
      }
      setState(() {
        _loading = false;
        _error = unauthorized
            ? context.l10n.mapPageSessionExpired
            : _extractApiError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.mapPageCurrentRideLoadFailed;
      });
    }
  }

  void _resetRideComposerState() {
    _pickupPoint = null;
    _dropoffPoint = null;
    _pickupConfirmed = false;
    _selectionMode = _PointSelectionMode.pickup;
    _requestStep = TaxiRequestStep.pickupSearch;
    _captainPoint = null;
    _captainHeadingDeg = null;
    _routePoints = const [];
    _lastRouteFrom = null;
    _lastRouteTo = null;
    _lastRouteAt = null;
    _openedLiveTrackingRideId = null;
    _nearbyCaptainMarkers.clear();
    _rideFieldErrors.clear();
    _rideFormError = null;
    _timingMode = _RideRequestTimingMode.now;
    _scheduledFor = null;
    _fareController.clear();
    _noteController.clear();
    _couponCodeController.clear();
    _pickupSearchController.clear();
    _dropoffSearchController.clear();
    _pickupLabelController.clear();
    _dropoffLabelController.clear();
    _lastAppliedPickupDefaultLabel = null;
    _sheetStage = TaxiSheetStage.half;
    _sheetStageBeforeKeyboard = null;
    _keyboardVisible = false;
    _sheetProgrammaticMotion = false;
    _sheetDragInProgress = false;
    _routeLoading = false;
    _isSearchingPickup = false;
    _isSearchingDropoff = false;
  }

  void _syncMapFromRideEnvelope() {
    final ride = _ride;
    if (ride == null) {
      _openedLiveTrackingRideId = null;
      _captainPoint = null;
      _captainHeadingDeg = null;
      _routePoints = const [];
      _lastRouteFrom = null;
      _lastRouteTo = null;
      _lastRouteAt = null;
      _syncRequestStepFromState();
      _startNearbyCaptainsPolling();
      return;
    }

    final pickup = _latLngFromMap(ride['pickup']);
    final dropoff = _latLngFromMap(ride['dropoff']);
    final latestRaw = _activeRideEnvelope?['latestLocation'];
    final latest = _latLngFromMap(latestRaw);

    if (pickup != null) {
      _pickupPoint = pickup;
      if (_pickupLabelController.text.trim().isEmpty) {
        _pickupLabelController.text =
            _string(ride['pickup']?['label']) ??
            context.l10n.mapPagePickupPoint;
      }
    }

    if (dropoff != null) {
      _dropoffPoint = dropoff;
      if (_dropoffLabelController.text.trim().isEmpty) {
        _dropoffLabelController.text =
            _string(ride['dropoff']?['label']) ??
            context.l10n.mapPageDropoffPoint;
      }
    }

    final latestHeading = latestRaw is Map
        ? _readDouble(latestRaw['headingDeg'])
        : null;
    if (latest != null) {
      _animateCaptainPointTo(latest, headingDeg: latestHeading);
    }
    _nearbyCaptainMarkers.clear();
    _requestStep = TaxiRequestStep.summaryAndSubmit;

    final target = _captainPoint ?? _pickupPoint ?? _dropoffPoint;
    if (target != null) {
      _mapController.move(target, 15.8);
    }

    _refreshRoutePolyline();
  }

  bool _shouldOpenLiveTrackingForStatus(String? status) {
    return status == 'captain_assigned' ||
        status == 'captain_arriving' ||
        status == 'ride_started';
  }

  void _maybeOpenLiveTrackingFromEnvelope(Map<String, dynamic>? envelope) {
    if (!mounted || envelope == null) return;
    final ride = taxiRideViewFromEnvelope(envelope);
    if (ride == null) {
      _openedLiveTrackingRideId = null;
      return;
    }
    final rideId = _readInt(ride['id']);
    final status = _string(ride['status']);
    if (rideId == null || !_shouldOpenLiveTrackingForStatus(status)) {
      _openedLiveTrackingRideId = null;
      return;
    }
    if (_openedLiveTrackingRideId == rideId) return;
    _openedLiveTrackingRideId = rideId;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) =>
              TaxiLiveTrackingScreen(rideId: rideId, initialEnvelope: envelope),
        ),
      );
    });
  }

  Future<void> _loadQuickOptions({bool force = false}) async {
    if (_loadingQuickOptions) return;
    if (!force && (_savedPlaces.isNotEmpty || _favoriteTrips.isNotEmpty)) {
      return;
    }
    _loadingQuickOptions = true;
    try {
      final responses = await Future.wait<dynamic>([
        _taxiApi.listSavedPlaces(),
        _taxiApi.listFavoriteTrips(),
      ]);
      if (!mounted) return;
      setState(() {
        _savedPlaces
          ..clear()
          ..addAll(
            List<Map<String, dynamic>>.from(
              (responses[0] as List).whereType<Map>().map(
                (item) => Map<String, dynamic>.from(item),
              ),
            ),
          );
        _favoriteTrips
          ..clear()
          ..addAll(
            List<Map<String, dynamic>>.from(
              (responses[1] as List).whereType<Map>().map(
                (item) => Map<String, dynamic>.from(item),
              ),
            ),
          );
      });
    } catch (_) {
      // Quick options are optional helpers and must not block the taxi flow.
    } finally {
      _loadingQuickOptions = false;
    }
  }

  void _syncRequestStepFromState() {
    if (_activeRideEnvelope != null) return;
    if (_pickupPoint == null) {
      _requestStep = TaxiRequestStep.pickupSearch;
      return;
    }
    if (!_pickupConfirmed) {
      _requestStep = TaxiRequestStep.pickupConfirm;
      return;
    }
    if (_dropoffPoint == null) {
      _requestStep = TaxiRequestStep.dropoffSearch;
      return;
    }
    _requestStep = TaxiRequestStep.summaryAndSubmit;
  }

  void _startNearbyCaptainsPolling() {
    _nearbyCaptainsTimer?.cancel();
    if (!_canUseTaxiApi) return;
    _nearbyCaptainsTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (!mounted) return;
      if (_activeRideEnvelope != null) return;
      unawaited(_loadNearbyCaptains());
    });
    unawaited(_loadNearbyCaptains());
  }

  Future<void> _loadNearbyCaptains() async {
    if (_loadingNearbyCaptains ||
        !_canUseTaxiApi ||
        _activeRideEnvelope != null) {
      return;
    }
    final center = _myLocation ?? _pickupPoint ?? _dropoffPoint;
    if (center == null) return;
    _loadingNearbyCaptains = true;
    try {
      final items = await _taxiApi.listNearbyCaptains(
        latitude: center.latitude,
        longitude: center.longitude,
        radiusM: 15000,
        limit: 100,
      );
      if (!mounted) return;
      setState(() {
        _nearbyCaptainMarkers
          ..clear()
          ..addAll(items);
      });
    } catch (_) {
      // Non-blocking helper layer; silence errors.
    } finally {
      _loadingNearbyCaptains = false;
    }
  }

  void _applySnapshot({
    required Map<String, dynamic> snapshot,
    required bool forPickup,
    bool confirmPickup = false,
  }) {
    final point = _latLngFromMap(snapshot);
    if (point == null) return;
    final label =
        _string(snapshot['label']) ??
        _string(snapshot['addressText']) ??
        (forPickup
            ? context.l10n.mapPagePickupPoint
            : context.l10n.mapPageDropoffPoint);

    setState(() {
      if (forPickup) {
        _pickupPoint = point;
        _pickupLabelController.text = label;
        _pickupSearchController.text = label;
        _pickupSuggestions = const [];
        _pickupConfirmed = confirmPickup || _pickupConfirmed;
        _selectionMode = _pickupConfirmed
            ? _PointSelectionMode.dropoff
            : _PointSelectionMode.pickup;
        _requestStep = _pickupConfirmed
            ? TaxiRequestStep.dropoffSearch
            : TaxiRequestStep.pickupConfirm;
      } else {
        _dropoffPoint = point;
        _dropoffLabelController.text = label;
        _dropoffSearchController.text = label;
        _dropoffSuggestions = const [];
        _selectionMode = _PointSelectionMode.dropoff;
        _requestStep = _pickupConfirmed
            ? TaxiRequestStep.summaryAndSubmit
            : TaxiRequestStep.dropoffConfirm;
      }
      _rideFieldErrors.remove(forPickup ? 'pickupSearch' : 'dropoffSearch');
      _rideFieldErrors.remove(forPickup ? 'pickupLabel' : 'dropoffLabel');
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
    _mapController.move(point, 16.4);
    unawaited(_refreshRoutePolyline(force: true));
  }

  void _applyFavoriteTrip(Map<String, dynamic> trip) {
    final pickupRaw = trip['pickupSnapshot'];
    final dropoffRaw = trip['dropoffSnapshot'];
    if (pickupRaw is! Map || dropoffRaw is! Map) return;

    _applySnapshot(
      snapshot: Map<String, dynamic>.from(pickupRaw),
      forPickup: true,
      confirmPickup: true,
    );
    _applySnapshot(
      snapshot: Map<String, dynamic>.from(dropoffRaw),
      forPickup: false,
    );
    _setSheetStage(TaxiSheetStage.expanded);
    _showMessage(context.l10n.mapPageFavoriteTripApplied);
  }

  void _applyInitialIntentIfNeeded() {
    if (_initialIntentApplied) return;
    _initialIntentApplied = true;

    if (widget.initialFareIqd != null && widget.initialFareIqd! > 0) {
      _fareController.text = '${widget.initialFareIqd}';
    }
    if (widget.initialCouponCode != null &&
        widget.initialCouponCode!.trim().isNotEmpty) {
      _couponCodeController.text = widget.initialCouponCode!
          .trim()
          .toUpperCase();
    }
    if (widget.initialScheduledFor != null) {
      _timingMode = _RideRequestTimingMode.scheduled;
      _scheduledFor = widget.initialScheduledFor;
    }
    if (widget.initialPickupSnapshot != null) {
      _applySnapshot(
        snapshot: Map<String, dynamic>.from(widget.initialPickupSnapshot!),
        forPickup: true,
        confirmPickup: true,
      );
    }
    if (widget.initialDropoffSnapshot != null) {
      _applySnapshot(
        snapshot: Map<String, dynamic>.from(widget.initialDropoffSnapshot!),
        forPickup: false,
      );
    }
  }

  void _connectRealtimeStream() {
    if (!_canUseTaxiApi) return;
    _streamSub?.cancel();
    _streamSub = _taxiApi
        .streamEvents(lastEventId: _lastEventId)
        .listen(
          (event) {
            if (event.eventId != null && event.eventId! > 0) {
              _lastEventId = event.eventId;
            }

            if (event.event == 'heartbeat') {
              if (!mounted) return;
              setState(() {
                _streamConnected = true;
                _lastRealtimeAt = DateTime.now();
              });
              return;
            }

            if (event.event == 'connected' || event.event == 'replayed') {
              _reconnectAttempt = 0;
              if (!mounted) return;
              setState(() {
                _streamConnected = true;
                _lastRealtimeAt = DateTime.now();
              });
              _refreshRideFromRealtime(force: true);
              return;
            }

            if (event.event == 'taxi_location_update') {
              _applyLocationRealtimeEvent(event.data);
              return;
            }

            if (event.event.startsWith('taxi_') &&
                event.event != 'taxi_location_update') {
              _refreshRideFromRealtime();
              return;
            }

            // Fallback for unknown events from taxi stream.
            _refreshRideFromRealtime();
          },
          onError: (error) {
            if (!mounted) return;
            final unauthorized = isTerminalAuthError(error);
            setState(() {
              _streamConnected = false;
              if (unauthorized) {
                _error = context.l10n.mapPageSessionExpired;
              }
            });
            if (unauthorized) {
              _canUseTaxiApi = false;
              _streamSub?.cancel();
              return;
            }
            _scheduleReconnect();
          },
          onDone: () {
            if (!mounted) return;
            setState(() => _streamConnected = false);
            _scheduleReconnect();
          },
          cancelOnError: true,
        );
  }

  void _refreshRideFromRealtime({bool force = false}) {
    final now = DateTime.now();
    if (!force && _lastSilentRefreshAt != null) {
      final elapsed = now.difference(_lastSilentRefreshAt!);
      if (elapsed < const Duration(milliseconds: 900)) {
        return;
      }
    }
    _lastSilentRefreshAt = now;
    _lastRealtimeAt = now;
    unawaited(_loadCurrentRide(silent: true));
  }

  void _applyLocationRealtimeEvent(Map<String, dynamic> data) {
    final activeRideId = _readInt(_ride?['id']);
    final eventRideId = _eventRideId(data);
    if (activeRideId != null &&
        eventRideId != null &&
        activeRideId != eventRideId) {
      return;
    }

    final location = data['location'] is Map
        ? Map<String, dynamic>.from(data['location'] as Map)
        : null;
    final point = _latLngFromMap(location);
    final heading = location == null
        ? null
        : _readDouble(location['headingDeg']);
    if (point == null || !mounted) return;

    setState(() {
      _streamConnected = true;
      _lastRealtimeAt = DateTime.now();
      if (_activeRideEnvelope != null && location != null) {
        _activeRideEnvelope = {
          ..._activeRideEnvelope!,
          'latestLocation': location,
        };
      }
    });
    _animateCaptainPointTo(point, headingDeg: heading);
    unawaited(_refreshRoutePolyline());
  }

  void _animateCaptainPointTo(LatLng target, {double? headingDeg}) {
    final from = _captainPoint;
    _captainAnimationTimer?.cancel();
    if (from == null) {
      if (!mounted) return;
      setState(() {
        _captainPoint = target;
        if (headingDeg != null) _captainHeadingDeg = headingDeg;
      });
      return;
    }

    final steps = 8;
    var tick = 0;
    _captainAnimationTimer = Timer.periodic(const Duration(milliseconds: 90), (
      timer,
    ) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      tick += 1;
      final t = tick / steps;
      final lat = from.latitude + (target.latitude - from.latitude) * t;
      final lng = from.longitude + (target.longitude - from.longitude) * t;
      setState(() {
        _captainPoint = LatLng(lat, lng);
        if (headingDeg != null) _captainHeadingDeg = headingDeg;
      });
      if (tick >= steps) {
        timer.cancel();
      }
    });
  }

  void _scheduleReconnect() {
    if (!_canUseTaxiApi) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6);
    final delaySeconds = switch (_reconnectAttempt) {
      1 => 2,
      2 => 4,
      3 => 8,
      4 => 12,
      5 => 20,
      _ => 30,
    };

    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!mounted) return;
      _connectRealtimeStream();
    });
  }

  double _sheetSizeForStage(TaxiSheetStage stage) {
    return switch (stage) {
      TaxiSheetStage.collapsed => _collapsedSheetExtent,
      TaxiSheetStage.half => _halfSheetExtent,
      TaxiSheetStage.expanded => _expandedSheetExtent,
    };
  }

  TaxiSheetStage _sheetStageForExtent(double extent) {
    final collapsedUpperBound = (_collapsedSheetExtent + _halfSheetExtent) / 2;
    final expandedLowerBound = (_halfSheetExtent + _expandedSheetExtent) / 2;
    if (extent <= collapsedUpperBound) {
      return TaxiSheetStage.collapsed;
    }
    if (extent >= expandedLowerBound) {
      return TaxiSheetStage.expanded;
    }
    return TaxiSheetStage.half;
  }

  void _settleSheetDragState() {
    _sheetDragSettleTimer?.cancel();
    if (_sheetProgrammaticMotion) return;
    _sheetDragSettleTimer = Timer(const Duration(milliseconds: 120), () {
      if (!mounted || !_sheetDragInProgress) return;
      setState(() => _sheetDragInProgress = false);
    });
  }

  Future<void> _setSheetStage(
    TaxiSheetStage stage, {
    bool immediate = false,
  }) async {
    final target = _sheetSizeForStage(stage);
    final alreadyAtTarget =
        _sheetStage == stage && (_lastSheetExtent - target).abs() < 0.01;
    if (alreadyAtTarget && !_sheetProgrammaticMotion) return;
    _sheetDragSettleTimer?.cancel();
    _lastSheetExtent = target;
    if (mounted) {
      setState(() {
        _sheetStage = stage;
        _sheetDragInProgress = false;
      });
    } else {
      _sheetStage = stage;
      _sheetDragInProgress = false;
    }
    if (!_requestSheetController.isAttached) return;
    _sheetProgrammaticMotion = true;
    try {
      if (immediate) {
        _requestSheetController.jumpTo(target);
      } else {
        await _requestSheetController.animateTo(
          target,
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
        );
      }
    } catch (_) {
      // Ignore transient sheet animation races caused by view metric changes.
    } finally {
      _sheetProgrammaticMotion = false;
      if (mounted) {
        setState(() {});
      }
    }
  }

  bool _handleSheetExtentNotification(
    DraggableScrollableNotification notification,
  ) {
    _lastSheetExtent = notification.extent;
    final nextStage = _sheetStageForExtent(notification.extent);
    if (_sheetProgrammaticMotion) {
      if (nextStage != _sheetStage && mounted) {
        setState(() => _sheetStage = nextStage);
      } else {
        _sheetStage = nextStage;
      }
      return false;
    }
    final needsUpdate = nextStage != _sheetStage || !_sheetDragInProgress;
    if (needsUpdate && mounted) {
      setState(() {
        _sheetStage = nextStage;
        _sheetDragInProgress = true;
      });
    } else {
      _sheetStage = nextStage;
      _sheetDragInProgress = true;
    }
    _settleSheetDragState();
    return false;
  }

  void _applySuggestedFare([int? suggestedFare]) {
    final nextValue = '${suggestedFare ?? _fareEstimate.suggestedIqd}';
    _fareController.value = TextEditingValue(
      text: nextValue,
      selection: TextSelection.collapsed(offset: nextValue.length),
    );
    _clearRideFieldError('proposedFareIqd');
  }

  Future<void> _refreshRoutePolyline({bool force = false}) async {
    final routeTarget = _resolveRouteTarget();
    if (routeTarget == null) {
      if ((_routePoints.isNotEmpty ||
              _routeDistanceMeters != null ||
              _routeDurationSeconds != null) &&
          mounted) {
        setState(() {
          _routePoints = const [];
          _routeDistanceMeters = null;
          _routeDurationSeconds = null;
        });
      }
      return;
    }

    final from = routeTarget.$1;
    final to = routeTarget.$2;
    final now = DateTime.now();

    if (!force &&
        _lastRouteFrom != null &&
        _lastRouteTo != null &&
        _lastRouteAt != null) {
      final movedFrom = _routeService.distanceMeters(_lastRouteFrom!, from);
      final movedTo = _routeService.distanceMeters(_lastRouteTo!, to);
      final age = now.difference(_lastRouteAt!);
      if (movedFrom < 45 && movedTo < 30 && age < const Duration(seconds: 18)) {
        return;
      }
    }

    if (!force && _routeLoading) return;

    if (mounted) {
      setState(() => _routeLoading = true);
    } else {
      _routeLoading = true;
    }

    try {
      final preview = await _routeService.fetchDrivingRoutePreview(
        from: from,
        to: to,
      );
      if (!mounted) return;
      setState(() {
        _routePoints = preview.points;
        _routeDistanceMeters = preview.distanceMeters;
        _routeDurationSeconds = preview.durationSeconds;
        _lastRouteFrom = from;
        _lastRouteTo = to;
        _lastRouteAt = now;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routePoints = [from, to];
        _routeDistanceMeters = _routeService.distanceMeters(from, to);
        _routeDurationSeconds = null;
        _lastRouteFrom = from;
        _lastRouteTo = to;
        _lastRouteAt = now;
      });
    } finally {
      if (mounted) {
        setState(() => _routeLoading = false);
      } else {
        _routeLoading = false;
      }
    }
  }

  (LatLng, LatLng)? _resolveRouteTarget() {
    final ride = _ride;
    final status = _string(ride?['status']);
    final pickup = _pickupPoint;
    final dropoff = _dropoffPoint;
    final captain = _captainPoint;

    if (ride != null) {
      if ((status == 'captain_assigned' || status == 'captain_arriving') &&
          captain != null &&
          pickup != null) {
        return (captain, pickup);
      }
      if (status == 'ride_started' && captain != null && dropoff != null) {
        return (captain, dropoff);
      }
      if (pickup != null && dropoff != null) {
        return (pickup, dropoff);
      }
      return null;
    }

    if (pickup != null && dropoff != null) {
      return (pickup, dropoff);
    }
    return null;
  }

  Future<void> _reverseGeocodeAndFill({
    required LatLng point,
    required bool forPickup,
  }) async {
    try {
      final response =
          await Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: {
                'User-Agent': 'MaslakiTaxi/1.0 (support@maslaki.app)',
                'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.8',
              },
            ),
          ).get(
            'https://nominatim.openstreetmap.org/reverse',
            queryParameters: {
              'format': 'jsonv2',
              'lat': point.latitude,
              'lon': point.longitude,
              'zoom': 18,
              'addressdetails': 1,
            },
          );

      final data = response.data;
      if (data is! Map || !mounted) return;
      final displayName = _string(data['display_name']);
      if (displayName == null || displayName.isEmpty) return;
      final short = _shortPlaceLabel(displayName);

      setState(() {
        if (forPickup) {
          _pickupLabelController.text = short;
          if (_pickupSearchController.text.trim().isEmpty) {
            _pickupSearchController.text = short;
          }
        } else {
          _dropoffLabelController.text = short;
          if (_dropoffSearchController.text.trim().isEmpty) {
            _dropoffSearchController.text = short;
          }
        }
      });
    } catch (_) {
      // Keep manual labels if reverse geocoding is unavailable.
    }
  }

  Future<void> _goToMyLocation({bool setAsPickupIfEmpty = false}) async {
    if (_isLocating) return;
    final l10n = context.l10n;
    final locationPermissions = ref.read(locationPermissionServiceProvider);

    setState(() => _isLocating = true);
    try {
      final currentStatus = await locationPermissions.getStatus();
      if (!currentStatus.serviceEnabled) {
        await _showLocationSettingsDialog(
          l10n.mapPageEnableLocationService,
          openLocationSettings: true,
        );
        return;
      }

      final nextStatus = await locationPermissions.requestPermission();
      final denied =
          nextStatus.state == AppLocationPermissionState.denied ||
          nextStatus.state == AppLocationPermissionState.permanentlyDenied;
      if (denied) {
        await _showLocationSettingsDialog(
          l10n.mapPageLocationPermissionDenied,
          openLocationSettings:
              nextStatus.state == AppLocationPermissionState.serviceDisabled,
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.bestForNavigation,
        timeLimit: const Duration(seconds: 12),
      );

      final point = LatLng(position.latitude, position.longitude);
      if (!mounted) return;

      setState(() {
        _myLocation = point;
        if (setAsPickupIfEmpty &&
            _pickupPoint == null &&
            _activeRideEnvelope == null) {
          _pickupPoint = point;
          _pickupConfirmed = true;
          _selectionMode = _PointSelectionMode.dropoff;
          _requestStep = TaxiRequestStep.dropoffSearch;
          // Seed a non-empty pickup label synchronously so a failing/slow
          // reverse geocode never leaves the pickup label empty (which blocks
          // submit). The async reverse geocode below overwrites it with the
          // real address on success.
          if (_pickupLabelController.text.trim().isEmpty) {
            _pickupLabelController.text = l10n.mapPageCurrentLocation;
          }
        }
      });

      _mapController.move(point, 16.5);
      if (setAsPickupIfEmpty && _activeRideEnvelope == null) {
        unawaited(_reverseGeocodeAndFill(point: point, forPickup: true));
      }
      unawaited(_loadNearbyCaptains());
      unawaited(_refreshRoutePolyline());
    } catch (_) {
      _showMessage(l10n.mapPageLocateCurrentPositionFailed);
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _onPickupSearchChanged(String query) {
    _pickupSearchDebounce?.cancel();
    _pickupSearchDebounce = Timer(const Duration(milliseconds: 650), () {
      _searchPlaces(query, forPickup: true);
    });
  }

  void _onDropoffSearchChanged(String query) {
    _dropoffSearchDebounce?.cancel();
    _dropoffSearchDebounce = Timer(const Duration(milliseconds: 650), () {
      _searchPlaces(query, forPickup: false);
    });
  }

  Future<void> _searchPlaces(String rawQuery, {required bool forPickup}) async {
    final query = rawQuery.trim();
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        if (forPickup) {
          _pickupSuggestions = const [];
          _isSearchingPickup = false;
        } else {
          _dropoffSuggestions = const [];
          _isSearchingDropoff = false;
        }
      });
      return;
    }

    final searchToken = query;
    setState(() {
      if (forPickup) {
        _isSearchingPickup = true;
      } else {
        _isSearchingDropoff = true;
      }
    });

    try {
      final items = await _fetchTaxiPlaceSuggestions(query);

      if (!mounted) return;
      final stillSameQuery =
          (forPickup
                  ? _pickupSearchController.text
                  : _dropoffSearchController.text)
              .trim();
      if (stillSameQuery != searchToken) return;

      setState(() {
        if (forPickup) {
          _pickupSuggestions = items;
          _isSearchingPickup = false;
        } else {
          _dropoffSuggestions = items;
          _isSearchingDropoff = false;
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        if (forPickup) {
          _isSearchingPickup = false;
          _pickupSuggestions = const [];
        } else {
          _isSearchingDropoff = false;
          _dropoffSuggestions = const [];
        }
      });
    }
  }

  Future<List<_PlaceSuggestion>> _fetchTaxiPlaceSuggestions(
    String query,
  ) async {
    final suggestions = <_PlaceSuggestion>[];
    final seen = <String>{};

    void addSuggestion(_PlaceSuggestion suggestion) {
      final key =
          '${suggestion.latitude.toStringAsFixed(5)},'
          '${suggestion.longitude.toStringAsFixed(5)}:'
          '${suggestion.title.toLowerCase()}';
      if (seen.add(key)) {
        suggestions.add(suggestion);
      }
    }

    for (final plan in _buildNominatimPlans(query)) {
      final List<_PlaceSuggestion> results;
      try {
        results = await _fetchNominatimSuggestions(plan);
      } catch (_) {
        continue;
      }
      for (final result in results) {
        addSuggestion(result);
        if (suggestions.length >= 16) return suggestions;
      }
      if (suggestions.length >= 8) return suggestions;
    }

    if (query.length >= 3) {
      final osmResults = await _fetchOverpassSuggestions(query);
      for (final result in osmResults) {
        addSuggestion(result);
        if (suggestions.length >= 16) break;
      }
    }

    return suggestions;
  }

  List<_NominatimSearchPlan> _buildNominatimPlans(String query) {
    final variants = <String>[];
    void add(String value) {
      final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.isNotEmpty &&
          !variants.any(
            (item) => item.toLowerCase() == cleaned.toLowerCase(),
          )) {
        variants.add(cleaned);
      }
    }

    add(query);
    add('$query العراق');
    add('$query Iraq');
    add('العراق $query');

    final normalized = query.toLowerCase();
    if (_containsAny(normalized, const ['كلية', 'جامعة', 'معهد'])) {
      add('$query university Iraq');
      add('$query college Iraq');
    }
    if (_containsAny(normalized, const ['مدرسة', 'اعدادية', 'إعدادية'])) {
      add('$query school Iraq');
    }
    if (_containsAny(normalized, const ['جامع', 'مسجد', 'حسينية'])) {
      add('$query mosque Iraq');
    }
    if (_containsAny(normalized, const ['شارع', 'طريق', 'جسر', 'تقاطع'])) {
      add('$query street Iraq');
      add('$query road Iraq');
    }
    if (_containsAny(normalized, const ['منطقة', 'حي', 'محلة', 'ناحية'])) {
      add('$query neighbourhood Iraq');
      add('$query neighborhood Iraq');
    }
    if (_containsAny(normalized, const ['مستشفى', 'عيادة', 'مركز صحي'])) {
      add('$query hospital Iraq');
    }
    if (_containsAny(normalized, const ['مول', 'سوق', 'مطعم', 'كافيه'])) {
      add('$query mall Iraq');
      add('$query restaurant Iraq');
    }

    final plans = <_NominatimSearchPlan>[];
    final bias = _myLocation ?? _pickupPoint ?? _bismayahCenter;
    plans.add(
      _NominatimSearchPlan(
        query: query,
        viewbox: _viewboxAround(bias, 0.45),
        bounded: false,
        limit: 12,
      ),
    );
    for (final variant in variants) {
      plans.add(
        _NominatimSearchPlan(
          query: variant,
          viewbox: _iraqViewbox,
          bounded: false,
          limit: 12,
        ),
      );
    }
    plans.add(
      _NominatimSearchPlan(
        query: query,
        viewbox: _iraqViewbox,
        bounded: true,
        limit: 16,
      ),
    );
    return plans;
  }

  Future<List<_PlaceSuggestion>> _fetchNominatimSuggestions(
    _NominatimSearchPlan plan,
  ) async {
    final response = await _placeSearchDio.get(
      'https://nominatim.openstreetmap.org/search',
      queryParameters: {
        'format': 'jsonv2',
        'addressdetails': 1,
        'extratags': 1,
        'namedetails': 1,
        'dedupe': 1,
        'polygon_geojson': 0,
        'countrycodes': 'iq',
        'bounded': plan.bounded ? 1 : 0,
        'viewbox': plan.viewbox,
        'limit': plan.limit,
        'q': plan.query,
      },
    );

    final list = response.data is List ? response.data as List : const [];
    return list
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .map(_placeSuggestionFromNominatim)
        .whereType<_PlaceSuggestion>()
        .toList();
  }

  _PlaceSuggestion? _placeSuggestionFromNominatim(Map<String, dynamic> item) {
    final lat = double.tryParse('${item['lat'] ?? ''}');
    final lon = double.tryParse('${item['lon'] ?? ''}');
    final label = '${item['display_name'] ?? ''}'.trim();
    if (lat == null || lon == null || label.isEmpty) return null;
    final namedetails = item['namedetails'] is Map
        ? Map<String, dynamic>.from(item['namedetails'] as Map)
        : const <String, dynamic>{};
    final preferredName =
        _string(namedetails['name:ar']) ??
        _string(namedetails['name']) ??
        _string(item['name']);
    return _PlaceSuggestion(
      latitude: lat,
      longitude: lon,
      title: preferredName?.trim().isNotEmpty == true
          ? preferredName!.trim()
          : _shortPlaceLabel(label),
      fullAddress: label,
      kind: _string(item['type']) ?? _string(item['class']),
    );
  }

  Future<List<_PlaceSuggestion>> _fetchOverpassSuggestions(String query) async {
    final escaped = _escapeOverpassRegex(query.trim());
    if (escaped.isEmpty) return const [];
    final data =
        '''
[out:json][timeout:8];
area["ISO3166-1"="IQ"][admin_level=2]->.searchArea;
(
  node["name"~"$escaped",i](area.searchArea);
  way["name"~"$escaped",i](area.searchArea);
  relation["name"~"$escaped",i](area.searchArea);
  node["name:ar"~"$escaped",i](area.searchArea);
  way["name:ar"~"$escaped",i](area.searchArea);
  relation["name:ar"~"$escaped",i](area.searchArea);
  node["alt_name"~"$escaped",i](area.searchArea);
  way["alt_name"~"$escaped",i](area.searchArea);
  relation["alt_name"~"$escaped",i](area.searchArea);
);
out center 20;
''';
    try {
      final response = await _placeSearchDio.get(
        'https://overpass-api.de/api/interpreter',
        queryParameters: {'data': data},
      );
      final raw = response.data;
      final elements = raw is Map ? raw['elements'] : null;
      if (elements is! List) return const [];
      return elements
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map(_placeSuggestionFromOverpass)
          .whereType<_PlaceSuggestion>()
          .toList();
    } catch (_) {
      return const [];
    }
  }

  _PlaceSuggestion? _placeSuggestionFromOverpass(Map<String, dynamic> item) {
    final lat = _readDouble(item['lat'] ?? item['center']?['lat']);
    final lon = _readDouble(item['lon'] ?? item['center']?['lon']);
    if (lat == null || lon == null) return null;
    final tags = item['tags'] is Map
        ? Map<String, dynamic>.from(item['tags'] as Map)
        : const <String, dynamic>{};
    final name =
        _string(tags['name:ar']) ??
        _string(tags['name']) ??
        _string(tags['official_name']) ??
        _string(tags['alt_name']);
    if (name == null || name.trim().isEmpty) return null;
    final kind =
        _string(tags['amenity']) ??
        _string(tags['shop']) ??
        _string(tags['tourism']) ??
        _string(tags['highway']) ??
        _string(tags['place']) ??
        _string(tags['building']);
    final city =
        _string(tags['addr:city']) ??
        _string(tags['addr:district']) ??
        _string(tags['addr:suburb']) ??
        _string(tags['addr:neighbourhood']);
    return _PlaceSuggestion(
      latitude: lat,
      longitude: lon,
      title: name.trim(),
      fullAddress: [
        name.trim(),
        if (city != null && city.trim().isNotEmpty) city.trim(),
        if (kind != null && kind.trim().isNotEmpty) kind.trim(),
        'Iraq',
      ].join(' - '),
      kind: kind,
    );
  }

  bool _containsAny(String input, List<String> needles) {
    return needles.any((needle) => input.contains(needle.toLowerCase()));
  }

  String _escapeOverpassRegex(String input) {
    return input.replaceAllMapped(
      RegExp(r'([\\.^$|?*+()[\]{}"])'),
      (match) => '\\${match.group(1)}',
    );
  }

  String _viewboxAround(LatLng center, double delta) {
    final west = (center.longitude - delta).clamp(38.5, 49.0);
    final east = (center.longitude + delta).clamp(38.5, 49.0);
    final north = (center.latitude + delta).clamp(28.5, 38.0);
    final south = (center.latitude - delta).clamp(28.5, 38.0);
    return '$west,$north,$east,$south';
  }

  String _shortPlaceLabel(String input) {
    final parts = input
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return input;
    if (parts.length == 1) return parts.first;
    return '${parts[0]} - ${parts[1]}';
  }

  void _selectPlaceSuggestion(
    _PlaceSuggestion place, {
    required bool forPickup,
  }) {
    final selectedPoint = LatLng(place.latitude, place.longitude);
    setState(() {
      if (forPickup) {
        _pickupPoint = selectedPoint;
        _pickupLabelController.text = place.title;
        _pickupSearchController.text = place.title;
        _pickupSuggestions = const [];
        _pickupConfirmed = true;
        _selectionMode = _PointSelectionMode.dropoff;
        _requestStep = TaxiRequestStep.dropoffSearch;
      } else {
        _dropoffPoint = selectedPoint;
        _dropoffLabelController.text = place.title;
        _dropoffSearchController.text = place.title;
        _dropoffSuggestions = const [];
        _selectionMode = _PointSelectionMode.dropoff;
        _requestStep = TaxiRequestStep.summaryAndSubmit;
      }
    });
    _mapController.move(selectedPoint, 16.4);
    unawaited(
      _setSheetStage(forPickup ? TaxiSheetStage.half : TaxiSheetStage.expanded),
    );
    unawaited(_refreshRoutePolyline());
  }

  void _confirmPickup() {
    if (_pickupPoint == null) {
      _showMessage(context.l10n.mapPageSelectPickupFirst);
      return;
    }
    setState(() {
      _pickupConfirmed = true;
      _selectionMode = _PointSelectionMode.dropoff;
      _requestStep = TaxiRequestStep.dropoffSearch;
      _rideFieldErrors.remove('pickupSearch');
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
    _setSheetStage(TaxiSheetStage.half);
    _showMessage(context.l10n.mapPagePickupConfirmedNextDropoff);
  }

  void _confirmDropoff() {
    if (_dropoffPoint == null) {
      _showMessage(context.l10n.mapPageSelectDropoffFirst);
      return;
    }
    setState(() {
      _requestStep = TaxiRequestStep.summaryAndSubmit;
      _rideFieldErrors.remove('dropoffSearch');
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
    _setSheetStage(TaxiSheetStage.expanded);
    unawaited(_refreshRoutePolyline());
    _showMessage(context.l10n.mapPageRouteSummaryTitle);
  }

  void _startPickupEdit() {
    setState(() {
      _selectionMode = _PointSelectionMode.pickup;
      _pickupConfirmed = false;
      _requestStep = TaxiRequestStep.pickupConfirm;
      _rideFieldErrors.remove('pickupSearch');
      _rideFieldErrors.remove('pickupLabel');
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
    _setSheetStage(TaxiSheetStage.half);
  }

  void _startDropoffEdit() {
    setState(() {
      _selectionMode = _PointSelectionMode.dropoff;
      _requestStep = _dropoffPoint == null
          ? TaxiRequestStep.dropoffSearch
          : TaxiRequestStep.dropoffConfirm;
      _rideFieldErrors.remove('dropoffSearch');
      _rideFieldErrors.remove('dropoffLabel');
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
    _setSheetStage(TaxiSheetStage.half);
  }

  Future<void> _openContextLocationSearch({required bool forPickup}) async {
    final result = await Navigator.of(context).push<_TaxiLocationSearchResult>(
      MaterialPageRoute(
        builder: (_) => _TaxiLocationSearchPage(
          title: forPickup
              ? context.l10n.mapPagePickupSearchLabel
              : context.l10n.mapPageDropoffSearchLabel,
          hintText: forPickup
              ? context.l10n.mapPagePickupSearchHint
              : context.l10n.mapPageDropoffSearchHint,
          initialQuery: forPickup
              ? _pickupSearchController.text.trim()
              : _dropoffSearchController.text.trim(),
        ),
      ),
    );
    if (!mounted || result == null) return;
    final point = LatLng(result.latitude, result.longitude);
    setState(() {
      if (forPickup) {
        _pickupPoint = point;
        _pickupConfirmed = true;
        _selectionMode = _PointSelectionMode.dropoff;
        _pickupLabelController.text = result.title;
        _pickupSearchController.text = result.address;
        _requestStep = TaxiRequestStep.dropoffSearch;
      } else {
        _dropoffPoint = point;
        _selectionMode = _PointSelectionMode.dropoff;
        _dropoffLabelController.text = result.title;
        _dropoffSearchController.text = result.address;
        _requestStep = TaxiRequestStep.summaryAndSubmit;
      }
    });
    _mapController.move(point, 16.5);
    _setSheetStage(forPickup ? TaxiSheetStage.half : TaxiSheetStage.expanded);
    unawaited(_refreshRoutePolyline());
  }

  TaxiFareEstimateRange get _fareEstimate =>
      TaxiFarePolicy.estimateFromDistanceMeters(
        _routeDistanceMeters,
        durationSeconds: _routeDurationSeconds,
      );

  String _formatScheduledFor(DateTime dateTime) {
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(dateTime);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(dateTime),
      alwaysUse24HourFormat: true,
    );
    return '$date - $time';
  }

  Future<void> _pickScheduledDateTime() async {
    final now = DateTime.now();
    final initial = _scheduledFor != null && _scheduledFor!.isAfter(now)
        ? _scheduledFor!
        : now.add(const Duration(minutes: 15));
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 30)),
    );
    if (pickedDate == null || !mounted) return;
    final pickedTime = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
    );
    if (pickedTime == null || !mounted) return;

    final candidate = DateTime(
      pickedDate.year,
      pickedDate.month,
      pickedDate.day,
      pickedTime.hour,
      pickedTime.minute,
    );
    if (candidate.isBefore(now.add(const Duration(minutes: 1)))) {
      setState(() {
        _rideFieldErrors['scheduledFor'] = context.l10n.validationInvalidDate;
        _rideFormError = context.l10n.validationReviewRequiredFields;
      });
      _showMessage(context.l10n.mapPageScheduleInPast);
      return;
    }

    setState(() {
      _scheduledFor = candidate;
      _rideFieldErrors.remove('scheduledFor');
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
  }

  Future<void> _openSavedPlacesSheet({required bool forPickup}) async {
    await _loadQuickOptions(force: true);
    if (!mounted) return;
    if (_savedPlaces.isEmpty) {
      _showMessage(context.l10n.taxiSavedPlacesEmpty);
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        final l10n = sheetContext.l10n;
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            shrinkWrap: true,
            itemCount: _savedPlaces.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final item = _savedPlaces[index];
              final placeType = _string(item['placeType']) ?? 'custom';
              final icon = switch (placeType) {
                'home' => Icons.home_rounded,
                'work' => Icons.business_center_rounded,
                _ => Icons.place_outlined,
              };
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: Icon(icon),
                title: Text(_string(item['label']) ?? '-'),
                subtitle: Text(_string(item['addressText']) ?? '-'),
                trailing: Text(
                  forPickup
                      ? l10n.mapPagePickupPoint
                      : l10n.mapPageDropoffPoint,
                ),
                onTap: () => Navigator.of(sheetContext).pop(item),
              );
            },
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    _applySnapshot(
      snapshot: selected,
      forPickup: forPickup,
      confirmPickup: forPickup,
    );
  }

  Future<void> _openFavoriteTripsSheet() async {
    await _loadQuickOptions(force: true);
    if (!mounted) return;
    if (_favoriteTrips.isEmpty) {
      _showMessage(context.l10n.taxiFavoriteTripsEmpty);
      return;
    }

    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 16),
            shrinkWrap: true,
            itemCount: _favoriteTrips.length,
            separatorBuilder: (_, _) => const SizedBox(height: 6),
            itemBuilder: (context, index) {
              final trip = _favoriteTrips[index];
              final pickup = trip['pickupSnapshot'] is Map
                  ? Map<String, dynamic>.from(trip['pickupSnapshot'] as Map)
                  : const <String, dynamic>{};
              final dropoff = trip['dropoffSnapshot'] is Map
                  ? Map<String, dynamic>.from(trip['dropoffSnapshot'] as Map)
                  : const <String, dynamic>{};
              return ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                leading: const Icon(Icons.route_outlined),
                title: Text(_string(trip['label']) ?? '-'),
                subtitle: Text(
                  '${_string(pickup['label']) ?? '-'} -> ${_string(dropoff['label']) ?? '-'}',
                ),
                onTap: () => Navigator.of(sheetContext).pop(trip),
              );
            },
          ),
        );
      },
    );

    if (selected == null || !mounted) return;
    _applyFavoriteTrip(selected);
  }

  Future<void> _saveCurrentAsFavoriteTrip() async {
    final l10n = context.l10n;
    if (_pickupPoint == null || _dropoffPoint == null) {
      _showMessage(l10n.validationSelectLocation);
      return;
    }

    final labelCtrl = TextEditingController();
    var localError = '';
    final save = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: Text(l10n.mapPageFavoriteSaveTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: labelCtrl,
                    decoration: InputDecoration(
                      labelText: l10n.mapPageFavoriteLabelField,
                      errorText: localError.isEmpty ? null : localError,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${_pickupLabelController.text.trim()} -> ${_dropoffLabelController.text.trim()}',
                    style: Theme.of(dialogContext).textTheme.bodySmall,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () {
                    if (labelCtrl.text.trim().isEmpty) {
                      setDialogState(() {
                        localError = l10n.validationRequiredField(
                          l10n.mapPageFavoriteLabelField,
                        );
                      });
                      return;
                    }
                    Navigator.of(dialogContext).pop(true);
                  },
                  child: Text(l10n.commonSave),
                ),
              ],
            );
          },
        );
      },
    );

    if (save != true || !mounted) {
      labelCtrl.dispose();
      return;
    }

    try {
      await _taxiApi.createFavoriteTrip({
        'label': labelCtrl.text.trim(),
        'pickupSnapshot': {
          'latitude': _pickupPoint!.latitude,
          'longitude': _pickupPoint!.longitude,
          'label': _pickupLabelController.text.trim(),
          'addressText': _pickupSearchController.text.trim().isEmpty
              ? _pickupLabelController.text.trim()
              : _pickupSearchController.text.trim(),
        },
        'dropoffSnapshot': {
          'latitude': _dropoffPoint!.latitude,
          'longitude': _dropoffPoint!.longitude,
          'label': _dropoffLabelController.text.trim(),
          'addressText': _dropoffSearchController.text.trim().isEmpty
              ? _dropoffLabelController.text.trim()
              : _dropoffSearchController.text.trim(),
        },
      });
      await _loadQuickOptions(force: true);
      if (!mounted) return;
      _showMessage(l10n.mapPageFavoriteTripSaved);
    } on DioException catch (e) {
      if (!mounted) return;
      _showMessage(_extractApiError(e));
    } catch (_) {
      if (!mounted) return;
      _showMessage(l10n.errorsServerFailure);
    } finally {
      labelCtrl.dispose();
    }
  }

  Future<void> _showLocationSettingsDialog(
    String message, {
    required bool openLocationSettings,
  }) async {
    if (!mounted) return;
    final l10n = context.l10n;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (openLocationSettings) {
                  await ref
                      .read(locationPermissionServiceProvider)
                      .openLocationSettings();
                } else {
                  await ref
                      .read(locationPermissionServiceProvider)
                      .openAppSettings();
                }
              },
              child: Text(l10n.commonSettings),
            ),
          ],
        );
      },
    );
  }

  Future<void> _openComplaintDialog() async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null) return;
    final l10n = context.l10n;
    try {
      final eligibility = await _taxiApi.complaintEligibility(rideId);
      final eligible = eligibility['eligible'] == true;
      if (!eligible) {
        _showMessage(l10n.mapPageComplaintNotEligible);
        return;
      }
    } on DioException catch (e) {
      _showMessage(_extractApiError(e));
      return;
    } catch (_) {
      _showMessage(l10n.mapPageComplaintEligibilityFailed);
      return;
    }
    if (!mounted) return;

    final reasonCtrl = TextEditingController();
    final detailsCtrl = TextEditingController();
    final scroll = FormScrollCoordinator();
    final categories = <String, String>{
      'bad_behavior': l10n.taxiComplaintCategoryBadBehavior,
      'delay': l10n.taxiComplaintCategoryDelay,
      'fare_dispute': l10n.taxiComplaintCategoryFare,
      'route_issue': l10n.taxiComplaintCategoryRoute,
      'vehicle_cleanliness': l10n.taxiComplaintCategoryCleanliness,
      'driving_quality': l10n.taxiComplaintCategoryDriving,
      'other': l10n.taxiComplaintCategoryOther,
    };
    var selectedCategory = categories.keys.first;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        var submitting = false;
        String? formError;
        final fieldErrors = <String, String>{};
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (submitting) return;
              final nextErrors = <String, String>{};
              if (reasonCtrl.text.trim().isEmpty) {
                nextErrors['reason'] = resolveFormFieldError(
                  l10n: l10n,
                  field: 'reason',
                  code: 'REQUIRED',
                  fieldLabel: l10n.mapPageComplaintReasonLabel,
                );
              }
              if (nextErrors.isNotEmpty) {
                setDialogState(() {
                  fieldErrors
                    ..clear()
                    ..addAll(nextErrors);
                  formError = l10n.validationReviewRequiredFields;
                });
                await scroll.focusFirstError(const ['reason']);
                return;
              }

              setDialogState(() {
                submitting = true;
                fieldErrors.clear();
                formError = null;
              });
              try {
                await _taxiApi.createComplaint(
                  tripId: rideId,
                  category: selectedCategory,
                  reason: reasonCtrl.text.trim(),
                  details: detailsCtrl.text.trim().isEmpty
                      ? null
                      : detailsCtrl.text.trim(),
                );
                if (!dialogContext.mounted) return;
                Navigator.of(dialogContext).pop();
                _showMessage(l10n.mapPageComplaintSubmitted);
              } on DioException catch (e) {
                final parsed = parseBackendFieldErrors(e);
                final nextErrors = <String, String>{};
                for (final entry in parsed.fieldCodes.entries) {
                  if (entry.key == '_form') continue;
                  nextErrors[entry.key] = resolveFormFieldError(
                    l10n: l10n,
                    field: entry.key,
                    code: entry.value,
                  );
                }
                setDialogState(() {
                  submitting = false;
                  if (nextErrors.isNotEmpty) {
                    fieldErrors
                      ..clear()
                      ..addAll(nextErrors);
                    formError = resolveFormLevelError(
                      l10n,
                      code: parsed.formCode ?? parsed.messageCode,
                      fallback: l10n.mapPageComplaintSubmitFailed,
                    );
                  } else {
                    formError = _extractApiError(e);
                  }
                });
              } catch (_) {
                setDialogState(() {
                  submitting = false;
                  formError = l10n.mapPageComplaintSubmitFailed;
                });
              }
            }

            return AlertDialog(
              title: Text(l10n.mapPageComplaintTitle),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    FormErrorBanner(message: formError),
                    DropdownButtonFormField<String>(
                      initialValue: selectedCategory,
                      decoration: InputDecoration(
                        labelText: l10n.mapPageComplaintCategoryLabel,
                      ),
                      items: categories.entries
                          .map(
                            (entry) => DropdownMenuItem<String>(
                              value: entry.key,
                              child: Text(entry.value),
                            ),
                          )
                          .toList(),
                      onChanged: submitting
                          ? null
                          : (value) {
                              if (value == null) return;
                              setDialogState(() => selectedCategory = value);
                            },
                    ),
                    const SizedBox(height: 10),
                    scroll.anchor(
                      'reason',
                      TextField(
                        controller: reasonCtrl,
                        focusNode: scroll.focusNodeFor('reason'),
                        decoration: InputDecoration(
                          labelText: l10n.mapPageComplaintReasonLabel,
                          errorText: fieldErrors['reason'],
                        ),
                        minLines: 2,
                        maxLines: 3,
                        onChanged: (_) {
                          if (fieldErrors.containsKey('reason')) {
                            setDialogState(() {
                              fieldErrors.remove('reason');
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: detailsCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.mapPageComplaintDetailsLabel,
                      ),
                      minLines: 2,
                      maxLines: 4,
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.mapPageComplaintSubmit),
                ),
              ],
            );
          },
        );
      },
    );

    reasonCtrl.dispose();
    detailsCtrl.dispose();
    scroll.dispose();
  }

  String? _mapPageFieldLabel(String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'pickupSearch':
        return l10n.mapPagePickupPoint;
      case 'dropoffSearch':
        return l10n.mapPageDropoffPoint;
      case 'pickupLabel':
        return l10n.mapPagePickupDescriptionLabel;
      case 'dropoffLabel':
        return l10n.mapPageDropoffDescriptionLabel;
      case 'proposedFareIqd':
      case 'offeredFareIqd':
        return l10n.mapPageSuggestedFareLabel;
      case 'couponCode':
        return l10n.taxiCouponCodeField;
      case 'scheduledFor':
        return l10n.mapPageScheduleModeLater;
      case 'note':
      case 'review':
        return l10n.mapPageOptionalNote;
      case 'reason':
        return l10n.mapPageComplaintReasonLabel;
      case 'messageText':
        return l10n.commonMessage;
      default:
        return null;
    }
  }

  String _resolveMapFieldError(String field, {String? code}) {
    final l10n = context.l10n;
    if (field == 'pickupSearch' || field == 'dropoffSearch') {
      return l10n.validationSelectLocation;
    }
    if (field == 'proposedFareIqd' || field == 'offeredFareIqd') {
      return l10n.validationMinValue(TaxiFarePolicy.minimumFareIqd.toString());
    }
    if (field == 'scheduledFor') {
      return l10n.validationInvalidDate;
    }
    if (field == 'rating') {
      return l10n.validationSelectOption;
    }
    return resolveFormFieldError(
      l10n: l10n,
      field: field,
      code: code,
      fieldLabel: _mapPageFieldLabel(field),
      customResolver: (l10n, field, code) {
        switch (field) {
          case 'pickupLatitude':
          case 'pickupLongitude':
            return l10n.validationSelectLocation;
          case 'dropoffLatitude':
          case 'dropoffLongitude':
            return l10n.validationSelectLocation;
          case 'proposedFareIqd':
          case 'offeredFareIqd':
            return l10n.validationMinValue(
              TaxiFarePolicy.minimumFareIqd.toString(),
            );
          case 'messageText':
            return l10n.validationMessageRequired;
          case 'rating':
            return l10n.validationSelectOption;
          default:
            return null;
        }
      },
    );
  }

  void _clearRideFieldError(String field) {
    if (!_rideFieldErrors.containsKey(field) && _rideFormError == null) return;
    setState(() {
      _rideFieldErrors.remove(field);
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
  }

  void _swapRideEndpoints() {
    if (_activeRideEnvelope != null) return;
    setState(() {
      final previousPickupPoint = _pickupPoint;
      final previousPickupLabel = _pickupLabelController.text;
      final previousPickupSearch = _pickupSearchController.text;
      final previousPickupSuggestions = _pickupSuggestions;

      _pickupPoint = _dropoffPoint;
      _pickupLabelController.text = _dropoffLabelController.text;
      _pickupSearchController.text = _dropoffSearchController.text;
      _pickupSuggestions = _dropoffSuggestions;

      _dropoffPoint = previousPickupPoint;
      _dropoffLabelController.text = previousPickupLabel;
      _dropoffSearchController.text = previousPickupSearch;
      _dropoffSuggestions = previousPickupSuggestions;
      _pickupConfirmed = _pickupPoint != null;

      _rideFieldErrors.remove('pickupSearch');
      _rideFieldErrors.remove('dropoffSearch');
      _rideFieldErrors.remove('pickupLabel');
      _rideFieldErrors.remove('dropoffLabel');
      if (_rideFieldErrors.isEmpty) {
        _rideFormError = null;
      }
    });
    unawaited(_refreshRoutePolyline(force: true));
  }

  Future<void> _focusRideFields(Iterable<String> fields) {
    const ordered = <String>[
      'pickupSearch',
      'dropoffSearch',
      'pickupLabel',
      'dropoffLabel',
      'scheduledFor',
      'proposedFareIqd',
      'couponCode',
      'note',
    ];
    final wanted = fields.toSet();
    return _rideComposerScroll.focusFirstError(ordered.where(wanted.contains));
  }

  Future<void> _createRide() async {
    if (_submitting) return;
    final l10n = context.l10n;
    final nextErrors = <String, String>{};

    if (_pickupPoint == null) {
      nextErrors['pickupSearch'] = _resolveMapFieldError('pickupSearch');
    } else if (!_pickupConfirmed) {
      nextErrors['pickupSearch'] = l10n.mapPageConfirmPickupBeforeSubmit;
    }

    if (_dropoffPoint == null) {
      nextErrors['dropoffSearch'] = _resolveMapFieldError('dropoffSearch');
    }

    final fare = tryParseLocalizedInt(_fareController.text.trim());
    if (fare == null || fare < TaxiFarePolicy.minimumFareIqd) {
      nextErrors['proposedFareIqd'] = _resolveMapFieldError('proposedFareIqd');
    }

    final pickupLabel = _pickupLabelController.text.trim();
    final dropoffLabel = _dropoffLabelController.text.trim();

    if (pickupLabel.isEmpty) {
      nextErrors['pickupLabel'] = _resolveMapFieldError('pickupLabel');
    }
    if (dropoffLabel.isEmpty) {
      nextErrors['dropoffLabel'] = _resolveMapFieldError('dropoffLabel');
    }
    if (_timingMode == _RideRequestTimingMode.scheduled) {
      if (_scheduledFor == null ||
          _scheduledFor!.isBefore(
            DateTime.now().add(const Duration(minutes: 1)),
          )) {
        nextErrors['scheduledFor'] = _resolveMapFieldError('scheduledFor');
      }
    }

    if (nextErrors.isNotEmpty) {
      setState(() {
        _rideFieldErrors
          ..clear()
          ..addAll(nextErrors);
        _rideFormError = l10n.validationReviewRequiredFields;
        _error = null;
      });
      _focusRideFields(nextErrors.keys);
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
      _rideFormError = null;
      _rideFieldErrors.clear();
    });

    try {
      if (_timingMode == _RideRequestTimingMode.scheduled) {
        await _taxiApi.createScheduledRide(
          pickupSnapshot: {
            'latitude': _pickupPoint!.latitude,
            'longitude': _pickupPoint!.longitude,
            'label': pickupLabel,
            'addressText': _pickupSearchController.text.trim().isEmpty
                ? pickupLabel
                : _pickupSearchController.text.trim(),
          },
          dropoffSnapshot: {
            'latitude': _dropoffPoint!.latitude,
            'longitude': _dropoffPoint!.longitude,
            'label': dropoffLabel,
            'addressText': _dropoffSearchController.text.trim().isEmpty
                ? dropoffLabel
                : _dropoffSearchController.text.trim(),
          },
          proposedFareIqd: fare!,
          scheduleFor: _scheduledFor!,
          couponCode: _couponCodeController.text.trim().isEmpty
              ? null
              : _couponCodeController.text.trim(),
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        );
        _showMessage(
          l10n.mapPageScheduledRideCreated(_formatScheduledFor(_scheduledFor!)),
        );
      } else {
        await _taxiApi.createRide(
          pickupLatitude: _pickupPoint!.latitude,
          pickupLongitude: _pickupPoint!.longitude,
          dropoffLatitude: _dropoffPoint!.latitude,
          dropoffLongitude: _dropoffPoint!.longitude,
          pickupLabel: pickupLabel,
          dropoffLabel: dropoffLabel,
          proposedFareIqd: fare!,
          couponCode: _couponCodeController.text.trim().isEmpty
              ? null
              : _couponCodeController.text.trim(),
          note: _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        );
        await _loadCurrentRide(silent: true);
        _showMessage(l10n.mapPageRideRequestSent);
      }
      await _loadQuickOptions(force: true);
    } on DioException catch (e) {
      final parsed = parseBackendFieldErrors(e);
      if (parsed.hasFieldErrors || parsed.formCode != null) {
        final nextErrors = <String, String>{};
        for (final entry in parsed.fieldCodes.entries) {
          final field = switch (entry.key) {
            'pickupLatitude' || 'pickupLongitude' => 'pickupSearch',
            'dropoffLatitude' || 'dropoffLongitude' => 'dropoffSearch',
            'couponCode' => 'couponCode',
            'scheduleFor' || 'scheduledFor' => 'scheduledFor',
            _ => entry.key,
          };
          nextErrors[field] = _resolveMapFieldError(field, code: entry.value);
        }
        setState(() {
          _rideFieldErrors
            ..clear()
            ..addAll(nextErrors);
          _rideFormError = resolveFormLevelError(
            l10n,
            code: parsed.formCode ?? parsed.messageCode,
            fallback: l10n.mapPageRideRequestFailed,
          );
        });
        await _focusRideFields(nextErrors.keys);
        return;
      }
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = l10n.mapPageRideRequestFailed;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancelRide() async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null) return;
    final l10n = context.l10n;

    final reason = await showTaxiCancelReasonSheet(context, isCaptain: false);
    if (reason == null || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _taxiApi.cancelRide(
        rideId,
        reasonCode: reason.code,
        reasonText: reason.text,
      );
      await _loadCurrentRide(silent: true);
      _captainPoint = null;
      _routePoints = const [];
      _lastRouteFrom = null;
      _lastRouteTo = null;
      _lastRouteAt = null;
      _showMessage(l10n.mapPageRideCancelled);
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
      // نعيد التحميل ليعكس القفل الحقيقي إن تغيّرت الحالة على الخادم.
      await _loadCurrentRide(silent: true);
    } catch (_) {
      setState(() {
        _error = l10n.mapPageRideCancelFailed;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _raiseRideEmergency() async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null || _submitting) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            context.lt(ar: 'مساعدة / حالة طارئة', en: 'Help / Emergency'),
          ),
          content: Text(
            context.lt(
              ar: 'سيتم فتح تذكرة عاجلة وإبلاغ الدعم فوراً. لن تُلغى الرحلة تلقائياً؛ سيتواصل معك فريق مسلكي.',
              en: 'An urgent ticket will be opened and support notified immediately. The ride is not auto-cancelled; the Maslaki team will contact you.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.lt(ar: 'تراجع', en: 'Back')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                context.lt(ar: 'إرسال طلب المساعدة', en: 'Send help request'),
              ),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _taxiApi.raiseRideEmergency(rideId);
      if (!mounted) return;
      _showMessage(
        context.lt(
          ar: 'تم إرسال طلب المساعدة. سيتواصل معك الدعم قريباً.',
          en: 'Help request sent. Support will contact you shortly.',
        ),
      );
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = context.lt(
          ar: 'تعذر إرسال طلب المساعدة حالياً.',
          en: 'Unable to send the help request right now.',
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _raiseRideFare(int proposedFareIqd) async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null || _submitting) return;

    final currentFare =
        _readInt(_ride?['proposedFareIqd']) ??
        _readInt(_ride?['customerFare']) ??
        TaxiFarePolicy.minimumFareIqd;
    if (proposedFareIqd <= currentFare) {
      _showMessage(
        _t(
          'يجب أن تكون الأجرة الجديدة أعلى من الأجرة الحالية.',
          'The new fare must be higher than the current fare.',
        ),
      );
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _taxiApi.raiseRideFare(
        rideId: rideId,
        proposedFareIqd: proposedFareIqd,
      );
      await _loadCurrentRide(silent: true);
      _showMessage(
        _t(
          'تم رفع الأجرة وإعادة فتح البحث.',
          'Fare raised and search reopened.',
        ),
      );
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = _t(
          'تعذر رفع الأجرة حالياً.',
          'Unable to raise the fare right now.',
        );
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ignore: unused_element
  Future<void> _acceptBid(int bidId) async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null || _submitting) return;

    final l10n = context.l10n;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _taxiApi.acceptBid(rideId: rideId, bidId: bidId);
      await _loadCurrentRide(silent: true);
      _showMessage(l10n.mapPageBidAccepted);
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = l10n.mapPageBidAcceptFailed;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _rejectCurrentBid({int? bidId}) async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null || _submitting) return;

    final l10n = context.l10n;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      if (bidId != null && bidId > 0) {
        await _taxiApi.rejectBid(rideId: rideId, bidId: bidId);
      } else {
        await _taxiApi.rejectCurrentBid(rideId: rideId);
      }
      await _loadCurrentRide(silent: true);
      _showMessage(l10n.mapPageBidRejected);
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = l10n.mapPageBidRejectFailed;
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _openRideRatingDialogV2() async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null || _submitting) return;

    final l10n = context.l10n;
    final reviewCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    final fieldErrors = <String, String>{};
    var selectedRating = 5;
    var dialogSubmitting = false;
    var dialogClosed = false;
    String? formError;

    Future<void> submit(StateSetter setModalState) async {
      if (dialogSubmitting) return;
      setModalState(() {
        dialogSubmitting = true;
        formError = null;
      });

      try {
        await _taxiApi.rateRide(
          rideId: rideId,
          rating: selectedRating,
          review: reviewCtrl.text.trim(),
        );
        if (!mounted) return;
        dialogClosed = true;
        Navigator.of(context).pop();
        await _loadCurrentRide(silent: true);
        _showMessage(l10n.mapPageRideRated);
      } on DioException catch (e) {
        final parsed = parseBackendFieldErrors(e);
        if (parsed.hasFieldErrors || parsed.formCode != null) {
          fieldErrors
            ..clear()
            ..addEntries(
              parsed.fieldCodes.entries.map(
                (entry) => MapEntry(
                  entry.key,
                  _resolveMapFieldError(entry.key, code: entry.value),
                ),
              ),
            );
          setModalState(() {
            formError = resolveFormLevelError(
              l10n,
              code: parsed.formCode ?? parsed.messageCode,
              fallback: l10n.mapPageRideRatingFailed,
            );
          });
          await scrollCoordinator.focusFirstError(fieldErrors.keys);
        } else {
          setModalState(() => formError = _extractApiError(e));
        }
      } catch (_) {
        setModalState(() => formError = l10n.mapPageRideRatingFailed);
      } finally {
        if (mounted && !dialogClosed) {
          setModalState(() => dialogSubmitting = false);
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(l10n.mapPageRateRideTitle),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FormErrorBanner(message: formError),
                  Text(
                    l10n.mapPageRateRideSubtitle,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(5, (index) {
                      final star = index + 1;
                      final active = star <= selectedRating;
                      return IconButton(
                        onPressed: dialogSubmitting
                            ? null
                            : () => setModalState(() => selectedRating = star),
                        icon: Icon(
                          active ? Icons.star_rounded : Icons.star_border,
                          color: active ? Colors.amber : Colors.grey,
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 8),
                  scrollCoordinator.anchor(
                    'review',
                    TextField(
                      controller: reviewCtrl,
                      focusNode: scrollCoordinator.focusNodeFor('review'),
                      maxLines: 3,
                      onChanged: (_) {
                        final removed = fieldErrors.remove('review') != null;
                        if (removed && formError != null) {
                          setModalState(() => formError = null);
                        } else if (removed) {
                          setModalState(() {});
                        }
                      },
                      decoration: InputDecoration(
                        labelText: l10n.mapPageOptionalNote,
                        border: const OutlineInputBorder(),
                        errorText: fieldErrors['review'],
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: dialogSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(l10n.mapPageRateRideLater),
                ),
                FilledButton(
                  onPressed: dialogSubmitting
                      ? null
                      : () => submit(setModalState),
                  child: dialogSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.mapPageSubmitRating),
                ),
              ],
            );
          },
        );
      },
    );

    reviewCtrl.dispose();
    scrollCoordinator.dispose();
  }

  Future<void> _openCounterOfferDialogV2({int? initialFare, int? bidId}) async {
    final l10n = context.l10n;
    final fareCtrl = TextEditingController(text: '${initialFare ?? 0}');
    final noteCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    final fieldErrors = <String, String>{};
    var dialogSubmitting = false;
    var dialogClosed = false;
    String? formError;

    Future<void> submit(StateSetter setModalState) async {
      if (dialogSubmitting) return;
      final offeredFare = tryParseLocalizedInt(fareCtrl.text.trim());
      final nextErrors = <String, String>{};
      if (offeredFare == null || offeredFare <= 0) {
        nextErrors['offeredFareIqd'] = _resolveMapFieldError('offeredFareIqd');
      }
      if (nextErrors.isNotEmpty) {
        fieldErrors
          ..clear()
          ..addAll(nextErrors);
        setModalState(() => formError = l10n.validationReviewRequiredFields);
        await scrollCoordinator.focusFirstError(nextErrors.keys);
        return;
      }

      setModalState(() {
        dialogSubmitting = true;
        formError = null;
      });
      try {
        final rideId = _readInt(_ride?['id']);
        if (rideId == null) return;
        if (bidId != null && bidId > 0) {
          await _taxiApi.counterOfferBid(
            rideId: rideId,
            bidId: bidId,
            offeredFareIqd: offeredFare!,
            note: noteCtrl.text.trim(),
          );
        } else {
          await _taxiApi.counterOfferCurrentBid(
            rideId: rideId,
            offeredFareIqd: offeredFare!,
            note: noteCtrl.text.trim(),
          );
        }
        if (!mounted) return;
        dialogClosed = true;
        Navigator.of(context).pop();
        await _loadCurrentRide(silent: true);
        _showMessage(l10n.mapPageCounterOfferSent);
      } on DioException catch (e) {
        final parsed = parseBackendFieldErrors(e);
        if (parsed.hasFieldErrors || parsed.formCode != null) {
          fieldErrors
            ..clear()
            ..addEntries(
              parsed.fieldCodes.entries.map(
                (entry) => MapEntry(
                  entry.key,
                  _resolveMapFieldError(entry.key, code: entry.value),
                ),
              ),
            );
          setModalState(() {
            formError = resolveFormLevelError(
              l10n,
              code: parsed.formCode ?? parsed.messageCode,
              fallback: l10n.mapPageCounterOfferFailed,
            );
          });
          await scrollCoordinator.focusFirstError(fieldErrors.keys);
        } else {
          setModalState(() => formError = _extractApiError(e));
        }
      } catch (_) {
        setModalState(() => formError = l10n.mapPageCounterOfferFailed);
      } finally {
        if (mounted && !dialogClosed) {
          setModalState(() => dialogSubmitting = false);
        }
      }
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
        ),
        child: StatefulBuilder(
          builder: (context, setModalState) {
            return AlertDialog(
              title: Text(l10n.mapPageCounterOfferTitle),
              content: Directionality(
                textDirection: Directionality.of(context),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FormErrorBanner(message: formError),
                      scrollCoordinator.anchor(
                        'offeredFareIqd',
                        TextField(
                          controller: fareCtrl,
                          focusNode: scrollCoordinator.focusNodeFor(
                            'offeredFareIqd',
                          ),
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          onChanged: (_) {
                            final removed =
                                fieldErrors.remove('offeredFareIqd') != null;
                            if (removed && formError != null) {
                              setModalState(() => formError = null);
                            } else if (removed) {
                              setModalState(() {});
                            }
                          },
                          decoration: InputDecoration(
                            labelText: l10n.mapPageSuggestedFareLabel,
                            errorText: fieldErrors['offeredFareIqd'],
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      scrollCoordinator.anchor(
                        'note',
                        TextField(
                          controller: noteCtrl,
                          focusNode: scrollCoordinator.focusNodeFor('note'),
                          maxLines: 2,
                          textInputAction: TextInputAction.done,
                          onChanged: (_) {
                            final removed = fieldErrors.remove('note') != null;
                            if (removed && formError != null) {
                              setModalState(() => formError = null);
                            } else if (removed) {
                              setModalState(() {});
                            }
                          },
                          decoration: InputDecoration(
                            labelText: l10n.mapPageOptionalNote,
                            errorText: fieldErrors['note'],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: dialogSubmitting
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: dialogSubmitting
                      ? null
                      : () => submit(setModalState),
                  child: dialogSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(l10n.commonSend),
                ),
              ],
            );
          },
        ),
      ),
    );

    fareCtrl.dispose();
    noteCtrl.dispose();
    scrollCoordinator.dispose();
  }

  Future<void> _openRideChatBottomSheetV2() async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null) return;
    final l10n = context.l10n;

    final textCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    List<Map<String, dynamic>> messages = const [];
    bool sending = false;
    String? localError;
    String? composerError;

    Future<void> refreshMessages(StateSetter setModalState) async {
      try {
        final items = await _taxiApi.listRideChat(rideId: rideId, limit: 120);
        setModalState(() {
          messages = items;
          localError = null;
        });
      } on DioException catch (e) {
        setModalState(() => localError = _extractApiError(e));
      } catch (_) {
        setModalState(() => localError = l10n.mapPageRideChatLoadFailed);
      }
    }

    Future<void> sendMessage(StateSetter setModalState) async {
      final text = textCtrl.text.trim();
      if (sending) return;
      if (text.isEmpty) {
        setModalState(() {
          composerError = l10n.validationMessageRequired;
        });
        await scrollCoordinator.focusFirstError(const ['messageText']);
        return;
      }
      setModalState(() {
        sending = true;
        composerError = null;
      });
      try {
        await _taxiApi.sendRideChatMessage(rideId: rideId, messageText: text);
        textCtrl.clear();
        await refreshMessages(setModalState);
      } on DioException catch (e) {
        final parsed = parseBackendFieldErrors(e);
        if (parsed.codeFor('messageText') != null ||
            parsed.codeFor('message') != null) {
          setModalState(() {
            composerError = resolveFormFieldError(
              l10n: l10n,
              field: 'messageText',
              code: parsed.codeFor('messageText') ?? parsed.codeFor('message'),
              fieldLabel: l10n.commonMessage,
            );
          });
          await scrollCoordinator.focusFirstError(const ['messageText']);
        } else {
          setModalState(() {
            localError = _extractApiError(e);
          });
        }
      } catch (_) {
        setModalState(() => localError = l10n.mapPageRideChatSendFailed);
      } finally {
        setModalState(() => sending = false);
      }
    }

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      showDragHandle: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            if (messages.isEmpty && localError == null) {
              unawaited(refreshMessages(setModalState));
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
                top: 6,
              ),
              child: Directionality(
                textDirection: Directionality.of(context),
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.72,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.mapPageRideChatTitle,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Expanded(
                        child: localError != null
                            ? Center(
                                child: Text(
                                  localError!,
                                  style: const TextStyle(color: Colors.red),
                                ),
                              )
                            : messages.isEmpty
                            ? Center(child: Text(l10n.mapPageRideChatEmpty))
                            : ListView.builder(
                                itemCount: messages.length,
                                itemBuilder: (_, i) {
                                  final msg = messages[i];
                                  final senderRole =
                                      _string(msg['senderRole']) ?? 'system';
                                  final senderName =
                                      _string(msg['sender']?['fullName']) ??
                                      switch (senderRole) {
                                        'customer' => l10n.commonYou,
                                        'captain' => l10n.mapPageCaptainLabel,
                                        _ => l10n.commonSystem,
                                      };
                                  final text =
                                      _string(msg['messageText']) ?? '-';
                                  final mine = senderRole == 'customer';
                                  return Align(
                                    alignment: mine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? Colors.blue.withValues(
                                                alpha: 0.14,
                                              )
                                            : Colors.black.withValues(
                                                alpha: 0.08,
                                              ),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            senderName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(text),
                                        ],
                                      ),
                                    ),
                                  );
                                },
                              ),
                      ),
                      FormErrorBanner(message: localError),
                      scrollCoordinator.anchor(
                        'messageText',
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: textCtrl,
                                focusNode: scrollCoordinator.focusNodeFor(
                                  'messageText',
                                ),
                                textInputAction: TextInputAction.send,
                                onChanged: (_) {
                                  if (composerError != null) {
                                    setModalState(() => composerError = null);
                                  }
                                },
                                onSubmitted: (_) => sendMessage(setModalState),
                                decoration: InputDecoration(
                                  hintText: l10n.mapPageWriteMessageHint,
                                  errorText: composerError,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            FilledButton(
                              onPressed: sending
                                  ? null
                                  : () => sendMessage(setModalState),
                              child: sending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(l10n.commonSend),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );

    textCtrl.dispose();
    scrollCoordinator.dispose();
  }

  Map<String, dynamic>? _offerQueueItemFor(Map<String, dynamic> offer) {
    final queueRaw = _offerQueue?['queue'] ?? _offerQueue?['offers'];
    if (queueRaw is! List) return null;
    final offerId = _readInt(offer['offerId']) ?? _readInt(offer['id']);
    if (offerId == null) return null;
    for (final item in queueRaw) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      if (_readInt(map['offerId']) == offerId ||
          _readInt(map['bidId']) == offerId) {
        return map;
      }
    }
    return null;
  }

  String? _offerNegotiationLabel(Map<String, dynamic> offer) {
    final status = _string(offer['status'])?.toLowerCase();
    if (status == 'accepted') {
      return _t('رحلة نشطة', 'Active ride');
    }
    final lastOfferBy = _string(offer['lastOfferBy'])?.toLowerCase();
    if (lastOfferBy == 'customer') {
      return _t('بانتظار رد الكابتن', 'Waiting for captain response');
    }
    if (lastOfferBy == 'captain') {
      return _t('بانتظار رد الراكب', 'Waiting for rider response');
    }
    if (offer['isCurrent'] == true) {
      return _t('العرض الحالي', 'Current offer');
    }
    return null;
  }

  int? _offerNegotiationCountdown(Map<String, dynamic> offer) {
    final item = _offerQueueItemFor(offer);
    final negotiation = item?['negotiation'] is Map
        ? Map<String, dynamic>.from(item!['negotiation'] as Map)
        : null;
    final fromPayload = _readInt(negotiation?['remainingSeconds']);
    if (fromPayload != null) return fromPayload.clamp(0, 9999);

    final timeoutSeconds =
        _readInt(negotiation?['timeoutSeconds']) ??
        _readInt(_offerQueue?['negotiationTimeoutSeconds']) ??
        300;
    final anchor =
        _parseIsoDate(offer['updatedAt']) ?? _parseIsoDate(offer['createdAt']);
    if (anchor == null) return null;
    final expiresAt = anchor.add(Duration(seconds: timeoutSeconds));
    final seconds = expiresAt.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 0;
    return seconds;
  }

  Widget? _buildIraqiTaxiPlate(
    Map<String, dynamic>? captain, {
    Map<String, dynamic>? vehicle,
  }) {
    final plateNumber =
        _string(captain?['plateNumber']) ??
        _string(vehicle?['vehiclePlate']) ??
        _string(vehicle?['plate']) ??
        _string(vehicle?['vehicleNumber']);
    final digits = _cleanPlateDigits(
      _string(captain?['plateDigits']) ??
          _string(vehicle?['vehiclePlateDigits']) ??
          _string(vehicle?['plateDigits']),
      fallback: plateNumber,
    );
    if (digits == null || digits.trim().isEmpty) return null;
    return _IraqiPlateBadge(
      city:
          _string(captain?['plateGovernorate']) ??
          _string(vehicle?['vehiclePlateGovernorate']) ??
          _string(vehicle?['plateGovernorate']),
      category:
          _string(captain?['plateCategory']) ??
          _string(vehicle?['vehiclePlateCategory']) ??
          _string(vehicle?['plateCategory']),
      letter: _cleanPlateLetter(
        _string(captain?['plateLetter']) ??
            _string(vehicle?['vehiclePlateLetter']) ??
            _string(vehicle?['plateLetter']),
        fallback: plateNumber,
      ),
      digits: digits,
    );
  }

  String? _cleanPlateDigits(String? value, {String? fallback}) {
    final raw = (value?.trim().isNotEmpty == true ? value : fallback)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final digits = RegExp(
      r'[0-9\u0660-\u0669]+',
    ).allMatches(raw).map((match) => match.group(0)).join();
    return digits.isEmpty ? raw : digits;
  }

  String? _cleanPlateLetter(String? value, {String? fallback}) {
    final raw = (value?.trim().isNotEmpty == true ? value : fallback)?.trim();
    if (raw == null || raw.isEmpty) return null;
    final match = RegExp(r'[A-Za-z\u0600-\u06FF]').firstMatch(raw);
    return (match?.group(0) ?? raw.substring(0, 1)).trim();
  }

  Widget _buildTaxiOfferCard(
    Map<String, dynamic> offer, {
    required String nonAvailable,
    int? customerFareIqd,
  }) {
    final l10n = context.l10n;
    final captain = offer['captain'] is Map
        ? Map<String, dynamic>.from(offer['captain'] as Map)
        : null;
    final offerId = _readInt(offer['offerId']) ?? _readInt(offer['id']);
    final fare = _readInt(offer['offeredFareIqd']) ?? 0;
    final fareLabel = fare > 0 ? formatIqd(fare) : nonAvailable;
    final offerStatus = _string(offer['status'])?.toLowerCase();
    final acceptedOriginalFare =
        offerStatus == 'accepted' ||
        offerStatus == 'assigned' ||
        offerStatus == 'captain_assigned' ||
        _string(offer['acceptedOriginalFare']) == 'true' ||
        offer['acceptedOriginalFare'] == true;
    final differentFare =
        customerFareIqd != null && fare > 0 && fare != customerFareIqd;
    final etaMinutes = _readInt(offer['etaMinutes']);
    final distanceM =
        _readDouble(offer['distanceM']) ??
        _readInt(offer['distanceM'])?.toDouble();
    final captainName = _string(captain?['fullName']) ?? _t('كابتن', 'Captain');
    final captainRating = _readDouble(captain?['ratingAvg']);
    final ridesCount = _readInt(captain?['ridesCount']) ?? 0;
    final profileImage = _string(captain?['profileImageUrl']);
    final note = _string(offer['note']);
    final current = offer['isCurrent'] == true;
    final queuePosition = _readInt(offer['queuePosition']);
    final remainingSeconds = _offerNegotiationCountdown(offer);
    final negotiationLabel = _offerNegotiationLabel(offer);
    final statusHint = acceptedOriginalFare
        ? _t('الكابتن قبل الأجرة الأصلية', 'Captain accepted the original fare')
        : differentFare
        ? _t('الكابتن اقترح سعراً مختلفاً', 'Captain proposed a different fare')
        : null;
    final badges = <Widget>[
      if (offer['isBestPrice'] == true)
        _offerBadge(_t('أفضل سعر', 'Best price'), Colors.green),
      if (offer['isNearest'] == true)
        _offerBadge(_t('الأقرب', 'Nearest'), Colors.blue),
      if (offer['isHighestRated'] == true)
        _offerBadge(_t('الأعلى تقييماً', 'Top rated'), Colors.amber),
      if (current) _offerBadge(_t('العرض الحالي', 'Current'), Colors.teal),
      if (acceptedOriginalFare)
        _offerBadge(
          _t('قبل السعر الأصلي', 'Accepted original fare'),
          Colors.purple,
        ),
      if (differentFare && !acceptedOriginalFare)
        _offerBadge(_t('سعر مختلف', 'Different fare'), Colors.orange),
    ];

    return Container(
      decoration: BoxDecoration(
        color: current
            ? Colors.lightBlue.withValues(alpha: 0.10)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: current
              ? Colors.lightBlue.withValues(alpha: 0.34)
              : Colors.white.withValues(alpha: 0.10),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.white.withValues(alpha: 0.10),
                  backgroundImage: profileImage != null
                      ? AppCachedImageProvider(profileImage)
                      : null,
                  child: profileImage == null
                      ? Text(
                          captainName.isNotEmpty
                              ? captainName.substring(0, 1)
                              : 'M',
                        )
                      : null,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              captainName,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                          if (queuePosition != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '#$queuePosition',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        captainRating != null && captainRating > 0
                            ? '${captainRating.toStringAsFixed(1)} - $ridesCount'
                            : _t('لا يوجد تقييم بعد', 'No rating yet'),
                        style: const TextStyle(fontSize: 12),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                              _string(captain?['vehicleType']),
                              _string(captain?['carMake']),
                              _string(captain?['carModel']),
                              _readInt(captain?['carYear'])?.toString(),
                            ]
                            .whereType<String>()
                            .where((v) => v.isNotEmpty)
                            .join(' - '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                      if (_string(captain?['carColor']) != null)
                        Text(
                          '${_t('لون السيارة', 'Car color')}: ${_string(captain?['carColor'])}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      if (_buildIraqiTaxiPlate(captain) != null) ...[
                        const SizedBox(height: 6),
                        Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _buildIraqiTaxiPlate(captain)!,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (fare > 0)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        fareLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Colors.tealAccent,
                        ),
                      ),
                      if (etaMinutes != null)
                        Text(
                          '${_t('ETA', 'ETA')}: $etaMinutes ${_t('د', 'min')}',
                          style: const TextStyle(fontSize: 11),
                        ),
                    ],
                  ),
              ],
            ),
            if (badges.isNotEmpty) ...[
              const SizedBox(height: 8),
              Wrap(spacing: 6, runSpacing: 6, children: badges),
            ],
            if (negotiationLabel != null) ...[
              const SizedBox(height: 8),
              Text(
                negotiationLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (statusHint != null) ...[
              const SizedBox(height: 4),
              Text(
                statusHint,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
            if (remainingSeconds != null) ...[
              const SizedBox(height: 6),
              Row(
                children: [
                  const Icon(Icons.timer_outlined, size: 16),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      _t('الوقت المتبقي', 'Time remaining'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  Text(
                    _formatCountdown(remainingSeconds),
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              LinearProgressIndicator(
                value: (remainingSeconds / 300).clamp(0.0, 1.0).toDouble(),
                minHeight: 6,
                borderRadius: BorderRadius.circular(999),
                backgroundColor: Colors.white12,
              ),
            ],
            if (distanceM != null && distanceM > 0) ...[
              const SizedBox(height: 8),
              Text(
                distanceM < 1000
                    ? _t(
                        'المسافة: ${distanceM.round()} م',
                        'Distance: ${distanceM.round()} m',
                      )
                    : _t(
                        'المسافة: ${(distanceM / 1000).toStringAsFixed(distanceM >= 10000 ? 0 : 1)} كم',
                        'Distance: ${(distanceM / 1000).toStringAsFixed(distanceM >= 10000 ? 0 : 1)} km',
                      ),
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (note != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_t('ملاحظة', 'Note')}: $note',
                style: const TextStyle(fontSize: 12),
              ),
            ],
            if (!acceptedOriginalFare) ...[
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: (_submitting || offerId == null)
                        ? null
                        : () => _acceptBid(offerId),
                    icon: const Icon(Icons.check_circle),
                    label: Text(l10n.commonAccept),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _submitting || offerId == null
                        ? null
                        : () => _rejectCurrentBid(bidId: offerId),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(l10n.commonReject),
                  ),
                  FilledButton.icon(
                    onPressed: _submitting || offerId == null
                        ? null
                        : () => _openCounterOfferDialogV2(
                            initialFare: fare > 0 ? fare : null,
                            bidId: offerId,
                          ),
                    icon: const Icon(Icons.price_change),
                    label: Text(_t('عرض مضاد', 'Counter')),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _offerBadge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }

  Future<void> _openShareRideSheet() async {
    final rideId = _readInt(_ride?['id']);
    final auth = ref.read(authControllerProvider);
    final currentUserId = auth.user?.id;
    if (rideId == null || currentUserId == null) return;

    await showTaxiRideShareFriendsSheet(
      context: context,
      ref: ref,
      rideId: rideId,
      currentUserId: currentUserId,
      taxiApi: _taxiApi,
    );
  }

  void _onMapTap(LatLng point) {
    if (_activeRideEnvelope != null) {
      _showMessage(context.l10n.mapPageActiveRideEditBlocked);
      return;
    }

    final forPickup = switch (_requestStep) {
      TaxiRequestStep.dropoffSearch ||
      TaxiRequestStep.dropoffConfirm ||
      TaxiRequestStep.summaryAndSubmit => false,
      _ => true,
    };
    setState(() {
      if (forPickup) {
        _pickupPoint = point;
        _pickupConfirmed = false;
        _requestStep = TaxiRequestStep.pickupConfirm;
        if (_pickupLabelController.text.trim().isEmpty) {
          _pickupLabelController.text = context.l10n.mapPagePickupPoint;
        }
      } else {
        _dropoffPoint = point;
        _requestStep = TaxiRequestStep.dropoffConfirm;
        if (_dropoffLabelController.text.trim().isEmpty) {
          _dropoffLabelController.text = context.l10n.mapPageDropoffPoint;
        }
      }
    });
    _setSheetStage(TaxiSheetStage.half);

    unawaited(_reverseGeocodeAndFill(point: point, forPickup: forPickup));
    unawaited(_refreshRoutePolyline());
  }

  Map<String, dynamic>? get _ride {
    return taxiRideViewFromEnvelope(_activeRideEnvelope);
  }

  List<Map<String, dynamic>> get _offers {
    final envelope = _activeRideEnvelope;
    if (envelope == null) return const [];
    final raw =
        envelope['offers'] ?? envelope['offerQueue'] ?? envelope['bids'];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    if (raw is Map && raw['queue'] is List) {
      return (raw['queue'] as List)
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return const [];
  }

  Map<String, dynamic>? get _offerQueue {
    final envelope = _activeRideEnvelope;
    if (envelope == null) return null;
    final raw = envelope['offerQueue'] ?? envelope['bidQueue'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Map<String, dynamic>? get _currentOffer {
    final ride = _ride;
    final currentOfferId =
        _readInt(_offerQueue?['currentOfferId']) ??
        _readInt(_offerQueue?['currentBidId']) ??
        _readInt(ride?['currentBidId']);
    if (currentOfferId == null) return null;
    for (final offer in _offers) {
      if (_readInt(offer['id']) == currentOfferId &&
          _string(offer['status']) == 'active') {
        return offer;
      }
    }
    final current = _offerQueue?['currentOffer'];
    if (current is Map) {
      return Map<String, dynamic>.from(current);
    }
    return null;
  }

  Map<String, dynamic>? get _currentBid => _currentOffer;

  List<Map<String, dynamic>> get _waitingOffers {
    final currentId = _readInt(_currentOffer?['id']);
    return _offers
        .where(
          (offer) =>
              _string(offer['status']) == 'active' &&
              _readInt(offer['id']) != currentId,
        )
        .toList();
  }

  bool get _canShareRide {
    final status = _string(_ride?['status']);
    return status == 'searching' ||
        status == 'captain_assigned' ||
        status == 'captain_arriving' ||
        status == 'ride_started';
  }

  int? _finalAcceptanceRemainingSeconds(Map<String, dynamic>? ride) {
    if (ride == null) return null;
    final deadline =
        _parseIsoDate(ride['finalAcceptanceDeadlineAt']) ??
        _parseIsoDate(ride['createdAt'])?.add(const Duration(minutes: 5));
    if (deadline == null) return null;
    final seconds = deadline.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return 0;
    return seconds;
  }

  bool _priceRaiseRecommended(Map<String, dynamic>? ride) {
    if (ride == null) return false;
    final status = _string(ride['status']);
    return status == 'price_raise_required' ||
        ride['priceRaiseRecommended'] == true;
  }

  bool _isCancelledTaxiRideStatus(String? status) {
    final normalized = status?.toLowerCase();
    return normalized == 'cancelled' ||
        normalized == 'cancelled_by_customer' ||
        normalized == 'cancelled_by_captain' ||
        normalized == 'cancelled_by_admin';
  }

  bool _isTerminalTaxiRideStatus(String? status) {
    final normalized = status?.toLowerCase();
    return normalized == 'completed' ||
        normalized == 'expired' ||
        _isCancelledTaxiRideStatus(normalized);
  }

  DateTime? _parseIsoDate(dynamic value) {
    final text = _string(value);
    if (text == null || text.isEmpty) return null;
    return DateTime.tryParse(text);
  }

  String _formatCountdown(int totalSeconds) {
    final clamped = totalSeconds < 0 ? 0 : totalSeconds;
    final mm = (clamped ~/ 60).toString().padLeft(2, '0');
    final ss = (clamped % 60).toString().padLeft(2, '0');
    return '$mm:$ss';
  }

  String _localizedRideStatusLabel(String? status) {
    final l10n = context.l10n;
    switch (status) {
      case 'price_raise_required':
        return _t('رفع الأجرة مطلوب', 'Price raise required');
      case 'searching':
        return l10n.mapPageStatusSearching;
      case 'captain_assigned':
        return l10n.mapPageStatusCaptainAssigned;
      case 'captain_arriving':
        return l10n.mapPageStatusCaptainArriving;
      case 'ride_started':
        return l10n.mapPageStatusRideStarted;
      case 'completed':
        return l10n.mapPageStatusCompleted;
      case 'cancelled':
      case 'cancelled_by_customer':
      case 'cancelled_by_captain':
      case 'cancelled_by_admin':
        return l10n.mapPageStatusCancelled;
      case 'expired':
        return l10n.mapPageStatusExpired;
      default:
        return l10n.mapPageStatusUnknown;
    }
  }

  String _formatRouteDistance(BuildContext context, double? distanceMeters) {
    final l10n = context.l10n;
    if (distanceMeters == null || distanceMeters <= 0) {
      return l10n.mapPageRouteDistanceUnknown;
    }
    if (distanceMeters < 1000) {
      return l10n.mapPageRouteDistanceMeters(distanceMeters.round().toString());
    }
    final km = (distanceMeters / 1000);
    return l10n.mapPageRouteDistanceKilometers(
      km.toStringAsFixed(km >= 10 ? 0 : 1),
    );
  }

  String _formatRouteDuration(BuildContext context, int? durationSeconds) {
    final l10n = context.l10n;
    if (durationSeconds == null || durationSeconds <= 0) {
      return l10n.mapPageRouteDurationUnknown;
    }
    final totalMinutes = (durationSeconds / 60).ceil();
    if (totalMinutes < 60) {
      return l10n.mapPageRouteDurationMinutes(totalMinutes.toString());
    }
    final hours = totalMinutes ~/ 60;
    final minutes = totalMinutes % 60;
    if (minutes == 0) {
      return l10n.mapPageRouteDurationHours(hours.toString());
    }
    return l10n.mapPageRouteDurationHoursMinutes(
      hours.toString(),
      minutes.toString(),
    );
  }

  String _rideHeaderTitle(BuildContext context, String? rideStatus) {
    final l10n = context.l10n;
    switch (rideStatus) {
      case 'price_raise_required':
        return _t('رفع الأجرة مطلوب', 'Price raise required');
      case 'searching':
        return l10n.mapPageRideSearchingTitle;
      case 'captain_assigned':
      case 'captain_arriving':
        return l10n.mapPageRideCaptainAssignedTitle;
      case 'ride_started':
        return l10n.mapPageRideStartedTitle;
      case 'completed':
        return l10n.mapPageRideCompletedTitle;
      case 'cancelled':
      case 'cancelled_by_customer':
      case 'cancelled_by_captain':
      case 'cancelled_by_admin':
        return l10n.mapPageRideCancelledTitle;
      case 'expired':
        return l10n.mapPageRideExpiredTitle;
      default:
        // An active ride (ride != null) with an unrecognized status must never
        // fall back to the "create taxi request" title — that is the composer's
        // title and rendering it here produced two identical cards. Use a
        // neutral in-progress title instead. In normal operation a real ride
        // always carries a known status.
        return l10n.mapPageRideSearchingTitle;
    }
  }

  String _rideHeaderSubtitle(
    BuildContext context, {
    required String? rideStatus,
    required bool priceRaiseRecommended,
    required int? finalAcceptanceRemaining,
  }) {
    final l10n = context.l10n;
    switch (rideStatus) {
      case 'price_raise_required':
        return _t(
          'فشلت عدة محاولات تعيين. ارفع الأجرة لإعادة فتح البحث.',
          'Several matches failed. Raise the fare to reopen search.',
        );
      case 'searching':
        if (priceRaiseRecommended) {
          return l10n.mapPageSearchingRaiseFareHint;
        }
        if (finalAcceptanceRemaining != null) {
          return l10n.mapPageSearchingCountdownHint(
            _formatCountdown(finalAcceptanceRemaining),
          );
        }
        return l10n.mapPageSearchingCaptainSubtitle;
      case 'captain_assigned':
      case 'captain_arriving':
        return l10n.mapPageCaptainAssignedSubtitle;
      case 'ride_started':
        return l10n.mapPageRideStartedSubtitle;
      case 'completed':
        return l10n.mapPageRideCompletedSubtitle;
      case 'cancelled':
      case 'cancelled_by_customer':
      case 'cancelled_by_captain':
      case 'cancelled_by_admin':
        return l10n.mapPageRideCancelledSubtitle;
      case 'expired':
        return l10n.mapPageRideExpiredSubtitle;
      default:
        return l10n.mapPageRideRequestHeroSubtitle;
    }
  }

  String _rideStatusLabel(String? status) {
    return _localizedRideStatusLabel(status);
  }

  Color _rideStatusColor(String? status, BuildContext context) {
    switch (status) {
      case 'price_raise_required':
        return Colors.deepOrange;
      case 'searching':
        return Colors.orange;
      case 'captain_assigned':
      case 'captain_arriving':
        return Colors.lightBlue;
      case 'ride_started':
        return Colors.green;
      case 'completed':
        return Colors.teal;
      case 'cancelled':
      case 'cancelled_by_customer':
      case 'cancelled_by_captain':
      case 'cancelled_by_admin':
      case 'expired':
        return Colors.redAccent;
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  int? _eventRideId(Map<String, dynamic> data) {
    final ride = data['ride'];
    if (ride is Map) {
      return _readInt(ride['id']);
    }
    return _readInt(data['rideId']);
  }

  LatLng? _latLngFromMap(dynamic raw) {
    if (raw is! Map) return null;
    final map = Map<String, dynamic>.from(raw);

    final lat = _readDouble(map['latitude']) ?? _readDouble(map['lat']);
    final lng =
        _readDouble(map['longitude']) ??
        _readDouble(map['lng']) ??
        _readDouble(map['lon']);

    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  int? _readInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    return tryParseLocalizedInt(value);
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return tryParseLocalizedDouble(value);
  }

  String? _string(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  String _extractApiError(DioException e) {
    final l10n = context.l10n;
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        if (isTerminalAuthError(e)) {
          return l10n.mapPageSessionExpired;
        }
        switch (message) {
          case 'INVALID_TOKEN':
          case 'UNAUTHORIZED':
          case 'FORBIDDEN':
            return _t('تعذر تنفيذ الطلب.', 'Request failed.');
          case 'TAXI_ACTIVE_RIDE_EXISTS':
            return l10n.mapPageApiActiveRideExists;
          case 'TAXI_RIDE_NOT_ACCEPTING_BIDS':
            return l10n.mapPageApiRideNotAcceptingBids;
          case 'TAXI_RIDE_NOT_PRICE_RAISE_REQUIRED':
            return _t(
              'لا يمكن رفع الأجرة الآن إلا عندما تطلبها الرحلة.',
              'Fare raise is only allowed when the ride requests it.',
            );
          case 'TAXI_FARE_NOT_INCREASED':
            return _t(
              'يجب أن تكون الأجرة الجديدة أعلى من الأجرة الحالية.',
              'The new fare must be higher than the current fare.',
            );
          case 'TAXI_RIDE_FARE_RAISE_FAILED':
            return _t(
              'تعذر رفع الأجرة حالياً.',
              'Unable to raise the fare right now.',
            );
          case 'TAXI_OFFER_NOT_FOUND':
          case 'TAXI_OFFER_EXPIRED':
            return _t(
              'العرض لم يعد متاحاً.',
              'The offer is no longer available.',
            );
          case 'TAXI_ALREADY_ASSIGNED':
            return _t(
              'تم قبول عرض آخر بالفعل.',
              'Another offer was already accepted.',
            );
          case 'TAXI_CAPTAIN_NOT_AVAILABLE':
          case 'NO_CAPTAINS_AVAILABLE':
            return _t(
              'لا يوجد كباتن متاحون حالياً.',
              'No captains are available right now.',
            );
          case 'TAXI_RIDE_OUT_OF_RANGE':
            return l10n.mapPageApiRideOutOfRange;
          case 'TAXI_NO_ACTIVE_BID':
            return l10n.mapPageApiNoActiveBid;
          case 'TAXI_CHAT_EMPTY_MESSAGE':
            return l10n.mapPageApiChatEmptyMessage;
          case 'TAXI_CHAT_CLOSED':
            return l10n.mapPageApiChatClosed;
          case 'TAXI_RIDE_NOT_COMPLETED':
            return l10n.mapPageApiRideNotCompleted;
          case 'TAXI_RIDE_CAPTAIN_NOT_FOUND':
            return l10n.mapPageApiRideCaptainNotFound;
          default:
            return message;
        }
      }
    }
    return l10n.errorsServerFailure;
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final taxiSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.taxi, displayName: context.l10n.mapPageTitle);
    if (taxiSection.isBlocked) {
      return SectionUnavailableScreen(entry: taxiSection);
    }
    final ride = _ride;
    final rideStatus = _string(ride?['status']);
    final rideFare =
        _readInt(ride?['finalFare']) ??
        _readInt(ride?['agreedFareIqd']) ??
        _readInt(ride?['proposedFareIqd']);
    // القفل مصدره الخادم: بعد توجه الكابتن (captain_arriving) يصبح
    // cancellationLocked = true فيُمنع الإلغاء العادي ويظهر مخرج الطوارئ بدلاً منه.
    final rideLocked = ride?['cancellationLocked'] == true;
    final canCancel = !rideLocked &&
        (rideStatus == 'searching' ||
            rideStatus == 'price_raise_required' ||
            rideStatus == 'captain_assigned');
    final canRaiseEmergency = rideLocked ||
        rideStatus == 'captain_arriving' ||
        rideStatus == 'ride_started';
    final scheme = Theme.of(context).colorScheme;
    final canPop = Navigator.of(context).canPop();

    return Scaffold(
      key: _scaffoldKey,
      resizeToAvoidBottomInset: false,
      endDrawer: const MaslakiUserDrawer(),
      appBar: MaslakiTopBar(
        title: context.l10n.mapPageTitle,
        subtitle: context.l10n.mapPageRideRequestHeroSubtitle,
        leading: canPop
            ? IconButton(
                tooltip: context.l10n.commonBack,
                onPressed: () => Navigator.of(context).maybePop(),
                icon: const Icon(Icons.arrow_back_rounded),
              )
            : const MaslakiUserDrawerButton(),
        actions: [
          if (canPop) const MaslakiUserDrawerButton(),
          IconButton(
            tooltip: context.l10n.commonRefresh,
            onPressed: _submitting ? null : () => _loadCurrentRide(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _bismayahCenter,
              initialZoom: _initialZoom,
              backgroundColor: const Color(0xFF111A28),
              onTap: (_, point) => _onMapTap(point),
              interactionOptions: InteractionOptions(
                flags: _sheetDragInProgress
                    ? InteractiveFlag.none
                    : InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                retinaMode: false,
                userAgentPackageName: 'app.maslaki.user',
                tileProvider: NetworkTileProvider(
                  headers: {
                    'User-Agent': 'MaslakiTaxi/1.0 (+https://maslaki.app)',
                  },
                ),
                // Maslaki navy night rendering; OSM coverage remains global.
                tileBuilder: (_, tileWidget, _) => ColorFiltered(
                  colorFilter: const ColorFilter.matrix(<double>[
                    -0.197, -0.257, -0.026, 0, 139.79,
                    -0.089, -0.436, -0.030, 0, 164.37,
                    -0.103, -0.347, -0.196, 0, 194.10,
                    0, 0, 0, 1, 0,
                  ]),
                  child: tileWidget,
                ),
              ),
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('© OpenStreetMap contributors'),
                ],
              ),
              if (_routePoints.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 7,
                      color: Colors.black.withValues(alpha: 0.22),
                    ),
                    Polyline(
                      points: _routePoints,
                      strokeWidth: 4.5,
                      color: scheme.primary.withValues(alpha: 0.95),
                    ),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          if (ride != null) ...[
            Positioned(
              top: 12,
              left: 12,
              right: 12,
              child: _buildTopStatusBar(context),
            ),
            Positioned(
              left: 12,
              right: 12,
              bottom: 12,
              child: SafeArea(
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOut,
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(context).bottom,
                  ),
                  child: _buildBottomCard(
                    context,
                    ride,
                    rideStatus,
                    rideFare,
                    canCancel,
                    canRaiseEmergency,
                  ),
                ),
              ),
            ),
          ] else
            _buildRideRequestSheetV3(context),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.extended(
            heroTag: 'my_location',
            onPressed: _goToMyLocation,
            icon: _isLocating
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.my_location_rounded),
            label: Text(context.l10n.mapPageCurrentLocation),
          ),
          if (_canShareRide) ...[
            const SizedBox(height: 8),
            FloatingActionButton.small(
              heroTag: 'share_ride',
              tooltip: context.l10n.taxiShareRideFriendsTitle,
              onPressed: _openShareRideSheet,
              child: const Icon(Icons.share_location_rounded),
            ),
          ],
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];
    var zoom = _initialZoom;
    try {
      zoom = _mapController.camera.zoom;
    } catch (_) {
      // Map controller camera is not ready on first test/build frame.
    }

    if (_activeRideEnvelope == null && _nearbyCaptainMarkers.isNotEmpty) {
      final nearby = List<Map<String, dynamic>>.from(_nearbyCaptainMarkers);
      if (zoom < 14 && nearby.length > 24) {
        nearby.removeRange(24, nearby.length);
      } else if (zoom < 12 && nearby.length > 14) {
        nearby.removeRange(14, nearby.length);
      }
      for (final captain in nearby) {
        final point = _latLngFromMap(captain);
        if (point == null) continue;
        final heading = _readDouble(captain['headingDeg']) ?? 0;
        markers.add(
          Marker(
            point: point,
            width: 34,
            height: 34,
            child: Transform.rotate(
              angle: heading * 3.141592653589793 / 180,
              child: Icon(
                Icons.directions_car_filled_rounded,
                color: Theme.of(context).colorScheme.primary,
                size: 26,
              ),
            ),
          ),
        );
      }
    }

    if (_pickupPoint != null) {
      markers.add(
        Marker(
          point: _pickupPoint!,
          width: 44,
          height: 44,
          child: Icon(
            Icons.trip_origin_rounded,
            color: Theme.of(context).colorScheme.secondary,
            size: 34,
          ),
        ),
      );
    }

    if (_dropoffPoint != null) {
      markers.add(
        Marker(
          point: _dropoffPoint!,
          width: 46,
          height: 46,
          child: Icon(
            Icons.location_on_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 38,
          ),
        ),
      );
    }

    if (_captainPoint != null) {
      markers.add(
        Marker(
          point: _captainPoint!,
          width: 48,
          height: 48,
          child: Transform.rotate(
            angle: (_captainHeadingDeg ?? 0) * 3.141592653589793 / 180,
            child: Icon(
              Icons.directions_car_rounded,
              color: Theme.of(context).colorScheme.primary,
              size: 36,
            ),
          ),
        ),
      );
    }

    if (_myLocation != null) {
      markers.add(
        Marker(
          point: _myLocation!,
          width: 36,
          height: 36,
          child: Container(
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: Colors.white, width: 2),
            ),
          ),
        ),
      );
    }

    return markers;
  }

  Widget _buildTopStatusBar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rideStatus = _string(_ride?['status']);
    final priceRaiseRecommended = _priceRaiseRecommended(_ride);
    final statusLabel = _ride == null
        ? context.l10n.mapPageReadyForRequest
        : _localizedRideStatusLabel(rideStatus);
    final routeDistance = _formatRouteDistance(context, _routeDistanceMeters);
    final routeDuration = _formatRouteDuration(context, _routeDurationSeconds);
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [
            const Color(0xFF163A66).withValues(alpha: 0.97),
            const Color(0xFF0E2441).withValues(alpha: 0.92),
          ],
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  _ride == null
                      ? Icons.route_rounded
                      : Icons.local_taxi_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _rideHeaderTitle(context, rideStatus),
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _rideHeaderSubtitle(
                        context,
                        rideStatus: rideStatus,
                        priceRaiseRecommended: priceRaiseRecommended,
                        finalAcceptanceRemaining: null,
                      ),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.74),
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: _rideStatusColor(
                    rideStatus,
                    context,
                  ).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: _rideStatusColor(
                      rideStatus,
                      context,
                    ).withValues(alpha: 0.26),
                  ),
                ),
                child: Text(
                  statusLabel,
                  style: TextStyle(
                    color: _rideStatusColor(rideStatus, context),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _TaxiTopMetric(
                  icon: _streamConnected
                      ? Icons.bolt_rounded
                      : Icons.bolt_outlined,
                  label: context.l10n.mapPageRealtimeLabel,
                  value: _streamConnected
                      ? context.l10n.mapPageRealtimeConnected
                      : context.l10n.mapPageRealtimeReconnecting,
                  iconColor: _streamConnected
                      ? Colors.lightGreenAccent
                      : Colors.orangeAccent,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TaxiTopMetric(
                  icon: Icons.straighten_rounded,
                  label: context.l10n.mapPageRouteDistanceLabel,
                  value: routeDistance,
                  iconColor: scheme.secondary,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TaxiTopMetric(
                  icon: Icons.schedule_rounded,
                  label: context.l10n.mapPageRouteDurationLabel,
                  value: routeDuration,
                  iconColor: Colors.cyanAccent,
                  trailing: _routeLoading
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Resolves a human label for a pickup/dropoff point, degrading to formatted
  /// coordinates when the address text is missing but the point has real
  /// coordinates (the marker draws from those coordinates, so the summary must
  /// not read "unavailable" while a pin is on the map). Only falls back to
  /// [fallback] when there is neither a label nor coordinates.
  String _pointSummaryLabel(dynamic point, String fallback) {
    if (point is! Map) return fallback;
    final label = _string(point['label'] ?? point['addressText']);
    if (label != null) return label;
    final lat = point['latitude'];
    final lng = point['longitude'];
    if (lat is num && lng is num) {
      return '${lat.toStringAsFixed(5)}, ${lng.toStringAsFixed(5)}';
    }
    return fallback;
  }

  Widget _buildBottomCard(
    BuildContext context,
    Map<String, dynamic> ride,
    String? rideStatus,
    int? rideFare,
    bool canCancel,
    bool canRaiseEmergency,
  ) {
    final l10n = context.l10n;
    final nonAvailable = context.lt(ar: 'غير متوفر', en: 'Not available');
    final offers = _offers;
    final offerQueue = _offerQueue;
    final currentOffer = _currentOffer;
    final waitingOffers = _waitingOffers;
    final waitingBids = waitingOffers;
    final finalAcceptanceRemaining = rideStatus == 'searching'
        ? _finalAcceptanceRemainingSeconds(ride)
        : null;
    final priceRaiseRecommended = _priceRaiseRecommended(ride);
    final captain = ride['captain'] is Map
        ? Map<String, dynamic>.from(ride['captain'] as Map)
        : null;
    final vehicle = ride['vehicle'] is Map
        ? Map<String, dynamic>.from(ride['vehicle'] as Map)
        : captain?['vehicle'] is Map
        ? Map<String, dynamic>.from(captain!['vehicle'] as Map)
        : null;
    final rideId = _readInt(ride['id']);
    final isActiveRide =
        rideStatus == 'captain_assigned' ||
        rideStatus == 'captain_arriving' ||
        rideStatus == 'ride_started';
    final rideTitle = isActiveRide && rideId != null && rideId > 0
        ? l10n.mapPageActiveRideTitle('$rideId')
        : _rideHeaderTitle(context, rideStatus);
    final fareLabel = rideFare != null && rideFare > 0
        ? formatIqd(rideFare)
        : nonAvailable;

    final screenHeight = MediaQuery.sizeOf(context).height;
    final keyboardOpened = MediaQuery.viewInsetsOf(context).bottom > 0;
    final maxCardHeight = keyboardOpened
        ? screenHeight * 0.80
        : screenHeight * 0.56;

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 132, maxHeight: maxCardHeight),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topRight,
            end: Alignment.bottomLeft,
            colors: [
              Theme.of(context).colorScheme.surface.withValues(alpha: 0.97),
              const Color(0xFF15365D).withValues(alpha: 0.95),
            ],
          ),
          border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Colors.black26,
              blurRadius: 12,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: _loading
            ? const SizedBox(
                height: 130,
                child: Center(child: CircularProgressIndicator()),
              )
            : SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            rideTitle,
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: _rideStatusColor(
                              rideStatus,
                              context,
                            ).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            _rideStatusLabel(rideStatus),
                            style: TextStyle(
                              color: _rideStatusColor(rideStatus, context),
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.mapPageRideFareLabel(fareLabel),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      l10n.mapPageRidePickupSummary(
                        _pointSummaryLabel(ride['pickup'], nonAvailable),
                      ),
                    ),
                    Text(
                      l10n.mapPageRideDropoffSummary(
                        _pointSummaryLabel(ride['dropoff'], nonAvailable),
                      ),
                    ),
                    if (rideStatus == 'searching' &&
                        finalAcceptanceRemaining != null) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: priceRaiseRecommended
                              ? Colors.deepOrange.withValues(alpha: 0.12)
                              : Colors.amber.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: priceRaiseRecommended
                                ? Colors.deepOrange.withValues(alpha: 0.28)
                                : Colors.amber.withValues(alpha: 0.24),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  priceRaiseRecommended
                                      ? Icons.warning_amber_rounded
                                      : Icons.timer_outlined,
                                  color: priceRaiseRecommended
                                      ? Colors.deepOrange
                                      : Colors.amber.shade800,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    l10n.mapPageSearchingFinalAcceptanceTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  _formatCountdown(finalAcceptanceRemaining),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w900,
                                    color: priceRaiseRecommended
                                        ? Colors.deepOrange
                                        : (finalAcceptanceRemaining <= 15
                                              ? Colors.redAccent
                                              : Colors.teal),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: (finalAcceptanceRemaining / 300)
                                  .clamp(0.0, 1.0)
                                  .toDouble(),
                              minHeight: 6,
                              borderRadius: BorderRadius.circular(999),
                              backgroundColor: Colors.black12,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              priceRaiseRecommended
                                  ? l10n.mapPageSearchingRaiseFareNow
                                  : l10n.mapPageSearchingWaitBeforeRaise,
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: priceRaiseRecommended
                                    ? Colors.deepOrange
                                    : null,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (captain != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.teal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 20,
                              backgroundImage:
                                  _string(captain['profileImageUrl']) != null
                                  ? AppCachedImageProvider(
                                      _string(captain['profileImageUrl'])!,
                                    )
                                  : null,
                              child: _string(captain['profileImageUrl']) == null
                                  ? const Icon(Icons.person_rounded)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    _string(captain['fullName']) ??
                                        l10n.mapPageCaptainFallbackName,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  Text(
                                    _string(captain['phone']) ?? '-',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  Text(
                                    '${_string(captain['carMake']) ?? ''} ${_string(captain['carModel']) ?? ''} ${_readInt(captain['carYear']) ?? ''}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if ((_readDouble(captain['ratingAvg']) ?? 0) >
                                      0)
                                    Row(
                                      children: [
                                        const Icon(
                                          Icons.star_rounded,
                                          size: 14,
                                          color: Colors.amber,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          l10n.mapPageCaptainRatingLine(
                                            (_readDouble(
                                                      captain['ratingAvg'],
                                                    ) ??
                                                    0)
                                                .toStringAsFixed(1),
                                            '${_readInt(captain['ridesCount']) ?? 0}',
                                          ),
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  if (_buildIraqiTaxiPlate(
                                        captain,
                                        vehicle: vehicle,
                                      ) !=
                                      null) ...[
                                    const SizedBox(height: 6),
                                    _buildIraqiTaxiPlate(
                                      captain,
                                      vehicle: vehicle,
                                    )!,
                                  ],
                                ],
                              ),
                            ),
                            if (_string(captain['carImageUrl']) != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: CachedAppImage(
                                  imageUrl: _string(captain['carImageUrl'])!,
                                  width: 56,
                                  height: 56,
                                  fit: BoxFit.cover,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                    if (vehicle != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.08),
                          ),
                        ),
                        child: Row(
                          children: [
                            if (_string(vehicle['vehicleImage']) != null)
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: CachedAppImage(
                                  imageUrl: _string(vehicle['vehicleImage'])!,
                                  width: 58,
                                  height: 58,
                                  fit: BoxFit.cover,
                                ),
                              )
                            else
                              const Icon(Icons.directions_car_rounded),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    [
                                          _string(vehicle['vehicleMake']),
                                          _string(vehicle['vehicleModel']),
                                          _readInt(
                                            vehicle['vehicleYear'],
                                          )?.toString(),
                                        ]
                                        .whereType<String>()
                                        .where((value) => value.isNotEmpty)
                                        .join(' - '),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    [
                                          _string(vehicle['vehicleColor']),
                                          _string(vehicle['vehicleType']),
                                        ]
                                        .whereType<String>()
                                        .where((value) => value.isNotEmpty)
                                        .join(' - '),
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  if (captain == null &&
                                      _buildIraqiTaxiPlate(
                                            captain,
                                            vehicle: vehicle,
                                          ) !=
                                          null) ...[
                                    const SizedBox(height: 6),
                                    _buildIraqiTaxiPlate(
                                      captain,
                                      vehicle: vehicle,
                                    )!,
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (rideStatus == 'completed') ...[
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (_readInt(ride['captainRating']) == null)
                            FilledButton.icon(
                              onPressed: _submitting
                                  ? null
                                  : _openRideRatingDialogV2,
                              icon: const Icon(Icons.star_rate_rounded),
                              label: Text(l10n.mapPageRateTaxiRide),
                            ),
                          OutlinedButton.icon(
                            onPressed: _submitting
                                ? null
                                : _openComplaintDialog,
                            icon: const Icon(
                              Icons.report_gmailerrorred_rounded,
                            ),
                            label: Text(l10n.mapPageComplaintAction),
                          ),
                          FilledButton.tonalIcon(
                            onPressed: _submitting
                                ? null
                                : _saveCurrentAsFavoriteTrip,
                            icon: const Icon(Icons.bookmark_add_outlined),
                            label: Text(l10n.mapPageSaveAsFavoriteAction),
                          ),
                        ],
                      ),
                    ],
                    if (rideStatus == 'price_raise_required') ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.deepOrange.withValues(alpha: 0.10),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: Colors.deepOrange.withValues(alpha: 0.22),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.priority_high_rounded,
                                  color: Colors.deepOrange.shade400,
                                  size: 18,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _t(
                                      'تحتاج الرحلة إلى رفع أجرة حتى نواصل البحث.',
                                      'The ride needs a fare raise before search continues.',
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _t(
                                'بعد عدة رفضات من كباتن مختلفين، أصبح من الأفضل رفع الأجرة لإعادة فتح البحث.',
                                'After several distinct captain declines, raising the fare is recommended to reopen search.',
                              ),
                            ),
                            const SizedBox(height: 10),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: [
                                for (final extra in const [1000, 2000, 3000])
                                  FilledButton.tonalIcon(
                                    onPressed: rideFare == null
                                        ? null
                                        : _submitting
                                        ? null
                                        : () => _raiseRideFare(
                                            math.max(
                                              rideFare + extra,
                                              TaxiFarePolicy.minimumFareIqd,
                                            ),
                                          ),
                                    icon: const Icon(Icons.trending_up_rounded),
                                    label: Text(
                                      '${formatIqd((rideFare ?? TaxiFarePolicy.minimumFareIqd) + extra)} +',
                                    ),
                                  ),
                                OutlinedButton.icon(
                                  onPressed: _submitting
                                      ? null
                                      : () => _raiseRideFare(
                                          math.max(
                                            (rideFare ??
                                                    TaxiFarePolicy
                                                        .minimumFareIqd) +
                                                1000,
                                            TaxiFarePolicy.minimumFareIqd,
                                          ),
                                        ),
                                  icon: const Icon(Icons.edit_rounded),
                                  label: Text(
                                    _t('رفع الأجرة الآن', 'Raise fare now'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                    if (rideStatus == 'searching') ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              offers.isEmpty
                                  ? l10n.mapPageRideSearchingTitle
                                  : _t('العروض المتاحة', 'Available offers'),
                              style: const TextStyle(
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          if (offerQueue != null)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.indigo.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                l10n.mapPageNegotiationQueueLabel(
                                  '${_readInt(offerQueue['offerCount']) ?? offers.length}',
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      if (offers.isEmpty)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.blueGrey.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.08),
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _t(
                                  'جاري البحث عن كابتن',
                                  'Searching for captain',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${_t('من', 'From')}: ${_string(ride['pickup']?['label']) ?? nonAvailable}',
                              ),
                              Text(
                                '${_t('إلى', 'To')}: ${_string(ride['dropoff']?['label']) ?? nonAvailable}',
                              ),
                              Text(
                                '${_t('الأجرة المقترحة', 'Suggested fare')}: ${rideFare != null && rideFare > 0 ? formatIqd(rideFare) : _t('بانتظار تحديد السعر', 'Waiting for fare')}',
                              ),
                              const SizedBox(height: 6),
                              Text(
                                _t(
                                  'نرسل طلبك للكباتن القريبين...',
                                  'We are sending your request to nearby captains...',
                                ),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        )
                      else ...[
                        if (currentOffer != null)
                          Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.lightBlue.withValues(alpha: 0.09),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: Colors.lightBlue.withValues(alpha: 0.22),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.timelapse_rounded,
                                  size: 18,
                                  color: Colors.lightBlue,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _offerNegotiationLabel(currentOffer) ??
                                        _t(
                                          'بانتظار رد الكابتن',
                                          'Waiting for captain response',
                                        ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                if (_offerNegotiationCountdown(currentOffer) !=
                                    null)
                                  Text(
                                    _formatCountdown(
                                      _offerNegotiationCountdown(currentOffer)!,
                                    ),
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ...offers.map(
                          (offer) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _buildTaxiOfferCard(
                              offer,
                              nonAvailable: nonAvailable,
                              customerFareIqd:
                                  _readInt(ride['proposedFareIqd']) ??
                                  _readInt(ride['customerFare']),
                            ),
                          ),
                        ),
                        if (waitingBids.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            l10n.mapPageNegotiationWaitingCaptains(
                              '${waitingBids.length}',
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ],
                    ],
                    if (_captainPoint != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        l10n.mapPageCaptainTrackingActive,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Colors.red,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    if (captain != null) ...[
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          if (isActiveRide)
                            OutlinedButton.icon(
                              onPressed: _openRideChatBottomSheetV2,
                              icon: const Icon(Icons.chat_rounded),
                              label: Text(l10n.mapPageChatWithCaptain),
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (canCancel)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _submitting ? null : _cancelRide,
                          icon: const Icon(Icons.cancel_rounded),
                          label: Text(
                            _submitting
                                ? l10n.mapPageRideCancelling
                                : l10n.mapPageRideCancelAction,
                          ),
                        ),
                      )
                    else if (canRaiseEmergency)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _submitting ? null : _raiseRideEmergency,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                          ),
                          icon: const Icon(Icons.sos_rounded),
                          label: Text(
                            context.lt(
                              ar: 'مساعدة / حالة طارئة',
                              en: 'Help / Emergency',
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildRideComposerV2(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final canSwap = _pickupPoint != null || _dropoffPoint != null;
    final routeReady = _pickupPoint != null && _dropoffPoint != null;
    final routeDistance = _formatRouteDistance(context, _routeDistanceMeters);
    final routeDuration = _formatRouteDuration(context, _routeDurationSeconds);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.local_taxi_rounded,
                      color: scheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.mapPageRideRequestCreateTitle,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          l10n.mapPageRideRequestHeroSubtitle,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.72),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: canSwap ? _swapRideEndpoints : null,
                    icon: const Icon(Icons.swap_vert_rounded),
                    label: Text(l10n.mapPageSwapPoints),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              SegmentedButton<_PointSelectionMode>(
                segments: [
                  ButtonSegment(
                    value: _PointSelectionMode.pickup,
                    icon: const Icon(Icons.trip_origin_rounded),
                    label: Text(l10n.mapPagePickupPoint),
                  ),
                  ButtonSegment(
                    value: _PointSelectionMode.dropoff,
                    icon: const Icon(Icons.location_on_rounded),
                    label: Text(l10n.mapPageDropoffPoint),
                  ),
                ],
                selected: {_selectionMode},
                onSelectionChanged: (values) {
                  setState(() {
                    _selectionMode = values.first;
                  });
                },
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _submitting
                        ? null
                        : () => _openSavedPlacesSheet(
                            forPickup:
                                _selectionMode == _PointSelectionMode.pickup,
                          ),
                    icon: const Icon(Icons.place_outlined),
                    label: Text(l10n.mapPageSavedPlacesAction),
                  ),
                  OutlinedButton.icon(
                    onPressed: _submitting ? null : _openFavoriteTripsSheet,
                    icon: const Icon(Icons.route_outlined),
                    label: Text(l10n.mapPageFavoriteTripsAction),
                  ),
                  FilledButton.tonalIcon(
                    onPressed: _submitting ? null : _saveCurrentAsFavoriteTrip,
                    icon: const Icon(Icons.bookmark_add_outlined),
                    label: Text(l10n.mapPageSaveAsFavoriteAction),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        FormErrorBanner(message: _rideFormError),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.mapPageScheduleSectionTitle,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              SegmentedButton<_RideRequestTimingMode>(
                segments: [
                  ButtonSegment<_RideRequestTimingMode>(
                    value: _RideRequestTimingMode.now,
                    icon: const Icon(Icons.flash_on_rounded),
                    label: Text(l10n.mapPageScheduleModeNow),
                  ),
                  ButtonSegment<_RideRequestTimingMode>(
                    value: _RideRequestTimingMode.scheduled,
                    icon: const Icon(Icons.schedule_rounded),
                    label: Text(l10n.mapPageScheduleModeLater),
                  ),
                ],
                selected: {_timingMode},
                onSelectionChanged: _submitting
                    ? null
                    : (values) {
                        setState(() {
                          _timingMode = values.first;
                          if (_timingMode == _RideRequestTimingMode.now) {
                            _rideFieldErrors.remove('scheduledFor');
                          }
                        });
                      },
              ),
              if (_timingMode == _RideRequestTimingMode.scheduled) ...[
                const SizedBox(height: 10),
                _rideComposerScroll.anchor(
                  'scheduledFor',
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _rideFieldErrors.containsKey('scheduledFor')
                            ? Theme.of(context).colorScheme.error
                            : Colors.white.withValues(alpha: 0.08),
                      ),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.event_available_outlined),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _scheduledFor == null
                                ? l10n.mapPageScheduleChooseTime
                                : _formatScheduledFor(_scheduledFor!),
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: _scheduledFor == null
                                  ? Colors.white.withValues(alpha: 0.75)
                                  : null,
                            ),
                          ),
                        ),
                        FilledButton.tonal(
                          onPressed: _submitting
                              ? null
                              : _pickScheduledDateTime,
                          child: Text(l10n.mapPageSchedulePickTimeAction),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_rideFieldErrors['scheduledFor'] != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    _rideFieldErrors['scheduledFor']!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.07)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _rideComposerScroll.anchor(
                'pickupSearch',
                TextField(
                  controller: _pickupSearchController,
                  focusNode: _rideComposerScroll.focusNodeFor('pickupSearch'),
                  textInputAction: TextInputAction.next,
                  onChanged: (value) {
                    _clearRideFieldError('pickupSearch');
                    _onPickupSearchChanged(value);
                  },
                  decoration: InputDecoration(
                    labelText: l10n.mapPagePickupSearchLabel,
                    hintText: l10n.mapPagePickupSearchHint,
                    border: const OutlineInputBorder(),
                    errorText: _rideFieldErrors['pickupSearch'],
                    suffixIcon: _isSearchingPickup
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.search),
                  ),
                ),
              ),
              if (_pickupSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildSuggestionList(_pickupSuggestions, forPickup: true),
              ],
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _pickupPoint == null ? null : _confirmPickup,
                icon: Icon(
                  _pickupConfirmed
                      ? Icons.verified_rounded
                      : Icons.check_circle_rounded,
                ),
                label: Text(
                  _pickupConfirmed
                      ? l10n.mapPagePickupConfirmedLabel
                      : l10n.mapPageConfirmPickupLabel,
                ),
              ),
              const SizedBox(height: 8),
              _rideComposerScroll.anchor(
                'dropoffSearch',
                TextField(
                  controller: _dropoffSearchController,
                  focusNode: _rideComposerScroll.focusNodeFor('dropoffSearch'),
                  textInputAction: TextInputAction.next,
                  onChanged: (value) {
                    _clearRideFieldError('dropoffSearch');
                    _onDropoffSearchChanged(value);
                  },
                  decoration: InputDecoration(
                    labelText: l10n.mapPageDropoffSearchLabel,
                    hintText: l10n.mapPageDropoffSearchHint,
                    border: const OutlineInputBorder(),
                    errorText: _rideFieldErrors['dropoffSearch'],
                    suffixIcon: _isSearchingDropoff
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : const Icon(Icons.search),
                  ),
                ),
              ),
              if (_dropoffSuggestions.isNotEmpty) ...[
                const SizedBox(height: 6),
                _buildSuggestionList(_dropoffSuggestions, forPickup: false),
              ],
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
              colors: [
                Colors.white.withValues(alpha: 0.05),
                scheme.primary.withValues(alpha: 0.07),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.mapPageRouteSummaryTitle,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _TaxiTopMetric(
                      icon: Icons.straighten_rounded,
                      label: l10n.mapPageRouteDistanceLabel,
                      value: routeDistance,
                      iconColor: scheme.secondary,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TaxiTopMetric(
                      icon: Icons.schedule_rounded,
                      label: l10n.mapPageRouteDurationLabel,
                      value: routeDuration,
                      iconColor: Colors.cyanAccent,
                      trailing: _routeLoading
                          ? const SizedBox(
                              width: 12,
                              height: 12,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                routeReady
                    ? l10n.mapPageRouteReadyHint
                    : (_selectionMode == _PointSelectionMode.pickup
                          ? l10n.mapPageTapMapForPickup
                          : l10n.mapPageTapMapForDropoff),
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.74),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _rideComposerScroll.anchor(
                'pickupLabel',
                TextField(
                  controller: _pickupLabelController,
                  focusNode: _rideComposerScroll.focusNodeFor('pickupLabel'),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearRideFieldError('pickupLabel'),
                  decoration: InputDecoration(
                    labelText: l10n.mapPagePickupDescriptionLabel,
                    border: const OutlineInputBorder(),
                    errorText: _rideFieldErrors['pickupLabel'],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _rideComposerScroll.anchor(
                'dropoffLabel',
                TextField(
                  controller: _dropoffLabelController,
                  focusNode: _rideComposerScroll.focusNodeFor('dropoffLabel'),
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearRideFieldError('dropoffLabel'),
                  decoration: InputDecoration(
                    labelText: l10n.mapPageDropoffDescriptionLabel,
                    border: const OutlineInputBorder(),
                    errorText: _rideFieldErrors['dropoffLabel'],
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: _rideComposerScroll.anchor(
                'proposedFareIqd',
                TextField(
                  controller: _fareController,
                  focusNode: _rideComposerScroll.focusNodeFor(
                    'proposedFareIqd',
                  ),
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.next,
                  onChanged: (_) => _clearRideFieldError('proposedFareIqd'),
                  decoration: InputDecoration(
                    labelText: l10n.mapPageSuggestedFareLabel,
                    border: const OutlineInputBorder(),
                    errorText: _rideFieldErrors['proposedFareIqd'],
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.08),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.mapPageRouteFarePreviewLabel,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.68),
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      formatIqd(
                        tryParseLocalizedInt(_fareController.text.trim()) ?? 0,
                      ),
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        _rideComposerScroll.anchor(
          'couponCode',
          TextField(
            controller: _couponCodeController,
            focusNode: _rideComposerScroll.focusNodeFor('couponCode'),
            textInputAction: TextInputAction.next,
            onChanged: (_) => _clearRideFieldError('couponCode'),
            decoration: InputDecoration(
              labelText: l10n.taxiCouponCodeField,
              hintText: l10n.taxiCouponCodeHint,
              border: const OutlineInputBorder(),
              errorText: _rideFieldErrors['couponCode'],
              prefixIcon: const Icon(Icons.local_offer_outlined),
            ),
          ),
        ),
        const SizedBox(height: 8),
        _rideComposerScroll.anchor(
          'note',
          TextField(
            controller: _noteController,
            focusNode: _rideComposerScroll.focusNodeFor('note'),
            maxLines: 2,
            textInputAction: TextInputAction.done,
            onChanged: (_) => _clearRideFieldError('note'),
            decoration: InputDecoration(
              labelText: l10n.mapPageCaptainNoteLabel,
              border: const OutlineInputBorder(),
              errorText: _rideFieldErrors['note'],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              _error!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        FilledButton.icon(
          onPressed: _submitting ? null : _createRide,
          icon: _submitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.local_taxi_rounded),
          label: Text(
            _submitting
                ? l10n.mapPageRideRequestSubmitting
                : (_timingMode == _RideRequestTimingMode.scheduled
                      ? l10n.mapPageScheduleRideSubmit
                      : l10n.mapPageRideRequestSubmit),
          ),
        ),
      ],
    );
  }

  Widget _buildRideRequestSheetV3(BuildContext context) {
    final l10n = context.l10n;
    final estimate = _fareEstimate;
    final parsedFare = tryParseLocalizedInt(_fareController.text.trim());
    final farePreview = parsedFare ?? estimate.suggestedIqd;
    final fareTooLow =
        parsedFare != null && parsedFare < TaxiFarePolicy.minimumFareIqd;
    final fareBelowSuggested =
        parsedFare != null &&
        parsedFare >= TaxiFarePolicy.minimumFareIqd &&
        parsedFare < estimate.lowIqd;
    final isScheduledValid =
        _timingMode == _RideRequestTimingMode.now ||
        (_scheduledFor != null &&
            _scheduledFor!.isAfter(
              DateTime.now().add(const Duration(minutes: 1)),
            ));
    final canSubmit =
        _pickupConfirmed &&
        _dropoffPoint != null &&
        isScheduledValid &&
        parsedFare != null &&
        parsedFare >= TaxiFarePolicy.minimumFareIqd &&
        !_submitting;
    final inPickupSearch = _requestStep == TaxiRequestStep.pickupSearch;
    final inPickupConfirm = _requestStep == TaxiRequestStep.pickupConfirm;
    final inDropoffConfirm = _requestStep == TaxiRequestStep.dropoffConfirm;
    final inSummary = _requestStep == TaxiRequestStep.summaryAndSubmit;
    final showFareComposer = _pickupConfirmed && _dropoffPoint != null;
    final showRouteMetrics =
        showFareComposer &&
        parsedFare != null &&
        parsedFare >= TaxiFarePolicy.minimumFareIqd;

    Widget buildSearchBlock() {
      final forPickup = inPickupSearch || inPickupConfirm;
      final label = forPickup
          ? l10n.mapPagePickupSearchLabel
          : l10n.mapPageDropoffSearchLabel;
      final hint = forPickup
          ? l10n.mapPagePickupSearchHint
          : l10n.mapPageDropoffSearchHint;
      final selectedText = forPickup
          ? _pickupSearchController.text.trim()
          : _dropoffSearchController.text.trim();

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: _submitting
                ? null
                : () => _openContextLocationSearch(forPickup: forPickup),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.search_rounded),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      selectedText.isEmpty ? hint : selectedText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: selectedText.isEmpty
                            ? Colors.white.withValues(alpha: 0.7)
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (inPickupConfirm || inDropoffConfirm) ...[
            const SizedBox(height: 8),
            Text(
              inPickupConfirm
                  ? l10n.mapPageTapMapForPickup
                  : l10n.mapPageTapMapForDropoff,
              style: TextStyle(
                fontSize: 12,
                color: Colors.white.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            setState(() {
                              _requestStep = forPickup
                                  ? TaxiRequestStep.pickupSearch
                                  : TaxiRequestStep.dropoffSearch;
                            });
                          },
                    child: Text(l10n.commonBack),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _submitting
                        ? null
                        : () {
                            if (forPickup) {
                              _confirmPickup();
                            } else {
                              _confirmDropoff();
                            }
                          },
                    child: Text(
                      forPickup
                          ? l10n.mapPageConfirmPickupLabel
                          : l10n.mapPageConfirmDropoffLabel,
                    ),
                  ),
                ),
              ],
            ),
            if (!forPickup && _pickupPoint != null) ...[
              const SizedBox(height: 6),
              TextButton.icon(
                onPressed: _submitting
                    ? null
                    : () {
                        setState(() {
                          _requestStep = TaxiRequestStep.pickupConfirm;
                        });
                      },
                icon: const Icon(Icons.edit_location_alt_outlined),
                label: Text(l10n.mapPagePickupPoint),
              ),
            ],
          ],
        ],
      );
    }

    return Align(
      alignment: Alignment.bottomCenter,
      child: NotificationListener<DraggableScrollableNotification>(
        onNotification: _handleSheetExtentNotification,
        child: DraggableScrollableSheet(
          controller: _requestSheetController,
          initialChildSize: _sheetSizeForStage(_sheetStage),
          minChildSize: _sheetSizeForStage(TaxiSheetStage.collapsed),
          maxChildSize: _sheetSizeForStage(TaxiSheetStage.expanded),
          expand: false,
          snap: true,
          snapSizes: <double>[
            _sheetSizeForStage(TaxiSheetStage.collapsed),
            _sheetSizeForStage(TaxiSheetStage.half),
            _sheetSizeForStage(TaxiSheetStage.expanded),
          ],
          builder: (context, scrollController) {
            return Container(
              decoration: BoxDecoration(
                color: Theme.of(
                  context,
                ).colorScheme.surface.withValues(alpha: 0.97),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(22),
                ),
                border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black26,
                    blurRadius: 18,
                    offset: Offset(0, -6),
                  ),
                ],
              ),
              child: CustomScrollView(
                controller: scrollController,
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(
                        14,
                        10,
                        14,
                        14 +
                            MediaQuery.viewInsetsOf(context).bottom +
                            MediaQuery.paddingOf(context).bottom,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Center(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(999),
                              onTap: () {
                                final next = switch (_sheetStage) {
                                  TaxiSheetStage.collapsed =>
                                    TaxiSheetStage.half,
                                  TaxiSheetStage.half =>
                                    TaxiSheetStage.expanded,
                                  TaxiSheetStage.expanded =>
                                    TaxiSheetStage.collapsed,
                                };
                                _setSheetStage(next);
                              },
                              child: Container(
                                width: 48,
                                height: 24,
                                alignment: Alignment.center,
                                child: Container(
                                  width: 36,
                                  height: 4,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.4),
                                    borderRadius: BorderRadius.circular(999),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          FormErrorBanner(message: _rideFormError),
                          if (_pickupPoint != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.trip_origin_rounded),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          l10n.mapPagePickupPoint,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _pickupSearchController.text
                                                  .trim()
                                                  .isNotEmpty
                                              ? _pickupSearchController.text
                                                    .trim()
                                              : _pickupLabelController.text
                                                    .trim(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _submitting
                                        ? null
                                        : _startPickupEdit,
                                    child: Text(l10n.commonEdit),
                                  ),
                                  IconButton(
                                    tooltip: l10n.mapPageCurrentLocation,
                                    onPressed: _submitting
                                        ? null
                                        : () => _goToMyLocation(
                                            setAsPickupIfEmpty: true,
                                          ),
                                    icon: const Icon(Icons.my_location_rounded),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_dropoffPoint != null) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.location_on_rounded),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        Text(
                                          l10n.mapPageDropoffPoint,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w800,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          _dropoffSearchController.text
                                                  .trim()
                                                  .isNotEmpty
                                              ? _dropoffSearchController.text
                                                    .trim()
                                              : _dropoffLabelController.text
                                                    .trim(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  TextButton(
                                    onPressed: _submitting
                                        ? null
                                        : _startDropoffEdit,
                                    child: Text(l10n.commonEdit),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (_timingMode ==
                              _RideRequestTimingMode.scheduled) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    l10n.mapPageScheduleSectionTitle,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 8),
                                  FilledButton.tonalIcon(
                                    onPressed: _submitting
                                        ? null
                                        : _pickScheduledDateTime,
                                    icon: const Icon(
                                      Icons.event_available_outlined,
                                    ),
                                    label: Text(
                                      _scheduledFor == null
                                          ? l10n.mapPageScheduleChooseTime
                                          : _formatScheduledFor(_scheduledFor!),
                                    ),
                                  ),
                                  if (_rideFieldErrors['scheduledFor'] !=
                                      null) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      _rideFieldErrors['scheduledFor']!,
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                          ],
                          if (!inSummary) buildSearchBlock(),
                          if (inSummary) ...[
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.09),
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    l10n.mapPageSuggestedFareLabel,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 10),
                                  TextField(
                                    controller: _fareController,
                                    keyboardType: TextInputType.number,
                                    onChanged: (_) =>
                                        _clearRideFieldError('proposedFareIqd'),
                                    decoration: InputDecoration(
                                      labelText: l10n.mapPageSuggestedFareLabel,
                                      hintText: formatIqd(
                                        estimate.suggestedIqd,
                                      ),
                                      border: const OutlineInputBorder(),
                                      errorText:
                                          _rideFieldErrors['proposedFareIqd'],
                                      suffixIcon: parsedFare == null
                                          ? IconButton(
                                              tooltip: l10n.commonApply,
                                              onPressed: _submitting
                                                  ? null
                                                  : _applySuggestedFare,
                                              icon: const Icon(
                                                Icons.bolt_rounded,
                                              ),
                                            )
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Wrap(
                                    alignment: WrapAlignment.spaceBetween,
                                    crossAxisAlignment:
                                        WrapCrossAlignment.center,
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      Text(
                                        '${l10n.mapPageRouteFarePreviewLabel}: ${formatIqd(farePreview)}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.74,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      if (parsedFare == null)
                                        TextButton.icon(
                                          onPressed: _submitting
                                              ? null
                                              : _applySuggestedFare,
                                          icon: const Icon(
                                            Icons.auto_fix_high_rounded,
                                            size: 16,
                                          ),
                                          label: Text(
                                            formatIqd(estimate.suggestedIqd),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (fareBelowSuggested) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      l10n.mapPageFareMayReduceAcceptance,
                                      style: TextStyle(
                                        color: Colors.amberAccent.shade100,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ],
                                  if (fareTooLow) ...[
                                    const SizedBox(height: 6),
                                    Text(
                                      l10n.validationMinValue(
                                        TaxiFarePolicy.minimumFareIqd
                                            .toString(),
                                      ),
                                      style: TextStyle(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.error,
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                  if (showRouteMetrics) ...[
                                    const SizedBox(height: 10),
                                    Text(
                                      l10n.mapPageRouteSummaryTitle,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Row(
                                      children: [
                                        Expanded(
                                          child: _TaxiTopMetric(
                                            icon: Icons.straighten_rounded,
                                            label:
                                                l10n.mapPageRouteDistanceLabel,
                                            value: _formatRouteDistance(
                                              context,
                                              _routeDistanceMeters,
                                            ),
                                            iconColor: Colors.cyanAccent,
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: _TaxiTopMetric(
                                            icon: Icons.schedule_rounded,
                                            label:
                                                l10n.mapPageRouteDurationLabel,
                                            value: _formatRouteDuration(
                                              context,
                                              _routeDurationSeconds,
                                            ),
                                            iconColor: Colors.lightGreenAccent,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                  if (_couponCodeController.text
                                      .trim()
                                      .isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: Text(
                                        '${l10n.taxiCouponCodeField}: ${_couponCodeController.text.trim()}',
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.72,
                                          ),
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            FilledButton.icon(
                              onPressed: canSubmit ? _createRide : null,
                              icon: _submitting
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(Icons.local_taxi_rounded),
                              label: Text(
                                _submitting
                                    ? l10n.mapPageRideRequestSubmitting
                                    : (_timingMode ==
                                              _RideRequestTimingMode.scheduled
                                          ? l10n.mapPageScheduleRideSubmit
                                          : l10n.mapPageRideRequestSubmit),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSuggestionList(
    List<_PlaceSuggestion> items, {
    required bool forPickup,
  }) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 170),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: Colors.black.withValues(alpha: 0.08),
      ),
      child: ListView.separated(
        shrinkWrap: true,
        itemCount: items.length,
        separatorBuilder: (_, _) =>
            Divider(height: 1, color: Colors.white.withValues(alpha: 0.12)),
        itemBuilder: (context, index) {
          final place = items[index];
          return ListTile(
            dense: true,
            leading: const Icon(Icons.place_rounded),
            title: Text(
              place.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
            subtitle: Text(
              place.fullAddress,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            onTap: () => _selectPlaceSuggestion(place, forPickup: forPickup),
          );
        },
      ),
    );
  }
}

class _IraqiPlateBadge extends StatelessWidget {
  final String? city;
  final String? category;
  final String? letter;
  final String digits;

  const _IraqiPlateBadge({
    required this.city,
    required this.category,
    required this.letter,
    required this.digits,
  });

  @override
  Widget build(BuildContext context) {
    final cleanDigits = digits.trim();
    final cleanLetter = (letter ?? '').trim();
    final cleanCity = (city ?? '').trim();
    final cleanCategory = (category ?? '').trim();
    final displayDigits = cleanDigits.split('').join(' ');

    return Container(
      width: 168,
      height: 78,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          Container(
            width: 28,
            color: Colors.white,
            alignment: Alignment.center,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const RotatedBox(
                  quarterTurns: 3,
                  child: Text(
                    'IRAQ',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 12,
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Icon(Icons.crop_square, color: Colors.blue.shade700, size: 8),
              ],
            ),
          ),
          Container(width: 1.4, color: Colors.black),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 7),
                    child: Row(
                      textDirection: TextDirection.ltr,
                      children: [
                        SizedBox(
                          width: 34,
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                cleanLetter.isEmpty ? '-' : cleanLetter,
                                maxLines: 1,
                                textDirection: TextDirection.rtl,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 27,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                        Expanded(
                          child: Center(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: Text(
                                displayDigits,
                                maxLines: 1,
                                textDirection: TextDirection.ltr,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 28,
                                  fontWeight: FontWeight.w900,
                                  letterSpacing: 0,
                                  height: 1,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                Container(height: 1.4, color: Colors.black),
                SizedBox(
                  height: 27,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerRight,
                            child: Text(
                              cleanCity,
                              maxLines: 1,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              cleanCategory,
                              maxLines: 1,
                              textDirection: TextDirection.rtl,
                              style: const TextStyle(
                                color: Colors.black,
                                fontSize: 14,
                                fontWeight: FontWeight.w900,
                                letterSpacing: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceSuggestion {
  final double latitude;
  final double longitude;
  final String title;
  final String fullAddress;
  final String? kind;

  const _PlaceSuggestion({
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.fullAddress,
    this.kind,
  });
}

class _NominatimSearchPlan {
  final String query;
  final String viewbox;
  final bool bounded;
  final int limit;

  const _NominatimSearchPlan({
    required this.query,
    required this.viewbox,
    required this.bounded,
    required this.limit,
  });
}

class _TaxiTopMetric extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color iconColor;
  final Widget? trailing;

  const _TaxiTopMetric({
    required this.icon,
    required this.label,
    required this.value,
    required this.iconColor,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 18, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.62),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ],
      ),
    );
  }
}

class _TaxiLocationSearchResult {
  const _TaxiLocationSearchResult({
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.address,
  });

  final double latitude;
  final double longitude;
  final String title;
  final String address;
}

class _TaxiLocationSearchPage extends StatefulWidget {
  const _TaxiLocationSearchPage({
    required this.title,
    required this.hintText,
    this.initialQuery = '',
  });

  final String title;
  final String hintText;
  final String initialQuery;

  @override
  State<_TaxiLocationSearchPage> createState() =>
      _TaxiLocationSearchPageState();
}

class _TaxiLocationSearchPageState extends State<_TaxiLocationSearchPage> {
  late final TextEditingController _queryController = TextEditingController(
    text: widget.initialQuery,
  );
  late final Dio _searchDio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 8),
      receiveTimeout: const Duration(seconds: 8),
      headers: {
        'User-Agent': 'MaslakiTaxi/1.0 (support@maslaki.app)',
        'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.8',
      },
    ),
  );
  Timer? _debounce;
  bool _loading = false;
  String? _error;
  List<_TaxiLocationSearchResult> _results = const [];

  @override
  void initState() {
    super.initState();
    if (_queryController.text.trim().isNotEmpty) {
      _search(_queryController.text.trim());
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _queryController.dispose();
    _searchDio.close(force: true);
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 650), () {
      _search(value.trim());
    });
  }

  Future<void> _search(String query) async {
    if (query.length < 2) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _results = const [];
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final items = await _fetchResults(query);

      if (!mounted) return;
      if (_queryController.text.trim() != query) return;
      setState(() {
        _results = items;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.l10n.errorsServerFailure;
      });
    }
  }

  Future<List<_TaxiLocationSearchResult>> _fetchResults(String query) async {
    final results = <_TaxiLocationSearchResult>[];
    final seen = <String>{};
    for (final variant in _queryVariants(query)) {
      final Response<dynamic> response;
      try {
        response = await _searchDio.get(
          'https://nominatim.openstreetmap.org/search',
          queryParameters: {
            'format': 'jsonv2',
            'addressdetails': 1,
            'extratags': 1,
            'namedetails': 1,
            'dedupe': 1,
            'polygon_geojson': 0,
            'countrycodes': 'iq',
            'bounded': 0,
            'viewbox': '38.79,37.39,48.58,29.06',
            'limit': 12,
            'q': variant,
          },
        );
      } catch (_) {
        continue;
      }
      final raw = response.data is List ? response.data as List : const [];
      for (final result
          in raw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .map(_resultFromNominatim)
              .whereType<_TaxiLocationSearchResult>()) {
        final key =
            '${result.latitude.toStringAsFixed(5)},'
            '${result.longitude.toStringAsFixed(5)}:'
            '${result.title.toLowerCase()}';
        if (seen.add(key)) {
          results.add(result);
          if (results.length >= 16) return results;
        }
      }
      if (results.length >= 8) return results;
    }
    return results;
  }

  List<String> _queryVariants(String query) {
    final variants = <String>[];
    void add(String value) {
      final cleaned = value.trim().replaceAll(RegExp(r'\s+'), ' ');
      if (cleaned.isNotEmpty &&
          !variants.any(
            (item) => item.toLowerCase() == cleaned.toLowerCase(),
          )) {
        variants.add(cleaned);
      }
    }

    add(query);
    add('$query العراق');
    add('$query Iraq');
    final normalized = query.toLowerCase();
    if (normalized.contains('كلية') || normalized.contains('جامعة')) {
      add('$query university Iraq');
      add('$query college Iraq');
    }
    if (normalized.contains('مدرسة') || normalized.contains('إعدادية')) {
      add('$query school Iraq');
    }
    if (normalized.contains('جامع') || normalized.contains('مسجد')) {
      add('$query mosque Iraq');
    }
    if (normalized.contains('شارع') || normalized.contains('طريق')) {
      add('$query street Iraq');
      add('$query road Iraq');
    }
    if (normalized.contains('منطقة') || normalized.contains('حي')) {
      add('$query neighborhood Iraq');
    }
    return variants;
  }

  _TaxiLocationSearchResult? _resultFromNominatim(Map<String, dynamic> item) {
    final lat = double.tryParse('${item['lat'] ?? ''}');
    final lng = double.tryParse('${item['lon'] ?? ''}');
    final address = '${item['display_name'] ?? ''}'.trim();
    if (lat == null || lng == null || address.isEmpty) return null;
    final namedetails = item['namedetails'] is Map
        ? Map<String, dynamic>.from(item['namedetails'] as Map)
        : const <String, dynamic>{};
    final preferredName =
        <dynamic>[namedetails['name:ar'], namedetails['name'], item['name']]
            .map((value) => '${value ?? ''}'.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    return _TaxiLocationSearchResult(
      latitude: lat,
      longitude: lng,
      title: preferredName.isNotEmpty
          ? preferredName
          : _shortAddressTitle(address),
      address: address,
    );
  }

  String _shortAddressTitle(String address) {
    final parts = address
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return address;
    if (parts.length == 1) return parts.first;
    return '${parts[0]} - ${parts[1]}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: TextField(
              controller: _queryController,
              textInputAction: TextInputAction.search,
              onChanged: _onQueryChanged,
              decoration: InputDecoration(
                labelText: widget.title,
                hintText: widget.hintText,
                border: const OutlineInputBorder(),
                suffixIcon: _loading
                    ? const Padding(
                        padding: EdgeInsets.all(10),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.error,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          Expanded(
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _results[index];
                return ListTile(
                  leading: const Icon(Icons.place_outlined),
                  title: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.address,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () => Navigator.of(context).pop(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
