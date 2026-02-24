// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../state/auth_controller.dart';

class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final blockCtrl = TextEditingController();
  final buildingCtrl = TextEditingController();
  final aptCtrl = TextEditingController();
  LocalImageFile? customerImageFile;

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
                                    onPressed: () =>
                                        Navigator.of(context).pop(),
                                    icon: const Icon(
                                      Icons.arrow_back,
                                      color: Colors.white,
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  const Expanded(
                                    child: Text(
                                      'إنشاء حساب مستخدم',
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
                                hint: 'مثال: علي أحمد',
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
                              ImagePickerField(
                                title: 'صورة الزبون (اختياري)',
                                selectedFile: customerImageFile,
                                existingImageUrl: null,
                                onPick: () async {
                                  final picked = await pickImageFromDevice();
                                  if (!mounted || picked == null) return;
                                  setState(() => customerImageFile = picked);
                                },
                                onClear: customerImageFile == null
                                    ? null
                                    : () => setState(
                                        () => customerImageFile = null,
                                      ),
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
                                        FocusScope.of(context).unfocus();
                                        await ref
                                            .read(
                                              authControllerProvider.notifier,
                                            )
                                            .register({
                                              'fullName': fullNameCtrl.text,
                                              'phone': phoneCtrl.text,
                                              'pin': pinCtrl.text,
                                              'block': blockCtrl.text,
                                              'buildingNumber':
                                                  buildingCtrl.text,
                                              'apartment': aptCtrl.text,
                                            }, imageFile: customerImageFile);

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
                                    : const Text('إنشاء الحساب'),
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
