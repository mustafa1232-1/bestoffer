// ignore_for_file: prefer_const_constructors, prefer_const_literals_to_create_immutables

import 'package:flutter/material.dart';

/// A softly-pulsing placeholder block used to build skeleton screens while real
/// data loads. Pure Flutter (no shimmer package) so it works everywhere.
class SkeletonBox extends StatefulWidget {
  final double? width;
  final double height;
  final BorderRadiusGeometry borderRadius;
  final bool circle;

  const SkeletonBox({
    super.key,
    this.width,
    this.height = 14,
    this.borderRadius = const BorderRadius.all(Radius.circular(8)),
    this.circle = false,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.06);
    final highlight =
        Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14);
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final color = Color.lerp(base, highlight, _controller.value)!;
        return Container(
          width: widget.circle ? widget.height : widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: color,
            shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
            borderRadius: widget.circle ? null : widget.borderRadius,
          ),
        );
      },
    );
  }
}

/// Skeleton for a single store card (cover + logo + two text lines + chips).
class StoreCardSkeleton extends StatelessWidget {
  const StoreCardSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.03),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AspectRatio(
            aspectRatio: 2.7,
            child: SkeletonBox(height: double.infinity, borderRadius: BorderRadius.zero),
          ),
          Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                const SkeletonBox(height: 52, width: 52, circle: true),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: const [
                      SkeletonBox(width: 160, height: 15),
                      SizedBox(height: 8),
                      SkeletonBox(width: 110, height: 12),
                    ],
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

/// A vertical list of store-card skeletons.
class StoreListSkeleton extends StatelessWidget {
  final int count;
  const StoreListSkeleton({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 22),
      children: List.generate(count, (_) => const StoreCardSkeleton()),
    );
  }
}

/// Skeleton row for a product card.
class ProductRowSkeleton extends StatelessWidget {
  const ProductRowSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          const SkeletonBox(height: 72, width: 72),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: const [
                SkeletonBox(width: 140, height: 14),
                SizedBox(height: 8),
                SkeletonBox(width: 90, height: 12),
                SizedBox(height: 8),
                SkeletonBox(width: 180, height: 34),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Error state with a retry action (and optional "clear filters"). Use this
/// instead of dumping a raw exception string so a failed request never reads as
/// "no results".
class MaslakiErrorRetry extends StatelessWidget {
  final String message;
  final Future<void> Function()? onRetry;
  final VoidCallback? onClearFilters;

  const MaslakiErrorRetry({
    super.key,
    required this.message,
    this.onRetry,
    this.onClearFilters,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.cloud_off_rounded,
              size: 48,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onRetry != null)
                  FilledButton.icon(
                    onPressed: () => onRetry!(),
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('إعادة المحاولة'),
                  ),
                if (onClearFilters != null) ...[
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: onClearFilters,
                    child: const Text('مسح عوامل التصفية'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

