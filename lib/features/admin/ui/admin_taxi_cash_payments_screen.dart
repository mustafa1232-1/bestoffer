import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/utils/parsers.dart';
import '../../../core/utils/currency.dart';
import '../models/pending_taxi_cash_payment_model.dart';
import '../state/admin_controller.dart';
import 'admin_taxi_captain_details_screen.dart';

class AdminTaxiCashPaymentsScreen extends ConsumerStatefulWidget {
  const AdminTaxiCashPaymentsScreen({super.key});

  @override
  ConsumerState<AdminTaxiCashPaymentsScreen> createState() =>
      _AdminTaxiCashPaymentsScreenState();
}

class _AdminTaxiCashPaymentsScreenState
    extends ConsumerState<AdminTaxiCashPaymentsScreen> {
  Future<void> _openCaptainDetails(int captainUserId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => AdminTaxiCaptainDetailsScreen(
          captainUserId: captainUserId,
        ),
      ),
    );
  }

  Future<void> _openPaymentSheet(PendingTaxiCashPaymentModel item) async {
    final l10n = context.l10n;
    final discountCtrl = TextEditingController(text: '${item.discountPercent}');
    final cycleDaysCtrl = TextEditingController(text: '30');
    final fieldErrors = <String, String?>{};
    String? formError;
    var submitting = false;

    final submitted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              String? fieldError(String field, String label) {
                final code = fieldErrors[field];
                if (code == null) return null;
                return resolveFormFieldError(
                  l10n: l10n,
                  field: field,
                  code: code,
                  fieldLabel: label,
                );
              }

              void clearFieldError(String field) {
                if (!fieldErrors.containsKey(field)) return;
                setSheetState(() => fieldErrors.remove(field));
              }

              Future<void> submit() async {
                final discountPercent = tryParseLocalizedInt(
                  discountCtrl.text.trim(),
                );
                final cycleDays = tryParseLocalizedInt(
                  cycleDaysCtrl.text.trim(),
                );
                final validationErrors = <String, String?>{};
                if (discountPercent == null ||
                    discountPercent < 0 ||
                    discountPercent > 100) {
                  validationErrors['discountPercent'] = 'INVALID_NUMBER';
                }
                if (cycleDays == null || cycleDays < 1 || cycleDays > 365) {
                  validationErrors['cycleDays'] = 'INVALID_NUMBER';
                }

                if (validationErrors.isNotEmpty) {
                  setSheetState(() {
                    fieldErrors
                      ..clear()
                      ..addAll(validationErrors);
                    formError = l10n.validationReviewRequiredFields;
                  });
                  return;
                }
                final safeDiscountPercent = discountPercent!;
                final safeCycleDays = cycleDays!;

                setSheetState(() {
                  submitting = true;
                  formError = null;
                  fieldErrors.clear();
                });

                try {
                  if (safeDiscountPercent != item.discountPercent) {
                    await ref
                        .read(adminApiProvider)
                        .setTaxiCaptainDiscount(
                          item.captainUserId,
                          discountPercent: safeDiscountPercent,
                        );
                  }
                  await ref
                      .read(adminApiProvider)
                      .confirmTaxiCaptainCashPayment(
                        item.captainUserId,
                        cycleDays: safeCycleDays,
                      );
                  await ref.read(adminControllerProvider.notifier).bootstrap();
                  if (!sheetContext.mounted) return;
                  Navigator.of(sheetContext).pop(true);
                } catch (error) {
                  final parsed = parseBackendFieldErrors(error);
                  setSheetState(() {
                    submitting = false;
                    fieldErrors
                      ..clear()
                      ..addAll(parsed.fieldCodes);
                    formError = resolveFormLevelError(
                      l10n,
                      code: parsed.formCode ?? parsed.messageCode,
                      fallback: mapAnyErrorL10n(
                        error,
                        fallbackBuilder: (l10n) =>
                            l10n.adminTaxiSubscriptionConfirmFailed,
                      ),
                    );
                  });
                }
              }

              return SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l10n.adminTaxiCashPaymentsReviewTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      '${item.fullName} - ${item.phone}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    FormErrorBanner(message: formError),
                    TextField(
                      controller: discountCtrl,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => clearFieldError('discountPercent'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCashPaymentsDiscount,
                        suffixText: '%',
                        errorText: fieldError(
                          'discountPercent',
                          l10n.adminTaxiCashPaymentsDiscount,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: cycleDaysCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                      ],
                      onChanged: (_) => clearFieldError('cycleDays'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCashPaymentsCycleDaysLabel,
                        errorText: fieldError(
                          'cycleDays',
                          l10n.adminTaxiCashPaymentsCycleDaysLabel,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: submitting
                                ? null
                                : () => Navigator.of(sheetContext).pop(false),
                            child: Text(l10n.commonCancel),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton(
                            onPressed: submitting ? null : submit,
                            child: Text(
                              l10n.adminTaxiCashPaymentsApplyAndConfirm,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
        );
      },
    );

    discountCtrl.dispose();
    cycleDaysCtrl.dispose();

    if (submitted == true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminTaxiSubscriptionConfirmSuccess)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminTaxiCashPaymentsTitle),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(adminControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () => ref.read(adminControllerProvider.notifier).bootstrap(),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: state.pendingTaxiCashPayments.isEmpty
              ? [
                  Padding(
                    padding: const EdgeInsets.only(top: 28),
                    child: Center(child: Text(l10n.adminTaxiCashPaymentsEmpty)),
                  ),
                ]
              : state.pendingTaxiCashPayments
                    .map(
                      (item) => _TaxiCashPaymentCard(
                        item: item,
                        onConfirm: () => _openPaymentSheet(item),
                        onOpenDetails: () =>
                            _openCaptainDetails(item.captainUserId),
                      ),
                    )
                    .toList(growable: false),
        ),
      ),
    );
  }
}

class _TaxiCashPaymentCard extends StatelessWidget {
  final PendingTaxiCashPaymentModel item;
  final VoidCallback onConfirm;
  final VoidCallback onOpenDetails;

  const _TaxiCashPaymentCard({
    required this.item,
    required this.onConfirm,
    required this.onOpenDetails,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const CircleAvatar(child: Icon(Icons.payments_outlined)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.fullName,
                        style: Theme.of(context).textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 4),
                      Text(item.phone),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: onOpenDetails,
                  icon: const Icon(Icons.badge_outlined),
                  label: Text(l10n.commonDetails),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _MetricPill(
                  label: l10n.adminTaxiCashPaymentsDueAmount,
                  value: formatIqd(item.dueAmountIqd),
                ),
                _MetricPill(
                  label: l10n.adminTaxiCashPaymentsMonthlyFee,
                  value: formatIqd(item.monthlyFeeIqd),
                ),
                _MetricPill(
                  label: l10n.adminTaxiCashPaymentsDiscount,
                  value: '${item.discountPercent}%',
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: onConfirm,
                icon: const Icon(Icons.check_circle_outline_rounded),
                label: Text(l10n.adminTaxiCashPaymentsConfirm),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MetricPill extends StatelessWidget {
  final String label;
  final String value;

  const _MetricPill({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.secondary.withValues(alpha: 0.10),
      ),
      child: Text('$label: $value'),
    );
  }
}
