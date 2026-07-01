import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../state/app_startup_controller.dart';
import 'splash_screen.dart';

class IntroScreen extends ConsumerStatefulWidget {
  const IntroScreen({super.key});

  @override
  ConsumerState<IntroScreen> createState() => _IntroScreenState();
}

class _IntroScreenState extends ConsumerState<IntroScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(appStartupControllerProvider.notifier).bootstrap();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(appStartupControllerProvider);
    final notifier = ref.read(appStartupControllerProvider.notifier);

    final waiting = state.phase != AppStartupPhase.serverCheckFailed;
    final failed = state.phase == AppStartupPhase.serverCheckFailed;
    return MaslakiSplashScreen(
      waiting: waiting,
      statusTitle: waiting ? l10n.startupIntroPreparingTitle : l10n.commonRetry,
      statusMessage: waiting
          ? l10n.startupIntroCheckingServer
          : l10n.startupIntroServerUnavailable,
      errorDetails: failed && state.error?.trim().isNotEmpty == true
          ? l10n.startupIntroErrorDetails(state.error!)
          : null,
      attempts: state.attempts,
      onRetry: failed ? notifier.checkServerReadiness : null,
    );
  }
}
