import 'package:flutter/material.dart';

import '../../../../core/media/cached_app_image.dart';
import '../../../orders/models/delivery_assignment_model.dart';

class OrderDeliveryAssignmentCard extends StatelessWidget {
  final OrderDeliveryAssignmentModel? assignment;
  final String waitingCopy;
  final String helperText;
  final bool compact;
  final bool showDriverDetails;
  final bool visibleWhenNoAssignment;
  final VoidCallback? onCall;
  final VoidCallback? onChat;

  const OrderDeliveryAssignmentCard({
    super.key,
    required this.assignment,
    required this.waitingCopy,
    required this.helperText,
    this.compact = false,
    this.showDriverDetails = true,
    this.visibleWhenNoAssignment = false,
    this.onCall,
    this.onChat,
  });

  @override
  Widget build(BuildContext context) {
    final driver = assignment?.driver;
    final status = (assignment?.assignmentStatus ?? '').trim().toUpperCase();
    final isAssigned = assignment?.isAssigned == true;
    final isPending = assignment?.isPendingNoDriver == true ||
        status == 'PENDING_NO_DRIVER' ||
        (status.isEmpty && driver == null);

    if (!isAssigned && !isPending && !visibleWhenNoAssignment) {
      return const SizedBox.shrink();
    }

    if (isPending || driver == null || !showDriverDetails) {
      return Container(
        padding: EdgeInsets.all(compact ? 10 : 12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white.withValues(alpha: 0.05),
          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              waitingCopy,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              helperText,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(
                      alpha: 0.78,
                    ),
              ),
            ),
          ],
        ),
      );
    }

    final vehicleBits = <String>[
      if ((driver.vehicleType ?? '').trim().isNotEmpty) driver.vehicleType!.trim(),
      if ((driver.vehicleModel ?? '').trim().isNotEmpty) driver.vehicleModel!.trim(),
      if ((driver.vehicleColor ?? '').trim().isNotEmpty) driver.vehicleColor!.trim(),
      if ((driver.vehiclePlateNumber ?? '').trim().isNotEmpty)
        driver.vehiclePlateNumber!.trim(),
    ];

    return Container(
      padding: EdgeInsets.all(compact ? 10 : 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withValues(alpha: 0.05),
        border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: SizedBox(
                  width: compact ? 46 : 54,
                  height: compact ? 46 : 54,
                  child: driver.photoUrl?.trim().isNotEmpty == true
                      ? CachedAppImage(
                          imageUrl: driver.photoUrl!,
                          width: compact ? 46 : 54,
                          height: compact ? 46 : 54,
                          fit: BoxFit.cover,
                          maxWidthDiskCache: 128,
                          maxHeightDiskCache: 128,
                          errorWidget: (context, error, stackTrace) =>
                              _DriverAvatarFallback(
                            name: driver.name,
                          ),
                        )
                      : _DriverAvatarFallback(name: driver.name),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      driver.name ?? '—',
                      textDirection: TextDirection.rtl,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                      ),
                    ),
                    if ((driver.phone ?? '').trim().isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        driver.phone!,
                        textDirection: TextDirection.rtl,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.78),
                        ),
                      ),
                    ],
                    const SizedBox(height: 2),
                    Text(
                      vehicleBits.isEmpty
                          ? 'معلومات السيارة غير مكتملة'
                          : vehicleBits.join(' • '),
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.76),
                      ),
                    ),
                  ],
                ),
              ),
              if ((driver.rating ?? 0) > 0) ...[
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Icon(Icons.star_rounded, color: Colors.amber, size: 20),
                    Text(
                      driver.rating!.toStringAsFixed(1),
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (assignment?.assignmentId != null) ...[
            const SizedBox(height: 8),
            Text(
              'Assignment #${assignment!.assignmentId}',
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.74),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            helperText,
            textDirection: TextDirection.rtl,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.72),
            ),
          ),
          if (onCall != null || onChat != null) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (onCall != null)
                  OutlinedButton.icon(
                    onPressed: onCall,
                    icon: const Icon(Icons.call_outlined),
                    label: const Text('اتصال'),
                  ),
                if (onChat != null)
                  OutlinedButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.chat_bubble_outline_rounded),
                    label: const Text('مراسلة'),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DriverAvatarFallback extends StatelessWidget {
  final String? name;

  const _DriverAvatarFallback({required this.name});

  @override
  Widget build(BuildContext context) {
    final initials = (name ?? '')
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .take(2)
        .map((part) => part.substring(0, 1))
        .join();
    return Container(
      color: Colors.white.withValues(alpha: 0.08),
      alignment: Alignment.center,
      child: Text(
        initials.isNotEmpty ? initials : 'D',
        style: const TextStyle(fontWeight: FontWeight.w800),
      ),
    );
  }
}
