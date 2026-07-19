import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../../../core/widgets/app_user_drawer.dart';
import '../../auth/state/auth_controller.dart';
import '../models/pending_delivery_account_model.dart';
import '../models/pending_taxi_profile_edit_request_model.dart';
import '../state/admin_controller.dart';
import 'admin_approvals_hub_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_services_hub_screen.dart';
import 'admin_service_provider_subscription_requests_screen.dart';
import 'admin_taxi_captain_details_screen.dart';

class AdminTaxiCaptainRequestsScreen extends ConsumerStatefulWidget {
  final int initialTabIndex;

  const AdminTaxiCaptainRequestsScreen({super.key, this.initialTabIndex = 0});

  @override
  ConsumerState<AdminTaxiCaptainRequestsScreen> createState() =>
      _AdminTaxiCaptainRequestsScreenState();
}

class _AdminTaxiCaptainRequestsScreenState
    extends ConsumerState<AdminTaxiCaptainRequestsScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.initialTabIndex.clamp(0, 1),
  );

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Widget _buildAdminDrawer() {
    final auth = ref.watch(authControllerProvider);
    return AppUserDrawer(
      title: 'لوحة الإدارة',
      subtitle: auth.user?.fullName,
      showCommunitySection: false,
      showSettings: false,
      enableItemSearch: false,
      items: [
        AppUserDrawerItem(
          icon: Icons.space_dashboard_rounded,
          label: 'لوحة التحكم',
          subtitle: 'الصفحة الرئيسية للأدمن',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).pushAndRemoveUntil(
              MaterialPageRoute<void>(
                builder: (_) => const AdminDashboardScreen(),
              ),
              (route) => false,
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.verified_user_outlined,
          label: 'حوض الموافقات',
          subtitle: 'مراجعة الطلبات المعلقة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminApprovalsHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.home_repair_service_outlined,
          label: 'إدارة الخدمات',
          subtitle: 'ملخص الخدمات والطلبات',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AdminServicesHubScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.description_outlined,
          label: 'طلبات الاشتراك',
          subtitle: 'عرض طلبات أصحاب الخدمة',
          group: 'التنقل',
          onTap: (_) async {
            await Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    const AdminServiceProviderSubscriptionRequestsScreen(),
              ),
            );
          },
        ),
        AppUserDrawerItem(
          icon: Icons.refresh_rounded,
          label: 'تحديث الصفحة',
          subtitle: 'إعادة تحميل الموافقات',
          group: 'الإجراءات',
          onTap: (_) async {
            await ref.read(adminControllerProvider.notifier).bootstrap();
          },
        ),
      ],
    );
  }

  Future<void> _openEditReview(
    PendingTaxiProfileEditRequestModel request,
  ) async {
    final noteCtrl = TextEditingController();
    final fieldErrors = <String, String?>{};
    String? formError;
    var submitting = false;
    await showModalBottomSheet<void>(
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
              final l10n = context.l10n;
              final navigator = Navigator.of(sheetContext);
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

              Future<void> executeAction(bool approve) async {
                setSheetState(() {
                  submitting = true;
                  formError = null;
                  fieldErrors.clear();
                });
                try {
                  final adminNote = noteCtrl.text.trim().isEmpty
                      ? null
                      : noteCtrl.text.trim();
                  if (approve) {
                    await ref
                        .read(adminApiProvider)
                        .approveTaxiCaptainProfileEditRequest(
                          request.id,
                          adminNote: adminNote,
                        );
                  } else {
                    await ref
                        .read(adminApiProvider)
                        .rejectTaxiCaptainProfileEditRequest(
                          request.id,
                          adminNote: adminNote,
                        );
                  }
                  await ref.read(adminControllerProvider.notifier).bootstrap();
                  if (!sheetContext.mounted) return;
                  navigator.pop();
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
                        fallbackBuilder: (l10n) => approve
                            ? l10n.adminTaxiProfileEditApproveFailed
                            : l10n.adminTaxiProfileEditRejectFailed,
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
                      l10n.adminTaxiCaptainReviewEditRequestTitle,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    FormErrorBanner(message: formError),
                    const SizedBox(height: 12),
                    Text(
                      '${request.fullName} - ${request.phone}',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    _MapSection(
                      title: l10n.adminTaxiCaptainCurrentProfile,
                      data: request.currentProfile,
                    ),
                    const SizedBox(height: 12),
                    _MapSection(
                      title: l10n.adminTaxiCaptainRequestedChanges,
                      data: request.requestedChanges,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: noteCtrl,
                      minLines: 2,
                      maxLines: 4,
                      onChanged: (_) => clearFieldError('adminNote'),
                      decoration: InputDecoration(
                        labelText: l10n.adminTaxiCaptainAdminNote,
                        errorText: fieldError(
                          'adminNote',
                          l10n.adminTaxiCaptainAdminNote,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: submitting
                                ? null
                                : () => executeAction(false),
                            icon: const Icon(Icons.close_rounded),
                            label: Text(l10n.commonReject),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: submitting
                                ? null
                                : () => executeAction(true),
                            icon: const Icon(Icons.check_rounded),
                            label: Text(l10n.commonApprove),
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
    noteCtrl.dispose();
  }

  Future<void> _openCaptainDetails(int captainUserId) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            AdminTaxiCaptainDetailsScreen(captainUserId: captainUserId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final state = ref.watch(adminControllerProvider);

    return Scaffold(
      drawer: Drawer(child: _buildAdminDrawer()),
      appBar: AppBar(
        title: Text(l10n.adminTaxiCaptainRequestsTitle),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(text: l10n.adminTaxiCaptainApprovalsTab),
            Tab(text: l10n.adminTaxiCaptainProfileEditsTab),
          ],
        ),
        actions: [
          IconButton(
            onPressed: () =>
                ref.read(adminControllerProvider.notifier).bootstrap(),
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          RefreshIndicator(
            onRefresh: () =>
                ref.read(adminControllerProvider.notifier).bootstrap(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: state.pendingTaxiCaptainAccounts.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Center(
                          child: Text(l10n.adminTaxiCaptainNoPendingApprovals),
                        ),
                      ),
                    ]
                  : state.pendingTaxiCaptainAccounts
                        .map(
                          (item) => _CaptainApprovalCard(
                            item: item,
                            saving: state.saving,
                            onApprove: () => ref
                                .read(adminControllerProvider.notifier)
                                .approveTaxiCaptainAccount(item.id),
                            onOpenDetails: () => _openCaptainDetails(item.id),
                          ),
                        )
                        .toList(growable: false),
            ),
          ),
          RefreshIndicator(
            onRefresh: () =>
                ref.read(adminControllerProvider.notifier).bootstrap(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              children: state.pendingTaxiProfileEditRequests.isEmpty
                  ? [
                      Padding(
                        padding: const EdgeInsets.only(top: 28),
                        child: Center(
                          child: Text(
                            l10n.adminTaxiCaptainNoPendingProfileEdits,
                          ),
                        ),
                      ),
                    ]
                  : state.pendingTaxiProfileEditRequests
                        .map(
                          (item) => Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const CircleAvatar(
                                        child: Icon(Icons.edit_note_outlined),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              item.fullName,
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleMedium
                                                  ?.copyWith(
                                                    fontWeight: FontWeight.w800,
                                                  ),
                                            ),
                                            const SizedBox(height: 4),
                                            Text(item.phone),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    l10n.adminTaxiCaptainChangedFields(
                                      item.requestedChanges.length,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () => _openCaptainDetails(
                                            item.captainUserId,
                                          ),
                                          icon: const Icon(
                                            Icons.badge_outlined,
                                          ),
                                          label: Text(l10n.commonDetails),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: FilledButton.tonalIcon(
                                          onPressed: () =>
                                              _openEditReview(item),
                                          icon: const Icon(Icons.open_in_new),
                                          label: Text(l10n.commonOpen),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        )
                        .toList(growable: false),
            ),
          ),
        ],
      ),
    );
  }
}

class _CaptainApprovalCard extends StatelessWidget {
  final PendingDeliveryAccountModel item;
  final bool saving;
  final Future<void> Function() onApprove;
  final VoidCallback onOpenDetails;

  const _CaptainApprovalCard({
    required this.item,
    required this.saving,
    required this.onApprove,
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
                const CircleAvatar(child: Icon(Icons.local_taxi_outlined)),
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
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _CaptainChip(
                  label: l10n.commonVehicle,
                  value: item.vehicleType,
                ),
                _CaptainChip(
                  label: l10n.commonModel,
                  value: '${item.carMake} ${item.carModel}',
                ),
                _CaptainChip(label: l10n.commonYear, value: '${item.carYear}'),
                _CaptainChip(label: l10n.commonPlate, value: item.plateNumber),
                if ((item.block).trim().isNotEmpty)
                  _CaptainChip(label: l10n.commonBlock, value: item.block),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onOpenDetails,
                    icon: const Icon(Icons.badge_outlined),
                    label: Text(l10n.commonDetails),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: saving ? null : onApprove,
                    icon: const Icon(Icons.check_rounded),
                    label: Text(l10n.commonApprove),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CaptainChip extends StatelessWidget {
  final String label;
  final String value;

  const _CaptainChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
      ),
      child: Text('$label: $value'),
    );
  }
}

class _MapSection extends StatelessWidget {
  final String title;
  final Map<String, dynamic> data;

  const _MapSection({required this.title, required this.data});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          if (data.isEmpty)
            Text(context.l10n.commonNoData)
          else
            ...data.entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text('${entry.value}')),
                    const SizedBox(width: 12),
                    Text(
                      entry.key,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
