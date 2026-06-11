// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../data/services_api.dart';
import '../models/service_models.dart';

class ServiceRequestCreateScreen extends ConsumerStatefulWidget {
  final ServiceOfferingModel offering;

  const ServiceRequestCreateScreen({super.key, required this.offering});

  @override
  ConsumerState<ServiceRequestCreateScreen> createState() =>
      _ServiceRequestCreateScreenState();
}

class _ServiceRequestCreateScreenState
    extends ConsumerState<ServiceRequestCreateScreen> {
  DateTime? _date;
  TimeOfDay? _time;
  final _quantityCtrl = TextEditingController();
  final _durationCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final List<LocalImageFile> _attachments = <LocalImageFile>[];
  int? _pricingOptionId;
  bool _requiresHomeService = false;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    ServicePricingOptionModel? defaultPricing;
    for (final item in widget.offering.pricingOptions) {
      if (item.isDefault) {
        defaultPricing = item;
        break;
      }
    }
    defaultPricing ??= widget.offering.pricingOptions.isNotEmpty
        ? widget.offering.pricingOptions.first
        : null;
    _pricingOptionId = defaultPricing?.id;
    _requiresHomeService =
        widget.offering.executionMode == 'home' ||
        widget.offering.executionMode == 'both';
  }

  @override
  void dispose() {
    _quantityCtrl.dispose();
    _durationCtrl.dispose();
    _notesCtrl.dispose();
    _cityCtrl.dispose();
    _areaCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 180)),
    );
    if (picked == null || !mounted) return;
    setState(() => _date = picked);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (picked == null || !mounted) return;
    setState(() => _time = picked);
  }

  Future<void> _addAttachment() async {
    final file = await pickImageFromDevice();
    if (file == null || !mounted) return;
    setState(() {
      _attachments.add(file);
      _error = null;
    });
  }

  Future<void> _submit() async {
    if (_loading) return;
    if (_date == null) {
      setState(() => _error = 'يرجى تحديد التاريخ');
      return;
    }
    if (_time == null) {
      setState(() => _error = 'يرجى تحديد الوقت');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final dateText =
          '${_date!.year.toString().padLeft(4, '0')}-${_date!.month.toString().padLeft(2, '0')}-${_date!.day.toString().padLeft(2, '0')}';
      final timeText =
          '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}';

      await ref.read(servicesApiProvider).createServiceRequest({
        'offeringId': widget.offering.id,
        'providerId': widget.offering.providerId,
        if ((_pricingOptionId ?? 0) > 0) 'pricingOptionId': _pricingOptionId,
        'requestedExecutionMode': _requiresHomeService
            ? 'home'
            : 'provider_location',
        'requestedDate': dateText,
        'requestedTime': timeText,
        if (_quantityCtrl.text.trim().isNotEmpty)
          'quantity': double.tryParse(_quantityCtrl.text.trim()),
        if (_durationCtrl.text.trim().isNotEmpty)
          'durationHours': double.tryParse(_durationCtrl.text.trim()),
        if (_notesCtrl.text.trim().isNotEmpty) 'notes': _notesCtrl.text.trim(),
        if (_cityCtrl.text.trim().isNotEmpty) 'city': _cityCtrl.text.trim(),
        if (_areaCtrl.text.trim().isNotEmpty) 'area': _areaCtrl.text.trim(),
        if (_addressCtrl.text.trim().isNotEmpty)
          'addressLine': _addressCtrl.text.trim(),
        'requiresHomeService': _requiresHomeService,
        'requiresQuote':
            widget.offering.inspectionRequired ||
            widget.offering.customQuoteOnly,
      }, attachmentFiles: _attachments);

      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب الخدمة بنجاح')),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final servicesSection = ref
        .watch(sectionAvailabilityControllerProvider)
        .entryFor(AppSectionKeys.services, displayName: 'الخدمات');
    if (servicesSection.isBlocked) {
      return SectionUnavailableScreen(entry: servicesSection);
    }
    final pricing = widget.offering.pricingOptions;
    return Scaffold(
      appBar: AppBar(title: const Text('طلب خدمة')),
      body: ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Text(
            widget.offering.name,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 4),
          Text(widget.offering.provider.businessName ?? ''),
          const SizedBox(height: 10),
          if (_error != null)
            Card(
              color: Colors.red.withValues(alpha: 0.12),
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickDate,
                  icon: const Icon(Icons.calendar_today_outlined),
                  label: Text(
                    _date == null
                        ? 'اختر التاريخ'
                        : '${_date!.year}-${_date!.month}-${_date!.day}',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _pickTime,
                  icon: const Icon(Icons.access_time_outlined),
                  label: Text(
                    _time == null
                        ? 'اختر الوقت'
                        : '${_time!.hour.toString().padLeft(2, '0')}:${_time!.minute.toString().padLeft(2, '0')}',
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (pricing.isNotEmpty)
            DropdownButtonFormField<int>(
              value: _pricingOptionId,
              decoration: const InputDecoration(labelText: 'خيار التسعير'),
              items: pricing
                  .map(
                    (item) => DropdownMenuItem<int>(
                      value: item.id,
                      child: Text(item.displayText()),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() => _pricingOptionId = value),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _quantityCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'الكمية / الوحدات',
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _durationCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: const InputDecoration(labelText: 'عدد الساعات'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SwitchListTile(
            value: _requiresHomeService,
            onChanged: (value) => setState(() => _requiresHomeService = value),
            title: const Text('الخدمة منزلية'),
          ),
          TextField(
            controller: _cityCtrl,
            decoration: const InputDecoration(labelText: 'المدينة'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _areaCtrl,
            decoration: const InputDecoration(labelText: 'المنطقة'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _addressCtrl,
            decoration: const InputDecoration(
              labelText: 'العنوان التفصيلي (اختياري)',
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _notesCtrl,
            maxLines: 4,
            decoration: const InputDecoration(
              labelText: 'ملاحظات الطلب',
              hintText: 'اكتب تفاصيل إضافية تساعد مقدم الخدمة...',
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              OutlinedButton.icon(
                onPressed: _addAttachment,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('إضافة صورة'),
              ),
              const SizedBox(width: 8),
              Text('المرفقات: ${_attachments.length}'),
            ],
          ),
          if (_attachments.isNotEmpty) ...[
            const SizedBox(height: 8),
            SizedBox(
              height: 82,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _attachments.length,
                separatorBuilder: (_, _) => const SizedBox(width: 8),
                itemBuilder: (context, index) {
                  final item = _attachments[index];
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: item.hasBytes
                            ? Image.memory(
                                item.bytes!,
                                width: 82,
                                height: 82,
                                fit: BoxFit.cover,
                              )
                            : Container(
                                width: 82,
                                height: 82,
                                color: Colors.black12,
                                alignment: Alignment.center,
                                child: const Icon(Icons.image_outlined),
                              ),
                      ),
                      Positioned(
                        top: 0,
                        right: 0,
                        child: InkWell(
                          onTap: () {
                            setState(() => _attachments.removeAt(index));
                          },
                          child: Container(
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
            label: Text(widget.offering.bookingCta),
          ),
        ],
      ),
    );
  }
}
