import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:maslaki/core/i18n/locale_text.dart';

import '../../customer/ui/maslaki_user_shell.dart';

class LiveTrackingShell extends StatefulWidget {
  final String title;
  final LatLng initialCenter;
  final double initialZoom;
  final List<Marker> markers;
  final List<Polyline> polylines;
  final Widget Function(BuildContext context, ScrollController scrollController)
  sheetBuilder;
  final List<Widget> topActions;
  final VoidCallback? onBack;

  const LiveTrackingShell({
    super.key,
    required this.title,
    required this.initialCenter,
    required this.markers,
    required this.polylines,
    required this.sheetBuilder,
    this.initialZoom = 15,
    this.topActions = const [],
    this.onBack,
  });

  @override
  State<LiveTrackingShell> createState() => _LiveTrackingShellState();
}

class _LiveTrackingShellState extends State<LiveTrackingShell> {
  final MapController _mapController = MapController();
  final ScrollController _sheetScrollController = ScrollController();
  bool _mapFullScreen = false;

  @override
  void dispose() {
    _sheetScrollController.dispose();
    super.dispose();
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
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => setState(() => _mapFullScreen = true),
                    child: _map(context, interactive: false),
                  ),
                ),
                _topBar(context, theme, tokens, fullScreen: false),
                PositionedDirectional(
                  end: 14,
                  bottom: 14,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: tokens.surfaceSecondary.withValues(alpha: 0.92),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: tokens.borderSubtle),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.open_in_full_rounded,
                          size: 15,
                          color: tokens.primaryAccent,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          context.lt(ar: 'اضغط للتكبير', en: 'Tap to expand'),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: tokens.textSecondary,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
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
      return FlutterMap(
        mapController: _mapController,
        options: MapOptions(
          initialCenter: widget.initialCenter,
          initialZoom: widget.initialZoom,
          interactionOptions: InteractionOptions(
            flags: interactive ? InteractiveFlag.all : InteractiveFlag.none,
          ),
        ),
        children: [
          TileLayer(
            urlTemplate:
                'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}{r}.png',
            retinaMode:
                (MediaQuery.maybeOf(context)?.devicePixelRatio ?? 1.0) > 1.0,
            fallbackUrl: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
            userAgentPackageName: 'app.maslaki.user',
            tileProvider: NetworkTileProvider(
              headers: {
                'User-Agent': 'MaslakiTracking/1.0 (+https://maslaki.app)',
              },
            ),
          ),
          if (widget.polylines.isNotEmpty)
            PolylineLayer(polylines: widget.polylines),
          if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
        ],
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
