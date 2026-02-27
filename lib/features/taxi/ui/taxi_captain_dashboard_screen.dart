import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/state/auth_controller.dart';
import '../data/taxi_api.dart';

final taxiCaptainApiProvider = Provider<TaxiApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return TaxiApi(dio);
});

class TaxiCaptainDashboardScreen extends ConsumerStatefulWidget {
  const TaxiCaptainDashboardScreen({super.key});

  @override
  ConsumerState<TaxiCaptainDashboardScreen> createState() =>
      _TaxiCaptainDashboardScreenState();
}

class _TaxiCaptainDashboardScreenState
    extends ConsumerState<TaxiCaptainDashboardScreen> {
  static const LatLng _bismayahCenter = LatLng(33.3128, 44.3615);

  final MapController _mapController = MapController();
  final Distance _distance = const Distance();

  Timer? _ticker;
  StreamSubscription<TaxiLiveEvent>? _streamSub;
  Timer? _streamReconnectTimer;

  bool _loading = true;
  bool _sending = false;
  bool _online = true;
  bool _streamConnected = false;
  bool _cameraLockedToCaptain = true;
  bool _cameraInitialized = false;

  DateTime? _lastSyncAt;
  String? _error;

  LatLng? _captainPoint;
  Map<String, dynamic>? _currentRideEnvelope;
  List<Map<String, dynamic>> _nearbyRequests = const [];

  TaxiApi get _api => ref.read(taxiCaptainApiProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _streamSub?.cancel();
    _streamReconnectTimer?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _tick(fullRefresh: true);
    _connectStream();
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) {
      _tick();
    });
  }

  Future<void> _tick({bool fullRefresh = false}) async {
    if (!mounted) return;

    if (!_online && _activeRide == null && !fullRefresh) {
      return;
    }

    try {
      final position = await _getCurrentPosition();
      if (position != null) {
        _captainPoint = LatLng(position.latitude, position.longitude);
      }

      if (_online && position != null) {
        final presence = await _api.upsertCaptainPresence(
          isOnline: true,
          latitude: position.latitude,
          longitude: position.longitude,
          headingDeg: _sanitizeHeading(position.heading),
          speedKmh: _sanitizeSpeedKmh(position.speed),
          accuracyM: position.accuracy,
          radiusM: 4000,
        );
        _nearbyRequests = _toMapList(presence['nearbyRequests']);
      }

      final rideEnvelope = await _api.getCurrentRideForCaptain();
      _currentRideEnvelope = rideEnvelope;
      _syncRideMarkers();

      final rideId = _readInt(_activeRide?['id']);
      if (rideId != null && position != null) {
        await _api.updateRideLocation(
          rideId: rideId,
          latitude: position.latitude,
          longitude: position.longitude,
          headingDeg: _sanitizeHeading(position.heading),
          speedKmh: _sanitizeSpeedKmh(position.speed),
          accuracyM: position.accuracy,
        );
      } else if (_online && _nearbyRequests.isEmpty) {
        _nearbyRequests = await _api.listNearbyRequests(
          radiusM: 4000,
          limit: 30,
        );
      }

      _moveCameraIfNeeded();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _lastSyncAt = DateTime.now();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _extractApiError(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحديث بيانات الكابتن الآن';
      });
    }
  }

  Future<Position?> _getCurrentPosition() async {
    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return null;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return null;
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.bestForNavigation,
    );
  }

  void _syncRideMarkers() {
    final ride = _activeRide;
    if (ride == null) return;

    final latest = _latLngFromMap(_currentRideEnvelope?['latestLocation']);
    if (latest != null) {
      _captainPoint = latest;
    }
  }

  void _moveCameraIfNeeded() {
    final target =
        _captainPoint ??
        _latLngFromMap(_activeRide?['pickup']) ??
        _latLngFromMap(_activeRide?['dropoff']);
    if (target == null) return;

    if (!_cameraInitialized) {
      _cameraInitialized = true;
      _mapController.move(target, 16.2);
      return;
    }
    if (_cameraLockedToCaptain) {
      _mapController.move(target, _mapController.camera.zoom.clamp(14.0, 17.5));
    }
  }

  void _connectStream() {
    _streamSub?.cancel();
    _streamSub = _api.streamEvents().listen(
      (event) {
        if (!mounted) return;
        if (event.event == 'connected' || event.event == 'heartbeat') {
          setState(() {
            _streamConnected = true;
            _lastSyncAt = DateTime.now();
          });
          return;
        }
        _tick(fullRefresh: true);
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _streamConnected = false);
        _scheduleStreamReconnect();
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _streamConnected = false);
        _scheduleStreamReconnect();
      },
      cancelOnError: true,
    );
  }

  void _scheduleStreamReconnect() {
    if (_streamReconnectTimer?.isActive == true) return;
    _streamReconnectTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      _connectStream();
    });
  }

  Future<void> _setOnline(bool value) async {
    if (_online == value) return;
    setState(() => _online = value);

    if (!value) {
      final point = _captainPoint ?? _bismayahCenter;
      try {
        await _api.upsertCaptainPresence(
          isOnline: false,
          latitude: point.latitude,
          longitude: point.longitude,
          radiusM: 4000,
        );
      } catch (_) {}
      return;
    }

    await _tick(fullRefresh: true);
  }

  Future<void> _submitBid(Map<String, dynamic> ride) async {
    final rideId = _readInt(ride['id']);
    if (rideId == null) return;

    final fareCtrl = TextEditingController(
      text: '${_readInt(ride['proposedFareIqd']) ?? 0}',
    );
    final etaCtrl = TextEditingController(text: '8');
    final noteCtrl = TextEditingController();

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: Directionality(
            textDirection: TextDirection.rtl,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'إرسال عرض للزبون',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: fareCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'السعر المقترح (IQD)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: etaCtrl,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'وقت الوصول التقديري (دقيقة)',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                    labelText: 'ملاحظة (اختياري)',
                  ),
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(true),
                  icon: const Icon(Icons.send_rounded),
                  label: const Text('إرسال العرض'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (confirmed != true) return;

    final offeredFare = int.tryParse(fareCtrl.text.trim());
    final eta = int.tryParse(etaCtrl.text.trim());
    if (offeredFare == null || offeredFare < 0) {
      _showMessage('السعر غير صحيح');
      return;
    }

    setState(() => _sending = true);
    try {
      await _api.createBid(
        rideId: rideId,
        offeredFareIqd: offeredFare,
        etaMinutes: eta,
        note: noteCtrl.text.trim(),
      );
      _showMessage('تم إرسال العرض بنجاح');
      await _tick(fullRefresh: true);
    } on DioException catch (e) {
      _showMessage(_extractApiError(e));
    } catch (_) {
      _showMessage('تعذر إرسال العرض الآن');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _advanceRide(String action) async {
    final rideId = _readInt(_activeRide?['id']);
    if (rideId == null || _sending) return;

    setState(() => _sending = true);
    try {
      if (action == 'arrive') {
        await _api.markArrived(rideId);
      } else if (action == 'start') {
        await _api.startRide(rideId);
      } else if (action == 'complete') {
        await _api.completeRide(rideId);
      }
      await _tick(fullRefresh: true);
    } on DioException catch (e) {
      _showMessage(_extractApiError(e));
    } catch (_) {
      _showMessage('تعذر تحديث حالة الرحلة');
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Map<String, dynamic>? get _activeRide {
    final envelope = _currentRideEnvelope;
    if (envelope == null) return null;
    final ride = envelope['ride'];
    if (ride is Map) {
      return Map<String, dynamic>.from(ride);
    }
    return null;
  }

  String _rideStatusLabel(String? status) {
    switch (status) {
      case 'searching':
        return 'بانتظار اختيار الزبون';
      case 'captain_assigned':
        return 'تم تعيينك على الرحلة';
      case 'captain_arriving':
        return 'في الطريق إلى الزبون';
      case 'ride_started':
        return 'الرحلة جارية الآن';
      case 'completed':
        return 'رحلة مكتملة';
      case 'cancelled':
        return 'تم إلغاء الرحلة';
      case 'expired':
        return 'انتهت مهلة الرحلة';
      default:
        return 'حالة غير معروفة';
    }
  }

  Color _rideStatusColor(String? status) {
    switch (status) {
      case 'captain_assigned':
        return const Color(0xFF3BC7FF);
      case 'captain_arriving':
        return const Color(0xFF68E0CF);
      case 'ride_started':
        return const Color(0xFF9EFF8E);
      case 'completed':
        return const Color(0xFF53C0B0);
      case 'cancelled':
      case 'expired':
        return const Color(0xFFFF8C8C);
      default:
        return const Color(0xFFFFD166);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ride = _activeRide;
    final status = _string(ride?['status']);
    return Scaffold(
      appBar: AppBar(
        title: const Text('واجهة كابتن التكسي'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _sending ? null : () => _tick(fullRefresh: true),
            icon: const Icon(Icons.refresh_rounded),
          ),
          IconButton(
            tooltip: 'تسجيل خروج',
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _bismayahCenter,
              initialZoom: 15.5,
              onPositionChanged: (mapCamera, hasGesture) {
                _cameraInitialized = true;
                if (hasGesture == true && _cameraLockedToCaptain) {
                  setState(() => _cameraLockedToCaptain = false);
                }
              },
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.example.bestoffer',
              ),
              MarkerLayer(markers: _buildMarkers()),
            ],
          ),
          Positioned(top: 12, left: 12, right: 12, child: _buildTopPanel()),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _buildBottomPanel(ride, status),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () =>
            setState(() => _cameraLockedToCaptain = !_cameraLockedToCaptain),
        icon: Icon(
          _cameraLockedToCaptain
              ? Icons.gps_fixed_rounded
              : Icons.gps_not_fixed_rounded,
        ),
        label: Text(_cameraLockedToCaptain ? 'تتبع الكابتن' : 'تحريك حر'),
      ),
    );
  }

  Widget _buildTopPanel() {
    final time = _lastSyncAt;
    final timeLabel = time == null
        ? '--:--'
        : '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.52),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _streamConnected ? Icons.bolt_rounded : Icons.bolt_outlined,
                color: _streamConnected
                    ? Colors.lightGreenAccent
                    : Colors.orangeAccent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _streamConnected
                      ? 'اتصال لحظي مباشر'
                      : 'إعادة الاتصال بالبث المباشر...',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(timeLabel, style: const TextStyle(color: Colors.white70)),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              const Text(
                'متصل الآن',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 8),
              Switch(value: _online, onChanged: _sending ? null : _setOnline),
              const Spacer(),
              if (_captainPoint != null)
                Text(
                  'Lat ${_captainPoint!.latitude.toStringAsFixed(5)}  Lng ${_captainPoint!.longitude.toStringAsFixed(5)}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBottomPanel(Map<String, dynamic>? ride, String? status) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 360),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.95),
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 14,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : ride != null
          ? _buildActiveRidePanel(ride, status)
          : _buildNearbyPanel(),
    );
  }

  Widget _buildActiveRidePanel(Map<String, dynamic> ride, String? status) {
    final customer = ride['customer'] is Map
        ? Map<String, dynamic>.from(ride['customer'] as Map)
        : <String, dynamic>{};
    final proposedFare = _readInt(ride['proposedFareIqd']) ?? 0;
    final agreedFare = _readInt(ride['agreedFareIqd']);
    final fare = agreedFare ?? proposedFare;

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'الرحلة الحالية #${ride['id']}',
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
                  color: _rideStatusColor(status).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _rideStatusLabel(status),
                  style: TextStyle(
                    color: _rideStatusColor(status),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text('الزبون: ${_string(customer['fullName']) ?? '-'}'),
          Text('الهاتف: ${_string(customer['phone']) ?? '-'}'),
          const SizedBox(height: 4),
          Text(
            'الأجرة: ${fare.toString()} IQD',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text('الانطلاق: ${_string(ride['pickup']?['label']) ?? '-'}'),
          Text('الوصول: ${_string(ride['dropoff']?['label']) ?? '-'}'),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: _sending ? null : () => _tick(fullRefresh: true),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('تحديث'),
              ),
              if (status == 'captain_assigned')
                FilledButton.icon(
                  onPressed: _sending ? null : () => _advanceRide('arrive'),
                  icon: const Icon(Icons.directions_car_rounded),
                  label: const Text('وصلت للزبون'),
                ),
              if (status == 'captain_assigned' || status == 'captain_arriving')
                FilledButton.icon(
                  onPressed: _sending ? null : () => _advanceRide('start'),
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('بدء الرحلة'),
                ),
              if (status == 'ride_started' || status == 'captain_arriving')
                FilledButton.icon(
                  onPressed: _sending ? null : () => _advanceRide('complete'),
                  icon: const Icon(Icons.flag_circle_rounded),
                  label: const Text('إنهاء الرحلة'),
                ),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(
              _error!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNearbyPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'الطلبات القريبة منك',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
        ),
        const SizedBox(height: 8),
        if (_nearbyRequests.isEmpty)
          const Expanded(
            child: Center(child: Text('لا توجد طلبات حالياً ضمن نطاقك')),
          )
        else
          Expanded(
            child: ListView.separated(
              itemCount: _nearbyRequests.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                final ride = _nearbyRequests[index];
                final distanceM =
                    _readDouble(ride['distanceM']) ??
                    _calcDistanceMeters(ride['pickup']);
                final distanceKm = (distanceM / 1000)
                    .clamp(0, 999)
                    .toStringAsFixed(2);
                final fare = _readInt(ride['proposedFareIqd']) ?? 0;
                final myBid = ride['myBid'] is Map
                    ? Map<String, dynamic>.from(ride['myBid'] as Map)
                    : null;
                final myBidStatus = _string(myBid?['status']);
                return Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black.withValues(alpha: 0.05),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              'طلب #${ride['id']} - $distanceKm كم',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '$fare IQD',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF2BC17A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text('من: ${_string(ride['pickup']?['label']) ?? '-'}'),
                      Text('إلى: ${_string(ride['dropoff']?['label']) ?? '-'}'),
                      if (myBidStatus != null)
                        Text(
                          'حالة عرضك: $myBidStatus',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerRight,
                        child: FilledButton.tonalIcon(
                          onPressed: _sending ? null : () => _submitBid(ride),
                          icon: const Icon(Icons.local_offer_outlined),
                          label: const Text('إرسال عرض'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
      ],
    );
  }

  List<Marker> _buildMarkers() {
    final markers = <Marker>[];

    final ride = _activeRide;
    final pickup = _latLngFromMap(ride?['pickup']);
    final dropoff = _latLngFromMap(ride?['dropoff']);

    if (pickup != null) {
      markers.add(
        Marker(
          point: pickup,
          width: 42,
          height: 42,
          child: const Icon(
            Icons.trip_origin_rounded,
            color: Color(0xFF2BC17A),
            size: 34,
          ),
        ),
      );
    }

    if (dropoff != null) {
      markers.add(
        Marker(
          point: dropoff,
          width: 46,
          height: 46,
          child: const Icon(
            Icons.location_on_rounded,
            color: Color(0xFFFF6363),
            size: 38,
          ),
        ),
      );
    }

    if (_captainPoint != null) {
      markers.add(
        Marker(
          point: _captainPoint!,
          width: 54,
          height: 54,
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: const Color(0xFF1D5A9C),
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black26,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(
              Icons.local_taxi_rounded,
              color: Colors.white,
              size: 30,
            ),
          ),
        ),
      );
    }

    return markers;
  }

  double _calcDistanceMeters(dynamic pickup) {
    final from = _captainPoint;
    final to = _latLngFromMap(pickup);
    if (from == null || to == null) return 0;
    return _distance(from, to);
  }

  List<Map<String, dynamic>> _toMapList(dynamic value) {
    if (value is! List) return const [];
    return value
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  LatLng? _latLngFromMap(dynamic value) {
    if (value is! Map) return null;
    final map = Map<String, dynamic>.from(value);
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
    if (value is num) return value.toInt();
    return int.tryParse('$value');
  }

  double? _readDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is num) return value.toDouble();
    return double.tryParse('$value');
  }

  String? _string(dynamic value) {
    if (value == null) return null;
    final text = '$value'.trim();
    if (text.isEmpty) return null;
    return text;
  }

  String _extractApiError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message is String && message.trim().isNotEmpty) {
        switch (message) {
          case 'TAXI_RIDE_NOT_ACCEPTING_BIDS':
            return 'الطلب لم يعد يستقبل عروضاً';
          case 'TAXI_RIDE_OUT_OF_RANGE':
            return 'هذا الطلب خارج نطاقك الحالي';
          case 'TAXI_RIDE_NOT_ASSIGNED_TO_CAPTAIN':
            return 'الرحلة غير مسندة لك';
          case 'DELIVERY_ACCOUNT_PENDING_APPROVAL':
            return 'حساب كابتن التكسي بانتظار موافقة الإدارة';
          default:
            return message;
        }
      }
    }
    return 'تعذر الاتصال بالخادم';
  }

  void _showMessage(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  double? _sanitizeHeading(double value) {
    if (value.isNaN || value.isInfinite) return null;
    if (value < 0 || value > 360) return null;
    return value;
  }

  double? _sanitizeSpeedKmh(double value) {
    if (value.isNaN || value.isInfinite) return null;
    if (value < 0) return null;
    return value * 3.6;
  }
}
