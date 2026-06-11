import 'dart:async';

import 'package:maslaki/core/constants/api.dart';
import 'package:maslaki/core/i18n/app_localizations_context.dart';
import 'package:maslaki/core/i18n/locale_text.dart';
import 'package:maslaki/features/auth/state/auth_controller.dart';
import 'package:maslaki/features/taxi/data/taxi_api.dart';
import 'package:maslaki/features/taxi/ui/taxi_share_ride_friends_sheet.dart';
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

class _TaxiLiveTrackingScreenState
    extends ConsumerState<TaxiLiveTrackingScreen> {
  Map<String, dynamic>? _envelope;
  bool _loading = true;
  String? _error;
  StreamSubscription<TaxiLiveEvent>? _streamSub;
  Timer? _pollTimer;
  int? _lastEventId;

  TaxiApi get _taxiApi => ref.read(taxiApiProvider);

  bool get _isPublic => widget.publicToken != null;
  bool get _isReadonly => _isPublic || widget.sharedReadonly;

  @override
  void initState() {
    super.initState();
    _envelope = widget.initialEnvelope;
    _loading = widget.initialEnvelope == null;
    unawaited(_load(silent: widget.initialEnvelope != null));
    _connectStream();
    _pollTimer = Timer.periodic(
      Duration(seconds: _isPublic ? 12 : 6),
      (_) => unawaited(_load(silent: true)),
    );
  }

  @override
  void dispose() {
    _streamSub?.cancel();
    _pollTimer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = _isPublic
          ? await _taxiApi.publicTrackByToken(widget.publicToken!)
          : widget.sharedReadonly
          ? await _taxiApi.getSharedRideTrack(rideId: widget.rideId)
          : await _taxiApi.getRideDetails(widget.rideId);
      if (!mounted) return;
      setState(() {
        _envelope = data;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.lt(
          ar: 'ØªØ¹Ø°Ø± ØªØ­Ù…ÙŠÙ„ Ø§Ù„ØªØªØ¨Ø¹ Ø§Ù„Ø­ÙŠ Ù„Ù‡Ø°Ù‡ Ø§Ù„Ø±Ø­Ù„Ø©.',
          en: 'Failed to load live tracking for this ride.',
        );
      });
    }
  }

  void _connectStream() {
    _streamSub?.cancel();
    final stream = _isPublic
        ? _taxiApi.streamPublicTrackByToken(widget.publicToken!)
        : _taxiApi.streamEvents(lastEventId: _lastEventId);
    _streamSub = stream.listen((event) {
      if (event.eventId != null) {
        _lastEventId = event.eventId;
      }
      if (_isPublic) {
        if (event.event == 'taxi_location_update') {
          setState(() {
            _envelope = event.data;
            _loading = false;
            _error = null;
          });
        } else if (event.event == 'resync_required' || event.event == 'closed') {
          unawaited(_load(silent: true));
        }
        return;
      }

      final eventRideId =
          _readInt(event.data['rideId']) ??
          _readInt(
            event.data['ride'] is Map ? (event.data['ride'] as Map)['id'] : null,
          );
      if (eventRideId != widget.rideId) return;
      if (event.event == 'taxi_location_update' ||
          event.event == 'taxi_ride_update' ||
          event.event == 'taxi_bid_update' ||
          event.event == 'taxi_shared_ride_update' ||
          event.event == 'resync_required') {
        unawaited(_load(silent: true));
      }
    });
  }

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
                title: Text(context.lt(ar: 'Ù…Ø´Ø§Ø±ÙƒØ© Ø¹Ø§Ù…Ø©', en: 'Public share')),
                subtitle: Text(
                  context.lt(
                    ar: 'ÙŠÙ†Ø´Ø¦ Ø±Ø§Ø¨Ø· ØªØªØ¨Ø¹ Ø¹Ø§Ù… Ù„Ù„Ù‚Ø±Ø§Ø¡Ø© ÙÙ‚Ø·.',
                    en: 'Creates a public readonly tracking link.',
                  ),
                ),
                onTap: () async {
                  Navigator.of(context).pop();
                  final shareTextPrefix = this.context.lt(
                    ar: 'تتبع رحلة مسلكي:',
                    en: 'Track my Maslaki ride:',
                  );
                  final out = await _taxiApi.createPublicShareToken(widget.rideId);
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
                  context.lt(ar: 'Ù…Ø´Ø§Ø±ÙƒØ© Ù…Ø¹ Ø§Ù„Ø£ØµØ¯Ù‚Ø§Ø¡', en: 'Share with friends'),
                ),
                subtitle: Text(
                  context.lt(
                    ar: 'ØªØ´Ø§Ø±Ùƒ Ø§Ù„Ø±Ø­Ù„Ø© Ø¯Ø§Ø®Ù„ Ø§Ù„ØªØ·Ø¨ÙŠÙ‚ Ù…Ø¹ Ø£ØµØ¯Ù‚Ø§Ø¦Ùƒ.',
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
    final phone = _string(_captain?['phone']);
    if (phone == null || phone.isEmpty) return;
    await launchUrl(
      Uri.parse('tel:$phone'),
      mode: LaunchMode.externalApplication,
    );
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
                              final item = messages[messages.length - 1 - index];
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
                                          item['messageText'] ?? item['message_text'],
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
                              ar: 'Ø§ÙƒØªØ¨ Ø±Ø³Ø§Ù„Ø©...',
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

  Map<String, dynamic>? get _ride {
    final raw = _envelope?['ride'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Map<String, dynamic>? get _latestLocation {
    final raw = _envelope?['latestLocation'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  Map<String, dynamic>? get _captain {
    final ride = _ride;
    final raw = ride?['captain'];
    return raw is Map ? Map<String, dynamic>.from(raw) : null;
  }

  LatLng get _initialCenter =>
      latLngFromMap(_latestLocation) ??
      latLngFromMap(_ride?['pickup']) ??
      basmayaTrackingCenter;

  List<Marker> get _markers {
    final tokens = context.maslakiTokens;
    final pickup = latLngFromMap(_ride?['pickup']);
    final dropoff = latLngFromMap(_ride?['dropoff']);
    final live = latLngFromMap(_latestLocation);
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
      if (live != null)
        Marker(
          point: live,
          width: 56,
          height: 56,
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
    ];
  }

  List<Polyline> get _polylines {
    final tokens = context.maslakiTokens;
    final points = <LatLng>[];
    final pickup = latLngFromMap(_ride?['pickup']);
    final dropoff = latLngFromMap(_ride?['dropoff']);
    final live = latLngFromMap(_latestLocation);
    if (live != null) {
      points.add(live);
      if (dropoff != null) points.add(dropoff);
    } else {
      if (pickup != null) points.add(pickup);
      if (dropoff != null) points.add(dropoff);
    }
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
      title: context.lt(ar: 'ØªØªØ¨Ø¹ Ø±Ø­Ù„Ø© Ø§Ù„ØªÙƒØ³ÙŠ', en: 'Taxi Live Tracking'),
      initialCenter: _initialCenter,
      markers: _markers,
      polylines: _polylines,
      sheetBuilder: (context, scrollController) {
        final tokens = context.maslakiTokens;
        return ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
          children: [
            Text(
              '#${_readInt(ride['id']) ?? widget.rideId}',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.displaySmall?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            _TaxiStatusBadge(label: _statusLabel(_string(ride['status']) ?? '')),
            const SizedBox(height: 16),
            _TaxiInfoTile(
              title: context.lt(ar: 'Ø§Ù„Ø³Ø§Ø¦Ù‚', en: 'Captain'),
              value: _string(_captain?['fullName']) ??
                  context.lt(ar: 'Ø¨Ø§Ù†ØªØ¸Ø§Ø± Ø§Ù„ØªØ¹ÙŠÙŠÙ†', en: 'Awaiting assignment'),
            ),
            _TaxiInfoTile(
              title: context.lt(ar: 'Ø§Ù„Ø§Ù†Ø·Ù„Ø§Ù‚', en: 'Pickup'),
              value: _string(
                    ride['pickup'] is Map ? (ride['pickup'] as Map)['label'] : null,
                  ) ??
                  '-',
            ),
            _TaxiInfoTile(
              title: context.lt(ar: 'Ø§Ù„ÙˆØ¬Ù‡Ø©', en: 'Dropoff'),
              value: _string(
                    ride['dropoff'] is Map ? (ride['dropoff'] as Map)['label'] : null,
                  ) ??
                  '-',
            ),
            _TaxiInfoTile(
              title: context.lt(ar: 'Ø§Ù„Ø£Ø¬Ø±Ø©', en: 'Fare'),
              value:
                  '${_readNum(ride['agreedFareIqd'] ?? ride['proposedFareIqd']).toStringAsFixed(0)} ${context.lt(ar: 'Ø¯.Ø¹', en: 'IQD')}',
            ),
            if (_latestLocation != null)
              _TaxiInfoTile(
                title: context.lt(ar: 'Ø¢Ø®Ø± ØªØ­Ø¯ÙŠØ«', en: 'Last update'),
                value: _string(
                      _latestLocation?['createdAt'] ??
                          _latestLocation?['updatedAt'],
                    ) ??
                    '-',
              ),
            const SizedBox(height: 16),
            Text(
              context.lt(ar: 'Ø³ÙŠØ± Ø§Ù„Ø±Ø­Ù„Ø©', en: 'Ride timeline'),
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: tokens.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            ..._timeline.map((entry) => _TaxiTimelineRow(entry: entry)),
            if (!_isReadonly) ...[
              const SizedBox(height: 18),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  FilledButton.icon(
                    onPressed: _shareRide,
                    icon: const Icon(Icons.share_rounded),
                    label: Text(context.lt(ar: 'Ù…Ø´Ø§Ø±ÙƒØ©', en: 'Share')),
                  ),
                  OutlinedButton.icon(
                    onPressed: _openRideChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: Text(context.lt(ar: 'Ù…Ø­Ø§Ø¯Ø«Ø©', en: 'Chat')),
                  ),
                  if ((_captain?['phone'] ?? '').toString().trim().isNotEmpty)
                    OutlinedButton.icon(
                      onPressed: _callCaptain,
                      icon: const Icon(Icons.call_outlined),
                      label: Text(context.lt(ar: 'Ø§ØªØµØ§Ù„', en: 'Call')),
                    ),
                ],
              ),
            ],
          ],
        );
      },
    );
  }

  List<_TaxiTimelineEntry> get _timeline {
    final ride = _ride ?? const <String, dynamic>{};
    final eventsRaw = _envelope?['events'];
    final hasAssigned = _string(ride['captain']?['fullName']) != null ||
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
        label: context.lt(ar: 'Ø¥Ø±Ø³Ø§Ù„ Ø§Ù„Ø·Ù„Ø¨', en: 'Request sent'),
        done: true,
        time: DateTime.tryParse(_string(ride['createdAt'] ?? ride['created_at']) ?? ''),
      ),
      _TaxiTimelineEntry(
        label: context.lt(ar: 'ØªØ¹ÙŠÙŠÙ† Ø§Ù„Ø³Ø§Ø¦Ù‚', en: 'Captain assigned'),
        done: hasAssigned,
        time: findEvent('captain_assigned'),
      ),
      _TaxiTimelineEntry(
        label: context.lt(ar: 'Ø§Ù„Ø³Ø§Ø¦Ù‚ ÙÙŠ Ø§Ù„Ø·Ø±ÙŠÙ‚', en: 'Captain arriving'),
        done: hasArriving,
        time: findEvent('captain_arriving'),
      ),
      _TaxiTimelineEntry(
        label: context.lt(ar: 'Ø¨Ø¯Ø£Øª Ø§Ù„Ø±Ø­Ù„Ø©', en: 'Ride started'),
        done: hasStarted,
        time: findEvent('ride_started'),
      ),
      _TaxiTimelineEntry(
        label: context.lt(ar: 'Ø§ÙƒØªÙ…Ù„Øª Ø§Ù„Ø±Ø­Ù„Ø©', en: 'Ride completed'),
        done: hasCompleted,
        time: findEvent('ride_completed'),
      ),
    ];
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'searching':
        return context.lt(ar: 'Ø¬Ø§Ø±Ù Ø§Ù„Ø¨Ø­Ø«', en: 'Searching');
      case 'captain_assigned':
        return context.lt(ar: 'ØªÙ… ØªØ¹ÙŠÙŠÙ† Ø§Ù„Ø³Ø§Ø¦Ù‚', en: 'Captain assigned');
      case 'captain_arriving':
        return context.lt(ar: 'Ø§Ù„Ø³Ø§Ø¦Ù‚ ÙÙŠ Ø§Ù„Ø·Ø±ÙŠÙ‚', en: 'Captain arriving');
      case 'ride_started':
        return context.lt(ar: 'Ø§Ù„Ø±Ø­Ù„Ø© Ø¨Ø¯Ø£Øª', en: 'Ride started');
      case 'completed':
        return context.lt(ar: 'Ø§ÙƒØªÙ…Ù„Øª Ø§Ù„Ø±Ø­Ù„Ø©', en: 'Completed');
      case 'cancelled':
        return context.lt(ar: 'ØªÙ… Ø§Ù„Ø¥Ù„ØºØ§Ø¡', en: 'Cancelled');
      default:
        return context.lt(ar: 'Ø±Ø­Ù„Ø© Ù†Ø´Ø·Ø©', en: 'Active ride');
    }
  }

  String? _string(dynamic value) {
    final out = '$value'.trim();
    return out.isEmpty || out == 'null' ? null : out;
  }

  int? _readInt(dynamic value) => int.tryParse('${value ?? ''}');

  double _readNum(dynamic value) {
    final parsed = double.tryParse('${value ?? ''}');
    return parsed ?? 0;
  }
}

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
            entry.done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            color: entry.done ? tokens.primaryAccent : tokens.textMuted,
          ),
        ],
      ),
    );
  }
}

