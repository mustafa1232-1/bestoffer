import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
          ],
        ],
      ),
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
