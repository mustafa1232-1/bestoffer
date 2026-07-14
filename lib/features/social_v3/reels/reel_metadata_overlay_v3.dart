import 'package:flutter/material.dart';

import '../domain/reel_view_data.dart';

/// Bottom-left metadata overlay for a full-screen reel (§3).
///
/// Username + follow control, expandable caption, original-audio label, and the
/// Maslaki local-context badge. Sits above the bottom navigation overlay and
/// leaves room for it (the caller supplies bottom padding).
class ReelMetadataOverlayV3 extends StatefulWidget {
  const ReelMetadataOverlayV3({
    super.key,
    required this.reel,
    this.showFollow = true,
    this.onFollow,
    this.onOpenAuthor,
  });

  final ReelV3ViewData reel;
  final bool showFollow;
  final VoidCallback? onFollow;
  final VoidCallback? onOpenAuthor;

  @override
  State<ReelMetadataOverlayV3> createState() => _ReelMetadataOverlayV3State();
}

class _ReelMetadataOverlayV3State extends State<ReelMetadataOverlayV3> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final reel = widget.reel;
    const shadow = [Shadow(color: Colors.black87, blurRadius: 8)];
    final handle = reel.authorHandle.isNotEmpty ? reel.authorHandle : reel.authorName;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            GestureDetector(
              onTap: widget.onOpenAuthor,
              child: Text(
                handle,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  shadows: shadow,
                ),
              ),
            ),
            if (reel.isAuthorVerified) ...[
              const SizedBox(width: 4),
              const Icon(Icons.verified, color: Color(0xFFE7B24B), size: 16),
            ],
            if (widget.showFollow) ...[
              const SizedBox(width: 10),
              _FollowChip(onTap: widget.onFollow),
            ],
          ],
        ),
        if (reel.caption.trim().isNotEmpty) ...[
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Text(
              reel.caption.trim(),
              maxLines: _expanded ? 6 : 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13.5,
                height: 1.3,
                shadows: shadow,
              ),
            ),
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 15),
            const SizedBox(width: 6),
            Flexible(
              child: Text(
                reel.audioLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12.5,
                  shadows: shadow,
                ),
              ),
            ),
            if (reel.localContextBadge != null) ...[
              const SizedBox(width: 10),
              _LocalBadge(label: reel.localContextBadge!),
            ],
          ],
        ),
      ],
    );
  }
}

class _FollowChip extends StatelessWidget {
  const _FollowChip({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white, width: 1.2),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const Text(
          'Follow',
          style: TextStyle(
            color: Colors.white,
            fontSize: 12,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Maslaki local-context badge (deep-navy pill, gold accent).
class _LocalBadge extends StatelessWidget {
  const _LocalBadge({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: const Color(0xCC0D1B2A),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: const Color(0xFFE7B24B), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.location_on, color: Color(0xFFE7B24B), size: 12),
          const SizedBox(width: 3),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
