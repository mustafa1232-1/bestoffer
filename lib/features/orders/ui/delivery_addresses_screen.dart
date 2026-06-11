// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../auth/presentation/widgets/basmaya_address_selector.dart';
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
    final l10n = context.l10n;

    ref.listen<DeliveryAddressState>(deliveryAddressControllerProvider, (
      prev,
      next,
    ) {
      if (next.error != null &&
          next.error != prev?.error &&
          !(next.validationError?.hasAnyErrors ?? false)) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
    });

    return Scaffold(
      appBar: AppBar(title: Text(l10n.deliveryAddressesTitle)),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: null,
        onPressed: state.saving ? null : () => _openAddressForm(),
        icon: const Icon(Icons.add_location_alt_outlined),
        label: Text(l10n.deliveryAddressesAdd),
      ),
      body: RefreshIndicator(
        onRefresh: () =>
            ref.read(deliveryAddressControllerProvider.notifier).bootstrap(),
        child: state.loading
            ? const Center(child: CircularProgressIndicator())
            : state.addresses.isEmpty
                ? ListView(
                    children: [
                      const SizedBox(height: 180),
                      Center(child: Text(l10n.deliveryAddressesEmpty)),
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
                          title: Text(address.label),
                          subtitle: Text(address.shortText),
                          leading: Radio<int>(
                            value: address.id,
                            groupValue: state.selectedAddressId,
                            onChanged: (value) {
                              if (value == null) return;
                              ref
                                  .read(
                                    deliveryAddressControllerProvider.notifier,
                                  )
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
                                  tooltip: l10n.deliveryAddressesSetDefault,
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
                                tooltip: l10n.commonEdit,
                                onPressed: state.saving
                                    ? null
                                    : () => _openAddressForm(address: address),
                                icon: const Icon(Icons.edit_outlined),
                              ),
                              IconButton(
                                tooltip: l10n.commonDelete,
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
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(l10n.deliveryAddressesDeleteTitle),
        content: Text(l10n.deliveryAddressesDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.commonDelete),
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
  final _fieldErrors = <String, String>{};
  final _scrollCoordinator = FormScrollCoordinator();
  String? _formError;
  String? _addressError;
  String? selectedBlock;
  String? selectedBuilding;
  String? selectedApartment;
  late bool isDefault;
  bool _defaultsApplied = false;

  @override
  void initState() {
    super.initState();
    final address = widget.address;
    labelCtrl = TextEditingController(text: address?.label ?? '');
    cityCtrl = TextEditingController(text: address?.city ?? '');
    selectedBlock = address?.block;
    selectedBuilding = address?.buildingNumber;
    selectedApartment = address?.apartment;
    isDefault = address?.isDefault ?? false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_defaultsApplied || widget.address != null) return;
    _defaultsApplied = true;
    labelCtrl.text = context.l10n.deliveryAddressesDefaultLabel;
    cityCtrl.text = context.l10n.deliveryAddressesDefaultCity;
  }

  @override
  void dispose() {
    labelCtrl.dispose();
    cityCtrl.dispose();
    _scrollCoordinator.dispose();
    super.dispose();
  }

  String? _errorOf(String field) => _fieldErrors[field];

  String _fieldLabel(BuildContext context, String field) {
    final l10n = context.l10n;
    switch (field) {
      case 'label':
        return l10n.deliveryAddressesLabel;
      case 'city':
        return l10n.deliveryAddressesCity;
      case 'block':
        return l10n.basmayaSectorLabel;
      case 'buildingNumber':
        return l10n.basmayaBuildingLabel;
      case 'apartment':
        return l10n.basmayaApartmentLabel;
      default:
        return field;
    }
  }

  void _clearField(String field) {
    if (!_fieldErrors.containsKey(field) &&
        _formError == null &&
        _addressError == null) {
      return;
    }
    setState(() {
      _fieldErrors.remove(field);
      if (field == 'block' || field == 'buildingNumber' || field == 'apartment') {
        _addressError = null;
      }
      _formError = null;
    });
  }

  bool _validate() {
    final next = <String, String>{};
    final l10n = context.l10n;
    if (labelCtrl.text.trim().isEmpty) {
      next['label'] = resolveFormFieldError(
        l10n: l10n,
        field: 'label',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'label'),
      );
    }
    if (cityCtrl.text.trim().isEmpty) {
      next['city'] = resolveFormFieldError(
        l10n: l10n,
        field: 'city',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'city'),
      );
    }
    if ((selectedBlock ?? '').trim().isEmpty) {
      next['block'] = resolveFormFieldError(
        l10n: l10n,
        field: 'block',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'block'),
      );
    }
    if ((selectedBuilding ?? '').trim().isEmpty) {
      next['buildingNumber'] = resolveFormFieldError(
        l10n: l10n,
        field: 'buildingNumber',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'buildingNumber'),
      );
    }
    if ((selectedApartment ?? '').trim().isEmpty) {
      next['apartment'] = resolveFormFieldError(
        l10n: l10n,
        field: 'apartment',
        code: 'REQUIRED',
        fieldLabel: _fieldLabel(context, 'apartment'),
      );
    }

    final nextAddressError = next.containsKey('block') ||
            next.containsKey('buildingNumber') ||
            next.containsKey('apartment')
        ? null
        : BasmayaAddressCatalog.validateSelection(
            block: selectedBlock,
            buildingNumber: selectedBuilding,
            apartment: selectedApartment,
            l10n: l10n,
          );

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(next);
      _addressError = nextAddressError;
      _formError = next.isEmpty && nextAddressError == null
          ? null
          : l10n.validationReviewRequiredFields;
    });

    return next.isEmpty && nextAddressError == null;
  }

  Future<void> _focusFirstError() async {
    final fields = <String>[
      if (_errorOf('label') != null) 'label',
      if (_errorOf('city') != null) 'city',
      if (_errorOf('block') != null) 'block',
      if (_errorOf('buildingNumber') != null) 'buildingNumber',
      if (_errorOf('apartment') != null) 'apartment',
    ];
    await _scrollCoordinator.focusFirstError(fields);
  }

  Future<bool> _applyBackendErrors() async {
    final state = ref.read(deliveryAddressControllerProvider);
    final parsed = state.validationError;
    if (parsed == null || !parsed.hasAnyErrors) return false;

    final next = <String, String>{};
    for (final entry in parsed.fieldCodes.entries) {
      next[entry.key] = resolveFormFieldError(
        l10n: context.l10n,
        field: entry.key,
        code: entry.value,
        fieldLabel: _fieldLabel(context, entry.key),
      );
    }

    setState(() {
      _fieldErrors
        ..clear()
        ..addAll(next);
      _addressError = parsed.formCode == 'ADDRESS_INVALID'
          ? resolveFormLevelError(context.l10n, code: parsed.formCode)
          : null;
      _formError = next.isNotEmpty
          ? context.l10n.validationReviewRequiredFields
          : resolveFormLevelError(
              context.l10n,
              code: parsed.formCode ?? parsed.messageCode,
              fallback: state.error,
            );
    });
    await _focusFirstError();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final saving = ref.watch(
      deliveryAddressControllerProvider.select((s) => s.saving),
    );
    final isEdit = widget.address != null;
    final l10n = context.l10n;

    Widget buildTextField({
      required String field,
      required TextEditingController controller,
      required String label,
      TextInputType keyboardType = TextInputType.text,
      TextDirection? textDirection,
    }) {
      return _scrollCoordinator.anchor(
        field,
        TextField(
          controller: controller,
          focusNode: _scrollCoordinator.focusNodeFor(field),
          keyboardType: keyboardType,
          textDirection: textDirection,
          onChanged: (_) => _clearField(field),
          decoration: InputDecoration(
            labelText: label,
            errorText: _errorOf(field),
          ),
        ),
      );
    }

    return Padding(
      padding: EdgeInsets.only(
        left: 14,
        right: 14,
        top: 14,
        bottom: MediaQuery.of(context).viewInsets.bottom + 14,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              isEdit
                  ? l10n.deliveryAddressesEditTitle
                  : l10n.deliveryAddressesAddTitle,
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
            ),
            const SizedBox(height: 12),
            FormErrorBanner(message: _formError),
            buildTextField(
              field: 'label',
              controller: labelCtrl,
              label: l10n.deliveryAddressesLabel,
            ),
            const SizedBox(height: 10),
            buildTextField(
              field: 'city',
              controller: cityCtrl,
              label: l10n.deliveryAddressesCity,
            ),
            const SizedBox(height: 10),
            _scrollCoordinator.anchor(
              'block',
              BasmayaAddressSelector(
                selectedBlock: selectedBlock,
                selectedBuilding: selectedBuilding,
                selectedApartment: selectedApartment,
                enabled: !saving,
                blockError: _errorOf('block'),
                buildingError: _errorOf('buildingNumber'),
                apartmentError: _errorOf('apartment'),
                generalError: _addressError,
                onBlockChanged: (value) {
                  setState(() {
                    selectedBlock = value;
                    final buildings = BasmayaAddressCatalog.buildingOptionsForBlock(
                      value,
                    );
                    if (!buildings.contains(selectedBuilding)) {
                      selectedBuilding = null;
                    }
                    selectedApartment = null;
                    _fieldErrors.remove('block');
                    _fieldErrors.remove('buildingNumber');
                    _fieldErrors.remove('apartment');
                    _addressError = null;
                    _formError = null;
                  });
                },
                onBuildingChanged: (value) {
                  setState(() {
                    selectedBuilding = value;
                    selectedApartment = null;
                    _fieldErrors.remove('buildingNumber');
                    _fieldErrors.remove('apartment');
                    _addressError = null;
                    _formError = null;
                  });
                },
                onApartmentChanged: (value) {
                  setState(() {
                    selectedApartment = value;
                    _fieldErrors.remove('apartment');
                    _addressError = null;
                    _formError = null;
                  });
                },
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: isDefault,
              onChanged: (value) => setState(() => isDefault = value),
              title: Text(l10n.deliveryAddressesDefaultSwitch),
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
                    : Text(
                        isEdit
                            ? l10n.deliveryAddressesSaveEdit
                            : l10n.deliveryAddressesSaveNew,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_validate()) {
      await _focusFirstError();
      return;
    }

    final controller = ref.read(deliveryAddressControllerProvider.notifier);
    if (widget.address == null) {
      await controller.createAddress(
        label: labelCtrl.text,
        city: cityCtrl.text,
        block: selectedBlock!,
        buildingNumber: selectedBuilding!,
        apartment: selectedApartment!,
        isDefault: isDefault,
      );
    } else {
      await controller.updateAddress(
        addressId: widget.address!.id,
        label: labelCtrl.text,
        city: cityCtrl.text,
        block: selectedBlock!,
        buildingNumber: selectedBuilding!,
        apartment: selectedApartment!,
        isDefault: isDefault,
      );
    }

    if (!mounted) return;
    if (await _applyBackendErrors()) {
      return;
    }
    if (!mounted) return;

    final error = ref.read(deliveryAddressControllerProvider).error;
    if (error == null) {
      Navigator.of(context).pop();
    } else {
      setState(() => _formError = error);
    }
  }
}
