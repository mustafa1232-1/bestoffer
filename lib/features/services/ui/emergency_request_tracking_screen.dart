import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../admin/state/admin_controller.dart';
import '../data/services_api.dart';
import '../emergency/emergency_contacts.dart';

class EmergencyRequestTrackingScreen extends ConsumerStatefulWidget {
  const EmergencyRequestTrackingScreen({
    super.key,
    required this.requestId,
    this.adminMode = false,
  });

  final int requestId;
  final bool adminMode;

  @override
  ConsumerState<EmergencyRequestTrackingScreen> createState() =>
      _EmergencyRequestTrackingScreenState();
}

class _EmergencyRequestTrackingScreenState
    extends ConsumerState<EmergencyRequestTrackingScreen> {
  final _message = TextEditingController();
  final _mapController = MapController();
  Timer? _refreshTimer;
  StreamSubscription<Position>? _positionSubscription;
  Map<String, dynamic>? _thread;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  int? _lastLocationId;

  @override
  void initState() {
    super.initState();
    _load();
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 5),
      (_) => _load(silent: true),
    );
    if (!widget.adminMode) _startLocationSharing();
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _positionSubscription?.cancel();
    _message.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    try {
      final data = widget.adminMode
          ? await ref
                .read(adminApiProvider)
                .getEmergencyThread(widget.requestId)
          : await ref
                .read(servicesApiProvider)
                .getEmergencyThread(widget.requestId);
      if (!mounted) return;
      final locations = _mapList(data['locations']);
      final latest = locations.isEmpty ? null : locations.first;
      final latestId = _asInt(latest?['id']);
      setState(() {
        _thread = data;
        _loading = false;
        _error = null;
      });
      if (latest != null && latestId != _lastLocationId) {
        _lastLocationId = latestId;
        final point = LatLng(
          _asDouble(latest['latitude']),
          _asDouble(latest['longitude']),
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _mapController.move(point, 16);
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent) _error = 'تعذر تحميل قناة الطوارئ. حاول مرة أخرى.';
      });
    }
  }

  Future<void> _startLocationSharing() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return;
      }
      await _positionSubscription?.cancel();
      _positionSubscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.best,
              distanceFilter: 3,
            ),
          ).listen((position) async {
            try {
              await ref
                  .read(servicesApiProvider)
                  .updateEmergencyLocation(
                    requestId: widget.requestId,
                    latitude: position.latitude,
                    longitude: position.longitude,
                    accuracyMeters: position.accuracy,
                    speedMps: position.speed,
                    headingDegrees: position.heading,
                    capturedAt: position.timestamp,
                  );
            } catch (_) {
              // The stream retries naturally with the next position update.
            }
          });
    } catch (_) {
      // The thread remains usable even when location permission is unavailable.
    }
  }

  Future<void> _send() async {
    final text = _message.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      if (widget.adminMode) {
        await ref
            .read(adminApiProvider)
            .sendEmergencyMessage(requestId: widget.requestId, message: text);
      } else {
        await ref
            .read(servicesApiProvider)
            .sendEmergencyMessage(requestId: widget.requestId, message: text);
      }
      _message.clear();
      await _load(silent: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = _asMap(_thread?['request']);
    final locations = _mapList(_thread?['locations']);
    final messages = _mapList(_thread?['messages']);
    final latest = locations.isEmpty ? null : locations.first;
    final target = emergencyContactByKey('${request['emergencyTarget'] ?? ''}');
    final point = latest == null
        ? const LatLng(33.3152, 44.3661)
        : LatLng(_asDouble(latest['latitude']), _asDouble(latest['longitude']));
    final phone = target?.phone ?? '911';

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.adminMode ? 'طلبات الطوارئ' : 'متابعة نداء الطوارئ'),
        actions: [
          IconButton(
            tooltip: 'تحديث',
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading && _thread == null
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _thread == null
          ? Center(
              child: FilledButton.icon(
                onPressed: _load,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(_error!),
              ),
            )
          : Column(
              children: [
                Container(
                  width: double.infinity,
                  color: Theme.of(context).colorScheme.errorContainer,
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(target?.icon ?? Icons.sos_rounded),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '${target?.title ?? 'طوارئ'} - ${request['requestCode'] ?? '#${widget.requestId}'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            if (widget.adminMode)
                              Text(
                                '${request['customerFullName'] ?? 'مستخدم'}  ${request['customerPhone'] ?? ''}',
                                textDirection: TextDirection.rtl,
                              ),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                        onPressed: () =>
                            launchUrl(Uri(scheme: 'tel', path: phone)),
                        icon: const Icon(Icons.call_rounded),
                        label: Text(phone),
                      ),
                    ],
                  ),
                ),
                SizedBox(
                  height: 250,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(initialCenter: point, initialZoom: 16),
                    children: [
                      TileLayer(
                        urlTemplate:
                            'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'app.maslaki.user',
                      ),
                      MarkerLayer(
                        markers: latest == null
                            ? const []
                            : [
                                Marker(
                                  point: point,
                                  width: 52,
                                  height: 52,
                                  child: const Icon(
                                    Icons.location_on_rounded,
                                    color: Color(0xFFC62828),
                                    size: 46,
                                  ),
                                ),
                              ],
                      ),
                    ],
                  ),
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  color: Theme.of(context).colorScheme.surfaceContainerLow,
                  child: Text(
                    latest == null
                        ? 'بانتظار أول تحديث للموقع'
                        : 'الموقع الحي فعال - آخر تحديث ${_timeLabel(latest['capturedAt'])}',
                    textAlign: TextAlign.right,
                    textDirection: TextDirection.rtl,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                Expanded(
                  child: messages.isEmpty
                      ? const Center(
                          child: Text(
                            'قناة التواصل جاهزة. اكتب أي تفاصيل مهمة هنا.',
                            textDirection: TextDirection.rtl,
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: messages.length,
                          itemBuilder: (context, index) {
                            final item = messages[index];
                            final fromAdmin =
                                item['senderRole'] == 'super_admin';
                            final mine = widget.adminMode
                                ? fromAdmin
                                : !fromAdmin;
                            return Align(
                              alignment: mine
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: Container(
                                constraints: const BoxConstraints(
                                  maxWidth: 330,
                                ),
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.all(11),
                                decoration: BoxDecoration(
                                  color: mine
                                      ? Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer
                                      : Theme.of(
                                          context,
                                        ).colorScheme.surfaceContainerHighest,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  '${item['message'] ?? ''}',
                                  textDirection: TextDirection.rtl,
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Row(
          textDirection: TextDirection.rtl,
          children: [
            Expanded(
              child: TextField(
                controller: _message,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                decoration: const InputDecoration(
                  hintText: 'اكتب تفاصيل أو رسالة عاجلة...',
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              tooltip: 'إرسال',
              onPressed: _sending ? null : _send,
              icon: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send_rounded),
            ),
          ],
        ),
      ),
    );
  }
}

Map<String, dynamic> _asMap(dynamic value) => value is Map
    ? value.map((key, item) => MapEntry('$key', item))
    : <String, dynamic>{};

List<Map<String, dynamic>> _mapList(dynamic value) => value is List
    ? value.whereType<Map>().map(_asMap).toList()
    : <Map<String, dynamic>>[];

int _asInt(dynamic value) => int.tryParse('$value') ?? 0;
double _asDouble(dynamic value) => double.tryParse('$value') ?? 0;

String _timeLabel(dynamic value) {
  final date = DateTime.tryParse('${value ?? ''}')?.toLocal();
  if (date == null) return 'الآن';
  return '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
}
