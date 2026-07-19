import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_controller.dart';

class ServiceProviderShell extends ConsumerWidget {
  final Widget child;

  const ServiceProviderShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authControllerProvider);
    if (!auth.isAuthed) {
      return const _ServiceProviderAccessBlocked(
        title: 'تسجيل الدخول مطلوب',
        message: 'سجل الدخول بحساب صاحب خدمة للوصول إلى لوحة الخدمات.',
      );
    }
    if (!auth.isServiceProvider) {
      return const _ServiceProviderAccessBlocked(
        title: 'غير مخول',
        message: 'هذا المسار مخصص فقط لحسابات أصحاب الخدمات.',
      );
    }
    return child;
  }
}

class _ServiceProviderAccessBlocked extends StatelessWidget {
  final String title;
  final String message;

  const _ServiceProviderAccessBlocked({
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الخدمات')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.lock_outline, size: 54),
              const SizedBox(height: 12),
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 20,
                ),
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
