import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/i18n/app_localizations_context.dart';
import '../../../../core/i18n/app_strings.dart';
import '../../../auth/state/auth_controller.dart';

class SettingsAccountScreen extends ConsumerStatefulWidget {
  const SettingsAccountScreen({super.key});

  @override
  ConsumerState<SettingsAccountScreen> createState() =>
      _SettingsAccountScreenState();
}

class _SettingsAccountScreenState extends ConsumerState<SettingsAccountScreen> {
  final currentPinForPhoneCtrl = TextEditingController();
  final newPhoneCtrl = TextEditingController();
  final currentPinForPinCtrl = TextEditingController();
  final newPinCtrl = TextEditingController();
  final confirmPinCtrl = TextEditingController();

  @override
  void dispose() {
    currentPinForPhoneCtrl.dispose();
    newPhoneCtrl.dispose();
    currentPinForPinCtrl.dispose();
    newPinCtrl.dispose();
    confirmPinCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = ref.watch(appStringsProvider);
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      appBar: AppBar(title: Text(strings.t('accountSecurity'))),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          if (!auth.isAuthed)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(strings.t('loginRequiredAccount')),
              ),
            )
          else ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '${strings.t('phoneLabel')}: ${auth.user?.phone ?? '-'}',
                    ),
                    const SizedBox(height: 12),
                    Text(
                      strings.t('changePhone'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _pinField(
                      controller: currentPinForPhoneCtrl,
                      label: strings.t('currentPin'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: newPhoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: strings.t('newPhone'),
                      ),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: auth.loading ? null : _savePhone,
                      icon: const Icon(Icons.phone_android_rounded),
                      label: Text(strings.t('savePhone')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      strings.t('changePin'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 8),
                    _pinField(
                      controller: currentPinForPinCtrl,
                      label: strings.t('currentPin'),
                    ),
                    const SizedBox(height: 8),
                    _pinField(
                      controller: newPinCtrl,
                      label: strings.t('newPin'),
                    ),
                    const SizedBox(height: 8),
                    _pinField(
                      controller: confirmPinCtrl,
                      label: strings.t('confirmNewPin'),
                    ),
                    const SizedBox(height: 10),
                    ElevatedButton.icon(
                      onPressed: auth.loading ? null : _savePin,
                      icon: const Icon(Icons.lock_outline_rounded),
                      label: Text(strings.t('savePin')),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            _DeleteAccountCard(
              loading: auth.loading,
              onDelete: _confirmDeleteAccount,
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _confirmDeleteAccount() async {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteAccountConfirmTitle),
        content: Text(l10n.settingsDeleteAccountConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsDeleteAccountConfirmAction),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final finalConfirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.settingsDeleteAccountFinalConfirmTitle),
        content: Text(l10n.settingsDeleteAccountFinalConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(MaterialLocalizations.of(ctx).cancelButtonLabel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: scheme.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(l10n.settingsDeleteAccountFinalConfirmAction),
          ),
        ],
      ),
    );
    if (finalConfirmed != true || !mounted) return;
    final ok = await ref.read(authControllerProvider.notifier).deleteAccount();
    if (!mounted) return;
    if (ok) {
      // Session cleared → the router redirects to login. Leave the settings stack.
      Navigator.of(context).popUntil((route) => route.isFirst);
      return;
    }
    final error = ref.read(authControllerProvider).error;
    _snack(
      (error != null && error.isNotEmpty)
          ? error
          : l10n.settingsDeleteAccountFailed,
    );
  }

  Widget _pinField({
    required TextEditingController controller,
    required String label,
  }) {
    return TextField(
      controller: controller,
      keyboardType: TextInputType.number,
      obscureText: true,
      decoration: InputDecoration(labelText: label),
    );
  }

  Future<void> _savePhone() async {
    final strings = ref.read(appStringsProvider);
    final currentPin = currentPinForPhoneCtrl.text.trim();
    final newPhone = newPhoneCtrl.text.trim();
    if (currentPin.isEmpty) {
      _snack(strings.t('enterCurrentPin'));
      return;
    }
    if (newPhone.isEmpty) {
      _snack(strings.t('enterPhone'));
      return;
    }

    final ok = await ref
        .read(authControllerProvider.notifier)
        .updateAccount(currentPin: currentPin, newPhone: newPhone);
    if (!mounted) return;

    if (ok) {
      newPhoneCtrl.clear();
      currentPinForPhoneCtrl.clear();
      _snack(strings.t('phoneUpdated'));
      return;
    }

    final error = ref.read(authControllerProvider).error;
    if (error != null && error.isNotEmpty) {
      _snack(error);
    }
  }

  Future<void> _savePin() async {
    final strings = ref.read(appStringsProvider);
    final currentPin = currentPinForPinCtrl.text.trim();
    final newPin = newPinCtrl.text.trim();
    final confirmPin = confirmPinCtrl.text.trim();

    if (currentPin.isEmpty) {
      _snack(strings.t('enterCurrentPin'));
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(newPin)) {
      _snack(strings.t('pinMinDigits'));
      return;
    }
    if (newPin != confirmPin) {
      _snack(strings.t('pinMismatch'));
      return;
    }

    final ok = await ref
        .read(authControllerProvider.notifier)
        .updateAccount(currentPin: currentPin, newPin: newPin);
    if (!mounted) return;

    if (ok) {
      currentPinForPinCtrl.clear();
      newPinCtrl.clear();
      confirmPinCtrl.clear();
      _snack(strings.t('pinUpdated'));
      return;
    }

    final error = ref.read(authControllerProvider).error;
    if (error != null && error.isNotEmpty) {
      _snack(error);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _DeleteAccountCard extends StatelessWidget {
  final bool loading;
  final Future<void> Function() onDelete;

  const _DeleteAccountCard({required this.loading, required this.onDelete});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(Icons.delete_forever_rounded, color: scheme.error),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    l10n.settingsDeleteAccount,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      color: scheme.error,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.settingsDeleteAccountHint),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: scheme.error,
                side: BorderSide(color: scheme.error),
              ),
              onPressed: loading ? null : () => onDelete(),
              icon: const Icon(Icons.delete_outline_rounded),
              label: Text(l10n.settingsDeleteAccount),
            ),
          ],
        ),
      ),
    );
  }
}
