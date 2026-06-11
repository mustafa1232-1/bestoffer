import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/ai_dev_support_api.dart';
import '../widgets/ops_feedback_state.dart';

class AiDevSupportSettingsScreen extends ConsumerStatefulWidget {
  const AiDevSupportSettingsScreen({super.key});

  @override
  ConsumerState<AiDevSupportSettingsScreen> createState() =>
      _AiDevSupportSettingsScreenState();
}

class _AiDevSupportSettingsScreenState
    extends ConsumerState<AiDevSupportSettingsScreen> {
  bool _loading = true;
  String? _error;
  Map<String, dynamic> _settings = const <String, dynamic>{};

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
      final data = await ref.read(aiDevSupportApiProvider).getSettings();
      final settings = (data['settings'] is Map<String, dynamic>)
          ? data['settings'] as Map<String, dynamic>
          : const <String, dynamic>{};
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  bool _boolOf(String key, {bool fallback = false}) {
    final value = _settings[key];
    if (value is bool) return value;
    if (value is num) return value != 0;
    return fallback;
  }

  Future<void> _save() async {
    try {
      await ref.read(aiDevSupportApiProvider).updateSettings(_settings);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Settings saved')));
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('$e')));
    }
  }

  Widget _switchTile(String key, String label) {
    return SwitchListTile(
      value: _boolOf(key),
      onChanged: (value) {
        setState(() {
          _settings = {..._settings, key: value};
        });
      },
      title: Text(label),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return OpsFeedbackState(
        icon: Icons.tune_rounded,
        title: 'Settings unavailable',
        message: _error!,
        actionLabel: 'Retry',
        onAction: _load,
      );
    }

    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _switchTile('ai_analysis_enabled', 'Enable AI Analysis'),
          _switchTile('sentry_webhook_enabled', 'Enable Sentry Webhook'),
          _switchTile('datadog_webhook_enabled', 'Enable Datadog Webhook'),
          _switchTile(
            'github_issue_creation_enabled',
            'Enable GitHub Issue Creation',
          ),
          _switchTile('auto_restart_enabled', 'Enable Auto Restart'),
          _switchTile('auto_rollback_enabled', 'Enable Auto Rollback'),
          _switchTile(
            'feature_flag_disable_enabled',
            'Enable Feature Flag Disable',
          ),
          _switchTile(
            'require_second_approval_for_critical',
            'Second Approval',
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save_outlined),
            label: const Text('Save settings'),
          ),
        ],
      ),
    );
  }
}
