import 'dart:async';

import 'package:flutter/material.dart';

import 'section_availability_models.dart';

class AppMaintenanceScreen extends StatefulWidget {
  final SectionAvailabilityEntry entry;

  const AppMaintenanceScreen({super.key, required this.entry});

  @override
  State<AppMaintenanceScreen> createState() => _AppMaintenanceScreenState();
}

class _AppMaintenanceScreenState extends State<AppMaintenanceScreen> {
  Timer? _timer;
  Duration? _remaining;

  DateTime? get _until {
    final raw = widget.entry.metadata['maintenanceUntil'];
    return raw == null ? null : DateTime.tryParse('$raw')?.toLocal();
  }

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _updateRemaining();
    });
  }

  void _updateRemaining() {
    final until = _until;
    setState(() {
      _remaining = until?.difference(DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = _remaining;
    final showCountdown = remaining != null && !remaining.isNegative;
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.build_circle_outlined, size: 76),
                const SizedBox(height: 20),
                const Text(
                  'التطبيق تحت الصيانة',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 14),
                Text(
                  widget.entry.effectiveMessage,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                if (showCountdown) ...[
                  const SizedBox(height: 20),
                  Text(
                    'يفتح بعد ${_formatDuration(remaining)}',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

String _formatDuration(Duration value) {
  final days = value.inDays;
  final hours = value.inHours.remainder(24);
  final minutes = value.inMinutes.remainder(60);
  final seconds = value.inSeconds.remainder(60);
  if (days > 0) return '$days يوم و $hours ساعة';
  if (hours > 0) return '$hours ساعة و $minutes دقيقة';
  return '$minutes دقيقة و $seconds ثانية';
}
