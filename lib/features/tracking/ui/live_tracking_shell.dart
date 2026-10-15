import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maslaki/core/i18n/locale_text.dart';

import '../../customer/ui/maslaki_user_shell.dart';
import '../tracking_map_utils.dart';

class LiveTrackingShell extends StatefulWidget {
  @visibleForTesting
  static bool disableNetworkTilesForTests = false;

  final String title;
  final LatLng initialCenter;
  final double initialZoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final TrackingMotionSample? trackedSample;
  final Widget Function(BuildContext context, double headingDegrees)?
  trackedMarkerBuilder;
  final double trackedMarkerWidth;
  final double trackedMarkerHeight;
  final Widget Function(BuildContext context, ScrollController scrollController)
  sheetBuilder;
  final List<Widget> topActions;
  final VoidCallback? onBack;
  final TileProvider? tileProvider;
  final bool showMapTiles;
  final ValueChanged<bool>? onFollowModeChanged;

  const LiveTrackingShell({
    super.key,
    required this.title,
    required this.initialCenter,
    required this.markers,
    required this.polylines,
    required this.sheetBuilder,
    this.trackedSample,
    this.trackedMarkerBuilder,
    this.trackedMarkerWidth = 58,
    this.trackedMarkerHeight = 58,
    this.initialZoom = 15,
    this.topActions = const [],
    this.onBack,
    this.tileProvider,
    this.showMapTiles = true,
    this.onFollowModeChanged,
  });

  @override
  State<LiveTrackingShell> createState() => _LiveTrackingShellState();
}

class _LiveTrackingShellState extends State<LiveTrackingShell>
    with SingleTickerProviderStateMixin {
  final MapController _mapController = MapController();
  final ScrollController _sheetScrollController = ScrollController();
  late final AnimationController _motionController;
  late final ValueNotifier<TrackingMotionSample?> _renderedSample;
  late final TileProvider _tileProvider;
  late final bool _ownsTileProvider;
  TrackingMotionSample? _motionFrom;
  TrackingMotionSample? _motionTo;
  bool _mapFullScreen = false;
  bool _followTrackedEntity = true;

  @override
  void initState() {
    super.initState();
    _ownsTileProvider = widget.tileProvider == null;
    _tileProvider =
        widget.tileProvider ??
        NetworkTileProvider(
          headers: {'User-Agent': 'MaslakiTracking/1.0 (+https://maslaki.app)'},
          silenceExceptions: true,
        );
    _renderedSample = ValueNotifier<TrackingMotionSample?>(
      widget.trackedSample,
    );
    _motionTo = widget.trackedSample;
    _motionController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 850),
    )..addListener(_renderMotionFrame);
  }

  @override
  void didUpdateWidget(covariant LiveTrackingShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = widget.trackedSample;
    if (incoming != null && shouldAcceptTrackingSample(_motionTo, incoming)) {
      _beginMotion(incoming);
    }
  }

  @override
  void dispose() {
    _motionController.dispose();
    _renderedSample.dispose();
    if (_ownsTileProvider) _tileProvider.dispose();
    _sheetScrollController.dispose();
    super.dispose();
  }

  void _beginMotion(TrackingMotionSample incoming) {
    final current = _renderedSample.value;
    _motionTo = incoming;
    if (shouldSnapTrackingSample(current, incoming)) {
      _motionController.stop();
      _motionFrom = incoming;
      _renderedSample.value = incoming;
      _followPoint(incoming.point);
      return;
    }
    _motionFrom = current;
    _motionController.forward(from: 0);
  }

  void _renderMotionFrame() {
    final from = _motionFrom;
    final to = _motionTo;
    if (from == null || to == null) return;
    final sample = interpolateTrackingSample(
      from,
      to,
      Curves.easeOutCubic.transform(_motionController.value),
    );
    _renderedSample.value = sample;
    _followPoint(sample.point);
  }

  void _followPoint(LatLng point) {
    if (!_followTrackedEntity || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_followTrackedEntity) return;
      try {
        _mapController.move(point, _mapController.camera.zoom);
      } catch (_) {
        // The controller can be briefly detached while switching map modes.
      }
    });
  }

  void _zoomBy(double delta) {
    final camera = _mapController.camera;
    final next = (camera.zoom + delta).clamp(3.0, 19.0);
    _mapController.move(camera.center, next);
  }

  void _recenter() {
    _followTrackedEntity = true;
    widget.onFollowModeChanged?.call(true);
    _mapController.move(
      _renderedSample.value?.point ?? widget.initialCenter,
      widget.initialZoom,
    );
  }

  void _fitBounds() {
    final points = widget.markers
        .map((marker) => marker.point)
        .toList(growable: true);
    final trackedPoint = _renderedSample.value?.point;
    if (trackedPoint != null) points.add(trackedPoint);
    if (points.length < 2) {
      _recenter();
      return;
    }
    try {
      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: LatLngBounds.fromPoints(points),
          padding: const EdgeInsets.all(64),
        ),
      );
    } catch (_) {
      _recenter();
    }
  }

  Widget _mapControls(BuildContext context, MaslakiThemeTokens tokens) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        _MapControlButton(
          icon: Icons.add_rounded,
          tooltip: context.lt(ar: 'تكبير', en: 'Zoom in'),
          onPressed: () => _zoomBy(1),
        ),
        const SizedBox(height: 8),
        _MapControlButton(
          icon: Icons.remove_rounded,
          tooltip: context.lt(ar: 'تصغير', en: 'Zoom out'),
          onPressed: () => _zoomBy(-1),
        ),
        const SizedBox(height: 8),
        _MapControlButton(
          icon: Icons.my_location_rounded,
          tooltip: context.lt(ar: 'إعادة التمركز', en: 'Recenter'),
          onPressed: _recenter,
        ),
        const SizedBox(height: 8),
        _MapControlButton(
          icon: Icons.fit_screen_rounded,
          tooltip: context.lt(ar: 'عرض المسار كاملاً', en: 'Fit route'),
          onPressed: _fitBounds,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final theme = Theme.of(context);

    // Full-screen interactive map (entered by tapping the map preview).
    if (_mapFullScreen) {
      return Scaffold(
        backgroundColor: tokens.backgroundPrimary,
        body: Stack(
          children: [
            Positioned.fill(child: _map(context, interactive: true)),
            _topBar(context, theme, tokens, fullScreen: true),
            PositionedDirectional(
              end: 14,
              bottom: 28,
              child: SafeArea(child: _mapControls(context, tokens)),
            ),
          ],
        ),
      );
    }

    // Split view: top half = live map (tap to expand), bottom half = order
    // info + courier contact. The bottom half always renders even if the map
    // tiles are unavailable, so the screen is never just a blank gray map.
    return Scaffold(
      backgroundColor: tokens.backgroundPrimary,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                // The preview map is fully interactive (pan + pinch zoom); the
                // top bar's expand button opens the full-screen view. Controls
                // are small corner buttons so they never block touching the map.
                Positioned.fill(child: _map(context, interactive: true)),
                _topBar(context, theme, tokens, fullScreen: false),
                PositionedDirectional(
                  end: 14,
                  bottom: 14,
                  child: _mapControls(context, tokens),
                ),
              ],
            ),
          ),
          Expanded(
            child: Container(
              width: double.infinity,
              decoration: BoxDecoration(
                color: tokens.surfaceSecondary.withValues(alpha: 0.98),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: tokens.borderSubtle),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.34),
                    blurRadius: 32,
                    offset: const Offset(0, -8),
                  ),
                ],
              ),
              child: Column(
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 54,
                    height: 5,
                    decoration: BoxDecoration(
                      color: tokens.textSecondary.withValues(alpha: 0.5),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Expanded(
                    child: widget.sheetBuilder(context, _sheetScrollController),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _map(BuildContext context, {required bool interactive}) {
    try {
      final showMapTiles =
          widget.showMapTiles && !LiveTrackingShell.disableNetworkTilesForTests;
      return RepaintBoundary(
        key: const ValueKey('live-tracking-map-boundary'),
        child: FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: widget.trackedSample?.point ?? widget.initialCenter,
            initialZoom: widget.initialZoom,
            interactionOptions: InteractionOptions(
              flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
            ),
            onPositionChanged: (camera, hasGesture) {
              if (hasGesture && _followTrackedEntity) {
                _followTrackedEntity = false;
                widget.onFollowModeChanged?.call(false);
              }
            },
          ),
          children: [
            if (showMapTiles)
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                retinaMode:
                    (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0) >
                    1.0,
                maxZoom: 19,
                userAgentPackageName: 'com.maslaki.user',
                tileProvider: _tileProvider,
              ),
            if (showMapTiles)
              const RichAttributionWidget(
                attributions: [
                  TextSourceAttribution('OpenStreetMap contributors'),
                ],
              ),
            if (widget.polylines.isNotEmpty)
              PolylineLayer(polylines: widget.polylines),
            if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
            if (widget.trackedMarkerBuilder != null)
              ValueListenableBuilder<TrackingMotionSample?>(
                valueListenable: _renderedSample,
                builder: (context, sample, child) {
                  if (sample == null) return const SizedBox.shrink();
                  return MarkerLayer(
                    markers: [
                      Marker(
                        point: sample.point,
                        width: widget.trackedMarkerWidth,
                        height: widget.trackedMarkerHeight,
                        child: RepaintBoundary(
                          key: const ValueKey('live-tracking-moving-marker'),
                          child: widget.trackedMarkerBuilder!(
                            context,
                            sample.headingDegrees,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
          ],
        ),
      );
    } catch (error, stack) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stack,
          library: 'live_tracking_shell',
          context: ErrorDescription('building tracking map'),
        ),
      );
      return _MapUnavailableFallback(interactive: interactive);
    }
  }

  Widget _topBar(
    BuildContext context,
    ThemeData theme,
    MaslakiThemeTokens tokens, {
    required bool fullScreen,
  }) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: Row(
          children: [
            _TrackingTopButton(
              icon: Icons.arrow_back_rounded,
              onPressed: fullScreen
                  ? () => setState(() => _mapFullScreen = false)
                  : (widget.onBack ??
                        () => MaslakiHomeNavigator.maybePopOrGoHome(context)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: tokens.surfaceSecondary.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: tokens.borderSubtle),
                ),
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: tokens.textPrimary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            _TrackingTopButton(
              icon: fullScreen
                  ? Icons.close_fullscreen_rounded
                  : Icons.open_in_full_rounded,
              onPressed: () => setState(() => _mapFullScreen = !_mapFullScreen),
            ),
            ...widget.topActions,
          ],
        ),
      ),
    );
  }
}

class _MapUnavailableFallback extends StatelessWidget {
  final bool interactive;

  const _MapUnavailableFallback({required this.interactive});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: tokens.backgroundSecondary,
        border: Border.all(color: tokens.borderSubtle),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.map_outlined, size: 34, color: tokens.textSecondary),
              const SizedBox(height: 10),
              Text(
                context.lt(
                  ar: 'تعذر عرض الخريطة الآن',
                  en: 'The map is unavailable right now',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.titleSmall?.copyWith(
                  color: tokens.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                context.lt(
                  ar: interactive
                      ? 'يمكنك الرجوع وإعادة فتح شاشة التتبع.'
                      : 'تفاصيل الطلب ما زالت متاحة في الأسفل.',
                  en: interactive
                      ? 'Go back and reopen the tracking screen.'
                      : 'Order details are still available below.',
                ),
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: tokens.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TrackingTopButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;

  const _TrackingTopButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: tokens.surfaceSecondary.withValues(alpha: 0.92),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: tokens.borderSubtle),
          ),
          child: Icon(icon, color: tokens.primaryAccent, size: 22),
        ),
      ),
    );
  }
}

class _MapControlButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _MapControlButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Ink(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: tokens.surfaceSecondary.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: tokens.borderSubtle),
            ),
            child: Icon(icon, color: tokens.primaryAccent, size: 22),
          ),
        ),
      ),
    );
  }
}
