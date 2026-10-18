import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/sections/section_availability_controller.dart';
import '../../../core/sections/section_availability_models.dart';
import '../../../core/sections/section_unavailable_screen.dart';
import '../../auth/state/auth_controller.dart';
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
  final _formKey = GlobalKey<FormState>();
  final _quantityCtrl = TextEditingController(text: '1');
  final _durationCtrl = TextEditingController(text: '1');
  final _addressCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _medicalConditionsCtrl = TextEditingController();
  final _medicationsCtrl = TextEditingController();
  final _allergiesCtrl = TextEditingController();
  final List<LocalImageFile> _attachments = [];

  late DateTime _date;
  late TimeOfDay _time;
  late final String _idempotencyKey;
  int? _pricingOptionId;
  String _preferredContact = 'in_app';
  double? _latitude;
  double? _longitude;
  bool _locating = false;
  bool _loading = false;
  bool _previewLoading = false;
  String? _error;
  ServiceBookingPreviewModel? _preview;
  Timer? _previewDebounce;

  @override
  void initState() {
    super.initState();
    final initial = DateTime.now().add(const Duration(hours: 1));
    _date = DateTime(initial.year, initial.month, initial.day);
    _time = TimeOfDay.fromDateTime(initial);
    _idempotencyKey =
        'service-${DateTime.now().microsecondsSinceEpoch}-${Random().nextInt(1 << 32)}';
    final options = widget.offering.pricingOptions;
    ServicePricingOptionModel? selected;
    for (final option in options) {
      if (option.isDefault) {
        selected = option;
        break;
      }
    }
    selected ??= options.isEmpty ? null : options.first;
    _pricingOptionId = selected?.id;
    _quantityCtrl.addListener(_schedulePreview);
    _durationCtrl.addListener(_schedulePreview);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _phoneCtrl.text = ref.read(authControllerProvider).user?.phone ?? '';
      _loadPreview();
    });
  }

  @override
  void dispose() {
    _previewDebounce?.cancel();
    _quantityCtrl.dispose();
    _durationCtrl.dispose();
    _addressCtrl.dispose();
    _descriptionCtrl.dispose();
    _phoneCtrl.dispose();
    _medicalConditionsCtrl.dispose();
    _medicationsCtrl.dispose();
    _allergiesCtrl.dispose();
    super.dispose();
  }

  ServicePricingOptionModel? get _pricingOption {
    for (final option in widget.offering.pricingOptions) {
      if (option.id == _pricingOptionId) return option;
    }
    return widget.offering.pricingOptions.isEmpty
        ? null
        : widget.offering.pricingOptions.first;
  }

  bool get _isMedical {
    final category =
        '${widget.offering.mainCategoryName ?? ''} '
                '${widget.offering.subcategoryName ?? ''} ${widget.offering.name}'
            .toLowerCase();
    return category.contains('طب') ||
        category.contains('صحة') ||
        category.contains('تمريض') ||
        category.contains('medical');
  }

  bool get _isHourly =>
      (_pricingOption?.pricingModel ?? '').toLowerCase().contains('hour');

  bool get _isUnitPricing {
    final model = (_pricingOption?.pricingModel ?? '').toLowerCase();
    return model.contains('unit') || model.contains('meter');
  }

  double? _number(TextEditingController controller) =>
      double.tryParse(controller.text.trim().replaceAll(',', '.'));

  int? get _durationMinutes {
    if (!_isHourly) return widget.offering.estimatedDurationMinutes;
    final hours = _number(_durationCtrl);
    return hours == null ? null : max(1, (hours * 60).round());
  }

  void _schedulePreview() {
    _previewDebounce?.cancel();
    _previewDebounce = Timer(const Duration(milliseconds: 350), _loadPreview);
  }

  Future<void> _loadPreview() async {
    final option = _pricingOption;
    if (option == null || !mounted) return;
    setState(() => _previewLoading = true);
    try {
      final raw = await ref.read(servicesApiProvider).previewServiceBooking({
        'offeringId': widget.offering.id,
        'providerId': widget.offering.providerId,
        'pricingType': option.pricingModel,
        if (_isUnitPricing) 'quantity': _number(_quantityCtrl) ?? 1,
        if (_isHourly && _durationMinutes != null)
          'durationMinutes': _durationMinutes,
      });
      if (!mounted) return;
      setState(() {
        _preview = ServiceBookingPreviewModel.fromJson(raw);
        _previewLoading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _previewLoading = false);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final value = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 180)),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _pickTime() async {
    final value = await showTimePicker(context: context, initialTime: _time);
    if (value != null && mounted) setState(() => _time = value);
  }

  Future<void> _useCurrentLocation() async {
    if (_locating) return;
    setState(() {
      _locating = true;
      _error = null;
    });
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        throw Exception('فعّل خدمة الموقع ثم حاول مرة أخرى.');
      }
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        throw Exception('لم يتم منح إذن الموقع.');
      }
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _pickAttachments() async {
    final remaining = 8 - _attachments.length;
    if (remaining <= 0) return;
    final files = await pickMultipleImagesFromDevice(maxFiles: remaining);
    if (!mounted || files.isEmpty) return;
    setState(() => _attachments.addAll(files));
  }

  Future<void> _submit() async {
    if (_loading || !_formKey.currentState!.validate()) return;
    if (_latitude == null || _longitude == null) {
      setState(() => _error = 'حدد موقع تنفيذ الخدمة قبل إرسال الطلب.');
      return;
    }
    if (['phone', 'whatsapp'].contains(_preferredContact) &&
        _phoneCtrl.text.trim().isEmpty) {
      setState(() => _error = 'أدخل رقم الهاتف لطريقة التواصل المختارة.');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final date =
          '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      final time =
          '${_time.hour.toString().padLeft(2, '0')}:${_time.minute.toString().padLeft(2, '0')}';
      final option = _pricingOption;
      final medicalInfo = <String, dynamic>{
        if (_medicalConditionsCtrl.text.trim().isNotEmpty)
          'conditions': _medicalConditionsCtrl.text.trim(),
        if (_medicationsCtrl.text.trim().isNotEmpty)
          'medications': _medicationsCtrl.text.trim(),
        if (_allergiesCtrl.text.trim().isNotEmpty)
          'allergies': _allergiesCtrl.text.trim(),
      };
      await ref.read(servicesApiProvider).createServiceRequest({
        'offeringId': widget.offering.id,
        'providerId': widget.offering.providerId,
        if (_pricingOptionId != null) 'pricingOptionId': _pricingOptionId,
        'pricingType': option?.pricingModel ?? 'inspection_required',
        'requestedExecutionMode': 'home',
        'requestedDate': date,
        'requestedTime': time,
        if (_isUnitPricing) 'quantity': _number(_quantityCtrl) ?? 1,
        if (_isHourly) 'durationHours': _number(_durationCtrl) ?? 1,
        if (_durationMinutes != null) 'durationMinutes': _durationMinutes,
        'notes': _descriptionCtrl.text.trim(),
        'city': 'بغداد',
        'area': 'بسماية',
        'addressLine': _addressCtrl.text.trim(),
        'latitude': _latitude,
        'longitude': _longitude,
        'requiresHomeService': true,
        'requiresQuote':
            widget.offering.inspectionRequired ||
            widget.offering.customQuoteOnly,
        'preferredContact': _preferredContact,
        if (_preferredContact != 'in_app')
          'contactPhone': _phoneCtrl.text.trim(),
        if (medicalInfo.isNotEmpty) 'medicalInfo': medicalInfo,
        if (_preview != null)
          'expectedPriceVersion': _preview!.preview.priceVersion,
        'idempotencyKey': _idempotencyKey,
      }, attachmentFiles: _attachments);
      if (!mounted) return;
      Navigator.of(context).pop(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم إرسال طلب الخدمة بنجاح.')),
      );
    } catch (error) {
      if (mounted) setState(() => _error = '$error');
    } finally {
      if (mounted) setState(() => _loading = false);
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
    final colorScheme = Theme.of(context).colorScheme;
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(title: const Text('حجز الخدمة')),
        bottomNavigationBar: SafeArea(
          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _loading ? null : _submit,
            icon: _loading
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_circle_outline_rounded),
            label: Text(_loading ? 'جارٍ إرسال الطلب...' : 'تأكيد طلب الخدمة'),
          ),
        ),
        body: SafeArea(
          top: false,
          child: Form(
            key: _formKey,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                Text(
                  widget.offering.name,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.offering.displayPriceText,
                  style: TextStyle(
                    color: colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(color: colorScheme.onErrorContainer),
                    ),
                  ),
                ],
                const SizedBox(height: 18),
                const _StepHeading(number: '1', title: 'اختر الموعد'),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickDate,
                        icon: const Icon(Icons.calendar_month_outlined),
                        label: Text(
                          '${_date.year}/${_date.month}/${_date.day}',
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _pickTime,
                        icon: const Icon(Icons.schedule_rounded),
                        label: Text(_time.format(context)),
                      ),
                    ),
                  ],
                ),
                if (widget.offering.pricingOptions.length > 1) ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<int>(
                    initialValue: _pricingOptionId,
                    decoration: const InputDecoration(
                      labelText: 'طريقة التسعير',
                    ),
                    items: widget.offering.pricingOptions
                        .map(
                          (option) => DropdownMenuItem(
                            value: option.id,
                            child: Text(option.displayText()),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      setState(() => _pricingOptionId = value);
                      _loadPreview();
                    },
                  ),
                ],
                if (_isHourly || _isUnitPricing) ...[
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _isHourly ? _durationCtrl : _quantityCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: _isHourly ? 'عدد الساعات' : 'الكمية المطلوبة',
                    ),
                    validator: (value) {
                      final number = double.tryParse(value?.trim() ?? '');
                      return number == null || number <= 0
                          ? 'أدخل قيمة صحيحة'
                          : null;
                    },
                  ),
                ],
                const SizedBox(height: 12),
                _PriceSummary(
                  preview: _preview?.preview,
                  loading: _previewLoading,
                  fallback: widget.offering.displayPriceText,
                ),
                const SizedBox(height: 22),
                const _StepHeading(number: '2', title: 'حدد مكان الخدمة'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _addressCtrl,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'العنوان التفصيلي',
                    hintText: 'المحلة، العمارة، الطابق، أقرب نقطة دالة',
                    prefixIcon: Icon(Icons.home_work_outlined),
                  ),
                  validator: (value) => (value ?? '').trim().length < 5
                      ? 'اكتب عنواناً واضحاً لتنفيذ الخدمة'
                      : null,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _locating ? null : _useCurrentLocation,
                  icon: _locating
                      ? const SizedBox.square(
                          dimension: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          _latitude == null
                              ? Icons.my_location_rounded
                              : Icons.location_on_rounded,
                        ),
                  label: Text(
                    _latitude == null
                        ? 'تحديد موقعي الحالي'
                        : 'تم تثبيت الموقع - اضغط للتحديث',
                  ),
                ),
                const SizedBox(height: 22),
                const _StepHeading(number: '3', title: 'اشرح ما تحتاجه'),
                const SizedBox(height: 10),
                TextFormField(
                  controller: _descriptionCtrl,
                  minLines: 3,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    labelText: 'وصف الطلب',
                    hintText: 'اكتب المشكلة أو المطلوب باختصار...',
                    alignLabelWithHint: true,
                  ),
                  validator: (value) => (value ?? '').trim().length < 5
                      ? 'أضف وصفاً قصيراً ليساعد فريق مسلكي'
                      : null,
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: _attachments.length >= 8 ? null : _pickAttachments,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: Text(
                    _attachments.isEmpty
                        ? 'إضافة صور توضيحية (اختياري)'
                        : 'إضافة صور أخرى (${_attachments.length}/8)',
                  ),
                ),
                if (_attachments.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _attachments.length,
                      separatorBuilder: (_, _) => const SizedBox(width: 8),
                      itemBuilder: (context, index) {
                        final file = _attachments[index];
                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: file.hasBytes
                                  ? Image.memory(
                                      file.bytes!,
                                      width: 76,
                                      height: 76,
                                      fit: BoxFit.cover,
                                    )
                                  : const SizedBox.square(
                                      dimension: 76,
                                      child: Icon(Icons.image_outlined),
                                    ),
                            ),
                            Positioned(
                              top: 2,
                              left: 2,
                              child: IconButton.filledTonal(
                                visualDensity: VisualDensity.compact,
                                iconSize: 16,
                                tooltip: 'حذف الصورة',
                                onPressed: () => setState(
                                  () => _attachments.removeAt(index),
                                ),
                                icon: const Icon(Icons.close_rounded),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
                if (_isMedical) ...[
                  const SizedBox(height: 12),
                  ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: const Text(
                      'معلومات طبية تساعد المختص (اختيارية)',
                      style: TextStyle(fontWeight: FontWeight.w800),
                    ),
                    children: [
                      TextField(
                        controller: _medicalConditionsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الأمراض أو الحالات الصحية',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _medicationsCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الأدوية المستخدمة',
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _allergiesCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الحساسيات المعروفة',
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 22),
                const _StepHeading(number: '4', title: 'طريقة التواصل'),
                const SizedBox(height: 10),
                SegmentedButton<String>(
                  segments: const [
                    ButtonSegment(
                      value: 'in_app',
                      icon: Icon(Icons.chat_bubble_outline_rounded),
                      label: Text('التطبيق'),
                    ),
                    ButtonSegment(
                      value: 'phone',
                      icon: Icon(Icons.call_outlined),
                      label: Text('اتصال'),
                    ),
                    ButtonSegment(
                      value: 'whatsapp',
                      icon: Icon(Icons.forum_outlined),
                      label: Text('واتساب'),
                    ),
                  ],
                  selected: {_preferredContact},
                  onSelectionChanged: (values) {
                    setState(() => _preferredContact = values.first);
                  },
                ),
                if (_preferredContact != 'in_app') ...[
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _phoneCtrl,
                    keyboardType: TextInputType.phone,
                    decoration: const InputDecoration(
                      labelText: 'رقم الهاتف للتواصل',
                      prefixIcon: Icon(Icons.phone_outlined),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                Text(
                  'لن يُعتمد أي مبلغ مختلف قبل أن يظهر لك بوضوح وتوافق عليه.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StepHeading extends StatelessWidget {
  final String number;
  final String title;

  const _StepHeading({required this.number, required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: Theme.of(context).colorScheme.primary,
          foregroundColor: Theme.of(context).colorScheme.onPrimary,
          child: Text(
            number,
            style: const TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(
            context,
          ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900),
        ),
      ],
    );
  }
}

class _PriceSummary extends StatelessWidget {
  final ServiceBookingPreviewSnapshotModel? preview;
  final bool loading;
  final String fallback;

  const _PriceSummary({
    required this.preview,
    required this.loading,
    required this.fallback,
  });

  String _money(num value) => '${value.round()} د.ع';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(8),
      ),
      child: loading
          ? const LinearProgressIndicator()
          : preview == null
          ? Row(
              children: [
                const Icon(Icons.receipt_long_outlined),
                const SizedBox(width: 8),
                Expanded(child: Text(fallback)),
              ],
            )
          : Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text('السعر المتوقع'),
                    Text(
                      _money(preview!.totalIqd),
                      style: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                  ],
                ),
                if (preview!.discountIqd > 0) ...[
                  const SizedBox(height: 4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('الخصم الحالي'),
                      Text('- ${_money(preview!.discountIqd)}'),
                    ],
                  ),
                ],
              ],
            ),
    );
  }
}
