// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../state/auth_controller.dart';

class OwnerRegisterScreen extends ConsumerStatefulWidget {
  const OwnerRegisterScreen({super.key});

  @override
  ConsumerState<OwnerRegisterScreen> createState() =>
      _OwnerRegisterScreenState();
}

class _OwnerRegisterScreenState extends ConsumerState<OwnerRegisterScreen> {
  final fullNameCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();
  final pinCtrl = TextEditingController();
  final blockCtrl = TextEditingController();
  final buildingCtrl = TextEditingController();
  final aptCtrl = TextEditingController();

  final merchantNameCtrl = TextEditingController();
  final merchantDescCtrl = TextEditingController();
  final merchantPhoneCtrl = TextEditingController();

  String merchantType = 'restaurant';
  LocalImageFile? ownerImageFile;
  LocalImageFile? merchantImageFile;

  @override
  void dispose() {
    fullNameCtrl.dispose();
    phoneCtrl.dispose();
    pinCtrl.dispose();
    blockCtrl.dispose();
    buildingCtrl.dispose();
    aptCtrl.dispose();
    merchantNameCtrl.dispose();
    merchantDescCtrl.dispose();
    merchantPhoneCtrl.dispose();
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
              constraints: const BoxConstraints(maxWidth: 560),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white.withOpacity(0.18)),
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
                                  const SizedBox(width: 4),
                                  const Expanded(
                                    child: Text(
                                      'إنشاء حساب صاحب متجر',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 20,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              const Text(
                                'بيانات الحساب',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _Field(
                                controller: fullNameCtrl,
                                label: 'الاسم الكامل',
                                hint: 'مثال: أحمد علي',
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
                                title: 'صورة صاحب المتجر (اختياري)',
                                selectedFile: ownerImageFile,
                                existingImageUrl: null,
                                onPick: () async {
                                  final picked = await pickImageFromDevice();
                                  if (!mounted || picked == null) return;
                                  setState(() => ownerImageFile = picked);
                                },
                                onClear: ownerImageFile == null
                                    ? null
                                    : () => setState(() => ownerImageFile = null),
                              ),
                              const SizedBox(height: 14),
                              const Text(
                                'بيانات المتجر',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 8),
                              _Field(
                                controller: merchantNameCtrl,
                                label: 'اسم المتجر',
                                hint: 'مثال: مطعم البيت العراقي',
                              ),
                              const SizedBox(height: 10),
                              DropdownButtonFormField<String>(
                                initialValue: merchantType,
                                items: const [
                                  DropdownMenuItem(
                                    value: 'restaurant',
                                    child: Text('مطعم'),
                                  ),
                                  DropdownMenuItem(
                                    value: 'market',
                                    child: Text('سوق'),
                                  ),
                                ],
                                onChanged: (v) => setState(
                                  () => merchantType = v ?? 'restaurant',
                                ),
                                decoration: const InputDecoration(
                                  labelText: 'نوع المتجر',
                                ),
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                controller: merchantDescCtrl,
                                label: 'وصف المتجر',
                                hint: 'وصف مختصر',
                              ),
                              const SizedBox(height: 10),
                              _Field(
                                controller: merchantPhoneCtrl,
                                label: 'هاتف المتجر',
                                hint: 'اختياري - يفضل تعبئته',
                                keyboardType: TextInputType.phone,
                              ),
                              const SizedBox(height: 10),
                              ImagePickerField(
                                title: 'صورة المتجر (اختياري)',
                                selectedFile: merchantImageFile,
                                existingImageUrl: null,
                                onPick: () async {
                                  final picked = await pickImageFromDevice();
                                  if (!mounted || picked == null) return;
                                  setState(() => merchantImageFile = picked);
                                },
                                onClear: merchantImageFile == null
                                    ? null
                                    : () =>
                                        setState(() => merchantImageFile = null),
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
                                            .read(authControllerProvider.notifier)
                                            .registerOwner(
                                              {
                                                'fullName': fullNameCtrl.text,
                                                'phone': phoneCtrl.text,
                                                'pin': pinCtrl.text,
                                                'block': blockCtrl.text,
                                                'buildingNumber':
                                                    buildingCtrl.text,
                                                'apartment': aptCtrl.text,
                                                'merchantName':
                                                    merchantNameCtrl.text,
                                                'merchantType': merchantType,
                                                'merchantDescription':
                                                    merchantDescCtrl.text,
                                                'merchantPhone':
                                                    merchantPhoneCtrl.text.isEmpty
                                                    ? phoneCtrl.text
                                                    : merchantPhoneCtrl.text,
                                                'merchantImageUrl': '',
                                              },
                                              ownerImageFile: ownerImageFile,
                                              merchantImageFile:
                                                  merchantImageFile,
                                            );

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
                                    : const Text('إنشاء حساب صاحب متجر'),
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
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: TextStyle(color: Colors.white.withOpacity(0.55)),
        labelStyle: TextStyle(color: Colors.white.withOpacity(0.85)),
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

