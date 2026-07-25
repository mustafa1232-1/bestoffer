import 'package:core_design_system/core_design_system.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/i18n/locale_text.dart';
import '../../../core/network/api_error_mapper.dart';
import '../state/admin_controller.dart';
import 'package:dio/dio.dart';

/// إعدادات رقم الدعم المركزي (المرحلة 8). تحديث يصل كل التطبيقات دون تحديث
/// التطبيق. الفرض والتحقق في الخادم.
class AdminSupportSettingsScreen extends ConsumerStatefulWidget {
  const AdminSupportSettingsScreen({super.key});

  @override
  ConsumerState<AdminSupportSettingsScreen> createState() =>
      _AdminSupportSettingsScreenState();
}

class _AdminSupportSettingsScreenState
    extends ConsumerState<AdminSupportSettingsScreen> {
  final _e164 = TextEditingController();
  final _display = TextEditingController();
  final _whatsapp = TextEditingController();
  final _hours = TextEditingController();
  final _emergency = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _e164.dispose();
    _display.dispose();
    _whatsapp.dispose();
    _hours.dispose();
    _emergency.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(adminApiProvider).getSupportContact();
      if (!mounted) return;
      _e164.text = '${data['supportPhoneE164'] ?? ''}';
      _display.text = '${data['supportPhoneDisplay'] ?? ''}';
      _whatsapp.text = '${data['supportWhatsApp'] ?? ''}';
      _hours.text = '${data['supportWorkingHours'] ?? ''}';
      _emergency.text = '${data['supportEmergencyPhone'] ?? ''}';
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.lt(
            ar: 'تعذّر تحميل إعدادات الدعم.',
            en: 'Unable to load support settings.',
          ));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _success = null;
    });
    try {
      await ref.read(adminApiProvider).updateSupportContact({
        'supportPhoneE164': _e164.text.trim(),
        'supportPhoneDisplay': _display.text.trim(),
        'supportWhatsApp': _whatsapp.text.trim(),
        'supportWorkingHours': _hours.text.trim(),
        'supportEmergencyPhone': _emergency.text.trim(),
      });
      if (!mounted) return;
      setState(() => _success = context.lt(
            ar: 'تم حفظ رقم الدعم. سيصل كل التطبيقات.',
            en: 'Support contact saved. It reaches all apps.',
          ));
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() => _error = mapDioError(
            e,
            fallback: context.lt(
              ar: 'تعذّر حفظ الإعدادات.',
              en: 'Unable to save settings.',
            ),
          ));
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = context.lt(
            ar: 'تعذّر حفظ الإعدادات.',
            en: 'Unable to save settings.',
          ));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(context.lt(ar: 'رقم الدعم المركزي', en: 'Central support')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(MaslakiSpacing.md),
              children: [
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MaslakiSpacing.sm),
                    child: Text(
                      _error!,
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                  ),
                if (_success != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: MaslakiSpacing.sm),
                    child: Text(
                      _success!,
                      style: const TextStyle(color: Colors.green),
                    ),
                  ),
                _field(
                  _e164,
                  context.lt(ar: 'رقم الدعم (E164)', en: 'Support phone (E164)'),
                  hint: '+9647XXXXXXXXX',
                  keyboard: TextInputType.phone,
                ),
                _field(
                  _display,
                  context.lt(ar: 'الرقم كما يُعرض', en: 'Display number'),
                ),
                _field(
                  _whatsapp,
                  context.lt(ar: 'واتساب (E164)', en: 'WhatsApp (E164)'),
                  keyboard: TextInputType.phone,
                ),
                _field(
                  _hours,
                  context.lt(ar: 'ساعات العمل', en: 'Working hours'),
                ),
                _field(
                  _emergency,
                  context.lt(ar: 'رقم الطوارئ (E164)', en: 'Emergency phone (E164)'),
                  keyboard: TextInputType.phone,
                ),
                const SizedBox(height: MaslakiSpacing.md),
                FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.save_rounded),
                  label: Text(
                    _saving
                        ? context.lt(ar: 'جارٍ الحفظ…', en: 'Saving…')
                        : context.lt(ar: 'حفظ', en: 'Save'),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: MaslakiSpacing.sm),
      child: TextField(
        controller: controller,
        keyboardType: keyboard,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
