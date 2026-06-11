// ignore_for_file: deprecated_member_use

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/settings/app_settings_controller.dart';
import '../state/auth_controller.dart';
import 'owner_register_screen.dart';
import 'taxi_captain_register_screen.dart';

enum RoleLoginScope { owner, delivery, taxiCaptain }

class RoleLoginScreen extends ConsumerStatefulWidget {
  final RoleLoginScope scope;

  const RoleLoginScreen({super.key, required this.scope});

  @override
  ConsumerState<RoleLoginScreen> createState() => _RoleLoginScreenState();
}

class _RoleLoginScreenState extends ConsumerState<RoleLoginScreen> {
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  String? _phoneError;
  String? _pinError;

  @override
  void dispose() {
    phoneCtrl.dispose();
    pinCtrl.dispose();
    super.dispose();
  }

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

    final isValidRole = switch (widget.scope) {
      RoleLoginScope.owner => authAfter.isOwner,
      RoleLoginScope.delivery => authAfter.isDelivery,
      RoleLoginScope.taxiCaptain => authAfter.isTaxiCaptain,
    };

    if (isValidRole) return;

    if (authAfter.isAuthed) {
      await ref.read(authControllerProvider.notifier).logout();
      if (!mounted) return;
      final mismatch = switch (widget.scope) {
        RoleLoginScope.owner => l10n.authOwnerOnlyAppError,
        RoleLoginScope.delivery => l10n.authDeliveryOnlyAppError,
        RoleLoginScope.taxiCaptain => l10n.authTaxiCaptainOnlyAppError,
      };
      messenger.showSnackBar(SnackBar(content: Text(mismatch)));
    }
  }

  String _title(BuildContext context) {
    final l10n = context.l10n;
    return switch (widget.scope) {
      RoleLoginScope.owner => l10n.storePortalWindowTitle,
      RoleLoginScope.delivery => l10n.deliveryAppTitle,
      RoleLoginScope.taxiCaptain => l10n.taxiCaptainAppTitle,
    };
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: Stack(
        children: [
          const _MeshBackground(),
          SafeArea(
            child: Center(
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
                                Expanded(
                                  child: Text(
                                    _title(context),
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 21,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: context.l10n.commonLanguage,
                                  icon: const Icon(
                                    Icons.translate_rounded,
                                    color: Colors.white,
                                  ),
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
                              ],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              context.l10n.authLoginTagline,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 13,
                              ),
                            ),
                            _Field(
                              controller: phoneCtrl,
                              label: context.l10n.authPhoneLabel,
                              hint: '0770xxxxxxx',
                              keyboardType: TextInputType.phone,
                              textDirection: TextDirection.ltr,
                              errorText: _phoneError,
                              onChanged: (_) {
                                if (_phoneError == null) return;
                                setState(() => _phoneError = null);
                              },
                            ),
                            const SizedBox(height: 12),
                            _Field(
                              controller: pinCtrl,
                              label: context.l10n.authPinLabel,
                              hint: '****',
                              keyboardType: TextInputType.number,
                              obscure: true,
                              textDirection: TextDirection.ltr,
                              errorText: _pinError,
                              onChanged: (_) {
                                if (_pinError == null) return;
                                setState(() => _pinError = null);
                              },
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
                              onPressed: auth.loading
                                  ? null
                                  : () => _submitLogin(context),
                              child: auth.loading
                                  ? const SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(context.l10n.authLogin),
                            ),
                            const SizedBox(height: 8),
                            if (widget.scope == RoleLoginScope.owner)
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const OwnerRegisterScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  context.l10n.authCreateOwnerAccount,
                                  style: const TextStyle(color: Colors.white),
                                ),
                              ),
                            if (widget.scope == RoleLoginScope.taxiCaptain)
                              TextButton(
                                onPressed: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) =>
                                          const TaxiCaptainRegisterScreen(),
                                    ),
                                  );
                                },
                                child: Text(
                                  context.l10n.authTaxiCaptainAccount,
                                  style: const TextStyle(color: Colors.white),
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
        ],
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
