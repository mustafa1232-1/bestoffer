import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

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

  @override
  Widget build(BuildContext context) {
    final tokens = context.maslakiTokens;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: tokens.backgroundPrimary,
      body: Stack(
        children: [
          Positioned.fill(
            child: FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: widget.initialCenter,
                initialZoom: widget.initialZoom,
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
                    headers: const {
                      'User-Agent': 'MaslakiTracking/1.0 (+https://maslaki.app)',
                    },
                  ),
                ),
                if (widget.polylines.isNotEmpty)
                  PolylineLayer(polylines: widget.polylines),
                if (widget.markers.isNotEmpty) MarkerLayer(markers: widget.markers),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Row(
                children: [
                  _TrackingTopButton(
                    icon: Icons.arrow_back_rounded,
                    onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: tokens.surfaceSecondary.withValues(alpha: 0.92),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: tokens.borderSubtle),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.22),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: tokens.textPrimary,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  if (widget.topActions.isNotEmpty) ...[
                    const SizedBox(width: 12),
                    ...widget.topActions,
                  ],
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: DraggableScrollableSheet(
              initialChildSize: 0.24,
              minChildSize: 0.18,
              maxChildSize: 0.9,
              snap: true,
              snapSizes: const [0.18, 0.46, 0.88],
              expand: false,
              builder: (context, scrollController) {
                return Container(
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
                        child: widget.sheetBuilder(context, scrollController),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
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
