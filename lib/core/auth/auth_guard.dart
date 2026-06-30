import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/presentation/login_screen.dart';
import '../../features/auth/state/auth_controller.dart';
import '../i18n/locale_text.dart';

Future<bool> requireAuthBeforeAction(
  BuildContext context, {
  String? featureArabic,
  String? featureEnglish,
}) async {
  final auth = ProviderScope.containerOf(context, listen: false).read(
    authControllerProvider,
  );
  if (auth.isAuthed) return true;

  final sheetContext = context;
  await showModalBottomSheet<void>(
    context: sheetContext,
    useRootNavigator: true,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) {
      final featureLine = _buildFeatureLine(
        context,
        arabic: featureArabic,
        english: featureEnglish,
      );
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'تحتاج إلى تسجيل الدخول لاستخدام هذه الميزة',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'You need to sign in to use this feature',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context)
                          .colorScheme
                          .onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              if (featureLine != null) ...[
                const SizedBox(height: 10),
                Text(
                  featureLine,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context)
                            .colorScheme
                            .onSurfaceVariant,
                      ),
                ),
              ],
              const SizedBox(height: 18),
              FilledButton(
                onPressed: () {
                  final rootNavigator = Navigator.of(
                    sheetContext,
                    rootNavigator: true,
                  );
                  Navigator.of(context).pop();
                  rootNavigator.push(
                    MaterialPageRoute<void>(
                      builder: (_) => const LoginScreen(),
                    ),
                  );
                },
                child: Text(
                  context.lt(ar: 'تسجيل الدخول', en: 'Sign in'),
                ),
              ),
              const SizedBox(height: 10),
              OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  context.lt(ar: 'متابعة التصفح', en: 'Continue browsing'),
                ),
              ),
            ],
          ),
        ),
      );
    },
  );
  return false;
}

String? _buildFeatureLine(
  BuildContext context, {
  String? arabic,
  String? english,
}) {
  final ar = (arabic ?? '').trim();
  final en = (english ?? '').trim();
  if (ar.isEmpty && en.isEmpty) return null;
  if (ar.isEmpty) return en;
  if (en.isEmpty) return ar;
  return context.lt(ar: ar, en: en);
}
