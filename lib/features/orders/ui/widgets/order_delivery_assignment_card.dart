import 'package:flutter/material.dart';

import '../../../../core/i18n/locale_text.dart';
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
    final statusCopy = _copyForStatus(context, status);
    final isPending =
        statusCopy != null ||
        assignment?.isPendingNoDriver == true ||
        (status.isEmpty && driver == null && visibleWhenNoAssignment);

    if (!isAssigned && !isPending && !visibleWhenNoAssignment) {
      return const SizedBox.shrink();
    }

    if (isPending || driver == null || !showDriverDetails) {
      final title = statusCopy?.title ?? waitingCopy;
      final body = statusCopy?.helper ?? helperText;
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
              title,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              body,
              textDirection: TextDirection.rtl,
              style: TextStyle(
                color: Theme.of(
                  context,
                ).colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ],
        ),
      );
    }

    final vehicleBits = <String>[
      if ((driver.vehicleType ?? '').trim().isNotEmpty)
        driver.vehicleType!.trim(),
      if ((driver.vehicleModel ?? '').trim().isNotEmpty)
        driver.vehicleModel!.trim(),
      if ((driver.vehicleColor ?? '').trim().isNotEmpty)
        driver.vehicleColor!.trim(),
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
                              _DriverAvatarFallback(name: driver.name),
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
                    const Icon(
                      Icons.star_rounded,
                      color: Colors.amber,
                      size: 20,
                    ),
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
            style: TextStyle(color: Colors.white.withValues(alpha: 0.72)),
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

  _DeliveryAssignmentCopy? _copyForStatus(BuildContext context, String status) {
    switch (status) {
      case 'PENDING_STORES':
        return _DeliveryAssignmentCopy(
          title: context.lt(
            ar: 'بانتظار قبول بقية المتاجر',
            en: 'Waiting for the remaining stores',
          ),
          helper: context.lt(
            ar: 'سيبدأ تعيين الدلفري بعد قبول بقية المتاجر للطلب.',
            en: 'Courier assignment starts after the remaining stores accept the order.',
          ),
        );
      case 'READY_FOR_ASSIGNMENT':
        return _DeliveryAssignmentCopy(
          title: context.lt(
            ar: 'جارٍ تعيين الدلفري',
            en: 'Assigning a courier',
          ),
          helper: context.lt(
            ar: 'سيتم عرض بيانات الدلفري فور اكتمال التعيين.',
            en: 'Courier details will appear as soon as assignment completes.',
          ),
        );
      case 'PENDING_NO_DRIVER':
        return _DeliveryAssignmentCopy(
          title: context.lt(
            ar: 'لا يوجد دلفري متاح حالياً، وستتم إعادة المحاولة تلقائياً',
            en: 'No courier is available right now, retries will continue automatically',
          ),
          helper: context.lt(
            ar: 'لا يلزم أي إجراء من المتجر، وسيتم التعيين عند توفر دلفري مناسب.',
            en: 'No store action is required; assignment will happen when a suitable courier is available.',
          ),
        );
      default:
        return null;
    }
  }
}

class _DeliveryAssignmentCopy {
  final String title;
  final String helper;

  const _DeliveryAssignmentCopy({required this.title, required this.helper});
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
