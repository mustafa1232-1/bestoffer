import 'package:flutter/material.dart';
import 'package:social_core/social_core.dart';

Future<DateTime?> pickSocialScheduledDateTime(
  BuildContext context, {
  DateTime? initialDateTime,
}) async {
  final now = DateTime.now();
  final seed = (initialDateTime ?? now.add(const Duration(minutes: 15))).isAfter(
        now,
      )
      ? (initialDateTime ?? now.add(const Duration(minutes: 15)))
      : now.add(const Duration(minutes: 15));
  final date = await showDatePicker(
    context: context,
    initialDate: seed,
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return null;
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay.fromDateTime(seed),
  );
  if (time == null) return null;
  final scheduledAt = DateTime(
    date.year,
    date.month,
    date.day,
    time.hour,
    time.minute,
  );
  if (scheduledAt.isBefore(now.add(const Duration(seconds: 30)))) {
    return now.add(const Duration(minutes: 1));
  }
  return scheduledAt;
}

class SocialScheduledMessageCard extends StatelessWidget {
  final SocialScheduledChatMessage item;
  final String title;
  final String scheduledLabel;
  final String failedLabel;
  final String processingLabel;
  final String deleteLabel;
  final VoidCallback? onDelete;

  const SocialScheduledMessageCard({
    super.key,
    required this.item,
    required this.title,
    required this.scheduledLabel,
    required this.failedLabel,
    required this.processingLabel,
    required this.deleteLabel,
    this.onDelete,
  });

  String _formatDateTime(BuildContext context, DateTime? value) {
    if (value == null) return '--';
    final localizations = MaterialLocalizations.of(context);
    final date = localizations.formatMediumDate(value);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: false,
    );
    return '$date • $time';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final statusLabel = item.isFailed
        ? failedLabel
        : item.isProcessing
        ? processingLabel
        : scheduledLabel;
    final preview = item.previewText;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            item.isFailed ? Icons.error_outline_rounded : Icons.schedule_rounded,
            color: item.isFailed
                ? theme.colorScheme.error
                : theme.colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  preview,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Text(
                      _formatDateTime(context, item.scheduledFor),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: item.isFailed
                            ? theme.colorScheme.errorContainer
                            : theme.colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: item.isFailed
                              ? theme.colorScheme.onErrorContainer
                              : theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              tooltip: deleteLabel,
              onPressed: onDelete,
              icon: const Icon(Icons.close_rounded),
            ),
        ],
      ),
    );
  }
}
