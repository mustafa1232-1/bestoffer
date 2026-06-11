import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../../core/theme/app_backdrop.dart';
import '../state/company_session_controller.dart';

class CompanyLoginScreen extends ConsumerStatefulWidget {
  const CompanyLoginScreen({super.key});

  @override
  ConsumerState<CompanyLoginScreen> createState() => _CompanyLoginScreenState();
}

class _CompanyLoginScreenState extends ConsumerState<CompanyLoginScreen> {
  final _phoneController = TextEditingController();
  final _pinController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _phoneController.dispose();
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(companySessionControllerProvider.notifier).login(
      phone: _phoneController.text.trim(),
      pin: _pinController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final session = ref.watch(companySessionControllerProvider);
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: AppBackdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(28),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: AlignmentDirectional.centerEnd,
                          child: PopupMenuButton<String>(
                            tooltip: l10n.commonLanguage,
                            icon: const Icon(Icons.translate_rounded),
                            onSelected: (code) {
                              ref
                                  .read(appSettingsControllerProvider.notifier)
                                  .setLocale(Locale(code));
                            },
                            itemBuilder: (menuContext) => [
                              PopupMenuItem(
                                value: 'ar',
                                child: Text(menuContext.l10n.commonArabic),
                              ),
                              PopupMenuItem(
                                value: 'en',
                                child: Text(menuContext.l10n.commonEnglish),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            color: scheme.primary.withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Icon(
                            Icons.apartment_rounded,
                            color: scheme.primary,
                            size: 34,
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          l10n.companyPortalTitle,
                          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          l10n.companyLoginIntro,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                        const SizedBox(height: 24),
                        TextFormField(
                          controller: _phoneController,
                          keyboardType: TextInputType.phone,
                          decoration: InputDecoration(
                            labelText: l10n.authPhoneLabel,
                            prefixIcon: const Icon(Icons.phone_android_rounded),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().isEmpty) {
                              return l10n.authPhoneRequired;
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 14),
                        TextFormField(
                          controller: _pinController,
                          keyboardType: TextInputType.number,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: l10n.authPinLabel,
                            prefixIcon: const Icon(Icons.lock_rounded),
                          ),
                          validator: (value) {
                            if ((value ?? '').trim().length < 4) {
                              return l10n.authPinInvalidFormat;
                            }
                            return null;
                          },
                          onFieldSubmitted: (_) => _submit(),
                        ),
                        if (session.error?.isNotEmpty == true) ...[
                          const SizedBox(height: 14),
                          Text(
                            session.error!,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: scheme.error),
                          ),
                        ],
                        const SizedBox(height: 22),
                        FilledButton.icon(
                          onPressed: session.loggingIn ? null : _submit,
                          icon: session.loggingIn
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.login_rounded),
                          label: Text(
                            session.loggingIn
                                ? l10n.companyLoginSigningIn
                                : l10n.companyLoginSubmit,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          l10n.companyLoginAccessHint,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
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
