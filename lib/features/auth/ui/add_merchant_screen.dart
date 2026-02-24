// ignore_for_file: use_build_context_synchronously

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/widgets/image_picker_field.dart';
import '../../admin/models/owner_account_model.dart';
import '../../admin/state/admin_controller.dart';
import '../../merchants/state/merchants_controller.dart';

enum _OwnerMode { existing, createNew }

class AddMerchantScreen extends ConsumerStatefulWidget {
  const AddMerchantScreen({super.key});

  @override
  ConsumerState<AddMerchantScreen> createState() => _AddMerchantScreenState();
}

class _AddMerchantScreenState extends ConsumerState<AddMerchantScreen> {
  final nameCtrl = TextEditingController();
  final descCtrl = TextEditingController();
  final phoneCtrl = TextEditingController();

  final ownerNameCtrl = TextEditingController();
  final ownerPhoneCtrl = TextEditingController();
  final ownerPinCtrl = TextEditingController();
  final ownerBlockCtrl = TextEditingController(text: 'A');
  final ownerBuildingCtrl = TextEditingController(text: '1');
  final ownerApartmentCtrl = TextEditingController(text: '1');

  String merchantType = 'restaurant';
  _OwnerMode ownerMode = _OwnerMode.existing;

  bool loadingOwners = false;
  bool saving = false;
  String? ownersError;
  List<OwnerAccountModel> owners = [];
  int? selectedOwnerId;

  LocalImageFile? merchantImageFile;
  LocalImageFile? ownerImageFile;

  @override
  void initState() {
    super.initState();
    Future.microtask(_loadOwners);
  }

  @override
  void dispose() {
    nameCtrl.dispose();
    descCtrl.dispose();
    phoneCtrl.dispose();
    ownerNameCtrl.dispose();
    ownerPhoneCtrl.dispose();
    ownerPinCtrl.dispose();
    ownerBlockCtrl.dispose();
    ownerBuildingCtrl.dispose();
    ownerApartmentCtrl.dispose();
    super.dispose();
  }

  bool _isValidPin(String pin) {
    final value = pin.trim();
    return RegExp(r'^\d{4,8}$').hasMatch(value);
  }

  Future<void> _loadOwners() async {
    setState(() {
      loadingOwners = true;
      ownersError = null;
    });

    try {
      final raw = await ref.read(adminApiProvider).availableOwners();
      final loaded = raw
          .map(
            (e) =>
                OwnerAccountModel.fromJson(Map<String, dynamic>.from(e as Map)),
          )
          .toList();

      if (!mounted) return;

      setState(() {
        owners = loaded;
        if (loaded.isEmpty) {
          ownerMode = _OwnerMode.createNew;
          selectedOwnerId = null;
        } else {
          selectedOwnerId ??= loaded.first.id;
        }
      });
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => ownersError = _mapApiError(e));
    } catch (_) {
      if (!mounted) return;
      setState(() => ownersError = 'تعذر تحميل حسابات أصحاب المتاجر');
    } finally {
      if (mounted) {
        setState(() => loadingOwners = false);
      }
    }
  }

  String _mapApiError(DioException e) {
    final data = e.response?.data;
    if (data is Map<String, dynamic>) {
      final message = data['message'];
      if (message == 'VALIDATION_ERROR') return 'تحقق من البيانات المدخلة';
      if (message == 'PHONE_EXISTS') return 'رقم الهاتف مستخدم مسبقًا';
      if (message == 'OWNER_NOT_FOUND') return 'حساب صاحب المتجر غير موجود';
      if (message == 'OWNER_ALREADY_HAS_MERCHANT') {
        return 'هذا الحساب مرتبط بمتجر مسبقًا';
      }
      if (message is String && message.isNotEmpty) return message;
    }
    return 'حدث خطأ أثناء تنفيذ العملية';
  }

  Future<void> _submit() async {
    final merchantName = nameCtrl.text.trim();
    if (merchantName.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('أدخل اسم المتجر')));
      return;
    }

    if (ownerMode == _OwnerMode.existing && selectedOwnerId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('اختر حساب صاحب متجر أو أنشئ حسابًا جديدًا'),
        ),
      );
      return;
    }

    if (ownerMode == _OwnerMode.createNew) {
      if (ownerNameCtrl.text.trim().isEmpty ||
          ownerPhoneCtrl.text.trim().isEmpty ||
          ownerBlockCtrl.text.trim().isEmpty ||
          ownerBuildingCtrl.text.trim().isEmpty ||
          ownerApartmentCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('أكمل بيانات حساب صاحب المتجر الجديد')),
        );
        return;
      }

      if (!_isValidPin(ownerPinCtrl.text)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('الـ PIN يجب أن يكون من 4 إلى 8 أرقام')),
        );
        return;
      }
    }

    setState(() => saving = true);

    try {
      await ref
          .read(merchantsControllerProvider.notifier)
          .addMerchant(
            name: merchantName,
            type: merchantType,
            description: descCtrl.text.trim(),
            phone: phoneCtrl.text.trim(),
            imageUrl: '',
            merchantImageFile: merchantImageFile,
            ownerImageFile: ownerMode == _OwnerMode.createNew
                ? ownerImageFile
                : null,
            ownerUserId: ownerMode == _OwnerMode.existing
                ? selectedOwnerId
                : null,
            ownerPayload: ownerMode == _OwnerMode.createNew
                ? {
                    'fullName': ownerNameCtrl.text.trim(),
                    'phone': ownerPhoneCtrl.text.trim(),
                    'pin': ownerPinCtrl.text.trim(),
                    'block': ownerBlockCtrl.text.trim(),
                    'buildingNumber': ownerBuildingCtrl.text.trim(),
                    'apartment': ownerApartmentCtrl.text.trim(),
                    'imageUrl': '',
                  }
                : null,
          );

      if (mounted) Navigator.of(context).pop(true);
    } on DioException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_mapApiError(e))));
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('فشل إنشاء المتجر')));
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إنشاء متجر')),
      body: SafeArea(
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _buildOwnerSection(),
              const SizedBox(height: 14),
              _buildMerchantSection(),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: saving ? null : _submit,
                  child: saving
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('حفظ المتجر'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOwnerSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'ربط حساب صاحب المتجر',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            SegmentedButton<_OwnerMode>(
              segments: const [
                ButtonSegment<_OwnerMode>(
                  value: _OwnerMode.existing,
                  label: Text('حساب موجود'),
                  icon: Icon(Icons.link),
                ),
                ButtonSegment<_OwnerMode>(
                  value: _OwnerMode.createNew,
                  label: Text('حساب جديد'),
                  icon: Icon(Icons.person_add_alt_1),
                ),
              ],
              selected: {ownerMode},
              onSelectionChanged: (selection) {
                if (selection.isNotEmpty) {
                  setState(() => ownerMode = selection.first);
                }
              },
            ),
            const SizedBox(height: 12),
            if (ownerMode == _OwnerMode.existing) ...[
              if (loadingOwners)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (ownersError != null)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(ownersError!, style: const TextStyle(color: Colors.red)),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _loadOwners,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة التحميل'),
                    ),
                  ],
                )
              else if (owners.isEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('لا يوجد صاحب متجر متاح حاليًا للربط'),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => setState(
                        () => ownerMode = _OwnerMode.createNew,
                      ),
                      child: const Text('إنشاء صاحب متجر جديد'),
                    ),
                  ],
                )
              else
                DropdownButtonFormField<int>(
                  key: ValueKey(selectedOwnerId),
                  initialValue: selectedOwnerId,
                  items: owners
                      .map(
                        (o) => DropdownMenuItem<int>(
                          value: o.id,
                          child: Text('${o.fullName} - ${o.phone}'),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => setState(() => selectedOwnerId = v),
                  decoration: InputDecoration(
                    labelText: 'حساب صاحب المتجر',
                    suffixIcon: IconButton(
                      onPressed: _loadOwners,
                      icon: const Icon(Icons.refresh),
                      tooltip: 'تحديث',
                    ),
                  ),
                ),
            ],
            if (ownerMode == _OwnerMode.createNew) ...[
              TextField(
                controller: ownerNameCtrl,
                decoration: const InputDecoration(labelText: 'اسم صاحب المتجر'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ownerPhoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'رقم هاتف صاحب المتجر',
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: ownerPinCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'PIN'),
                obscureText: true,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: ownerBlockCtrl,
                      decoration: const InputDecoration(labelText: 'البلوك'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ownerBuildingCtrl,
                      decoration: const InputDecoration(labelText: 'العمارة'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: ownerApartmentCtrl,
                      decoration: const InputDecoration(labelText: 'الشقة'),
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
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMerchantSection() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'بيانات المتجر',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم المتجر'),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: merchantType,
              items: const [
                DropdownMenuItem(value: 'restaurant', child: Text('مطعم')),
                DropdownMenuItem(value: 'market', child: Text('سوق')),
              ],
              onChanged: (v) => setState(() => merchantType = v ?? 'restaurant'),
              decoration: const InputDecoration(labelText: 'النوع'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: descCtrl,
              decoration: const InputDecoration(labelText: 'الوصف'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'هاتف المتجر (اختياري)',
                hintText: 'إذا تُرك فارغًا سيتم استخدام هاتف صاحب المتجر',
              ),
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
                  : () => setState(() => merchantImageFile = null),
            ),
          ],
        ),
      ),
    );
  }
}

