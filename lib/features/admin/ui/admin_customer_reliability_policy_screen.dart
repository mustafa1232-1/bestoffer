import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/admin_controller.dart';

class AdminCustomerReliabilityPolicyScreen extends ConsumerStatefulWidget {
  const AdminCustomerReliabilityPolicyScreen({super.key});

  @override
  ConsumerState<AdminCustomerReliabilityPolicyScreen> createState() =>
      _AdminCustomerReliabilityPolicyScreenState();
}

class _AdminCustomerReliabilityPolicyScreenState
    extends ConsumerState<AdminCustomerReliabilityPolicyScreen> {
  final _windowDaysController = TextEditingController();
  final _baseScoreController = TextEditingController();
  final _warningThresholdController = TextEditingController();
  final _weightCompletedController = TextEditingController();
  final _weightCancelledController = TextEditingController();
  final _weightFailedDeliveryController = TextEditingController();
  final _weightNoAnswerController = TextEditingController();
  final _weightComplaintsController = TextEditingController();
  final _thresholdTrustedController = TextEditingController();
  final _thresholdNeedsAttentionController = TextEditingController();

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    Future.microtask(_load);
  }

  @override
  void dispose() {
    _windowDaysController.dispose();
    _baseScoreController.dispose();
    _warningThresholdController.dispose();
    _weightCompletedController.dispose();
    _weightCancelledController.dispose();
    _weightFailedDeliveryController.dispose();
    _weightNoAnswerController.dispose();
    _weightComplaintsController.dispose();
    _thresholdTrustedController.dispose();
    _thresholdNeedsAttentionController.dispose();
    super.dispose();
  }

  double _asDouble(dynamic value, double fallback) {
    if (value is num) return value.toDouble();
    return double.tryParse('${value ?? ''}') ?? fallback;
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await ref.read(adminApiProvider).customerReliabilityPolicy();
      final config = Map<String, dynamic>.from(
        (data['config'] as Map?) ?? const <String, dynamic>{},
      );
      final weights = Map<String, dynamic>.from(
        (config['weights'] as Map?) ?? const <String, dynamic>{},
      );
      final thresholds = Map<String, dynamic>.from(
        (config['thresholds'] as Map?) ?? const <String, dynamic>{},
      );

      _windowDaysController.text =
          _asDouble(config['windowDays'], 180).round().toString();
      _baseScoreController.text = _asDouble(config['baseScore'], 70).toString();
      _warningThresholdController.text =
          _asDouble(config['warningThreshold'], 50).toString();
      _weightCompletedController.text =
          _asDouble(weights['completed'], 4).toString();
      _weightCancelledController.text =
          _asDouble(weights['cancelledByCustomer'], -8).toString();
      _weightFailedDeliveryController.text =
          _asDouble(weights['failedDelivery'], -10).toString();
      _weightNoAnswerController.text =
          _asDouble(weights['noAnswer'], -9).toString();
      _weightComplaintsController.text =
          _asDouble(weights['complaints'], -12).toString();
      _thresholdTrustedController.text =
          _asDouble(thresholds['trustedMin'], 80).toString();
      _thresholdNeedsAttentionController.text =
          _asDouble(thresholds['needsAttentionMax'], 45).toString();
    } catch (e) {
      _error = 'تعذر تحميل سياسة موثوقية العميل: $e';
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  double _readNumber(TextEditingController controller, double fallback) {
    return double.tryParse(controller.text.trim()) ?? fallback;
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final trustedMin = _readNumber(_thresholdTrustedController, 80);
      final needsAttentionRaw =
          _readNumber(_thresholdNeedsAttentionController, 45);
      final needsAttentionMax = needsAttentionRaw > trustedMin
          ? trustedMin
          : needsAttentionRaw;
      final config = <String, dynamic>{
        'windowDays': _readNumber(_windowDaysController, 180).round(),
        'baseScore': _readNumber(_baseScoreController, 70),
        'warningThreshold': _readNumber(_warningThresholdController, 50),
        'weights': {
          'completed': _readNumber(_weightCompletedController, 4),
          'cancelledByCustomer': _readNumber(_weightCancelledController, -8),
          'failedDelivery': _readNumber(_weightFailedDeliveryController, -10),
          'noAnswer': _readNumber(_weightNoAnswerController, -9),
          'complaints': _readNumber(_weightComplaintsController, -12),
        },
        'thresholds': {
          'trustedMin': trustedMin,
          'needsAttentionMax': needsAttentionMax,
        },
      };
      await ref
          .read(adminApiProvider)
          .updateCustomerReliabilityPolicy(config: config);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('تم حفظ سياسة موثوقية العميل.')),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('تعذر حفظ السياسة: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Widget _numberField(
    TextEditingController controller,
    String label,
  ) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(
        decimal: true,
        signed: true,
      ),
      textDirection: TextDirection.ltr,
      decoration: InputDecoration(labelText: label),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('سياسة موثوقية العملاء')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.red.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Text(_error!),
                    ),
                    const SizedBox(height: 12),
                  ],
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'إعدادات عامة',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          _numberField(_windowDaysController, 'نافذة التحليل بالأيام'),
                          _numberField(_baseScoreController, 'النتيجة الأساسية'),
                          _numberField(
                            _warningThresholdController,
                            'حد التحذير للمتجر',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'الأوزان',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          _numberField(_weightCompletedController, 'وزن الطلبات المكتملة'),
                          _numberField(
                            _weightCancelledController,
                            'وزن إلغاء العميل',
                          ),
                          _numberField(
                            _weightFailedDeliveryController,
                            'وزن تعذر التسليم',
                          ),
                          _numberField(_weightNoAnswerController, 'وزن عدم الرد'),
                          _numberField(_weightComplaintsController, 'وزن الشكاوى'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'حدود التصنيف',
                            style: TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 8),
                          _numberField(
                            _thresholdTrustedController,
                            'Trusted >=',
                          ),
                          _numberField(
                            _thresholdNeedsAttentionController,
                            'Needs Attention <=',
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ السياسة'),
                  ),
                ],
              ),
            ),
    );
  }
}
