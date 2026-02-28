import 'dart:async';

import 'package:bestoffer/features/auth/state/auth_controller.dart';
import 'package:bestoffer/features/taxi/data/taxi_api.dart';
import 'package:bestoffer/features/taxi/data/taxi_route_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum _PointSelectionMode { pickup, dropoff }

final taxiApiProvider = Provider<TaxiApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return TaxiApi(dio);
});

final taxiRouteServiceProvider = Provider<TaxiRouteService>((ref) {
  return TaxiRouteService();
});

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  static const LatLng _bismayahCenter = LatLng(33.3128, 44.3615);
  static const double _initialZoom = 15;

  final MapController _mapController = MapController();
  final TextEditingController _pickupLabelController = TextEditingController(
    text: 'موقعي الحالي',
  );
  final TextEditingController _dropoffLabelController = TextEditingController();
  final TextEditingController _pickupSearchController = TextEditingController();
  final TextEditingController _dropoffSearchController =
      TextEditingController();
  final TextEditingController _fareController = TextEditingController(
    text: '10000',
  );
  final TextEditingController _noteController = TextEditingController();

  StreamSubscription<TaxiLiveEvent>? _streamSub;
  Timer? _reconnectTimer;
  Timer? _pickupSearchDebounce;
  Timer? _dropoffSearchDebounce;

  _PointSelectionMode _selectionMode = _PointSelectionMode.pickup;
  LatLng? _pickupPoint;
  LatLng? _dropoffPoint;
  LatLng? _captainPoint;
  LatLng? _myLocation;

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
  DateTime? _lastRealtimeAt;
  DateTime? _lastRouteAt;
  String? _error;
  List<_PlaceSuggestion> _pickupSuggestions = const [];
  List<_PlaceSuggestion> _dropoffSuggestions = const [];
  List<LatLng> _routePoints = const [];
  LatLng? _lastRouteFrom;
  LatLng? _lastRouteTo;

  TaxiApi get _taxiApi => ref.read(taxiApiProvider);
  TaxiRouteService get _routeService => ref.read(taxiRouteServiceProvider);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _bootstrap();
    });
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _reconnectTimer?.cancel();
    _pickupSearchDebounce?.cancel();
    _dropoffSearchDebounce?.cancel();
    _pickupLabelController.dispose();
    _dropoffLabelController.dispose();
    _pickupSearchController.dispose();
    _dropoffSearchController.dispose();
    _fareController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    final auth = ref.read(authControllerProvider);
    if (!auth.isAuthed) {
      setState(() {
        _loading = false;
        _canUseTaxiApi = false;
        _error = 'يرجى تسجيل الدخول أولًا لاستخدام خدمة التكسي';
      });
      return;
    }
    if (auth.isBackoffice || auth.isOwner || auth.isDelivery) {
      setState(() {
        _loading = false;
        _canUseTaxiApi = false;
        _error = 'خدمة التكسي متاحة لحسابات الزبائن فقط';
      });
      return;
    }

    await Future.wait([
      _goToMyLocation(setAsPickupIfEmpty: true),
      _loadCurrentRide(),
    ]);
    if (_canUseTaxiApi) _connectRealtimeStream();
  }

  Future<void> _loadCurrentRide({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      final envelope = await _taxiApi.getCurrentRideForCustomer();
      if (!mounted) return;

      _activeRideEnvelope = envelope;
      _syncMapFromRideEnvelope();

      setState(() {
        _loading = false;
      });
    } on DioException catch (e) {
      if (!mounted) return;
      if (_isUnauthorizedStatus(e.response?.statusCode)) {
        _canUseTaxiApi = false;
        _streamSub?.cancel();
      }
      setState(() {
        _loading = false;
        _error = _extractApiError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحميل بيانات الرحلة الحالية';
      });
    }
  }

  void _syncMapFromRideEnvelope() {
    final ride = _ride;
    if (ride == null) {
      _captainPoint = null;
      _routePoints = const [];
      _lastRouteFrom = null;
      _lastRouteTo = null;
      _lastRouteAt = null;
      return;
    }

    final pickup = _latLngFromMap(ride['pickup']);
    final dropoff = _latLngFromMap(ride['dropoff']);
    final latest = _latLngFromMap(_activeRideEnvelope?['latestLocation']);

    if (pickup != null) {
      _pickupPoint = pickup;
      if (_pickupLabelController.text.trim().isEmpty) {
        _pickupLabelController.text =
            _string(ride['pickup']?['label']) ?? 'نقطة الانطلاق';
      }
    }

    if (dropoff != null) {
      _dropoffPoint = dropoff;
      if (_dropoffLabelController.text.trim().isEmpty) {
        _dropoffLabelController.text =
            _string(ride['dropoff']?['label']) ?? 'نقطة الوصول';
      }
    }

    _captainPoint = latest;

    final target = _captainPoint ?? _pickupPoint ?? _dropoffPoint;
    if (target != null) {
      _mapController.move(target, 15.8);
    }

    _refreshRoutePolyline();
  }

  void _connectRealtimeStream() {
    if (!_canUseTaxiApi) return;
    _streamSub?.cancel();
    _streamSub = _taxiApi.streamEvents().listen(
      (event) {
        if (event.event == 'heartbeat' || event.event == 'connected') {
          if (!mounted) return;
          setState(() {
            _streamConnected = true;
            _lastRealtimeAt = DateTime.now();
          });
          return;
        }

        final rideId = _eventRideId(event.data);
        final activeRideId = _readInt(_ride?['id']);

        if (activeRideId == null || rideId == null || activeRideId == rideId) {
          _lastRealtimeAt = DateTime.now();
          _loadCurrentRide(silent: true);
        }
      },
      onError: (error) {
        if (!mounted) return;
        final unauthorized = _isUnauthorizedDioError(error);
        setState(() {
          _streamConnected = false;
          if (unauthorized) {
            _error = 'انتهت الجلسة، يرجى تسجيل الدخول مرة أخرى';
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

  void _scheduleReconnect() {
    if (!_canUseTaxiApi) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _connectRealtimeStream();
    });
  }

  Future<void> _refreshRoutePolyline({bool force = false}) async {
    final routeTarget = _resolveRouteTarget();
    if (routeTarget == null) {
      if (_routePoints.isNotEmpty && mounted) {
        setState(() => _routePoints = const []);
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
      final points = await _routeService.fetchDrivingRoute(from: from, to: to);
      if (!mounted) return;
      setState(() {
        _routePoints = points;
        _lastRouteFrom = from;
        _lastRouteTo = to;
        _lastRouteAt = now;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _routePoints = [from, to];
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
              headers: const {
                'User-Agent': 'BestOfferTaxi/1.0 (support@bestoffer.app)',
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

  bool _isUnauthorizedStatus(int? statusCode) {
    return statusCode == 401 || statusCode == 403;
  }

  bool _isUnauthorizedDioError(Object error) {
    if (error is! DioException) return false;
    return _isUnauthorizedStatus(error.response?.statusCode);
  }

  Future<void> _goToMyLocation({bool setAsPickupIfEmpty = false}) async {
    if (_isLocating) return;

    setState(() => _isLocating = true);
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        _showMessage('يرجى تشغيل خدمة الموقع في الجهاز');
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        _showMessage('تم رفض إذن الوصول إلى الموقع');
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
          _pickupConfirmed = false;
        }
      });

      _mapController.move(point, 16.5);
      if (setAsPickupIfEmpty && _activeRideEnvelope == null) {
        unawaited(_reverseGeocodeAndFill(point: point, forPickup: true));
      }
      unawaited(_refreshRoutePolyline());
    } catch (_) {
      _showMessage('تعذر تحديد موقعك الحالي');
    } finally {
      if (mounted) setState(() => _isLocating = false);
    }
  }

  void _onPickupSearchChanged(String query) {
    _pickupSearchDebounce?.cancel();
    _pickupSearchDebounce = Timer(const Duration(milliseconds: 380), () {
      _searchPlaces(query, forPickup: true);
    });
  }

  void _onDropoffSearchChanged(String query) {
    _dropoffSearchDebounce?.cancel();
    _dropoffSearchDebounce = Timer(const Duration(milliseconds: 380), () {
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

    setState(() {
      if (forPickup) {
        _isSearchingPickup = true;
      } else {
        _isSearchingDropoff = true;
      }
    });

    try {
      final response =
          await Dio(
            BaseOptions(
              connectTimeout: const Duration(seconds: 8),
              receiveTimeout: const Duration(seconds: 8),
              headers: const {
                'User-Agent': 'BestOfferTaxi/1.0 (support@bestoffer.app)',
                'Accept-Language': 'ar-IQ,ar;q=0.9,en;q=0.8',
              },
            ),
          ).get(
            'https://nominatim.openstreetmap.org/search',
            queryParameters: {
              'format': 'jsonv2',
              'addressdetails': 1,
              'dedupe': 1,
              'polygon_geojson': 0,
              'countrycodes': 'iq',
              'bounded': 1,
              'viewbox': '44.62,33.48,44.15,33.10',
              'limit': 10,
              'q': query,
            },
          );

      final list = response.data is List ? response.data as List : const [];
      final items = list
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .map((item) {
            final lat = double.tryParse('${item['lat'] ?? ''}');
            final lon = double.tryParse('${item['lon'] ?? ''}');
            final label = '${item['display_name'] ?? ''}'.trim();
            if (lat == null || lon == null || label.isEmpty) return null;
            return _PlaceSuggestion(
              latitude: lat,
              longitude: lon,
              title: _shortPlaceLabel(label),
              fullAddress: label,
            );
          })
          .whereType<_PlaceSuggestion>()
          .toList();

      if (!mounted) return;
      final stillSameQuery =
          (forPickup
                  ? _pickupSearchController.text
                  : _dropoffSearchController.text)
              .trim();
      if (stillSameQuery != query) return;

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
        _pickupConfirmed = false;
        _selectionMode = _PointSelectionMode.pickup;
      } else {
        _dropoffPoint = selectedPoint;
        _dropoffLabelController.text = place.title;
        _dropoffSearchController.text = place.title;
        _dropoffSuggestions = const [];
      }
    });
    _mapController.move(selectedPoint, 16.4);
    unawaited(_refreshRoutePolyline());
  }

  void _confirmPickup() {
    if (_pickupPoint == null) {
      _showMessage('حدد نقطة الانطلاق أولاً');
      return;
    }
    setState(() {
      _pickupConfirmed = true;
      _selectionMode = _PointSelectionMode.dropoff;
    });
    _showMessage('تم تأكيد الانطلاق. الآن حدد نقطة الوصول');
  }

  Future<void> _createRide() async {
    if (_submitting) return;

    if (_pickupPoint == null || _dropoffPoint == null) {
      _showMessage('حدد نقطة الانطلاق ونقطة الوصول');
      return;
    }

    if (!_pickupConfirmed) {
      _showMessage('يجب تأكيد نقطة الانطلاق قبل الإرسال');
      return;
    }

    final fare = int.tryParse(_fareController.text.trim());
    if (fare == null || fare < 0) {
      _showMessage('ادخل سعرًا صحيحًا بالأرقام');
      return;
    }

    final pickupLabel = _pickupLabelController.text.trim();
    final dropoffLabel = _dropoffLabelController.text.trim();

    if (pickupLabel.isEmpty || dropoffLabel.isEmpty) {
      _showMessage('يرجى كتابة وصف واضح لنقطتي الانطلاق والوصول');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _taxiApi.createRide(
        pickupLatitude: _pickupPoint!.latitude,
        pickupLongitude: _pickupPoint!.longitude,
        dropoffLatitude: _dropoffPoint!.latitude,
        dropoffLongitude: _dropoffPoint!.longitude,
        pickupLabel: pickupLabel,
        dropoffLabel: dropoffLabel,
        proposedFareIqd: fare,
        note: _noteController.text.trim().isEmpty
            ? null
            : _noteController.text.trim(),
      );

      await _loadCurrentRide(silent: true);
      _showMessage('تم إرسال طلب التكسي بنجاح');
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = 'تعذر إرسال الطلب حالياً';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _cancelRide() async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _taxiApi.cancelRide(rideId);
      await _loadCurrentRide(silent: true);
      _captainPoint = null;
      _routePoints = const [];
      _lastRouteFrom = null;
      _lastRouteTo = null;
      _lastRouteAt = null;
      _showMessage('تم إلغاء الرحلة');
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = 'تعذر إلغاء الرحلة حالياً';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _acceptBid(int bidId) async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null || _submitting) return;

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      await _taxiApi.acceptBid(rideId: rideId, bidId: bidId);
      await _loadCurrentRide(silent: true);
      _showMessage('تم قبول عرض الكابتن');
    } on DioException catch (e) {
      setState(() {
        _error = _extractApiError(e);
      });
    } catch (_) {
      setState(() {
        _error = 'تعذر قبول العرض حالياً';
      });
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _createShareToken() async {
    final rideId = _readInt(_ride?['id']);
    if (rideId == null) return;

    try {
      final out = await _taxiApi.createShareToken(rideId);
      final token = _string(out['token']) ?? '';
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            token.isEmpty
                ? 'تم إنشاء رابط مشاركة التتبع'
                : 'رمز التتبع: $token',
          ),
          duration: const Duration(seconds: 6),
        ),
      );
    } on DioException catch (e) {
      _showMessage(_extractApiError(e));
    } catch (_) {
      _showMessage('تعذر إنشاء رابط التتبع الآن');
    }
  }

  void _onMapTap(LatLng point) {
    if (_activeRideEnvelope != null) {
      _showMessage('لديك رحلة نشطة حالياً، لا يمكن تعديل النقاط الآن');
      return;
    }

    final forPickup = _selectionMode == _PointSelectionMode.pickup;
    setState(() {
      if (forPickup) {
        _pickupPoint = point;
        _pickupConfirmed = false;
        if (_pickupLabelController.text.trim().isEmpty) {
          _pickupLabelController.text = 'نقطة الانطلاق';
        }
      } else {
        _dropoffPoint = point;
        if (_dropoffLabelController.text.trim().isEmpty) {
          _dropoffLabelController.text = 'نقطة الوصول';
        }
      }
    });

    unawaited(_reverseGeocodeAndFill(point: point, forPickup: forPickup));
    unawaited(_refreshRoutePolyline());
  }

  Map<String, dynamic>? get _ride {
    final envelope = _activeRideEnvelope;
    if (envelope == null) return null;
    final ride = envelope['ride'];
    if (ride is Map) {
      return Map<String, dynamic>.from(ride);
    }
    return null;
  }

  List<Map<String, dynamic>> get _bids {
    final envelope = _activeRideEnvelope;
    if (envelope == null) return const [];
    final raw = envelope['bids'];
    if (raw is! List) return const [];

    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  String _rideStatusLabel(String? status) {
    switch (status) {
      case 'searching':
        return 'بانتظار عروض الكباتن';
      case 'captain_assigned':
        return 'تم اختيار الكابتن';
      case 'captain_arriving':
        return 'الكابتن في الطريق';
      case 'ride_started':
        return 'الرحلة جارية';
      case 'completed':
        return 'تم إكمال الرحلة';
      case 'cancelled':
        return 'تم إلغاء الرحلة';
      case 'expired':
        return 'انتهت مهلة الطلب';
      default:
        return 'حالة غير معروفة';
    }
  }

  Color _rideStatusColor(String? status, BuildContext context) {
    switch (status) {
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
    return int.tryParse('$value');
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse('$value');
  }

  String? _string(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  String _extractApiError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        switch (message) {
          case 'TAXI_ACTIVE_RIDE_EXISTS':
            return 'لديك رحلة نشطة حالياً، أكملها أو قم بإلغائها أولاً';
          case 'TAXI_RIDE_NOT_ACCEPTING_BIDS':
            return 'الطلب لم يعد يستقبل عروضاً';
          case 'TAXI_RIDE_OUT_OF_RANGE':
            return 'الكابتن خارج نطاق الطلب';
          default:
            return message;
        }
      }
    }
    return 'فشل الاتصال بالخادم';
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    final ride = _ride;
    final rideStatus = _string(ride?['status']);
    final rideFare =
        _readInt(ride?['agreedFareIqd']) ?? _readInt(ride?['proposedFareIqd']);
    final canCancel =
        rideStatus == 'searching' ||
        rideStatus == 'captain_assigned' ||
        rideStatus == 'captain_arriving' ||
        rideStatus == 'ride_started';

    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('خريطة التكسي الذكية'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
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
              onTap: (_, point) => _onMapTap(point),
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                fallbackUrl:
                    'https://basemaps.cartocdn.com/light_all/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.bestoffer.bismayah',
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
                      color: Colors.cyanAccent.withValues(alpha: 0.95),
                    ),
                  ],
                ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
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
                ),
              ),
            ),
          ),
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
            label: const Text('موقعي'),
          ),
          const SizedBox(height: 8),
          FloatingActionButton.small(
            heroTag: 'toggle_mode',
            tooltip: _selectionMode == _PointSelectionMode.pickup
                ? 'التبديل إلى نقطة الوصول'
                : 'التبديل إلى نقطة الانطلاق',
            onPressed: _activeRideEnvelope != null
                ? null
                : () {
                    setState(() {
                      _selectionMode =
                          _selectionMode == _PointSelectionMode.pickup
                          ? _PointSelectionMode.dropoff
                          : _PointSelectionMode.pickup;
                    });
                  },
            child: Icon(
              _selectionMode == _PointSelectionMode.pickup
                  ? Icons.flag_outlined
                  : Icons.place_outlined,
            ),
          ),
        ],
      ),
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    if (_pickupPoint != null) {
      markers.add(
        Marker(
          point: _pickupPoint!,
          width: 44,
          height: 44,
          child: const Icon(
            Icons.trip_origin_rounded,
            color: Colors.green,
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
          child: const Icon(
            Icons.location_on_rounded,
            color: Colors.redAccent,
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
          child: const Icon(
            Icons.motorcycle_rounded,
            color: Colors.orange,
            size: 36,
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
              color: Colors.blueAccent,
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            _streamConnected ? Icons.bolt_rounded : Icons.bolt_outlined,
            color: _streamConnected
                ? Colors.lightGreenAccent
                : Colors.orangeAccent,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              _streamConnected
                  ? 'التحديث اللحظي نشط'
                  : 'جاري إعادة الاتصال بالتحديث المباشر...',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (_routeLoading)
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          if (_lastRealtimeAt != null)
            Text(
              '${_lastRealtimeAt!.hour.toString().padLeft(2, '0')}:${_lastRealtimeAt!.minute.toString().padLeft(2, '0')}',
              style: const TextStyle(color: Colors.white70, fontSize: 12),
            ),
        ],
      ),
    );
  }

  Widget _buildBottomCard(
    BuildContext context,
    Map<String, dynamic>? ride,
    String? rideStatus,
    int? rideFare,
    bool canCancel,
  ) {
    final bids = _bids;
    final captain = ride != null && ride['captain'] is Map
        ? Map<String, dynamic>.from(ride['captain'] as Map)
        : null;

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
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.96),
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
                child: ride != null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'رحلة نشطة #${ride['id']}',
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
                                    color: _rideStatusColor(
                                      rideStatus,
                                      context,
                                    ),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'السعر: ${rideFare ?? 0} د.ع',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'الانطلاق: ${_string(ride['pickup']?['label']) ?? '-'}',
                          ),
                          Text(
                            'الوصول: ${_string(ride['dropoff']?['label']) ?? '-'}',
                          ),
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
                                        _string(captain['profileImageUrl']) !=
                                            null
                                        ? NetworkImage(
                                            _string(
                                              captain['profileImageUrl'],
                                            )!,
                                          )
                                        : null,
                                    child:
                                        _string(captain['profileImageUrl']) ==
                                            null
                                        ? const Icon(Icons.person_rounded)
                                        : null,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          _string(captain['fullName']) ??
                                              'الكابتن',
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
                                        if (_string(captain['plateNumber']) !=
                                            null)
                                          Text(
                                            'اللوحة: ${_string(captain['plateNumber'])}',
                                            style: const TextStyle(
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                  if (_string(captain['carImageUrl']) != null)
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.network(
                                        _string(captain['carImageUrl'])!,
                                        width: 56,
                                        height: 56,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          ],
                          if (rideStatus == 'searching' && bids.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            const Text(
                              'عروض الكباتن',
                              style: TextStyle(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 6),
                            ...bids.take(3).map((bid) {
                              final bidId = _readInt(bid['id']);
                              final bidCaptain = bid['captain'] is Map
                                  ? Map<String, dynamic>.from(
                                      bid['captain'] as Map,
                                    )
                                  : null;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Colors.blueGrey.withValues(
                                    alpha: 0.08,
                                  ),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _string(bidCaptain?['fullName']) ??
                                                'كابتن',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          Text(
                                            'العرض: ${_readInt(bid['offeredFareIqd']) ?? 0} د.ع',
                                          ),
                                          if (_readInt(bid['etaMinutes']) !=
                                              null)
                                            Text(
                                              'وقت الوصول المتوقع: ${_readInt(bid['etaMinutes'])} دقيقة',
                                            ),
                                        ],
                                      ),
                                    ),
                                    FilledButton.tonal(
                                      onPressed: (_submitting || bidId == null)
                                          ? null
                                          : () => _acceptBid(bidId),
                                      child: const Text('قبول العرض'),
                                    ),
                                  ],
                                ),
                              );
                            }),
                          ],
                          if (_captainPoint != null) ...[
                            const SizedBox(height: 6),
                            const Text(
                              'يتم تتبع حركة الكابتن مباشرة على الخريطة',
                              style: TextStyle(
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
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: _submitting
                                      ? null
                                      : _createShareToken,
                                  icon: const Icon(
                                    Icons.share_location_rounded,
                                  ),
                                  label: const Text('مشاركة التتبع'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: _submitting || !canCancel
                                      ? null
                                      : _cancelRide,
                                  icon: const Icon(Icons.cancel_rounded),
                                  label: Text(
                                    _submitting ? 'جاري...' : 'إلغاء الرحلة',
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      )
                    : _buildRideComposer(context),
              ),
      ),
    );
  }

  Widget _buildRideComposer(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'إنشاء طلب تكسي',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        SegmentedButton<_PointSelectionMode>(
          segments: const [
            ButtonSegment(
              value: _PointSelectionMode.pickup,
              icon: Icon(Icons.trip_origin_rounded),
              label: Text('نقطة الانطلاق'),
            ),
            ButtonSegment(
              value: _PointSelectionMode.dropoff,
              icon: Icon(Icons.location_on_rounded),
              label: Text('نقطة الوصول'),
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
        TextField(
          controller: _pickupSearchController,
          textInputAction: TextInputAction.next,
          onChanged: _onPickupSearchChanged,
          decoration: InputDecoration(
            labelText: 'ابحث عن موقع الانطلاق',
            hintText: 'اكتب اسم منطقة أو شارع',
            border: const OutlineInputBorder(),
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
        if (_pickupSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildSuggestionList(_pickupSuggestions, forPickup: true),
        ],
        const SizedBox(height: 8),
        FilledButton.icon(
          onPressed: _pickupPoint == null ? null : _confirmPickup,
          icon: Icon(
            _pickupConfirmed ? Icons.verified_rounded : Icons.check_circle,
          ),
          label: Text(
            _pickupConfirmed ? 'تم تأكيد نقطة الانطلاق' : 'تأكيد نقطة الانطلاق',
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _dropoffSearchController,
          textInputAction: TextInputAction.next,
          onChanged: _onDropoffSearchChanged,
          decoration: InputDecoration(
            labelText: 'ابحث عن نقطة الوصول',
            hintText: 'مطعم، مستشفى، شارع، أو أي موقع',
            border: const OutlineInputBorder(),
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
        if (_dropoffSuggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          _buildSuggestionList(_dropoffSuggestions, forPickup: false),
        ],
        const SizedBox(height: 8),
        TextField(
          controller: _pickupLabelController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'وصف نقطة الانطلاق',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _dropoffLabelController,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'وصف نقطة الوصول',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _fareController,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'الأجرة المقترحة (د.ع)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _noteController,
          maxLines: 2,
          textInputAction: TextInputAction.done,
          decoration: const InputDecoration(
            labelText: 'ملاحظة للكابتن (اختياري)',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          _selectionMode == _PointSelectionMode.pickup
              ? 'اضغط على الخريطة لتحديد نقطة الانطلاق'
              : 'اضغط على الخريطة لتحديد نقطة الوصول',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
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
          label: Text(_submitting ? 'جاري الإرسال...' : 'إرسال طلب التكسي'),
        ),
      ],
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

class _PlaceSuggestion {
  final double latitude;
  final double longitude;
  final String title;
  final String fullAddress;

  const _PlaceSuggestion({
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.fullAddress,
  });
}
