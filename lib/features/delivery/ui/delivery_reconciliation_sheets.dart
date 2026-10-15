import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/files/image_picker_service.dart';
import '../../../core/files/local_image_file.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';

class CourierPickupSettlementInput {
  const CourierPickupSettlementInput({
    required this.merchantPaidActual,
    required this.withoutReceipt,
    this.receiptFile,
    this.note,
  });

  final double merchantPaidActual;
  final bool withoutReceipt;
  final LocalImageFile? receiptFile;
  final String? note;
}

class CourierDeliveryCashInput {
  const CourierDeliveryCashInput({required this.customerReceivedActual});

  final double customerReceivedActual;
}

double? _parseMoney(String value) {
  final normalized = value
      .trim()
      .replaceAll(',', '')
      .replaceAllMapped(
        RegExp(r'[٠-٩]'),
        (match) => '${match.group(0)!.codeUnitAt(0) - 0x0660}',
      )
      .replaceAllMapped(
        RegExp(r'[۰-۹]'),
        (match) => '${match.group(0)!.codeUnitAt(0) - 0x06f0}',
      );
  final parsed = double.tryParse(normalized);
  return parsed != null && parsed.isFinite && parsed >= 0 ? parsed : null;
}

Future<CourierPickupSettlementInput?> showCourierPickupSettlementSheet(
  BuildContext context, {
  required double expectedStoreAmount,
}) async {
  final amountController = TextEditingController(
    text: expectedStoreAmount.round().toString(),
  );
  final noteController = TextEditingController();
  LocalImageFile? receipt;
  var withoutReceipt = false;
  String? validationMessage;

  final result = await showModalBottomSheet<CourierPickupSettlementInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) {
        final paid = _parseMoney(amountController.text);
        final difference = paid == null ? 0 : expectedStoreAmount - paid;
        return Padding(
          padding: EdgeInsets.fromLTRB(
            18,
            14,
            18,
            18 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  context.lt(
                    ar: 'تأكيد الدفع للمتجر',
                    en: 'Confirm store payment',
                  ),
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 6),
                Text(
                  context.lt(
                    ar: 'المبلغ المتوقع للمنتجات ${formatIqd(expectedStoreAmount)}. أدخل ما دفعته فعلياً للمتجر.',
                    en: 'Expected product amount is ${formatIqd(expectedStoreAmount)}. Enter what you actually paid the store.',
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: amountController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹.,]')),
                  ],
                  decoration: InputDecoration(
                    labelText: context.lt(
                      ar: 'المبلغ المدفوع للمتجر',
                      en: 'Amount paid to store',
                    ),
                    prefixIcon: const Icon(Icons.payments_outlined),
                    suffixText: context.lt(ar: 'د.ع', en: 'IQD'),
                  ),
                  onChanged: (_) => setSheetState(() {
                    validationMessage = null;
                  }),
                ),
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: difference < 0
                        ? Theme.of(context).colorScheme.errorContainer
                        : Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    difference == 0
                        ? context.lt(
                            ar: 'لا يوجد فرق في سعر الشراء.',
                            en: 'No purchase difference.',
                          )
                        : difference > 0
                        ? context.lt(
                            ar: 'فرق لصالح التطبيق: ${formatIqd(difference)}',
                            en: 'Difference due to app: ${formatIqd(difference)}',
                          )
                        : context.lt(
                            ar: 'دفعت زيادة: ${formatIqd(difference.abs())} وستدخل ضمن مستحقاتك.',
                            en: 'You advanced ${formatIqd(difference.abs())}; it will be included in your dues.',
                          ),
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(height: 14),
                if (receipt != null && receipt!.bytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.memory(
                      receipt!.bytes!,
                      height: 150,
                      width: double.infinity,
                      fit: BoxFit.cover,
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton.icon(
                  onPressed: withoutReceipt
                      ? null
                      : () async {
                          final picked = await captureImageFromCamera();
                          if (picked == null || !context.mounted) return;
                          setSheetState(() {
                            receipt = picked;
                            validationMessage = null;
                          });
                        },
                  icon: const Icon(Icons.photo_camera_outlined),
                  label: Text(
                    receipt == null
                        ? context.lt(
                            ar: 'التقاط صورة الفاتورة',
                            en: 'Capture receipt',
                          )
                        : context.lt(
                            ar: 'إعادة تصوير الفاتورة',
                            en: 'Retake receipt',
                          ),
                  ),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: withoutReceipt,
                  title: Text(
                    context.lt(
                      ar: 'لا توجد فاتورة',
                      en: 'No receipt available',
                    ),
                  ),
                  subtitle: Text(
                    context.lt(
                      ar: 'سيحوّل الطلب للمراجعة الإدارية.',
                      en: 'The order will be sent for admin review.',
                    ),
                  ),
                  onChanged: (value) => setSheetState(() {
                    withoutReceipt = value == true;
                    if (withoutReceipt) receipt = null;
                    validationMessage = null;
                  }),
                ),
                TextField(
                  controller: noteController,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: context.lt(
                      ar: 'ملاحظة اختيارية',
                      en: 'Optional note',
                    ),
                  ),
                ),
                if (validationMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    validationMessage!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                FilledButton.icon(
                  onPressed: () {
                    final amount = _parseMoney(amountController.text);
                    if (amount == null) {
                      setSheetState(() {
                        validationMessage = context.lt(
                          ar: 'أدخل مبلغاً صحيحاً.',
                          en: 'Enter a valid amount.',
                        );
                      });
                      return;
                    }
                    if (receipt == null && !withoutReceipt) {
                      setSheetState(() {
                        validationMessage = context.lt(
                          ar: 'أرفق صورة الفاتورة أو اختر لا توجد فاتورة.',
                          en: 'Attach the receipt or choose no receipt.',
                        );
                      });
                      return;
                    }
                    Navigator.of(sheetContext).pop(
                      CourierPickupSettlementInput(
                        merchantPaidActual: amount,
                        receiptFile: receipt,
                        withoutReceipt: withoutReceipt,
                        note: noteController.text.trim().isEmpty
                            ? null
                            : noteController.text.trim(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(
                    context.lt(
                      ar: 'تأكيد الاستلام والانطلاق',
                      en: 'Confirm pickup and continue',
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
  amountController.dispose();
  noteController.dispose();
  return result;
}

Future<CourierDeliveryCashInput?> showCourierDeliveryCashSheet(
  BuildContext context, {
  required double invoiceTotal,
}) async {
  final controller = TextEditingController(
    text: invoiceTotal.round().toString(),
  );
  String? error;
  final result = await showModalBottomSheet<CourierDeliveryCashInput>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (sheetContext) => StatefulBuilder(
      builder: (context, setSheetState) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              context.lt(ar: 'تأكيد تحصيل الطلب', en: 'Confirm collection'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              context.lt(
                ar: 'إجمالي الفاتورة ${formatIqd(invoiceTotal)}. أدخل المبلغ المستلم فعلياً من الزبون.',
                en: 'Invoice total is ${formatIqd(invoiceTotal)}. Enter the amount actually received from the customer.',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: context.lt(
                  ar: 'المستلم من الزبون',
                  en: 'Received from customer',
                ),
                prefixIcon: const Icon(Icons.account_balance_wallet_outlined),
                suffixText: context.lt(ar: 'د.ع', en: 'IQD'),
                errorText: error,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton(
              onPressed: () {
                final amount = _parseMoney(controller.text);
                if (amount == null) {
                  setSheetState(() {
                    error = context.lt(
                      ar: 'أدخل مبلغاً صحيحاً.',
                      en: 'Enter a valid amount.',
                    );
                  });
                  return;
                }
                Navigator.of(
                  sheetContext,
                ).pop(CourierDeliveryCashInput(customerReceivedActual: amount));
              },
              child: Text(
                context.lt(ar: 'تأكيد التسليم', en: 'Confirm delivery'),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  controller.dispose();
  return result;
}
