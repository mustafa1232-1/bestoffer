import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminPermissionsMatrixScreen extends ConsumerStatefulWidget {
  const AdminPermissionsMatrixScreen({super.key});

  @override
  ConsumerState<AdminPermissionsMatrixScreen> createState() =>
      _AdminPermissionsMatrixScreenState();
}

class _AdminPermissionsMatrixScreenState
    extends ConsumerState<AdminPermissionsMatrixScreen> {
  bool _loading = true;
  String? _error;
  List<String> _roles = const [];
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
      final out = await ref.read(adminApiProvider).opsPermissionsMatrix();
      final roles = List<dynamic>.from(out['roles'] as List? ?? const [])
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
      final raw = List<dynamic>.from(out['items'] as List? ?? const []);
      final items = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _roles = roles;
        _items = items;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminOpsPermissionsMatrixLoadFailed,
        );
      });
    }
  }

  Future<void> _saveOverride({
    required String roleKey,
    required String capabilityKey,
    required bool isEnabled,
    String? notes,
  }) async {
    try {
      await ref
          .read(adminApiProvider)
          .upsertOpsPermissionOverride(
            roleKey: roleKey,
            capabilityKey: capabilityKey,
            isEnabled: isEnabled,
            notes: notes,
          );
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              e,
              fallback: context.l10n.adminOpsPermissionsMatrixSaveFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openCreateDialog() async {
    final l10n = context.l10n;
    if (_roles.isEmpty) return;
    var selectedRole = _roles.first;
    final capabilityCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    var isEnabled = true;

    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return AlertDialog(
              title: Text(l10n.adminOpsPermissionsMatrixCreateTitle),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selectedRole,
                      decoration: InputDecoration(
                        labelText: l10n.adminOpsPermissionsMatrixRole,
                      ),
                      onChanged: (value) {
                        if (value == null) return;
                        setSheetState(() => selectedRole = value);
                      },
                      items: _roles
                          .map(
                            (role) => DropdownMenuItem(
                              value: role,
                              child: Text(role),
                            ),
                          )
                          .toList(growable: false),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: capabilityCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.adminOpsPermissionsMatrixCapability,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: notesCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.adminOpsPermissionsMatrixNotes,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: isEnabled,
                      onChanged: (value) {
                        setSheetState(() => isEnabled = value);
                      },
                      title: Text(l10n.adminOpsPermissionsMatrixEnabled),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.commonCancel),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.commonSave),
                ),
              ],
            );
          },
        );
      },
    );
    if (ok != true) return;
    final capability = capabilityCtrl.text.trim();
    if (capability.isEmpty) return;
    await _saveOverride(
      roleKey: selectedRole,
      capabilityKey: capability,
      isEnabled: isEnabled,
      notes: notesCtrl.text.trim().isEmpty ? null : notesCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminOpsPermissionsMatrixTitle),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: _openCreateDialog,
        icon: const Icon(Icons.add_rounded),
        label: Text(l10n.adminOpsPermissionsMatrixCreateAction),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _items.isEmpty
          ? Center(child: Text(l10n.adminOpsPermissionsMatrixEmpty))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                itemCount: _roles.length,
                itemBuilder: (context, index) {
                  final role = _roles[index];
                  final roleItems = _items
                      .where(
                        (item) =>
                            '${item['role_key']}'.trim().toLowerCase() ==
                            role.toLowerCase(),
                      )
                      .toList(growable: false);
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ExpansionTile(
                      title: Text(role),
                      subtitle: Text(
                        l10n.adminOpsPermissionsMatrixOverridesCount(
                          roleItems.length,
                        ),
                      ),
                      childrenPadding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                      children: [
                        if (roleItems.isEmpty)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                l10n.adminOpsPermissionsMatrixNoOverrides,
                              ),
                            ),
                          )
                        else
                          ...roleItems.map((item) {
                            final capability = '${item['capability_key']}';
                            final enabled = item['is_enabled'] == true;
                            return SwitchListTile(
                              title: Text(capability),
                              subtitle: Text('${item['notes'] ?? ''}'),
                              value: enabled,
                              onChanged: (value) {
                                _saveOverride(
                                  roleKey: role,
                                  capabilityKey: capability,
                                  isEnabled: value,
                                  notes: '${item['notes'] ?? ''}'.trim().isEmpty
                                      ? null
                                      : '${item['notes']}'.trim(),
                                );
                              },
                            );
                          }),
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}
