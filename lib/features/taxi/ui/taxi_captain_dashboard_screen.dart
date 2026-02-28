import 'dart:async';

import 'package:bestoffer/features/taxi/data/taxi_route_service.dart';
import 'package:bestoffer/features/taxi/ui/taxi_call_screen.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../auth/state/auth_controller.dart';
import '../data/taxi_api.dart';

final taxiCaptainApiProvider = Provider<TaxiApi>((ref) {
  final dio = ref.read(dioClientProvider).dio;
  return TaxiApi(dio);
});

final taxiCaptainRouteServiceProvider = Provider<TaxiRouteService>((ref) {
  return TaxiRouteService();
});

class TaxiCaptainDashboardScreen extends ConsumerStatefulWidget {
  const TaxiCaptainDashboardScreen({super.key});

  @override
  ConsumerState<TaxiCaptainDashboardScreen> createState() =>
      _TaxiCaptainDashboardScreenState();
}

class _TaxiCaptainDashboardScreenState
    extends ConsumerState<TaxiCaptainDashboardScreen> {
  static const _center = LatLng(33.3128, 44.3615);

  final _mapController = MapController();
  Timer? _ticker;
  StreamSubscription<TaxiLiveEvent>? _streamSub;

  bool _loading = true;
  bool _sending = false;
  bool _online = true;
  bool _streamConnected = false;
  bool _followMe = true;
  bool _routeLoading = false;
  bool _callScreenOpen = false;
  int _tab = 0;
  int _tickCounter = 0;
  String _period = 'day';

  String? _error;
  DateTime? _lastSync;
  DateTime? _lastRouteAt;
  int? _lastCallSignalId;
  int? _lastIncomingSessionId;

  LatLng? _captainPoint;
  LatLng? _lastRouteFrom;
  LatLng? _lastRouteTo;
  List<LatLng> _routePoints = const [];
  Map<String, dynamic>? _currentRideEnvelope;
  List<Map<String, dynamic>> _nearby = const [];
  Map<String, dynamic>? _dashboard;
  Map<String, dynamic>? _profile;
  Map<String, dynamic>? _subscription;

  TaxiApi get _api => ref.read(taxiCaptainApiProvider);
  TaxiRouteService get _routeService =>
      ref.read(taxiCaptainRouteServiceProvider);

  @override
  void initState() {
    super.initState();
    Future.microtask(_bootstrap);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _streamSub?.cancel();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _refreshMeta();
    await _tick(full: true);
    _connectStream();
    _ticker = Timer.periodic(const Duration(seconds: 5), (_) async {
      await _tick();
      _tickCounter++;
      if (_tickCounter % 6 == 0) await _refreshMeta();
    });
  }

  Future<void> _refreshMeta() async {
    try {
      final result = await Future.wait([
        _api.getCaptainDashboard(period: _period, limit: 80),
        _api.getCaptainProfile(),
        _api.getCaptainSubscription(),
      ]);
      if (!mounted) return;
      setState(() {
        _dashboard = result[0];
        _profile = result[1];
        _subscription = result[2];
        _error = null;
        _lastSync = DateTime.now();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = _err(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'تعذر تحديث بيانات الكابتن');
    }
  }

  Future<void> _tick({bool full = false}) async {
    if (!mounted) return;
    if (_locked && !full) {
      setState(() {
        _loading = false;
        _routePoints = const [];
      });
      return;
    }

    try {
      final pos = await _position();
      if (pos != null) _captainPoint = LatLng(pos.latitude, pos.longitude);

      if (_online && pos != null) {
        final p = await _api.upsertCaptainPresence(
          isOnline: true,
          latitude: pos.latitude,
          longitude: pos.longitude,
          headingDeg: _sanitizeHeading(pos.heading),
          speedKmh: _sanitizeSpeed(pos.speed),
          accuracyM: pos.accuracy,
          radiusM: 4000,
        );
        _nearby = _toMapList(p['nearbyRequests']);
      }

      _currentRideEnvelope = await _api.getCurrentRideForCaptain();
      final rideId = _asInt(_ride?['id']);
      if (rideId != null && pos != null) {
        await _api.updateRideLocation(
          rideId: rideId,
          latitude: pos.latitude,
          longitude: pos.longitude,
          headingDeg: _sanitizeHeading(pos.heading),
          speedKmh: _sanitizeSpeed(pos.speed),
          accuracyM: pos.accuracy,
        );
      }

      if (_followMe && _captainPoint != null) {
        _mapController.move(_captainPoint!, 16.0);
      }

      await _refreshRoutePolyline();

      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = null;
        _lastSync = DateTime.now();
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _err(e);
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'تعذر تحديث بيانات الرحلات';
      });
    }
  }

  Future<void> _refreshRoutePolyline({bool force = false}) async {
    final target = _resolveCaptainRouteTarget();
    if (target == null) {
      if (_routePoints.isNotEmpty && mounted) {
        setState(() => _routePoints = const []);
      }
      return;
    }

    final from = target.$1;
    final to = target.$2;
    final now = DateTime.now();

    if (!force &&
        _lastRouteFrom != null &&
        _lastRouteTo != null &&
        _lastRouteAt != null) {
      final movedFrom = _routeService.distanceMeters(_lastRouteFrom!, from);
      final movedTo = _routeService.distanceMeters(_lastRouteTo!, to);
      final age = now.difference(_lastRouteAt!);
      if (movedFrom < 45 && movedTo < 30 && age < const Duration(seconds: 16)) {
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

  (LatLng, LatLng)? _resolveCaptainRouteTarget() {
    final ride = _ride;
    if (ride == null || _captainPoint == null) return null;

    final status = _str(ride['status']);
    final pickup = _latLng(ride['pickup']);
    final dropoff = _latLng(ride['dropoff']);

    if ((status == 'captain_assigned' || status == 'captain_arriving') &&
        pickup != null) {
      return (_captainPoint!, pickup);
    }
    if (status == 'ride_started' && dropoff != null) {
      return (_captainPoint!, dropoff);
    }
    return null;
  }

  Future<void> _openInWaze({
    required LatLng destination,
    required String targetLabel,
  }) async {
    try {
      await _routeService.openWazeNavigation(destination);
    } catch (_) {
      _snack('تعذر فتح تطبيق الخرائط لـ $targetLabel');
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
            _lastSync = DateTime.now();
          });
          return;
        }
        if (event.event == 'taxi_call_update') {
          unawaited(_handleCallRealtimeEvent(event.data));
        }
        _tick(full: true);
        _refreshMeta();
      },
      onError: (_) {
        if (mounted) setState(() => _streamConnected = false);
      },
      onDone: () {
        if (mounted) setState(() => _streamConnected = false);
      },
    );
  }

  Future<Position?> _position() async {
    if (!await Geolocator.isLocationServiceEnabled()) return null;
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

  Future<void> _setOnline(bool value) async {
    setState(() => _online = value);
    if (!value) {
      final p = _captainPoint ?? _center;
      setState(() => _routePoints = const []);
      await _api.upsertCaptainPresence(
        isOnline: false,
        latitude: p.latitude,
        longitude: p.longitude,
        radiusM: 4000,
      );
    } else {
      await _tick(full: true);
    }
  }

  Future<void> _advance(String action) async {
    if (_locked) {
      _snack('الاشتراك منتهي. اطلب تسديد الاشتراك.');
      return;
    }
    final rideId = _asInt(_ride?['id']);
    if (rideId == null) return;
    setState(() => _sending = true);
    try {
      if (action == 'arrive') await _api.markArrived(rideId);
      if (action == 'start') await _api.startRide(rideId);
      if (action == 'complete') await _api.completeRide(rideId);
      await _tick(full: true);
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _requestCashPayment() async {
    setState(() => _sending = true);
    try {
      await _api.requestCaptainCashPayment();
      await _refreshMeta();
      _snack('تم إرسال طلب التسديد للإدارة');
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _submitBid(Map<String, dynamic> ride) async {
    if (_locked) {
      _snack('الاشتراك منتهي. اطلب التسديد أولاً.');
      return;
    }
    final rideId = _asInt(ride['id']);
    if (rideId == null) return;

    final baseFare = _asInt(ride['proposedFareIqd']) ?? 0;
    final fareCtrl = TextEditingController(text: '$baseFare');
    final etaCtrl = TextEditingController(text: '8');
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
        ),
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          title: const Row(
            children: [
              Icon(Icons.local_offer_rounded),
              SizedBox(width: 8),
              Text('إرسال عرض للكابتن'),
            ],
          ),
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'سعر الزبون الحالي: ${_money(baseFare)}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: fareCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'سعر عرضك (د.ع)',
                      prefixIcon: Icon(Icons.price_change_rounded),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: etaCtrl,
                    keyboardType: TextInputType.number,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'زمن الوصول المتوقع (دقيقة)',
                      prefixIcon: Icon(Icons.timer_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: noteCtrl,
                    textInputAction: TextInputAction.done,
                    maxLines: 2,
                    decoration: const InputDecoration(
                      labelText: 'رسالة للزبون (اختياري)',
                      prefixIcon: Icon(Icons.chat_bubble_outline_rounded),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              onPressed: () => Navigator.pop(dialogContext, true),
              icon: const Icon(Icons.send_rounded),
              label: const Text('إرسال العرض'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;
    final fare = int.tryParse(fareCtrl.text.trim());
    final eta = int.tryParse(etaCtrl.text.trim());
    if (fare == null || fare < 0) {
      _snack('السعر غير صحيح');
      return;
    }

    setState(() => _sending = true);
    try {
      await _api.createBid(
        rideId: rideId,
        offeredFareIqd: fare,
        etaMinutes: eta,
        note: noteCtrl.text.trim(),
      );
      _snack('تم إرسال العرض بنجاح');
      await _tick(full: true);
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openRideChatBottomSheet(int rideId) async {
    final textCtrl = TextEditingController();
    List<Map<String, dynamic>> messages = const [];
    bool sending = false;
    String? localError;

    Future<void> refresh(StateSetter setModalState) async {
      try {
        final items = await _api.listRideChat(rideId: rideId, limit: 120);
        setModalState(() {
          messages = items;
          localError = null;
        });
      } on DioException catch (e) {
        setModalState(() => localError = _err(e));
      } catch (_) {
        setModalState(() => localError = 'تعذر تحميل المحادثة');
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
              unawaited(refresh(setModalState));
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 12,
                right: 12,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 12,
                top: 6,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SizedBox(
                  height: MediaQuery.sizeOf(context).height * 0.68,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'محادثة الرحلة',
                        style: TextStyle(
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
                            ? const Center(child: Text('لا توجد رسائل بعد'))
                            : ListView.builder(
                                itemCount: messages.length,
                                itemBuilder: (_, i) {
                                  final msg = messages[i];
                                  final role =
                                      _str(msg['senderRole']) ?? 'system';
                                  final senderName =
                                      _str(msg['sender']?['fullName']) ??
                                      (role == 'captain'
                                          ? 'أنت'
                                          : role == 'customer'
                                          ? 'الزبون'
                                          : 'النظام');
                                  final text = _str(msg['messageText']) ?? '-';
                                  final mine = role == 'captain';
                                  return Align(
                                    alignment: mine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: Container(
                                      margin: const EdgeInsets.only(bottom: 6),
                                      padding: const EdgeInsets.all(10),
                                      decoration: BoxDecoration(
                                        color: mine
                                            ? Colors.green.withValues(
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
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: textCtrl,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) async {
                                final text = textCtrl.text.trim();
                                if (text.isEmpty || sending) return;
                                setModalState(() => sending = true);
                                try {
                                  await _api.sendRideChatMessage(
                                    rideId: rideId,
                                    messageText: text,
                                  );
                                  textCtrl.clear();
                                  await refresh(setModalState);
                                } finally {
                                  setModalState(() => sending = false);
                                }
                              },
                              decoration: const InputDecoration(
                                hintText: 'اكتب رسالة للزبون...',
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          FilledButton(
                            onPressed: sending
                                ? null
                                : () async {
                                    final text = textCtrl.text.trim();
                                    if (text.isEmpty) return;
                                    setModalState(() => sending = true);
                                    try {
                                      await _api.sendRideChatMessage(
                                        rideId: rideId,
                                        messageText: text,
                                      );
                                      textCtrl.clear();
                                      await refresh(setModalState);
                                    } catch (_) {
                                      setModalState(() {
                                        localError = 'تعذر إرسال الرسالة';
                                      });
                                    } finally {
                                      setModalState(() => sending = false);
                                    }
                                  },
                            child: const Text('إرسال'),
                          ),
                        ],
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
  }

  Future<void> _callUser({
    required int rideId,
    String? phone,
    String? remoteDisplayName,
  }) async {
    if (rideId > 0) {
      await _openInAppCall(
        rideId: rideId,
        isCaller: true,
        remoteDisplayName: remoteDisplayName,
      );
      return;
    }

    final value = (phone ?? '').trim();
    if (value.isEmpty) {
      _snack('Phone number is not available');
      return;
    }
    final uri = Uri.parse('tel:$value');
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened) {
      _snack('Could not open phone call');
    }
  }

  Future<void> _handleCallRealtimeEvent(Map<String, dynamic> data) async {
    final activeRideId = _asInt(_ride?['id']);
    final eventRideId = data['ride'] is Map
        ? _asInt((data['ride'] as Map)['id'])
        : _asInt(data['rideId']);
    if (activeRideId == null ||
        eventRideId == null ||
        activeRideId != eventRideId) {
      return;
    }

    final signal = data['signal'] is Map
        ? Map<String, dynamic>.from(data['signal'] as Map)
        : null;
    final signalId = _asInt(signal?['id']);
    if (signalId != null) {
      if (_lastCallSignalId == signalId) return;
      _lastCallSignalId = signalId;
    }

    final session = data['session'] is Map
        ? Map<String, dynamic>.from(data['session'] as Map)
        : null;
    final sessionId = _asInt(session?['id']);
    final eventType = _str(data['eventType']) ?? '';
    final customerName = _str(_ride?['customer']?['fullName']);

    if (eventType == 'incoming_call') {
      if (_callScreenOpen || sessionId == null) return;
      if (_lastIncomingSessionId == sessionId) return;
      _lastIncomingSessionId = sessionId;
      await _openInAppCall(
        rideId: activeRideId,
        isCaller: false,
        initialSessionId: sessionId,
        remoteDisplayName: customerName,
      );
      return;
    }

    if (eventType == 'outgoing_call' && !_callScreenOpen && sessionId != null) {
      await _openInAppCall(
        rideId: activeRideId,
        isCaller: true,
        initialSessionId: sessionId,
        remoteDisplayName: customerName,
      );
      return;
    }

    if (eventType == 'call_ended') {
      _snack('Call ended');
    }
  }

  Future<void> _openInAppCall({
    required int rideId,
    required bool isCaller,
    int? initialSessionId,
    String? remoteDisplayName,
  }) async {
    if (_callScreenOpen || !mounted) return;
    _callScreenOpen = true;
    try {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => TaxiCallScreen(
            rideId: rideId,
            isCaller: isCaller,
            initialSessionId: initialSessionId,
            remoteDisplayName: remoteDisplayName,
          ),
        ),
      );
    } finally {
      _callScreenOpen = false;
      if (mounted) {
        unawaited(_tick(full: true));
      }
    }
  }

  Future<void> _requestProfileEdit() async {
    final p = _profileMap;
    if (p == null) return;

    final nameCtrl = TextEditingController(text: _str(p['fullName']) ?? '');
    final phoneCtrl = TextEditingController(text: _str(p['phone']) ?? '');
    final carMakeCtrl = TextEditingController(text: _str(p['carMake']) ?? '');
    final carModelCtrl = TextEditingController(text: _str(p['carModel']) ?? '');
    final noteCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AnimatedPadding(
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(dialogContext).bottom,
        ),
        child: AlertDialog(
          title: const Text('طلب تعديل البيانات'),
          content: Directionality(
            textDirection: TextDirection.rtl,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'الاسم'),
                  ),
                  TextField(
                    controller: phoneCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'الهاتف'),
                  ),
                  TextField(
                    controller: carMakeCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'شركة السيارة',
                    ),
                  ),
                  TextField(
                    controller: carModelCtrl,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      labelText: 'موديل السيارة',
                    ),
                  ),
                  TextField(
                    controller: noteCtrl,
                    textInputAction: TextInputAction.done,
                    decoration: const InputDecoration(
                      labelText: 'ملاحظة (اختياري)',
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('إرسال'),
            ),
          ],
        ),
      ),
    );

    if (ok != true) return;

    final changes = <String, dynamic>{};
    if (nameCtrl.text.trim().isNotEmpty &&
        nameCtrl.text.trim() != (_str(p['fullName']) ?? '')) {
      changes['fullName'] = nameCtrl.text.trim();
    }
    if (phoneCtrl.text.trim().isNotEmpty &&
        phoneCtrl.text.trim() != (_str(p['phone']) ?? '')) {
      changes['phone'] = phoneCtrl.text.trim();
    }
    if (carMakeCtrl.text.trim().isNotEmpty &&
        carMakeCtrl.text.trim() != (_str(p['carMake']) ?? '')) {
      changes['carMake'] = carMakeCtrl.text.trim();
    }
    if (carModelCtrl.text.trim().isNotEmpty &&
        carModelCtrl.text.trim() != (_str(p['carModel']) ?? '')) {
      changes['carModel'] = carModelCtrl.text.trim();
    }

    if (changes.isEmpty) {
      _snack('لا يوجد تغيير لإرساله');
      return;
    }

    setState(() => _sending = true);
    try {
      await _api.requestCaptainProfileEdit(
        requestedChanges: changes,
        captainNote: noteCtrl.text.trim(),
      );
      _snack('تم إرسال طلب التعديل بنجاح');
    } on DioException catch (e) {
      _snack(_err(e));
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Map<String, dynamic>? get _ride {
    final r = _currentRideEnvelope?['ride'];
    return r is Map ? Map<String, dynamic>.from(r) : null;
  }

  Map<String, dynamic>? get _profileMap {
    final p = _profile?['profile'];
    return p is Map ? Map<String, dynamic>.from(p) : null;
  }

  Map<String, dynamic>? get _sub {
    final s =
        _subscription?['subscription'] ??
        _profile?['subscription'] ??
        _dashboard?['subscription'];
    return s is Map ? Map<String, dynamic>.from(s) : null;
  }

  bool get _locked => _sub?['canAccess'] != true && _sub != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: const Text('واجهة كابتن التكسي'),
        actions: [
          IconButton(
            onPressed: _sending
                ? null
                : () async {
                    await _refreshMeta();
                    await _tick(full: true);
                  },
            icon: const Icon(Icons.refresh),
          ),
          IconButton(
            onPressed: () => ref.read(authControllerProvider.notifier).logout(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: IndexedStack(
        index: _tab,
        children: [_rideTab(), _dashboardTab(), _profileTab()],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (v) => setState(() => _tab = v),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.local_taxi), label: 'الرحلات'),
          NavigationDestination(icon: Icon(Icons.insights), label: 'الداشبورد'),
          NavigationDestination(
            icon: Icon(Icons.person),
            label: 'الملف الشخصي',
          ),
        ],
      ),
      floatingActionButton: _tab == 0
          ? FloatingActionButton.extended(
              onPressed: () => setState(() => _followMe = !_followMe),
              icon: Icon(_followMe ? Icons.gps_fixed : Icons.gps_not_fixed),
              label: Text(_followMe ? 'تتبع' : 'حر'),
            )
          : null,
    );
  }

  Widget _rideTab() {
    final status = _str(_ride?['status']);
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(initialCenter: _center, initialZoom: 15.5),
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
                    color: Colors.black.withValues(alpha: 0.2),
                  ),
                  Polyline(
                    points: _routePoints,
                    strokeWidth: 4.4,
                    color: Colors.amberAccent.withValues(alpha: 0.95),
                  ),
                ],
              ),
            MarkerLayer(markers: _markers()),
          ],
        ),
        Positioned(top: 12, left: 12, right: 12, child: _topPanel()),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: SafeArea(child: _bottomPanel(status)),
        ),
      ],
    );
  }

  Widget _topPanel() {
    final t = _lastSync;
    final last = t == null
        ? '--:--'
        : '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                _streamConnected ? Icons.wifi : Icons.wifi_off,
                color: _streamConnected ? Colors.greenAccent : Colors.amber,
              ),
              const SizedBox(width: 8),
              Text(
                _streamConnected ? 'تحديث مباشر' : 'إعادة اتصال',
                style: const TextStyle(color: Colors.white),
              ),
              if (_routeLoading)
                const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              const Spacer(),
              Text(
                'آخر مزامنة: $last',
                style: const TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ],
          ),
          Row(
            children: [
              const Text(
                'متاح للطلبات',
                style: TextStyle(color: Colors.white70),
              ),
              const Spacer(),
              Switch(value: _online, onChanged: _locked ? null : _setOnline),
            ],
          ),
          if (_locked)
            const Text(
              'الحساب موقوف بسبب الاشتراك',
              style: TextStyle(
                color: Colors.amber,
                fontWeight: FontWeight.bold,
              ),
            ),
        ],
      ),
    );
  }

  Widget _bottomPanel(String? status) {
    final screenHeight = MediaQuery.sizeOf(context).height;
    final panelHeight = (screenHeight * 0.44).clamp(250.0, 430.0).toDouble();
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 220, maxHeight: panelHeight),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black54,
          borderRadius: BorderRadius.circular(12),
        ),
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _locked
            ? SingleChildScrollView(child: _subscriptionCard(compact: false))
            : (_ride == null
                  ? _nearbyPanel()
                  : SingleChildScrollView(
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      child: _activeRidePanel(status),
                    )),
      ),
    );
  }

  Widget _activeRidePanel(String? status) {
    final ride = _ride!;
    final fare =
        _asInt(ride['agreedFareIqd']) ?? _asInt(ride['proposedFareIqd']) ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'رحلة #${ride['id']}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'الحالة: ${_status(status)}',
          style: const TextStyle(color: Colors.white70),
        ),
        Text(
          'من: ${_str(ride['pickup']?['label']) ?? '-'}',
          style: const TextStyle(color: Colors.white70),
        ),
        Text(
          'إلى: ${_str(ride['dropoff']?['label']) ?? '-'}',
          style: const TextStyle(color: Colors.white70),
        ),
        Text(
          'الأجرة: ${_money(fare)}',
          style: const TextStyle(color: Colors.greenAccent),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            FilledButton.tonalIcon(
              onPressed: _sending
                  ? null
                  : () {
                      final pickup = _latLng(ride['pickup']);
                      if (pickup == null) return;
                      _openInWaze(
                        destination: pickup,
                        targetLabel: 'موقع الزبون',
                      );
                    },
              icon: const Icon(Icons.person_pin_circle_rounded),
              label: const Text('فتح موقع الزبون'),
            ),
            FilledButton.tonalIcon(
              onPressed: _sending
                  ? null
                  : () {
                      final dropoff = _latLng(ride['dropoff']);
                      if (dropoff == null) return;
                      _openInWaze(
                        destination: dropoff,
                        targetLabel: 'نقطة الوصول',
                      );
                    },
              icon: const Icon(Icons.flag_rounded),
              label: const Text('فتح نقطة الوصول'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              onPressed: _sending || (_asInt(ride['id']) ?? 0) <= 0
                  ? null
                  : () => _openRideChatBottomSheet(_asInt(ride['id'])!),
              icon: const Icon(Icons.chat_rounded),
              label: const Text('دردشة'),
            ),
            OutlinedButton.icon(
              onPressed: _sending
                  ? null
                  : () => _callUser(
                      rideId: _asInt(ride['id']) ?? 0,
                      phone: _str(ride['customer']?['phone']),
                      remoteDisplayName: _str(ride['customer']?['fullName']),
                    ),
              icon: const Icon(Icons.call_rounded),
              label: const Text('اتصال بالزبون'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (status == 'captain_assigned')
          FilledButton(
            onPressed: _sending ? null : () => _advance('arrive'),
            child: const Text('التوجه للزبون'),
          ),
        if (status == 'captain_arriving')
          FilledButton(
            onPressed: _sending ? null : () => _advance('start'),
            child: const Text('بدء الرحلة'),
          ),
        if (status == 'ride_started')
          FilledButton(
            onPressed: _sending ? null : () => _advance('complete'),
            child: const Text('إنهاء الرحلة'),
          ),
      ],
    );
  }

  Widget _nearbyPanel() {
    if (_nearby.isEmpty) {
      return const Center(
        child: Text(
          'لا توجد طلبات ضمن نطاقك',
          style: TextStyle(color: Colors.white70),
        ),
      );
    }
    return ListView.separated(
      itemCount: _nearby.length,
      separatorBuilder: (_, index) => const SizedBox(height: 8),
      itemBuilder: (_, i) {
        final r = _nearby[i];
        final fare = _asInt(r['proposedFareIqd']) ?? 0;
        final myBid = r['myBid'] is Map
            ? Map<String, dynamic>.from(r['myBid'] as Map)
            : null;
        final myBidId = _asInt(myBid?['id']);
        final currentBidId = _asInt(r['currentBidId']);
        final isCurrentNegotiationBid =
            myBidId != null && currentBidId != null && myBidId == currentBidId;
        final queueTag = myBid == null
            ? 'جديد'
            : isCurrentNegotiationBid
            ? 'دورك الآن'
            : 'بانتظار الدور';
        final queueColor = myBid == null
            ? Colors.lightGreenAccent
            : isCurrentNegotiationBid
            ? Colors.orangeAccent
            : Colors.white70;
        final rideId = _asInt(r['id']) ?? 0;
        return Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.black26,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'طلب #${r['id']}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: queueColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      queueTag,
                      style: TextStyle(
                        color: queueColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'من: ${_str(r['pickup']?['label']) ?? '-'}',
                style: const TextStyle(color: Colors.white70),
              ),
              Text(
                'إلى: ${_str(r['dropoff']?['label']) ?? '-'}',
                style: const TextStyle(color: Colors.white70),
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Text(
                    'سعر الزبون: ${_money(fare)}',
                    style: const TextStyle(color: Colors.greenAccent),
                  ),
                  const Spacer(),
                  if (myBid != null)
                    Text(
                      'عرضك: ${_money(_asInt(myBid['offeredFareIqd']) ?? 0)}',
                      style: const TextStyle(color: Colors.lightBlueAccent),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.tonal(
                    onPressed: _sending ? null : () => _submitBid(r),
                    child: Text(myBid == null ? 'إرسال عرض' : 'تعديل عرضي'),
                  ),
                  if (isCurrentNegotiationBid)
                    OutlinedButton.icon(
                      onPressed: _sending || rideId <= 0
                          ? null
                          : () => _openRideChatBottomSheet(rideId),
                      icon: const Icon(Icons.chat_rounded),
                      label: const Text('دردشة'),
                    ),
                  if (isCurrentNegotiationBid)
                    OutlinedButton.icon(
                      onPressed: _sending
                          ? null
                          : () => _callUser(
                              rideId: rideId,
                              phone: _str(r['customer']?['phone']),
                              remoteDisplayName: _str(
                                r['customer']?['fullName'],
                              ),
                            ),
                      icon: const Icon(Icons.call_rounded),
                      label: const Text('اتصال'),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _dashboardTab() {
    final m = (_dashboard?['metrics'] is Map)
        ? Map<String, dynamic>.from(_dashboard!['metrics'] as Map)
        : <String, dynamic>{};
    final history = (_dashboard?['history'] is List)
        ? _toMapList(_dashboard!['history'])
        : const <Map<String, dynamic>>[];

    int rides(String k) => _asInt((m[k] as Map?)?['ridesCount']) ?? 0;
    int earn(String k) => _asInt((m[k] as Map?)?['earningsIqd']) ?? 0;

    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _subscriptionCard(compact: true),
          const SizedBox(height: 10),
          _metricCard('اليوم', rides('day'), earn('day')),
          _metricCard('الأسبوع', rides('week'), earn('week')),
          _metricCard('الشهر', rides('month'), earn('month')),
          _metricCard('الإجمالي', rides('total'), earn('total')),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            children: [
              _periodChip('day', 'اليوم'),
              _periodChip('week', 'الأسبوع'),
              _periodChip('month', 'الشهر'),
              _periodChip('all', 'الكل'),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'سجل الرحلات',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          if (history.isEmpty)
            const Text(
              'لا توجد رحلات في هذه الفترة',
              style: TextStyle(color: Colors.white70),
            )
          else
            ...history.map(
              (r) => ListTile(
                title: Text(
                  'رحلة #${r['id']}',
                  style: const TextStyle(color: Colors.white),
                ),
                subtitle: Text(
                  '${_status(_str(r['status']))} - ${_str(r['createdAt']) ?? ''}',
                  style: const TextStyle(color: Colors.white70),
                ),
                trailing: Text(
                  _money(
                    _asInt(r['agreedFareIqd']) ??
                        _asInt(r['proposedFareIqd']) ??
                        0,
                  ),
                  style: const TextStyle(color: Colors.greenAccent),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _profileTab() {
    final p = _profileMap;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _subscriptionCard(compact: false),
          const SizedBox(height: 10),
          _profileRow('الاسم', _str(p?['fullName']) ?? '-'),
          _profileRow('الهاتف', _str(p?['phone']) ?? '-'),
          _profileRow('البلوك', _str(p?['block']) ?? '-'),
          _profileRow('العمارة', _str(p?['buildingNumber']) ?? '-'),
          _profileRow('الشقة', _str(p?['apartment']) ?? '-'),
          const Divider(color: Colors.white24),
          _profileRow('شركة السيارة', _str(p?['carMake']) ?? '-'),
          _profileRow('الموديل', _str(p?['carModel']) ?? '-'),
          _profileRow('سنة الصنع', _str(p?['carYear']) ?? '-'),
          _profileRow('اللوحة', _str(p?['plateNumber']) ?? '-'),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _sending ? null : _requestProfileEdit,
            icon: const Icon(Icons.edit_note),
            label: const Text('طلب تعديل البيانات (موافقة الأدمن)'),
          ),
          if (_error != null)
            Text(_error!, style: const TextStyle(color: Colors.amber)),
        ],
      ),
    );
  }

  Widget _subscriptionCard({required bool compact}) {
    final s = _sub;
    final can = s?['canAccess'] == true;
    final pending = s?['cashPaymentPending'] == true;
    final days = _asInt(s?['remainingDays']) ?? 0;
    final fee = _asInt(s?['discountedMonthlyFeeIqd']) ?? 10000;
    final discount = _asInt(s?['discountPercent']) ?? 0;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: can
            ? Colors.teal.withValues(alpha: 0.2)
            : Colors.red.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            can
                ? 'الاشتراك فعال'
                : (pending ? 'بانتظار اعتماد التسديد' : 'الاشتراك منتهي'),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            can ? 'المتبقي: $days يوم' : 'المبلغ المطلوب: ${_money(fee)}',
            style: const TextStyle(color: Colors.white70),
          ),
          Text(
            'الخصم: $discount%',
            style: const TextStyle(color: Colors.white70),
          ),
          if (!can)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: FilledButton(
                onPressed: (pending || _sending) ? null : _requestCashPayment,
                child: Text(
                  pending ? 'تم إرسال طلب التسديد' : 'طلب تسديد نقدي',
                ),
              ),
            ),
          if (!compact && can && days <= 7)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'تنبيه: بقي أقل من أسبوع على انتهاء الاشتراك',
                style: TextStyle(color: Colors.amber),
              ),
            ),
        ],
      ),
    );
  }

  Widget _metricCard(String title, int rides, int earnings) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.black26,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          Text('رحلات: $rides', style: const TextStyle(color: Colors.white70)),
          const SizedBox(width: 12),
          Text(
            _money(earnings),
            style: const TextStyle(color: Colors.greenAccent),
          ),
        ],
      ),
    );
  }

  Widget _periodChip(String value, String label) {
    return ChoiceChip(
      label: Text(label),
      selected: _period == value,
      onSelected: (_) async {
        setState(() => _period = value);
        await _refreshMeta();
      },
    );
  }

  Widget _profileRow(String k, String v) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: const TextStyle(color: Colors.white70)),
          ),
          Expanded(
            child: Text(v, style: const TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  List<Marker> _markers() {
    final list = <Marker>[];
    final pickup = _latLng(_ride?['pickup']);
    final dropoff = _latLng(_ride?['dropoff']);
    if (pickup != null) {
      list.add(
        Marker(
          point: pickup,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.trip_origin,
            color: Colors.greenAccent,
            size: 30,
          ),
        ),
      );
    }
    if (dropoff != null) {
      list.add(
        Marker(
          point: dropoff,
          width: 40,
          height: 40,
          child: const Icon(
            Icons.location_on,
            color: Colors.redAccent,
            size: 32,
          ),
        ),
      );
    }
    if (_captainPoint != null) {
      list.add(
        Marker(
          point: _captainPoint!,
          width: 46,
          height: 46,
          child: const Icon(Icons.local_taxi, color: Colors.white, size: 34),
        ),
      );
    }
    return list;
  }

  LatLng? _latLng(dynamic v) {
    if (v is! Map) return null;
    final m = Map<String, dynamic>.from(v);
    final lat = _asDouble(m['latitude']) ?? _asDouble(m['lat']);
    final lng = _asDouble(m['longitude']) ?? _asDouble(m['lng']);
    if (lat == null || lng == null) return null;
    return LatLng(lat, lng);
  }

  List<Map<String, dynamic>> _toMapList(dynamic v) {
    if (v is! List) return const [];
    return v.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  int? _asInt(dynamic v) => v is int ? v : int.tryParse('${v ?? ''}');
  double? _asDouble(dynamic v) =>
      v is num ? v.toDouble() : double.tryParse('${v ?? ''}');
  String? _str(dynamic v) {
    final s = '${v ?? ''}'.trim();
    return s.isEmpty ? null : s;
  }

  String _money(int n) {
    final s = n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (m) => ',',
    );
    return '$s IQD';
  }

  String _status(String? s) {
    switch (s) {
      case 'searching':
        return 'بحث عن كابتن';
      case 'captain_assigned':
        return 'تم التعيين';
      case 'captain_arriving':
        return 'في الطريق للزبون';
      case 'ride_started':
        return 'الرحلة جارية';
      case 'completed':
        return 'مكتملة';
      case 'cancelled':
        return 'ملغية';
      case 'expired':
        return 'منتهية';
      default:
        return 'غير معروف';
    }
  }

  String _err(DioException e) {
    final data = e.response?.data;
    if (data is Map) {
      final msg = data['message'];
      if (msg is String && msg.isNotEmpty) {
        switch (msg) {
          case 'DELIVERY_SUBSCRIPTION_EXPIRED':
            return 'انتهى الاشتراك. اطلب التسديد النقدي';
          case 'DELIVERY_SUBSCRIPTION_PAYMENT_PENDING':
            return 'تم طلب التسديد، بانتظار موافقة الأدمن';
          case 'DELIVERY_ACCOUNT_PENDING_APPROVAL':
            return 'الحساب بانتظار موافقة الإدارة';
          default:
            return msg;
        }
      }
    }
    return 'تعذر الاتصال بالخادم';
  }

  void _snack(String t) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(t)));
  }

  double? _sanitizeHeading(double v) =>
      (v.isFinite && v >= 0 && v <= 360) ? v : null;
  double? _sanitizeSpeed(double v) => (v.isFinite && v >= 0) ? v * 3.6 : null;
}
