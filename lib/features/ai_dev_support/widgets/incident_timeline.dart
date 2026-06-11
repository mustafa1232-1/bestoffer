import 'package:flutter/material.dart';

class IncidentTimeline extends StatelessWidget {
  final List<Map<String, dynamic>> logs;

  const IncidentTimeline({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    if (logs.isEmpty) {
      return const Center(child: Text('No timeline events yet.'));
    }

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (context, index) {
        final row = logs[index];
        return ListTile(
          dense: true,
          leading: const Icon(Icons.timeline),
          title: Text('${row['action'] ?? row['target_type'] ?? 'event'}'),
          subtitle: Text('${row['created_at'] ?? row['createdAt'] ?? ''}'),
        );
      },
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemCount: logs.length,
    );
  }
}
