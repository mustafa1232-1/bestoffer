import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../state/admin_controller.dart';
import 'admin_approvals_hub_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_services_hub_screen.dart';

class AdminServiceProviderApplicationsScreen extends ConsumerStatefulWidget {
  const AdminServiceProviderApplicationsScreen({super.key});

  @override
  ConsumerState<AdminServiceProviderApplicationsScreen> createState() =>
      _AdminServiceProviderApplicationsScreenState();
}

class _AdminServiceProviderApplicationsScreenState
    extends ConsumerState<AdminServiceProviderApplicationsScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _statusFilter = 'pending';
  List<Map<String, dynamic>> _items = const <Map<String, dynamic>>[];

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
      final envelope = await ref
          .read(adminApiProvider)
          .listPendingServiceProviders(
            providerStatus: _statusFilter,
            limit: 200,
          );
      final rows = envelope['items'] is List
          ? List<dynamic>.from(envelope['items'] as List)
          : const <dynamic>[];
      if (!mounted) return;
      setState(() {
        _items = rows
            .whereType<Map>()
            .map((row) => Map<String, dynamic>.from(row))
            .toList(growable: false);
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: 'Could not load service-provider applications.',
        );
      });
    }
  }

  int _asInt(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse('${value ?? ''}') ?? 0;
  }

  String _asText(dynamic value) => '${value ?? ''}'.trim();

  Widget _buildAdminDrawer() {
    final auth = ref.watch(authControllerProvider);
    return AppUserDrawer(
      title: 'Admin',
      subtitle: auth.user?.fullName,
      showCommunitySection: false,
      showSettings: false,
      enableItemSearch: false,
      items: [
        AppUserDrawerItem(
          icon: Icons.space_dashboard_rounded,
          label: 'Dashboard',
          subtitle: 'Admin home',
          group: 'Navigation',
          onTap: (_) async {
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDashboardScreen(),
              ),
              (route) => false,
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.verified_user_outlined,
          label: 'Approvals',
          subtitle: 'Review pending applications',
          group: 'Navigation',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminApprovalsHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.home_repair_service_outlined,
          label: 'Services',
          subtitle: 'Services summary and requests',
          group: 'Navigation',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminServicesHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.description_outlined,
          label: 'Provider applications',
          subtitle: 'Free registration review',
          group: 'Navigation',
          onTap: (_) async => _load(),
        ),
      ],
    );
  }

  Future<void> _updateStatus(Map<String, dynamic> row, String status) async {
    final noteCtrl = TextEditingController();
    try {
      final approved = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(_dialogTitle(status)),
          content: TextField(
            controller: noteCtrl,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Review note',
              helperText:
                  'Use only identity, data quality, safety, category, or content reasons.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Confirm'),
            ),
          ],
        ),
      );
      if (approved != true) return;
      setState(() => _saving = true);
      await ref
          .read(adminApiProvider)
          .updateServiceProviderModeration(
            providerId: _asInt(row['id']),
            status: status,
            note: noteCtrl.text.trim(),
          );
      await _load();
      if (!mounted) return;
      await ref.read(adminControllerProvider.notifier).bootstrap();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Application updated to $status.')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(mapAnyError(e, fallback: 'Could not update review.')),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
      noteCtrl.dispose();
    }
  }

  String _dialogTitle(String status) {
    switch (status) {
      case 'approved':
        return 'Approve provider application';
      case 'rejected':
        return 'Reject provider application';
      case 'suspended':
        return 'Suspend provider account';
      default:
        return 'Update provider application';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      drawer: Drawer(child: _buildAdminDrawer()),
      appBar: AppBar(
        title: const Text('Service Provider Applications'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
            child: DropdownButtonFormField<String>(
              initialValue: _statusFilter,
              items: const [
                DropdownMenuItem(value: 'pending', child: Text('Under review')),
                DropdownMenuItem(value: 'approved', child: Text('Approved')),
                DropdownMenuItem(value: 'rejected', child: Text('Rejected')),
                DropdownMenuItem(value: 'suspended', child: Text('Suspended')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _statusFilter = value);
                _load();
              },
              decoration: const InputDecoration(labelText: 'Review status'),
            ),
          ),
          if (_saving) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                  ? ListView(
                      children: [
                        const SizedBox(height: 120),
                        Center(child: Text(_error!)),
                      ],
                    )
                  : _items.isEmpty
                  ? ListView(
                      children: const [
                        SizedBox(height: 120),
                        Center(child: Text('No provider applications.')),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(12),
                      itemCount: _items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final row = _items[index];
                        final status = _asText(
                          row['providerApprovalStatus'] ?? row['status'],
                        );
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _asText(row['businessName']).isEmpty
                                      ? _asText(row['ownerFullName'])
                                      : _asText(row['businessName']),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 16,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text('Phone: ${_asText(row['phone'])}'),
                                Text('City: ${_asText(row['city'])}'),
                                Text(
                                  'Category: ${_asText(row['mainCategoryName'])}',
                                ),
                                Text('Review status: $status'),
                                if (_asText(row['approvalNote']).isNotEmpty)
                                  Text(
                                    'Review note: ${_asText(row['approvalNote'])}',
                                  ),
                                const SizedBox(height: 10),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    if (status != 'approved')
                                      FilledButton.icon(
                                        onPressed: _saving
                                            ? null
                                            : () => _updateStatus(
                                                row,
                                                'approved',
                                              ),
                                        icon: const Icon(
                                          Icons.check_circle_outline,
                                        ),
                                        label: const Text('Approve'),
                                      ),
                                    if (status != 'rejected')
                                      TextButton.icon(
                                        onPressed: _saving
                                            ? null
                                            : () => _updateStatus(
                                                row,
                                                'rejected',
                                              ),
                                        icon: const Icon(Icons.block_rounded),
                                        label: const Text('Reject'),
                                      ),
                                    if (status == 'approved')
                                      OutlinedButton.icon(
                                        onPressed: _saving
                                            ? null
                                            : () => _updateStatus(
                                                row,
                                                'suspended',
                                              ),
                                        icon: const Icon(
                                          Icons.pause_circle_outline,
                                        ),
                                        label: const Text('Suspend'),
                                      ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
