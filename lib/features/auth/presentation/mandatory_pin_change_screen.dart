import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/auth_input_normalizer.dart';
import '../state/auth_controller.dart';

class MandatoryPinChangeScreen extends ConsumerStatefulWidget {
  const MandatoryPinChangeScreen({super.key, this.initialPin = ''});

  final String initialPin;

  @override
  ConsumerState<MandatoryPinChangeScreen> createState() =>
      _MandatoryPinChangeScreenState();
}

class _MandatoryPinChangeScreenState
    extends ConsumerState<MandatoryPinChangeScreen> {
  late final current = TextEditingController(text: widget.initialPin);
  final next = TextEditingController();
  String? error;
  bool saving = false;

  @override
  void dispose() {
    current.dispose();
    next.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (saving) return;
    final currentValue = normalizeAuthPin(current.text);
    final value = normalizeAuthPin(next.text);
    if (!RegExp(r'^\d{4,8}$').hasMatch(currentValue)) {
      setState(() => error = 'أدخل الرمز المؤقت الذي استخدمته لتسجيل الدخول');
      return;
    }
    if (!RegExp(r'^\d{4,8}$').hasMatch(value) || value == '1234') {
      setState(
        () => error = 'أدخل رمزًا جديدًا من 4 إلى 8 أرقام، ولا تستخدم 1234',
      );
      return;
    }
    if (value == currentValue) {
      setState(() => error = 'يجب أن يختلف الرمز الجديد عن الرمز المؤقت');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await ref
          .read(authControllerProvider.notifier)
          .completeTemporaryPinChange(currentValue, value);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          saving = false;
          error = 'تعذر حفظ الرمز الجديد، حاول مرة أخرى';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('تعيين رمز جديد')),
    body: Padding(
      padding: const EdgeInsets.all(24),
      child: ListView(
        children: [
          const Icon(Icons.lock_reset_rounded, size: 56),
          const SizedBox(height: 16),
          const Text(
            'تمت الموافقة على إعادة تعيين حسابك. يجب إنشاء رمز جديد قبل المتابعة.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          TextField(
            controller: current,
            enabled: !saving,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(labelText: 'الرمز المؤقت الحالي'),
          ),
          TextField(
            controller: next,
            enabled: !saving,
            obscureText: true,
            keyboardType: TextInputType.number,
            maxLength: 8,
            decoration: const InputDecoration(labelText: 'الرمز الجديد'),
          ),
          if (error != null) ...[
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ],
          FilledButton(
            onPressed: saving ? null : submit,
            child: Text(saving ? 'جار الحفظ...' : 'حفظ الرمز والمتابعة'),
          ),
        ],
      ),
    ),
  );
}
