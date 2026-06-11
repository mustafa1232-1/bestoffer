import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminResidenceChangeRequestsScreen extends ConsumerStatefulWidget {
  const AdminResidenceChangeRequestsScreen({super.key});

  @override
  ConsumerState<AdminResidenceChangeRequestsScreen> createState() =>
      _AdminResidenceChangeRequestsScreenState();
}

class _AdminResidenceChangeRequestsScreenState
    extends ConsumerState<AdminResidenceChangeRequestsScreen> {
  bool _loading = true;
  bool _busy = false;
  String _status = 'pending';
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final out = await ref
          .read(adminApiProvider)
          .residenceChangeRequests(status: _status, limit: 120);
      if (!mounted) return;
      setState(() {
        _items = List<dynamic>.from(out['items'] as List? ?? const [])
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminResidenceChangeLoadFailed,
        );
      });
    }
  }

  Future<String?> _askNote({required bool approve}) async {
    final ctrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          approve
              ? context.l10n.adminResidenceChangeApproveDialogTitle
              : context.l10n.adminResidenceChangeRejectDialogTitle,
          textDirection: Directionality.of(context),
          textAlign: TextAlign.end,
        ),
        content: TextField(
          controller: ctrl,
          minLines: 2,
          maxLines: 4,
          textDirection: Directionality.of(context),
          decoration: InputDecoration(
            hintText: context.l10n.adminResidenceChangeOptionalReviewNote,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(context.l10n.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(context.l10n.commonConfirm),
          ),
        ],
      ),
    );
    final text = ctrl.text.trim();
    ctrl.dispose();
    if (ok != true) return null;
    return text;
  }

  Future<void> _review(int requestId, {required bool approve}) async {
    if (_busy) return;
    final note = await _askNote(approve: approve);
    if (note == null) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(adminApiProvider);
      if (approve) {
        await api.approveResidenceChangeRequest(requestId, reviewNote: note);
      } else {
        await api.rejectResidenceChangeRequest(requestId, reviewNote: note);
      }
      if (!mounted) return;
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            approve
                ? context.l10n.adminResidenceChangeApproved
                : context.l10n.adminResidenceChangeRejected,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.adminResidenceChangeReviewActionFailed,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _valueFromSnapshot(Map<String, dynamic>? snapshot, List<String> keys) {
    for (final key in keys) {
      final raw = '${snapshot?[key] ?? ''}'.trim();
      if (raw.isNotEmpty) return raw;
    }
    return '-';
  }

  Widget _snapshotCard(String title, Map<String, dynamic>? snapshot) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            title,
            textDirection: Directionality.of(context),
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          _infoRow(
            context.l10n.commonBlock,
            _valueFromSnapshot(snapshot, const ['block', 'town']),
          ),
          _infoRow(
            context.l10n.commonBuilding,
            _valueFromSnapshot(snapshot, const [
              'buildingNumber',
              'building_number',
            ]),
          ),
          _infoRow(
            context.l10n.commonApartment,
            _valueFromSnapshot(snapshot, const [
              'apartmentNumber',
              'apartment_number',
              'apartment',
            ]),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        textDirection: Directionality.of(context),
        children: [
          Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w700)),
          Expanded(
            child: Text(
              value,
              textDirection: Directionality.of(context),
              textAlign: TextAlign.start,
            ),
          ),
        ],
      ),
    );
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'approved':
        return context.l10n.commonApproved;
      case 'rejected':
        return context.l10n.commonRejected;
      case 'cancelled':
        return context.l10n.commonCancelled;
      default:
        return context.l10n.commonPending;
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'approved':
        return const Color(0xFF16A34A);
      case 'rejected':
        return const Color(0xFFDC2626);
      case 'cancelled':
        return const Color(0xFF64748B);
      default:
        return const Color(0xFFF59E0B);
    }
  }

  Widget _buildCard(Map<String, dynamic> item) {
    final status = '${item['status'] ?? 'pending'}'.trim().toLowerCase();
    final requestId = int.tryParse('${item['id'] ?? ''}') ?? 0;
    final pending = status == 'pending';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              textDirection: Directionality.of(context),
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${item['userFullName'] ?? ''}'.trim().isEmpty
                            ? context.l10n.commonUnknownUser
                            : '${item['userFullName']}',
                        textDirection: Directionality.of(context),
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${item['userPhone'] ?? ''}',
                        textDirection: Directionality.of(context),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(999),
                    color: _statusColor(status).withValues(alpha: 0.16),
                  ),
                  child: Text(
                    _statusLabel(status),
                    style: TextStyle(
                      color: _statusColor(status),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _snapshotCard(
                    context.l10n.adminResidenceChangeCurrentResidence,
                    item['currentSnapshot'] is Map
                        ? Map<String, dynamic>.from(
                            item['currentSnapshot'] as Map,
                          )
                        : const <String, dynamic>{},
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _snapshotCard(
                    context.l10n.adminResidenceChangeRequestedResidence,
                    item['requestedSnapshot'] is Map
                        ? Map<String, dynamic>.from(
                            item['requestedSnapshot'] as Map,
                          )
                        : const <String, dynamic>{},
                  ),
                ),
              ],
            ),
            if ('${item['note'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 10),
              Text(
                '${context.l10n.adminResidenceChangeUserNote}: ${item['note']}',
                textDirection: Directionality.of(context),
              ),
            ],
            if ('${item['reviewNote'] ?? ''}'.trim().isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                '${context.l10n.adminResidenceChangeReviewNote}: ${item['reviewNote']}',
                textDirection: Directionality.of(context),
              ),
            ],
            const SizedBox(height: 12),
            if (pending)
              Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _review(requestId, approve: false),
                    icon: const Icon(Icons.close_rounded),
                    label: Text(context.l10n.commonReject),
                  ),
                  FilledButton.icon(
                    onPressed: _busy
                        ? null
                        : () => _review(requestId, approve: true),
                    icon: const Icon(Icons.check_rounded),
                    label: Text(context.l10n.commonApprove),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.adminDashboardResidenceChangeRequests),
      ),
      body: Column(
        children: [
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
            child: Row(
              children: [
                for (final status in const [
                  'pending',
                  'approved',
                  'rejected',
                  'cancelled',
                  'all',
                ])
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 8),
                    child: ChoiceChip(
                      label: Text(
                        status == 'pending'
                            ? context.l10n.commonPending
                            : status == 'approved'
                            ? context.l10n.commonApproved
                            : status == 'rejected'
                            ? context.l10n.commonRejected
                            : status == 'cancelled'
                            ? context.l10n.commonCancelled
                            : context.l10n.commonAll,
                      ),
                      selected: _status == status,
                      onSelected: (_) async {
                        setState(() => _status = status);
                        await _load();
                      },
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 24),
                            child: Text(
                              _error!,
                              textAlign: TextAlign.center,
                              textDirection: Directionality.of(context),
                            ),
                          ),
                        ),
                      ],
                    )
                  : _items.isEmpty
                  ? ListView(
                      children: [
                        const SizedBox(height: 140),
                        Center(
                          child: Text(
                            context.l10n.adminResidenceChangeEmpty,
                            textDirection: Directionality.of(context),
                          ),
                        ),
                      ],
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
                      itemCount: _items.length,
                      itemBuilder: (context, index) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _buildCard(_items[index]),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
