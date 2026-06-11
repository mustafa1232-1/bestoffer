import 'package:flutter/material.dart';

import '../../core/i18n/app_localizations_context.dart';

String jobApplicationStatusLabel(BuildContext context, String status) {
  final l10n = context.l10n;
  switch (status.trim().toLowerCase()) {
    case 'submitted':
      return l10n.jobsStatusReceived;
    case 'shortlisted':
      return l10n.jobsStatusShortlisted;
    case 'rejected':
      return l10n.commonRejected;
    case 'hired':
      return l10n.jobsStatusHired;
    case 'withdrawn':
      return l10n.jobsStatusWithdrawn;
    case 'dismissed_after_hire':
      return l10n.jobsStatusDismissed;
    case 'archived':
      return l10n.jobsStatusArchived;
    default:
      return status;
  }
}

String jobApplicationStatusGroupLabel(BuildContext context, String? status) {
  final l10n = context.l10n;
  switch (status?.trim().toLowerCase()) {
    case null:
    case '':
      return l10n.commonAll;
    case 'submitted':
      return l10n.jobsStatusReceivedGroup;
    case 'shortlisted':
      return l10n.jobsStatusShortlistedGroup;
    case 'rejected':
      return l10n.jobsStatusRejectedGroup;
    case 'hired':
      return l10n.jobsStatusHiredGroup;
    case 'withdrawn':
      return l10n.jobsStatusWithdrawnGroup;
    case 'dismissed_after_hire':
      return l10n.jobsStatusDismissedGroup;
    case 'archived':
      return l10n.jobsStatusArchivedGroup;
    default:
      return status!;
  }
}
