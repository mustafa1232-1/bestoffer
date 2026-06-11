// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/app_permission_matrix.dart';
import '../../../core/forms/backend_field_error_parser.dart';
import '../../../core/forms/form_error_banner.dart';
import '../../../core/forms/form_field_error_resolver.dart';
import '../../../core/forms/form_scroll_coordinator.dart';
import '../../../core/i18n/app_localizations_context.dart';
import '../../../core/network/api_error_mapper.dart' hide parseBackendFieldErrors;
import '../../company/company_portal_text.dart';
import '../../company/models/company_models.dart';
import '../state/admin_controller.dart';

class AdminCompaniesScreen extends ConsumerStatefulWidget {
  const AdminCompaniesScreen({super.key});

  @override
  ConsumerState<AdminCompaniesScreen> createState() =>
      _AdminCompaniesScreenState();
}

class _AdminCompaniesScreenState extends ConsumerState<AdminCompaniesScreen> {
  Future<_AdminCompaniesPayload>? _future;

  Map<String, String> _actionErrorMessages(BuildContext context) {
    final l10n = context.l10n;
    return {
      ..._defaultErrorMessages,
      'FORBIDDEN_ADMIN_ONLY': l10n.adminCompaniesPermissionDenied,
      'FORBIDDEN_SUPER_ADMIN_ONLY': l10n.adminCompaniesPermissionDenied,
      'COMPANY_NOT_FOUND': l10n.adminCompaniesCompanyNotFound,
      'COMPANY_BRANCH_REQUEST_NOT_FOUND':
          l10n.adminCompaniesBranchRequestNotFound,
      'COMPANY_BRANCH_REQUEST_ALREADY_REVIEWED':
          l10n.adminCompaniesBranchRequestAlreadyReviewed,
      'COMPANY_BRANCH_OWNER_PHONE_ROLE_CONFLICT':
          l10n.adminCompaniesBranchOwnerPhoneRoleConflict,
      'OWNER_ALREADY_HAS_MERCHANT': l10n.adminCompaniesOwnerAlreadyHasBranch,
      'MERCHANT_NOT_FOUND': l10n.adminCompaniesBranchNotFound,
      'PHONE_EXISTS': l10n.apiPhoneExists,
    };
  }

  static const Map<String, String> _defaultErrorMessages = {
    'FORBIDDEN_ADMIN_ONLY': 'صلاحياتك الحالية لا تسمح بإدارة الشركات.',
    'FORBIDDEN_SUPER_ADMIN_ONLY': 'صلاحياتك الحالية لا تسمح بإدارة الشركات.',
    'COMPANY_NOT_FOUND': 'الشركة المطلوبة غير موجودة.',
    'COMPANY_BRANCH_REQUEST_NOT_FOUND': 'طلب الفرع المطلوب غير موجود.',
    'COMPANY_BRANCH_REQUEST_ALREADY_REVIEWED':
        'تمت مراجعة هذا الطلب مسبقًا. حدّث الصفحة لرؤية الحالة الحالية.',
    'COMPANY_BRANCH_OWNER_PHONE_ROLE_CONFLICT':
        'رقم مالك الفرع مرتبط بحساب من نوع آخر ولا يمكن استخدامه لهذا الطلب.',
    'OWNER_ALREADY_HAS_MERCHANT': 'هذا المالك مرتبط بمتجر آخر بالفعل.',
    'MERCHANT_NOT_FOUND': 'الفرع المطلوب غير موجود.',
    'PHONE_EXISTS': 'رقم الهاتف مستخدم مسبقًا.',
  };

  @override
  void initState() {
    super.initState();
    if (_canManageCompanies()) {
      _future = _load();
    }
  }

  Future<_AdminCompaniesPayload> _load() async {
    final api = ref.read(adminApiProvider);
    final results = await Future.wait<dynamic>([
      api.companyAdminCompanies(),
      api.companyAdminPendingBranchRequests(),
      api.merchants(),
    ]);
    return _AdminCompaniesPayload(
      companies:
          (((results[0] as Map<String, dynamic>)['companies'] as List?) ??
                  const [])
              .whereType<Map>()
              .map(
                (row) => CompanySummary.fromJson(row.cast<String, dynamic>()),
              )
              .toList(),
      requests:
          (((results[1] as Map<String, dynamic>)['requests'] as List?) ??
                  const [])
              .whereType<Map>()
              .map(
                (row) =>
                    CompanyBranchRequest.fromJson(row.cast<String, dynamic>()),
              )
              .toList(),
      merchants: (results[2] as List)
          .whereType<Map>()
          .map((row) => row.cast<String, dynamic>())
          .toList(),
    );
  }

  Future<void> _refresh() async {
    if (!_canManageCompanies()) return;
    final nextFuture = _load();
    if (mounted) {
      setState(() => _future = nextFuture);
    }
    try {
      await nextFuture;
    } catch (_) {
      // FutureBuilder renders the error state.
    }
  }

  String? _text(TextEditingController controller) {
    final value = controller.text.trim();
    return value.isEmpty ? null : value;
  }

  bool _canManageCompanies() {
    final permissions = ref.read(appPermissionMatrixProvider);
    return permissions.can(AppCapability.adminCompanies);
  }

  String? _normalizeCompanyEditorField(
    String rawField, {
    required bool isEdit,
  }) {
    final normalized = rawField.trim().toLowerCase();
    switch (normalized) {
      case 'name':
        return 'name';
      case 'code':
      case 'companycode':
        return 'code';
      case 'legalname':
        return 'legalName';
      case 'brandname':
        return 'brandName';
      case 'businesstype':
        return 'businessType';
      case 'summary':
        return 'summary';
      case 'headquartersaddress':
      case 'address':
        return 'hqAddress';
      case 'primarycontactname':
        return 'primaryContact';
      case 'contactphone':
        return 'phone';
      case 'supportphone':
        return 'supportPhone';
      case 'contactemail':
      case 'email':
        return 'email';
      case 'website':
      case 'websiteurl':
        return 'website';
      case 'registrationnumber':
        return 'registrationNumber';
      case 'taxnumber':
        return 'taxNumber';
      case 'notes':
        return 'notes';
      case 'phone':
        return isEdit ? 'phone' : 'ownerPhone';
      case 'fullname':
      case 'owner.fullname':
      case 'ownerfullname':
        return 'ownerFullName';
      case 'owner.phone':
      case 'ownerphone':
        return 'ownerPhone';
      case 'pin':
      case 'owner.pin':
      case 'ownerpin':
        return 'ownerPin';
      default:
        return null;
    }
  }

  String _companyEditorFieldLabel(
    BuildContext context,
    String field,
  ) {
    final l10n = context.l10n;
    switch (field) {
      case 'name':
        return l10n.adminCompaniesCompanyNameLabel;
      case 'code':
        return l10n.adminCompaniesCompanyCodeLabel;
      case 'legalName':
        return l10n.adminCompaniesLegalNameLabel;
      case 'brandName':
        return l10n.adminCompaniesBrandNameLabel;
      case 'businessType':
        return l10n.adminCompaniesBusinessTypeLabel;
      case 'summary':
        return l10n.adminCompaniesSummaryLabel;
      case 'hqAddress':
        return l10n.adminCompaniesHeadquartersAddressLabel;
      case 'primaryContact':
        return l10n.adminCompaniesPrimaryContactLabel;
      case 'phone':
        return l10n.commonPhone;
      case 'supportPhone':
        return l10n.adminCompaniesSupportPhoneLabel;
      case 'email':
        return l10n.commonEmail;
      case 'website':
        return l10n.adminCompaniesWebsiteLabel;
      case 'registrationNumber':
        return l10n.adminCompaniesRegistrationNumberLabel;
      case 'taxNumber':
        return l10n.adminCompaniesTaxNumberLabel;
      case 'notes':
        return l10n.adminCompaniesAdminNotesLabel;
      case 'ownerFullName':
        return l10n.adminCompaniesOwnerNameLabel;
      case 'ownerPhone':
        return l10n.adminCompaniesOwnerPhoneLabel;
      case 'ownerPin':
        return l10n.adminCompaniesOwnerPinLabel;
      default:
        return field;
    }
  }

  Future<void> _showCompanyEditor({CompanySummary? company}) async {
    final l10n = context.l10n;
    final isEdit = company != null;
    final scrollCoordinator = FormScrollCoordinator();
    final name = TextEditingController(text: company?.name ?? '');
    final code = TextEditingController(text: company?.code ?? '');
    final legalName = TextEditingController(text: company?.legalName ?? '');
    final brandName = TextEditingController(text: company?.brandName ?? '');
    final businessType = TextEditingController(
      text: company?.businessType ?? '',
    );
    final summary = TextEditingController(text: company?.summary ?? '');
    final hqAddress = TextEditingController(
      text: company?.headquartersAddress ?? '',
    );
    final primaryContact = TextEditingController(
      text: company?.primaryContactName ?? '',
    );
    final phone = TextEditingController(text: company?.contactPhone ?? '');
    final supportPhone = TextEditingController(
      text: company?.supportPhone ?? '',
    );
    final email = TextEditingController(text: company?.contactEmail ?? '');
    final website = TextEditingController(text: company?.websiteUrl ?? '');
    final registrationNumber = TextEditingController(
      text: company?.registrationNumber ?? '',
    );
    final taxNumber = TextEditingController(text: company?.taxNumber ?? '');
    final notes = TextEditingController(text: company?.notes ?? '');
    final ownerFullName = TextEditingController();
    final ownerPhone = TextEditingController();
    final ownerPin = TextEditingController();
    var status = company?.status ?? 'active';
    var saving = false;
    var formError = '';
    var fieldErrors = <String, String>{};

    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) {
          void clearFieldError(String field) {
            if (!fieldErrors.containsKey(field) && formError.isEmpty) {
              return;
            }
            setModalState(() {
              fieldErrors = Map<String, String>.from(fieldErrors)
                ..remove(field);
              if (formError.isNotEmpty) {
                formError = '';
              }
            });
          }

          String? customFieldResolver(
            String field,
            String? code,
          ) {
            switch (code?.trim().toUpperCase()) {
              case 'COMPANY_CODE_EXISTS':
                return field == 'code' ? l10n.adminCompaniesCodeExists : null;
              case 'COMPANY_OWNER_PHONE_ROLE_CONFLICT':
                return field == 'ownerPhone'
                    ? l10n.adminCompaniesOwnerPhoneRoleConflict
                    : null;
              case 'COMPANY_OWNER_ACCOUNT_REQUIRED':
                return field.startsWith('owner')
                    ? l10n.adminCompaniesOwnerAccountRequired
                    : null;
              default:
                return null;
            }
          }

          Map<String, String> validateLocally() {
            final next = <String, String>{};
            final trimmedName = name.text.trim();
            final trimmedEmail = email.text.trim();
            if (trimmedName.isEmpty) {
              next['name'] = l10n.validationRequiredField(
                l10n.adminCompaniesCompanyNameLabel,
              );
            }
            if (trimmedEmail.isNotEmpty &&
                !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(trimmedEmail)) {
              next['email'] = l10n.validationInvalidEmail;
            }
            if (!isEdit) {
              if (ownerFullName.text.trim().isEmpty) {
                next['ownerFullName'] = l10n.validationRequiredField(
                  l10n.adminCompaniesOwnerNameLabel,
                );
              }
              if (ownerPhone.text.trim().isEmpty) {
                next['ownerPhone'] = l10n.validationRequiredField(
                  l10n.adminCompaniesOwnerPhoneLabel,
                );
              }
              if (ownerPin.text.trim().length < 4) {
                next['ownerPin'] = l10n.adminCompaniesValidPinRequired;
              }
            }
            return next;
          }

          Future<void> submit() async {
            if (saving) return;
            final localErrors = validateLocally();
            if (localErrors.isNotEmpty) {
              setModalState(() {
                fieldErrors = localErrors;
                formError = l10n.validationReviewRequiredFields;
              });
              await scrollCoordinator.focusFirstError(<String>[
                'name',
                'code',
                'phone',
                'email',
                'ownerFullName',
                'ownerPhone',
                'ownerPin',
              ].where(localErrors.containsKey));
              return;
            }

            setModalState(() {
              saving = true;
              formError = '';
              fieldErrors = <String, String>{};
            });

            final Map<String, dynamic> body = {
              'name': name.text.trim(),
              'code': _text(code),
              'legalName': _text(legalName),
              'brandName': _text(brandName),
              'businessType': _text(businessType),
              'summary': _text(summary),
              'headquartersAddress': _text(hqAddress),
              'primaryContactName': _text(primaryContact),
              'contactPhone': _text(phone),
              'supportPhone': _text(supportPhone),
              'contactEmail': _text(email),
              'websiteUrl': _text(website),
              'registrationNumber': _text(registrationNumber),
              'taxNumber': _text(taxNumber),
              'notes': _text(notes),
              'status': status,
            }..removeWhere((key, value) => value == null);

            try {
              if (isEdit) {
                await ref.read(adminApiProvider).companyAdminUpdateCompany(
                  companyId: company.id,
                  body: body,
                );
              } else {
                body['owner'] = {
                  'fullName': ownerFullName.text.trim(),
                  'phone': ownerPhone.text.trim(),
                  'pin': ownerPin.text.trim(),
                  'role': 'company_owner',
                  'workTitle': l10n.adminCompaniesOwnerWorkTitle,
                  'workCompany': name.text.trim(),
                };
                await ref.read(adminApiProvider).companyAdminCreateCompany(body);
              }
            } catch (error) {
              if (!dialogContext.mounted) return;
              final parsed = parseBackendFieldErrors(error);
              final fallback = mapAnyError(
                error,
                fallback: isEdit
                    ? l10n.adminCompaniesUpdateFailed
                    : l10n.adminCompaniesCreateFailed,
                customMessages: {
                  ..._actionErrorMessages(context),
                  'COMPANY_CODE_EXISTS': l10n.adminCompaniesCodeExists,
                  'COMPANY_OWNER_PHONE_ROLE_CONFLICT':
                      l10n.adminCompaniesOwnerPhoneRoleConflict,
                  'COMPANY_OWNER_ACCOUNT_REQUIRED':
                      l10n.adminCompaniesOwnerAccountRequired,
                  'PHONE_EXISTS': l10n.apiPhoneExists,
                },
              );
              final nextErrors = <String, String>{};
              for (final entry in parsed.fieldCodes.entries) {
                final field = _normalizeCompanyEditorField(
                  entry.key,
                  isEdit: isEdit,
                );
                if (field == null) continue;
                nextErrors[field] = resolveFormFieldError(
                  l10n: l10n,
                  field: field,
                  code: entry.value,
                  fieldLabel: _companyEditorFieldLabel(context, field),
                  customResolver: (_, field, code) =>
                      customFieldResolver(field, code),
                );
              }
              setModalState(() {
                saving = false;
                fieldErrors = nextErrors;
                formError = parsed.hasFieldErrors
                    ? resolveFormLevelError(
                        l10n,
                        code: parsed.formCode ?? parsed.messageCode,
                        fallback: l10n.validationReviewRequiredFields,
                      )
                    : fallback;
              });
              if (nextErrors.isNotEmpty) {
                await scrollCoordinator.focusFirstError(<String>[
                  'name',
                  'code',
                  'phone',
                  'email',
                  'ownerFullName',
                  'ownerPhone',
                  'ownerPin',
                ].where(nextErrors.containsKey));
              }
              return;
            }

            if (!mounted) return;
            Navigator.of(dialogContext).pop(true);
          }

          InputDecoration decorationFor(
            String field, {
            required String label,
            String? helperText,
          }) {
            return InputDecoration(
              labelText: label,
              helperText: helperText,
              errorText: fieldErrors[field],
            );
          }

          return AlertDialog(
            title: Text(
              isEdit
                  ? l10n.adminCompaniesEditCompanyTitle
                  : l10n.adminCompaniesCreateCompanyTitle,
            ),
            content: SizedBox(
              width: 720,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    FormErrorBanner(
                      message: formError.isEmpty ? null : formError,
                    ),
                    scrollCoordinator.anchor(
                      'name',
                      TextFormField(
                        controller: name,
                        focusNode: scrollCoordinator.focusNodeFor('name'),
                        decoration: decorationFor(
                          'name',
                          label: l10n.adminCompaniesCompanyNameLabel,
                        ),
                        onChanged: (_) => clearFieldError('name'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'code',
                      TextFormField(
                        controller: code,
                        focusNode: scrollCoordinator.focusNodeFor('code'),
                        textDirection: TextDirection.ltr,
                        decoration: decorationFor(
                          'code',
                          label: l10n.adminCompaniesCompanyCodeLabel,
                          helperText: l10n.adminCompaniesCompanyCodeHelper,
                        ),
                        onChanged: (_) => clearFieldError('code'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: status,
                      decoration: InputDecoration(labelText: l10n.commonStatus),
                      items: {status, 'active', 'inactive', 'suspended'}
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(companyStatusLabel(context, item)),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => status = value ?? status,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: legalName,
                      decoration: decorationFor(
                        'legalName',
                        label: l10n.adminCompaniesLegalNameLabel,
                      ),
                      onChanged: (_) => clearFieldError('legalName'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: brandName,
                      decoration: decorationFor(
                        'brandName',
                        label: l10n.adminCompaniesBrandNameLabel,
                      ),
                      onChanged: (_) => clearFieldError('brandName'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: businessType,
                      decoration: decorationFor(
                        'businessType',
                        label: l10n.adminCompaniesBusinessTypeLabel,
                      ),
                      onChanged: (_) => clearFieldError('businessType'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: summary,
                      maxLines: 3,
                      decoration: decorationFor(
                        'summary',
                        label: l10n.adminCompaniesSummaryLabel,
                      ),
                      onChanged: (_) => clearFieldError('summary'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: primaryContact,
                      decoration: decorationFor(
                        'primaryContact',
                        label: l10n.adminCompaniesPrimaryContactLabel,
                      ),
                      onChanged: (_) => clearFieldError('primaryContact'),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'phone',
                      TextFormField(
                        controller: phone,
                        focusNode: scrollCoordinator.focusNodeFor('phone'),
                        keyboardType: TextInputType.phone,
                        textDirection: TextDirection.ltr,
                        decoration: decorationFor(
                          'phone',
                          label: l10n.commonPhone,
                        ),
                        onChanged: (_) => clearFieldError('phone'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: supportPhone,
                      keyboardType: TextInputType.phone,
                      textDirection: TextDirection.ltr,
                      decoration: decorationFor(
                        'supportPhone',
                        label: l10n.adminCompaniesSupportPhoneLabel,
                      ),
                      onChanged: (_) => clearFieldError('supportPhone'),
                    ),
                    const SizedBox(height: 12),
                    scrollCoordinator.anchor(
                      'email',
                      TextFormField(
                        controller: email,
                        focusNode: scrollCoordinator.focusNodeFor('email'),
                        keyboardType: TextInputType.emailAddress,
                        textDirection: TextDirection.ltr,
                        decoration: decorationFor(
                          'email',
                          label: l10n.commonEmail,
                        ),
                        onChanged: (_) => clearFieldError('email'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: website,
                      keyboardType: TextInputType.url,
                      textDirection: TextDirection.ltr,
                      decoration: decorationFor(
                        'website',
                        label: l10n.adminCompaniesWebsiteLabel,
                      ),
                      onChanged: (_) => clearFieldError('website'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: hqAddress,
                      maxLines: 2,
                      decoration: decorationFor(
                        'hqAddress',
                        label: l10n.adminCompaniesHeadquartersAddressLabel,
                      ),
                      onChanged: (_) => clearFieldError('hqAddress'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: registrationNumber,
                      decoration: decorationFor(
                        'registrationNumber',
                        label: l10n.adminCompaniesRegistrationNumberLabel,
                      ),
                      onChanged: (_) => clearFieldError('registrationNumber'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: taxNumber,
                      decoration: decorationFor(
                        'taxNumber',
                        label: l10n.adminCompaniesTaxNumberLabel,
                      ),
                      onChanged: (_) => clearFieldError('taxNumber'),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: notes,
                      maxLines: 3,
                      decoration: decorationFor(
                        'notes',
                        label: l10n.adminCompaniesAdminNotesLabel,
                      ),
                      onChanged: (_) => clearFieldError('notes'),
                    ),
                    if (!isEdit) ...[
                      const SizedBox(height: 16),
                      Align(
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          l10n.adminCompaniesPrimaryOwnerSectionTitle,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                      const SizedBox(height: 12),
                      scrollCoordinator.anchor(
                        'ownerFullName',
                        TextFormField(
                          controller: ownerFullName,
                          focusNode: scrollCoordinator.focusNodeFor(
                            'ownerFullName',
                          ),
                          decoration: decorationFor(
                            'ownerFullName',
                            label: l10n.adminCompaniesOwnerNameLabel,
                          ),
                          onChanged: (_) => clearFieldError('ownerFullName'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      scrollCoordinator.anchor(
                        'ownerPhone',
                        TextFormField(
                          controller: ownerPhone,
                          focusNode: scrollCoordinator.focusNodeFor(
                            'ownerPhone',
                          ),
                          keyboardType: TextInputType.phone,
                          textDirection: TextDirection.ltr,
                          decoration: decorationFor(
                            'ownerPhone',
                            label: l10n.adminCompaniesOwnerPhoneLabel,
                          ),
                          onChanged: (_) => clearFieldError('ownerPhone'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      scrollCoordinator.anchor(
                        'ownerPin',
                        TextFormField(
                          controller: ownerPin,
                          focusNode: scrollCoordinator.focusNodeFor('ownerPin'),
                          obscureText: true,
                          decoration: decorationFor(
                            'ownerPin',
                            label: l10n.adminCompaniesOwnerPinLabel,
                          ),
                          onChanged: (_) => clearFieldError('ownerPin'),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving
                    ? null
                    : () => Navigator.of(dialogContext).pop(false),
                child: Text(l10n.commonCancel),
              ),
              FilledButton(
                onPressed: saving ? null : submit,
                child: Text(
                  isEdit
                      ? l10n.adminCompaniesSaveChanges
                      : l10n.adminCompaniesCreateAction,
                ),
              ),
            ],
          );
        },
      ),
    );

    for (final controller in [
      name,
      code,
      legalName,
      brandName,
      businessType,
      summary,
      hqAddress,
      primaryContact,
      phone,
      supportPhone,
      email,
      website,
      registrationNumber,
      taxNumber,
      notes,
      ownerFullName,
      ownerPhone,
      ownerPin,
    ]) {
      controller.dispose();
    }
    scrollCoordinator.dispose();
    if (saved == true) await _refresh();
  }

  Future<void> _showDeleteCompany(CompanySummary company) async {
    final l10n = context.l10n;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.adminCompaniesDeleteTitle),
        content: Text(l10n.adminCompaniesDeleteDescription(company.name)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.adminCompaniesDeleteConfirm),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref
          .read(adminApiProvider)
          .companyAdminDeleteCompany(companyId: company.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.adminCompaniesDeleted(company.name))),
      );
      await _refresh();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mapAnyError(
              error,
              fallback: l10n.adminCompaniesDeleteFailed,
              customMessages: {
                'COMPANY_NOT_FOUND': l10n.adminCompaniesCompanyNotFound,
              },
            ),
          ),
        ),
      );
    }
  }

  Future<void> _showLinkBranch(
    CompanySummary company,
    List<Map<String, dynamic>> merchants,
  ) async {
    final l10n = context.l10n;
    int? merchantId;
    var saving = false;
    var selectionError = '';
    var formError = '';
    final linked = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: Text(l10n.adminCompaniesLinkBranchTitle(company.name)),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FormErrorBanner(
                  message: formError.isEmpty ? null : formError,
                ),
                DropdownButtonFormField<int>(
                  initialValue: merchantId,
                  decoration: InputDecoration(
                    labelText: l10n.adminCompaniesBranchSelectorLabel,
                    errorText: selectionError.isEmpty ? null : selectionError,
                  ),
                  items: merchants
                      .map(
                        (merchant) => DropdownMenuItem<int>(
                          value: (merchant['id'] as num?)?.toInt() ?? 0,
                          child: Text(
                            '${merchant['name'] ?? l10n.adminCompaniesDefaultMerchantName}',
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    setModalState(() {
                      merchantId = value;
                      selectionError = '';
                      formError = '';
                    });
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () async {
                if (saving) return;
                if (merchantId == null || merchantId! <= 0) {
                  setModalState(() {
                    selectionError = l10n.validationSelectOption;
                    formError = l10n.validationReviewRequiredFields;
                  });
                  return;
                }
                setModalState(() {
                  saving = true;
                  selectionError = '';
                  formError = '';
                });
                try {
                  await ref.read(adminApiProvider).companyAdminLinkBranch(
                    companyId: company.id,
                    merchantId: merchantId!,
                  );
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setModalState(() {
                    saving = false;
                    formError = mapAnyError(
                      error,
                      fallback: l10n.adminCompaniesLinkBranchFailed,
                      customMessages: _actionErrorMessages(context),
                    );
                  });
                }
              },
              child: Text(l10n.adminCompaniesLinkBranchAction),
            ),
          ],
        ),
      ),
    );
    if (linked == true) await _refresh();
  }

  Future<void> _reviewRequest(
    CompanyBranchRequest request,
    bool approve,
  ) async {
    final l10n = context.l10n;
    final noteController = TextEditingController();
    var saving = false;
    var formError = '';
    final done = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setModalState) => AlertDialog(
          title: Text(
            approve
                ? l10n.adminCompaniesApproveBranchRequestTitle
                : l10n.adminCompaniesRejectBranchRequestTitle,
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FormErrorBanner(message: formError.isEmpty ? null : formError),
              TextField(
                controller: noteController,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: l10n.adminCompaniesReviewNoteLabel,
                ),
                onChanged: (_) {
                  if (formError.isEmpty) return;
                  setModalState(() => formError = '');
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving
                  ? null
                  : () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.commonCancel),
            ),
            FilledButton(
              onPressed: () async {
                if (saving) return;
                setModalState(() => formError = '');
                saving = true;
                try {
                  if (approve) {
                    await ref
                        .read(adminApiProvider)
                        .companyAdminApproveBranchRequest(
                          requestId: request.id,
                          body: {
                            if (noteController.text.trim().isNotEmpty)
                              'reviewNote': noteController.text.trim(),
                          },
                        );
                  } else {
                    await ref
                        .read(adminApiProvider)
                        .companyAdminRejectBranchRequest(
                          requestId: request.id,
                          body: {'reviewNote': noteController.text.trim()},
                        );
                  }
                  if (!mounted) return;
                  Navigator.of(dialogContext).pop(true);
                } catch (error) {
                  if (!dialogContext.mounted) return;
                  setModalState(() {
                    saving = false;
                    formError = mapAnyError(
                      error,
                      fallback: approve
                          ? l10n.adminCompaniesApproveBranchRequestFailed
                          : l10n.adminCompaniesRejectBranchRequestFailed,
                      customMessages: _actionErrorMessages(context),
                    );
                  });
                }
              },
              child: Text(approve ? l10n.commonApprove : l10n.commonReject),
            ),
          ],
        ),
      ),
    );
    noteController.dispose();
    if (done == true) await _refresh();
  }

  Widget _metricPill(String label, int? value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      ),
      child: Text('$label: ${value ?? 0}'),
    );
  }

  Widget _companyInfoRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18),
        const SizedBox(width: 8),
        Expanded(child: Text('$label: $value')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final canManageCompanies = ref
        .watch(appPermissionMatrixProvider)
        .can(AppCapability.adminCompanies);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.adminCompaniesScreenTitle),
        actions: [
          IconButton(
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: l10n.commonRefresh,
          ),
        ],
      ),
      body: !canManageCompanies
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline_rounded, size: 32),
                    const SizedBox(height: 12),
                    Text(
                      l10n.adminCompaniesPermissionDenied,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          : FutureBuilder<_AdminCompaniesPayload>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.error_outline_rounded, size: 32),
                          const SizedBox(height: 12),
                          Text(
                            mapAnyError(
                              snapshot.error!,
                              fallback: l10n.adminCompaniesLoadFailed,
                              customMessages: _actionErrorMessages(context),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          FilledButton(
                            onPressed: _refresh,
                            child: Text(l10n.commonRetry),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                final payload = snapshot.data;
                if (payload == null) {
                  return Center(child: Text(l10n.adminCompaniesNoData));
                }
                return RefreshIndicator(
                  onRefresh: _refresh,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.adminCompaniesPortalTitle,
                                      style: const TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                    const SizedBox(height: 8),
                                    Text(l10n.adminCompaniesPortalSubtitle),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 12),
                              FilledButton.icon(
                                onPressed: () => _showCompanyEditor(),
                                icon: const Icon(Icons.add_business_rounded),
                                label: Text(l10n.adminCompaniesCreateAction),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (payload.companies.isEmpty)
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: Text(l10n.adminCompaniesEmpty),
                          ),
                        )
                      else
                        ...payload.companies.map(
                          (company) => Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              company.name,
                                              style: const TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                            if ((company.brandName ?? '')
                                                .isNotEmpty) ...[
                                              const SizedBox(height: 4),
                                              Text(company.brandName!),
                                            ],
                                          ],
                                        ),
                                      ),
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 8,
                                        children: [
                                          Chip(
                                            label: Directionality(
                                              textDirection: TextDirection.ltr,
                                              child: Text(company.code),
                                            ),
                                          ),
                                          Chip(
                                            label: Text(
                                              companyStatusLabel(
                                                context,
                                                company.status,
                                              ),
                                            ),
                                          ),
                                          if ((company.businessType ?? '')
                                              .isNotEmpty)
                                            Chip(
                                              label: Text(
                                                company.businessType!,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      _metricPill(
                                        l10n.adminCompaniesBranchesMetric,
                                        company.branchesCount,
                                      ),
                                      _metricPill(
                                        l10n.adminCompaniesUsersMetric,
                                        company.usersCount,
                                      ),
                                      _metricPill(
                                        l10n.adminCompaniesActiveUsersMetric,
                                        company.activeUsersCount,
                                      ),
                                    ],
                                  ),
                                  if ((company.summary ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Text(company.summary!),
                                  ],
                                  const SizedBox(height: 12),
                                  Wrap(
                                    spacing: 16,
                                    runSpacing: 12,
                                    children: [
                                      if ((company.legalName ?? '').isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.gavel_rounded,
                                            l10n.adminCompaniesLegalNameLabel,
                                            company.legalName!,
                                          ),
                                        ),
                                      if ((company.primaryContactName ?? '')
                                          .isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.person_outline_rounded,
                                            l10n.adminCompaniesPrimaryContactShort,
                                            company.primaryContactName!,
                                          ),
                                        ),
                                      if ((company.contactPhone ?? '')
                                          .isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.phone_rounded,
                                            l10n.commonPhone,
                                            company.contactPhone!,
                                          ),
                                        ),
                                      if ((company.supportPhone ?? '')
                                          .isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.support_agent_rounded,
                                            l10n.adminCompaniesSupportPhoneLabel,
                                            company.supportPhone!,
                                          ),
                                        ),
                                      if ((company.contactEmail ?? '')
                                          .isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.alternate_email_rounded,
                                            l10n.commonEmail,
                                            company.contactEmail!,
                                          ),
                                        ),
                                      if ((company.websiteUrl ?? '').isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.language_rounded,
                                            l10n.adminCompaniesWebsiteShort,
                                            company.websiteUrl!,
                                          ),
                                        ),
                                      if ((company.headquartersAddress ?? '')
                                          .isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.location_on_outlined,
                                            l10n.adminCompaniesHeadquartersShort,
                                            company.headquartersAddress!,
                                          ),
                                        ),
                                      if ((company.registrationNumber ?? '')
                                          .isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.badge_outlined,
                                            l10n.adminCompaniesRegistrationNumberLabel,
                                            company.registrationNumber!,
                                          ),
                                        ),
                                      if ((company.taxNumber ?? '').isNotEmpty)
                                        SizedBox(
                                          width: 320,
                                          child: _companyInfoRow(
                                            Icons.receipt_long_outlined,
                                            l10n.adminCompaniesTaxNumberLabel,
                                            company.taxNumber!,
                                          ),
                                        ),
                                    ],
                                  ),
                                  if ((company.notes ?? '').isNotEmpty) ...[
                                    const SizedBox(height: 10),
                                    _companyInfoRow(
                                      Icons.notes_rounded,
                                      l10n.adminCompaniesAdminNotesShort,
                                      company.notes!,
                                    ),
                                  ],
                                  const SizedBox(height: 14),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 8,
                                    children: [
                                      FilledButton.icon(
                                        onPressed: () => _showCompanyEditor(
                                          company: company,
                                        ),
                                        icon: const Icon(Icons.edit_rounded),
                                        label: Text(
                                          l10n.adminCompaniesEditInfoAction,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () => _showLinkBranch(
                                          company,
                                          payload.merchants,
                                        ),
                                        icon: const Icon(Icons.link_rounded),
                                        label: Text(
                                          l10n.adminCompaniesLinkBranchAction,
                                        ),
                                      ),
                                      OutlinedButton.icon(
                                        onPressed: () =>
                                            _showDeleteCompany(company),
                                        icon: const Icon(
                                          Icons.delete_outline_rounded,
                                        ),
                                        label: Text(
                                          l10n.adminCompaniesDeleteAction,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      const SizedBox(height: 16),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l10n.adminCompaniesPendingBranchRequestsTitle,
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 12),
                              if (payload.requests.isEmpty)
                                Text(
                                  l10n.adminCompaniesPendingBranchRequestsEmpty,
                                )
                              else
                                ...payload.requests.map(
                                  (request) => Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(14),
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(16),
                                      border: Border.all(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.outlineVariant,
                                      ),
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                request.requestedName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w800,
                                                ),
                                              ),
                                            ),
                                            Chip(
                                              label: Text(
                                                companyStatusLabel(
                                                  context,
                                                  request.status,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          l10n.adminCompaniesBranchRequestLocationLine(
                                            companyBranchTypeLabel(
                                              context,
                                              request.requestedType,
                                            ),
                                            request.branchLocationLabel ??
                                                l10n.adminCompaniesNoLocation,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          l10n.adminCompaniesSuggestedOwnerLine(
                                            request.ownerFullName ??
                                                l10n.commonNotSet,
                                            request.ownerPhone ??
                                                l10n.adminCompaniesNoPhone,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 8,
                                          children: [
                                            FilledButton.icon(
                                              onPressed: () =>
                                                  _reviewRequest(request, true),
                                              icon: const Icon(
                                                Icons.check_rounded,
                                              ),
                                              label: Text(l10n.commonApprove),
                                            ),
                                            OutlinedButton.icon(
                                              onPressed: () => _reviewRequest(
                                                request,
                                                false,
                                              ),
                                              icon: const Icon(
                                                Icons.close_rounded,
                                              ),
                                              label: Text(l10n.commonReject),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _AdminCompaniesPayload {
  final List<CompanySummary> companies;
  final List<CompanyBranchRequest> requests;
  final List<Map<String, dynamic>> merchants;

  const _AdminCompaniesPayload({
    required this.companies,
    required this.requests,
    required this.merchants,
  });
}
