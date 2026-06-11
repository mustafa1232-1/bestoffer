import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../state/app_startup_controller.dart';
import 'onboarding_screen.dart';

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

    if (state.phase == AppStartupPhase.onboarding) {
      return MaslakiOnboardingScreen(onStartNow: notifier.completeFirstLaunch);
    }

    final waiting =
        state.phase == AppStartupPhase.idle ||
        state.phase == AppStartupPhase.checkingServer;
    final failed = state.phase == AppStartupPhase.serverCheckFailed;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF050B24), Color(0xFF101B45), Color(0xFF261B52)],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(26),
                    color: Colors.white.withValues(alpha: 0.09),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.14),
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 66,
                          height: 66,
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: LinearGradient(
                                begin: Alignment.topLeft,
                                end: Alignment.bottomRight,
                                colors: [Color(0xFF43D6FF), Color(0xFF7A5BFF)],
                              ),
                            ),
                            child: Icon(
                              Icons.rocket_launch_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          l10n.startupIntroPreparingTitle,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          waiting
                              ? l10n.startupIntroCheckingServer
                              : l10n.startupIntroServerUnavailable,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.86),
                            height: 1.5,
                            fontSize: 15.2,
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (waiting) ...[
                          const LinearProgressIndicator(minHeight: 5),
                        ] else if (failed) ...[
                          if (state.error?.trim().isNotEmpty == true)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                l10n.startupIntroErrorDetails(state.error!),
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: Colors.red.shade200,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          FilledButton.icon(
                            onPressed: notifier.checkServerReadiness,
                            icon: const Icon(Icons.refresh_rounded),
                            label: Text(l10n.commonRetry),
                          ),
                        ],
                        const SizedBox(height: 10),
                        Text(
                          l10n.startupIntroAttempts(state.attempts),
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.66),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
