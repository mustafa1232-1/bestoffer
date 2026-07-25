import 'package:flutter/material.dart';

import '../../../core/i18n/locale_text.dart';

/// نتيجة اختيار سبب الإلغاء.
class TaxiCancelReason {
  const TaxiCancelReason({required this.code, this.text});

  final String code;
  final String? text;
}

class _ReasonOption {
  const _ReasonOption(this.code, this.ar, this.en);
  final String code;
  final String ar;
  final String en;
}

const List<_ReasonOption> _customerReasons = [
  _ReasonOption('changed_mind', 'غيّرت رأيي', 'Changed my mind'),
  _ReasonOption('long_wait', 'الانتظار طال', 'Waiting too long'),
  _ReasonOption('found_alternative', 'وجدت وسيلة أخرى', 'Found another ride'),
  _ReasonOption('wrong_pickup', 'موقع الالتقاط غير صحيح', 'Wrong pickup location'),
  _ReasonOption('price_high', 'الأجرة مرتفعة', 'Fare is too high'),
  _ReasonOption('other', 'سبب آخر', 'Other reason'),
];

const List<_ReasonOption> _captainReasons = [
  _ReasonOption('customer_unreachable', 'تعذّر التواصل مع الزبون', 'Cannot reach the customer'),
  _ReasonOption('too_far', 'المسافة بعيدة', 'Pickup is too far'),
  _ReasonOption('vehicle_issue', 'مشكلة في المركبة', 'Vehicle issue'),
  _ReasonOption('wrong_info', 'معلومات الرحلة غير صحيحة', 'Incorrect ride details'),
  _ReasonOption('other', 'سبب آخر', 'Other reason'),
];

/// يعرض ورقة سفلية لاختيار سبب الإلغاء (إلزامي). يعيد null إذا تراجع المستخدم.
Future<TaxiCancelReason?> showTaxiCancelReasonSheet(
  BuildContext context, {
  bool isCaptain = false,
}) {
  return showModalBottomSheet<TaxiCancelReason>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _TaxiCancelReasonSheet(isCaptain: isCaptain),
  );
}

class _TaxiCancelReasonSheet extends StatefulWidget {
  const _TaxiCancelReasonSheet({required this.isCaptain});

  final bool isCaptain;

  @override
  State<_TaxiCancelReasonSheet> createState() => _TaxiCancelReasonSheetState();
}

class _TaxiCancelReasonSheetState extends State<_TaxiCancelReasonSheet> {
  String? _selectedCode;
  final TextEditingController _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  List<_ReasonOption> get _options =>
      widget.isCaptain ? _captainReasons : _customerReasons;

  bool get _canSubmit {
    if (_selectedCode == null) return false;
    if (_selectedCode == 'other') {
      return _otherController.text.trim().isNotEmpty;
    }
    return true;
  }

  void _submit() {
    if (!_canSubmit) return;
    final text = _otherController.text.trim();
    Navigator.of(context).pop(
      TaxiCancelReason(
        code: _selectedCode!,
        text: text.isEmpty ? null : text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 8,
        bottom: 16 + bottomInset,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.lt(ar: 'سبب إلغاء الرحلة', en: 'Reason for cancelling'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            context.lt(
              ar: 'الرجاء اختيار سبب الإلغاء لإكمال العملية.',
              en: 'Please choose a reason to complete the cancellation.',
            ),
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 12),
          for (final option in _options)
            RadioListTile<String>(
              contentPadding: EdgeInsets.zero,
              value: option.code,
              groupValue: _selectedCode,
              onChanged: (value) => setState(() => _selectedCode = value),
              title: Text(context.lt(ar: option.ar, en: option.en)),
            ),
          if (_selectedCode == 'other')
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: TextField(
                controller: _otherController,
                minLines: 1,
                maxLines: 3,
                maxLength: 500,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  hintText: context.lt(
                    ar: 'اكتب سبب الإلغاء',
                    en: 'Write the reason',
                  ),
                ),
              ),
            ),
          const SizedBox(height: 8),
          FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(
              context.lt(ar: 'تأكيد الإلغاء', en: 'Confirm cancellation'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(context.lt(ar: 'تراجع', en: 'Back')),
          ),
        ],
      ),
    );
  }
}
