// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart';
import '../company_portal_text.dart';
import '../data/company_api.dart';
import '../models/company_models.dart';
import 'widgets/company_ui.dart';

import 'package:maslaki/core/media/cached_app_image.dart';

class CompanyUsersScreen extends StatefulWidget {
  final CompanyApi api;
  final int companyId;

  const CompanyUsersScreen({
    super.key,
    required this.api,
    required this.companyId,
  });

  @override
  State<CompanyUsersScreen> createState() => _CompanyUsersScreenState();
}

class _CompanyUsersScreenState extends State<CompanyUsersScreen> {
  Future<List<CompanyUserRecord>>? _future;

  @override
  void initState() {
    super.initState();
    _future = widget.api.users(widget.companyId);
  }

  @override
  void didUpdateWidget(covariant CompanyUsersScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.companyId != widget.companyId) {
      _future = widget.api.users(widget.companyId);
    }
  }

  Future<void> _refresh() async {
    setState(() => _future = widget.api.users(widget.companyId));
    await _future;
  }

  Future<void> _showCreateUser() async {
    final l10n = context.l10n;
    final fullNameController = TextEditingController();
    final phoneController = TextEditingController();
    final pinController = TextEditingController();
    final workTitleController = TextEditingController();
    final workCompanyController = TextEditingController();
    final scrollCoordinator = FormScrollCoordinator();
    final fieldErrors = <String, String>{};
    String? formError;
    var saving = false;
    var dialogClosed = false;
    var role = 'company_manager';

    final created = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) {
          Future<void> submit() async {
            if (saving) return;
            final nextErrors = <String, String>{};
            if (fullNameController.text.trim().isEmpty) {
              nextErrors['fullName'] = resolveFormFieldError(
                l10n: l10n,
                field: 'fullName',
                fieldLabel: l10n.companyUsersFullName,
              );
            }
            if (phoneController.text.trim().isEmpty) {
              nextErrors['phone'] = resolveFormFieldError(
                l10n: l10n,
                field: 'phone',
                fieldLabel: l10n.authPhoneLabel,
              );
            }
            if (pinController.text.trim().length < 4) {
              nextErrors['pin'] = l10n.authPinInvalidFormat;
            }

            if (nextErrors.isNotEmpty) {
              fieldErrors
                ..clear()
                ..addAll(nextErrors);
              setModalState(
                () => formError = l10n.validationReviewRequiredFields,
              );
              await scrollCoordinator.focusFirstError(nextErrors.keys);
              return;
            }

            setModalState(() {
              saving = true;
              formError = null;
              fieldErrors.clear();
            });

            try {
              await widget.api.createUser(
                widget.companyId,
                fullName: fullNameController.text.trim(),
                phone: phoneController.text.trim(),
                pin: pinController.text.trim(),
                role: role,
                workTitle: workTitleController.text.trim().isEmpty
                    ? null
                    : workTitleController.text.trim(),
                workCompany: workCompanyController.text.trim().isEmpty
                    ? null
                    : workCompanyController.text.trim(),
              );
              if (!mounted) return;
              dialogClosed = true;
              Navigator.of(context).pop(true);
            } on Exception catch (e) {
              final parsed = parseBackendFieldErrors(e);
              if (parsed.hasFieldErrors || parsed.formCode != null) {
                fieldErrors.clear();
                if (parsed.fieldCodes.containsKey('fullName')) {
                  fieldErrors['fullName'] = resolveFormFieldError(
                    l10n: l10n,
                    field: 'fullName',
                    code: parsed.codeFor('fullName'),
                    fieldLabel: l10n.companyUsersFullName,
                  );
                }
                if (parsed.fieldCodes.containsKey('phone')) {
                  fieldErrors['phone'] = resolveFormFieldError(
                    l10n: l10n,
                    field: 'phone',
                    code: parsed.codeFor('phone'),
                    fieldLabel: l10n.authPhoneLabel,
                  );
                }
                if (parsed.fieldCodes.containsKey('pin')) {
                  fieldErrors['pin'] = resolveFormFieldError(
                    l10n: l10n,
                    field: 'pin',
                    code: parsed.codeFor('pin'),
                    fieldLabel: l10n.authPinLabel,
                  );
                }
                setModalState(() {
                  formError = resolveFormLevelError(
                    l10n,
                    code: parsed.formCode ?? parsed.messageCode,
                    fallback: l10n.validationReviewRequiredFields,
                  );
                });
                await scrollCoordinator.focusFirstError(fieldErrors.keys);
              } else {
                setModalState(() {
                  formError = mapAnyErrorL10n(
                    e,
                    fallbackBuilder: (l10n) => l10n.errorsUnknown,
                  );
                });
              }
            } finally {
              if (mounted && !dialogClosed) {
                setModalState(() => saving = false);
              }
            }
          }

          return AlertDialog(
            title: Text(l10n.companyUsersCreateTitle),
            content: SizedBox(
              width: 520,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormErrorBanner(message: formError),
                    scrollCoordinator.anchor(
                      'fullName',
                      TextField(
                        controller: fullNameController,
                        focusNode: scrollCoordinator.focusNodeFor('fullName'),
                        onChanged: (_) {
                          final removed =
                              fieldErrors.remove('fullName') != null;
                          if (removed && formError != null) {
                            setModalState(() => formError = null);
                          } else if (removed) {
                            setModalState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: l10n.companyUsersFullName,
                          errorText: fieldErrors['fullName'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'phone',
                      TextField(
                        controller: phoneController,
                        focusNode: scrollCoordinator.focusNodeFor('phone'),
                        keyboardType: TextInputType.phone,
                        onChanged: (_) {
                          final removed = fieldErrors.remove('phone') != null;
                          if (removed && formError != null) {
                            setModalState(() => formError = null);
                          } else if (removed) {
                            setModalState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: l10n.authPhoneLabel,
                          errorText: fieldErrors['phone'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'pin',
                      TextField(
                        controller: pinController,
                        focusNode: scrollCoordinator.focusNodeFor('pin'),
                        obscureText: true,
                        onChanged: (_) {
                          final removed = fieldErrors.remove('pin') != null;
                          if (removed && formError != null) {
                            setModalState(() => formError = null);
                          } else if (removed) {
                            setModalState(() {});
                          }
                        },
                        decoration: InputDecoration(
                          labelText: l10n.authPinLabel,
                          errorText: fieldErrors['pin'],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: role,
                      decoration: InputDecoration(
                        labelText: l10n.companyUsersRole,
                      ),
                      items: [
                        DropdownMenuItem(
                          value: 'company_owner',
                          child: Text(l10n.companyRoleOwner),
                        ),
                        DropdownMenuItem(
                          value: 'company_manager',
                          child: Text(l10n.companyRoleManager),
                        ),
                        DropdownMenuItem(
                          value: 'finance_viewer',
                          child: Text(l10n.companyRoleFinanceViewer),
                        ),
                        DropdownMenuItem(
                          value: 'operations_viewer',
                          child: Text(l10n.companyRoleOperationsViewer),
                        ),
                      ],
                      onChanged: (value) => role = value ?? role,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: workTitleController,
                      decoration: InputDecoration(
                        labelText: l10n.companyUsersWorkTitle,
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: workCompanyController,
                      decoration: InputDecoration(
                        labelText: l10n.companyUsersWorkCompany,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(context).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(l10n.commonCreate),
              ),
            ],
          );
        },
      ),
    );

    fullNameController.dispose();
    phoneController.dispose();
    pinController.dispose();
    workTitleController.dispose();
    workCompanyController.dispose();
    scrollCoordinator.dispose();
    if (created == true) await _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return FutureBuilder<List<CompanyUserRecord>>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return CompanyEmptyState(
            icon: Icons.group_outlined,
            title: l10n.companyUsersLoadFailed,
            description: '${snapshot.error}',
            action: FilledButton.icon(
              onPressed: _refresh,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l10n.commonRetry),
            ),
          );
        }
        final users = snapshot.data ?? const <CompanyUserRecord>[];
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              CompanySectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CompanySectionHeader(
                      title: l10n.companyUsersTitle,
                      subtitle: l10n.companyUsersSubtitle,
                      actions: [
                        FilledButton.icon(
                          onPressed: _showCreateUser,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(l10n.companyUsersCreate),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (users.isEmpty)
                      CompanyEmptyState(
                        icon: Icons.group_add_outlined,
                        title: l10n.companyUsersEmptyTitle,
                        description: l10n.companyUsersEmptyDescription,
                        action: FilledButton.icon(
                          onPressed: _showCreateUser,
                          icon: const Icon(Icons.person_add_alt_1_rounded),
                          label: Text(l10n.companyUsersAddFirst),
                        ),
                      )
                    else
                      ...users.map(
                        (record) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              color: Colors.white.withValues(alpha: 0.04),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 24,
                                  backgroundColor: Theme.of(
                                    context,
                                  ).colorScheme.primary.withValues(alpha: 0.18),
                                  backgroundImage: record.user.imageUrl == null
                                      ? null
                                      : AppCachedImageProvider(
                                          record.user.imageUrl!,
                                        ),
                                  child: record.user.imageUrl == null
                                      ? const Icon(Icons.person_rounded)
                                      : null,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        record.user.fullName,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              fontWeight: FontWeight.w800,
                                            ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        [
                                          record.user.phone,
                                          companyRoleLabel(
                                            context,
                                            record.role,
                                          ),
                                        ].join(' • '),
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                      ),
                                      if ((record.user.workTitle ?? '')
                                          .isNotEmpty)
                                        Text(
                                          record.user.workTitle!,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                    ],
                                  ),
                                ),
                                CompanyStatusChip(
                                  label: record.isActive
                                      ? l10n.companyBranchesActive
                                      : l10n.companyUsersDisabled,
                                  color: record.isActive
                                      ? Colors.greenAccent.shade400
                                      : Theme.of(context).colorScheme.error,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
