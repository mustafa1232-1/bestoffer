import 'dart:math' as math;
import 'dart:async';

import 'package:maslaki/core/constants/api.dart';
import 'package:maslaki/core/i18n/app_localizations_context.dart';
import 'package:maslaki/core/i18n/locale_text.dart';
import 'package:maslaki/core/media/cached_app_image.dart';
import 'package:maslaki/core/utils/currency.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/core/network/session_invalidation.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/ui/taxi_share_ride_friends_sheet.dart';
import 'package:maslaki/features/taxi/domain/taxi_assignment_contract.dart';
import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../tracking_map_utils.dart';
import 'live_tracking_shell.dart';

class TaxiLiveTrackingScreen extends ConsumerStatefulWidget {
  final int rideId;
  final bool sharedReadonly;
  final String? publicToken;
  final Map<String, dynamic>? initialEnvelope;

  const TaxiLiveTrackingScreen({
    super.key,
    required this.rideId,
    this.sharedReadonly = false,
    this.publicToken,
    this.initialEnvelope,
  });

  @override
  ConsumerState<TaxiLiveTrackingScreen> createState() =>
      _TaxiLiveTrackingScreenState();
}

class _TaxiLiveTrackingScreenState extends ConsumerState<TaxiLiveTrackingScreen>
    with WidgetsBindingObserver {
  Map<String, dynamic>? _envelope;
  bool _loading = true;
  String? _error;
  StreamSubscription<TaxiLiveEvent>? _streamSub;
  Timer? _pollTimer;
  int? _lastEventId;
  Timer? _reconnectTimer;
  int _reconnectAttempt = 0;
  bool _lifecycleResumed = true;
  bool _submitting = false;
  late final VoidCallback _sessionInvalidationListener;

  TaxiApi get _taxiApi => ref.read(taxiApiProvider);

  bool get _isPublic => widget.publicToken != null;
  bool get _isReadonly => _isPublic || widget.sharedReadonly;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sessionInvalidationListener = _handleSessionInvalidation;
    SessionInvalidationBus.instance.addListener(_sessionInvalidationListener);
    _envelope = widget.initialEnvelope;
    _loading = widget.initialEnvelope == null;
    unawaited(_load(silent: widget.initialEnvelope != null));
    _startLiveUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    SessionInvalidationBus.instance.removeListener(
      _sessionInvalidationListener,
    );
    _stopLiveUpdates();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleResumed = state == AppLifecycleState.resumed;
    if (_lifecycleResumed) {
      if (taxiTrackingIsActive(_envelope)) {
        unawaited(_load(silent: true));
        _startLiveUpdates();
      }
    } else {
      _stopLiveUpdates();
    }
  }

  void _handleSessionInvalidation() {
    if (!mounted) return;
    _stopLiveUpdates();
    setState(() {
      _envelope = null;
      _loading = false;
      _error = null;
    });
  }

  void _startLiveUpdates() {
    if (!_lifecycleResumed || !taxiTrackingIsActive(_envelope)) return;
    _reconnectTimer?.cancel();
    _connectStream();
    _pollTimer?.cancel();
    _pollTimer = Timer.periodic(Duration(seconds: _isPublic ? 12 : 6), (_) {
      if (_lifecycleResumed && taxiTrackingIsActive(_envelope)) {
        unawaited(_load(silent: true));
      }
    });
  }

  void _stopLiveUpdates() {
    _streamSub?.cancel();
    _streamSub = null;
    _pollTimer?.cancel();
    _pollTimer = null;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
  }

  void _scheduleReconnect() {
    if (!_lifecycleResumed || !taxiTrackingIsActive(_envelope)) return;
    if (_reconnectTimer?.isActive == true) return;
    _reconnectAttempt = (_reconnectAttempt + 1).clamp(1, 6);
    final seconds = <int>[2, 4, 8, 12, 20, 30][_reconnectAttempt - 1];
    _reconnectTimer = Timer(Duration(seconds: seconds), _startLiveUpdates);
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
      if (!taxiTrackingIsActive(_envelope)) _stopLiveUpdates();
    }
    try {
      final data =
          await (_isPublic
                  ? _taxiApi.publicTrackByToken(widget.publicToken!)
                  : widget.sharedReadonly
                  ? _taxiApi.getSharedRideTrack(rideId: widget.rideId)
                  : _taxiApi.getRideDetails(widget.rideId))
              .timeout(const Duration(seconds: 15));
      if (!mounted) return;
      setState(() {
        _envelope = trackingMap(data) ?? const <String, dynamic>{};
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'Ã˜ÂªÃ˜Â¹Ã˜Â°Ã˜Â± Ã˜ÂªÃ˜Â­Ã™â€¦Ã™Å Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ˜ÂªÃ˜Â¨Ã˜Â¹ Ã˜Â§Ã™â€žÃ˜Â­Ã™Å  Ã™â€žÃ™â€¡Ã˜Â°Ã™â€¡ Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â©.',
          en: 'Failed to load live tracking for this ride.',
        );
      });
    }
  }

  void _connectStream() {
    _streamSub?.cancel();
    final stream = _isPublic
        ? _taxiApi.streamPublicTrackByToken(widget.publicToken!)
        : _taxiApi.streamRideEvents(
            rideId: widget.rideId,
            lastEventId: _lastEventId,
          );
    _streamSub = stream.listen(
      (event) {
        if (!mounted) return;
        _reconnectAttempt = 0;
        if (event.eventId != null) {
          _lastEventId = event.eventId;
        }
        if (_isPublic) {
          if (event.event == 'taxi_location_update') {
            setState(() {
              _envelope = mergeTaxiTrackingEvent(_envelope, event.data);
              _loading = false;
              _error = null;
            });
            if (!taxiTrackingIsActive(_envelope)) _stopLiveUpdates();
          } else if (event.event == 'resync_required' ||
              event.event == 'closed') {
            unawaited(_load(silent: true));
            _scheduleReconnect();
          }
          return;
        }

        if (event.event == 'resync_required') {
          unawaited(_load(silent: true));
          return;
        }

        final eventRideId =
            _readInt(event.data['rideId']) ??
            _readInt(
              event.data['ride'] is Map
                  ? (event.data['ride'] as Map)['id']
                  : null,
            );
        if (eventRideId != widget.rideId) return;
        if (event.event == 'taxi_location_update' ||
            event.event.startsWith('taxi_')) {
          setState(() {
            _envelope = mergeTaxiTrackingEvent(_envelope, event.data);
            _loading = false;
            _error = null;
          });
          if (!taxiTrackingIsActive(_envelope)) _stopLiveUpdates();
        }
      },
      onError: (error, stack) {
        unawaited(_load(silent: true));
        _scheduleReconnect();
      },
      onDone: _scheduleReconnect,
    );
  }

  // ignore: unused_element
  Future<void> _shareRide() async {
    final auth = ref.read(authControllerProvider);
    final currentUserId = auth.user?.id;
    if (_isReadonly || currentUserId == null) return;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.public_rounded),
                title: Text(
                  context.lt(
                    ar: 'Ã™â€¦Ã˜Â´Ã˜Â§Ã˜Â±Ã™Æ’Ã˜Â© Ã˜Â¹Ã˜Â§Ã™â€¦Ã˜Â©',
                    en: 'Public share',
                  ),
                ),
                subtitle: Text(
                  context.lt(
                    ar: 'Ã™Å Ã™â€ Ã˜Â´Ã˜Â¦ Ã˜Â±Ã˜Â§Ã˜Â¨Ã˜Â· Ã˜ÂªÃ˜ÂªÃ˜Â¨Ã˜Â¹ Ã˜Â¹Ã˜Â§Ã™â€¦ Ã™â€žÃ™â€žÃ™â€šÃ˜Â±Ã˜Â§Ã˜Â¡Ã˜Â© Ã™ÂÃ™â€šÃ˜Â·.',
                    en: 'Creates a public readonly tracking link.',
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final shareTextPrefix = this.context.lt(
                    ar: 'ØªØªØ¨Ø¹ Ø±Ø­Ù„Ø© Ù…Ø³Ù„ÙƒÙŠ:',
                    en: 'Track my Maslaki ride:',
                  );
                  final out = await _taxiApi.createPublicShareToken(
                    widget.rideId,
                  );
                  final token = (out['token'] ?? '').toString().trim();
                  if (token.isEmpty) return;
                  final url = '${Api.baseUrl}/api/taxi/public/track/$token';
                  await SharePlus.instance.share(
                    ShareParams(text: '$shareTextPrefix\n$url'),
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.group_outlined),
                title: Text(
                  context.lt(
                    ar: 'Ã™â€¦Ã˜Â´Ã˜Â§Ã˜Â±Ã™Æ’Ã˜Â© Ã™â€¦Ã˜Â¹ Ã˜Â§Ã™â€žÃ˜Â£Ã˜ÂµÃ˜Â¯Ã™â€šÃ˜Â§Ã˜Â¡',
                    en: 'Share with friends',
                  ),
                ),
                subtitle: Text(
                  context.lt(
                    ar: 'Ã˜ÂªÃ˜Â´Ã˜Â§Ã˜Â±Ã™Æ’ Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â© Ã˜Â¯Ã˜Â§Ã˜Â®Ã™â€ž Ã˜Â§Ã™â€žÃ˜ÂªÃ˜Â·Ã˜Â¨Ã™Å Ã™â€š Ã™â€¦Ã˜Â¹ Ã˜Â£Ã˜ÂµÃ˜Â¯Ã™â€šÃ˜Â§Ã˜Â¦Ã™Æ’.',
                    en: 'Shares the ride inside the app with your friends.',
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  await showTaxiRideShareFriendsSheet(
                    context: this.context,
                    ref: ref,
                    rideId: widget.rideId,
                    currentUserId: currentUserId,
                    taxiApi: _taxiApi,
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _callCaptain() async {
    final phone =
        _string(_ride?['captainPhone']) ??
        _string(_captain?['phone']) ??
        _string(_captain?['captainPhone']);
    if (phone == null || phone.isEmpty) return;
    await launchUrl(
      Uri.parse('tel:$phone'),
      mode: LaunchMode.externalApplication,
    );
  }

  Future<void> _cancelRide() async {
    if (_isReadonly || !_isActiveRide(_ride ?? const <String, dynamic>{})) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(context.lt(ar: 'إلغاء الرحلة', en: 'Cancel ride')),
          content: Text(
            context.lt(
              ar: 'هل تريد إلغاء هذه الرحلة الآن؟',
              en: 'Do you want to cancel this ride now?',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(context.lt(ar: 'لا', en: 'No')),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(context.lt(ar: 'نعم', en: 'Yes')),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !mounted) return;

    setState(() {
      _submitting = true;
    });

    try {
      await _taxiApi.cancelRide(widget.rideId);
      await _load(silent: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = context.lt(
          ar: 'تعذر إلغاء الرحلة حالياً.',
          en: 'Unable to cancel the ride right now.',
        );
      });
    } finally {
      if (mounted) {
        setState(() {
          _submitting = false;
        });
      }
    }
  }

  Future<void> _openRideChat() async {
    if (_isReadonly) return;
    final controller = TextEditingController();
    List<Map<String, dynamic>> messages = const [];
    var loading = true;
    var sending = false;
    String? error;

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        Future<void> loadMessages(StateSetter setModalState) async {
          try {
            final items = await _taxiApi.listRideChat(
              rideId: widget.rideId,
              limit: 120,
            );
            setModalState(() {
              messages = items;
              loading = false;
              error = null;
            });
          } catch (_) {
            setModalState(() {
              loading = false;
              error = this.context.l10n.mapPageRideChatLoadFailed;
            });
          }
        }

        return StatefulBuilder(
          builder: (context, setModalState) {
            if (loading && messages.isEmpty && error == null) {
              unawaited(loadMessages(setModalState));
            }
            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
                top: 8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    this.context.l10n.mapPageRideChatTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    height: 280,
                    child: loading
                        ? const Center(child: CircularProgressIndicator())
                        : error != null
                        ? Center(child: Text(error!))
                        : messages.isEmpty
                        ? Center(
                            child: Text(this.context.l10n.mapPageRideChatEmpty),
                          )
                        : ListView.builder(
                            reverse: true,
                            itemCount: messages.length,
                            itemBuilder: (context, index) {
                              final item =
                                  messages[messages.length - 1 - index];
                              final mine =
                                  _readInt(item['senderUserId']) ==
                                  ref.read(authControllerProvider).user?.id;
                              return Align(
                                alignment: mine
                                    ? AlignmentDirectional.centerEnd
                                    : AlignmentDirectional.centerStart,
                                child: Container(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: mine
                                        ? context.maslakiTokens.primaryAccent
                                              .withValues(alpha: 0.18)
                                        : context.maslakiTokens.cardPrimary,
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: context.maslakiTokens.borderSubtle,
                                    ),
                                  ),
                                  child: Text(
                                    _string(
                                          item['messageText'] ??
                                              item['message_text'],
                                        ) ??
                                        '',
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      IconButton(
                        onPressed: sending
                            ? null
                            : () async {
                                final text = controller.text.trim();
                                if (text.isEmpty) return;
                                setModalState(() => sending = true);
                                try {
                                  await _taxiApi.sendRideChatMessage(
                                    rideId: widget.rideId,
                                    messageText: text,
                                  );
                                  controller.clear();
                                  await loadMessages(setModalState);
                                } finally {
                                  if (context.mounted) {
                                    setModalState(() => sending = false);
                                  }
                                }
                              },
                        icon: const Icon(Icons.send_rounded),
                      ),
                      Expanded(
                        child: TextField(
                          controller: controller,
                          textInputAction: TextInputAction.send,
                          onSubmitted: (_) async {},
                          decoration: InputDecoration(
                            hintText: this.context.lt(
                              ar: 'Ã˜Â§Ã™Æ’Ã˜ÂªÃ˜Â¨ Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€žÃ˜Â©...',
                              en: 'Type a message...',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _openRideDetails() async {
    final ride = _ride;
    if (ride == null || !mounted) return;

    final captain = _captain;
    final vehicle = trackingMap(ride['vehicle']);
    final rideId = _readInt(ride['rideId'] ?? ride['id']);
    final statusLabel = _statusLabel(_string(ride['status']) ?? '');
    final finalFare =
        ride['finalFare'] ?? ride['agreedFareIqd'] ?? ride['customerFare'];

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) {
        final tokens = context.maslakiTokens;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            8,
            16,
            16 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              Text(
                context.lt(ar: 'تفاصيل الرحلة', en: 'Ride details'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _TaxiInfoTile(
                title: context.lt(ar: 'رقم الرحلة', en: 'Ride number'),
                value: rideId != null && rideId > 0 ? '#$rideId' : '-',
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'الحالة', en: 'Status'),
                value: statusLabel,
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'السائق', en: 'Captain'),
                value:
                    _string(ride['captainName']) ??
                    _string(captain?['fullName']) ??
                    context.lt(ar: 'غير متوفر', en: 'Not available'),
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'المركبة', en: 'Vehicle'),
                value: _formatVehicleSummary(
                  vehicle,
                  captain,
                  context.lt(ar: 'غير متوفر', en: 'Not available'),
                ),
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'نقطة الاستلام', en: 'Pickup'),
                value:
                    trackingNestedString(ride['pickup'], const ['label']) ??
                    _string(ride['pickupAddress']) ??
                    context.lt(ar: 'غير متوفر', en: 'Not available'),
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'الوجهة', en: 'Destination'),
                value:
                    trackingNestedString(ride['dropoff'], const ['label']) ??
                    _string(ride['destinationAddress']) ??
                    context.lt(ar: 'غير متوفر', en: 'Not available'),
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'الأجرة النهائية', en: 'Final fare'),
                value: _formatRideFareLabel(
                  context,
                  finalFare,
                  context.lt(ar: 'بانتظار تحديد السعر', en: 'Waiting for fare'),
                ),
              ),
              if (_latestLocation != null)
                _TaxiInfoTile(
                  title: context.lt(ar: 'آخر تحديث', en: 'Last update'),
                  value:
                      trackingNestedString(_latestLocation, const [
                        'updatedAt',
                      ]) ??
                      trackingNestedString(_latestLocation, const [
                        'createdAt',
                      ]) ??
                      context.lt(ar: 'غير متوفر', en: 'Not available'),
                ),
            ],
          ),
        );
      },
    );
  }

  bool _isTerminalRide(Map<String, dynamic> ride) {
    final status = _string(ride['status'])?.toLowerCase();
    return status == 'completed' ||
        status == 'cancelled' ||
        status == 'expired';
  }

  bool _isActiveRide(Map<String, dynamic> ride) {
    final status = _string(ride['status'])?.toLowerCase();
    return status == 'captain_assigned' ||
        status == 'captain_arriving' ||
        status == 'ride_started';
  }

  bool _isBeforePickup(Map<String, dynamic> ride) {
    final status = _string(ride['status'])?.toLowerCase();
    return status == 'captain_assigned' || status == 'captain_arriving';
  }

  bool _canCancelRide(Map<String, dynamic> ride) {
    return _isBeforePickup(ride);
  }

  String _phaseMessage(Map<String, dynamic> ride) {
    final status = _string(ride['status'])?.toLowerCase();
    switch (status) {
      case 'captain_assigned':
        return context.lt(
          ar: 'الكابتن في الطريق إلى نقطة الاستلام',
          en: 'Captain is heading to pickup',
        );
      case 'captain_arriving':
        return context.lt(
          ar: 'الكابتن يقترب من نقطة الاستلام',
          en: 'Captain is arriving at pickup',
        );
      case 'ride_started':
        return context.lt(
          ar: 'الرحلة جارية إلى الوجهة',
          en: 'Ride is on the way to the destination',
        );
      case 'completed':
        return context.lt(
          ar: 'اكتملت الرحلة بنجاح',
          en: 'Ride completed successfully',
        );
      case 'cancelled':
        return context.lt(ar: 'تم إلغاء الرحلة', en: 'Ride was cancelled');
      default:
        return context.lt(ar: 'تم تعيين الرحلة', en: 'Ride assigned');
    }
  }

  String _formatDistanceLabel(double? distanceMeters) {
    if (distanceMeters == null || distanceMeters <= 0) {
      return context.lt(ar: 'غير متوفر', en: 'Not available');
    }
    if (distanceMeters < 1000) {
      return '${distanceMeters.round()} m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(distanceMeters >= 10000 ? 0 : 1)} km';
  }

  String _formatDurationLabel(int? durationSeconds) {
    if (durationSeconds == null || durationSeconds <= 0) {
      return context.lt(ar: 'غير متوفر', en: 'Not available');
    }
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) return '$minutes min';
    final hours = minutes ~/ 60;
    final remaining = minutes % 60;
    if (remaining == 0) return '$hours h';
    return '$hours h $remaining min';
  }

  String _formatEtaLabel(int? minutes) {
    if (minutes == null || minutes <= 0) {
      return context.lt(ar: 'غير متوفر', en: 'Not available');
    }
    return '$minutes min';
  }

  String _formatVehicleSummary(
    Map<String, dynamic>? vehicle,
    Map<String, dynamic>? captain,
    String fallback,
  ) {
    final parts = <String?>[
      _string(vehicle?['vehicleMake'] ?? captain?['carMake']),
      _string(vehicle?['vehicleModel'] ?? captain?['carModel']),
      _readInt(vehicle?['vehicleYear'] ?? captain?['carYear'])?.toString(),
    ].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    if (parts.isEmpty) return fallback;
    return parts.join(' • ');
  }

  bool _isLocationStale(Map<String, dynamic>? location) {
    final updatedAt = DateTime.tryParse(
      _string(location?['updatedAt'] ?? location?['createdAt']) ?? '',
    );
    if (updatedAt == null) return false;
    return DateTime.now().difference(updatedAt).inSeconds > 120;
  }

  Widget _buildTrackingSheet(
    BuildContext context,
    ScrollController scrollController,
    Map<String, dynamic> ride,
  ) {
    final tokens = context.maslakiTokens;
    final displayState = taxiRideDisplayState(ride);
    final isWaitingState =
        displayState == 'searching' || displayState == 'negotiating';
    final isTerminalState = _isTerminalRide(ride);
    final isActiveState = displayState == 'active';
    final rideStatus = _string(ride['status']) ?? '';
    final nonAvailable = context.lt(ar: 'غير متوفر', en: 'Not available');

    final captain = _captain;
    final vehicle = trackingMap(ride['vehicle']);
    final finalFare =
        ride['finalFare'] ??
        ride['agreedFareIqd'] ??
        ride['customerFare'] ??
        ride['proposedFareIqd'];
    final paymentMethod = _string(
      ride['paymentMethod'] ?? ride['paymentType'] ?? ride['payment_method'],
    );
    final pickupLabel =
        trackingNestedString(ride['pickup'], const ['label']) ??
        _string(ride['pickupAddress']) ??
        nonAvailable;
    final dropoffLabel =
        trackingNestedString(ride['dropoff'], const ['label']) ??
        _string(ride['destinationAddress']) ??
        nonAvailable;
    final currentLocation = _latestLocation;
    final captainName =
        _string(ride['captainName']) ??
        _string(captain?['fullName']) ??
        nonAvailable;
    final captainPhoto =
        _string(ride['captainPhotoUrl']) ??
        _string(captain?['profileImageUrl']) ??
        _string(captain?['imageUrl']) ??
        _string(captain?['photoUrl']);
    final captainPhone =
        _string(ride['captainPhone']) ??
        _string(captain?['phone']) ??
        _string(captain?['captainPhone']);
    final captainRating =
        _readNum(ride['captainRating']) ?? _readNum(captain?['ratingAvg']);
    final captainRatingCount =
        _readInt(ride['captainRatingCount']) ??
        _readInt(captain?['ratingCount']) ??
        _readInt(captain?['ridesCount']);
    final captainCompletedTrips =
        _readInt(ride['captainCompletedTrips']) ??
        _readInt(captain?['ridesCount']);
    final captainDistanceMeters = _readNum(ride['captainDistanceMeters']);
    final estimatedArrivalMinutes = _readInt(
      ride['captainEstimatedArrivalMinutes'] ?? ride['estimatedArrivalMinutes'],
    );
    final routeDistance = _readNum(
      ride['distanceMeters'] ??
          ride['routeDistance'] ??
          ride['routeDistanceMeters'],
    );
    final routeDuration = _readInt(
      ride['durationSeconds'] ??
          ride['routeDuration'] ??
          ride['routeDurationSeconds'],
    );
    final currentLocationAgeStale = _isLocationStale(currentLocation);
    final currentLocationUpdatedAt =
        trackingNestedString(currentLocation, const ['updatedAt']) ??
        trackingNestedString(currentLocation, const ['createdAt']) ??
        nonAvailable;

    Widget sectionCard(Widget child) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tokens.cardPrimary.withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: tokens.primaryAccent.withValues(alpha: 0.18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: child,
      );
    }

    Widget sectionHeader({
      required IconData icon,
      required String title,
      String? subtitle,
    }) {
      return Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: tokens.primaryAccent.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: tokens.primaryAccent, size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                  ),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    textAlign: TextAlign.end,
                    style: TextStyle(color: tokens.textSecondary, fontSize: 12),
                  ),
                ],
              ],
            ),
          ),
        ],
      );
    }

    Widget statChip(String label, String value, {IconData? icon}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: tokens.surfaceSecondary.withValues(alpha: 0.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 16, color: tokens.primaryAccent),
              const SizedBox(width: 6),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: tokens.textSecondary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  style: TextStyle(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      );
    }

    if (isWaitingState) {
      return ListView(
        controller: scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
        children: [
          Text(
            displayState == 'negotiating'
                ? context.lt(
                    ar: 'جاري التفاوض مع الكابتن',
                    en: 'Negotiation in progress',
                  )
                : context.lt(
                    ar: 'جاري البحث عن كابتن',
                    en: 'Searching for a captain',
                  ),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              color: tokens.textPrimary,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          sectionCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                sectionHeader(
                  icon: Icons.route_rounded,
                  title: context.lt(ar: 'الحالة الحالية', en: 'Current status'),
                  subtitle: _phaseMessage(ride),
                ),
                const SizedBox(height: 12),
                _TaxiInfoTile(
                  title: context.lt(ar: 'الانطلاق', en: 'Pickup'),
                  value: pickupLabel,
                ),
                _TaxiInfoTile(
                  title: context.lt(ar: 'الوجهة', en: 'Destination'),
                  value: dropoffLabel,
                ),
                _TaxiInfoTile(
                  title: context.lt(ar: 'الأجرة', en: 'Fare'),
                  value: _formatRideFareLabel(context, finalFare, nonAvailable),
                ),
                const SizedBox(height: 4),
                Text(
                  displayState == 'negotiating'
                      ? context.lt(
                          ar: 'بانتظار قبول العرض أو إرسال عرض مضاد.',
                          en: 'Waiting for the captain to respond.',
                        )
                      : context.lt(
                          ar: 'سيبدأ التتبع الحي بعد تعيين الكابتن.',
                          en: 'Live tracking starts after a captain is assigned.',
                        ),
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView(
      controller: scrollController,
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
      children: [
        sectionCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionHeader(
                icon: Icons.local_taxi_rounded,
                title: context.lt(ar: 'الحالة الحالية', en: 'Current status'),
                subtitle: _phaseMessage(ride),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  statChip(
                    context.lt(ar: 'الوصول', en: 'ETA'),
                    _formatEtaLabel(estimatedArrivalMinutes),
                    icon: Icons.schedule_rounded,
                  ),
                  statChip(
                    context.lt(ar: 'المتبقي', en: 'Distance'),
                    _formatDistanceLabel(
                      captainDistanceMeters ?? routeDistance,
                    ),
                    icon: Icons.straighten_rounded,
                  ),
                  statChip(
                    context.lt(ar: 'التحديث', en: 'Update'),
                    currentLocationAgeStale
                        ? context.lt(ar: 'قديم', en: 'Stale')
                        : currentLocationUpdatedAt,
                    icon: currentLocationAgeStale
                        ? Icons.warning_amber_rounded
                        : Icons.bolt_rounded,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        sectionCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionHeader(
                icon: Icons.person_pin_circle_rounded,
                title: context.lt(
                  ar: 'الكابتن والمركبة',
                  en: 'Captain and vehicle',
                ),
                subtitle: captainName,
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (captainPhoto != null) ...[
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: tokens.surfaceSecondary,
                      backgroundImage: AppCachedImageProvider(captainPhoto),
                    ),
                    const SizedBox(width: 12),
                  ] else ...[
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: tokens.surfaceSecondary,
                      child: Icon(
                        Icons.person_rounded,
                        color: tokens.primaryAccent,
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          captainName,
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.end,
                          children: [
                            if (captainRating != null && captainRating > 0)
                              statChip(
                                context.lt(ar: 'التقييم', en: 'Rating'),
                                '${captainRating.toStringAsFixed(1)}${captainRatingCount != null ? ' • $captainRatingCount' : ''}',
                                icon: Icons.star_rounded,
                              ),
                            if (captainCompletedTrips != null &&
                                captainCompletedTrips > 0)
                              statChip(
                                context.lt(ar: 'الرحلات', en: 'Trips'),
                                '$captainCompletedTrips',
                                icon: Icons.emoji_transportation_rounded,
                              ),
                            if (captainPhone != null && captainPhone.isNotEmpty)
                              statChip(
                                context.lt(ar: 'الهاتف', en: 'Phone'),
                                captainPhone,
                                icon: Icons.call_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (vehicle != null &&
                      _string(vehicle['vehicleImage']) != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: CachedAppImage(
                        imageUrl: _string(vehicle['vehicleImage'])!,
                        width: 92,
                        height: 60,
                        fit: BoxFit.cover,
                      ),
                    )
                  else
                    Container(
                      width: 92,
                      height: 60,
                      decoration: BoxDecoration(
                        color: tokens.surfaceSecondary,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: tokens.borderSubtle),
                      ),
                      child: Icon(
                        Icons.directions_car_rounded,
                        color: tokens.primaryAccent,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          _formatVehicleSummary(
                            vehicle,
                            captain,
                            context.lt(
                              ar: 'معلومات المركبة غير مكتملة',
                              en: 'Vehicle information not complete',
                            ),
                          ),
                          textAlign: TextAlign.end,
                          style: TextStyle(
                            color: tokens.textPrimary,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          [
                                _string(
                                  vehicle?['vehicleColor'] ??
                                      captain?['carColor'],
                                ),
                                _string(
                                  vehicle?['vehicleType'] ??
                                      captain?['vehicleType'],
                                ),
                                _string(
                                  vehicle?['vehiclePlate'] ??
                                      captain?['plateNumber'],
                                ),
                                _string(vehicle?['vehicleNumber']),
                              ]
                              .whereType<String>()
                              .where((value) => value.trim().isNotEmpty)
                              .join(' • '),
                          textAlign: TextAlign.end,
                          style: TextStyle(color: tokens.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        sectionCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionHeader(
                icon: Icons.alt_route_rounded,
                title: context.lt(
                  ar: 'نقطة الالتقاط والوجهة',
                  en: 'Pickup and destination',
                ),
                subtitle: context.lt(
                  ar: 'المسافة والوقت المتوقع',
                  en: 'Distance and ETA',
                ),
              ),
              const SizedBox(height: 12),
              _TaxiInfoTile(
                title: context.lt(ar: 'الانطلاق', en: 'Pickup'),
                value: pickupLabel,
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'الوجهة', en: 'Destination'),
                value: dropoffLabel,
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'الوقت المتوقع', en: 'ETA'),
                value: _formatEtaLabel(estimatedArrivalMinutes),
              ),
              _TaxiInfoTile(
                title: context.lt(
                  ar: 'المسافة المتبقية',
                  en: 'Remaining distance',
                ),
                value: _formatDistanceLabel(
                  taxiRideHasPickedUp(ride)
                      ? routeDistance
                      : captainDistanceMeters,
                ),
              ),
              if (routeDuration != null)
                _TaxiInfoTile(
                  title: context.lt(ar: 'مدة الرحلة', en: 'Trip duration'),
                  value: _formatDurationLabel(routeDuration),
                ),
            ],
          ),
        ),
        if (isActiveState) ...[
          const SizedBox(height: 12),
          sectionCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                sectionHeader(
                  icon: Icons.contact_support_rounded,
                  title: context.lt(ar: 'إجراءات الرحلة', en: 'Ride actions'),
                  subtitle: context.lt(
                    ar: 'اتصال ومراسلة وتفاصيل الرحلة والمشاركة',
                    en: 'Call, message, ride details, and sharing',
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    if (captainPhone != null && captainPhone.isNotEmpty)
                      FilledButton.icon(
                        onPressed: _callCaptain,
                        icon: const Icon(Icons.call_outlined),
                        label: Text(context.lt(ar: 'اتصال', en: 'Call')),
                      ),
                    OutlinedButton.icon(
                      onPressed: _openRideChat,
                      icon: const Icon(Icons.chat_bubble_outline_rounded),
                      label: Text(
                        context.lt(ar: 'مراسلة السائق', en: 'Message captain'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _openRideDetails,
                      icon: const Icon(Icons.info_outline_rounded),
                      label: Text(
                        context.lt(ar: 'تفاصيل الرحلة', en: 'Ride details'),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: _shareRide,
                      icon: const Icon(Icons.share_rounded),
                      label: Text(
                        context.lt(ar: 'مشاركة الرحلة', en: 'Share ride'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        sectionCard(
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      context.lt(ar: 'الأجرة النهائية', en: 'Final fare'),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: tokens.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _formatRideFareLabel(
                        context,
                        finalFare,
                        context.lt(
                          ar: 'بانتظار تحديد السعر',
                          en: 'Waiting for fare',
                        ),
                      ),
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        color: tokens.textPrimary,
                        fontWeight: FontWeight.w900,
                        fontSize: 22,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      paymentMethod == null || paymentMethod.isEmpty
                          ? context.lt(
                              ar: 'طريقة الدفع غير محددة',
                              en: 'Payment method not set',
                            )
                          : '${context.lt(ar: 'الدفع', en: 'Payment')}: $paymentMethod',
                      textAlign: TextAlign.end,
                      style: TextStyle(color: tokens.textSecondary),
                    ),
                  ],
                ),
              ),
              if (_canCancelRide(ride)) ...[
                const SizedBox(width: 12),
                OutlinedButton.icon(
                  onPressed: _submitting ? null : _cancelRide,
                  icon: const Icon(Icons.close_rounded),
                  label: Text(
                    context.lt(ar: 'إلغاء الرحلة', en: 'Cancel ride'),
                  ),
                ),
              ],
            ],
          ),
        ),
        if (isTerminalState) ...[
          const SizedBox(height: 12),
          sectionCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                sectionHeader(
                  icon: rideStatus == 'completed'
                      ? Icons.check_circle_rounded
                      : Icons.block_rounded,
                  title: rideStatus == 'completed'
                      ? context.lt(ar: 'الرحلة منتهية', en: 'Ride completed')
                      : context.lt(ar: 'الرحلة ملغاة', en: 'Ride cancelled'),
                  subtitle: _phaseMessage(ride),
                ),
                const SizedBox(height: 8),
                Text(
                  context.lt(
                    ar: 'يمكنك مراجعة التفاصيل أو مشاركة الرحلة إن كانت متاحة.',
                    en: 'You can review the ride details or share it if available.',
                  ),
                  textAlign: TextAlign.end,
                  style: TextStyle(color: tokens.textSecondary),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 12),
        sectionCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sectionHeader(
                icon: Icons.timeline_rounded,
                title: context.lt(ar: 'خط زمني للرحلة', en: 'Ride timeline'),
                subtitle: context.lt(
                  ar: 'المراحل المهمة للرحلة الحالية',
                  en: 'Important ride milestones',
                ),
              ),
              const SizedBox(height: 10),
              ..._timeline.map((entry) => _TaxiTimelineRow(entry: entry)),
            ],
          ),
        ),
      ],
    );
  }

  Map<String, dynamic>? get _ride {
    return taxiRideViewFromEnvelope(_envelope);
  }

  Map<String, dynamic>? get _latestLocation {
    return trackingMap(_envelope?['latestLocation']);
  }

  Map<String, dynamic>? get _captain {
    return trackingMap(_ride?['captain']);
  }

  LatLng get _initialCenter =>
      taxiRideMapFocusPoint(_ride) ?? basmayaTrackingCenter;

  List<Marker> get _markers {
    final tokens = context.maslakiTokens;
    final pickup = taxiRidePickupPoint(_ride);
    final dropoff = taxiRideDropoffPoint(_ride);
    final captainPoint = taxiRideCaptainPoint(_ride);
    final heading = _readNum(_ride?['captainHeading']);
    return [
      if (pickup != null)
        Marker(
          point: pickup,
          width: 46,
          height: 46,
          child: Icon(
            Icons.trip_origin_rounded,
            color: tokens.success,
            size: 30,
          ),
        ),
      if (dropoff != null)
        Marker(
          point: dropoff,
          width: 50,
          height: 50,
          child: Icon(
            Icons.location_on_rounded,
            color: tokens.primaryAccent,
            size: 40,
          ),
        ),
      if (captainPoint != null)
        Marker(
          point: captainPoint,
          width: 56,
          height: 56,
          child: Transform.rotate(
            angle: (heading ?? 0) * math.pi / 180,
            child: Container(
              decoration: BoxDecoration(
                color: tokens.surfaceSecondary,
                shape: BoxShape.circle,
                border: Border.all(color: tokens.primaryAccent, width: 1.4),
                boxShadow: [
                  BoxShadow(
                    color: tokens.glowPrimary.withValues(alpha: 0.36),
                    blurRadius: 18,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Icon(
                Icons.directions_car_rounded,
                color: tokens.primaryAccent,
                size: 30,
              ),
            ),
          ),
        ),
    ];
  }

  List<Polyline> get _polylines {
    final tokens = context.maslakiTokens;
    final start = taxiRideRouteStartPoint(_ride);
    final end = taxiRideRouteEndPoint(_ride);
    final points = <LatLng?>[
      start,
      end,
    ].whereType<LatLng>().toList(growable: false);
    if (points.length < 2) return const [];
    return [
      Polyline(
        points: points,
        strokeWidth: 4.2,
        color: tokens.primaryAccent.withValues(alpha: 0.92),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return Scaffold(
        backgroundColor: context.maslakiTokens.backgroundPrimary,
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    if (_error != null || _ride == null) {
      return Scaffold(
        backgroundColor: context.maslakiTokens.backgroundPrimary,
        appBar: AppBar(),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(_error ?? ''),
          ),
        ),
      );
    }

    final ride = _ride!;
    return LiveTrackingShell(
      title: context.lt(
        ar: 'Ã˜ÂªÃ˜ÂªÃ˜Â¨Ã˜Â¹ Ã˜Â±Ã˜Â­Ã™â€žÃ˜Â© Ã˜Â§Ã™â€žÃ˜ÂªÃ™Æ’Ã˜Â³Ã™Å ',
        en: 'Taxi Live Tracking',
      ),
      initialCenter: _initialCenter,
      markers: _markers,
      polylines: _polylines,
      sheetBuilder: (context, scrollController) {
        return _buildTrackingSheet(context, scrollController, ride);
        /*
        final tokens = context.maslakiTokens;
        final displayState = taxiRideDisplayState(ride);
        final isWaitingState =
            displayState == 'searching' || displayState == 'negotiating';
        final nonAvailable = context.lt(
          ar: 'ØºÙŠØ± Ù…ØªÙˆÙØ±',
          en: 'Not available',
        );

        final vehicle = trackingMap(ride['vehicle']);
        final finalFare =
            ride['finalFare'] ??
            ride['agreedFareIqd'] ??
            ride['proposedFareIqd'];
        if (isWaitingState) {
          return ListView(
            controller: scrollController,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              Text(
                displayState == 'negotiating'
                    ? context.lt(
                        ar: 'Ø¬Ø§Ø±ÙŠ Ø§Ù„ØªÙØ§ÙˆØ¶ Ù…Ø¹ Ø§Ù„ÙƒØ§Ø¨ØªÙ†',
                        en: 'Negotiation in progress',
                      )
                    : context.lt(
                        ar: 'Ø¬Ø§Ø±ÙŠ Ø§Ù„Ø¨Ø­Ø« Ø¹Ù† ÙƒØ§Ø¨ØªÙ†',
                        en: 'Searching for a captain',
                      ),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              _TaxiInfoTile(
                title: context.lt(ar: 'Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚', en: 'Pickup'),
                value:
                    trackingNestedString(ride['pickup'], const ['label']) ??
                    nonAvailable,
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'Ø§Ù„ÙˆØ¬Ù‡Ø©', en: 'Dropoff'),
                value:
                    trackingNestedString(ride['dropoff'], const ['label']) ??
                    nonAvailable,
              ),
              _TaxiInfoTile(
                title: context.lt(ar: 'Ø§Ù„Ø£Ø¬Ø±Ø©', en: 'Fare'),
                value: _formatRideFareLabel(context, finalFare, nonAvailable),
              ),
              const SizedBox(height: 12),
              Text(
                displayState == 'negotiating'
                    ? context.lt(
                        ar: 'Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ù‚Ø¨ÙˆÙ„ Ø£Ø­Ø¯ Ø§Ù„Ø¹Ø±ÙˆØ¶ Ù‚Ø¨Ù„ ÙØªØ­ Ø§Ù„ØªØªØ¨Ø¹ Ø§Ù„Ø­ÙŠ.',
                        en: 'Waiting for an accepted offer before live tracking.',
                      )
                    : context.lt(
                        ar: 'Ø³ÙŠØ¨Ø¯Ø£ Ø§Ù„ØªØªØ¨Ø¹ Ø§Ù„Ø­ÙŠ Ø¨Ø¹Ø¯ ØªØ¹ÙŠÙŠÙ† Ø§Ù„ÙƒØ§Ø¨ØªÙ†.',
                        en: 'Live tracking starts after a captain is assigned.',
                      ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: tokens.textSecondary),
              ),
            ],
          );
        }

        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              _rideIdLabel(ride),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _TaxiStatusBadge(
              label: _statusLabel(_string(ride['status']) ?? ''),
            ),
            const SizedBox(height: 16),
            _TaxiInfoTile(
              title: context.lt(
                ar: 'Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¦Ã™â€š',
                en: 'Captain',
              ),
              value: _string(_captain?['fullName']) ?? nonAvailable,
            ),
            _TaxiInfoTile(
              title: context.lt(
                ar: 'Ã˜Â§Ã™â€žÃ˜Â§Ã™â€ Ã˜Â·Ã™â€žÃ˜Â§Ã™â€š',
                en: 'Pickup',
              ),
              value:
                  trackingNestedString(ride['pickup'], const ['label']) ??
                  nonAvailable,
            ),
            _TaxiInfoTile(
              title: context.lt(
                ar: 'Ã˜Â§Ã™â€žÃ™Ë†Ã˜Â¬Ã™â€¡Ã˜Â©',
                en: 'Dropoff',
              ),
              value:
                  trackingNestedString(ride['dropoff'], const ['label']) ??
                  nonAvailable,
            ),
            _TaxiInfoTile(
              title: context.lt(ar: 'Ã˜Â§Ã™â€žÃ˜Â£Ã˜Â¬Ã˜Â±Ã˜Â©', en: 'Fare'),
              value: _formatRideFareLabel(context, finalFare, nonAvailable),
            ),
            _TaxiInfoTile(
              title: context.lt(
                ar: 'ÃƒËœÃ‚Â§Ãƒâ„¢Ã¢â‚¬Å¾Ã‚Â¢ÃƒËœÃ‚Â·Ãƒâ„¢Ã…Â ÃƒËœÃ‚Â±Ãƒâ„¢Ã‚Â©',
                en: 'Trip distance',
              ),
              value: (() {
                final distanceM = _readNum(
                  ride['routeDistance'] ?? ride['routeDistanceMeters'],
                );
                if (distanceM == null || distanceM <= 0) {
                  return nonAvailable;
                }
                if (distanceM < 1000) {
                  return '${distanceM.round()} m';
                }
                return '${(distanceM / 1000).toStringAsFixed(distanceM >= 10000 ? 0 : 1)} km';
              })(),
            ),
            _TaxiInfoTile(
              title: context.lt(
                ar: 'ÃƒËœÃ‚Â§Ã™â€žÃ˜ÂªÃ™â€¦Ã™Å Ã˜Â± Ã˜Â§Ã™â‚¬Ã˜ÂªÃ¢â‚¬Â¦Ã™â€¡Ã™Å ',
                en: 'Estimated arrival',
              ),
              value: (() {
                final minutes = _readInt(ride['estimatedArrivalMinutes']);
                return minutes == null || minutes <= 0
                    ? nonAvailable
                    : '$minutes min';
              })(),
            ),
            if (vehicle != null)
              _TaxiInfoTile(
                title: context.lt(
                  ar: 'ÃƒËœÃ‚Â§Ã™â€žÃ˜Â³Ã™Å Ã˜Â§Ã˜Â±Ã˜Â©',
                  en: 'Vehicle',
                ),
                value:
                    [
                          trackingString(vehicle['vehicleMake']),
                          trackingString(vehicle['vehicleModel']),
                          trackingString(vehicle['vehicleYear']),
                          trackingString(vehicle['vehicleColor']),
                          trackingString(vehicle['vehiclePlate']),
                        ]
                        .whereType<String>()
                        .where((value) => value.isNotEmpty)
                        .join(' • '),
              ),
            if (_latestLocation != null)
              _TaxiInfoTile(
                title: context.lt(
                  ar: 'Ã˜Â¢Ã˜Â®Ã˜Â± Ã˜ÂªÃ˜Â­Ã˜Â¯Ã™Å Ã˜Â«',
                  en: 'Last update',
                ),
                value:
                    trackingNestedString(_latestLocation, const [
                      'createdAt',
                    ]) ??
                    trackingNestedString(_latestLocation, const [
                      'updatedAt',
                    ]) ??
                    nonAvailable,
              ),
            const SizedBox(height: 16),
            Text(
              context.lt(
                ar: 'Ã˜Â³Ã™Å Ã˜Â± Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â©',
                en: 'Ride timeline',
              ),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ..._timeline.map((entry) => _TaxiTimelineRow(entry: entry)),
            if (!_isReadonly &&
                displayState == 'active' &&
                (_captain?['phone'] ?? '').toString().trim().isNotEmpty) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _shareRide,
                    icon: const Icon(Icons.share_rounded),
                    label: Text(
                      context.lt(ar: 'Ã™â€¦Ã˜Â´Ã˜Â§Ã˜Â±Ã™Æ’Ã˜Â©', en: 'Share'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openRideChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text(
                      context.lt(ar: 'Ã™â€¦Ã˜Â­Ã˜Â§Ã˜Â¯Ã˜Â«Ã˜Â©', en: 'Chat'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: _callCaptain,
                    icon: const Icon(Icons.call_outlined),
                    label: Text(context.lt(ar: 'اتصال', en: 'Call')),
                  ),
                ],
              ),
            ],
          ],
        );
        */
      },
    );
  }

  List<_TaxiTimelineEntry> get _timeline {
    final ride = _ride ?? const <String, dynamic>{};
    final eventsRaw = _envelope?['events'];
    final hasAssigned =
        _string(_captain?['fullName']) != null ||
        _string(ride['status']) == 'captain_assigned' ||
        _string(ride['status']) == 'captain_arriving' ||
        _string(ride['status']) == 'ride_started' ||
        _string(ride['status']) == 'completed';
    final hasArriving =
        _string(ride['status']) == 'captain_arriving' ||
        _string(ride['status']) == 'ride_started' ||
        _string(ride['status']) == 'completed';
    final hasStarted =
        _string(ride['status']) == 'ride_started' ||
        _string(ride['status']) == 'completed';
    final hasCompleted = _string(ride['status']) == 'completed';
    final eventTexts = eventsRaw is List
        ? eventsRaw
              .whereType<Map>()
              .map((item) => Map<String, dynamic>.from(item))
              .toList(growable: false)
        : const <Map<String, dynamic>>[];

    DateTime? findEvent(String type) {
      for (final item in eventTexts) {
        final candidate = _string(item['eventType'] ?? item['event_type']);
        if (candidate == type) {
          return DateTime.tryParse(
            _string(item['createdAt'] ?? item['created_at']) ?? '',
          );
        }
      }
      return null;
    }

    return [
      _TaxiTimelineEntry(
        label: context.lt(
          ar: 'Ã˜Â¥Ã˜Â±Ã˜Â³Ã˜Â§Ã™â€ž Ã˜Â§Ã™â€žÃ˜Â·Ã™â€žÃ˜Â¨',
          en: 'Request sent',
        ),
        done: true,
        time: DateTime.tryParse(
          _string(ride['createdAt'] ?? ride['created_at']) ?? '',
        ),
      ),
      _TaxiTimelineEntry(
        label: context.lt(
          ar: 'Ã˜ÂªÃ˜Â¹Ã™Å Ã™Å Ã™â€  Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¦Ã™â€š',
          en: 'Captain assigned',
        ),
        done: hasAssigned,
        time: findEvent('captain_assigned'),
      ),
      _TaxiTimelineEntry(
        label: context.lt(
          ar: 'Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¦Ã™â€š Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™Å Ã™â€š',
          en: 'Captain arriving',
        ),
        done: hasArriving,
        time: findEvent('captain_arriving'),
      ),
      _TaxiTimelineEntry(
        label: context.lt(
          ar: 'Ã˜Â¨Ã˜Â¯Ã˜Â£Ã˜Âª Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â©',
          en: 'Ride started',
        ),
        done: hasStarted,
        time: findEvent('ride_started'),
      ),
      _TaxiTimelineEntry(
        label: context.lt(
          ar: 'Ã˜Â§Ã™Æ’Ã˜ÂªÃ™â€¦Ã™â€žÃ˜Âª Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â©',
          en: 'Ride completed',
        ),
        done: hasCompleted,
        time: findEvent('ride_completed'),
      ),
    ];
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'searching':
        return context.lt(
          ar: 'Ã˜Â¬Ã˜Â§Ã˜Â±Ã™Â Ã˜Â§Ã™â€žÃ˜Â¨Ã˜Â­Ã˜Â«',
          en: 'Searching',
        );
      case 'captain_assigned':
        return context.lt(
          ar: 'Ã˜ÂªÃ™â€¦ Ã˜ÂªÃ˜Â¹Ã™Å Ã™Å Ã™â€  Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¦Ã™â€š',
          en: 'Captain assigned',
        );
      case 'captain_arriving':
        return context.lt(
          ar: 'Ã˜Â§Ã™â€žÃ˜Â³Ã˜Â§Ã˜Â¦Ã™â€š Ã™ÂÃ™Å  Ã˜Â§Ã™â€žÃ˜Â·Ã˜Â±Ã™Å Ã™â€š',
          en: 'Captain arriving',
        );
      case 'ride_started':
        return context.lt(
          ar: 'Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â© Ã˜Â¨Ã˜Â¯Ã˜Â£Ã˜Âª',
          en: 'Ride started',
        );
      case 'completed':
        return context.lt(
          ar: 'Ã˜Â§Ã™Æ’Ã˜ÂªÃ™â€¦Ã™â€žÃ˜Âª Ã˜Â§Ã™â€žÃ˜Â±Ã˜Â­Ã™â€žÃ˜Â©',
          en: 'Completed',
        );
      case 'cancelled':
        return context.lt(
          ar: 'Ã˜ÂªÃ™â€¦ Ã˜Â§Ã™â€žÃ˜Â¥Ã™â€žÃ˜ÂºÃ˜Â§Ã˜Â¡',
          en: 'Cancelled',
        );
      default:
        return context.lt(
          ar: 'Ã˜Â±Ã˜Â­Ã™â€žÃ˜Â© Ã™â€ Ã˜Â´Ã˜Â·Ã˜Â©',
          en: 'Active ride',
        );
    }
  }

  String? _string(dynamic value) {
    return trackingString(value);
  }

  int? _readInt(dynamic value) => int.tryParse('${value ?? ''}');

  double? _readNum(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  // ignore: unused_element
  String _rideIdLabel(Map<String, dynamic> ride) {
    final rideId = _readInt(ride['id']) ?? widget.rideId;
    if (rideId <= 0) {
      return context.lt(ar: 'ØºÙŠØ± Ù…ØªÙˆÙØ±', en: 'Not available');
    }
    return '#$rideId';
  }

  String _formatRideFareLabel(
    BuildContext context,
    dynamic rawFare,
    String nonAvailable,
  ) {
    final fare = _readNum(rawFare);
    if (fare == null || fare <= 0) return nonAvailable;
    return formatIqd(fare.round());
  }
}

// ignore: unused_element
class _TaxiStatusBadge extends StatelessWidget {
  final String label;

  const _TaxiStatusBadge({required this.label});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Align(
      alignment: AlignmentDirectional.center,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: tokens.primaryAccent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: tokens.borderSubtle),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: tokens.secondaryAccent,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _TaxiInfoTile extends StatelessWidget {
  final String title;
  final String value;

  const _TaxiInfoTile({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: tokens.cardPrimary.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              value,
              textAlign: TextAlign.end,
              style: TextStyle(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            title,
            style: TextStyle(
              color: tokens.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaxiTimelineEntry {
  final String label;
  final bool done;
  final DateTime? time;

  const _TaxiTimelineEntry({
    required this.label,
    required this.done,
    required this.time,
  });
}

class _TaxiTimelineRow extends StatelessWidget {
  final _TaxiTimelineEntry entry;

  const _TaxiTimelineRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  entry.label,
                  textAlign: TextAlign.end,
                  style: TextStyle(
                    color: entry.done ? tokens.textPrimary : tokens.textMuted,
                    fontWeight: entry.done ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                if (entry.time != null)
                  Text(
                    '${entry.time!.day}/${entry.time!.month} ${entry.time!.hour.toString().padLeft(2, '0')}:${entry.time!.minute.toString().padLeft(2, '0')}',
                    style: TextStyle(color: tokens.textMuted, fontSize: 12),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Icon(
            entry.done
                ? Icons.check_circle_rounded
                : Icons.radio_button_unchecked,
            color: entry.done ? tokens.primaryAccent : tokens.textMuted,
          ),
        ],
      ),
    );
  }
}
