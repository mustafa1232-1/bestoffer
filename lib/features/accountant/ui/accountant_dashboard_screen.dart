// ignore_for_file: unused_element

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/i18n/locale_text.dart';
import '../../../core/utils/currency.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../../hr/ui/hr_employee_portal_screen.dart';
import '../../notifications/ui/notifications_bell.dart';
import '../../settings/ui/pages/settings_account_screen.dart';
import '../../settings/ui/pages/settings_support_screen.dart';
import '../state/accountant_controller.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

enum _AccountantTab { dashboard, pending, ledger, profile }

class AccountantDashboardScreen extends ConsumerStatefulWidget {
  const AccountantDashboardScreen({super.key});

  @override
  ConsumerState<AccountantDashboardScreen> createState() =>
      _AccountantDashboardScreenState();
}

class _AccountantDashboardScreenState
    extends ConsumerState<AccountantDashboardScreen> {
  _AccountantTab _tab = _AccountantTab.dashboard;
  bool _suppressTransientMessages = false;

  void _setTab(_AccountantTab tab) {
    if (_tab == tab) return;
    setState(() => _tab = tab);
  }

  @override
  void initState() {
    super.initState();
    Future.microtask(
      () => ref.read(accountantControllerProvider.notifier).bootstrap(),
    );
  }

  String _title() {
    switch (_tab) {
      case _AccountantTab.dashboard:
        return 'لوحة المحاسب';
      case _AccountantTab.pending:
        return 'ذمم الدلفري';
      case _AccountantTab.ledger:
        return 'الصندوق والحركات';
      case _AccountantTab.profile:
        return 'الملف الشخصي';
    }
  }

  Future<void> _showAmountDialogLegacy({
    required String title,
    required String actionLabel,
    required Future<void> Function(num amount, String? note) onSubmit,
  }) async {
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title, textDirection: TextDirection.rtl),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: amountCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(labelText: 'المبلغ'),
              textDirection: TextDirection.ltr,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: noteCtrl,
              decoration: const InputDecoration(labelText: 'ملاحظة (اختياري)'),
              textDirection: TextDirection.rtl,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            onPressed: () async {
              final amount = num.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) return;
              await onSubmit(
                amount,
                noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
              if (mounted) Navigator.of(context).pop();
            },
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }

  Future<void> _showAmountDialog({
    required String title,
    required String actionLabel,
    required Future<void> Function(num amount, String? note) onSubmit,
  }) async {
    final l10n = context.l10n;
    final amountCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    final fieldErrors = <String, String>{};
    String? formError;
    String? successMessage;
    var submitting = false;

    void clearFieldError(
      String field,
      void Function(VoidCallback fn) setDialogState,
    ) {
      if (!fieldErrors.containsKey(field)) return;
      setDialogState(() => fieldErrors.remove(field));
    }

    _suppressTransientMessages = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (submitting) return;

              final amount = num.tryParse(amountCtrl.text.trim());
              if (amount == null || amount <= 0) {
                setDialogState(() {
                  fieldErrors['amount'] = l10n.validationAmountInvalid;
                  formError = l10n.validationReviewRequiredFields;
                });
                await scrollCoordinator.focusFirstError(const ['amount']);
                return;
              }

              setDialogState(() {
                submitting = true;
                formError = null;
                fieldErrors.remove('amount');
              });

              await onSubmit(
                amount,
                noteCtrl.text.trim().isEmpty ? null : noteCtrl.text.trim(),
              );
              if (!mounted) return;

              final next = ref.read(accountantControllerProvider);
              if (next.error != null && next.error!.trim().isNotEmpty) {
                setDialogState(() {
                  submitting = false;
                  formError = next.error;
                });
                return;
              }

              successMessage = next.successMessage;
              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
            }

            return AlertDialog(
              title: Text(
                title,
                textDirection: Directionality.of(dialogContext),
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormErrorBanner(message: formError),
                    scrollCoordinator.anchor(
                      'amount',
                      TextField(
                        controller: amountCtrl,
                        focusNode: scrollCoordinator.focusNodeFor('amount'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) =>
                            clearFieldError('amount', setDialogState),
                        decoration: InputDecoration(
                          labelText: l10n.commonAmount,
                          errorText: fieldErrors['amount'],
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: InputDecoration(
                        labelText: l10n.accountantOptionalNoteLabel,
                      ),
                      textDirection: Directionality.of(dialogContext),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.commonCancel),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(actionLabel),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      _suppressTransientMessages = false;
      scrollCoordinator.dispose();
      amountCtrl.dispose();
      noteCtrl.dispose();
    }

    if (!mounted || successMessage == null || successMessage!.trim().isEmpty) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(successMessage!)));
  }

  Future<void> _showSettlementConfirmDialog({
    required Map<String, dynamic> item,
  }) async {
    final l10n = context.l10n;
    final expectedAmount =
        num.tryParse('${item['storeNetReceivedAmount'] ?? item['totalAmount'] ?? 0}') ??
        0;
    final actualAmountCtrl = TextEditingController(
      text: expectedAmount.toStringAsFixed(0),
    );
    final reasonCtrl = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    final fieldErrors = <String, String>{};
    String? formError;
    var submitting = false;

    void clearFieldError(
      String field,
      void Function(VoidCallback fn) setDialogState,
    ) {
      if (!fieldErrors.containsKey(field)) return;
      setDialogState(() => fieldErrors.remove(field));
    }

    _suppressTransientMessages = true;
    try {
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            Future<void> submit() async {
              if (submitting) return;
              final actualAmount = num.tryParse(actualAmountCtrl.text.trim());
              if (actualAmount == null || actualAmount < 0) {
                setDialogState(() {
                  fieldErrors['actualAmount'] = l10n.validationAmountInvalid;
                  formError = l10n.validationReviewRequiredFields;
                });
                await scrollCoordinator.focusFirstError(const ['actualAmount']);
                return;
              }

              setDialogState(() {
                submitting = true;
                formError = null;
                fieldErrors.remove('actualAmount');
              });

              await ref
                  .read(accountantControllerProvider.notifier)
                  .confirmSettlement(
                    settlementId: (item['id'] as num).toInt(),
                    actualAmount: actualAmount,
                    differenceReason: reasonCtrl.text.trim().isEmpty
                        ? null
                        : reasonCtrl.text.trim(),
                    note: reasonCtrl.text.trim().isEmpty
                        ? null
                        : reasonCtrl.text.trim(),
                  );
              if (!mounted) return;

              final next = ref.read(accountantControllerProvider);
              if (next.error != null && next.error!.trim().isNotEmpty) {
                setDialogState(() {
                  submitting = false;
                  formError = next.error;
                });
                return;
              }

              if (!dialogContext.mounted) return;
              Navigator.of(dialogContext).pop();
            }

            return AlertDialog(
              title: Text(
                context.lt(
                  ar: 'تأكيد استلام التسوية',
                  en: 'Confirm settlement receipt',
                ),
                textDirection: Directionality.of(dialogContext),
              ),
              content: SizedBox(
                width: 380,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormErrorBanner(message: formError),
                    Text(
                      '${item['deliveryFullName'] ?? '-'} - ${item['deliveryPhone'] ?? ''}',
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${context.lt(ar: "المبلغ المتوقع", en: "Expected amount")}: ${formatIqd(expectedAmount)}',
                      textDirection: TextDirection.rtl,
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'actualAmount',
                      TextField(
                        controller: actualAmountCtrl,
                        focusNode: scrollCoordinator.focusNodeFor('actualAmount'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        onChanged: (_) =>
                            clearFieldError('actualAmount', setDialogState),
                        decoration: InputDecoration(
                          labelText: context.lt(
                            ar: 'المبلغ الفعلي',
                            en: 'Actual amount',
                          ),
                          errorText: fieldErrors['actualAmount'],
                        ),
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: reasonCtrl,
                      decoration: InputDecoration(
                        labelText: context.lt(
                          ar: 'سبب الفرق (اختياري)',
                          en: 'Difference reason (optional)',
                        ),
                      ),
                      maxLines: 2,
                      textDirection: Directionality.of(dialogContext),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(l10n.commonCancel),
                ),
                ElevatedButton(
                  onPressed: submitting ? null : submit,
                  child: submitting
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(
                          context.lt(
                            ar: 'تأكيد الاستلام',
                            en: 'Confirm receipt',
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      );
    } finally {
      _suppressTransientMessages = false;
      scrollCoordinator.dispose();
      actualAmountCtrl.dispose();
      reasonCtrl.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(accountantControllerProvider);
    final auth = ref.watch(authControllerProvider);

    ref.listen<AccountantState>(accountantControllerProvider, (prev, next) {
      if (_suppressTransientMessages) {
        return;
      }
      if (next.error != null && next.error != prev?.error) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.error!)));
      }
      if (next.successMessage != null &&
          next.successMessage != prev?.successMessage) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(next.successMessage!)));
      }
    });

    final summary = state.summary;
    final balance = num.tryParse('${summary['balance'] ?? 0}') ?? 0;
    final pendingAmount = num.tryParse('${summary['pendingAmount'] ?? 0}') ?? 0;
    final pendingCount = num.tryParse('${summary['pendingCount'] ?? 0}') ?? 0;

    return Scaffold(
      drawer: AppUserDrawer(
        title: _title(),
        subtitle: 'إدارة الصندوق وذمم الدلفري',
        items: [
          AppUserDrawerItem(
            icon: Icons.dashboard_outlined,
            label: 'لوحة المحاسب',
            onTap: (_) async => _setTab(_AccountantTab.dashboard),
          ),
          AppUserDrawerItem(
            icon: Icons.request_quote_outlined,
            label: 'ذمم الدلفري',
            onTap: (_) async => _setTab(_AccountantTab.pending),
          ),
          AppUserDrawerItem(
            icon: Icons.account_balance_wallet_outlined,
            label: 'الصندوق والحركات',
            onTap: (_) async => _setTab(_AccountantTab.ledger),
          ),
          AppUserDrawerItem(
            icon: Icons.person_outline,
            label: 'الملف الشخصي',
            onTap: (_) async => _setTab(_AccountantTab.profile),
          ),
          AppUserDrawerItem(
            icon: Icons.badge_outlined,
            label: 'بوابة الموظف',
            onTap: (_) async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const HrEmployeePortalScreen(),
                ),
              );
            },
          ),
          AppUserDrawerItem(
            icon: Icons.refresh_rounded,
            label: 'تحديث',
            onTap: (_) async =>
                ref.read(accountantControllerProvider.notifier).bootstrap(),
          ),
        ],
      ),
      appBar: AppBar(
        title: Text(_title()),
        actions: const [NotificationsBellButton()],
      ),
      body: state.loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () =>
                  ref.read(accountantControllerProvider.notifier).bootstrap(),
              child: ListView(
                padding: const EdgeInsets.all(12),
                children: [
                  _AccountantQuickTabs(currentTab: _tab, onSelectTab: _setTab),
                  const SizedBox(height: 10),
                  if (_tab == _AccountantTab.dashboard) ...[
                    _MetricCard(
                      title: 'الرصيد الحالي',
                      value: formatIqd(balance),
                      icon: Icons.account_balance_wallet_outlined,
                      onTap: () => _setTab(_AccountantTab.ledger),
                    ),
                    const SizedBox(height: 8),
                    _MetricCard(
                      title: 'الذمم المعلقة',
                      value:
                          '${pendingCount.toInt()} - ${formatIqd(pendingAmount)}',
                      icon: Icons.request_quote_outlined,
                      onTap: () => _setTab(_AccountantTab.pending),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: state.saving
                              ? null
                              : () => _showAmountDialog(
                                  title: 'إضافة رصيد افتتاحي',
                                  actionLabel: 'تأكيد',
                                  onSubmit: (amount, note) => ref
                                      .read(
                                        accountantControllerProvider.notifier,
                                      )
                                      .addOpeningBalance(
                                        amount: amount,
                                        note: note,
                                      ),
                                ),
                          icon: const Icon(Icons.add_card_outlined),
                          label: const Text('رصيد افتتاحي'),
                        ),
                        ElevatedButton.icon(
                          onPressed: state.saving
                              ? null
                              : () => _showAmountDialog(
                                  title: 'تسجيل مصروف',
                                  actionLabel: 'إضافة مصروف',
                                  onSubmit: (amount, note) => ref
                                      .read(
                                        accountantControllerProvider.notifier,
                                      )
                                      .addExpense(amount: amount, note: note),
                                ),
                          icon: const Icon(Icons.remove_circle_outline),
                          label: const Text('تسجيل مصروف'),
                        ),
                      ],
                    ),
                  ],
                  if (_tab == _AccountantTab.pending) ...[
                    if (state.pendingSettlements.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('لا توجد ذمم بانتظار الاستلام.'),
                      )
                    else
                      ...state.pendingSettlements.map(
                        (item) => Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Text(
                                  '${item['deliveryFullName'] ?? '-'} - ${item['deliveryPhone'] ?? ''}',
                                  textDirection: TextDirection.rtl,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'التاريخ: ${item['archiveDate']}',
                                  textDirection: TextDirection.rtl,
                                ),
                                Text(
                                  'عدد الطلبات: ${item['ordersCount']}',
                                  textDirection: TextDirection.rtl,
                                ),
                                Text(
                                  'المبلغ: ${formatIqd(item['totalAmount'])}',
                                  textDirection: TextDirection.rtl,
                                ),
                                Text(
                                  'المستلم المتوقع: ${formatIqd(item['storeNetReceivedAmount'] ?? item['store_net_received_amount'] ?? item['totalAmount'])}',
                                  textDirection: TextDirection.rtl,
                                ),
                                Text(
                                  'ذمة التطبيق: ${formatIqd(item['appDueFromDelivery'] ?? item['app_due_from_delivery'] ?? 0)}',
                                  textDirection: TextDirection.rtl,
                                ),
                                Text(
                                  'الفرق: ${formatIqd(item['differenceAmount'] ?? item['difference_amount'] ?? 0)}',
                                  textDirection: TextDirection.rtl,
                                ),
                                const SizedBox(height: 8),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: ElevatedButton.icon(
                                    onPressed: state.saving
                                        ? null
                                        : () => _showSettlementConfirmDialog(
                                              item: item,
                                            ),
                                    icon: const Icon(Icons.verified_outlined),
                                    label: const Text('تأكيد الاستلام'),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                  if (_tab == _AccountantTab.ledger) ...[
                    if (state.ledger.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 18),
                        child: Text('لا توجد حركات بعد.'),
                      )
                    else
                      ...state.ledger.map(
                        (entry) => ListTile(
                          leading: Icon(
                            entry['direction'] == 'credit'
                                ? Icons.arrow_downward_rounded
                                : Icons.arrow_upward_rounded,
                            color: entry['direction'] == 'credit'
                                ? Colors.green
                                : Colors.redAccent,
                          ),
                          title: Text(
                            '${entry['entryType']} - ${formatIqd(entry['amount'])}',
                            textDirection: TextDirection.rtl,
                          ),
                          subtitle: Text(
                            '${entry['createdAt'] ?? ''}',
                            textDirection: TextDirection.rtl,
                          ),
                        ),
                      ),
                  ],
                  if (_tab == _AccountantTab.profile) ...[
                    ListTile(
                      leading: CircleAvatar(
                        backgroundImage: auth.user?.imageUrl?.isNotEmpty == true
                            ? AppCachedImageProvider(auth.user!.imageUrl!)
                            : null,
                        child: auth.user?.imageUrl?.isNotEmpty == true
                            ? null
                            : const Icon(Icons.person_outline),
                      ),
                      title: Text(auth.user?.fullName ?? '-'),
                      subtitle: Text(auth.user?.phone ?? '-'),
                    ),
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsAccountScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.security_outlined),
                      label: const Text('إعدادات الحساب'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => const SettingsSupportScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.support_agent_rounded),
                      label: const Text('الدعم والمساعدة'),
                    ),
                  ],
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.icon,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        onTap: onTap,
        leading: Icon(icon),
        title: Text(title, textDirection: TextDirection.rtl),
        subtitle: Text(value, textDirection: TextDirection.rtl),
        trailing: onTap == null ? null : const Icon(Icons.chevron_left_rounded),
      ),
    );
  }
}

class _AccountantQuickTabs extends StatelessWidget {
  final _AccountantTab currentTab;
  final ValueChanged<_AccountantTab> onSelectTab;

  const _AccountantQuickTabs({
    required this.currentTab,
    required this.onSelectTab,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 42,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          _AccountantQuickTabChip(
            label: 'لوحة المحاسب',
            selected: currentTab == _AccountantTab.dashboard,
            onTap: () => onSelectTab(_AccountantTab.dashboard),
          ),
          const SizedBox(width: 8),
          _AccountantQuickTabChip(
            label: 'ذمم الدلفري',
            selected: currentTab == _AccountantTab.pending,
            onTap: () => onSelectTab(_AccountantTab.pending),
          ),
          const SizedBox(width: 8),
          _AccountantQuickTabChip(
            label: 'الصندوق',
            selected: currentTab == _AccountantTab.ledger,
            onTap: () => onSelectTab(_AccountantTab.ledger),
          ),
          const SizedBox(width: 8),
          _AccountantQuickTabChip(
            label: 'الملف الشخصي',
            selected: currentTab == _AccountantTab.profile,
            onTap: () => onSelectTab(_AccountantTab.profile),
          ),
        ],
      ),
    );
  }
}

class _AccountantQuickTabChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _AccountantQuickTabChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.2)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.45),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.w700,
              color: selected ? scheme.primary : scheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
