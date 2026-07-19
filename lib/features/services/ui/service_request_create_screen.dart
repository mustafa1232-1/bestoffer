// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:math';

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
  final _random = Random();
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
  bool _previewLoading = false;
  String? _previewError;
  ServiceBookingPreviewModel? _preview;
  Timer? _previewDebounce;
  late final String _idempotencyKey;
  int _previewGeneration = 0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'svc-booking-${DateTime.now().microsecondsSinceEpoch}-${_random.nextInt(1 << 32)}';
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
    _quantityCtrl.addListener(_schedulePreview);
    _durationCtrl.addListener(_schedulePreview);
    _notesCtrl.addListener(_schedulePreview);
    _cityCtrl.addListener(_schedulePreview);
    _areaCtrl.addListener(_schedulePreview);
    _addressCtrl.addListener(_schedulePreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _schedulePreview(force: true);
      }
    });
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _quantityCtrl.removeListener(_schedulePreview);
    _durationCtrl.removeListener(_schedulePreview);
    _notesCtrl.removeListener(_schedulePreview);
    _cityCtrl.removeListener(_schedulePreview);
    _areaCtrl.removeListener(_schedulePreview);
    _addressCtrl.removeListener(_schedulePreview);
    _quantityCtrl.dispose();
    _durationCtrl.dispose();
    _notesCtrl.dispose();
    _cityCtrl.dispose();
    _areaCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  ServicePricingOptionModel? get _selectedPricingOption {
    for (final item in widget.offering.pricingOptions) {
      if (item.id == _pricingOptionId) {
        return item;
      }
    }
    return widget.offering.pricingOptions.isNotEmpty
        ? widget.offering.pricingOptions.first
        : null;
  }

  double? _parseDouble(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text.replaceAll(',', '.'));
  }

  int? _parseDurationMinutes() {
    final hours = _parseDouble(_durationCtrl);
    if (hours == null) return null;
    return (hours * 60).round();
  }

  void _schedulePreview({bool force = false}) {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(Duration(milliseconds: force ? 0 : 300), () {
      if (mounted) {
        _loadPreview();
      }
    });
  }

  Future<void> _loadPreview() async {
    final pricingOption = _selectedPricingOption;
    if (pricingOption == null) {
      if (!mounted) return;
      setState(() {
        _preview = null;
        _previewError = null;
        _previewLoading = false;
      });
      return;
    }

    final generation = ++_previewGeneration;
    if (mounted) {
      setState(() {
        _previewLoading = true;
        _previewError = null;
      });
    }

    try {
      final body = <String, dynamic>{
        'offeringId': widget.offering.id,
        'providerId': widget.offering.providerId,
        'pricingType': pricingOption.pricingModel,
      };
      final quantity = _parseDouble(_quantityCtrl);
      if (quantity != null) body['quantity'] = quantity;
      final durationMinutes = _parseDurationMinutes();
      if (durationMinutes != null) body['durationMinutes'] = durationMinutes;

      final response = await ref
          .read(servicesApiProvider)
          .previewServiceBooking(body);
      final preview = ServiceBookingPreviewModel.fromJson(response);
      if (!mounted || generation != _previewGeneration) return;
      setState(() {
        _preview = preview;
        _previewError = null;
        _previewLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _previewGeneration) return;
      setState(() {
        _previewLoading = false;
        _previewError = '$e';
      });
    }
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
      final pricingOption = _selectedPricingOption;
      final quantity = _parseDouble(_quantityCtrl);
      final durationMinutes = _parseDurationMinutes();

      final payload = <String, dynamic>{
        'offeringId': widget.offering.id,
        'providerId': widget.offering.providerId,
        'pricingOptionId': (_pricingOptionId ?? 0) > 0 ? _pricingOptionId : null,
        'pricingType': pricingOption?.pricingModel,
        'requestedExecutionMode':
            _requiresHomeService ? 'home' : 'provider_location',
        'requestedDate': dateText,
        'requestedTime': timeText,
        'quantity': quantity,
        'durationHours': _durationCtrl.text.trim().isNotEmpty
            ? double.tryParse(_durationCtrl.text.trim())
            : null,
        'durationMinutes': durationMinutes,
        'notes':
            _notesCtrl.text.trim().isEmpty ? null : _notesCtrl.text.trim(),
        'city': _cityCtrl.text.trim().isEmpty ? null : _cityCtrl.text.trim(),
        'area': _areaCtrl.text.trim().isEmpty ? null : _areaCtrl.text.trim(),
        'addressLine':
            _addressCtrl.text.trim().isEmpty ? null : _addressCtrl.text.trim(),
        'requiresHomeService': _requiresHomeService,
        'requiresQuote':
            widget.offering.inspectionRequired ||
            widget.offering.customQuoteOnly,
        'expectedPriceVersion': _preview?.preview.priceVersion,
        'idempotencyKey': _idempotencyKey,
      }..removeWhere((key, value) => value == null);

      await ref.read(servicesApiProvider).createServiceRequest(
            payload,
            attachmentFiles: _attachments,
          );

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
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'معاينة التسعير',
                          style: TextStyle(fontWeight: FontWeight.w900),
                        ),
                      ),
                      TextButton(
                        onPressed: _previewLoading
                            ? null
                            : () => _schedulePreview(force: true),
                        child: _previewLoading
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Text('تحديث'),
                      ),
                    ],
                  ),
                  if (_previewError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _previewError!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    )
                  else if (_selectedPricingOption == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('لا توجد خيارات تسعير لهذه الخدمة.'),
                    )
                  else if (_preview == null)
                    const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Text('اضبط الكمية أو المدة لعرض معاينة السعر.'),
                    )
                  else
                    _ServiceBookingPreviewCard(preview: _preview!.preview),
                ],
              ),
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
              onChanged: (value) {
                setState(() => _pricingOptionId = value);
                _schedulePreview(force: true);
              },
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

class _ServiceBookingPreviewCard extends StatelessWidget {
  final ServiceBookingPreviewSnapshotModel preview;

  const _ServiceBookingPreviewCard({required this.preview});

  String _money(double value) {
    final text = value.toStringAsFixed(
      value.truncateToDouble() == value ? 0 : 2,
    );
    return '$text IQD';
  }

  String _trimmedNumber(double value) {
    return value.toStringAsFixed(value.truncateToDouble() == value ? 0 : 2);
  }

  @override
  Widget build(BuildContext context) {
    final promotion = preview.promotionSnapshot;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _chip('نوع التسعير', preview.pricingType),
            _chip('سعر الوحدة', _money(preview.unitPriceIqd)),
            _chip('الكمية', _trimmedNumber(preview.quantity)),
            _chip('المدة', '${preview.durationMinutes} دقيقة'),
          ],
        ),
        const SizedBox(height: 10),
        Text('الإجمالي قبل الخصم: ${_money(preview.subtotalIqd)}'),
        Text('الخصم: ${_money(preview.discountIqd)}'),
        Text('رسوم الخدمة: ${_money(preview.serviceFeeIqd)}'),
        Text(
          'المجموع النهائي: ${_money(preview.totalIqd)}',
          style: const TextStyle(fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 8),
        Text('Version: ${preview.priceVersion}'),
        Text('تنتهي: ${preview.expiresAt}'),
        if (promotion != null && promotion['title'] != null) ...[
          const SizedBox(height: 8),
          Text(
            'Promotion: ${promotion['title']}',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade400),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 2),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }
}
