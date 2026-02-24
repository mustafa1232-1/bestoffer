// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/delivery_address_model.dart';
import '../state/delivery_address_controller.dart';

class DeliveryAddressesScreen extends ConsumerStatefulWidget {
  final bool selectOnTap;

  const DeliveryAddressesScreen({super.key, this.selectOnTap = false});

  @override
  ConsumerState<DeliveryAddressesScreen> createState() =>
      _DeliveryAddressesScreenState();
}

class _DeliveryAddressesScreenState
    extends ConsumerState<DeliveryAddressesScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(deliveryAddressControllerProvider.notifier).bootstrap(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(deliveryAddressControllerProvider);

    ref.listen<DeliveryAddressState>(deliveryAddressControllerProvider, (
      prev,
      next,
    ) {
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: const Text('عناوين التوصيل')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: state.saving ? null : () => _openAddressForm(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: const Text('إضافة عنوان'),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(deliveryAddressControllerProvider.notifier).bootstrap(),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.addresses.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 180),
                  Center(child: Text('لا توجد عناوين توصيل')),
                ],
              )
            : ListView.builder(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
                itemCount: state.addresses.length,
                itemBuilder: (context, index) {
                  final address = state.addresses[index];
                  final selected = state.selectedAddressId == address.id;
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: ListTile(
                      onTap: () {
                        ref
                            .read(deliveryAddressControllerProvider.notifier)
                            .selectAddress(address.id);
                        if (widget.selectOnTap) {
                          Navigator.of(context).pop(true);
                        }
                      },
                      title: Text(
                        address.label,
                        textDirection: TextDirection.rtl,
                      ),
                      subtitle: Text(
                        address.shortText,
                        textDirection: TextDirection.rtl,
                      ),
                      leading: Radio<int>(
                        value: address.id,
                        groupValue: state.selectedAddressId,
                        onChanged: (value) {
                          if (value == null) return;
                          ref
                              .read(deliveryAddressControllerProvider.notifier)
                              .selectAddress(value);
                          if (widget.selectOnTap) {
                            Navigator.of(context).pop(true);
                          }
                        },
                      ),
                      trailing: Wrap(
                        spacing: 2,
                        children: [
                          if (!address.isDefault)
                            IconButton(
                              tooltip: 'افتراضي',
                              onPressed: state.saving
                                  ? null
                                  : () => ref
                                        .read(
                                          deliveryAddressControllerProvider
                                              .notifier,
                                        )
                                        .setDefaultAddress(address.id),
                              icon: const Icon(Icons.star_outline_rounded),
                            ),
                          IconButton(
                            tooltip: 'تعديل',
                            onPressed: state.saving
                                ? null
                                : () => _openAddressForm(address: address),
                            icon: const Icon(Icons.edit_outlined),
                          ),
                          IconButton(
                            tooltip: 'حذف',
                            onPressed: state.saving
                                ? null
                                : () => _confirmDelete(address.id),
                            icon: const Icon(Icons.delete_outline),
                          ),
                          if (selected)
                            const Padding(
                              padding: EdgeInsetsDirectional.only(start: 4),
                              child: Icon(
                                Icons.check_circle,
                                color: Colors.green,
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }

  Future<void> _confirmDelete(int addressId) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('حذف العنوان'),
        content: const Text('هل تريد حذف عنوان التوصيل هذا؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('حذف'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref
        .read(deliveryAddressControllerProvider.notifier)
        .deleteAddress(addressId);
  }

  Future<void> _openAddressForm({DeliveryAddressModel? address}) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _AddressFormSheet(address: address),
    );
  }
}

class _AddressFormSheet extends ConsumerStatefulWidget {
  final DeliveryAddressModel? address;

  const _AddressFormSheet({this.address});

  @override
  ConsumerState<_AddressFormSheet> createState() => _AddressFormSheetState();
}

class _AddressFormSheetState extends ConsumerState<_AddressFormSheet> {
  late final TextEditingController labelCtrl;
  late final TextEditingController cityCtrl;
  late final TextEditingController blockCtrl;
  late final TextEditingController buildingCtrl;
  late final TextEditingController apartmentCtrl;
  late bool isDefault;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    labelCtrl = TextEditingController(text: address?.label ?? 'المنزل');
    cityCtrl = TextEditingController(text: address?.city ?? 'مدينة بسماية');
    blockCtrl = TextEditingController(text: address?.block ?? '');
    buildingCtrl = TextEditingController(text: address?.buildingNumber ?? '');
    apartmentCtrl = TextEditingController(text: address?.apartment ?? '');
    isDefault = address?.isDefault ?? false;
  }

  @override
  void dispose() {
    labelCtrl.dispose();
    cityCtrl.dispose();
    blockCtrl.dispose();
    buildingCtrl.dispose();
    apartmentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(
      deliveryAddressControllerProvider.select((s) => s.saving),
    );
    final isEdit = widget.address != null;

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isEdit ? 'تعديل عنوان التوصيل' : 'إضافة عنوان توصيل',
                style: const TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(labelText: 'اسم العنوان'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: cityCtrl,
                decoration: const InputDecoration(labelText: 'المدينة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: blockCtrl,
                decoration: const InputDecoration(labelText: 'البلوك'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: buildingCtrl,
                decoration: const InputDecoration(labelText: 'العمارة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: apartmentCtrl,
                decoration: const InputDecoration(labelText: 'الشقة'),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: isDefault,
                onChanged: (value) => setState(() => isDefault = value),
                title: const Text('تعيين كعنوان افتراضي'),
              ),
              const SizedBox(height: 10),
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
                      : Text(isEdit ? 'حفظ التعديلات' : 'إضافة العنوان'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (labelCtrl.text.trim().isEmpty ||
        blockCtrl.text.trim().isEmpty ||
        buildingCtrl.text.trim().isEmpty ||
        apartmentCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('الرجاء إكمال بيانات العنوان')),
      );
      return;
    }

    final controller = ref.read(deliveryAddressControllerProvider.notifier);
    if (widget.address == null) {
      await controller.createAddress(
        label: labelCtrl.text,
        city: cityCtrl.text,
        block: blockCtrl.text,
        buildingNumber: buildingCtrl.text,
        apartment: apartmentCtrl.text,
        isDefault: isDefault,
      );
    } else {
      await controller.updateAddress(
        addressId: widget.address!.id,
        label: labelCtrl.text,
        city: cityCtrl.text,
        block: blockCtrl.text,
        buildingNumber: buildingCtrl.text,
        apartment: apartmentCtrl.text,
        isDefault: isDefault,
      );
    }

    if (!mounted) return;
    final error = ref.read(deliveryAddressControllerProvider).error;
    if (error == null) {
      Navigator.of(context).pop();
    }
  }
}
