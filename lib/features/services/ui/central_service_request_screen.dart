import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../auth/state/auth_controller.dart';
import '../data/services_api.dart';
import '../emergency/emergency_contacts.dart';
import '../models/service_models.dart';
import 'emergency_request_tracking_screen.dart';
import 'service_my_requests_screen.dart';

class CentralServiceRequestScreen extends ConsumerStatefulWidget {
  const CentralServiceRequestScreen({super.key, required this.service});

  final CentralServiceCatalogItem service;

  @override
  ConsumerState<CentralServiceRequestScreen> createState() =>
      _CentralServiceRequestScreenState();
}

class _CentralServiceRequestScreenState
    extends ConsumerState<CentralServiceRequestScreen> {
  final _formKey = GlobalKey<FormState>();
  final _description = TextEditingController();
  final _city = TextEditingController(text: 'بسماية');
  final _area = TextEditingController();
  final _address = TextEditingController();
  final _contactPhone = TextEditingController();
  final Map<String, TextEditingController> _answerControllers = {};
  final Map<String, bool> _booleanAnswers = {};
  final List<LocalImageFile> _attachments = [];
  late final String _idempotencyKey;

  String? _quickIssue;
  String _urgency = 'normal';
  String _preferredContact = 'phone';
  String? _executionMode;
  String? _emergencyTarget;
  DateTime? _date;
  TimeOfDay? _time;
  double? _latitude;
  double? _longitude;
  bool _locating = false;
  bool _submitting = false;

  bool get _isEmergency => widget.service.emergency;

  @override
  void initState() {
    super.initState();
    _idempotencyKey =
        'central:${widget.service.key}:${DateTime.now().microsecondsSinceEpoch}';
    _executionMode = widget.service.executionModes.isEmpty
        ? null
        : widget.service.executionModes.first;
    _prefillCustomerAddress();
    for (final question in widget.service.questions) {
      final key = '${question['key'] ?? ''}'.trim();
      if (key.isEmpty || key == 'emergencyTarget') continue;
      if ('${question['type']}' == 'boolean') {
        _booleanAnswers[key] = false;
      } else {
        _answerControllers[key] = TextEditingController();
      }
    }
  }

  void _prefillCustomerAddress() {
    final user = ref.read(authControllerProvider).user;
    if (user == null) return;

    _contactPhone.text = user.phone.trim();

    final block = user.block.trim();
    final building = user.buildingNumber.trim();
    final apartment = user.apartment.trim();
    if (block.isNotEmpty) _area.text = 'بلوك $block';

    final addressParts = <String>[
      if (building.isNotEmpty) 'عمارة $building',
      if (apartment.isNotEmpty) 'شقة $apartment',
    ];
    if (addressParts.isNotEmpty) _address.text = addressParts.join('، ');
  }

  void _selectQuickIssue(String issue, bool selected) {
    final previousIssue = _quickIssue;
    setState(() {
      _quickIssue = selected ? issue : null;
      for (final key in const ['caseType', 'faultType']) {
        final controller = _answerControllers[key];
        if (controller == null) continue;
        final current = controller.text.trim();
        if (selected && (current.isEmpty || current == previousIssue)) {
          controller.text = issue;
        } else if (!selected && current == issue) {
          controller.clear();
        }
      }
    });
  }

  @override
  void dispose() {
    _description.dispose();
    _city.dispose();
    _area.dispose();
    _address.dispose();
    _contactPhone.dispose();
    for (final controller in _answerControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _pickAttachments() async {
    final files = await pickMultipleImagesFromDevice(maxFiles: 8);
    if (!mounted || files.isEmpty) return;
    setState(() {
      _attachments
        ..clear()
        ..addAll(files.take(8));
    });
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    try {
      final position = await _currentPosition();
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      _showMessage('تم تثبيت موقعك الحالي بنجاح.');
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر تحديد الموقع. فعّل خدمة الموقع واسمح للتطبيق باستخدامها.',
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<Position> _currentPosition() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) throw StateError('LOCATION_SERVICE_DISABLED');
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw StateError('LOCATION_PERMISSION_DENIED');
    }
    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.best,
    );
  }

  Future<void> _activateEmergency(EmergencyContact contact) async {
    if (_submitting) return;
    var callOpened = false;
    FocusScope.of(context).unfocus();
    setState(() {
      _submitting = true;
      _emergencyTarget = contact.key;
      _quickIssue = contact.title;
    });

    try {
      final position = await _currentPosition().timeout(
        const Duration(seconds: 5),
      );
      if (!mounted) return;
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      final answers = <String, dynamic>{
        ..._booleanAnswers,
        'officialEmergencyPhone': contact.phone,
        'emergencyCategory': contact.title,
      };
      for (final entry in _answerControllers.entries) {
        final value = entry.value.text.trim();
        if (value.isNotEmpty) answers[entry.key] = value;
      }
      final requestFuture = ref
          .read(servicesApiProvider)
          .createCentralServiceRequest({
            'serviceKey': widget.service.key,
            'quickIssue': contact.title,
            'description': _description.text.trim().isEmpty
                ? contact.subtitle
                : _description.text.trim(),
            'urgency': 'emergency',
            'requestedExecutionMode': _executionMode ?? 'home',
            'city': _city.text.trim(),
            'area': _area.text.trim(),
            'addressLine': _address.text.trim(),
            'latitude': position.latitude,
            'longitude': position.longitude,
            'preferredContact': 'phone',
            if (_contactPhone.text.trim().isNotEmpty)
              'contactPhone': _contactPhone.text.trim(),
            'emergencyTarget': contact.key,
            'intakeAnswers': answers,
            'idempotencyKey': _idempotencyKey,
          }, attachmentFiles: _attachments);
      callOpened = await launchUrl(Uri(scheme: 'tel', path: contact.phone));
      final result = await requestFuture;
      final requestId = int.tryParse('${result['id'] ?? ''}') ?? 0;
      if (!mounted) return;
      setState(() => _submitting = false);
      if (requestId > 0) {
        await Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) =>
                EmergencyRequestTrackingScreen(requestId: requestId),
          ),
        );
      }
    } catch (_) {
      if (!callOpened) {
        await launchUrl(Uri(scheme: 'tel', path: contact.phone));
      }
      if (mounted) {
        setState(() => _submitting = false);
        _showMessage(
          'تم فتح الاتصال، لكن تعذر إرسال الموقع إلى مسلكي. فعّل الموقع والإنترنت ثم حاول مجدداً.',
          error: true,
        );
      }
    }
  }

  Future<void> _selectDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 180)),
    );
    if (value != null && mounted) setState(() => _date = value);
  }

  Future<void> _selectTime() async {
    final value = await showTimePicker(
      context: context,
      initialTime: _time ?? TimeOfDay.now(),
    );
    if (value != null && mounted) setState(() => _time = value);
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;
    if (_isEmergency && _emergencyTarget == null) {
      _showMessage('اختر الجهة المطلوبة للحالة العاجلة.', error: true);
      return;
    }
    if (_isEmergency && (_latitude == null || _longitude == null)) {
      _showMessage('يجب تثبيت موقعك قبل إرسال نداء SOS.', error: true);
      return;
    }
    if (_preferredContact != 'in_app' && _contactPhone.text.trim().isEmpty) {
      _showMessage('أدخل رقم الهاتف لطريقة التواصل المختارة.', error: true);
      return;
    }

    final answers = <String, dynamic>{..._booleanAnswers};
    for (final entry in _answerControllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) answers[entry.key] = value;
    }
    setState(() => _submitting = true);
    try {
      final result = await ref
          .read(servicesApiProvider)
          .createCentralServiceRequest({
            'serviceKey': widget.service.key,
            if (_quickIssue != null) 'quickIssue': _quickIssue,
            'description': _description.text.trim(),
            'urgency': _isEmergency ? 'emergency' : _urgency,
            if (_executionMode != null)
              'requestedExecutionMode': _executionMode,
            if (_date != null) 'requestedDate': _dateText(_date!),
            if (_time != null) 'requestedTime': _timeText(_time!),
            'city': _city.text.trim(),
            'area': _area.text.trim(),
            'addressLine': _address.text.trim(),
            if (_latitude != null) 'latitude': _latitude,
            if (_longitude != null) 'longitude': _longitude,
            'preferredContact': _preferredContact,
            if (_preferredContact != 'in_app')
              'contactPhone': _contactPhone.text.trim(),
            if (_emergencyTarget != null) 'emergencyTarget': _emergencyTarget,
            'intakeAnswers': answers,
            'idempotencyKey': _idempotencyKey,
          }, attachmentFiles: _attachments);
      if (!mounted) return;
      setState(() => _submitting = false);
      await _showSuccess('${result['requestCode'] ?? result['id'] ?? ''}');
    } catch (_) {
      if (mounted) {
        _showMessage(
          'تعذر إرسال الطلب الآن. تحقق من الاتصال وحاول مرة أخرى.',
          error: true,
        );
      }
    } finally {
      if (mounted && _submitting) setState(() => _submitting = false);
    }
  }

  Future<void> _showSuccess(String code) async {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.check_circle_rounded, size: 48),
        title: Text(_isEmergency ? 'وصل نداء المساعدة' : 'تم إرسال طلبك'),
        content: Text(
          _isEmergency
              ? 'استلم فريق مسلكي النداء $code. أبقِ هاتفك متاحاً وتابع الإشعارات.'
              : 'رقم الطلب $code. سنرسل لك إشعاراً واضحاً عند مراجعة الطلب وتعيين المختص.',
          textDirection: TextDirection.rtl,
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.of(this.context).pushReplacement(
                MaterialPageRoute(
                  builder: (_) => const ServiceMyRequestsScreen(),
                ),
              );
            },
            child: const Text('متابعة الطلب'),
          ),
        ],
      ),
    );
  }

  void _showMessage(String message, {bool error = false}) {
    final scheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, textDirection: TextDirection.rtl),
        backgroundColor: error ? scheme.error : scheme.primary,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = _hexColor(widget.service.color);
    return Scaffold(
      appBar: AppBar(title: Text(widget.service.title)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 120),
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Icon(
                    _isEmergency
                        ? Icons.sos_rounded
                        : Icons.support_agent_rounded,
                    color: Colors.white,
                    size: 34,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          widget.service.title,
                          textDirection: TextDirection.rtl,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 19,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.service.subtitle,
                          textDirection: TextDirection.rtl,
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            if (_isEmergency) ...[
              const SizedBox(height: 12),
              _EmergencyNotice(onCall: () => _callNumber('911')),
              const SizedBox(height: 18),
              const _SectionTitle(
                title: 'ما الجهة المطلوبة؟',
                icon: Icons.emergency_rounded,
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: iraqEmergencyContacts.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisExtent: 132,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                ),
                itemBuilder: (context, index) {
                  final contact = iraqEmergencyContacts[index];
                  return _EmergencyContactCard(
                    contact: contact,
                    selected: _emergencyTarget == contact.key,
                    loading: _submitting && _emergencyTarget == contact.key,
                    onTap: () => _activateEmergency(contact),
                  );
                },
              ),
            ],
            const SizedBox(height: 20),
            const _SectionTitle(
              title: 'ما الذي تحتاجه؟',
              icon: Icons.tune_rounded,
            ),
            const SizedBox(height: 8),
            Wrap(
              alignment: WrapAlignment.end,
              textDirection: TextDirection.rtl,
              spacing: 8,
              runSpacing: 8,
              children: widget.service.quickIssues
                  .map(
                    (issue) => ChoiceChip(
                      selected: _quickIssue == issue,
                      label: Text(issue),
                      onSelected: (selected) =>
                          _selectQuickIssue(issue, selected),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _description,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              minLines: 3,
              maxLines: 6,
              maxLength: 2500,
              decoration: const InputDecoration(
                labelText: 'اشرح الحالة أو المطلوب',
                hintText: 'اكتب التفاصيل التي تساعدنا على اختيار المختص الصحيح',
                alignLabelWithHint: true,
              ),
              validator: (value) {
                if ((value ?? '').trim().isEmpty && _quickIssue == null) {
                  return 'اختر نوع الطلب أو اكتب وصفاً واضحاً';
                }
                return null;
              },
            ),
            ..._buildDynamicQuestions(),
            if (!_isEmergency) ...[
              const SizedBox(height: 18),
              const _SectionTitle(
                title: 'أولوية الطلب',
                icon: Icons.priority_high_rounded,
              ),
              const SizedBox(height: 8),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'normal',
                    label: Text('عادي'),
                    icon: Icon(Icons.schedule_rounded),
                  ),
                  ButtonSegment(
                    value: 'urgent',
                    label: Text('عاجل'),
                    icon: Icon(Icons.bolt_rounded),
                  ),
                ],
                selected: {_urgency},
                onSelectionChanged: (value) =>
                    setState(() => _urgency = value.first),
              ),
            ],
            if (widget.service.executionModes.length > 1) ...[
              const SizedBox(height: 18),
              const _SectionTitle(
                title: 'طريقة تقديم الخدمة',
                icon: Icons.route_outlined,
              ),
              const SizedBox(height: 8),
              Wrap(
                alignment: WrapAlignment.end,
                textDirection: TextDirection.rtl,
                spacing: 8,
                children: widget.service.executionModes
                    .map(
                      (mode) => ChoiceChip(
                        selected: _executionMode == mode,
                        label: Text(_executionModeLabel(mode)),
                        onSelected: (_) =>
                            setState(() => _executionMode = mode),
                      ),
                    )
                    .toList(),
              ),
            ],
            const SizedBox(height: 20),
            const _SectionTitle(
              title: 'الموقع والموعد',
              icon: Icons.location_on_outlined,
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _city,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'المدينة'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _area,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(labelText: 'المنطقة أو المجمع'),
            ),
            const SizedBox(height: 10),
            TextFormField(
              controller: _address,
              textDirection: TextDirection.rtl,
              textAlign: TextAlign.right,
              decoration: const InputDecoration(
                labelText: 'العنوان التفصيلي أو أقرب نقطة دالة',
              ),
              validator: _isEmergency
                  ? (value) => (value ?? '').trim().isEmpty
                        ? 'أدخل نقطة دالة تساعد الفريق على الوصول'
                        : null
                  : null,
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _locating ? null : _locate,
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
                    ? 'تثبيت موقعي الحالي'
                    : 'تم تثبيت الموقع - تحديثه',
              ),
            ),
            if (!_isEmergency) ...[
              const SizedBox(height: 10),
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectDate,
                      icon: const Icon(Icons.calendar_month_rounded),
                      label: Text(
                        _date == null ? 'اختيار اليوم' : _dateText(_date!),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _selectTime,
                      icon: const Icon(Icons.schedule_rounded),
                      label: Text(
                        _time == null ? 'اختيار الوقت' : _timeText(_time!),
                      ),
                    ),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 20),
            const _SectionTitle(
              title: 'طريقة التواصل المفضلة',
              icon: Icons.forum_outlined,
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                  value: 'phone',
                  label: Text('اتصال'),
                  icon: Icon(Icons.call_outlined),
                ),
                ButtonSegment(
                  value: 'whatsapp',
                  label: Text('واتساب'),
                  icon: Icon(Icons.chat_outlined),
                ),
                ButtonSegment(
                  value: 'in_app',
                  label: Text('داخل التطبيق'),
                  icon: Icon(Icons.forum_outlined),
                ),
              ],
              selected: {_preferredContact},
              onSelectionChanged: (value) =>
                  setState(() => _preferredContact = value.first),
            ),
            if (_preferredContact != 'in_app') ...[
              const SizedBox(height: 10),
              TextFormField(
                controller: _contactPhone,
                keyboardType: TextInputType.phone,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(
                  labelText: 'رقم الهاتف للتواصل',
                  prefixIcon: Icon(Icons.phone_outlined),
                ),
              ),
            ],
            const SizedBox(height: 20),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.add_photo_alternate_outlined),
              title: const Text(
                'إضافة صور توضيحية',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
              ),
              subtitle: Text(
                _attachments.isEmpty
                    ? 'اختياري - صورة العطل أو المستند تساعد على التشخيص'
                    : 'تم اختيار ${_attachments.length} صورة',
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
              ),
              trailing: IconButton.filledTonal(
                tooltip: 'اختيار صور',
                onPressed: _pickAttachments,
                icon: const Icon(Icons.photo_library_outlined),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(52),
            backgroundColor: _isEmergency
                ? Theme.of(context).colorScheme.error
                : null,
          ),
          onPressed: _submitting ? null : _submit,
          icon: _submitting
              ? const SizedBox.square(
                  dimension: 19,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(_isEmergency ? Icons.sos_rounded : Icons.send_rounded),
          label: Text(_isEmergency ? 'إرسال نداء SOS الآن' : 'إرسال الطلب'),
        ),
      ),
    );
  }

  List<Widget> _buildDynamicQuestions() {
    final widgets = <Widget>[];
    for (final question in widget.service.questions) {
      final key = '${question['key'] ?? ''}'.trim();
      if (key.isEmpty || key == 'emergencyTarget') continue;
      final label = '${question['label'] ?? key}'.trim();
      final type = '${question['type'] ?? 'text'}';
      final required = question['required'] == true;
      widgets.add(const SizedBox(height: 10));
      if (type == 'boolean') {
        widgets.add(
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _booleanAnswers[key] ?? false,
            title: Text(label, textDirection: TextDirection.rtl),
            onChanged: (value) => setState(() => _booleanAnswers[key] = value),
          ),
        );
      } else {
        widgets.add(
          TextFormField(
            controller: _answerControllers[key],
            keyboardType: type == 'number'
                ? TextInputType.number
                : TextInputType.text,
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
            decoration: InputDecoration(labelText: label),
            validator: required
                ? (value) =>
                      (value ?? '').trim().isEmpty ? 'هذا الحقل مطلوب' : null
                : null,
          ),
        );
      }
    }
    return widgets;
  }

  Future<void> _callNumber(String phone) async {
    await launchUrl(Uri(scheme: 'tel', path: phone));
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title, required this.icon});
  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Row(
      textDirection: TextDirection.rtl,
      children: [
        Icon(icon, color: Theme.of(context).colorScheme.primary, size: 21),
        const SizedBox(width: 7),
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

class _EmergencyNotice extends StatelessWidget {
  const _EmergencyNotice({required this.onCall});
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          const Text(
            'اضغط نوع الطوارئ أدناه: سنثبت موقعك ونرسل الطلب إلى السوبر أدمن ثم نفتح الاتصال الرسمي فوراً. الرقم الموحد للطوارئ في العراق هو 911.',
            textDirection: TextDirection.rtl,
            textAlign: TextAlign.right,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: onCall,
            icon: const Icon(Icons.call_rounded),
            label: const Text('اتصال مباشر بالطوارئ الموحدة 911'),
          ),
        ],
      ),
    );
  }
}

class _EmergencyContactCard extends StatelessWidget {
  const _EmergencyContactCard({
    required this.contact,
    required this.selected,
    required this.loading,
    required this.onTap,
  });

  final EmergencyContact contact;
  final bool selected;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected ? scheme.errorContainer : scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? scheme.error : scheme.outlineVariant,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: loading ? null : onTap,
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                textDirection: TextDirection.rtl,
                children: [
                  Icon(contact.icon, color: scheme.error),
                  const Spacer(),
                  if (loading)
                    const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  else
                    Text(
                      contact.phone,
                      style: TextStyle(
                        color: scheme.error,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                contact.title,
                textDirection: TextDirection.rtl,
                textAlign: TextAlign.right,
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 3),
              Expanded(
                child: Text(
                  contact.subtitle,
                  textDirection: TextDirection.rtl,
                  textAlign: TextAlign.right,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Text(
                'إرسال الموقع والاتصال',
                style: TextStyle(
                  color: scheme.error,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _executionModeLabel(String value) => switch (value) {
  'home' => 'في موقعك',
  'remote' => 'عن بُعد',
  'provider_location' => 'لدى المختص',
  _ => value,
};

String _dateText(DateTime value) =>
    '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

String _timeText(TimeOfDay value) =>
    '${value.hour.toString().padLeft(2, '0')}:${value.minute.toString().padLeft(2, '0')}';

Color _hexColor(String value) {
  final parsed = int.tryParse(value.replaceAll('#', ''), radix: 16);
  return parsed == null ? const Color(0xFF2F684F) : Color(0xFF000000 | parsed);
}
