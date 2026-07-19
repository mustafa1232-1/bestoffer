// ignore_for_file: deprecated_member_use

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/platform/app_platform_capabilities.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/widgets/maslaki_brand_mark.dart';
import '../../../core/widgets/maslaki_wordmark.dart';
import '../../settings/ui/settings_screen.dart';
import '../../services/ui/service_provider_onboarding_screen.dart';
import '../state/auth_controller.dart';
import 'register_screen.dart';

/// شاشة الدخول الأساسية للتطبيق، وتستخدم أيضاً كبوابة مقيدة لمسار أصحاب
/// المتاجر عندما يكون `ownerOnly=true`.
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  late final AnimationController _controller;
  String? _phoneError;
  String? _pinError;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

  /// يتحقق من صحة الهاتف قبل إرسال الطلب إلى الخادم لتقليل round-trips.
  String? _validatePhone(BuildContext context, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return context.l10n.authPhoneRequired;
    }
    final digitsOnly = normalized.replaceAll(RegExp(r'[^0-9]'), '');
    if (digitsOnly.length < 10) {
      return context.l10n.authPhoneIncomplete;
    }
    return null;
  }

  /// يتحقق من صيغة PIN المتوقعة من النظام قبل login.
  String? _validatePin(BuildContext context, String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) {
      return context.l10n.authPinRequired;
    }
    if (!RegExp(r'^[0-9]{4,8}$').hasMatch(normalized)) {
      return context.l10n.authPinInvalidFormat;
    }
    return null;
  }

  /// ينفذ login ثم يطبق guard إضافي لمسار owner-only إذا كانت الشاشة مستخدمة
  /// داخل تطبيق أو تدفق مقصور على أصحاب المتاجر.
  Future<void> _submitLogin(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = context.l10n;
    FocusScope.of(context).unfocus();
    final phoneError = _validatePhone(context, phoneCtrl.text);
    final pinError = _validatePin(context, pinCtrl.text);
    setState(() {
      _phoneError = phoneError;
      _pinError = pinError;
    });
    if (phoneError != null || pinError != null) return;

    await ref
        .read(authControllerProvider.notifier)
        .login(phoneCtrl.text, pinCtrl.text);

    if (!mounted) return;
    final authAfter = ref.read(authControllerProvider);
    if (!authAfter.isAuthed && authAfter.error != null) {
      setState(() {
        _pinError = authAfter.error;
      });
      return;
    }
    if (authAfter.isCustomer ||
        authAfter.isBackoffice ||
        authAfter.isServiceProvider) {
      return;
    }

    if (authAfter.isAuthed) {
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.authUserOnlyAppError)),
      );
    }
  }

  @override
  /// يبني shell شاشة الدخول مع دعم layout مكتبي/هاتفي وسلوك اللغة الحالي.
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final settings = ref.watch(appSettingsControllerProvider);
    final l10n = context.l10n;
    final useDesktopLayout =
        appIsDesktop && MediaQuery.sizeOf(context).width >= 1180;

    if (settings.animationsEnabled && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!settings.animationsEnabled && _controller.isAnimating) {
      _controller.stop(canceled: false);
      _controller.value = 0;
    }

    return Scaffold(
      body: Stack(
        children: [
          const _MeshBackground(),
          SafeArea(
            child: Padding(
              padding: EdgeInsets.all(useDesktopLayout ? 24 : 18),
              child: useDesktopLayout
                  ? Row(
                      children: [
                        const Expanded(child: _DesktopLoginShowcase()),
                        const SizedBox(width: 24),
                        SizedBox(
                          width: 470,
                          child: _buildLoginCard(
                            context,
                            auth: auth,
                            settings: settings,
                            l10n: l10n,
                          ),
                        ),
                      ],
                    )
                  : Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 430),
                        child: _buildLoginCard(
                          context,
                          auth: auth,
                          settings: settings,
                          l10n: l10n,
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  /// يبني البطاقة الزجاجية التي تحتوي حقول الدخول والإجراءات الثانوية.
  Widget _buildLoginCard(
    BuildContext context, {
    required AuthState auth,
    required AppSettingsState settings,
    required AppLocalizations l10n,
  }) {
    final tokens = context.maslakiTokens;
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: tokens.borderSubtle.withValues(alpha: 0.72),
            ),
            color: tokens.cardPrimary.withValues(alpha: 0.78),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const MaslakiBrandMark(size: 46, borderRadius: 14),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: MaslakiWordmark(
                      arabicSize: 22,
                      latinSize: 9.5,
                      latinLetterSpacing: 3.6,
                      crossAxisAlignment: CrossAxisAlignment.start,
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: l10n.commonLanguage,
                    icon: Icon(Icons.translate, color: tokens.textPrimary),
                    onSelected: (code) {
                      ref
                          .read(appSettingsControllerProvider.notifier)
                          .setLocale(Locale(code));
                    },
                    itemBuilder: (context) => [
                      PopupMenuItem(
                        value: 'ar',
                        child: Text(l10n.commonArabic),
                      ),
                      PopupMenuItem(
                        value: 'en',
                        child: Text(l10n.commonEnglish),
                      ),
                    ],
                  ),
                  IconButton(
                    tooltip: l10n.commonSettings,
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white70,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              _WelcomePill(
                controller: _controller,
                animationsEnabled: settings.animationsEnabled,
                text: l10n.authLoginTagline,
              ),
              const SizedBox(height: 14),
              Form(
                child: Column(
                  children: [
                    _Field(
                      controller: phoneCtrl,
                      label: l10n.authPhoneLabel,
                      hint: '0770xxxxxxx',
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      errorText: _phoneError,
                      onChanged: (_) {
                        if (_phoneError == null) return;
                        setState(() {
                          _phoneError = null;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    _Field(
                      controller: pinCtrl,
                      label: l10n.authPinLabel,
                      hint: '****',
                      keyboardType: TextInputType.number,
                      obscure: true,
                      textDirection: TextDirection.ltr,
                      errorText: _pinError,
                      onChanged: (_) {
                        if (_pinError == null) return;
                        setState(() {
                          _pinError = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (auth.error != null && _pinError != auth.error)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text(
                    auth.error!,
                    style: const TextStyle(color: Colors.amber),
                    textAlign: TextAlign.start,
                  ),
                ),
              ElevatedButton(
                onPressed: auth.loading ? null : () => _submitLogin(context),
                child: auth.loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.authLogin),
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const RegisterScreen()),
                  );
                },
                child: Text(
                  l10n.authCreateUserAccount,
                  style: TextStyle(color: tokens.textPrimary),
                ),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ServiceProviderOnboardingScreen(),
                    ),
                  );
                },
                child: const Text('إنشاء حساب صاحب خدمة'),
              ),
              const SizedBox(height: 6),
              FilledButton.icon(
                onPressed: auth.loading
                    ? null
                    : () async {
                        await ref
                            .read(authControllerProvider.notifier)
                            .continueAsGuest();
                      },
                icon: const Icon(Icons.person_outline_rounded),
                label: Text(
                  context.lt(ar: 'الدخول كزائر', en: 'Continue as Guest'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DesktopLoginShowcase extends StatelessWidget {
  const _DesktopLoginShowcase();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: const LinearGradient(
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
          colors: [Color(0x66D4B07A), Color(0x22FFFFFF), Color(0x334A6D93)],
        ),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              MaslakiBrandMark(size: 56, borderRadius: 18),
              SizedBox(width: 12),
              MaslakiWordmark(
                arabicSize: 30,
                latinSize: 11,
                latinLetterSpacing: 4.2,
                arabicColor: Colors.white,
                latinColor: Color(0xFFE5C38F),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            l10n.authDesktopTitle,
            style: theme.textTheme.displaySmall?.copyWith(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            l10n.authLoginTagline,
            style: theme.textTheme.titleMedium?.copyWith(
              color: Colors.white.withOpacity(0.86),
            ),
          ),
          const SizedBox(height: 24),
          _DesktopFeatureTile(
            icon: Icons.desktop_windows_rounded,
            title: l10n.authDesktopFeatureNavigationTitle,
            subtitle: l10n.authDesktopFeatureNavigationBody,
          ),
          const SizedBox(height: 12),
          _DesktopFeatureTile(
            icon: Icons.dashboard_customize_rounded,
            title: l10n.authDesktopFeatureControlsTitle,
            subtitle: l10n.authDesktopFeatureControlsBody,
          ),
          const SizedBox(height: 12),
          _DesktopFeatureTile(
            icon: Icons.fullscreen_rounded,
            title: l10n.authDesktopFeatureWorkspaceTitle,
            subtitle: l10n.authDesktopFeatureWorkspaceBody,
          ),
          const Spacer(),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _DesktopStatChip(label: l10n.authDesktopChipCommunity),
              _DesktopStatChip(label: l10n.authDesktopChipOrders),
              _DesktopStatChip(label: l10n.authDesktopChipTaxi),
            ],
          ),
        ],
      ),
    );
  }
}

class _DesktopFeatureTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _DesktopFeatureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFFD4B07A)),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(color: Colors.white.withOpacity(0.76)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DesktopStatChip extends StatelessWidget {
  final String label;

  const _DesktopStatChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Colors.white.withOpacity(0.10),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _WelcomePill extends StatelessWidget {
  final AnimationController controller;
  final bool animationsEnabled;
  final String text;

  const _WelcomePill({
    required this.controller,
    required this.animationsEnabled,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    if (!animationsEnabled) {
      return _buildContent(0.55);
    }

    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final value = Curves.easeInOut.transform(controller.value);
        return _buildContent(value);
      },
    );
  }

  Widget _buildContent(double value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Color.lerp(
          const Color(0x33D4B07A),
          const Color(0x334A6D93),
          value,
        ),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: TextStyle(color: Colors.white.withOpacity(0.95)),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final TextInputType keyboardType;
  final bool obscure;
  final TextDirection textDirection;
  final String? errorText;
  final ValueChanged<String>? onChanged;

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.keyboardType,
    required this.textDirection,
    this.obscure = false,
    this.errorText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: textDirection,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        onChanged: onChanged,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          errorText: errorText,
          hintText: hint,
          hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
          labelStyle: TextStyle(color: Colors.white.withOpacity(0.85)),
          filled: true,
          fillColor: Colors.white.withOpacity(0.10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(18)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.16)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: BorderSide(color: Colors.white.withOpacity(0.35)),
          ),
        ),
      ),
    );
  }
}

class _MeshBackground extends StatelessWidget {
  const _MeshBackground();

  @override
  Widget build(BuildContext context) {
    return const SizedBox.expand();
  }
}
