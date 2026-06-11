import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/app_localizations_context.dart';
import '../state/admin_controller.dart';

class AdminCreateUserScreen extends ConsumerStatefulWidget {
  const AdminCreateUserScreen({super.key});

  @override
  ConsumerState<AdminCreateUserScreen> createState() =>
      _AdminCreateUserScreenState();
}

class _AdminCreateUserScreenState extends ConsumerState<AdminCreateUserScreen> {
  final _formKey = GlobalKey<FormState>();
  final _fullNameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _pinCtrl = TextEditingController();
  final _blockCtrl = TextEditingController(text: 'A');
  final _buildingCtrl = TextEditingController();
  final _apartmentCtrl = TextEditingController();

  String _role = 'user';
  String _driverType = 'app_driver';
  int? _merchantId;

  bool get _showMerchantField =>
      _role == 'delivery' || _role == 'accountant' || _role == 'hr';

  bool get _merchantRequired =>
      _role == 'accountant' ||
      _role == 'hr' ||
      (_role == 'delivery' && _driverType == 'store_driver');

  @override
  void dispose() {
    _fullNameCtrl.dispose();
    _phoneCtrl.dispose();
    _pinCtrl.dispose();
    _blockCtrl.dispose();
    _buildingCtrl.dispose();
    _apartmentCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final body = <String, dynamic>{
      'fullName': _fullNameCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'pin': _pinCtrl.text.trim(),
      'block': _blockCtrl.text.trim(),
      'buildingNumber': _buildingCtrl.text.trim(),
      'apartment': _apartmentCtrl.text.trim(),
      'role': _role,
      if (_role == 'delivery') 'driverType': _driverType,
      if (_showMerchantField && _merchantId != null) 'merchantId': _merchantId,
    };
    await ref.read(adminControllerProvider.notifier).createUser(body);
    final next = ref.read(adminControllerProvider);
    if (!mounted) return;
    if (next.error == null) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);
    final merchants = state.managedMerchants;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminCreateUserTitle),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.error != null)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Theme.of(
                      context,
                    ).colorScheme.error.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text(state.error!),
                ),
              TextFormField(
                controller: _fullNameCtrl,
                decoration: InputDecoration(
                  labelText: l10n.adminCreateUserFullName,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.adminCreateUserNameRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _phoneCtrl,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(
                  labelText: l10n.authPhoneLabel,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.adminCreateUserPhoneRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _pinCtrl,
                keyboardType: TextInputType.number,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.authPinLabel,
                ),
                validator: (value) {
                  final pin = (value ?? '').trim();
                  if (pin.isEmpty) {
                    return l10n.adminCreateUserPinRequired;
                  }
                  if (!RegExp(r'^\d{4,8}$').hasMatch(pin)) {
                    return l10n.authPinInvalidFormat;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: _role,
                decoration: InputDecoration(
                  labelText: l10n.adminCreateUserRole,
                ),
                items: [
                  DropdownMenuItem(
                    value: 'user',
                    child: Text(l10n.adminCreateUserCustomerRole),
                  ),
                  DropdownMenuItem(
                    value: 'owner',
                    child: Text(l10n.adminCreateUserOwnerRole),
                  ),
                  DropdownMenuItem(
                    value: 'delivery',
                    child: Text(l10n.adminCreateUserDeliveryRole),
                  ),
                  DropdownMenuItem(
                    value: 'accountant',
                    child: Text(l10n.adminCreateUserAccountantRole),
                  ),
                  DropdownMenuItem(
                    value: 'hr',
                    child: Text(l10n.adminCreateUserHrRole),
                  ),
                  DropdownMenuItem(
                    value: 'deputy_admin',
                    child: Text(l10n.adminCreateUserDeputyAdminRole),
                  ),
                  DropdownMenuItem(
                    value: 'call_center',
                    child: Text(l10n.adminCreateUserCallCenterRole),
                  ),
                  DropdownMenuItem(
                    value: 'admin',
                    child: Text(l10n.adminCreateUserAdminRole),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _role = value ?? 'user';
                    if (_role != 'delivery') {
                      _driverType = 'app_driver';
                    }
                    if (!_showMerchantField) _merchantId = null;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_role == 'delivery')
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<String>(
                    initialValue: _driverType,
                    decoration: InputDecoration(
                      labelText: l10n.adminCreateUserDriverType,
                      helperText: _driverType == 'store_driver'
                          ? l10n.adminCreateUserStoreDriverHelper
                          : l10n.adminCreateUserAppDriverHelper,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'app_driver',
                        child: Text(l10n.adminCreateUserAppDriver),
                      ),
                      DropdownMenuItem(
                        value: 'store_driver',
                        child: Text(l10n.adminCreateUserStoreDriver),
                      ),
                    ],
                    onChanged: (value) {
                      setState(() {
                        _driverType = value ?? 'app_driver';
                      });
                    },
                    validator: (value) {
                      if (_role == 'delivery' &&
                          value != 'app_driver' &&
                          value != 'store_driver') {
                        return l10n.adminCreateUserDriverTypeRequired;
                      }
                      return null;
                    },
                  ),
                ),
              if (_showMerchantField)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: DropdownButtonFormField<int>(
                    initialValue: _merchantId,
                    decoration: InputDecoration(
                      labelText: _merchantRequired
                          ? l10n.adminCreateUserAssignedMerchant
                          : l10n.adminCreateUserAssignedMerchantOptional,
                      helperText: _role == 'delivery' && !_merchantRequired
                          ? l10n.adminCreateUserMerchantOptionalHelper
                          : null,
                    ),
                    items: merchants
                        .map(
                          (item) => DropdownMenuItem<int>(
                            value: item.id,
                            child: Text(item.name),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) => setState(() => _merchantId = value),
                    validator: (value) {
                      if (_merchantRequired && value == null) {
                        return l10n.adminCreateUserMerchantRequired;
                      }
                      return null;
                    },
                  ),
                ),
              TextFormField(
                controller: _blockCtrl,
                decoration: InputDecoration(
                  labelText: l10n.companyBranchRequestOwnerBlock,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.adminCreateUserBlockRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _buildingCtrl,
                decoration: InputDecoration(
                  labelText: l10n.adminCreateUserBuildingNumber,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.adminCreateUserBuildingRequired
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _apartmentCtrl,
                decoration: InputDecoration(
                  labelText: l10n.companyBranchRequestOwnerApartment,
                ),
                validator: (value) => (value ?? '').trim().isEmpty
                    ? l10n.adminCreateUserApartmentRequired
                    : null,
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: state.saving ? null : _submit,
                icon: state.saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.person_add_alt_1_rounded),
                label: Text(
                  l10n.adminCreateUserCreateButton,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
