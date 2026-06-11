import 'package:flutter/material.dart';

import '../models/ops_incident.dart';
import 'severity_badge.dart';

class IncidentCard extends StatelessWidget {
  final OpsIncident incident;
  final VoidCallback? onTap;

  const IncidentCard({super.key, required this.incident, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.all(14),
        title: Text(
          incident.title,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w800,
          ),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ID: ${incident.id} • ${incident.source} • ${incident.status}'),
              if ((incident.affectedModule ?? '').isNotEmpty)
                Text('Module: ${incident.affectedModule}'),
              if (incident.updatedAt != null)
                Text('Updated: ${incident.updatedAt}'),
            ],
          ),
        ),
        trailing: SeverityBadge(severity: incident.severity),
      ),
    );
  }
}
