// ignore_for_file: deprecated_member_use

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_strings.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../../settings/ui/settings_screen.dart';
import '../state/auth_controller.dart';
import 'delivery_register_screen.dart';
import 'owner_register_screen.dart';
import 'register_screen.dart';

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

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    final strings = ref.watch(appStringsProvider);
    final settings = ref.watch(appSettingsControllerProvider);

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
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 430),
              child: Padding(
                padding: const EdgeInsets.all(18),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.16),
                        ),
                        color: Colors.white.withOpacity(0.08),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  color: Colors.white.withOpacity(0.12),
                                ),
                                child: const Icon(
                                  Icons.storefront,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'BestOffer | Basmaya',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 21,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              PopupMenuButton<String>(
                                tooltip: strings.t('language'),
                                icon: const Icon(
                                  Icons.translate,
                                  color: Colors.white,
                                ),
                                onSelected: (code) {
                                  ref
                                      .read(
                                        appSettingsControllerProvider.notifier,
                                      )
                                      .setLocale(Locale(code));
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'ar',
                                    child: Text(strings.t('arabic')),
                                  ),
                                  PopupMenuItem(
                                    value: 'en',
                                    child: Text(strings.t('english')),
                                  ),
                                ],
                              ),
                              IconButton(
                                tooltip: strings.t('settings'),
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => const SettingsScreen(),
                                    ),
                                  );
                                },
                                icon: const Icon(
                                  Icons.settings_outlined,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          _WelcomePill(
                            controller: _controller,
                            animationsEnabled: settings.animationsEnabled,
                            text: strings.t('loginTagline'),
                          ),
                          const SizedBox(height: 14),
                          _Field(
                            controller: phoneCtrl,
                            label: strings.t('phoneLabel'),
                            hint: '0770xxxxxxx',
                            keyboardType: TextInputType.phone,
                            textDirection: strings.isEnglish
                                ? TextDirection.ltr
                                : TextDirection.rtl,
                          ),
                          const SizedBox(height: 12),
                          _Field(
                            controller: pinCtrl,
                            label: strings.t('pinLabel'),
                            hint: '****',
                            keyboardType: TextInputType.number,
                            obscure: true,
                            textDirection: TextDirection.ltr,
                          ),
                          const SizedBox(height: 14),
                          if (auth.error != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Text(
                                auth.error!,
                                style: const TextStyle(color: Colors.amber),
                                textAlign: TextAlign.start,
                              ),
                            ),
                          ElevatedButton(
                            onPressed: auth.loading
                                ? null
                                : () async {
                                    FocusScope.of(context).unfocus();
                                    await ref
                                        .read(authControllerProvider.notifier)
                                        .login(phoneCtrl.text, pinCtrl.text);
                                  },
                            child: auth.loading
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : Text(strings.t('login')),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const RegisterScreen(),
                                ),
                              );
                            },
                            child: Text(
                              strings.t('createUserAccount'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) => const OwnerRegisterScreen(),
                                ),
                              );
                            },
                            child: Text(
                              strings.t('createOwnerAccount'),
                              style: const TextStyle(color: Colors.white),
                            ),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (_) =>
                                      const DeliveryRegisterScreen(),
                                ),
                              );
                            },
                            child: const Text(
                              'إنشاء حساب كابتن تكسي',
                              style: TextStyle(color: Colors.white),
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
        ],
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
          const Color(0x334ED6FF),
          const Color(0x3395FFD3),
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

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    required this.keyboardType,
    required this.textDirection,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: textDirection,
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        obscureText: obscure,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
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
