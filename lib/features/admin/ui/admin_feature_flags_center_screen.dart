import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';

class AdminFeatureFlagsCenterScreen extends ConsumerStatefulWidget {
  const AdminFeatureFlagsCenterScreen({super.key});

  @override
  ConsumerState<AdminFeatureFlagsCenterScreen> createState() =>
      _AdminFeatureFlagsCenterScreenState();
}

class _AdminFeatureFlagsCenterScreenState
    extends ConsumerState<AdminFeatureFlagsCenterScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _flags = const [];

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
      final out = await ref.read(adminApiProvider).opsFeatureFlags();
      final raw = List<dynamic>.from(out['items'] as List? ?? const []);
      final flags = raw
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList(growable: false);
      if (!mounted) return;
      setState(() {
        _flags = flags;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = mapAnyError(
          e,
          fallback: context.l10n.adminOpsFeatureFlagsLoadFailed,
        );
      });
    }
  }

  Future<void> _saveFlag({
    required String flagKey,
    required bool enabled,
    required int rolloutPercent,
    String? description,
    List<String> roles = const [],
    Map<String, dynamic> config = const {},
  }) async {
    try {
      await ref
          .read(adminApiProvider)
          .upsertOpsFeatureFlag(
            flagKey: flagKey,
            isEnabled: enabled,
            rolloutPercent: rolloutPercent,
            description: description,
            targetRoles: roles,
            config: config,
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
              fallback: context.l10n.adminOpsFeatureFlagsSaveFailed,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _openCreateDialog() async {
    final l10n = context.l10n;
    final keyCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    var enabled = false;
    var rollout = 0.0;
    final created = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return AlertDialog(
              title: Text(l10n.adminOpsFeatureFlagsCreateTitle),
              content: SizedBox(
                width: 420,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: keyCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.adminOpsFeatureFlagsFlagKey,
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: descCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.adminOpsFeatureFlagsFieldDescription,
                      ),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: enabled,
                      onChanged: (value) {
                        setSheetState(() => enabled = value);
                      },
                      title: Text(l10n.adminOpsFeatureFlagsEnabled),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: Text(l10n.adminOpsFeatureFlagsRollout)),
                        Text('${rollout.round()}%'),
                      ],
                    ),
                    Slider(
                      value: rollout,
                      min: 0,
                      max: 100,
                      divisions: 20,
                      onChanged: (value) {
                        setSheetState(() => rollout = value);
                      },
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
                  child: Text(l10n.commonCreate),
                ),
              ],
            );
          },
        );
      },
    );
    if (created != true) return;
    final flagKey = keyCtrl.text.trim().toLowerCase();
    if (flagKey.isEmpty) return;
    await _saveFlag(
      flagKey: flagKey,
      enabled: enabled,
      rolloutPercent: rollout.round(),
      description: descCtrl.text.trim().isEmpty ? null : descCtrl.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminOpsFeatureFlagsTitle),
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
        label: Text(l10n.adminOpsFeatureFlagsCreateAction),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(child: Text(_error!))
          : _flags.isEmpty
          ? Center(child: Text(l10n.adminOpsFeatureFlagsEmpty))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 24),
                itemCount: _flags.length,
                itemBuilder: (context, index) {
                  final item = _flags[index];
                  final key = '${item['flag_key'] ?? ''}'.trim();
                  final enabled = item['is_enabled'] == true;
                  final rollout =
                      int.tryParse('${item['rollout_percent']}') ?? 0;
                  final description = '${item['description'] ?? ''}'.trim();
                  return Card(
                    margin: const EdgeInsets.symmetric(vertical: 6),
                    child: ListTile(
                      leading: const Icon(Icons.tune_rounded),
                      title: Text(key.isEmpty ? '-' : key),
                      subtitle: Text(
                        '${description.isEmpty ? l10n.adminOpsFeatureFlagsNoDescription : description}\n${l10n.adminOpsFeatureFlagsRollout}: $rollout%',
                      ),
                      isThreeLine: true,
                      trailing: Switch(
                        value: enabled,
                        onChanged: (value) {
                          _saveFlag(
                            flagKey: key,
                            enabled: value,
                            rolloutPercent: rollout,
                            description: description.isEmpty
                                ? null
                                : description,
                            roles: List<String>.from(
                              item['target_roles'] as List? ?? const [],
                            ),
                            config: Map<String, dynamic>.from(
                              item['config_json'] as Map? ?? const {},
                            ),
                          );
                        },
                      ),
                    ),
                  );
                },
              ),
            ),
    );
  }
}
