// ignore_for_file: use_build_context_synchronously

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/auth_controller.dart';

class DeliveryRegisterScreen extends ConsumerStatefulWidget {
  const DeliveryRegisterScreen({super.key});

  @override
  ConsumerState<DeliveryRegisterScreen> createState() =>
      _DeliveryRegisterScreenState();
}

class _DeliveryRegisterScreenState extends ConsumerState<DeliveryRegisterScreen> {
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final blockCtrl = TextEditingController();
  final buildingCtrl = TextEditingController();
  final aptCtrl = TextEditingController();
  bool analyticsConsentAccepted = false;

  @override
  void dispose() {
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    blockCtrl.dispose();
    buildingCtrl.dispose();
    aptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);

    return Scaffold(
      body: Stack(
        children: [
          const _MeshBackground(),
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 520),
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
                          color: Colors.white.withOpacity(0.18),
                        ),
                        color: Colors.white.withOpacity(0.08),
                      ),
                      child: Directionality(
                        textDirection: TextDirection.rtl,
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  IconButton(
                                    onPressed: () => Navigator.of(context).pop(),
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'إنشاء حساب دلفري',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                controller: fullNameCtrl,
                                label: 'الاسم الكامل',
                                hint: 'مثال: سيف أحمد',
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                controller: phoneCtrl,
                                label: 'رقم الهاتف',
                                hint: '0770xxxxxxx',
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                controller: pinCtrl,
                                label: 'الرمز السري PIN',
                                hint: '4-8 أرقام',
                                keyboardType: TextInputType.number,
                                obscure: true,
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: [
                                  Expanded(
                                    child: _Field(
                                      controller: blockCtrl,
                                      label: 'البلوك',
                                      hint: 'B',
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _Field(
                                      controller: buildingCtrl,
                                      label: 'رقم العمارة',
                                      hint: '12',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: _Field(
                                      controller: aptCtrl,
                                      label: 'الشقة',
                                      hint: '3',
                                      keyboardType: TextInputType.number,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              _ConsentCard(
                                accepted: analyticsConsentAccepted,
                                onChanged: (value) {
                                  setState(() => analyticsConsentAccepted = value);
                                },
                                onDetailsTap: () => _showConsentInfo(context),
                              ),
                              const SizedBox(height: 14),
                              if (auth.error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 10),
                                  child: Text(
                                    auth.error!,
                                    style: const TextStyle(color: Colors.amber),
                                  ),
                                ),
                              ElevatedButton(
                                onPressed: auth.loading
                                    ? null
                                    : () async {
                                        if (!analyticsConsentAccepted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'يرجى الموافقة على سياسة تحسين التجربة أولاً',
                                              ),
                                            ),
                                          );
                                          return;
                                        }

                                        FocusScope.of(context).unfocus();
                                        await ref
                                            .read(authControllerProvider.notifier)
                                            .registerDelivery({
                                              'fullName': fullNameCtrl.text,
                                              'phone': phoneCtrl.text,
                                              'pin': pinCtrl.text,
                                              'block': blockCtrl.text,
                                              'buildingNumber':
                                                  buildingCtrl.text,
                                              'apartment': aptCtrl.text,
                                              'analyticsConsentAccepted': true,
                                              'analyticsConsentVersion':
                                                  'analytics_v1',
                                            });

                                        if (mounted &&
                                            ref
                                                .read(authControllerProvider)
                                                .isAuthed) {
                                          Navigator.of(context).pop();
                                        }
                                      },
                                child: auth.loading
                                    ? const SizedBox(
                                        height: 18,
                                        width: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : const Text('إنشاء حساب الدلفري'),
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
          ),
        ],
      ),
    );
  }

  Future<void> _showConsentInfo(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: const [
                Text(
                  'سياسة تحسين التجربة',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                ),
                SizedBox(height: 10),
                Text(
                  'نقوم بجمع بيانات الاستخدام داخل التطبيق لتحسين التوصيات وسير العمل، دون أي تجاوز للخصوصية.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  final bool accepted;
  final ValueChanged<bool> onChanged;
  final VoidCallback onDetailsTap;

  const _ConsentCard({
    required this.accepted,
    required this.onChanged,
    required this.onDetailsTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const Icon(
                Icons.privacy_tip_outlined,
                color: Colors.white70,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'نستخدم نشاطك داخل التطبيق لتحسين الاقتراحات وجودة الخدمة.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.9),
                    fontSize: 12.5,
                  ),
                ),
              ),
              TextButton(
                onPressed: onDetailsTap,
                child: const Text('التفاصيل'),
              ),
            ],
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: accepted,
            activeColor: Colors.cyanAccent.shade400,
            checkColor: Colors.black,
            onChanged: (value) => onChanged(value == true),
            title: const Text(
              'أوافق على جمع بيانات الاستخدام لتحسين تجربتي',
              style: TextStyle(color: Colors.white, fontSize: 13),
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

  const _Field({
    required this.controller,
    required this.label,
    required this.hint,
    this.keyboardType = TextInputType.text,
    this.obscure = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscure,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(labelText: label, hintText: hint),
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

